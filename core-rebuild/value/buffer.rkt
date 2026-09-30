#lang racket/base

;; ============================================================
;; 值层 · value/buffer.rkt —— 拼接 + 顶点缓冲
;;
;; 「逻辑：把若干 cvector 拼成连续缓冲 / n 个同型向量的 CPU 形状」。
;; 不调用任何 GL（纯 CPU 数据），命名：[Racket 传统]。
;; GLSL 名（gl-vec/… 、concat-vecs）在 rename-buffer.rkt。
;; ============================================================

(require ffi/vector)

(provide concat-vectors concat-vectors! concat-dvectors concat-dvectors!
         vec-buffer vec-buffer? vec-buffer-width vec-buffer-data
         vec-buffer-from make-vec-buffer
         vec-buffer-count vec-buffer-ref vec-buffer-set!)

;; ---------- 拼接 ----------

;; 通用原地拼接：把若干同型 cvector 依次写进 dst（从下标 0 起），返回元素数。
(define (concat-cvector! get-len get-ref cset! dst vs)
  (define i 0)
  (for ([v vs])
    (for ([j (in-range (get-len v))])
      (cset! dst i (get-ref v j))
      (set! i (add1 i))))
  i)

(define (concat-vectors! dst vs) (concat-cvector! f32vector-length f32vector-ref f32vector-set! dst vs))
(define (concat-dvectors! dst vs) (concat-cvector! f64vector-length f64vector-ref f64vector-set! dst vs))

;; 静态：拼成一块新缓冲（只分配输出这一块）
(define (concat-cvector get-len get-ref cset! make vs)
  (define out (make (for/sum ([v vs]) (get-len v)) 0.0))
  (concat-cvector! get-len get-ref cset! out vs)
  out)

(define (concat-vectors . vs) (concat-cvector f32vector-length f32vector-ref f32vector-set! make-f32vector vs))
(define (concat-dvectors . vs) (concat-cvector f64vector-length f64vector-ref f64vector-set! make-f64vector vs))

;; ---------- 顶点缓冲：n 个同型向量 ----------

;; 内部结构：一个 f32vector + 每个向量的宽度（分量数）。对应 GLSL 的 vec2[N]/vec3[N]。
(struct vec-buffer (data width) #:transparent)

;; 静态：从若干同宽向量构造
(define (vec-buffer-from vs)
  (unless (pair? vs) (error 'vec-buffer-from "至少给一个向量"))
  (define w (f32vector-length (car vs)))
  (for ([v (cdr vs)])
    (unless (= (f32vector-length v) w)
      (error 'vec-buffer-from "所有向量宽度须一致，实际 ~a 与 ~a" w (f32vector-length v))))
  (define data (make-f32vector (* w (length vs)) 0.0))
  (concat-vectors! data vs)
  (vec-buffer data w))

;; 动态：预分配 n 个同型向量（都填 template），之后 vec-buffer-set! 原地覆写
(define (make-vec-buffer n template)
  (unless (and (exact? n) (integer? n) (>= n 0))
    (error 'make-vec-buffer "n 应为非负整数，实际 ~s" n))
  (define w (f32vector-length template))
  (define data (make-f32vector (* n w) 0.0))
  (for ([i (in-range n)])
    (for ([j (in-range w)])
      (f32vector-set! data (+ (* i w) j) (f32vector-ref template j))))
  (vec-buffer data w))

(define (vec-buffer-count v) (quotient (f32vector-length (vec-buffer-data v)) (vec-buffer-width v)))

(define (vec-buffer-ref v i)
  (define w (vec-buffer-width v))
  (define data (vec-buffer-data v))
  (define out (make-f32vector w 0.0))
  (for ([j (in-range w)])
    (f32vector-set! out j (f32vector-ref data (+ (* i w) j))))
  out)

(define (vec-buffer-set! v i w)
  (define width (vec-buffer-width v))
  (unless (= (f32vector-length w) width)
    (error 'vec-buffer-set! "宽度不匹配：期望 ~a，实际 ~a" width (f32vector-length w)))
  (define data (vec-buffer-data v))
  (for ([j (in-range width)])
    (f32vector-set! data (+ (* i width) j) (f32vector-ref w j))))
