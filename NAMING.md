# racket-glsl 命名归属（ownership）

一份「哪个名字属于谁」的约定。所有新增 API 都按这张表取名。

## 一、五个命名空间

| 名字形态 | 归属 | 例子 |
|---|---|---|
| 裸名、`?`、`!`、`->` | **Racket / `racket/base`**（我们不遮蔽） | `length`、`vector-ref`、`set!`、`exact->inexact` |
| `gl-<opengl符号>` | **OpenGL C API 的 1:1 机械映射** | `glCreateShader` → `gl-create-shader` |
| `glsl-*` | **本 DSL 的语言层概念** | `glsl-size`、`glsl-struct`、`glsl-program`、`glsl-interface`、`glsl-kind` |
| `gl-vec*` | **本 DSL 的 CPU 缓冲类型** | `gl-vec`、`gl-vec-ref`、`gl-vec-count`、`gl-vec->f32vector` |
| `vecN`/`dvecN`/`ivecN`/`uvecN`/`bvecN`、`matN`/`dmatN` | **GLSL 类型构造器** | `vec3`、`mat4`、`dvec3`、`uvec4` |
| `v*` | **向量取用 / 运算** | `vx`、`vref`、`vset!`、`vcount`、`vadd`、`vdot`、`vnormalize` |
| `matN-*` | **矩阵取用 / 运算** | `mat4-ref`、`mat4-mul`、`mat4-inverse`、`mat4-transpose` |
| `mat4-<场景词>` | **场景 / 相机变换**（`transform.rkt`） | `mat4-look-at`、`mat4-perspective`、`mat4-ortho` |
| `->X` | **Racket 风格转换** | `->f32vector`、`->s32vector` |

## 二、规则

1. **`gl-` 有两种用法，但可区分**
   - `gl-<动词>…` ↔ OpenGL C 符号（`gl-create-shader` ↔ `glCreateShader`）：**只做机械映射，不发明**。
   - `gl-vec-*` = 我们自己的缓冲**类型**前缀（`gl-vec` 是一个类型名，不对应任何 `glXxx`）。

2. **不发明新的 `gl-<动词>` 名字**。要加自己的东西，用 `glsl-*`（语言层）或 `v*`/`mat*`（值层）。

3. **不遮蔽 `racket/base`**。裸 GLSL 名 `length`/`abs`/`min`/`max`/`floor`/`sqrt`/… 一律加前缀：`vlength`/`vabs`/`vmin`/`vmax`/`vfloor`/`vsqrt`。

4. **能推导的形状不进名字，不能推导的进名字**。
   - 向量宽度可由 cvector 长度推出 → 泛型 `v*`，不带宽度。
   - 矩阵阶推不出（`f32vector` 长度 4 可能是 `vec4` 也可能是 `mat2`）→ 写进名字：`mat4-*`。

5. **全名优先于缩写**：`gl-vec-ref`（不是 `vec-ref`），避免和 `vref`/`vcount` 混。

6. **Racket 惯例**：kebab-case；谓词 `?`（`vec?`）；原地修改 `!`（`vset!`、`gl-vec-set!`）；转换 `->`（`->f32vector`）。

## 三、层的归属（文件）

| 文件 | 负责 | 典型名字 |
|---|---|---|
| `core/rename-vector.rkt` | 构造 + 数据布局 | `vec3`、`mat4`、`gl-vec*`、`glsl-size`、`glsl-struct` |
| `core/vec-math.rkt` | 取用 + 运算（GLSL 内建镜像） | `v*`、`matN-*`、`->*` |
| `core/transform.rkt` | 场景 / 相机变换（图形学约定） | `mat4-look-at`、`mat4-perspective` |
| `core/opengl-rename.rkt` | OpenGL 符号的 kebab 映射 | `gl-create-shader`、`gl-uniform-matrix-4fv` |
| `core/tool.rkt` | 编译（文本 → shader）+ 报错 | `compile-shader` |
| `core/program.rkt` | program 生命周期 | `build-program`、`use-program`、`uniform-location` |
| `core/glsl-interface.rkt` / `core/glsl-program.rkt` | 类型模型 / 产物 | `glsl-type`、`glsl-var`、`glsl-program` |
| `core/rewrite.rkt` | 表面语法 `(glsl ...)` | `glsl`、`glsl-unquote` |

## 四、判据（新增名字前问三句）

1. 这是 GLSL 里有对应物的**运算/取用**吗？→ `v*` / `matN-*`（`vec-math.rkt`）。
2. 这是**图形学约定**（相机/投影/变换）吗？→ `mat4-<场景词>`（`transform.rkt`）。
3. 这是**本 DSL 的概念**（语言/布局/类型）吗？→ `glsl-*`；若是 CPU 缓冲类型 → `gl-vec-*`。

都不属于 → 大概率不该加，或该放在调用方。
