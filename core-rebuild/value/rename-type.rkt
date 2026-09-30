#lang racket/base

;; ============================================================
;; 值层 · value/rename-type.rkt —— GLSL 风格命名（类型与存储）
;;
;; 纯 alias：value/type.rkt 的 Racket 名 → GLSL 名。零逻辑。
;; ============================================================

(require "type.rkt")

(provide glsl-size glsl-kind glsl-byte-size glsl-stride glsl-stride-bytes glsl-type-table)

(define (glsl-size t) (type-elements t))
(define (glsl-kind t) (type-kind t))
(define (glsl-byte-size t) (type-byte-size t))
(define (glsl-stride . ts) (apply + (map type-elements ts)))
(define (glsl-stride-bytes . ts) (apply type-stride ts))

;; 旧的 alist 形状：(类型名 . 元素数)
(define glsl-type-table (map (lambda (e) (cons (car e) (cadr e))) type-table))
