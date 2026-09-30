#lang racket/base

;; ============================================================
;; 值层 · value/rename-buffer.rkt —— GLSL 风格命名（缓冲 / 拼接）
;;
;; 纯 alias：value/buffer.rkt 的 Racket 名 → GLSL 名。零逻辑。
;; gl-vec-* 是「本 DSL 的 CPU 缓冲类型」前缀，不是 OpenGL 函数。
;; 元素取用的别名（gl-vec-count/ref/set!）在 rename-access.rkt。
;; ============================================================

(require "buffer.rkt")

(provide gl-vec make-gl-vec gl-vec? gl-vec-width gl-vec->f32vector
         concat-vecs concat-vecs! concat-dvecs concat-dvecs!)

(define (gl-vec . vs) (vec-buffer-from vs))
(define make-gl-vec make-vec-buffer)
(define gl-vec? vec-buffer?)
(define gl-vec-width vec-buffer-width)
(define gl-vec->f32vector vec-buffer-data)

(define concat-vecs concat-vectors)
(define concat-vecs! concat-vectors!)
(define concat-dvecs concat-dvectors)
(define concat-dvecs! concat-dvectors!)
