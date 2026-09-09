#lang racket/base
;; ============================================================
;; 重写层 (glsl ...) 测试
;; 运行：racket racket-glsl/rewrite-test.rkt
;; ============================================================
(require rackunit
         "rewrite.rkt")

;; ---------- 顶点着色器（02 课，表面语法） ----------
(define vert
  (glsl
   (version 330 core)
   (layout (location 0) in vec2 aPos)
   (layout (location 1) in vec2 aUV)
   (out vec2 vUV)
   (define (main) void
     (set! vUV aUV)
     (set! gl_Position (vec4 aPos 0.0 1.0)))))

(check-equal?
 (glsl-pretty vert)
 "#version 330 core\nlayout(location = 0) in vec2 aPos;\nlayout(location = 1) in vec2 aUV;\nout vec2 vUV;\nvoid main() {\n  vUV = aUV;\n  gl_Position = vec4(aPos, 0.0, 1.0);\n}")

;; ---------- 片元着色器（02 课，表面语法） ----------
(define frag
  (glsl
   (version 330 core)
   (in vec2 vUV)
   (uniform float uTime)
   (out vec4 FragColor)
   (define (main) void
     (vec2 p (- (* vUV 2.0) 1.0))
     (float d (length p))
     (float ring (fract (- (* d 6.0) uTime)))
     (vec3 c (mix (vec3 0.10 0.15 0.40) (vec3 0.10 0.70 1.00) ring))
     (*= c (- 1.0 (* 0.55 d)))
     (+= c (* (vec3 0.15) (+ 0.5 (* 0.5 (sin (* uTime 2.0))))))
     (when (and (> (x p) 0.15) (> (y p) 0.15))
       (set! c (vec3 (+ (* (x p) 0.5) 0.5)
                     (+ (* (y p) 0.5) 0.5)
                     (+ 0.5 (* 0.4 (sin (+ uTime (* (x p) 3.0))))))))
     (set! FragColor (vec4 (clamp c 0.0 1.0) 1.0)))))

(displayln "===== 02 片元（表面语法 → 美化）=====")
(displayln (glsl-pretty frag))
(newline)

;; ---------- 语法覆盖断言（逐个特性） ----------
(check-equal? (glsl (version 330 core) (uniform vec4 uMVP))
              "#version 330 core\n uniform vec4 uMVP;")
(check-equal? (glsl (struct Light (vec3 pos) (float i)))
              "struct Light { vec3 pos; float i; };")
(check-equal? (glsl (define (sq (float x)) float (* x x)))
              "float sq(float x) { return (x * x); }")
;; 函数体最后一个表达式有值 → 作为 return（重写层此能力待加，先手写 return）
(check-equal? (glsl (define (f (inout vec3 p)) void
                      (return (+ (x p) 1.0))))
              "void f(inout vec3 p) { return (p.x + 1.0); }")
(check-equal? (glsl (define (main) void
                      (for (int i 0) (< i 8) (++ i)
                        (set! x (+ x i)))))
              "void main() { for (int i = 0; (i < 8); ++i) { x = (x + i); } }")
(check-equal? (glsl (define (main) void
                      (cond [(> a b) (set! c a)]
                            [else (set! c b)])))
              "void main() { if ((a > b)) { c = a; } else { c = b; } }")
(check-equal? (glsl (define (main) void
                      (while (< i n) (++ i))))
              "void main() { while ((i < n)) { ++i; } }")
(check-equal? (glsl (define (main) void
                      (unless done (break))))
              "void main() { if ((!done)) { break; } }")
;; switch
(check-equal? (glsl (define (main) void
                      (switch mode
                        [case 1 (set! c a)]
                        [case 2 (set! c b)]
                        [default (set! c z)])))
              "void main() { switch (mode) { case 1: { c = a; } case 2: { c = b; } default: { c = z; } } }")
;; layout 多 item
(check-equal? (glsl (layout (location 0) (binding 1) uniform sampler2D uTex))
              "layout(location = 0, binding = 1) uniform sampler2D uTex;")
;; raw 逃逸（顶层 + 语句）
(check-equal? (glsl (raw "#define FOO 1"))
              "#define FOO 1")
(check-equal? (glsl (define (main) void (raw "foo();")))
              "void main() { foo(); }")

