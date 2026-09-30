#lang racket/base
;; 运行：racket racket-glsl/core-test/transform-test.rkt
(require rackunit
         ffi/vector
         "../core/value/rename-type.rkt"
         "../core/value/rename-access.rkt"
         "../core/value/rename-construct.rkt"
         "../core/value/rename-layout.rkt"
         "../core/value/rename-buffer.rkt"
         "../core/value/convert.rkt"
         "../core/value/rename-vec.rkt"
         "../core/value/rename-matrix.rkt"
         "../core/value/convert.rkt"
         "../core/value/rename-transform.rkt")

(define (lf v) (map (lambda (x) (inexact->exact (round (* x 1e6)))) (f32vector->list v)))

;; ---------- 模型矩阵：translate / rot / scaling ----------
(check-equal? (mat4-ref (mat4-translate 1.0 2.0 3.0) 3 0) 1.0)
(check-equal? (lf (mat4-mul-vec (mat4-translate 1.0 2.0 3.0) (vec4 10.0 20.0 30.0 1.0)))
              '(11000000 22000000 33000000 1000000))

;; 绕 Z 轴 90°：(1,0) → (0,1)
(check-equal? (lf (mat4-mul-vec (mat4-rot-z 90.0) (vec4 1.0 0.0 0.0 1.0)))
              '(0 1000000 0 1000000))
;; 绕 X 轴 90°：(0,1,0) → (0,0,1)
(check-equal? (lf (mat4-mul-vec (mat4-rot-x 90.0) (vec4 0.0 1.0 0.0 1.0)))
              '(0 0 1000000 1000000))

(check-equal? (lf (mat4-mul-vec (mat4-scaling 2.0 3.0 4.0) (vec4 1.0 1.0 1.0 1.0)))
              '(2000000 3000000 4000000 1000000))

;; ---------- 视图矩阵：look-at ----------
;; 相机在 z=5 看原点 → 原点映到 (0,0,-5,1)
(define V (mat4-look-at (vec3 0.0 0.0 5.0) (vec3 0.0 0.0 0.0) (vec3 0.0 1.0 0.0)))
(check-equal? (lf (mat4-mul-vec V (vec4 0.0 0.0 0.0 1.0))) '(0 0 -5000000 1000000))

;; ---------- 投影矩阵：ortho / perspective ----------
(check-equal? (f32vector-length (mat4-ortho 0.0 800.0 600.0 0.0 0.1 100.0)) 16)
(define P (mat4-perspective 45.0 (/ 4.0 3.0) 0.1 100.0))
(check-equal? (f32vector-length P) 16)
(check-equal? (mat4-ref P 2 3) -1.0)          ; w' = -z 是"近大远小"的关键

;; ---------- 集成：mvp = P · V · M ----------
(define mvp (mat4-mul (mat4-mul P V) (mat4-rot-z 0.0)))
(check-true (f32vector? mvp))
(check-equal? (f32vector-length mvp) 16)
;; 点 (0,0,0,1) 在相机前方 → 齐次 w = 5（= 距离）
(check-equal? (vw (mat4-mul-vec mvp (vec4 0.0 0.0 0.0 1.0))) 5.0)

;; ---------- 和 vec-math 配合：逆变换撤销平移 ----------
(check-equal? (lf (mat4-inverse (mat4-translate 1.0 2.0 3.0)))
              (lf (mat4-translate -1.0 -2.0 -3.0)))

(displayln "transform 全部测试通过")
