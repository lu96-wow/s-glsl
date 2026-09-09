#lang racket/base
;; 运行：racket racket-glsl/rename-vector-test.rkt
(require rackunit
         "rename-vector.rkt")

;; ffi vector 的 equal? 不比较内容，统一用 ->list 比
(define (lv v) (f32vector->list v))
(define (li v) (s32vector->list v))
(define (lu v) (u32vector->list v))

;; ---------- 向量构造 + 显式输入检查 ----------
(check-equal? (lv (vec3 1.0 2.0 3.0)) '(1.0 2.0 3.0))
(check-exn exn:fail? (lambda () (vec2 1 2)))            ; 整数 → 报错（不隐式转）
(check-exn exn:fail? (lambda () (vec3 1.0 2.0)))        ; 元数不对报错

(check-equal? (li (ivec3 1 2 3)) '(1 2 3))
(check-exn exn:fail? (lambda () (ivec2 1.0 2.0)))       ; 非整数 → 报错
(check-equal? (lu (uvec2 1 2)) '(1 2))

;; bvec：#t/#f 和数字都收，0/#f→0，非 0/#t→1
(check-equal? (lu (bvec3 #t #f #t)) '(1 0 1))
(check-equal? (lu (bvec2 0 5)) '(0 1))

;; ---------- mat：对角 ----------
(check-equal? (lv (mat2 1.0)) '(1.0 0.0 0.0 1.0))
(check-equal? (lv (mat4 2.0))
              '(2.0 0.0 0.0 0.0
                0.0 2.0 0.0 0.0
                0.0 0.0 2.0 0.0
                0.0 0.0 0.0 2.0))

;; ---------- mat：拷贝 / f64→f32 ----------
(check-equal? (lv (mat4 (f32vector 1.0 0.0 0.0 0.0  0.0 1.0 0.0 0.0  0.0 0.0 1.0 0.0  0.0 0.0 0.0 1.0)))
              '(1.0 0.0 0.0 0.0  0.0 1.0 0.0 0.0  0.0 0.0 1.0 0.0  0.0 0.0 0.0 1.0))
(check-equal? (lv (mat4 (f64vector 1.0 0.0 0.0 0.0  0.0 1.0 0.0 0.0  0.0 0.0 1.0 0.0  0.0 0.0 0.0 1.0)))
              '(1.0 0.0 0.0 0.0  0.0 1.0 0.0 0.0  0.0 0.0 1.0 0.0  0.0 0.0 0.0 1.0))

;; ---------- mat：列向量 ----------
(check-equal? (lv (mat2 (vec2 1.0 0.0) (vec2 0.0 1.0)))
              '(1.0 0.0 0.0 1.0))
(check-equal? (lv (mat4 (vec4 1.0 0.0 0.0 0.0) (vec4 0.0 1.0 0.0 0.0)
                        (vec4 0.0 0.0 1.0 0.0) (vec4 0.0 0.0 0.0 1.0)))
              '(1.0 0.0 0.0 0.0  0.0 1.0 0.0 0.0  0.0 0.0 1.0 0.0  0.0 0.0 0.0 1.0))

;; ---------- mat：16 标量（列主序） ----------
(check-equal? (lv (mat4 1.0 0.0 0.0 0.0  0.0 1.0 0.0 0.0  0.0 0.0 1.0 0.0  0.0 0.0 0.0 1.0))
              '(1.0 0.0 0.0 0.0  0.0 1.0 0.0 0.0  0.0 0.0 1.0 0.0  0.0 0.0 0.0 1.0))

;; ---------- mat：非法形式报错 ----------
(check-exn exn:fail? (lambda () (mat4)))                              ; 零元
(check-exn exn:fail? (lambda () (mat4 1.0 2.0 3.0 4.0)))             ; 4 标量（GLSL 也非法）
(check-exn exn:fail? (lambda () (mat4 1 0 0 0  0 1 0 0  0 0 1 0  0 0 0 1))) ; 整数标量
(check-exn exn:fail? (lambda () (mat4 (f32vector 1.0 2.0 3.0))))     ; 长度错

;; ---------- 尺寸 / 步长 ----------
(check-equal? (glsl-size 'vec3) 3)
(check-equal? (glsl-byte-size 'vec3) 12)
(check-equal? (glsl-stride 'vec3 'vec2) 5)
(check-exn exn:fail? (lambda () (glsl-size 'sampler2D)))    ; 无 CPU 表示

(displayln "rename-vector 全部测试通过")
