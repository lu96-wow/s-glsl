# core-rebuild —— 结构总纲

`core-rebuild/` 是 `core/` 的重建目标。项目是 **Racket ↔ OpenGL 的桥梁**，
但按「设计功能和逻辑」分成 **三部分 + 一个胶水**，而不是一条层链。

```
core-rebuild/
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

## Part 2 铁律：一个逻辑 = 一个实现 + 一个 `rename-*.rkt`（同目录）

| 逻辑 | 实现（Racket 名） | rename（GLSL 名） |
|---|---|---|
| 类型与存储 | `value/type.rkt` | `value/rename-type.rkt`：`glsl-size / glsl-kind / glsl-byte-size / glsl-stride-bytes` |
| 构造 | `value/construct.rkt` | `value/rename-construct.rkt`：`vec2…bvec4 / mat2…dmat4` |
| 交错布局 | `value/layout.rkt` | `value/rename-layout.rkt`：`glsl-struct` |
| 缓冲 / 拼接 | `value/buffer.rkt` | `value/rename-buffer.rkt`：`gl-vec / concat-vecs / …` |
| 向量运算 | `value/vec.rkt` | `value/rename-vec.rkt`：`vadd / vdot / vnormalize / …` |
| 矩阵运算 | `value/matrix.rkt` | `value/rename-matrix.rkt`：`mat4-ref(col,row) / mat4-mul / …` |
| 场景变换 | `value/transform.rkt` | `value/rename-transform.rkt`：`mat4-look-at / mat4-perspective / …` |
| 精度转换 | `value/convert.rkt` | 无（CPU 侧 Racket 风格优先，后面再定） |

内部共享底座：`value/cvector.rkt`（运行时 cvector 原语：`value-kind / ensure-* / cvector-map*`），
它不是用户 API，因此没有 rename。

依赖方向：

```
value/cvector.rkt ← value/type.rkt
      ↑
value/{construct,layout,vec,matrix,convert}   value/buffer.rkt
      ↑
value/transform.rkt

value/rename-*.rkt  →  只依赖对应的 value/<逻辑>.rkt（零逻辑）
```

## 共享点（唯一）

`(glsl)` 内要判断「这是不是类型」，值层 `value/type.rkt` 要判断「有没有 CPU 表示」。
两边**只共享一张「GLSL 类型名清单」**。归属待定（倾向：Part 1 的 `interface.rkt` 拥有完整类型模型
含 sampler/image/void；`value/type.rkt` 只拥有 CPU 可表示子集 + 存储属性）。定稿前不要双向复制。

## 已确认的设计决定

1. Part 2 目录名 = `value/`。
2. 实现与 rename **同目录**成对。
3. 胶水（编译/链接/报错）放独立 `tool/` 目录。
4. Part 1 的「表面 → core」按功能叫 `glsl/rewrite.rkt`（它是重写，不是简单改名）。
5. CPU 侧以 Racket 风格优先；`convert` 暂不出 GLSL rename。

## 迁移映射（旧 `core/` → 新）

| 旧文件 | 新位置 | 部分 | 状态 |
|---|---|---|---|
| `core/core.rkt` | `glsl/core.rkt` | 1 | ✅ |
| `core/pretty.rkt` | `glsl/pretty.rkt` | 1 | ✅ |
| `core/glsl-interface.rkt` | `glsl/interface.rkt` | 1 | ✅ |
| `core/glsl-program.rkt` | `glsl/program.rkt` | 1 | ✅ |
| `core/rewrite.rkt` | `glsl/rewrite.rkt` | 1 | ✅ |
| `core/rename-vector.rkt` | `value/{type,construct,layout,buffer}.rkt` + `value/rename-{type,construct,layout,buffer}.rkt` | 2 | ✅ |
| `core/vec-math.rkt` | `value/{cvector,vec,matrix,convert}.rkt` + `value/rename-{vec,matrix}.rkt` | 2 | ✅ |
| `core/transform.rkt` | `value/transform.rkt` + `value/rename-transform.rkt` | 2 | ✅ |
| `core/opengl-rename.rkt` | `opengl/rename.rkt` | 3 | ✅ |
| `core/tool.rkt` | `tool/compile.rkt` | 胶水 | ✅ |
| `core/program.rkt` | `tool/program.rkt` | 胶水 | ✅ |
| `core/gl-error.rkt` | `tool/error.rkt` | 胶水 | ✅ |

> 迁移期间 `core/` 保持原样可用；测试暂不迁移。
