#lang racket/base

;; ============================================================
;; vec-math.rkt —— CPU 侧对 GLSL 向量/矩阵的「取用 + 运算」层
;;
;; 定位：
;;   - rename-vector.rkt  = 定义（构造）+ 数据布局（size/stride/pack）
;;   - vec-math.rkt       = 取用（读/写/运算 = GLSL 内建镜像），本文件
;;   - transform.rkt      = 常用变换构造（look-at/perspective/… 场景约定），在 vec-math 之上
;;
;; 原理：
;;   ① 数据面不变：值仍是裸 ffi cvector（f32/f64/s32/u32vector），零拷贝、可直接上传。
;;   ② 取用面是纯函数，不带类型标签。形状规则：
;;        - 向量宽度 = cvector 长度（自动）→ 向量运算泛型；
;;        - 矩阵阶 = 名字里的数字（mat4-*）→ 矩阵运算按类型命名。
;;   ③ 精度规则：同类进同类出；跨精度/跨类报错，不做隐式提升。
;;   ④ GLSL 语义优先：矩阵列主序、m[col][row]、逐分量 *；不引入 Racket 隐式转换。
;;   ⑤ 命名（详见 racket-glsl/NAMING.md）：
;;        - 向量用 v* 前缀（vref/vadd/vdot…）：和 gl-vec-*（缓冲类型）区分开；
;;        - 矩阵用 matN-/dmatN- 前缀（阶写进名字，运行期推不出来）；
;;        - 裸 GLSL 名（length/abs/min/…）会撞 racket/base，故一律加前缀。
;; ============================================================

(require ffi/vector
         "rename-vector.rkt"      ; gl-vec? / gl-vec->f32vector（unwrap gl-vec 用）
         (for-syntax racket/base   ; 宏体 phase 1：syntax-case / #%app
                     racket/syntax)) ; format-id

(provide
 ;; 分量 / 形状
 vcount vref vset! vx vy vz vw vmap
 ;; 逐分量算术（含 int 族）
 vadd vsub vmul vdiv vneg vabs vmin vmax vfloor vceil vfract vmod
 ;; 幂 / 指 / 三角（仅 float/double）
 vsqrt vpow vexp vlog vsin vcos vtan vradians vdegrees
 ;; 几何（仅 float/double）
 vdot vcross vlength vdistance vnormalize vmix vclamp vstep vsmoothstep
 vreflect vrefract vfaceforward
 ;; 位运算（仅 int 族）
 vand vor vxor vnot vshl vshr
 ;; 转换 / unwrap
 ->f32vector ->f64vector ->s32vector ->u32vector)

;; ---------- kind 分派 ----------

(define (kind-of v who)
  (cond [(f32vector? v) 'f32] [(f64vector? v) 'f64]
        [(s32vector? v) 's32] [(u32vector? v) 'u32]
        [else (error who "需要向量（f32/f64/s32/u32vector），实际 ~s" v)]))

(define (kind-make k)
  (case k [(f32) f32vector] [(f64) f64vector] [(s32) s32vector] [(u32) u32vector]))
(define (kind-ref* k)
  (case k [(f32) f32vector-ref] [(f64) f64vector-ref] [(s32) s32vector-ref] [(u32) u32vector-ref]))
(define (kind-set* k)
  (case k [(f32) f32vector-set!] [(f64) f64vector-set!] [(s32) s32vector-set!] [(u32) u32vector-set!]))
(define (kind-len* k)
  (case k [(f32) f32vector-length] [(f64) f64vector-length] [(s32) s32vector-length] [(u32) u32vector-length]))
(define (kind-float? k) (or (eq? k 'f32) (eq? k 'f64)))
(define (kind-int? k) (or (eq? k 's32) (eq? k 'u32)))
(define (kind-name k) (symbol->string k))

(define (check-scalar who k s)
  (cond [(kind-float? k) (unless (flonum? s)
                           (error who "标量应为浮点数（如 1.0），实际 ~s" s))]
        [else (unless (and (exact? s) (integer? s))
                (error who "标量应为精确整数，实际 ~s" s))])
  s)

