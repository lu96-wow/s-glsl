#lang racket/base

;; ============================================================
;; glsl-program.rkt —— (glsl ...) 的产物：带源映射的 GLSL 程序
;;
;;   glsl-program(src forms tokens)：
;;     src    = 美化后的 GLSL（可直接编译）
;;     forms  = 每个顶层 form 的源映射（glsl-form）
;;     tokens = 每个标识符的精确源位置（glsl-token，报错指到标识符用）
;;
;; make-glsl-program 是运行时入口（宏展开后调用它）：
;;   「代码」（各 form 生成 GLSL 字符串，运行时求值）
;;   +「数据」（源位置表 / 标识符表，宏展开期已剥好、quote 成字面量）
;;   → glsl-program
;; ============================================================

(require racket/string "pretty.rkt")   ; string-join / glsl-pretty-line-map

(provide glsl-src make-glsl-program glsl-program-lookup
         (struct-out glsl-program)
         (struct-out glsl-form)
         (struct-out glsl-token))

;; ---------- 数据 ----------

;; glsl-program：src = 美化后的 GLSL；forms = 顶层 form 源映射；tokens = 标识符表
(struct glsl-program (src forms tokens) #:transparent)

;; glsl-form：一个顶层 form 的源映射
;;   src-path = .rkt 源文件路径（拿不到则 #f）；src-line/src-col/src-span = 源文件里的位置
;;   text = 该 form 的原始 s 表达式；start-line/end-line = 生成 GLSL 落在哪几行（闭区间）
(struct glsl-form (src-path src-line src-col src-span text start-line end-line) #:transparent)

;; glsl-token：一个标识符名 + 它的源文件位置
(struct glsl-token (name src-path src-line src-col) #:transparent)

;; ---------- 构造 ----------

;; 取出 GLSL 源文本：glsl-program → 它的 src；字符串 → 原样
(define (glsl-src x)
  (if (glsl-program? x) (glsl-program-src x) x))

;; 每个片段在 raw 串里的 [start, end] 闭区间下标
(define (part-spans strs)
  (let loop ([xs strs] [offset 0] [acc '()])
    (if (null? xs)
        (reverse acc)
        (let ([len (string-length (car xs))])
          (define start offset)
          (define end (max start (- (+ start len) 1)))  ; len>=1 时 = start+len-1；空串退化为 start
          (loop (cdr xs) (+ start len 1) (cons (cons start end) acc))))))

;; 把 (parts source-infos tokens) 拼成 glsl-program：
;;   parts = 各顶层 form 生成的 GLSL 字符串（已求值，顺序对应）
;;   source-infos = 各 form 的 (src-path src-line src-col src-span text)
;;   tokens = 各标识符的 (name src-path src-line src-col)
(define (make-glsl-program parts source-infos tokens)
  ;; 片段：字面核心是字符串；glsl-unquote 拼接的值可为字符串或 glsl-program（取 src）
  (define strs
    (for/list ([p (in-list parts)])
      (cond
        [(string? p) p]
        [(glsl-program? p) (glsl-program-src p)]
        [else (error 'make-glsl-program
                     "glsl-unquote 必须返回字符串或 glsl-program，得到：~s" p)])))
  (define spans (part-spans strs))
  (define marks (apply append (map (lambda (sp) (list (car sp) (cdr sp))) spans)))
  (define-values (pretty lines) (glsl-pretty-line-map (string-join strs " ") marks))
  (define forms
    (for/list ([info source-infos] [i (in-naturals)])
      (glsl-form (list-ref info 0) (list-ref info 1) (list-ref info 2) (list-ref info 3) (list-ref info 4)
                 (list-ref lines (* 2 i))
                 (list-ref lines (+ (* 2 i) 1)))))
  ;; tokens 进来是 (名字 路径 行 列) 的裸列表，转成 glsl-token 结构
  (glsl-program pretty forms (map (lambda (t) (apply glsl-token t)) tokens)))

;; ---------- 查询 ----------

;; 美化 GLSL 第 line 行落在哪个顶层 form；没有则 #f
(define (glsl-program-lookup prog line)
  (for/first ([f (glsl-program-forms prog)]
              #:when (<= (glsl-form-start-line f) line (glsl-form-end-line f)))
    f))
