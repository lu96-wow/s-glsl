#lang racket/base

;; ============================================================
;; rename-vector.rkt —— GLSL 类型名 ↔ ffi/vector 命名桥
;;
;; 目的：shader 里写 (in vec3 aPos)，CPU 侧也用 vec3 这个名字构造数据；
;;       顺带消掉 glVertexAttribPointer 的 stride/offset 魔法数字。
;;
;; 边界：
;;   - 只做"类型别名 + 数据命名桥"：把 GLSL 类型名映射到 ffi/vector 类型；
;;     数学运算不在这里（由教程 lib.rkt 提供，且直接作用于这些别名类型）。
;;   - 覆盖"CPU 有数据表示"的全部 GLSL 向量/矩阵类型：vec/dvec/ivec/uvec/bvec/mat/dmat。
;;     sampler*/image*/atomic_uint 没有 CPU 向量，不在本模块。
;;   - 标量（float/int/uint/bool/double）直接就是 Racket 数，不重定义，避免遮蔽 Racket 内置。
;;   - struct：glsl-struct 把 GLSL 的 struct（具名字段）镜像到 CPU 侧，
;;     一并生成铺平 / stride / offset / size（供 VBO + glVertexAttribPointer 用）。
;;   - 精度/类别对称：pack / glsl-struct 按字段类别决定结果——全 float → f32vector、
;;     全 double → f64vector、全 int/ivec → s32vector、全 uint/uvec/bool/bvec → u32vector；
;;     混合类别（如 vec3 + int）→ u8vector（按字节正确铺开）。只有 float 系与 double
;;     系混用仍报错（沿用原约定）。
;;   - 精度是 GLSL 命名轴上的选择：vec→f32vector，dvec→f64vector。别名透明，
;;     结果是货真价实的 ffi/vector，随时可用 ffi/vector 的 API（本模块已 all-from-out 转发）。
;;   - 列主序约定：GLSL mat/dmat 与 ffi/vector 的列主序展开一致，直接转、不转置。
;;   - GLSL bool 在内存是 32 位：bvec 映射到 u32vector（0/1）。
;;   - 注意：concat-vecs / pack / glsl-size / stride-bytes / field-offsets 属于
;;     "GL 数据上传助手"（glVertexAttribPointer 的布局数学），不是 GLSL 语法；
;;     放在本模块只为"数据桥"一站配齐，概念上要与上面的 GLSL 类型区分开。
;;
;; 显式输入检查（不隐式转换）：
;;   - float 构造器要求 flonum（如 1.0）；整数/有理数直接报错，由调用方写 1.0。
;;     （依据：ffi/vector 的 f32vector 走 _float ctype，本就不收精确数——
;;      隐式 exact->inexact 反而掩盖了这一点。）
;;   - int/uint 构造器要求精确整数。
;; ============================================================

(require ffi/vector)
(require (for-syntax racket/base
                     racket/syntax))

(provide (all-from-out ffi/vector)
         ;; 向量构造器（元数由 Racket 自身 arity 保证）
         vec2 vec3 vec4
         dvec2 dvec3 dvec4
         ivec2 ivec3 ivec4
         uvec2 uvec3 uvec4
         bvec2 bvec3 bvec4
         ;; 矩阵构造器（全形式分派）
         mat2 mat3 mat4
         dmat2 dmat3 dmat4
         ;; 拼装：把多个 vec/dvec（f32vector/f64vector）连成一个连续缓冲
         concat-vecs concat-vecs!
         concat-dvecs concat-dvecs!
         ;; gl-vec：n 个同型向量的缓冲（静态/动态顶点数据）
         gl-vec make-gl-vec gl-vec? gl-vec-count gl-vec-width gl-vec-ref gl-vec-set! gl-vec->f32vector
         ;; GLSL struct：具名字段，与 shader 的 (struct ...) 对齐
         glsl-struct
         ;; 尺寸 / 步长 / 类别帮助
         glsl-size glsl-byte-size glsl-stride glsl-stride-bytes glsl-type-table
         glsl-kind)

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

