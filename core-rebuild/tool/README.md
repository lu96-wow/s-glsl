# 胶水 · tool/ —— 把两块接起来（编译 / 链接 / 报错）

这里不属于「GLSL 语言」也不属于「OpenGL rename」，它是**唯一的组合点**：
用 Part 1 产出的 GLSL 文本 + Part 3 的 `gl-*` 名字，去和 GL 驱动打交道。

| 逻辑 | 文件 | 迁移来源 | 状态 |
|---|---|---|---|
| 编译：GLSL 文本 → shader（+ 三段式报错） | `compile.rkt` | `core/tool.rkt` | ✅ |
| 链接 / program 生命周期（link/build/use/uniform/delete） | `program.rkt` | `core/program.rkt` | ✅ |
| 报错的解析 / 定位 / 渲染（纯函数） | `error.rkt` | `core/gl-error.rkt` | ✅ |

内部依赖：`program.rkt` → `compile.rkt` → `error.rkt` → `../glsl/program.rkt`。
外部依赖：`../glsl/{pretty,program}.rkt`（GLSL 文本 / 产物）、`../opengl/rename.rkt`（`gl-*`）、`opengl` 包。

> 注意：本目录的 `program.rkt` 是 **GL program 生命周期**，与 `glsl/program.rkt`（`glsl-program` 产物）不是一回事。
