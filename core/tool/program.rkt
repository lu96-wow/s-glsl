#lang racket/base

;; ============================================================
;; 胶水 · tool/program.rkt —— GL program 生命周期层
;;
;;   编译（委托 tool/compile.rkt 的 shader-compile）
;;   → 链接 program-link → 组织 build-program / build-program/list
;;   → 启用 program-use → 查 uniform uniform-location
;;   → 释放 shader-delete / program-delete
;;
;; 工具层命名（规则 9）：不与 raw 层同基名。
;;   raw：  gl-compile-shader / gl-link-program / gl-use-program / gl-delete-shader …
;;   工具： shader-compile    / program-link    / program-use    / shader-delete …
;;
;; 约定：
;;   - 链接失败自动抛异常，带 program info log。
;;   - 每段管线可自定义：任何 GL 着色器阶段类型都可作为编译 type。
;;   - 本模块不重新导出 OpenGL 名字（gl-vertex-shader 等由调用方从
;;     opengl/rename.rkt 拿），内部统一用 kebab-case 的 gl-* 名字。
;; ============================================================

(require "compile.rkt"            ; shader-compile（文本 → shader + 报错）
         "../opengl/rename.rkt")  ; gl-* 名字

(provide program-link program-use shader-delete program-delete
         build-program build-program/list uniform-location
         ;; 旧名（deprecated，等价别名，下个大版本删）
         link-program use-program delete-shader delete-program)

;; ---------- 内部：程序信息日志 ----------

;; 取 info log：get-iv 查长度、get-log 取内容，拼成 UTF-8 字符串
(define (info-log get-iv get-log obj)
  (define len (get-iv obj gl-info-log-length))
  (define-values (actual log) (get-log obj len))
  (bytes->string/utf-8 log #\? 0 actual))

(define (program-info-log prog)
  (info-log gl-get-program-iv gl-get-program-info-log prog))

;; ---------- 链接：若干着色器对象 → 一个程序对象 ----------

;; 链接失败自动抛错，带链接日志。
;; 注意：shader 的所有权仍归调用方——本函数只 attach/link，不删除。
;; 但 program 是本函数创建的，链接失败也要释放，否则句柄丢失就泄漏。
(define (program-link . shaders)
  (define prog (gl-create-program))
  (for ([s shaders])
    (gl-attach-shader prog s))
  (gl-link-program prog)
  (when (zero? (gl-get-program-iv prog gl-link-status))
    ;; 先取日志（program 删了就读不到了），再释放 program，最后抛错
    (define log (program-info-log prog))
    (gl-delete-program prog)
    (error 'program-link "program link failed:\n~a" log))
  prog)

;; ---------- 组织：把 (阶段类型 源码) 编译 + 链接成一个程序 ----------

;; 宏（每段写成 (类型 源码)，不提前求值）——每段管线可自定义、任意组合：
;;   (build-program (gl-vertex-shader vs) (gl-fragment-shader fs))
;;   (build-program (gl-vertex-shader vs) (gl-geometry-shader gs) (gl-fragment-shader fs))
(define-syntax-rule (build-program (type src) ...)
  (build-program/list (list (list type src) ...)))

;; 函数版（给需要动态构造阶段列表的代码用）：
;;   (build-program/list (list (list gl-vertex-shader vs) (list gl-fragment-shader fs)))
;;
;; 这些 shader 是本函数自己编译的，所有权在这里：
;;   - 链接成功后立刻 detach + delete（编译产物已并入 program，没别的用途）
;;   - 中途任何一步失败（编译失败 / 链接失败）也全部 delete，避免句柄丢失造成泄漏
;; program-link 不删 shader——那是"调用方传入、调用方拥有"的情况。
(define (build-program/list stages)
  (define compiled '())                     ; 已编译、待释放（逆序累积）
  (define (free-compiled!)
    (for ([s (in-list compiled)]) (gl-delete-shader s))
    (set! compiled '()))
  (with-handlers ([exn:fail? (lambda (e) (free-compiled!) (raise e))])
    (for ([s (in-list stages)])
      (set! compiled (cons (shader-compile (car s) (cadr s)) compiled)))
    (set! compiled (reverse compiled))
    (define prog (apply program-link compiled))
    ;; 链接成功：shader 已并入 program，detach 后即可安全删除
    (for ([s (in-list compiled)])
      (gl-detach-shader prog s)
      (gl-delete-shader s))
    (set! compiled '())                     ; 已释放，别让 handler 重复删
    prog))

;; ---------- 启用：把程序设为"当前要用的程序" ----------

;; OpenGL 是状态机，同一时刻只有一个"当前程序"，之后所有绘制都用它。
(define (program-use prog)
  (gl-use-program prog))

;; ---------- 查 uniform：按名字拿一个 uniform 的位置 ----------

;; uniform = CPU 每帧传给 shader 的全局常量。
;; 找不到时返回 -1（OpenGL 约定），调用方自行判断。
(define (uniform-location prog name)
  (gl-get-uniform-location prog name))

;; ---------- 释放：删除 GL 对象 ----------

;; OpenGL 的删除是"标记待删"：真正释放等它不再被使用。删完别再引用。
(define (shader-delete shader)
  (gl-delete-shader shader))

(define (program-delete prog)
  (gl-delete-program prog))

;; ---------- 旧名（deprecated，等价别名）----------
(define link-program program-link)
(define use-program program-use)
(define delete-shader shader-delete)
(define delete-program program-delete)