;; double 精度向量：dvec → f64vector（分量不收窄，保留 f64）
(define (dvec2 x y) (f64vector (check-float 'dvec2 x) (check-float 'dvec2 y)))
(define (dvec3 x y z) (f64vector (check-float 'dvec3 x) (check-float 'dvec3 y) (check-float 'dvec3 z)))
(define (dvec4 x y z w) (f64vector (check-float 'dvec4 x) (check-float 'dvec4 y) (check-float 'dvec4 z) (check-float 'dvec4 w)))

;; ---------- 拼装 ----------

;; 通用原地拼接：把若干同型 cvector 依次写进 dst（从下标 0 开始），返回元素数。
;; get-len / get-ref / cset! 是该 cvector 类型的 长度/读/写 函数——f32、f64 共用这一份循环。
(define (concat-cvector! get-len get-ref cset! dst vs)
  (define i 0)
  (for ([v vs])
    (for ([j (in-range (get-len v))])
      (cset! dst i (get-ref v j))
      (set! i (add1 i))))
  i)

;; 把一串 vec（f32vector）依次写进 dst（原地，从下标 0 开始），返回写入的元素数。
;; 给"每帧重新生成顶点数据"的动态场景：dst 预分配一次、每帧覆写，零额外分配。
;;   (define buf (make-f32vector MAX 0.0))            ; init 时分配一次
;;   (define n (concat-vecs! buf (list (vec2 ...) ...)))  ; 每帧覆写，n = 元素数
;;   (gl-buffer-sub-data gl-array-buffer 0 (* 4 n) buf)   ; 只更新 GPU，不重分配
(define (concat-vecs! dst vs)
  (concat-cvector! f32vector-length f32vector-ref f32vector-set! dst vs))

;; 把多个 vec（f32vector）连成一个**新**连续缓冲（静态数据：拼一次即可）。
;; 例：(concat-vecs (vec2 -0.5 -0.5) (vec2 0.5 -0.5) (vec2 0.0 0.5))
;;     → (f32vector -0.5 -0.5 0.5 -0.5 0.0 0.5)
;; 只分配输出这一块，不经过 list/apply（无参数个数上限）。
;; 注：同宽度的向量请优先用 gl-vec（见下）；本函数主要留给"混合宽度"的交错数据。
(define (concat-vecs . vs)
  (define total (for/sum ([v vs]) (f32vector-length v)))
  (define out (make-f32vector total 0.0))
  (concat-vecs! out vs)
  out)

;; double 版：把多个 dvec（f64vector）连成一个**新**连续缓冲。
;; 给 double 顶点数据（dvec3 位置 / dvec4 齐次坐标等）拼 VBO 用。
(define (concat-dvecs! dst vs)
  (concat-cvector! f64vector-length f64vector-ref f64vector-set! dst vs))

(define (concat-dvecs . vs)
  (define total (for/sum ([v vs]) (f64vector-length v)))
  (define out (make-f64vector total 0.0))
  (concat-dvecs! out vs)
  out)

;; ---------- gl-vec：n 个同型向量的缓冲 ----------
;;
;; 命名归属：gl-vec-* 是「我们封装层」自己的 CPU 缓冲类型，
;; 不是 OpenGL 函数（OpenGL 映射一律是 gl-<动词> ↔ glXxx）。
;; 用全名（gl-vec-ref 而不是 vec-ref）是为了不和 vref/vcount 这些
;; “向量取用”短名产生缩写歧义。
;;
;; 内部结构：一个 f32vector + 每个 vec 的宽度（分量数）。
;; 对应 GLSL 的 vec2[N]/vec3[N]（同宽度向量数组），是"动态数量顶点"的 CPU 形状。
(struct gl-vec-buffer (data width) #:transparent)

(define gl-vec? gl-vec-buffer?)
(define gl-vec-width gl-vec-buffer-width)

;; 静态构造：(gl-vec (vec2 ...) (vec2 ...) ...) —— 若干同型 vec，宽度取第一个、校验其余。
;; 个数 = 你列了几个 vec（不用手写 num）。
(define (gl-vec . vs)
  (unless (pair? vs)
    (error 'gl-vec "至少给一个 vec，如 (gl-vec (vec2 0.0 0.0))"))
  (define w (f32vector-length (car vs)))
  (for ([v (cdr vs)])
    (unless (= (f32vector-length v) w)
      (error 'gl-vec "所有 vec 宽度须一致，实际 ~a 与 ~a" w (f32vector-length v))))
  (define data (make-f32vector (* w (length vs)) 0.0))
  (concat-vecs! data vs)
  (gl-vec-buffer data w))

;; 动态构造：(make-gl-vec 1000 (vec3 0.0 0.0 0.0)) —— 预分配 n 个同型 vec（都填 template）。
;; 之后用 gl-vec-set! 逐帧原地覆写，零分配。
(define (make-gl-vec n template)
  (unless (and (exact? n) (integer? n) (>= n 0))
    (error 'make-gl-vec "n 应为非负整数，实际 ~s" n))
  (define w (f32vector-length template))
  (define data (make-f32vector (* n w) 0.0))
  (for ([i (in-range n)])
    (for ([j (in-range w)])
      (f32vector-set! data (+ (* i w) j) (f32vector-ref template j))))
  (gl-vec-buffer data w))

;; 有多少个 vec
(define (gl-vec-count v) (quotient (f32vector-length (gl-vec-buffer-data v)) (gl-vec-buffer-width v)))

;; 函数式读：返回第 i 个 vec（一个新 f32vector，宽度个分量）
(define (gl-vec-ref v i)
  (define w (gl-vec-buffer-width v))
  (define data (gl-vec-buffer-data v))
  (define out (make-f32vector w 0.0))
  (for ([j (in-range w)])
    (f32vector-set! out j (f32vector-ref data (+ (* i w) j))))
  out)

;; set! 式写：把第 i 个 vec 原地覆写为 w（零分配；w 须同宽）
(define (gl-vec-set! v i w)
  (define width (gl-vec-buffer-width v))
  (unless (= (f32vector-length w) width)
    (error 'gl-vec-set! "宽度不匹配：期望 ~a，实际 ~a" width (f32vector-length w)))
  (define data (gl-vec-buffer-data v))
  (for ([j (in-range width)])
    (f32vector-set! data (+ (* i width) j) (f32vector-ref w j))))

;; 上传：底层 f32vector（零拷贝）
(define (gl-vec->f32vector v) (gl-vec-buffer-data v))

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

;; 通用矩阵构造：name="mat2"/"dmat2"…，n=2/3/4，build=list→f32/f64vector，args=构造参数
;;   (mat 1 标量)         → 对角
;;   (mat f32/f64[n*n])   → 拷贝（mat 收 f64 转 f32；dmat 收 f32 转 f64）
;;   (mat n 个列向量)      → 拼列
;;   (mat n*n 个标量)      → 列主序
;;   零元或其它 → 报错（对齐 GLSL）
(define (make-mat name n build args)
  (define total (* n n))
  (cond
    [(null? args)
     (error name "~a() 在 GLSL 中是未初始化，不支持零参数构造" name)]
    [(= (length args) 1)
     (define x (car args))
     (cond
       [(number? x) (build (diag-list name n x))]
       [(and (f32vector? x) (= (f32vector-length x) total))
        (build (f32vector->list x))]
       [(and (f64vector? x) (= (f64vector-length x) total))
        (build (f64vector->list x))]
       [else (error name "~a 单参数应为标量或长度 ~a 的 f32/f64 向量，实际 ~s" name total x)])]
    [(= (length args) n)
     (build (apply append (map (lambda (c) (col->list name c n)) args)))]
    [(= (length args) total)
     (build (map (lambda (x) (check-float name x)) args))]
    [else
     (error name "~a 参数个数应为 1（对角/拷贝）、~a（列向量）或 ~a（标量），实际 ~a"
            name n total (length args))]))

;; matN → f32vector；dmatN → f64vector（同一个 GLSL 名字，两种精度存储）
(define (mat2 . args) (make-mat "mat2" 2 (lambda (xs) (apply f32vector xs)) args))
(define (mat3 . args) (make-mat "mat3" 3 (lambda (xs) (apply f32vector xs)) args))
(define (mat4 . args) (make-mat "mat4" 4 (lambda (xs) (apply f32vector xs)) args))
(define (dmat2 . args) (make-mat "dmat2" 2 (lambda (xs) (apply f64vector xs)) args))
(define (dmat3 . args) (make-mat "dmat3" 3 (lambda (xs) (apply f64vector xs)) args))
(define (dmat4 . args) (make-mat "dmat4" 4 (lambda (xs) (apply f64vector xs)) args))

;; ---------- 尺寸 / 步长 ----------

;; GLSL 类型名 → 元素数（CPU 有数据表示的类型）。
;; 标量也算 1 个元素；这样 glsl-size 能算含标量的交错布局（如 pos+color+float）。
(define glsl-type-table
  '((float . 1) (int . 1) (uint . 1) (bool . 1) (double . 1)
    (vec2 . 2)  (vec3 . 3)  (vec4 . 4)
    (dvec2 . 2) (dvec3 . 3) (dvec4 . 4)
    (ivec2 . 2) (ivec3 . 3) (ivec4 . 4)
    (uvec2 . 2) (uvec3 . 3) (uvec4 . 4)
    (bvec2 . 2) (bvec3 . 3) (bvec4 . 4)
    (mat2 . 4)  (mat3 . 9)  (mat4 . 16)
    (dmat2 . 4) (dmat3 . 9) (dmat4 . 16)))

(define (glsl-size t)
  (define e (assq t glsl-type-table))
  (unless e (error 'glsl-size "未知 GLSL 类型（或无可表示的 CPU 类型）：~s" t))
  (cdr e))

;; 精度判断：double 族（double/dvec*/dmat*）→ f64；float 族 → f32。
;; 一处定义、三处用：glsl-component-bytes / pack / glsl-struct（宏在编译期，
;; 用下面同名的 define-for-syntax 常量）。
;; 存储类别（宏展开期用；与运行期 glsl-kind 保持一致）
(define-for-syntax (kind-of-type t)
  (case t
    [(float vec2 vec3 vec4 mat2 mat3 mat4) 'f32]
    [(double dvec2 dvec3 dvec4 dmat2 dmat3 dmat4) 'f64]
    [(int ivec2 ivec3 ivec4) 's32]
    [(uint uvec2 uvec3 uvec4 bool bvec2 bvec3 bvec4) 'u32]
    [else (error 'glsl-struct "未知 GLSL 类型（或无 CPU 表示）：~s" t)]))

(define double-family '(double dvec2 dvec3 dvec4 dmat2 dmat3 dmat4))
(define (double-type? t) (and (memq t double-family) #t))

;; 每个分量占几字节：float/int/uint/bool 系 = 4；double 系 = 8
(define (glsl-component-bytes t)
  (if (double-type? t) 8 4))

;; ---------- 存储类别 ----------
;; 每个有 CPU 表示的 GLSL 类型归到一个“存储类别”，决定字节怎么写、打包成哪种向量：
;;   f32 → float/vec*/mat*        （f32vector）
;;   f64 → double/dvec*/dmat*     （f64vector）
;;   s32 → int/ivec*              （s32vector）
;;   u32 → uint/uvec*/bool/bvec*  （u32vector；GLSL bool 在内存是 32 位 0/1）
(define (glsl-kind t)
  (case t
    [(float vec2 vec3 vec4 mat2 mat3 mat4) 'f32]
    [(double dvec2 dvec3 dvec4 dmat2 dmat3 dmat4) 'f64]
    [(int ivec2 ivec3 ivec4) 's32]
    [(uint uvec2 uvec3 uvec4 bool bvec2 bvec3 bvec4) 'u32]
    [else (error 'glsl-kind "未知 GLSL 类型（或无 CPU 表示）：~s" t)]))

;; 类别 → 分量字节数 / 向量谓词 / 长度 / 读 / 构造器 / 名字
(define (kind-component-bytes k) (if (eq? k 'f64) 8 4))
(define (kind-vector? k)
  (case k [(f32) f32vector?] [(f64) f64vector?] [(s32) s32vector?] [(u32) u32vector?]))
(define (kind-length k)
  (case k [(f32) f32vector-length] [(f64) f64vector-length] [(s32) s32vector-length] [(u32) u32vector-length]))
(define (kind-ref k)
  (case k [(f32) f32vector-ref] [(f64) f64vector-ref] [(s32) s32vector-ref] [(u32) u32vector-ref]))
(define (kind-ctor k)
  (case k [(f32) f32vector] [(f64) f64vector] [(s32) s32vector] [(u32) u32vector]))
(define (kind->name k)
  (case k [(f32) "f32vector"] [(f64) "f64vector"] [(s32) "s32vector"] [(u32) "u32vector"]))

;; 分量 → 本机字节序的字节串（GL 直接吃本机字节序）
(define (component->bytes kind x)
  (case kind
    [(f32) (real->floating-point-bytes x 4 (system-big-endian?))]
    [(f64) (real->floating-point-bytes x 8 (system-big-endian?))]
    [(s32) (integer->integer-bytes x 4 #t (system-big-endian?))]
    [(u32) (integer->integer-bytes x 4 #f (system-big-endian?))]))

;; 元素数 × 分量字节数
(define (glsl-byte-size t) (* (glsl-size t) (glsl-component-bytes t)))

;; 交错属性总元素数（stride 用）
(define (glsl-stride . types)
  (apply + (map glsl-size types)))

;; 交错属性的字节步长：若干类型依次排开后的总字节数。
;; 用法（glVertexAttribPointer 的 stride/offset）：
;;   stride = (glsl-stride-bytes 'vec3 'vec3)      ; 位置+法线交错 = 24 字节
;;   offset = (glsl-stride-bytes 'vec3)            ; 第 2 个属性跳过前面 12 字节
;; 同一函数既算"步长"也算"前缀偏移"，消除手写字节魔法数字。
(define (glsl-stride-bytes . types)
  (apply + (map glsl-byte-size types)))

;; 一个字段值 → 分量列表（长度 = glsl-size t），同时做类型/长度检查。
(define (field->components who t f)
  (define kind (glsl-kind t))
  (define n (glsl-size t))
  (define (scalar x)
    (case kind
      [(f32 f64) (check-float who x)]
      [(s32)     (check-int who x)]
      [(u32)     (if (eq? t 'bool)
                     (->bool x)                      ; bool：收 #t/#f/数字
                     (begin (check-int who x)
                            (when (negative? x)
                              (error who "uint 分量不能为负：~s" x))
                            x))]))
  (cond
    [(= n 1) (list (scalar f))]
    [else
     (define v? (kind-vector? kind))
     (unless (v? f)
       (error who "字段 ~s 应为长度 ~a 的 ~a，实际 ~s" t n (kind->name kind) f))
     (define len (kind-length kind))
     (unless (= (len f) n)
       (error who "字段 ~s 应为长度 ~a 的 ~a，实际长度 ~a" t n (kind->name kind) (len f)))
     (define ref (kind-ref kind))
     (for/list ([j (in-range n)]) (ref f j))]))

;; 低层原语：按类型清单把字段值铺成一条交错的记录（标量字段直接给数）。
;; 一般不要直接用——用 glsl-struct（具名字段）表达交错记录，它内部调 pack。
;;
;; 结果类型由各字段的存储类别决定：
;;   全 f32                         → f32vector
;;   全 f64                         → f64vector
;;   全 s32（int/ivec*）            → s32vector
;;   全 u32（uint/uvec*/bool/bvec*）→ u32vector
;;   混合类别（如 vec3 + int）      → u8vector（按字节正确铺开）
;;   float 系与 double 系混用       → 报错（沿用原约定）
(define (pack types . fields)
  (unless (= (length types) (length fields))
    (error 'pack "字段数与类型清单不一致：~a 个字段 vs ~a 个类型" (length fields) (length types)))
  (when (null? types) (error 'pack "至少要一个字段"))
  (define kinds (map glsl-kind types))
  (when (and (memq 'f32 kinds) (memq 'f64 kinds))
    (error 'pack "交错缓冲不能混用 float/double 精度：~s" types))
  (define comps (for/list ([t (in-list types)] [f (in-list fields)])
                  (field->components 'pack t f)))
  (cond
    [(andmap (lambda (k) (eq? k (car kinds))) kinds)
     (apply (kind-ctor (car kinds)) (apply append comps))]
    [else
     ;; 混合类别 → u8vector：逐字段按类别写正确字节
     (define out (make-u8vector (apply + (map glsl-byte-size types)) 0))
     (for/fold ([off 0]) ([t (in-list types)] [cs (in-list comps)])
       (define kind (glsl-kind t))
       (define bs (kind-component-bytes kind))
       (for ([x (in-list cs)] [j (in-naturals)])
         (for ([b (in-bytes (component->bytes kind x))] [k (in-naturals)])
           (u8vector-set! out (+ off (* j bs) k) b)))
       (+ off (* (length cs) bs)))
     out]))

;; 低层原语：交错布局里每个字段的字节偏移（glsl-struct 内部用）：
;;   (glsl-field-offsets '(vec3 vec3 float)) → '(0 12 24)
(define (glsl-field-offsets types)
  (let loop ([ts types] [off 0] [acc '()])
    (if (null? ts)
        (reverse acc)
        (loop (cdr ts) (+ off (glsl-byte-size (car ts))) (cons off acc)))))

;; ============================================================
;; GLSL struct：把 shader 里的 struct 镜像到 CPU 侧。
;;   用法与 shader 一致，字段写 (类型 名字)：
;;   (glsl-struct instance (vec3 offset) (vec3 color) (float phase))
;; 生成：
;;   - Racket struct：instance（构造器，与 GLSL 的 struct 构造器同名）/ instance? / instance-offset / ...
;;   - (instance->f32vector rec)  铺平成交错向量（喂 VBO）；按字段类别自动取
;;     ->f32vector / ->f64vector / ->s32vector / ->u32vector，混合类别时生成 ->bytes（u8vector）
;;   - (instance-stride)          总字节步长
;;   - (instance-field-offset 'x) 字段字节偏移（给 glVertexAttribPointer）
;;   - (instance-field-size   'x) 字段分量数（给 glVertexAttribPointer 的 size）
;; 与 shader 的 (glsl (struct Instance (vec3 offset) (vec3 color) (float phase)))
;; 字段顺序、类型、名字完全一致。
;; ============================================================
(define-syntax (glsl-struct stx)
  (syntax-case stx ()
    [(_ Name (type field) ...)
     (let* ([types     (syntax->list #'(type ...))]
            [fields    (syntax->list #'(field ...))]
            [type-syms (map syntax->datum types)])
       (when (null? fields)
         (error 'glsl-struct "至少需要一个字段"))
       (define kinds (map kind-of-type type-syms))
       (when (and (memq 'f32 kinds) (memq 'f64 kinds))
         (error 'glsl-struct "字段不能混用 float/double 精度：~s" type-syms))
       (define all-same? (andmap (lambda (k) (eq? k (car kinds))) kinds))
       (define pack-fmt
         (if all-same?
             (case (car kinds)
               [(f32) "~a->f32vector"]
               [(f64) "~a->f64vector"]
               [(s32) "~a->s32vector"]
               [(u32) "~a->u32vector"])
             "~a->bytes"))
       (with-syntax
         ([types-list   (datum->syntax #'Name type-syms)]
          [to-vec       (format-id #'Name pack-fmt #'Name)]
          [stride-fn    (format-id #'Name "~a-stride" #'Name)]
          [field-offset (format-id #'Name "~a-field-offset" #'Name)]
          [field-size   (format-id #'Name "~a-field-size" #'Name)]
          [(field-acc ...)
           (map (lambda (f) (format-id #'Name "~a-~a" #'Name f)) fields)]
          [(field-clause ...)
           (for/list ([f fields] [i (in-naturals)])
             #`[(#,f) #,i])])
         #'(begin
             (struct Name (field ...) #:transparent)
             (define (to-vec rec)
               (pack 'types-list (field-acc rec) ...))
             (define (stride-fn)
               (apply glsl-stride-bytes 'types-list))
             (define (field-offset f)
               (list-ref (glsl-field-offsets 'types-list)
                         (case f
                           field-clause ...
                           [else (error 'field-offset "未知字段：~s" f)])))
             (define (field-size f)
               (glsl-size (list-ref 'types-list
                                    (case f
                                      field-clause ...
                                      [else (error 'field-size "未知字段：~s" f)])))))))]))
