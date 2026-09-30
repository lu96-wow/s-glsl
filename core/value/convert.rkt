#lang racket/base

;; ============================================================
;; 值层 · value/convert.rkt —— 精度转换
;;
;; 「逻辑：任意 GLSL 向量 / 缓冲 → 指定精度的裸 cvector」。
;; 命名：[Racket 传统]（->f32vector / …）。CPU 侧以 Racket 风格优先，
;; 暂不出 GLSL 风格 rename（后面再定）。
;; ============================================================

(require ffi/vector "cvector.rkt" "buffer.rkt")

(provide ->f32vector ->f64vector ->s32vector ->u32vector)

(define (real->int who x)
  (cond [(exact-integer? x) x]
        [(real? x) (inexact->exact (truncate x))]
        [else (error who "不能转成整数：~s" x)]))

(define (->f32vector x)
  (cond [(vec-buffer? x) (vec-buffer-data x)]
        [(f32vector? x) x]
        [(f64vector? x) (list->f32vector (f64vector->list x))]
        [(s32vector? x) (list->f32vector (map exact->inexact (s32vector->list x)))]
        [(u32vector? x) (list->f32vector (map exact->inexact (u32vector->list x)))]
        [else (error '->f32vector "不能转成 f32vector：~s" x)]))

(define (->f64vector x)
  (cond [(vec-buffer? x) (list->f64vector (map exact->inexact (f32vector->list (vec-buffer-data x))))]
        [(f64vector? x) x]
        [(f32vector? x) (list->f64vector (map exact->inexact (f32vector->list x)))]
        [(s32vector? x) (list->f64vector (map exact->inexact (s32vector->list x)))]
        [(u32vector? x) (list->f64vector (map exact->inexact (u32vector->list x)))]
        [else (error '->f64vector "不能转成 f64vector：~s" x)]))

(define (->s32vector x)
  (define (from lst) (list->s32vector (map (lambda (y) (real->int '->s32vector y)) lst)))
  (cond [(vec-buffer? x) (from (f32vector->list (vec-buffer-data x)))]
        [(s32vector? x) x]
        [(f32vector? x) (from (f32vector->list x))]
        [(f64vector? x) (from (f64vector->list x))]
        [(u32vector? x) (from (u32vector->list x))]
        [else (error '->s32vector "不能转成 s32vector：~s" x)]))

(define (->u32vector x)
  (define (from lst)
    (list->u32vector (map (lambda (y)
                            (define i (real->int '->u32vector y))
                            (when (negative? i) (error '->u32vector "负值不能转成 uint：~s" y))
                            i)
                          lst)))
  (cond [(vec-buffer? x) (from (f32vector->list (vec-buffer-data x)))]
        [(u32vector? x) x]
        [(f32vector? x) (from (f32vector->list x))]
        [(f64vector? x) (from (f64vector->list x))]
        [(s32vector? x) (from (s32vector->list x))]
        [else (error '->u32vector "不能转成 u32vector：~s" x)]))
