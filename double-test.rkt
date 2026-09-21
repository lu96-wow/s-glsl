#lang racket/base
;; ============================================================
;; double-test.rkt —— double 精度端到端冒烟测试
;; 运行：racket racket-glsl/double-test.rkt   （需要显示器 + GL 4.0+）
;; 验证：dvec 顶点属性（gl-vertex-attrib-l-pointer）+ double uniform
;;       （gl-uniform-1d）+ f64vector VBO 上传（gl-buffer-data）全链路。
;; 通过 = 打印 "double upload ok" 并 exit 0；失败 = 抛异常。
;; ============================================================
(require racket/gui
         "opengl-rename.rkt"     ; gl-* 命名层（含 double 函数）
         "rewrite.rkt"           ; (glsl ...) 宏
         "rename-vector.rkt"     ; dvec*/concat-dvecs/glsl-stride-bytes
         "tool.rkt")             ; build-program / uniform-location

;; 一个离屏 GL 上下文（不必 show 窗口；with-gl-context 会按需创建上下文）
(define cfg (new gl-config%))
(send cfg set-legacy? #f)
(send cfg set-double-buffered #t)
(define frame (new frame% (label "double-test")))
(define canvas (new canvas% (style '(gl no-autoclear)) (gl-config cfg) (parent frame)))

;; double 着色器：机器是 GL 4.5，double 系类型可用（顶点属性需较新 GLSL）。
(define vert-src
  (glsl (version 410 core)
        (layout (location 0) in dvec3 aPos)     ; double 精度顶点属性（4.10+）
        (uniform double uScale)                 ; double 精度 uniform
        (define (main) void
          (set! gl_Position
                (vec4 (float (* (x aPos) uScale))   ; double×double → 显式转 float
                      (float (y aPos))
                      0.0 1.0)))))
(define frag-src
  (glsl (version 410 core)
        (out vec4 FragColor)
        (define (main) void
          (set! FragColor (vec4 1.0 0.0 0.0 1.0)))))

(send canvas with-gl-context
  (lambda ()
    ;; ① 编译链接 double 着色器
    (define prog (build-program (gl-vertex-shader vert-src)
                                (gl-fragment-shader frag-src)))
    ;; ② double uniform（glUniform* 操作"当前程序"，先 use-program）
    (use-program prog)
    (define loc (uniform-location prog "uScale"))
    (gl-uniform-1d loc 1.0)
    ;; ③ f64vector VBO 上传
    (define data (concat-dvecs (dvec3 -0.5 -0.5 0.0)
                               (dvec3  0.5 -0.5 0.0)
                               (dvec3  0.0  0.5 0.0)))
    (define vbo (u32vector-ref (gl-gen-buffers 1) 0))
    (gl-bind-buffer gl-array-buffer vbo)
    (gl-buffer-data gl-array-buffer (gl-vector-sizeof data) data gl-static-draw)
    ;; ④ double 顶点属性（L-pointer：无 normalized 参数，dvec3 步长 24 字节）
    (define v (u32vector-ref (gl-gen-vertex-arrays 1) 0))
    (gl-bind-vertex-array v)
    (gl-vertex-attrib-l-pointer 0 3 gl-double (glsl-stride-bytes 'dvec3) 0)
    (gl-enable-vertex-attrib-array 0)
    (gl-bind-vertex-array 0)
    (printf "double upload ok: program=~a uniform-loc=~a vbo=~a vao=~a\n"
            prog loc vbo v)))

(exit 0)
