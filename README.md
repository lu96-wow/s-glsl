# s-glsl · 在 Racket 里写 GLSL

给 Racket 的 GLSL DSL：一个 `(glsl ...)` 宏、一个 `#lang glsl` 环境，以及配套的
CPU 侧数据类型 / 运算 / 反射 / 编译报错层。

**定位**：只优化「在 Racket 里使用 GLSL」这件事——写 shader、造和算 GLSL 值、
读 shader 的类型接口、把 shader 编译链接起来并把错误讲清楚。
GL 对象/状态/窗口（buffer、VAO、texture、FBO、uniform 上传、事件循环）不属于本库，由调用方自行封装。

```racket
#lang glsl

(define vert
  (glsl (version 330 core)
        (layout (location 0) in vec3 aPos)
        (layout (location 1) in vec3 aColor)
        (uniform mat4 uMVP)
        (out vec3 vColor)
        (define (main) void
          (set! vColor aColor)
          (set! gl_Position (* uMVP (vec4 aPos 1.0))))))

;; CPU 侧用同名类型算矩阵，不碰裸 ffi
(define V (mat4-look-at (vec3 0.0 0.0 3.0) (vec3 0.0 0.0 0.0) (vec3 0.0 1.0 0.0)))
(define P (mat4-perspective 45.0 (/ 16.0 9.0) 0.1 100.0))
(define M (mat4-mul P V))
```

---

## 目录

