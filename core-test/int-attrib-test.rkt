#lang racket/base
;; ============================================================
;; int-attrib-test.rkt —— 整数顶点属性端到端冒烟测试
;; 运行：racket racket-glsl/core-test/int-attrib-test.rkt   （需要显示器 + GL）
;; 验证：ivec 顶点属性（gl-vertex-attrib-ip-pointer）+ s32vector VBO 上传
;;       + gl-int / glsl-stride-bytes（ivec3 = 12 字节）全链路。
;; 通过 = 打印 "int attrib ok" 并 exit 0；失败 = 抛异常。
;; ============================================================
(require racket/gui
         ffi/vector
         "../core/opengl/rename.rkt"       ; gl-* 命名层（含 I 指针与 gl-int）
         "../core/glsl/rewrite.rkt"             ; (glsl ...) 宏
         "../core/value/rename-type.rkt"   ; glsl-stride-bytes
         "../core/value/rename-buffer.rkt"
         "../core/value/convert.rkt"
         "../core/tool/program.rkt")               ; build-program / use-program

;; 离屏 GL 上下文（不必 show 窗口）
(define cfg (new gl-config%))
(send cfg set-legacy? #f)
(send cfg set-double-buffered #t)
(define frame (new frame% (label "int-attrib-test")))
(define canvas (new canvas% (style '(gl no-autoclear)) (gl-config cfg) (parent frame)))

;; 顶点着色器：整数属性 ivec3，拿整数算出位置（int 索引/精确值的典型用法）
(define vert-src
  (glsl (version 330 core)
        (layout (location 0) in ivec3 aIDs)
        (define (main) void
          (set! gl_Position
                (vec4 (* 0.25 (float (- (x aIDs) 1)))
                      (* 0.25 (float (- (y aIDs) 1)))
                      0.0 1.0)))))
(define frag-src
  (glsl (version 330 core)
        (out vec4 FragColor)
        (define (main) void
          (set! FragColor (vec4 0.2 0.8 0.4 1.0)))))

(send canvas with-gl-context
  (lambda ()
    ;; ① 编译链接
    (define prog (build-program (gl-vertex-shader vert-src)
                                (gl-fragment-shader frag-src)))
    (use-program prog)
    ;; ② s32vector VBO 上传（3 个 ivec3）
    (define data (s32vector 1 0 0   0 1 0   1 1 0))
    (define vbo (u32vector-ref (gl-gen-buffers 1) 0))
    (gl-bind-buffer gl-array-buffer vbo)
    (gl-buffer-data gl-array-buffer (gl-vector-sizeof data) data gl-static-draw)
    ;; ③ 整数属性：gl-vertex-attrib-ip-pointer（5 参数，无 normalized）
    (define v (u32vector-ref (gl-gen-vertex-arrays 1) 0))
    (gl-bind-vertex-array v)
    (gl-vertex-attrib-ip-pointer 0 3 gl-int (glsl-stride-bytes 'ivec3) 0)
    (gl-enable-vertex-attrib-array 0)
    (gl-bind-vertex-array 0)
    (printf "int attrib ok: program=~a vbo=~a vao=~a\n" prog vbo v)))

(exit 0)
