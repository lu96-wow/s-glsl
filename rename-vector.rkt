#lang racket/base

;; ============================================================
;; rename-vector.rkt —— GLSL 类型名 ↔ ffi/vector 命名桥
;;
;; 目的：shader 里写 (in vec3 aPos)，CPU 侧也用 vec3 这个名字构造数据；
;;       顺带消掉 glVertexAttribPointer 的 stride/offset 魔法数字。
;;
;; 边界：
;;   - 只做"数据命名桥"，不重实现 GLSL 数学。矩阵计算仍在 lib.rkt 的 m4-*（f64vector）。
;;   - 只覆盖"CPU 有数据表示"的类型：vec/ivec/uvec/bvec/mat。
;;     sampler*/image*/atomic_uint 没有 CPU 向量，不在本模块。
;;   - 标量（float/int/uint/bool）直接就是 Racket 数，不重定义，避免遮蔽 Racket 内置。
;;   - 列主序约定：GLSL mat 与 lib.rkt 的 f64vector[16] 都是列主序，直接转、不转置。
;;   - GLSL bool 在内存是 32 位：bvec 映射到 u32vector（0/1）。
;;
;; 显式输入检查（不隐式转换）：
;;   - float 构造器要求 flonum（如 1.0）；整数/有理数直接报错，由调用方写 1.0。
;;     （依据：ffi/vector 的 f32vector 走 _float ctype，本就不收精确数——
;;      隐式 exact->inexact 反而掩盖了这一点。）
;;   - int/uint 构造器要求精确整数。
;; ============================================================

(require ffi/vector)

(provide (all-from-out ffi/vector)
         ;; 向量构造器（元数由 Racket 自身 arity 保证）
         vec2 vec3 vec4
         ivec2 ivec3 ivec4
         uvec2 uvec3 uvec4
         bvec2 bvec3 bvec4
         ;; 矩阵构造器（全形式分派）
         mat2 mat3 mat4
         ;; 尺寸 / 步长帮助
         glsl-size glsl-byte-size glsl-stride glsl-type-table)

;; ---------- 输入检查 ----------

(define (check-float who x)
  (unless (flonum? x)
    (error who "参数应为浮点（如 1.0，不要整数/有理数），实际 ~s" x))
  x)

(define (check-int who x)
  (unless (and (exact? x) (integer? x))
    (error who "参数应为整数，实际 ~s" x))
  x)

;; ---------- 向量 ----------

