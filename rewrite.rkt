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
;; ============================================================

(require (for-syntax racket/base
                     racket/string
                     racket/format
                     racket/set
                     racket/list
                     racket/syntax
                     "core.rkt")
         "core.rkt")

(provide glsl (all-from-out "core.rkt"))

(begin-for-syntax

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
         [(and (symbol? head) (swizzle-name? head))
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
      [(pair? s)
       (define head (car s))
       (define args (cdr s))
       (cond
         [(eq? head 'begin) (cons 'glsl-block (map rw-stmt args))]
         [(eq? head 'when)
          (list 'glsl-if (rw-expr (car args)) (rw-body (cdr args)))]
         [(eq? head 'unless)
          (list 'glsl-if (list 'glsl-unary "!" (rw-expr (car args))) (rw-body (cdr args)))]
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
          (define ty (rw-type (car after)))
          (define nm (symbol->string (cadr after)))
          (if (null? (cddr after))
              (list 'glsl-decl (cons 'list quals) ty nm)
              (list 'glsl-decl (cons 'list quals) ty nm (rw-expr (caddr after)))))))

  ;; 声明限定符 / layout 项结束标志：遇到这些进入"类型区"
  (define qual-keywords
    '(in out uniform const buffer flat smooth noperspective centroid sample patch
      invariant precise shared readonly writeonly restrict coherent volatile))

  ;; layout item → 核心 spec 项：(key value) 或裸名
  (define (rw-layout-item it)
    (cond
      [(and (pair? it) (null? (cdr it))) (symbol->string (car it))]  ; (std140)/(points) 等裸项
      [(pair? it) (list 'list (symbol->string (car it)) (cadr it))]  ; (location 0)（数据形式）
      [else (symbol->string it)]))                                    ; 裸符号

  ;; 同上，但产出"运行时值"（给 field->str 直接调核心层用）：(offset 0) → ("offset" 0)
  (define (layout-item->val it)
    (cond
      [(and (pair? it) (null? (cdr it))) (symbol->string (car it))]
      [(pair? it) (list (symbol->string (car it)) (cadr it))]
      [else (symbol->string it)]))

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
        [else (loop (cdr fs) (cons (car fs) acc))])))

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

  ;; 是否为"表达式形态"（非控制流/声明）
  (define (expr-form? f)
    (and (pair? f)
         (let ([h (car f)])
           (not (or (memq h stmt-keywords)
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
    (list* 'glsl-struct (symbol->string (car args)) (map rw-field (cdr args))))

  ;; ---------- 顶层 ----------
  (define (rw-top t)
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
      [(declaration? t)
       (rw-decl t)]
      [else (error 'glsl "bad top-level form: ~s" t)])))

;; ---------- 入口宏 ----------
(define-syntax (glsl stx)
  (syntax-case stx ()
    [(_ form ...)
     (let ()
       ;; 先收集本块 struct 名，扩充类型集合
       (define forms (syntax->list #'(form ...)))
       (type-names builtin-types)
       (for ([f forms])
         (define d (syntax->datum f))
         (when (and (pair? d) (eq? 'struct (car d)))
           (type-names (set-add (type-names) (cadr d)))))
       ;; 纯数据重写 → 转回 syntax（用宏定义侧上下文）
       (datum->syntax #'glsl-shader
                      (cons 'glsl-shader
                            (map (lambda (f) (rw-top (syntax->datum f))) forms))))]))