;; ---------- 数组类型（(array 内层 [大小])）----------
(check-equal? (glsl (version 330 core) ((array float 4) weights))
              "#version 330 core\n float[4] weights;")
(check-equal? (glsl ((array vec3) v))              ; 未定长 → []
              "vec3[] v;")
(check-equal? (glsl ((array (array float 4) 3) m)) ; 数组的数组
              "float[4][3] m;")
(check-equal? (glsl (in (array vec3 4) aPos))      ; 限定符 + 数组
              "in vec3[4] aPos;")
(check-equal? (glsl (layout (location 0) in (array vec2 4) data))
              "layout(location = 0) in vec2[4] data;")
(check-equal? (glsl (struct S ((array float 4) weights)))
              "struct S { float[4] weights; };")
;; 数组构造器（类型位当构造器头）
(check-equal? (glsl (define (f) (array float 4) ((array float 4) 1.0 2.0 3.0 4.0)))
              "float[4] f() { return float[4](1.0, 2.0, 3.0, 4.0); }")

;; ---------- raw 表达式位（★必须在 swizzle 判定之前）----------
(check-equal? (glsl (define (main) void (float x (raw "1.0 + 2.0"))))
              "void main() { float x = 1.0 + 2.0; }")

;; ---------- 独立 layout（compute/几何/early_fragment_tests，无类型）----------
(check-equal? (glsl (version 430 core) (layout (local_size_x 8) (local_size_y 8) in))
              "#version 430 core\n layout(local_size_x = 8, local_size_y = 8) in;")
(check-equal? (glsl (layout (points) in))
              "layout(points) in;")
(check-equal? (glsl (layout (triangle_strip) (max_vertices 3) out))
              "layout(triangle_strip, max_vertices = 3) out;")

;; ---------- cond → else if 链（不套多余的 {}）----------
(check-equal? (glsl (define (main) void
                      (cond [(= a 1) (set! c a)]
                            [(= a 2) (set! c b)]
                            [else (set! c z)])))
              "void main() { if ((a == 1)) { c = a; } else if ((a == 2)) { c = b; } else { c = z; } }")

;; ---------- 通用声明限定符（flat/patch/shared/readonly...）----------
(check-equal? (glsl (flat in vec3 v)) "flat in vec3 v;")
(check-equal? (glsl (patch in vec3 p) (patch out vec3 q))
              "patch in vec3 p; patch out vec3 q;")
(check-equal? (glsl (shared vec4 acc)) "shared vec4 acc;")
(check-equal? (glsl (layout (rgba32f) readonly uniform image2D img))
              "layout(rgba32f) readonly uniform image2D img;")

;; ---------- 接口块（UBO/SSBO/in-out block）----------
(check-equal? (glsl (layout (std140) (binding 0) uniform (block Camera (mat4 view) (mat4 proj)) cam))
              "layout(std140, binding = 0) uniform Camera { mat4 view; mat4 proj; } cam;")
(check-equal? (glsl (layout (std430) (binding 1) buffer (block Particles ((array vec4) position)) particles))
              "layout(std430, binding = 1) buffer Particles { vec4[] position; } particles;")
(check-equal? (glsl (out (block VertexData (vec3 normal) (vec2 uv)) vs_out))
              "out VertexData { vec3 normal; vec2 uv; } vs_out;")
;; 成员访问（.field + aref 组合）
(check-equal? (glsl (define (main) void (set! (.view cam) (mat4 1.0))))
              "void main() { cam.view = mat4(1.0); }")
(check-equal? (glsl (define (main) void (set! (aref (.position particles) i) (vec4 1.0))))
              "void main() { particles.position[i] = vec4(1.0); }")

;; ---------- 字段级 layout / 限定符 ----------
(check-equal? (glsl (layout (std140) uniform (block Camera
                                            (layout (offset 0) mat4 view)
                                            (layout (offset 64) mat4 proj)) cam))
              "layout(std140) uniform Camera { layout(offset = 0) mat4 view; layout(offset = 64) mat4 proj; } cam;")
(check-equal? (glsl (out (block V (flat vec3 normal) (vec2 uv)) vs_out))
              "out V { flat vec3 normal; vec2 uv; } vs_out;")
