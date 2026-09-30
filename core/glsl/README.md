# Part 1 · glsl/ —— `(glsl)` 命名空间内：GLSL 语言（特殊、隔离）

这里**只有 GLSL 语言本身的实现**，不掺值层、不掺 OpenGL。

| 逻辑 | 文件 | 状态 |
|---|---|---|
| GLSL 字符串原语 | `core.rkt` | ✅ 已迁移 |
| 美化 | `pretty.rkt` | ✅ 已迁移 |
| 类型模型 / 接口反射 | `interface.rkt` | ✅ 已迁移 |
| 产物 + 源映射 | `program.rkt` | ✅ 已迁移 |
| 表面语法 → core（`(glsl)` 宏） | `rewrite.rkt` | ✅ 已迁移 |

规则：

- 不 require `value/rename-*.rkt`；不 require `opengl/rename.rkt`。
- 唯一与值层/外部的共享点是**「GLSL 类型名清单」**：`(glsl)` 内要判断「这是不是类型」，
  值层的 `value/type.rkt` 要判断「有没有 CPU 表示」。两者用同名键对应，不重复造表。
  这张清单的归属见 `LAYERS.md` §共享点。
