# Part 3 · opengl/ —— OpenGL → Racket 风格命名（独立块）

| 逻辑 | 文件 | 状态 |
|---|---|---|
| OpenGL C API → Racket 命名 | `rename.rkt` | ✅ 已迁移自 `core/opengl-rename.rkt` |

`rename.rkt` 是**纯机械映射**，只认外部 `opengl` 包的 C 名字，不需要知道 GLSL、也不需要知道值层：

- 函数：`glGenBuffers` → `gl-gen-buffers`
- 常量：`GL_ARRAY_BUFFER` → `gl-array-buffer`
- 冲突例外：`GL_CULL_FACE` → `var-cull-face`（避开与函数 `gl-cull-face` 撞名）

编译 / 链接 / 报错不在这里，在 `tool/`（因为它要同时用到 GLSL 文本，属于组合）。
