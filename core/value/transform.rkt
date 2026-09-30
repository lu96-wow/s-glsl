#lang racket/base

;; ============================================================
;; 值层 · value/transform.rkt —— 场景 / 相机变换
;;
;; 「逻辑：图形学参数化约定（右手系、列主序、角度制）」。
;; 命名：[Racket 传统]（look-at-matrix / perspective-matrix / …）。
;; GLSL 名（mat4-look-at / …）在 rename-transform.rkt。
;; ============================================================

(require ffi/vector "access.rkt" "vec.rkt")

(provide translation-matrix rotation-x-matrix rotation-y-matrix rotation-z-matrix
         scaling-matrix ortho-matrix perspective-matrix look-at-matrix)

(define pi (acos -1.0))
(define (rad deg) (* (/ pi 180.0) deg))

;; 16 个标量 → f32vector（列主序）
(define (m4 . xs) (apply f32vector xs))

(define (translation-matrix x y z)
  (m4 1.0 0.0 0.0 0.0
      0.0 1.0 0.0 0.0
      0.0 0.0 1.0 0.0
      x   y   z   1.0))

(define (rotation-x-matrix deg)
  (define c (cos (rad deg))) (define s (sin (rad deg)))
  (m4 1.0 0.0 0.0 0.0
      0.0 c   s   0.0
      0.0 (- s) c 0.0
      0.0 0.0 0.0 1.0))

(define (rotation-y-matrix deg)
  (define c (cos (rad deg))) (define s (sin (rad deg)))
  (m4 c     0.0 s   0.0
      0.0   1.0 0.0 0.0
      (- s) 0.0 c   0.0
      0.0   0.0 0.0 1.0))

(define (rotation-z-matrix deg)
  (define c (cos (rad deg))) (define s (sin (rad deg)))
  (m4 c     s     0.0 0.0
      (- s) c     0.0 0.0
      0.0   0.0   1.0 0.0
      0.0   0.0   0.0 1.0))

(define (scaling-matrix sx sy sz)
  (m4 sx  0.0 0.0 0.0
      0.0 sy  0.0 0.0
      0.0 0.0 sz  0.0
      0.0 0.0 0.0 1.0))

(define (ortho-matrix l r b t n f)
  (define rl (- r l)) (define tb (- t b)) (define fn (- f n))
  (m4 (/ 2.0 rl) 0.0 0.0 0.0
      0.0 (/ 2.0 tb) 0.0 0.0
      0.0 0.0 (/ -2.0 fn) 0.0
      (- (/ (+ r l) rl)) (- (/ (+ t b) tb)) (- (/ (+ f n) fn)) 1.0))

(define (perspective-matrix fovy aspect near far)
  (define f (/ 1.0 (tan (/ (rad fovy) 2.0))))
  (m4 (/ f aspect) 0.0 0.0 0.0
      0.0 f 0.0 0.0
      0.0 0.0 (/ (+ far near) (- near far)) -1.0
      0.0 0.0 (/ (* 2.0 far near) (- near far)) 0.0))

(define (look-at-matrix eye center up)
  (define f (vec-normalize (vec-sub center eye)))
  (define s (vec-normalize (vec-cross f up)))
  (define u (vec-cross s f))
  (m4 (vec-x s) (vec-x u) (- (vec-x f)) 0.0
      (vec-y s) (vec-y u) (- (vec-y f)) 0.0
      (vec-z s) (vec-z u) (- (vec-z f)) 0.0
      (- (vec-dot s eye)) (- (vec-dot u eye)) (vec-dot f eye) 1.0))
