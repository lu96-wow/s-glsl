# core/ —— 结构总纲

`core/` 是本项目的实现根目录。项目是 **Racket ↔ OpenGL 的桥梁**，
按「设计功能和逻辑」分成 **三部分 + 一个胶水**，而不是一条层链。

```
core/
  glsl/     Part 1：(glsl) 命名空间内 —— GLSL 语言（特殊、隔离）
  value/    Part 2：(glsl) 命名空间外 —— Racket-ffi 重实现（每逻辑 实现 + rename-*.rkt）
  opengl/   Part 3：(glsl) 命名空间外 —— OpenGL → Racket 命名
  tool/     胶水：把 Part 1 的 GLSL 文本和 Part 3 的 gl-* 接起来
```

## 两个正交的判断

### 判断 1：命名空间在不在 `(glsl)` 里

| | 谁 | 例子 | 归属 |
|---|---|---|---|
| `(glsl)` 内 | 宏认识的 GLSL 表面词汇 | `(uniform mat4 uMVP)`、`(vec4 a 1.0)`、`set!` | Part 1 |
| `(glsl)` 外 | 普通 Racket 代码里的 API | `(vec3 1.0 2.0 3.0)`、`vadd`、`gl-create-shader` | Part 2 / Part 3 |

同名不同物：`vec3` 内是 GLSL 类型→文本，外是 f32vector 构造。两边两套绑定，互不 require。

### 判断 2：rename 的方向（互不依赖）

- 方向 A：`Racket 实现 → GLSL 命名`（Part 2）
- 方向 B：`OpenGL C → Racket 命名`（Part 3）

A、B 谁都不 require 对方。

## Part 1 · `core/glsl/` —— `(glsl)` 命名空间内

| 逻辑 | 文件 |
|---|---|
| GLSL 字符串原语 | `glsl/core.rkt` |
| 表面语法 → core（`(glsl)` 宏） | `glsl/rewrite.rkt` |
| 美化 | `glsl/pretty.rkt` |
| 类型模型 / 接口反射 | `glsl/interface.rkt` |
| 产物 + 源映射 | `glsl/program.rkt` |

不 require `value/`，不 require `opengl/`。

## Part 2 · `core/value/` —— 一个逻辑 = 实现 + `rename-*.rkt`（同目录）

| 逻辑 | 实现（Racket 名） | rename（GLSL 名） |
|---|---|---|
| 类型与存储 | `value/type.rkt` | `value/rename-type.rkt`：`glsl-size / glsl-kind / glsl-byte-size / glsl-stride-bytes` |
| 取用（索引读写） | `value/access.rkt` | `value/rename-access.rkt`：`vcount/vref/vset!/vx…vw`、`mat4-ref/mat4-set!`、`gl-vec-count/ref/set!` |
| 构造 | `value/construct.rkt` | `value/rename-construct.rkt`：`vec2…bvec4 / mat2…dmat4` |
| 交错布局 | `value/layout.rkt` | `value/rename-layout.rkt`：`glsl-struct` |
| 缓冲 / 拼接 | `value/buffer.rkt` | `value/rename-buffer.rkt`：`gl-vec / concat-vecs / …` |
| 向量运算 | `value/vec.rkt` | `value/rename-vec.rkt`：`vadd / vdot / vnormalize / …` |
| 矩阵运算 | `value/matrix.rkt` | `value/rename-matrix.rkt`：`mat4-ref(col,row) / mat4-mul / …` |
| 精度转换 | `value/convert.rkt` | 无（CPU 侧 Racket 风格优先） |

内部共享底座：`value/cvector.rkt`（运行时 cvector 原语），不是用户 API，因此没有 rename。

依赖方向：

```
value/cvector.rkt  ←  value/type.rkt, value/access.rkt, value/construct.rkt,
                      value/layout.rkt, value/vec.rkt, value/matrix.rkt, value/convert.rkt
value/buffer.rkt   ←  value/access.rkt
value/access.rkt   ←  value/matrix.rkt
value/rename-*.rkt →  只依赖对应的 value/<逻辑>.rkt（零逻辑）
```

## Part 3 · `core/opengl/` —— OpenGL → Racket 命名

`opengl/rename.rkt`：纯机械映射，只认外部 `opengl` 包。`glGenBuffers` → `gl-gen-buffers`，
`GL_ARRAY_BUFFER` → `gl-array-buffer`（冲突例外 `GL_CULL_FACE` → `var-cull-face`）。

## 胶水 · `core/tool/` —— 唯一组合点

| 逻辑 | 文件 |
|---|---|
| 编译：GLSL 文本 → shader（+ 三段式报错） | `tool/compile.rkt` |
| 链接 / program 生命周期 | `tool/program.rkt` |
| 报错解析 / 定位 / 渲染 | `tool/error.rkt` |

依赖 `glsl/` + `opengl/rename.rkt` + 外部 `opengl` 包。不 require `value/`。

## 唯一共享点

`(glsl)` 内要判断「这是不是类型」，值层 `value/type.rkt` 要判断「有没有 CPU 表示」。
两边共享一张「GLSL 类型名清单」，但互不 require：

- `glsl/interface.rkt` 拥有**完整 GLSL 类型目录**（含 sampler/image/void/atomic_uint）。
- `value/type.rkt` 只拥有**CPU 可表示子集 + 存储属性**。

## `#lang glsl` 聚合（`main.rkt`）

`main.rkt` require：Part 1 `glsl/rewrite.rkt`（重导 core/pretty/interface/program）、
Part 2 的 7 个 `value/rename-*.rkt` + `value/convert.rkt`、Part 3 `opengl/rename.rkt`、
胶水 `tool/{compile,program,error}.rkt`、`ffi/vector`；
provide 上述全部（GLSL 风格 API）。值层的 Racket 风格实现（`vec-add` / `matrix-ref` …）
不在这里导出，需要时直接 require `value/<逻辑>.rkt`。

## 迁移历史（旧 `core/` 已删除）

| 旧文件 | 新位置 |
|---|---|
| `core/core.rkt` | `glsl/core.rkt` |
| `core/pretty.rkt` | `glsl/pretty.rkt` |
| `core/glsl-interface.rkt` | `glsl/interface.rkt` |
| `core/glsl-program.rkt` | `glsl/program.rkt` |
| `core/rewrite.rkt` | `glsl/rewrite.rkt` |
| `core/rename-vector.rkt` | `value/{type,construct,layout,buffer}.rkt` + `value/rename-{type,construct,layout,buffer}.rkt`（缓冲元素取用归 `access.rkt`） |
| `core/vec-math.rkt` | `value/{cvector,access,vec,matrix,convert}.rkt` + `value/rename-{access,vec,matrix}.rkt` |
| `core/opengl-rename.rkt` | `opengl/rename.rkt` |
| `core/tool.rkt` | `tool/compile.rkt` |
| `core/program.rkt` | `tool/program.rkt` |
| `core/gl-error.rkt` | `tool/error.rkt` |

功能核对：旧 `core/` 全部导出与现 `core/` 全部导出做集合差，**非 `ffi/vector` 重导出的缺失 = 0**；
`ffi/vector` 的重导出由 `main.rkt` 提供。`core-test/` 全部测试（含 GL `double-test`）通过。
