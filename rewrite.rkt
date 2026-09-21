#lang racket/base

;; ============================================================
;; GLSL 重写层（Layer 1）：(glsl ...) 宏
;;
;; 设计：重写器是"纯数据 → 纯数据"的函数。
;;   surface datum（(vec2 1.0 2.0)、(set! x v)、(in vec2 aPos)...）
;;     ↓ rw-expr / rw-stmt / rw-top（普通 Racket list 操作）
;;   core datum（(glsl-ctor "vec2" 1.0 2.0)、...）
;;
;; (glsl ...) 宏只做三步：
;;   syntax->datum → rw-top → datum->syntax（用宏定义侧上下文，保证 glsl-* 可解析）
;;
;; ★ glsl-unquote：在 (glsl ...) 内原样插入 Racket 代码 / 宏。
;;   (glsl-unquote e) 会在重写前被“摘下”，原位放一个标记；e 保留“使用侧语法”
;;   原样求值（须返回字符串或 glsl-program），拼接进最终 GLSL。
;;   顶层 / 语句 / 表达式位置都支持。
;; ============================================================

(require (for-syntax racket/base
                     racket/string
                     racket/format
                     racket/set
                     racket/list
                     racket/syntax
                     "core.rkt"
                     "glsl-program.rkt")
         "core.rkt"
         "pretty.rkt"
         "glsl-program.rkt")

(provide glsl glsl-unquote
         (all-from-out "core.rkt")
         (all-from-out "pretty.rkt")
         (all-from-out "glsl-program.rkt"))

