# racket-glsl 命名归属（ownership）

一份「哪个名字属于谁」的约定。所有新增 API 都按这张表取名。

## 一、五个命名空间

| 名字形态 | 归属 | 例子 |
|---|---|---|
| 裸名、`?`、`!`、`->` | **Racket / `racket/base`**（我们不遮蔽） | `length`、`vector-ref`、`set!`、`exact->inexact` |
| `gl-<opengl符号>` | **OpenGL C API 的 1:1 机械映射** | `glCreateShader` → `gl-create-shader` |
| `glsl-*` | **本 DSL 的语言层概念** | `glsl-size`、`glsl-struct`、`glsl-program`、`glsl-interface`、`glsl-kind` |
| `vec-array*` | **本 DSL 的 CPU 向量数组类型**（自有类型，不带 `gl-`；按名字区分元素：`vec-array`=f32、`dvec-array`=f64、`ivec-array`=s32、`uvec-array`=u32） | `vec-array`、`ivec-array`、`vec-array-ref`、`vec-array-data` |
| `vecN`/`dvecN`/`ivecN`/`uvecN`/`bvecN`、`matN`/`dmatN` | **GLSL 类型构造器** | `vec3`、`mat4`、`dvec3`、`uvec4` |
| `v*` | **向量取用 / 运算** | `vx`、`vref`、`vset!`、`vcount`、`vadd`、`vdot`、`vnormalize` |
| `matN-*` | **矩阵取用 / 运算** | `mat4-ref`、`mat4-mul`、`mat4-inverse`、`mat4-transpose` |
| `->X` | **Racket 风格转换** | `->f32vector`、`->s32vector` |

## 二、规则

1. **`gl-` 只给 OpenGL C 符号的 1:1 机械映射**（`gl-create-shader` ↔ `glCreateShader`、
   `gl-array-buffer` ↔ `GL_ARRAY_BUFFER`）：**只做机械映射，不发明**。
   我们自己的数据类型一律不带 `gl-`：CPU 向量数组叫 `vec-array`，不叫 `gl-vec`。

2. **不发明新的 `gl-<动词>` 名字**。要加自己的东西，用 `glsl-*`（语言层）或 `v*`/`mat*`（值层）。

3. **不遮蔽 `racket/base`**。裸 GLSL 名 `length`/`abs`/`min`/`max`/`floor`/`sqrt`/… 一律加前缀：`vlength`/`vabs`/`vmin`/`vmax`/`vfloor`/`vsqrt`。

4. **能推导的形状不进名字，不能推导的进名字**。
   - 向量宽度可由 cvector 长度推出 → 泛型 `v*`，不带宽度。
   - 矩阵阶推不出（`f32vector` 长度 4 可能是 `vec4` 也可能是 `mat2`）→ 写进名字：`mat4-*`。

5. **全名优先于缩写**：`vec-array-ref`（不是 `vec-ref`），避免和 `vref`/`vcount` 混。

6. **Racket 惯例**：kebab-case；谓词 `?`（`vec?`）；原地修改 `!`（`vset!`、`vec-array-set!`）；转换 `->`（`->f32vector`）。
7. **取数据 ≠ 转换**：取内部存储（零拷贝）用 `X-data`；真正的类型转换用 `->type`。
8. **一个词只表示一件事**：存储类别用 `storage-kind`（不写裸 `kind`）；元素数用 `element-count`；
   字节数名字里必须带 `byte(s)`；stride 一律写 `stride-bytes`（不写裸 `stride`）。
9. **工具层不与 raw 层同基名**：`compile-shader` 与 `gl-compile-shader` 这种只差 `gl-` 的对照，
   要么在文档里明确标注，要么改成不易混的名字（如 `shader-compile`）。

## 三、层的归属（文件）

`core/` 分三部分 + 胶水（详见 [core/LAYERS.md](core/LAYERS.md)）。

**Part 2（`core/value/`）：每个逻辑 = 实现（Racket 名）+ `rename-*.rkt`（GLSL 名）**

| 逻辑 | 实现（Racket 名） | rename（GLSL 名） |
|---|---|---|
| 类型与存储 | `core/value/type.rkt` | `rename-type.rkt`：`glsl-size`、`glsl-kind`、`glsl-byte-size` |
| 取用（索引读写） | `core/value/access.rkt` | `rename-access.rkt`：`vcount`、`vref`、`mat4-ref`、`gl-vec-ref` |
| 构造 | `core/value/construct.rkt` | `rename-construct.rkt`：`vec3`、`mat4`、`dvec3` |
| 交错布局 | `core/value/layout.rkt` | `rename-layout.rkt`：`glsl-struct` |
| 缓冲 / 拼接 | `core/value/buffer.rkt` | `rename-buffer.rkt`：`vec-array`、`concat-vecs` |
| 向量运算 | `core/value/vec.rkt` | `rename-vec.rkt`：`v*` |
| 矩阵运算 | `core/value/matrix.rkt` | `rename-matrix.rkt`：`matN-*` |
| 精度转换 | `core/value/convert.rkt` | （CPU 侧 Racket 风格优先，暂无 rename） |

**Part 1（`core/glsl/`）：`(glsl)` 命名空间内的 GLSL 语言**

| 文件 | 负责 | 典型名字 |
|---|---|---|
| `core/glsl/core.rkt` | 字符串原语 | `glsl-decl`、`glsl-fn` |
| `core/glsl/rewrite.rkt` | 表面语法 `(glsl ...)` | `glsl`、`glsl-unquote` |
| `core/glsl/pretty.rkt` | 文本美化 | `glsl-pretty` |
| `core/glsl/interface.rkt` | 类型模型 / 反射 | `glsl-type`、`glsl-var` |
| `core/glsl/program.rkt` | 产物 + 源映射 | `glsl-program` |

**Part 3 / 胶水**

| 文件 | 负责 | 典型名字 |
|---|---|---|
| `core/opengl/rename.rkt` | OpenGL 符号的 kebab 映射 | `gl-create-shader`、`gl-uniform-matrix-4fv` |
| `core/tool/compile.rkt` | 编译（文本 → shader）+ 报错 | `compile-shader` |
| `core/tool/program.rkt` | program 生命周期 | `build-program`、`use-program`、`uniform-location` |
| `core/tool/error.rkt` | 报错解析 / 定位 / 渲染 | `parse-gl-error-log`、`render-error` |

## 四、判据（新增名字前问两句）

1. 这是 GLSL 里有对应物的**运算/取用**吗？→ `v*` / `matN-*`（`vec.rkt` / `matrix.rkt`）。
2. 这是**本 DSL 的概念**（语言/布局/类型）吗？→ `glsl-*`；若是 CPU 缓冲类型 → `gl-vec-*`。

都不属于 → 大概率不该加，或该放在调用方。