- [安装](#安装)
- [快速开始](#快速开始)
- [语法参考](#语法参考)
- [CPU 侧 API](#cpu-侧-api)
- [接口反射](#接口反射)
- [编译 / 链接 / 报错](#编译--链接--报错)
- [分层与文件](#分层与文件)
- [命名归属](#命名归属)
- [范围（做什么 / 不做什么）](#范围做什么--不做什么)
- [测试](#测试)

---

## 安装

```bash
git clone https://github.com/lu96-wow/s-glsl.git
cd s-glsl
raco pkg install --auto --link .
```

依赖（会由 `--auto` 自动装）：`base`、`gui-lib`、`rackunit-lib`、`opengl`。

安装后即可在任意 `.rkt` 文件顶部写 `#lang glsl`。卸载：`raco pkg remove s-glsl`。

---

## 快速开始

### 方式一：`#lang glsl`（推荐）

`#lang glsl` 就是一个**普通 Racket 模块**，只是把本库全套预先 `require` 好了。
`glsl` / `vec3` / `mat4` / `vadd` / `build-program` / `gl-*` 全部开箱可用。

```racket
#lang glsl

(define vert
  (glsl (version 330 core)
        (layout (location 0) in vec3 aPos)
        (uniform mat4 uMVP)
        (define (main) void
          (set! gl_Position (* uMVP (vec4 aPos 1.0))))))

(define frag
  (glsl (version 330 core)
        (out vec4 FragColor)
        (define (main) void
          (set! FragColor (vec4 1.0 0.5 0.2 1.0)))))

(define prog (build-program (gl-vertex-shader vert) (gl-fragment-shader frag)))
```

### 方式二：在 `#lang racket/base` 里 require

```racket
#lang racket/base
(require glsl)   ; 等价于 #lang glsl 的那一整套
(define vs (glsl (version 330 core)
                 (layout (location 0) in vec3 aPos)
                 (define (main) void (set! gl_Position (vec4 aPos 1.0)))))
```

### 查看一个 shader 长什么样

```racket
(displayln (glsl-program-src vert))
```

```
#version 330 core
layout(location = 0) in vec3 aPos;
uniform mat4 uMVP;
void main() {
  gl_Position = (uMVP * vec4(aPos, 1.0));
}
```

---

## 语法参考

`(glsl form ...)` 里每个顶层 form 是一条 GLSL 声明/定义。表面语法是 S 表达式，
但语义是 GLSL。

### 变量

```racket
;; 顶层声明：限定符... 类型 名字 [初值]
(in vec2 vUV)
(out vec4 FragColor)
(uniform float uTime)
(const float PI 3.14159)
(flat in vec3 vNormal)
(shared vec4 acc)
(layout (location 0) in vec2 aPos)                 ; layout(location = 0) in vec2 aPos;
(layout (std140) (binding 0) uniform Camera cam)

;; 函数体内局部变量
(vec2 p (- (* vUV 2.0) 1.0))                       ; vec2 p = ((vUV * 2.0) - 1.0);
(float d (length p))
```

- 声明**只支持单变量**：`(float a b)` 会报错。
- 数组类型 `(array 内层 [大小])`，省略大小即未定长 `[]`：
  `(in (array vec3 4) aPos)` → `in vec3[4] aPos;`、`((array float 4) f()` 构造器。
- 接口块 `(block 名字 (字段类型 字段名) ...)`：
  `(uniform (block Camera (mat4 view) (mat4 proj)) cam)` → `uniform Camera { mat4 view; mat4 proj; } cam;`

### 运算符

| Racket 写法 | GLSL |
|---|---|
| `(+ a b)` `(- a b)` `(* a b)` `(/ a b)` `(% a b)` | `+ - * / %` |
| `(<< a b)` `(>> a b)` | `<< >>` |
| `(< a b)` `(<= a b)` `(> a b)` `(>= a b)` `(= a b)` `(!= a b)` | `< <= > >= == !=` |
| `(and a b)` `(or a b)` `(xor a b)` | `&& \|\| ^^` |
| `(bit-and a b)` `(bit-or a b)` `(bit-xor a b)` `(bit-not a)` | `& \| ^ ~` |
| `(not a)` / `(! a)` | `!` |
| `(- a)` `(+ a)` | 一元 `-` / `+` |
| `(if c t e)` | 三元 `c ? t : e`（**表达式位置**） |
| `#t` / `#f` | `true` / `false` |

- 赋值：`(set! x v)`、复合 `(+= x v)`（注意顺序是**左值在前**）、`(++ i)` / `(-- i)`。
- 取值：`(x v)` / `(xyz v)`（swizzle，字母限 `xyzw`/`rgba`/`stpq`，长度 1–4）、
  `(.view cam)`（字段访问）、`(aref a i)`（下标）。
- 数字直接写 Racket 数；**不接受有理数字面量**（写 `0.5`，不要 `1/2`）。
- `(raw "任意 token")` 原样插入（逃生舱）。

### 控制流

```racket
(when (> a 0.5) (set! x a))            ; if (...) { ... }
(unless done (break))                  ; if (!done) { break; }
(cond [(= a 1) (set! c a)]             ; if / else if / else 链
      [(= a 2) (set! c b)]
      [else    (set! c z)])
(for (int i 0) (< i 8) (++ i)          ; for (int i = 0; (i < 8); ++i) { ... }
  (set! x (+ x i)))
(while (< i n) (++ i))
(do-while (< i n) (++ i) (set! s (+ s i)))
(switch mode
  [case 1 (set! c a)]
  [case 2 (set! c b)]
  [default (set! c z)])
(break) (continue) (return) (return v) (discard)
```

> 注意：`if` 在**语句位置不可用**（它被保留给三元表达式）。分支用 `when` / `unless` / `cond`。
> `for` 的 init 必须是声明 `(int i 0)`，且只能一个变量。

### 函数

```racket
(define (main) void
  (set! gl_Position (vec4 0.0 0.0 0.0 1.0)))

(define (sq (float x)) float (* x x))          ; 函数体最后一个表达式自动作 return
(define (f (inout vec3 p)) void (return (+ (x p) 1.0)))
```

参数可带 `in` / `out` / `inout`；返回类型写在参数表后面。

### 结构

```racket
(struct Light (vec3 pos) (float i))            ; struct Light { vec3 pos; float i; };
```

### 预处理指令

```racket
(define-macro FOO 1)                           ; #define FOO 1
(define-macro (ADD a b) (+ a b))               ; #define ADD(a, b) (a + b)
(ifdef FOO) (else) (endif)
(if 1) (elif 0) (else) (endif)
(undef BAR)
(error "unsupported")
(pragma "STDGL invariant(all)")
(extension GL_OES_standard_derivatives enable)
```

指令在顶层和函数体内都可以用（`if`/`elif` 仅在顶层，因为语句位置的 `(if ...)` 是三元）。

### `glsl-unquote`：在 shader 里插入 Racket 代码

```racket
(glsl (version 330 core)
      (glsl-unquote (format "#define N ~a" 8))
      (glsl-unquote some-declaration-string)
      (define (main) void
        (glsl-unquote (format "int x = ~a;" 1))))
```

求值结果可以是字符串或另一个 `glsl-program`（可组合）。

---

## CPU 侧 API

CPU 侧的 GLSL 值就是货真价实的 `ffi/vector`（零拷贝、可直接上传）。
构造出的 `vec3` 是 `f32vector`、`dvec3` 是 `f64vector`，以此类推。

### 构造（`rename-vector`）

```racket
(vec3 1.0 2.0 3.0)          ; -> #<f32vector>   浮点必须写 1.0
(dvec3 1.0 2.0 3.0)         ; -> #<f64vector>
(ivec2 1 2) (uvec2 1 2) (bvec3 #t #f #t)
(mat4 2.0)                  ; 对角矩阵 mat4(2.0)
(mat4 c0 c1 c2 c3)          ; 4 个列向量
(mat4 16 个标量)            ; 16 个标量，列主序
(concat-vecs (vec2 ..) (vec2 ..))
```

### 取用 / 运算（`vec-math`）

```racket
;; 分量
(vx v) (vy v) (vz v) (vw v) (vref v i) (vset! v i x) (vcount v)

;; 逐分量算术（float / int 族）
(vadd a b) (vsub a b) (vmul a b) (vmul v 2.0) (vdiv a b) (vneg v)
(vabs v) (vmin v 0.0) (vmax v 1.0) (vmod a b) (vfract v)

;; 几何
(vdot a b) (vcross a b) (vlength v) (vdistance a b) (vnormalize v)
(vmix a b t) (vclamp v lo hi) (vstep e x) (vsmoothstep e0 e1 x)
(vreflect i n) (vrefract i n eta)

;; 矩阵（mat2/3/4 与 dmat2/3/4）
(mat4-ref m col row) (mat4-set! m col row x) (mat4-identity)
(mat4-mul A B) (mat4-mul-vec M v) (mat4-vec-mul v M)
(mat4-add A B) (mat4-sub A B) (mat4-transpose M) (mat4-inverse M) (mat4-mul-scalar M s)

;; 转换
(->f32vector x) (->f64vector x) (->s32vector x) (->u32vector x)
```

规则：
- **同类进同类出**，跨精度/跨类报错（不做隐式提升）。
- 向量宽度由 cvector 长度自动得到（`vadd` 不需要宽度参数）；
  矩阵阶写进名字（`mat4-*`），因为运行期区分不出 `vec4` 和 `mat2`。
- 运算返回新值；`vset!` / `mat*-set!` 原地写。

### 场景 / 相机变换（`transform`）

```racket
(mat4-translate x y z)
(mat4-rot-x deg) (mat4-rot-y deg) (mat4-rot-z deg)
(mat4-scaling sx sy sz)
(mat4-look-at eye center up)                       ; 视图矩阵
(mat4-ortho l r b t n f)                           ; 正交投影
(mat4-perspective fovy aspect near far)            ; 透视投影（fovy 用度）
```

约定：右手系、列主序、角度制。典型 MVP：

```racket
(define mvp (mat4-mul (mat4-mul P V) M))
```

### 顶点布局（`glsl-struct`）

把 shader 里的 `struct` 镜像到 CPU 侧，自动给 stride / offset / size：

```racket
(glsl-struct vertex (vec3 pos) (vec3 color))

(define v0 (vertex (vec3 1.0 2.0 3.0) (vec3 1.0 0.0 0.0)))
(vertex->f32vector v0)        ; 铺平成 f32vector（喂 VBO）
(vertex-stride)               ; 24
(vertex-field-offset 'color)  ; 12
(vertex-field-size 'pos)      ; 3（分量数）
```

尺寸辅助（消灭字节魔数）：

```racket
(glsl-size 'vec3)                 ; 3
(glsl-byte-size 'vec3)            ; 12
(glsl-stride-bytes 'vec3 'vec2)   ; 20
(glsl-kind 'dvec3)                ; f64
```

### 顶点缓冲（`gl-vec`）

同宽度向量的数组（对应 GLSL `vec3[N]`），适合动态顶点数据：

```racket
(gl-vec (vec2 -0.5 -0.5) (vec2 0.5 -0.5) (vec2 0.0 0.5))   ; 静态
(make-gl-vec 1000 (vec3 0.0 0.0 0.0))                       ; 预分配，每帧原地覆写
(gl-vec-count gv) (gl-vec-width gv) (gl-vec-ref gv i) (gl-vec-set! gv i v)
(gl-vec->f32vector gv)                                      ; 底层连续缓冲
```

---

## 接口反射

`(glsl ...)` 的产物是 `glsl-program`，带类型化的接口信息和源映射。

```racket
(define shader
  (glsl (version 330 core)
        (layout (location 0) in vec3 aPos)
        (uniform mat4 uMVP)
        (uniform sampler2D uTex)
        (layout (std140) (binding 0) uniform (block Camera (mat4 view) (mat4 proj)) cam)))

(define ifc (glsl-program-interface shader))

(glsl-interface-vars ifc)                            ; 全部声明
(glsl-interface-vars-with-qualifier ifc 'uniform)    ; 按限定符取
(glsl-interface-vars-with-kind ifc 'sampler)         ; 按类型 kind 取
(glsl-interface-ref ifc 'uMVP)                       ; 按名字查
(glsl-var-name v) (glsl-var-type v) (glsl-var-qualifiers v) (glsl-var-layout v)
(glsl-type-name t) (glsl-type-kind t) (glsl-type-size t) (glsl-type-fields t)
```

`glsl-interface` 是**只读**的：它提供类型数据，不生成 setter、不合并多个 shader。
要不要据此生成 uniform setter，是调用方的事。

---

## 编译 / 链接 / 报错

```racket
;; 编译一段 GLSL 文本（glsl-program 或字符串）→ shader 对象
(compile-shader (gl-vertex-shader vert))

;; 编译 + 链接
(build-program (gl-vertex-shader vert) (gl-fragment-shader frag))          ; 宏
(build-program/list (list (list gl-vertex-shader vert) ...))               ; 函数版

(use-program prog)
(uniform-location prog "uMVP")   ; 找不到返回 -1
```

编译失败会抛异常，消息是**三段式**：

```
OpenGL log:
  0:5(2): error: `uMVP' undeclared

OpenGL source:
   4 | void main() {
>  5 |   gl_Position = (uMVP * vec4(aPos, 1.0));
     | ...

s-expr source: /path/to/file.rkt:12
  ...
```

即：GL 原始日志 → 美化后的 GLSL + 报错行 → 对应的 `.rkt` 源文件行。
（源映射精确到行；裸字符串没有 `.rkt` 映射，只有美化 GLSL。）

所有权约定：`compile-shader` / `link-program` 失败时会释放自己创建的 GL 对象；
`build-program/list` 链接成功后 **detach + delete** 中间 shader，不泄漏。

---

## 分层与文件

```
core/rewrite.rkt        (glsl ...) 宏：表面语法 → core 调用
core/core.rkt           字符串原语（声明/表达式/语句/函数/结构的文本生成）
core/pretty.rkt         GLSL 文本美化（缩进）
core/glsl-interface.rkt 类型模型 + 接口反射（glsl-type / glsl-var / ...）
core/glsl-program.rkt   glsl-program 产物 + 源映射
core/gl-error.rkt       编译报错的解析 / 定位 / 渲染
core/opengl-rename.rkt  OpenGL 名字映射（glCreateShader → gl-create-shader）
core/tool.rkt           编译：GLSL 文本 → shader（+ 报错）
core/program.rkt        program 生命周期：link / build / use / uniform / delete
core/rename-vector.rkt  构造 + 数据布局（vecN/matN、gl-vec、glsl-struct）
core/vec-math.rkt       取用 + 运算（GLSL 内建镜像）
core/transform.rkt      场景 / 相机变换
main.rkt                #lang glsl 的模块语言（重导 racket/base + 全套）
lang/reader.rkt         #lang 声明（syntax/module-reader）
```

依赖方向单向：`rename-vector → vec-math → transform`；其余各层互相独立。

---

## 命名归属

一套约定，决定「哪个名字属于谁」（完整版见 [NAMING.md](NAMING.md)）：

| 前缀 / 形态 | 归属 | 例 |
|---|---|---|
| 裸名、`?`、`!`、`->` | Racket / `racket/base`（不遮蔽） | `length`、`set!` |
| `gl-<opengl符号>` | OpenGL C API 的 1:1 映射 | `gl-create-shader` |
| `glsl-*` | 本 DSL 的语言层 | `glsl-size`、`glsl-struct`、`glsl-program` |
| `gl-vec*` | 本 DSL 的 CPU 缓冲类型 | `gl-vec`、`gl-vec-ref` |
| `vecN` / `matN` | GLSL 类型构造器 | `vec3`、`mat4` |
| `v*` | 向量取用 / 运算 | `vref`、`vadd`、`vdot` |
| `matN-*` | 矩阵取用 / 运算 | `mat4-ref`、`mat4-mul` |
| `mat4-<场景词>` | 场景 / 相机变换 | `mat4-look-at`、`mat4-perspective` |

---

## 范围（做什么 / 不做什么）

**做**：GLSL 文本的书写 → CPU 值 ↔ 类型信息 ↔ 编译报错。

**不做**（由调用方自行封装）：
- GL 对象与状态：`gen-buffer` / 上传 / 属性绑定 / uniform 上传 / 纹理 / FBO
- 窗口与事件循环
- UBO/SSBO 绑定、compute dispatch、program pipeline、program binary

本库提供 `gl-*`（OpenGL 名字）作为地基，但这些「GL 资源/状态」的助手刻意不做——
它们不属于「使用 GLSL」，属于「使用 OpenGL」。

---

## 测试

```bash
# 在仓库根目录（clone 出来的 s-glsl/）里：
raco test core-test
# 或逐个运行
racket core-test/rewrite-test.rkt
```

覆盖：表面语法重写、字符串原语、美化、接口反射、报错定位、向量构造/布局/运算、
场景变换。（`core-test/double-test.rkt` 需要显示器 + GL 4.0+。）

---

## License

MIT