(begin-for-syntax

  ;; ---------- glsl-unquote 拼接标记 ----------
  ;; 表面 (glsl-unquote e) 在重写前被"摘下"，原位放一个 splice-marker：
  ;; 重写各层只把它当普通原子透传，最后由 tree->syntax 换成使用侧的 Racket 表达式。
  (struct splice-marker (index) #:transparent)

  ;; ---------- 类型名集合 ----------
  (define builtin-types
    (apply set
           (append
            '(float int uint bool double void atomic_uint)
            (for*/list ([p '("" "i" "u" "b" "d")] [n '(2 3 4)])
              (string->symbol (format "~avec~a" p n)))
            (for*/list ([p '("" "d")] [n '(2 3 4)])
              (string->symbol (format "~amat~a" p n)))
            (for*/list ([p '("" "d")] [c '(2 3 4)] [r '(2 3 4)])
              (string->symbol (format "~amat~ax~a" p c r)))
            '(sampler1D sampler2D sampler3D samplerCube
              sampler2DArray samplerCubeArray sampler2DMS samplerBuffer
              sampler1DShadow sampler2DShadow samplerCubeShadow
              sampler2DArrayShadow samplerCubeArrayShadow
              isampler1D isampler2D isampler3D isamplerCube isampler2DArray
              isamplerCubeArray isampler2DMS isamplerBuffer
              usampler1D usampler2D usampler3D usamplerCube usampler2DArray
              usamplerCubeArray usampler2DMS usamplerBuffer
              image1D image2D image3D imageCube image2DArray imageBuffer
              iimage1D iimage2D iimage3D iimageCube iimage2DArray iimageBuffer
              uimage1D uimage2D uimage3D uimageCube uimage2DArray uimageBuffer))))

  ;; 当前类型集合（含本块收集的 struct 名）
  (define type-names (make-parameter builtin-types))

  ;; ---------- 运算符表 ----------
  (define bin-ops
    '((+ . "+") (- . "-") (* . "*") (/ . "/") (% . "%")
      (<< . "<<") (>> . ">>") (< . "<") (<= . "<=") (> . ">") (>= . ">=")
      (= . "==") (!= . "!=")
      (and . "&&") (or . "||") (xor . "^^")
      (bit-and . "&") (bit-or . "|") (bit-xor . "^")))

  (define unary-ops
    '((not . "!") (! . "!") (bit-not . "~")))

  (define assign-ops
    '((+= . "+") (-= . "-") (*= . "*") (/= . "/") (%= . "%")
      (<<= . "<<") (>>= . ">>")
      (bit-and= . "&") (bit-or= . "|") (bit-xor= . "^")))

  ;; swizzle 名：全由 x y z w r g b a s t p q 组成，长度 1-4
  (define (swizzle-name? sym)
    (define s (symbol->string sym))
    (and (> (string-length s) 0)
         (<= (string-length s) 4)
         (for/and ([ch (in-list (string->list s))])
           (member ch '(#\x #\y #\z #\w #\r #\g #\b #\a #\s #\t #\p #\q)))))

  ;; ---------- 类型位：内建类型符号 / (array 内层 [大小]) / (block 名 字段...) ----------
  ;; 数组大小缺省 → []（未定长：几何/细分着色器的 in/out、函数参数等）
  (define (array-type? t)
    (and (pair? t) (eq? (car t) 'array) (>= (length t) 2)))

  ;; 接口块：(block 名 (字段类型 字段名) ...) —— UBO/SSBO/in-out 块的"类型位"
  (define (block-type? t)
    (and (pair? t) (eq? (car t) 'block) (>= (length t) 2) (symbol? (cadr t))))

  (define (glsl-type? t)
    (or (and (symbol? t) (set-member? (type-names) t))
        (array-type? t)
        (block-type? t)))

  ;; 类型 → GLSL 文本：float → "float"；(array vec3 4) → "vec3[4]"；
  ;; (block Camera (mat4 view)) → "Camera { mat4 view; }"
  (define (rw-type t)
    (cond
      [(symbol? t) (symbol->string t)]
      [(array-type? t)
       (define sz (if (null? (cddr t)) "[]" (format "[~a]" (caddr t))))
       (string-append (rw-type (cadr t)) sz)]
      [(block-type? t)
       (format "~a { ~a }"
               (symbol->string (cadr t))
               (string-join (map field->str (cddr t)) " "))]
      [else (error 'glsl "bad type: ~s" t)]))

  ;; 声明 vs 构造器：layout/限定符开头 → 声明；类型开头 → 第二元是符号才是声明
  ;; （否则是构造器表达式，如 ((array float 4) 1.0 2.0 3.0 4.0)）
  (define (declaration? s)
    (and (pair? s)
         (let ([h (car s)] [a (cdr s)])
           (cond
             [(eq? h 'layout) #t]
             [(memq h qual-keywords) #t]
             [(glsl-type? h) (and (pair? a) (symbol? (car a)))]
             [else #f]))))

  ;; ---------- 表达式 ----------
  (define (rw-expr e)
    (cond
      [(splice-marker? e) e]            ; ★ glsl-unquote：原样透传，运行期求值
      [(number? e)
       (when (and (exact? e) (rational? e) (not (integer? e)))
         (error 'glsl "GLSL 没有有理数字面量：~s。请写小数（如 0.5）或用 (/ 1.0 2.0)" e))
       e]
      [(boolean? e) (if e "true" "false")]
      [(symbol? e) (symbol->string e)]
      [(pair? e)
       (define head (car e))
       (define args (cdr e))
       (cond
         [(eq? head 'if)
          (list 'glsl-ternary (rw-expr (car args)) (rw-expr (cadr args)) (rw-expr (caddr args)))]
         [(and (memq head '(+ -)) (= (length args) 1))
          (list 'glsl-unary (symbol->string head) (rw-expr (car args)))]
         [(assq head unary-ops)
          (list 'glsl-unary (cdr (assq head unary-ops)) (rw-expr (car args)))]
         [(assq head bin-ops)
          (list* 'glsl-bin (cdr (assq head bin-ops)) (map rw-expr args))]
         [(eq? head 'set!)
          (list 'glsl-assign (rw-lvalue (car args)) (rw-expr (cadr args)))]
         [(assq head assign-ops)
          (list 'glsl-cassign (cdr (assq head assign-ops))
                (rw-lvalue (car args)) (rw-expr (cadr args)))]
         [(eq? head '++) (list 'glsl-inc (rw-lvalue (car args)))]
         [(eq? head '--) (list 'glsl-dec (rw-lvalue (car args)))]
         [(eq? head 'raw) (list 'glsl-raw (car args))]  ; ★在 swizzle 之前：raw 由 r/a/w 组成，会被误判成 swizzle
         [(and (symbol? head) (swizzle-name? head) (pair? args))
          (list 'glsl-swizzle (symbol->string head) (rw-expr (car args)))]
         [(and (symbol? head) (string-prefix? (symbol->string head) "."))
          (list 'glsl-field (substring (symbol->string head) 1) (rw-expr (car args)))]
         [(eq? head 'aref)
          (list 'glsl-aref (rw-expr (car args)) (rw-expr (cadr args)))]
         [(glsl-type? head)
          (list* 'glsl-ctor (rw-type head) (map rw-expr args))]
         [else
          (list* 'glsl-call (symbol->string head) (map rw-expr args))])]
      [else (error 'glsl "bad expression: ~s" e)]))

  (define (rw-lvalue e)
    (if (symbol? e) (symbol->string e) (rw-expr e)))

  ;; ---------- 语句 ----------
  (define (rw-body stmts)
    (cons 'glsl-block (map rw-stmt stmts)))

  (define (rw-cond clauses)
    (let go ([cs clauses])
      (cond
        [(null? cs) #f]
        [else
         (define cl (car cs))
         (if (eq? (car cl) 'else)
             (rw-body (cdr cl))
             (list 'glsl-if (rw-expr (car cl)) (rw-body (cdr cl)) (go (cdr cs))))])))

  (define (rw-switch args)
    (define test (rw-expr (car args)))
    (define cases '())
    (define default #f)
    (for ([cl (cdr args)])
      (cond
        [(eq? (car cl) 'case)
         (define lab (cadr cl))
         (define label (if (number? lab) lab (symbol->string lab)))
         (set! cases (cons (list 'list label (rw-body (cddr cl))) cases))]
        [(eq? (car cl) 'default)
         (set! default (rw-body (cdr cl)))]))
    (define cases-expr (cons 'list (reverse cases)))
    (if default
        (list 'glsl-switch test cases-expr default)
        (list 'glsl-switch test cases-expr)))

  (define (rw-stmt s)
    (cond
      [(splice-marker? s) s]            ; ★ glsl-unquote：整条语句
      [(pair? s)
       (define head (car s))
       (define args (cdr s))
       (cond
         [(eq? head 'begin) (cons 'glsl-block (map rw-stmt args))]
         [(eq? head 'when)
          (list 'glsl-if (rw-expr (car args)) (rw-body (cdr args)))]
         [(eq? head 'unless)
          (list 'glsl-if (list 'glsl-unary "!" (rw-expr (car args))) (rw-body (cdr args)))]
         [(eq? head 'if)
          (error 'glsl "if 是表达式（三元 ?:）；语句位置的分支请用 when / unless / cond：~s" s)]
         [(eq? head 'cond) (rw-cond args)]
         [(eq? head 'for)
          (list 'glsl-for (rw-decl (car args))
                (rw-expr (cadr args)) (rw-expr (caddr args))
                (rw-body (cdddr args)))]
         [(eq? head 'while)
          (list 'glsl-while (rw-expr (car args)) (rw-body (cdr args)))]
         [(eq? head 'do-while)
          (list 'glsl-do-while (rw-expr (car args)) (rw-body (cdr args)))]
         [(eq? head 'break) '(glsl-break)]
         [(eq? head 'continue) '(glsl-continue)]
         [(eq? head 'discard) '(glsl-discard)]
         [(eq? head 'raw) (list 'glsl-raw (car args))]
         [(eq? head 'switch) (rw-switch args)]
         [(eq? head 'return)
          (if (null? args) '(glsl-return) (list 'glsl-return (rw-expr (car args))))]
         [(rw-directive s) => (lambda (d) d)]  ; ★ 预处理指令（ifdef/ifndef/else/endif/...）
         [(declaration? s)
          (rw-decl s)]
         [else (list 'glsl-stmt (rw-expr s))])]
      [else (error 'glsl "bad statement: ~s" s)]))

  ;; ---------- 声明 ----------
  ;; 通用声明：(QUAL* TYPE name [init])，QUAL* 可为空或任意限定符（in/out/uniform/const/flat/...）
  (define (rw-decl s)
    (if (eq? (car s) 'layout)
        (rw-layout (cdr s))
        (let ()
          (define-values (quals after) (collect-quals s))
          (unless (and (pair? after) (pair? (cdr after)))
            (error 'glsl "bad declaration：缺少类型或变量名 ~s" s))
          ;; 声明只能是一个变量：(类型 名字 [初值])；多变量/坏形状给清晰报错
          (unless (and (symbol? (cadr after)) (<= (length after) 3))
            (error 'glsl "bad declaration：~s（应为 (类型 名字 [初值]) 单变量）" s))
          (define ty (rw-type (car after)))
          (define nm (symbol->string (cadr after)))
          (if (null? (cddr after))
              (list 'glsl-decl (cons 'list quals) ty nm)
              (list 'glsl-decl (cons 'list quals) ty nm (rw-expr (caddr after)))))))

  ;; 声明限定符 / layout 项结束标志：遇到这些进入"类型区"
  (define qual-keywords
    '(in out uniform const buffer flat smooth noperspective centroid sample patch
      invariant precise shared readonly writeonly restrict coherent volatile))

  ;; layout item → 运行时值：裸项 (std140) → "std140"；(offset 0) → ("offset" 0)
  (define (layout-item->val it)
    (cond
      [(and (pair? it) (null? (cdr it))) (symbol->string (car it))]
      [(pair? it) (list (symbol->string (car it)) (cadr it))]
      [else (symbol->string it)]))

  ;; 同上，但产出"代码"（quote 成数据），供 rw-layout 嵌入生成表达式
  (define (rw-layout-item it)
    (list 'quote (layout-item->val it)))

  ;; 收集 layout 项，直到遇到类型或限定符关键字
  (define (collect-layout-items forms)
    (let loop ([fs forms] [acc '()])
      (define d (car fs))
      (cond
        [(glsl-type? d) (values (reverse acc) fs)]          ; 类型（含 array/block）→ 结束
        [(memq d qual-keywords) (values (reverse acc) fs)]  ; 限定符 → 结束
        [(pair? d) (loop (cdr fs) (cons d acc))]            ; (location 0) 等项
        [else (loop (cdr fs) (cons d acc))])))              ; 裸项 std140 等

  ;; layout：(layout (location 0) (binding 1) in vec2 aPos)
  (define (rw-layout args)
    (define-values (items rest) (collect-layout-items args))
    (define spec (cons 'list (map rw-layout-item items)))
    (define-values (quals after) (collect-quals rest))
    (if (null? after)                          ; 独立 layout：layout(...) in;（compute/几何/early_fragment_tests）
        (list 'glsl-layout-qual spec (cons 'list quals))
        (let ()
          (define ty (rw-type (car after)))
          (define nm (symbol->string (cadr after)))
          (if (null? (cddr after))
              (list 'glsl-layout spec (cons 'list quals) ty nm)
              (list 'glsl-layout spec (cons 'list quals) ty nm (rw-expr (caddr after)))))))

  ;; 从 forms 头收集限定符符号，直到遇到类型（符号或 (array ...)）；返回 (quals rest)
  (define (collect-quals forms)
    (let loop ([fs forms] [acc '()])
      (cond
        [(null? fs) (values (map symbol->string (reverse acc)) '())]
        [(glsl-type? (car fs))
         (values (map symbol->string (reverse acc)) fs)]
        [(symbol? (car fs))
         (loop (cdr fs) (cons (car fs) acc))]
        [else (error 'glsl "bad declaration：~s 既不是限定符也不是类型" (car fs))])))

  ;; 接口块字段 → 字符串："mat4 view;" / "flat vec3 n;" / "layout(offset = 0) mat4 view;"
  (define (field->str f)
    (cond
      [(and (pair? f) (eq? (car f) 'layout))
       (define-values (items rest) (collect-layout-items (cdr f)))
       (define-values (quals after) (collect-quals rest))
       (define ty (rw-type (car after)))
       (define nm (symbol->string (cadr after)))
       (glsl-layout (map layout-item->val items) quals ty nm)]
      [else
       (define-values (quals after) (collect-quals f))
       (define ty (rw-type (car after)))
       (define nm (symbol->string (cadr after)))
       (glsl-decl quals ty nm)]))

  ;; ---------- 函数 / 结构 ----------
  (define stmt-keywords
    '(when unless cond for while do-while break continue return discard begin))

  ;; 语句位置的预处理指令头（不含 if：(if ...) 在表达式位置是三元，只在顶层才是 #if）
  (define directive-keywords
    '(define-macro undef ifdef ifndef elif else endif error pragma extension))

  ;; 是否为"表达式形态"（非控制流/声明/预处理指令）
  (define (expr-form? f)
    (and (pair? f)
         (let ([h (car f)])
           (not (or (memq h stmt-keywords)
                    (memq h directive-keywords)
                    (declaration? f))))))

  (define (rw-param p)
    (define head (car p))
    (if (memq head '(in out inout))
        (list 'glsl-param (list 'list (symbol->string head))
              (rw-type (cadr p)) (symbol->string (caddr p)))
        (list 'glsl-param (list 'list) (rw-type (car p)) (symbol->string (cadr p)))))

  (define (rw-fn args)
    (define sig (car args))
    (define fname (symbol->string (car sig)))
    (define params (map rw-param (cdr sig)))
    (define ret (rw-type (cadr args)))
    (define body-forms (cddr args))
    ;; 非 void 且最后一个 body 是表达式 → 作为 return
    (define body
      (if (and (not (null? body-forms))
               (not (equal? ret "void"))
               (expr-form? (last body-forms)))
          (append (map rw-stmt (drop-right body-forms 1))
                  (list (list 'glsl-return (rw-expr (last body-forms)))))
          (map rw-stmt body-forms)))
    (list* 'glsl-fn fname ret (cons 'list params) body))

  (define (rw-field f)
    (list 'glsl-field-decl (rw-type (car f)) (symbol->string (cadr f))))

  (define (rw-struct args)
    (list* 'glsl-struct-decl (symbol->string (car args)) (map rw-field (cdr args))))

  ;; ---------- 预处理指令 ----------
  ;; 预处理指令是语法无关的（编译前按行处理），所以顶层 / 语句位置都允许。
  ;; 但语句位置的 (if ...) 仍保持“三元表达式错误”语义（rw-stmt 里更早的分支拦截），
  ;; 因此 #if/#elif 只在顶层可用。

  ;; 指令 token：符号→字符串、字符串/数字原样（#if 0 / #if 1 / #if FOO）
  (define (rw-macro-token x)
    (cond
      [(symbol? x) (symbol->string x)]
      [(string? x) x]
      [(number? x) x]
      [else (error 'glsl "bad macro token: ~s" x)]))

  ;; 宏体：字符串 = 原样（任意 token 序列的逃生舱）；
  ;;       数字/符号/布尔/列表 = 按表面表达式重写（1→"1"、baz→"baz"、(+ a b)→(a + b)）
  (define (rw-macro-body body)
    (if (string? body) body (rw-expr body)))

  ;; (define-macro FOO 1)              → #define FOO 1
  ;; (define-macro FOO baz)            → #define FOO baz
  ;; (define-macro (ADD a b) (+ a b))  → #define ADD(a, b) (a + b)
  ;; (define-macro (MAX a b) "a + b")  → #define MAX(a, b) a + b（字符串=原样）
  (define (rw-macro-define args)
    (unless (and (= (length args) 2))
      (error 'glsl "bad define-macro：~s（应为 (define-macro 名 体) 或 (define-macro (名 参数...) 体)）" (cons 'define-macro args)))
    (define sig (car args))
    (define body (rw-macro-body (cadr args)))
    (cond
      [(symbol? sig)
       (list 'glsl-macro-define (symbol->string sig) #f body)]
      [(and (pair? sig) (symbol? (car sig)) (andmap symbol? (cdr sig)))
       (list 'glsl-macro-define (symbol->string (car sig))
             (cons 'list (map symbol->string (cdr sig))) body)]
      [else (error 'glsl "bad define-macro 签名：~s（应为 名 或 (名 参数...)）" sig)]))

  ;; 一个预处理指令 datum → 其 core 调用 datum；不是指令则 #f
  (define (rw-directive s)
    (and (pair? s)
         (let ([head (car s)] [args (cdr s)])
           (case head
             [(define-macro) (rw-macro-define args)]
             [(undef ifdef ifndef)
              (unless (and (= (length args) 1) (symbol? (car args)))
                (error 'glsl "bad ~a：~s（应为 (~a 名字)）" head s head))
              (list (case head [(undef) 'glsl-macro-undef]
                               [(ifdef) 'glsl-macro-ifdef]
                               [else 'glsl-macro-ifndef])
                    (symbol->string (car args)))]
             [(if elif error)
              (unless (= (length args) 1)
                (error 'glsl "bad ~a：~s（应为 (~a 值)）" head s head))
              (list (case head [(if) 'glsl-macro-if]
                               [(elif) 'glsl-macro-elif]
                               [else 'glsl-macro-error])
                    (rw-macro-token (car args)))]
             [(else endif)
              (unless (null? args)
                (error 'glsl "bad ~a：~s（应为 (~a)）" head s head))
              (list (if (eq? head 'else) 'glsl-macro-else 'glsl-macro-endif))]
             [(pragma)
              (unless (and (= (length args) 1) (string? (car args)))
                (error 'glsl "bad pragma：~s（应为 (pragma \"...\")）" s))
              (list 'glsl-macro-pragma (car args))]
             [(extension)
              (unless (and (= (length args) 2) (symbol? (car args)) (symbol? (cadr args)))
                (error 'glsl "bad extension：~s（应为 (extension 名字 行为)）" s))
              (list 'glsl-macro-extension (symbol->string (car args)) (symbol->string (cadr args)))]
             [else #f]))))

  ;; ---------- 顶层 ----------
  (define (rw-top t)
    (cond
      [(splice-marker? t) t]            ; ★ glsl-unquote：整个顶层 form
      [else
       (define head (car t))
       (define args (cdr t))
       (cond
         [(eq? head 'version)
          (define n (car args))
          (if (null? (cdr args))
              (list 'glsl-version n)
              (list 'glsl-version n (symbol->string (cadr args))))]
         [(eq? head 'define) (rw-fn args)]
         [(eq? head 'struct) (rw-struct args)]
         [(eq? head 'raw) (list 'glsl-raw (car args))]
         [(rw-directive t) => (lambda (d) d)]  ; ★ 预处理指令（define-macro/ifdef/if/...）
         [(declaration? t)
          (rw-decl t)]
         [else (error 'glsl "bad top-level form: ~s" t)])])))

;; glsl-unquote：在 (glsl ...) 内被"摘下"（按符号名提取，见 glsl 宏的 walk）。
;; 提供一个同名宏，让它在 (glsl ...) 之外出现时给出清晰报错。
(define-syntax (glsl-unquote stx)
  (raise-syntax-error 'glsl-unquote "glsl-unquote 只能直接写在 (glsl ...) 内" stx))

;; ---------- 入口宏 ----------
(define-syntax (glsl stx)
  (syntax-case stx ()
    [(_ form ...)
     (let ()
       (define forms (syntax->list #'(form ...)))

       ;; ★ 摘出 (glsl-unquote e)：原位放 splice-marker，e 保留使用侧语法。
       ;;   这样重写各层看不到 Racket 表达式，最后由 tree->syntax 换回语法对象。
       (define splices '())                       ; 逆序累积的拼接表达式（syntax）
       (define (walk f)
         (define d (syntax->datum f))
         (cond
           [(and (pair? d) (eq? (car d) 'glsl-unquote))
            (define lst (syntax->list f))
            (unless (and lst (= 2 (length lst)))
              (error 'glsl "bad glsl-unquote：~s（应为 (glsl-unquote 表达式)）" d))
            (set! splices (cons (cadr lst) splices))
            (splice-marker (sub1 (length splices)))]
           [(pair? d)
            (define lst (syntax->list f))
            (if lst
                (map walk lst)
                (error 'glsl "glsl-unquote：不支持点对语法 ~s" d))]
           [else d]))
       (define datas (map walk forms))            ; 带标记的 datum 树
       (define splice-vec (list->vector (reverse splices)))

       ;; 先收集本块 struct 名，扩充类型集合
       (type-names builtin-types)
       (for ([d datas])
         (when (and (pair? d) (eq? 'struct (car d)))
           (type-names (set-add (type-names) (cadr d)))))
       ;; 源文件路径 → 字符串（拿不到则 #f）
       (define (src-path-string f)
         (define src (syntax-source f))
         (cond [(path? src) (path->string src)]
               [src (format "~a" src)]
               [else #f]))
       ;; 一个 form 的源信息：(src-path src-line src-col src-span text)
       (define (source-info f)
         (list (src-path-string f)
               (syntax-line f) (syntax-column f) (syntax-span f) (syntax->datum f)))
       ;; 遍历 syntax 收集每个标识符的 (名字 路径 行 列)，报错时据此直接指到标识符。
       ;; ★ 跳过 glsl-unquote 子树：那里的标识符是 Racket 代码，不属于 GLSL 名字表。
       (define (collect-identifiers f)
         (define dat (syntax->datum f))
         (if (and (pair? dat) (eq? (car dat) 'glsl-unquote))
             '()
             (syntax-case f ()
               [(a . b) (append (collect-identifiers #'a) (collect-identifiers #'b))]
               [id (identifier? #'id)
                   (list (list (symbol->string (syntax->datum #'id))
                               (src-path-string #'id)
                               (syntax-line #'id)
                               (syntax-column #'id)))]
               [_ '()])))
       (define tokens (apply append (map collect-identifiers forms)))

       ;; 带标记的 datum 树 → 语法对象：普通原子用宏定义侧上下文（glsl-* 可解析），
       ;; splice-marker 换成使用侧语法（Racket 表达式原样求值，须返回字符串/glsl-program）。
       (define (tree->syntax t)
         (cond
           [(splice-marker? t) (vector-ref splice-vec (splice-marker-index t))]
           [(pair? t) (cons (tree->syntax (car t)) (tree->syntax (cdr t)))]
           [else (datum->syntax #'make-glsl-program t)]))

       ;; 生成 (make-glsl-program (list 片段...) '(源信息...) '(标识符表...))。
       ;; 片段 = 要运行的代码（rw-top 结果 / glsl-unquote 表达式）；
       ;; 源信息/标识符表 = 要引用的数据。代码与数据分列，避免混写 quote 导致的括号/转义错误。
       (with-syntax ([(part ...) (map (lambda (d) (tree->syntax (rw-top d))) datas)])
         #`(make-glsl-program
            (list part ...)
            '#,(map source-info forms)
            '#,tokens)))]))
