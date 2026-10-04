#lang racket/base

;; ============================================================
;; 值层 · value/rename-buffer.rkt —— GLSL 风格命名（缓冲 / 拼接）
;;
;; 纯 alias：value/buffer.rkt 的 Racket 名 → GLSL 名。零逻辑。
;; gl-vec-* 是「本 DSL 的 CPU 缓冲类型」前缀，不是 OpenGL 函数。
;; 元素取用的别名（gl-vec-count/ref/set!）在 rename-access.rkt。
;; ============================================================

(require "buffer.rkt")

(provide vec-array make-vec-array vec-array? vec-array-width vec-array-data
         ;; 旧名（deprecated，等价别名，下个大版本删）
         gl-vec make-gl-vec gl-vec? gl-vec-width gl-vec->f32vector
         concat-vecs concat-vecs! concat-dvecs concat-dvecs!)

;; ---------- 新名：CPU 向量数组（vecN[]），不带 gl- ----------
;; vec-buffer 里的 data 本来就是一条 f32vector，所以 vec-array-data 是零拷贝取数据；
;; 需要“转换”（如 f64→f32）时用 convert.rkt 的 ->f32vector。
(define (vec-array . vs) (vec-buffer-from vs))
(define make-vec-array make-vec-buffer)
(define vec-array? vec-buffer?)
(define vec-array-width vec-buffer-width)
(define vec-array-data vec-buffer-data)

;; ---------- 旧名（deprecated，等价别名）----------
(define gl-vec vec-array)
(define make-gl-vec make-vec-array)
(define gl-vec? vec-array?)
(define gl-vec-width vec-array-width)
(define gl-vec->f32vector vec-array-data)

(define concat-vecs concat-vectors)
(define concat-vecs! concat-vectors!)
(define concat-dvecs concat-dvectors)
(define concat-dvecs! concat-dvectors!)
