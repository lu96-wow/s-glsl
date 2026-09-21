#lang racket/base
;; 运行：racket racket-glsl/rename-vector-test.rkt
(require rackunit
         "rename-vector.rkt")

;; ffi vector 的 equal? 不比较内容，统一用 ->list 比
(define (lv v) (f32vector->list v))
(define (ld v) (f64vector->list v))
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

;; ---------- dvec：double 精度向量 ----------
(check-equal? (ld (dvec3 1.0 2.0 3.0)) '(1.0 2.0 3.0))
(check-exn exn:fail? (lambda () (dvec2 1 2)))            ; 整数 → 报错（不隐式转）

;; ---------- 拼装 ----------
(check-equal? (lv (concat-vecs (vec2 -0.5 -0.5) (vec2 0.5 -0.5) (vec2 0.0 0.5)))
              '(-0.5 -0.5 0.5 -0.5 0.0 0.5))
(check-equal? (lv (concat-vecs)) '())
;; 原地拼装：写进预分配 dst，返回元素数
(define dst (make-f32vector 10 0.0))
(check-equal? (concat-vecs! dst (list (vec2 1.0 2.0) (vec3 3.0 4.0 5.0))) 5)
(check-equal? (lv dst) '(1.0 2.0 3.0 4.0 5.0 0.0 0.0 0.0 0.0 0.0))

;; ---------- vec：n 个同型向量 ----------
;; 静态构造 + 访问
(define vn (vec (vec2 -0.5 -0.5) (vec2 0.5 -0.5) (vec2 0.0 0.5)))
(check-true (vec? vn))
(check-equal? (vec-count vn) 3)
(check-equal? (vec-width vn) 2)
(check-equal? (lv (vec->f32vector vn)) '(-0.5 -0.5 0.5 -0.5 0.0 0.5))
(check-equal? (lv (vec-ref vn 1)) '(0.5 -0.5))        ; 函数式读：新切片
;; set! 式写（原地，零分配）
(vec-set! vn 1 (vec2 9.0 9.0))
(check-equal? (lv (vec->f32vector vn)) '(-0.5 -0.5 9.0 9.0 0.0 0.5))
;; 动态构造：预分配 n 个，填 template
(define dn (make-vec 1000 (vec3 0.0 0.0 0.0)))
(check-equal? (vec-count dn) 1000)
(check-equal? (vec-width dn) 3)
(check-equal? (lv (vec-ref dn 999)) '(0.0 0.0 0.0))
(vec-set! dn 0 (vec3 1.0 2.0 3.0))
(check-equal? (lv (vec-ref dn 0)) '(1.0 2.0 3.0))
;; 报错：空 / 宽度不一致 / set! 宽度不匹配
(check-exn exn:fail? (lambda () (vec)))
(check-exn exn:fail? (lambda () (vec (vec2 1.0 2.0) (vec3 1.0 2.0 3.0))))
(check-exn exn:fail? (lambda () (vec-set! vn 0 (vec3 1.0 2.0 3.0))))

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

;; ---------- dmat：double 精度矩阵 ----------
(check-equal? (ld (dmat2 1.0)) '(1.0 0.0 0.0 1.0))
(check-equal? (ld (dmat4 (vec4 1.0 0.0 0.0 0.0) (vec4 0.0 1.0 0.0 0.0)
                         (vec4 0.0 0.0 1.0 0.0) (vec4 0.0 0.0 0.0 1.0)))
              '(1.0 0.0 0.0 0.0  0.0 1.0 0.0 0.0  0.0 0.0 1.0 0.0  0.0 0.0 0.0 1.0))
;; mat↔dmat 互转（精度在 GLSL 名字里，不在 ffi 名字里）
(check-equal? (lv (mat4 (dmat4 2.0)))
              '(2.0 0.0 0.0 0.0  0.0 2.0 0.0 0.0  0.0 0.0 2.0 0.0  0.0 0.0 0.0 2.0))
(check-equal? (ld (dmat4 (mat4 2.0)))
              '(2.0 0.0 0.0 0.0  0.0 2.0 0.0 0.0  0.0 0.0 2.0 0.0  0.0 0.0 0.0 2.0))

;; ---------- 尺寸 / 步长 ----------
(check-equal? (glsl-size 'vec3) 3)
(check-equal? (glsl-byte-size 'vec3) 12)
(check-equal? (glsl-stride 'vec3 'vec2) 5)
(check-equal? (glsl-stride-bytes 'vec3 'vec2) 20)
(check-equal? (glsl-stride-bytes 'vec3 'vec3 'float) 28)   ; 实例数组每行 7 float
(check-equal? (glsl-stride-bytes 'vec3) 12)                 ; 前缀偏移 = 跳过 vec3
;; double 系：分量 8 字节
(check-equal? (glsl-size 'dvec3) 3)
(check-equal? (glsl-byte-size 'dvec3) 24)
(check-equal? (glsl-byte-size 'dmat4) 128)
(check-equal? (glsl-stride-bytes 'vec3 'dvec3) 36)
(check-exn exn:fail? (lambda () (glsl-size 'sampler2D)))    ; 无 CPU 表示

;; ---------- glsl-struct：交错记录 ----------
;; 具名字段（(类型 名字)，与 shader 一致）：生成构造器 / 访问器 / 铺平 / stride / offset / size
(glsl-struct instance
  (vec3 offset)
  (vec3 color)
  (float phase))

(check-true (instance? (instance (vec3 1.0 2.0 3.0) (vec3 4.0 5.0 6.0) 0.5)))
(check-equal? (lv (instance-offset (instance (vec3 1.0 2.0 3.0) (vec3 4.0 5.0 6.0) 0.5)))
              '(1.0 2.0 3.0))
;; 铺平：向量 + 向量 + 标量 → 一条 f32vector（用 f32 里精确可表示的数）
(check-equal? (lv (instance->f32vector
                   (instance (vec3 1.0 2.0 3.0) (vec3 0.5 0.25 0.125) 0.75)))
              '(1.0 2.0 3.0 0.5 0.25 0.125 0.75))
;; 布局从 struct 声明推导
(check-equal? (instance-stride) 28)
(check-equal? (instance-field-offset 'offset) 0)
(check-equal? (instance-field-offset 'color) 12)
(check-equal? (instance-field-offset 'phase) 24)
(check-equal? (instance-field-size 'offset) 3)
(check-equal? (instance-field-size 'color) 3)
(check-equal? (instance-field-size 'phase) 1)
(check-exn exn:fail? (lambda () (instance-field-offset 'nope)))

;; 纯向量字段的 struct（无标量）也能铺平
(glsl-struct vert (vec3 pos) (vec3 nrm))
(check-equal? (lv (vert->f32vector (vert (vec3 1.0 2.0 3.0) (vec3 4.0 5.0 6.0))))
              '(1.0 2.0 3.0 4.0 5.0 6.0))
(check-equal? (vert-stride) 24)
(check-equal? (vert-field-offset 'nrm) 12)

;; 空 struct → 报错
(check-exn exn:fail? (lambda () (eval '(glsl-struct Empty))))

;; ---------- concat-dvecs：double 拼装 ----------
(check-equal? (ld (concat-dvecs (dvec2 1.0 2.0) (dvec3 3.0 4.0 5.0)))
              '(1.0 2.0 3.0 4.0 5.0))
(check-equal? (ld (concat-dvecs)) '())
(define ddst (make-f64vector 6 0.0))
(check-equal? (concat-dvecs! ddst (list (dvec3 1.0 2.0 3.0) (dvec2 4.0 5.0))) 5)
(check-equal? (ld ddst) '(1.0 2.0 3.0 4.0 5.0 0.0))

;; ---------- glsl-struct：double 字段 → ->f64vector ----------
(glsl-struct dparticle
  (dvec3 position)
  (dvec2 velocity)
  (double mass))
(check-equal? (ld (dparticle->f64vector
                   (dparticle (dvec3 1.0 2.0 3.0) (dvec2 0.5 0.25) 0.125)))
              '(1.0 2.0 3.0 0.5 0.25 0.125))
(check-equal? (dparticle-stride) 48)   ; 24 + 16 + 8
(check-equal? (dparticle-field-offset 'position) 0)
(check-equal? (dparticle-field-offset 'velocity) 24)
(check-equal? (dparticle-field-offset 'mass) 40)
(check-equal? (dparticle-field-size 'mass) 1)
(check-exn exn:fail? (lambda () (dparticle-field-offset 'nope)))

;; 混用 float/double 字段 → 宏展开时报错（不是运行时报错）
(check-exn exn:fail? (lambda () (eval '(glsl-struct mixed-vertex (vec3 a) (dvec3 b)))))

(displayln "rename-vector 全部测试通过")
