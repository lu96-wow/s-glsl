#lang racket/base
;; core 冒烟：验证实现层 / rename 层 / 语言层 / OpenGL rename 都能加载并工作。
(require rackunit
         ffi/vector
         "value/type.rkt"
         "value/vec.rkt"
         "value/matrix.rkt"
         "value/convert.rkt"
         "value/buffer.rkt"
         "value/transform.rkt"
         "value/rename-type.rkt"
         "value/rename-construct.rkt"
         "value/rename-layout.rkt"
         "value/rename-buffer.rkt"
         "value/rename-vec.rkt"
         "value/rename-matrix.rkt"
         "value/rename-transform.rkt"
         "glsl/rewrite.rkt"
         "opengl/rename.rkt"
         "tool/error.rkt"
         "tool/compile.rkt"
         "tool/program.rkt")

;; ---------- 实现层（Racket 名，Racket 约定） ----------
(check-true (type-known? 'mat2x3))
(check-equal? (type-kind 'mat2x3) 'f32)

(define A (mat4 1.0 2.0 3.0 4.0  5.0 6.0 7.0 8.0  9.0 10.0 11.0 12.0  13.0 14.0 15.0 16.0))
(check-equal? (matrix-ref A 0 1) 5.0)      ; Racket：row0,col1

;; 标量可放任一侧
(check-true (f32vector? (vec-mod 2.0 (vec3 1.0 2.0 3.0))))
(check-true (f32vector? (vec-add 1.0 (vec3 1.0 2.0 3.0))))
;; floor 只对 float
(check-exn exn:fail? (lambda () (vec-floor (ivec3 1 2 3))))

;; ---------- rename 层（GLSL 名） ----------
(check-equal? (mat4-ref A 0 1) 2.0)        ; GLSL：col0,row1
(check-equal? (f32vector->list (vadd (vec2 1.0 2.0) (vec2 3.0 4.0))) '(4.0 6.0))
(check-equal? (glsl-size 'vec3) 3)
(check-equal? (glsl-stride-bytes 'vec3 'vec2) 20)

(glsl-struct vertex (vec3 pos) (vec3 color))
(define v0 (vertex (vec3 1.0 2.0 3.0) (vec3 1.0 0.0 0.0)))
(check-equal? (f32vector->list (vertex->f32vector v0)) '(1.0 2.0 3.0 1.0 0.0 0.0))
(check-equal? (vertex-stride) 24)
(check-equal? (vertex-field-offset 'color) 12)

(check-equal? (mat4-ref (mat4-translate 1.0 2.0 3.0) 3 0) 1.0)
(define V (mat4-look-at (vec3 0.0 0.0 5.0) (vec3 0.0 0.0 0.0) (vec3 0.0 1.0 0.0)))
(check-equal? (vz (mat4-mul-vec V (vec4 0.0 0.0 0.0 1.0))) -5.0)

;; ---------- 语言层（Part 1：(glsl) 内） ----------
(check-equal? (glsl-decl '("in") "vec2" "aPos") "in vec2 aPos;")
(check-equal? (glsl-pretty "if (x) { a = b; }") "if (x) {\n  a = b;\n}")
(check-equal? (glsl-version 330 "core") "#version 330 core\n")

(define vert
  (glsl (version 330 core)
        (layout (location 0) in vec3 aPos)
        (uniform mat4 uMVP)
        (out vec3 vColor)
        (define (main) void
          (set! vColor aPos)
          (set! gl_Position (* uMVP (vec4 aPos 1.0))))))
(check-true (glsl-program? vert))
(check-true (regexp-match? #rx"#version 330 core" (glsl-program-src vert)))
(define ifc (glsl-program-interface vert))
(check-true (and (glsl-interface-ref ifc 'uMVP) #t))
(check-true (glsl-var-has-qualifier? (glsl-interface-ref ifc 'uMVP) 'uniform))
(check-true (and (glsl-program-lookup vert 3) #t))

;; ---------- OpenGL rename ----------
(check-true (procedure? gl-create-shader))
(check-true (integer? gl-array-buffer))

;; ---------- 胶水（tool/，纯函数部分不需 GL 上下文） ----------
(check-true (procedure? compile-shader))
(check-true (procedure? link-program))
(define glog "0:5(2): error: `uMVP' undeclared\n")
(define errs (parse-gl-error-log glog))
(check-equal? (gl-error-line (car errs)) 5)
(define located (map (lambda (e) (locate-gl-error vert e)) errs))
(check-true (and (located-error-form (car located)) #t))
(define rendered (render-error glog vert located))
(check-true (regexp-match? #rx"OpenGL log:" rendered))
(check-true (regexp-match? #rx"OpenGL source:" rendered))
(check-true (regexp-match? #rx"s-expr source:" rendered))

(displayln "core smoke: ALL OK")