(define (vec2 x y) (f32vector (check-float 'vec2 x) (check-float 'vec2 y)))
(define (vec3 x y z) (f32vector (check-float 'vec3 x) (check-float 'vec3 y) (check-float 'vec3 z)))
(define (vec4 x y z w) (f32vector (check-float 'vec4 x) (check-float 'vec4 y) (check-float 'vec4 z) (check-float 'vec4 w)))

(define (ivec2 x y) (s32vector (check-int 'ivec2 x) (check-int 'ivec2 y)))
(define (ivec3 x y z) (s32vector (check-int 'ivec3 x) (check-int 'ivec3 y) (check-int 'ivec3 z)))
(define (ivec4 x y z w) (s32vector (check-int 'ivec4 x) (check-int 'ivec4 y) (check-int 'ivec4 z) (check-int 'ivec4 w)))

(define (uvec2 x y) (u32vector (check-int 'uvec2 x) (check-int 'uvec2 y)))
(define (uvec3 x y z) (u32vector (check-int 'uvec3 x) (check-int 'uvec3 y) (check-int 'uvec3 z)))
(define (uvec4 x y z w) (u32vector (check-int 'uvec4 x) (check-int 'uvec4 y) (check-int 'uvec4 z) (check-int 'uvec4 w)))

;; bool → 0/1：#f 或 0 → 0，其余（#t / 非零数）→ 1
(define (->bool x)
  (cond
    [(boolean? x) (if x 1 0)]
    [(number? x) (if (zero? x) 0 1)]
    [else (error 'bvec "元素应为 #t/#f 或数字，实际 ~s" x)]))

(define (bvec2 x y) (u32vector (->bool x) (->bool y)))
(define (bvec3 x y z) (u32vector (->bool x) (->bool y) (->bool z)))
(define (bvec4 x y z w) (u32vector (->bool x) (->bool y) (->bool z) (->bool w)))

;; ---------- 矩阵（通用分派） ----------

;; 列向量 → list（f32vector/f64vector/list，长度须为 n）
(define (col->list who c n)
  (cond
    [(f32vector? c)
     (unless (= (f32vector-length c) n)
       (error who "列向量长度应为 ~a，实际 ~a" n (f32vector-length c)))
     (f32vector->list c)]
    [(f64vector? c)
     (unless (= (f64vector-length c) n)
       (error who "列向量长度应为 ~a，实际 ~a" n (f64vector-length c)))
     (f64vector->list c)]
    [(list? c)
     (unless (= (length c) n)
       (error who "列向量长度应为 ~a，实际 ~a" n (length c)))
     (map (lambda (x) (check-float who x)) c)]
    [else (error who "列应为 f32vector/f64vector/list，实际 ~s" c)]))

;; 对角矩阵（列主序展开）
(define (diag-list who n x)
  (define f (check-float who x))
  (for*/list ([c (in-range n)] [r (in-range n)])
    (if (= r c) f 0.0)))

;; 通用矩阵构造：who=mat2/mat3/mat4，n=2/3/4，args=构造参数
;;   (mat 1 标量)         → 对角
;;   (mat f32/f64[n*n])   → 拷贝 / f64→f32
;;   (mat n 个列向量)      → 拼列
;;   (mat n*n 个标量)      → 列主序
;;   零元或其它 → 报错（对齐 GLSL）
(define (make-mat who n args)
  (define total (* n n))
  (cond
    [(null? args)
     (error who "mat~a() 在 GLSL 中是未初始化，不支持零参数构造" n)]
    [(= (length args) 1)
     (define x (car args))
     (cond
       [(number? x) (apply f32vector (diag-list who n x))]
       [(and (f32vector? x) (= (f32vector-length x) total))
        (apply f32vector (f32vector->list x))]
       [(and (f64vector? x) (= (f64vector-length x) total))
        (apply f32vector (f64vector->list x))]
       [else (error who "mat~a 单参数应为标量或长度 ~a 的 f32/f64 向量，实际 ~s" n total x)])]
    [(= (length args) n)
     (apply f32vector (apply append (map (lambda (c) (col->list who c n)) args)))]
    [(= (length args) total)
     (apply f32vector (map (lambda (x) (check-float who x)) args))]
    [else
     (error who "mat~a 参数个数应为 1（对角/拷贝）、~a（列向量）或 ~a（标量），实际 ~a"
            n n total (length args))]))

(define (mat2 . args) (make-mat 'mat2 2 args))
(define (mat3 . args) (make-mat 'mat3 3 args))
(define (mat4 . args) (make-mat 'mat4 4 args))

;; ---------- 尺寸 / 步长 ----------

;; GLSL 类型名 → 元素数（CPU 有数据表示的类型）
(define glsl-type-table
  '((vec2 . 2)  (vec3 . 3)  (vec4 . 4)
    (ivec2 . 2) (ivec3 . 3) (ivec4 . 4)
    (uvec2 . 2) (uvec3 . 3) (uvec4 . 4)
    (bvec2 . 2) (bvec3 . 3) (bvec4 . 4)
    (mat2 . 4)  (mat3 . 9)  (mat4 . 16)))

(define (glsl-size t)
  (define e (assq t glsl-type-table))
  (unless e (error 'glsl-size "未知 GLSL 类型（或无可表示的 CPU 类型）：~s" t))
  (cdr e))

;; 元素数 × 4（float/int/uint/bool 都是 4 字节）
(define (glsl-byte-size t) (* 4 (glsl-size t)))

;; 交错属性总元素数（stride 用；字节 = (* 4 (glsl-stride ...))）
(define (glsl-stride . types)
  (apply + (map glsl-size types)))
