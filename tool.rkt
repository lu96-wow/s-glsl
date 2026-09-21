#lang racket/base

;; ============================================================
;; tool.rkt —— GLSL 文本 → 程序 的工具层
;;
;; 隐藏 OpenGL 的 ffi 细节（gl-shader-source 的 s32vector/vector、
;; 编译链接状态检查、info log 拼接），把"编译 → 链接 → 组织成程序"
;; 这一整套收成几个函数，覆盖一个程序的完整生命周期：
;;   编译 compile-shader → 链接 link-program → 组织 build-program
;;   → 启用 use-program → 查 uniform uniform-location → 删除 delete-*
;;
;; 约定：
;;   - 编译失败自动抛异常，消息分四段（OpenGL 行列/美化、s表达式 行列/美化，见 gl-error.rkt）。
;;   - 链接失败抛异常，带链接日志。
;;   - 每段管线可自定义：任何 GL 着色器阶段类型都可作为编译 type。
;;   - 本模块不重新导出 OpenGL 名字（gl-vertex-shader 等由调用方从
;;     opengl-rename.rkt 拿），内部统一用 kebab-case 的 gl-* 名字。
;; ============================================================

(require "pretty.rkt" "glsl-program.rkt" "opengl-rename.rkt" "gl-error.rkt" ffi/vector)

(provide compile-shader link-program build-program build-program/list
         use-program uniform-location delete-shader delete-program)

;; ---------- 内部：报错日志 ----------

;; 取 info log：get-iv 查长度、get-log 取内容，拼成 UTF-8 字符串（shader/program 共用）
(define (info-log get-iv get-log obj)
  (define len (get-iv obj gl-info-log-length))
  (define-values (actual log) (get-log obj len))
  (bytes->string/utf-8 log #\? 0 actual))

(define (shader-info-log shader)
  (info-log gl-get-shader-iv gl-get-shader-info-log shader))

(define (program-info-log prog)
  (info-log gl-get-program-iv gl-get-program-info-log prog))

;; 报错定位（解析 / 定位 / 渲染）在 gl-error.rkt，本文件只做第 ④ 阶段：抛出。

;; ---------- ① 编译：一段 GLSL 文本 → 一个着色器对象 ----------

;; type 是任意着色器阶段：gl-vertex-shader / gl-tess-control-shader /
;; gl-tess-evaluation-shader / gl-geometry-shader / gl-fragment-shader。
;; 编译失败自动抛错，错误消息带 GLSL 报错日志。
(define (compile-shader type src)
  ;; 先统一成"美化后的字符串"再编译，报错行号因此对齐美化版：
  ;;   glsl-program（(glsl ...) 的产物）→ 它的 src 已经是美化串，直接用；
  ;;   裸字符串 → 现做 glsl-pretty。
  (define src* (if (glsl-program? src) (glsl-program-src src) (glsl-pretty src)))
  (define shader (gl-create-shader type))
  ;; gl-shader-source 的 C 签名要"字符串数组 + 每段长度数组"：
  ;; 长度数组必须是 s32vector（32 位有符号整数向量）。纯 ffi 细节，藏在这里。
  (gl-shader-source shader 1 (vector src*) (s32vector (string-length src*)))
  (gl-compile-shader shader)
  (when (zero? (gl-get-shader-iv shader gl-compile-status))
    (define log (shader-info-log shader))
    ;; 源映射上下文：glsl-program 才有映射；裸字符串只有美化源码（无 form 提示）
    (define ctx (if (glsl-program? src) src src*))
    (define located (map (lambda (e) (locate-gl-error ctx e))
                         (parse-gl-error-log log)))
    (error 'compile-shader
           "shader compile failed:\n\n~a"
           (render-error log ctx located)))
  shader)

;; ---------- ② 链接：若干着色器对象 → 一个程序对象 ----------

;; 链接失败自动抛错，带链接日志。
(define (link-program . shaders)
  (define prog (gl-create-program))
  (for ([s shaders])
    (gl-attach-shader prog s))
  (gl-link-program prog)
  (when (zero? (gl-get-program-iv prog gl-link-status))
    (error 'link-program "program link failed:\n~a" (program-info-log prog)))
  prog)

;; ---------- ③ 组织：把 (阶段类型 源码) 编译 + 链接成一个程序 ----------

;; 宏（每段写成 (类型 源码)，不提前求值）——每段管线可自定义、任意组合：
;;   (build-program (gl-vertex-shader vs) (gl-fragment-shader fs))
;;   (build-program (gl-vertex-shader vs) (gl-geometry-shader gs) (gl-fragment-shader fs))
(define-syntax-rule (build-program (type src) ...)
  (build-program/list (list (list type src) ...)))

;; 函数版（给需要动态构造阶段列表的代码用）：
;;   (build-program/list (list (list gl-vertex-shader vs) (list gl-fragment-shader fs)))
(define (build-program/list stages)
  (apply link-program
         (for/list ([s stages])
           (compile-shader (car s) (cadr s)))))

;; ---------- ④ 启用：把程序设为"当前要用的程序" ----------

;; OpenGL 是状态机，同一时刻只有一个"当前程序"，之后所有绘制都用它。
(define (use-program prog)
  (gl-use-program prog))

;; ---------- ⑤ 查 uniform：按名字拿一个 uniform 的位置 ----------

;; uniform = CPU 每帧传给 shader 的全局常量（教程后面会讲）。
;; 找不到时返回 -1（OpenGL 约定），调用方自行判断。
(define (uniform-location prog name)
  (gl-get-uniform-location prog name))

;; ---------- ⑥ 删除：释放 GPU 资源 ----------

;; OpenGL 的删除是"标记待删"：真正释放等它不再被使用。删完别再引用。
(define (delete-shader shader)
  (gl-delete-shader shader))

(define (delete-program prog)
  (gl-delete-program prog))
