#lang racket/base

;; ============================================================
;; 值层 · value/rename-construct.rkt —— GLSL 风格命名（构造）
;;
;; 纯 alias：value/construct.rkt 的 Racket 名 → GLSL 类型构造器。零逻辑。
;; ============================================================

(require ffi/vector "construct.rkt")

(provide vec2 vec3 vec4 dvec2 dvec3 dvec4 ivec2 ivec3 ivec4 uvec2 uvec3 uvec4 bvec2 bvec3 bvec4
         mat2 mat3 mat4 dmat2 dmat3 dmat4)

;; ---------- 向量 ----------

(define (vec2 x y) (make-f32-vec 'vec2 2 x y))
(define (vec3 x y z) (make-f32-vec 'vec3 3 x y z))
(define (vec4 x y z w) (make-f32-vec 'vec4 4 x y z w))

(define (dvec2 x y) (make-f64-vec 'dvec2 2 x y))
(define (dvec3 x y z) (make-f64-vec 'dvec3 3 x y z))
(define (dvec4 x y z w) (make-f64-vec 'dvec4 4 x y z w))

(define (ivec2 x y) (make-s32-vec 'ivec2 2 x y))
(define (ivec3 x y z) (make-s32-vec 'ivec3 3 x y z))
(define (ivec4 x y z w) (make-s32-vec 'ivec4 4 x y z w))

(define (uvec2 x y) (make-u32-vec 'uvec2 2 x y))
(define (uvec3 x y z) (make-u32-vec 'uvec3 3 x y z))
(define (uvec4 x y z w) (make-u32-vec 'uvec4 4 x y z w))

(define (bvec2 x y) (make-bool-vec 'bvec2 2 x y))
(define (bvec3 x y z) (make-bool-vec 'bvec3 3 x y z))
(define (bvec4 x y z w) (make-bool-vec 'bvec4 4 x y z w))

;; ---------- 矩阵 ----------

(define (mat2 . args) (apply make-matrix 2 f32vector args))
(define (mat3 . args) (apply make-matrix 3 f32vector args))
(define (mat4 . args) (apply make-matrix 4 f32vector args))
(define (dmat2 . args) (apply make-matrix 2 f64vector args))
(define (dmat3 . args) (apply make-matrix 3 f64vector args))
(define (dmat4 . args) (apply make-matrix 4 f64vector args))
