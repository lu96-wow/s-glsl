#lang racket/base

;; ============================================================
;; 值层 · value/rename-buffer.rkt —— GLSL 风格命名（缓冲 / 拼接）
;;
;; 纯 alias：value/buffer.rkt 的 Racket 名 → GLSL 名。零逻辑。
;; gl-vec-* 是「本 DSL 的 CPU 缓冲类型」前缀，不是 OpenGL 函数。
;; ============================================================

(require "buffer.rkt")

(provide gl-vec make-gl-vec gl-vec? gl-vec-width gl-vec-count gl-vec-ref gl-vec-set! gl-vec->f32vector
         concat-vecs concat-vecs! concat-dvecs concat-dvecs!)

(define (gl-vec . vs) (vec-buffer-from vs))
(define make-gl-vec make-vec-buffer)
(define gl-vec? vec-buffer?)
(define gl-vec-width vec-buffer-width)
(define gl-vec-count vec-buffer-count)
(define gl-vec-ref vec-buffer-ref)
(define gl-vec-set! vec-buffer-set!)
(define gl-vec->f32vector vec-buffer-data)

(define concat-vecs concat-vectors)
(define concat-vecs! concat-vectors!)
(define concat-dvecs concat-dvectors)
(define concat-dvecs! concat-dvectors!)