;; ---------- 分量 / 形状 ----------

(define (vcount v) ((kind-len* (kind-of v 'vcount)) v))
(define (vref v i) ((kind-ref* (kind-of v 'vref)) v i))
(define (vset! v i x) ((kind-set* (kind-of v 'vset!)) v i x))
(define (vx v) (vref v 0))
(define (vy v) (vref v 1))
(define (vz v) (vref v 2))
(define (vw v) (vref v 3))

;; 逐分量应用任意函数（逃生舱）。结果类型同输入，f 的返回值须匹配该 cvector 的元素类型。
(define (vmap f v)
  (define k (kind-of v 'vmap))
  (define n ((kind-len* k) v))
  (define ref (kind-ref* k))
  (apply (kind-make k) (for/list ([i (in-range n)]) (f (ref v i)))))

;; ---------- 逐分量内部原语 ----------

(define (v-map1 who f v)
  (define k (kind-of v who))
  (define n ((kind-len* k) v))
  (define ref (kind-ref* k))
  (apply (kind-make k) (for/list ([i (in-range n)]) (f (ref v i)))))

(define (v-map2 who f a b)
  (define ka (kind-of a who))
  (define kb (kind-of b who))
  (unless (eq? ka kb) (error who "两个向量精度/类别不同：~a vs ~a" (kind-name ka) (kind-name kb)))
  (define n ((kind-len* ka) a))
  (unless (= n ((kind-len* kb) b)) (error who "向量长度不同：~a vs ~a" n ((kind-len* kb) b)))
  (define ra (kind-ref* ka))
  (define rb (kind-ref* kb))
  (apply (kind-make ka) (for/list ([i (in-range n)]) (f (ra a i) (rb b i)))))

(define (v-map3 who f a b c)
  (define ka (kind-of a who))
  (unless (and (eq? ka (kind-of b who)) (eq? ka (kind-of c who)))
    (error who "三个向量精度/类别不同"))
  (define n ((kind-len* ka) a))
  (unless (and (= n ((kind-len* ka) b)) (= n ((kind-len* ka) c)))
    (error who "向量长度不同"))
  (define ra (kind-ref* ka))
  (apply (kind-make ka) (for/list ([i (in-range n)]) (f (ra a i) (ra b i) (ra c i)))))

(define (v-map-num-r who f v s)          ; v op s
  (define k (kind-of v who))
  (check-scalar who k s)
  (define n ((kind-len* k) v))
  (define ref (kind-ref* k))
  (apply (kind-make k) (for/list ([i (in-range n)]) (f (ref v i) s))))

(define (v-map-num-l who f s v)          ; s op v
  (define k (kind-of v who))
  (check-scalar who k s)
  (define n ((kind-len* k) v))
  (define ref (kind-ref* k))
  (apply (kind-make k) (for/list ([i (in-range n)]) (f s (ref v i)))))

;; ---------- 逐分量算术 ----------

(define (vadd a b) (v-map2 'vadd + a b))
(define (vsub a b) (v-map2 'vsub - a b))
(define (vmul a b)
  (cond [(number? a) (v-map-num-l 'vmul * a b)]
        [(number? b) (v-map-num-r 'vmul * a b)]
        [else (v-map2 'vmul * a b)]))
(define (vdiv a b)
  (define (op k) (if (kind-int? k) quotient /))
  (cond [(number? a) (v-map-num-l 'vdiv (op (kind-of b 'vdiv)) a b)]
        [(number? b) (v-map-num-r 'vdiv (op (kind-of a 'vdiv)) a b)]
        [else (v-map2 'vdiv (op (kind-of a 'vdiv)) a b)]))
(define (vneg v) (v-map1 'vneg - v))
(define (vabs v) (v-map1 'vabs abs v))
(define (vfloor v) (v-map1 'vfloor floor v))
(define (vceil v) (v-map1 'vceil ceiling v))
(define (vfract v) (v-map1 'vfract (lambda (x) (- x (floor x))) v))
(define (float-mod x y) (- x (* y (floor (/ x y)))))
(define (vmod a b)
  (define (op k) (if (kind-int? k) modulo float-mod))
  (cond [(number? b) (v-map-num-r 'vmod (op (kind-of a 'vmod)) a b)]
        [else (v-map2 'vmod (op (kind-of a 'vmod)) a b)]))
(define (vmin a b)
  (cond [(number? b) (v-map-num-r 'vmin min a b)] [else (v-map2 'vmin min a b)]))
(define (vmax a b)
  (cond [(number? b) (v-map-num-r 'vmax max a b)] [else (v-map2 'vmax max a b)]))

;; ---------- 幂 / 指 / 三角（仅 float/double）----------

(define (require-float who v)
  (define k (kind-of v who))
  (unless (kind-float? k) (error who "只对 float/double 向量有意义，实际 ~a" (kind-name k)))
  v)

(define (vsqrt v)    (require-float 'vsqrt v)    (v-map1 'vsqrt sqrt v))
(define (vpow a b)   (require-float 'vpow a)     (if (number? b) (v-map-num-r 'vpow expt a b) (v-map2 'vpow expt a b)))
(define (vexp v)     (require-float 'vexp v)     (v-map1 'vexp exp v))
(define (vlog v)     (require-float 'vlog v)     (v-map1 'vlog log v))
(define (vsin v)     (require-float 'vsin v)     (v-map1 'vsin sin v))
(define (vcos v)     (require-float 'vcos v)     (v-map1 'vcos cos v))
(define (vtan v)     (require-float 'vtan v)     (v-map1 'vtan tan v))
(define (vradians v) (require-float 'vradians v) (v-map1 'vradians (lambda (x) (* x (/ (acos -1.0) 180.0))) v))
(define (vdegrees v) (require-float 'vdegrees v) (v-map1 'vdegrees (lambda (x) (* x (/ 180.0 (acos -1.0)))) v))

;; ---------- 几何 ----------

(define (vdot a b)
  (require-float 'vdot a)
  (define k (kind-of a 'vdot))
  (unless (eq? k (kind-of b 'vdot)) (error 'vdot "两个向量类别不同"))
  (define n ((kind-len* k) a))
  (unless (= n ((kind-len* k) b)) (error 'vdot "向量长度不同"))
  (define ref (kind-ref* k))
  (for/sum ([i (in-range n)]) (* (ref a i) (ref b i))))

(define (vlength v) (sqrt (vdot v v)))
(define (vdistance a b) (vlength (vsub a b)))
(define (vnormalize v)
  (define l (vlength v))
  (when (zero? l) (error 'vnormalize "零向量不能归一化"))
  (vdiv v l))

(define (vcross a b)
  (require-float 'vcross a)
  (define k (kind-of a 'vcross))
  (unless (eq? k (kind-of b 'vcross)) (error 'vcross "两个向量类别不同"))
  (unless (and (= ((kind-len* k) a) 3) (= ((kind-len* k) b) 3))
    (error 'vcross "叉积要求 3 分量向量"))
  (define ref (kind-ref* k))
  (apply (kind-make k)
         (list (- (* (ref a 1) (ref b 2)) (* (ref a 2) (ref b 1)))
               (- (* (ref a 2) (ref b 0)) (* (ref a 0) (ref b 2)))
               (- (* (ref a 0) (ref b 1)) (* (ref a 1) (ref b 0))))))

(define (vmix a b t)
  (require-float 'vmix a)
  (cond [(number? t)
         (check-scalar 'vmix (kind-of a 'vmix) t)
         (v-map2 'vmix (lambda (x y) (+ x (* t (- y x)))) a b)]
        [else (v-map3 'vmix (lambda (x y tt) (+ x (* tt (- y x)))) a b t)]))

(define (vclamp v lo hi)
  (cond [(and (number? lo) (number? hi))
         (check-scalar 'vclamp (kind-of v 'vclamp) lo)
         (check-scalar 'vclamp (kind-of v 'vclamp) hi)
         (v-map1 'vclamp (lambda (x) (min (max x lo) hi)) v)]
        [(and (not (number? lo)) (not (number? hi)))
         (v-map3 'vclamp (lambda (x l h) (min (max x l) h)) v lo hi)]
        [else (error 'vclamp "lo/hi 要么都是标量，要么都是向量")]))

(define (vstep e x)
  (require-float 'vstep x)
  (if (number? e)
      (begin (check-scalar 'vstep (kind-of x 'vstep) e)
             (v-map1 'vstep (lambda (y) (if (< y e) 0.0 1.0)) x))
      (v-map2 'vstep (lambda (ee y) (if (< y ee) 0.0 1.0)) e x)))

(define (vsmoothstep e0 e1 x)
  (require-float 'vsmoothstep x)
  (define (ss a b y)
    (define t (min (max (/ (- y a) (- b a)) 0.0) 1.0))
    (* t t (- 3.0 (* 2.0 t))))
  (cond [(and (number? e0) (number? e1))
         (v-map1 'vsmoothstep (lambda (y) (ss e0 e1 y)) x)]
        [(and (not (number? e0)) (not (number? e1)))
         (v-map3 'vsmoothstep ss e0 e1 x)]
        [else (error 'vsmoothstep "e0/e1 要么都是标量，要么都是向量")]))

(define (vreflect i n)
  (require-float 'vreflect i)
  (vsub i (vmul n (* 2.0 (vdot n i)))))

(define (vrefract i n eta)
  (require-float 'vrefract i)
  (define d (vdot n i))
  (define k (- 1.0 (* eta eta (- 1.0 (* d d)))))
  (if (negative? k)
      (v-map1 'vrefract (lambda (_) 0.0) i)
      (vsub (vmul i eta) (vmul n (+ (* eta d) (sqrt k))))))

(define (vfaceforward n i nref)
  (if (< (vdot nref i) 0.0) n (vneg n)))

;; ---------- 位运算（仅 int 族）----------

(define (require-int who v)
  (define k (kind-of v who))
  (unless (kind-int? k) (error who "只对 int/uint 向量有意义，实际 ~a" (kind-name k)))
  v)

(define (vand a b) (require-int 'vand a) (v-map2 'vand bitwise-and a b))
(define (vor a b)  (require-int 'vor a)  (v-map2 'vor  bitwise-ior a b))
(define (vxor a b) (require-int 'vxor a) (v-map2 'vxor bitwise-xor a b))
(define (vnot v)
  (require-int 'vnot v)
  (define k (kind-of v 'vnot))
  (if (eq? k 'u32)
      (v-map1 'vnot (lambda (x) (bitwise-and (bitwise-not x) #xFFFFFFFF)) v)
      (v-map1 'vnot bitwise-not v)))
(define (vshl v s) (require-int 'vshl v) (v-map-num-r 'vshl (lambda (x n) (arithmetic-shift x n)) v s))
(define (vshr v s) (require-int 'vshr v) (v-map-num-r 'vshr (lambda (x n) (arithmetic-shift x (- n))) v s))

;; ============================================================
;; 矩阵：mat2/3/4 + dmat2/3/4（列主序，m[col][row] 存 idx = col*n+row）
;; ============================================================

(define (mat-check who kind m)
  (define k (kind-of m who))
  (unless (eq? k kind)
    (error who "精度不匹配：期望 ~a 矩阵，实际 ~a" (kind-name kind) (kind-name k)))
  kind)

(define (mat-ref/impl who kind n m col row)
  (mat-check who kind m)
  ((kind-ref* kind) m (+ (* col n) row)))

(define (mat-set/impl! who kind n m col row x)
  (mat-check who kind m)
  ((kind-set* kind) m (+ (* col n) row) x))

(define (mat-identity/impl who kind n)
  (apply (kind-make kind)
         (for*/list ([c (in-range n)] [r (in-range n)])
           (if (= c r) 1.0 0.0))))

(define (mat-copy/impl who kind n m)
  (mat-check who kind m)
  (define ref (kind-ref* kind))
  (apply (kind-make kind) (for/list ([i (in-range (* n n))]) (ref m i))))

(define (mat-mul/impl who kind n a b)
  (mat-check who kind a) (mat-check who kind b)
  (define ref (kind-ref* kind))
  (apply (kind-make kind)
         (for*/list ([c (in-range n)] [r (in-range n)])
           (for/fold ([acc 0.0]) ([k (in-range n)])
             (+ acc (* (ref a (+ (* k n) r)) (ref b (+ (* c n) k))))))))

(define (mat-mul-vec/impl who kind n m v)
  (mat-check who kind m)
  (unless (eq? kind (kind-of v who)) (error who "向量精度与矩阵不匹配"))
  (define ref (kind-ref* kind))
  (unless (= n ((kind-len* kind) v)) (error who "向量长度应为 ~a" n))
  (apply (kind-make kind)
         (for/list ([r (in-range n)])
           (for/fold ([acc 0.0]) ([c (in-range n)])
             (+ acc (* (ref m (+ (* c n) r)) (ref v c)))))))

(define (vec-mul-mat/impl who kind n v m)
  (mat-check who kind m)
  (unless (eq? kind (kind-of v who)) (error who "向量精度与矩阵不匹配"))
  (define ref (kind-ref* kind))
  (unless (= n ((kind-len* kind) v)) (error who "向量长度应为 ~a" n))
  (apply (kind-make kind)
         (for/list ([c (in-range n)])
           (for/fold ([acc 0.0]) ([r (in-range n)])
             (+ acc (* (ref v r) (ref m (+ (* c n) r))))))))

(define (mat-add/impl who kind n a b) (mat-check who kind a) (mat-check who kind b) (v-map2 who + a b))
(define (mat-sub/impl who kind n a b) (mat-check who kind a) (mat-check who kind b) (v-map2 who - a b))
(define (mat-neg/impl who kind n m)   (mat-check who kind m) (v-map1 who - m))

(define (mat-transpose/impl who kind n m)
  (mat-check who kind m)
  (define ref (kind-ref* kind))
  (apply (kind-make kind)
         (for*/list ([c (in-range n)] [r (in-range n)]) (ref m (+ (* r n) c)))))

(define (mat-inverse/impl who kind n m)
  (mat-check who kind m)
  (define ref (kind-ref* kind))
  (define rows (make-vector n))
  (for ([r (in-range n)])
    (define v (make-f64vector (* 2 n) 0.0))
    (for ([c (in-range n)]) (f64vector-set! v c (exact->inexact (ref m (+ (* c n) r)))))
    (f64vector-set! v (+ n r) 1.0)
    (vector-set! rows r v))
  (for ([i (in-range n)])
    (define-values (p _)
      (for/fold ([best i] [bestv (abs (f64vector-ref (vector-ref rows i) i))])
                ([r (in-range (add1 i) n)])
        (define v (abs (f64vector-ref (vector-ref rows r) i)))
        (if (> v bestv) (values r v) (values best bestv))))
    (unless (> (abs (f64vector-ref (vector-ref rows p) i)) 1e-12)
      (error who "矩阵不可逆（奇异）"))
    (unless (= p i)
      (define tmp (vector-ref rows i))
      (vector-set! rows i (vector-ref rows p))
      (vector-set! rows p tmp))
    (define piv-row (vector-ref rows i))
    (define piv (f64vector-ref piv-row i))
    (for ([c (in-range (* 2 n))]) (f64vector-set! piv-row c (/ (f64vector-ref piv-row c) piv)))
    (for ([r (in-range n)] #:unless (= r i))
      (define row (vector-ref rows r))
      (define f (f64vector-ref row i))
      (for ([c (in-range (* 2 n))])
        (f64vector-set! row c (- (f64vector-ref row c) (* f (f64vector-ref piv-row c)))))))
  (apply (kind-make kind)
         (for*/list ([c (in-range n)] [r (in-range n)])
           (f64vector-ref (vector-ref rows r) (+ n c)))))

(define (mat-mul-scalar/impl who kind n m s)
  (mat-check who kind m)
  (check-scalar who kind s)
  (define ref (kind-ref* kind))
  (apply (kind-make kind) (for/list ([i (in-range (* n n))]) (* (ref m i) s))))

;; 为 mat2/3/4 + dmat2/3/4 生成上面 13 个操作
(define-syntax (define-mat-ops stx)
  (syntax-case stx ()
    [(_ prefix n kind)
     (with-syntax ([(ref st ident copy mul mul-vec vec-mul add sub neg tr inv muls)
                    (for/list ([s '("ref" "set!" "identity" "copy" "mul" "mul-vec" "vec-mul"
                                    "add" "sub" "neg" "transpose" "inverse" "mul-scalar")])
                      (format-id #'prefix "~a-~a" #'prefix s))])
       #'(begin
           (define (ref m col row) (mat-ref/impl ref (quote kind) n m col row))
           (define (st m col row x) (mat-set/impl! st (quote kind) n m col row x))
           (define (ident) (mat-identity/impl ident (quote kind) n))
           (define (copy m) (mat-copy/impl copy (quote kind) n m))
           (define (mul a b) (mat-mul/impl mul (quote kind) n a b))
           (define (mul-vec m v) (mat-mul-vec/impl mul-vec (quote kind) n m v))
           (define (vec-mul v m) (vec-mul-mat/impl vec-mul (quote kind) n v m))
           (define (add a b) (mat-add/impl add (quote kind) n a b))
           (define (sub a b) (mat-sub/impl sub (quote kind) n a b))
           (define (neg m) (mat-neg/impl neg (quote kind) n m))
           (define (tr m) (mat-transpose/impl tr (quote kind) n m))
           (define (inv m) (mat-inverse/impl inv (quote kind) n m))
           (define (muls m s) (mat-mul-scalar/impl muls (quote kind) n m s))
           (provide ref st ident copy mul mul-vec vec-mul add sub neg tr inv muls)))]))

(define-mat-ops mat2 2 f32)
(define-mat-ops mat3 3 f32)
(define-mat-ops mat4 4 f32)
(define-mat-ops dmat2 2 f64)
(define-mat-ops dmat3 3 f64)
(define-mat-ops dmat4 4 f64)

;; 常用变换（mat4-translate / mat4-rot-x/y/z / mat4-scaling / mat4-ortho /
;; mat4-perspective / mat4-look-at）在 transform.rkt：那是“场景/相机约定”层，
;; 不是 GLSL 内建，故此文件不提供。

;; ============================================================
;; 转换 / unwrap：任意 GLSL 向量 → 指定精度的裸 cvector
;; ============================================================

(define (real->int who x)
  (cond [(exact-integer? x) x]
        [(real? x) (inexact->exact (truncate x))]
        [else (error who "不能转成整数：~s" x)]))

(define (->f32vector x)
  (cond [(gl-vec? x) (gl-vec->f32vector x)]
        [(f32vector? x) x]
        [(f64vector? x) (list->f32vector (f64vector->list x))]
        [(s32vector? x) (list->f32vector (map exact->inexact (s32vector->list x)))]
        [(u32vector? x) (list->f32vector (map exact->inexact (u32vector->list x)))]
        [else (error '->f32vector "不能转成 f32vector：~s" x)]))

(define (->f64vector x)
  (cond [(gl-vec? x) (list->f64vector (map exact->inexact (f32vector->list (gl-vec->f32vector x))))]
        [(f64vector? x) x]
        [(f32vector? x) (list->f64vector (map exact->inexact (f32vector->list x)))]
        [(s32vector? x) (list->f64vector (map exact->inexact (s32vector->list x)))]
        [(u32vector? x) (list->f64vector (map exact->inexact (u32vector->list x)))]
        [else (error '->f64vector "不能转成 f64vector：~s" x)]))

(define (->s32vector x)
  (define (from lst) (list->s32vector (map (lambda (y) (real->int '->s32vector y)) lst)))
  (cond [(gl-vec? x) (from (f32vector->list (gl-vec->f32vector x)))]
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
  (cond [(gl-vec? x) (from (f32vector->list (gl-vec->f32vector x)))]
        [(u32vector? x) x]
        [(f32vector? x) (from (f32vector->list x))]
        [(f64vector? x) (from (f64vector->list x))]
        [(s32vector? x) (from (s32vector->list x))]
        [else (error '->u32vector "不能转成 u32vector：~s" x)]))
