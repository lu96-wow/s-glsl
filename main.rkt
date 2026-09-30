#lang racket/base

;; ============================================================
;; glsl/main.rkt —— #lang glsl 的模块语言（聚合入口）
;;
;; body 仍然是普通 Racket 模块；「#lang glsl」只是把下面这些预先 require 好：
;;
;;   Part 1 · core/glsl/rewrite.rkt       GLSL 语言（(glsl ...) 宏 + 产物 + 接口反射）
;;   Part 2 · core/value/rename-*.rkt     Racket-ffi 重实现的 GLSL 风格命名
;;            core/value/convert.rkt      精度转换（Racket 风格：->f32vector …）
;;   Part 3 · core/opengl/rename.rkt      OpenGL → Racket 命名（gl-*）
;;   胶水   · core/tool/{compile,program,error}.rkt   编译 / 链接 / 报错
;;   地基   · ffi/vector                   裸 cvector（f32vector 等）
;;
;; 值层的 Racket 风格实现（vec-add / matrix-ref / …）不在这里导出；
;; 需要时直接 require 对应 core/value/<逻辑>.rkt。
;;
;; reader 层见 lang/reader.rkt（#lang s-exp syntax/module-reader glsl/main）。
;; ============================================================

(require ffi/vector
         ;; Part 1：(glsl) 内 —— 语言（rewrite 已重导 core/pretty/interface/program）
         "core/glsl/rewrite.rkt"
         ;; Part 2：(glsl) 外 —— Racket-ffi 重实现的 GLSL 风格命名
         "core/value/rename-type.rkt"
         "core/value/rename-construct.rkt"
         "core/value/rename-layout.rkt"
         "core/value/rename-buffer.rkt"
         "core/value/rename-vec.rkt"
         "core/value/rename-matrix.rkt"
         "core/value/rename-transform.rkt"
         "core/value/convert.rkt"
         ;; Part 3：(glsl) 外 —— OpenGL → Racket 命名
         "core/opengl/rename.rkt"
         ;; 胶水
         "core/tool/compile.rkt"
         "core/tool/program.rkt"
         "core/tool/error.rkt")

(provide (all-from-out racket/base)
         (all-from-out ffi/vector)
         (all-from-out "core/glsl/rewrite.rkt")
         (all-from-out "core/value/rename-type.rkt")
         (all-from-out "core/value/rename-construct.rkt")
         (all-from-out "core/value/rename-layout.rkt")
         (all-from-out "core/value/rename-buffer.rkt")
         (all-from-out "core/value/rename-vec.rkt")
         (all-from-out "core/value/rename-matrix.rkt")
         (all-from-out "core/value/rename-transform.rkt")
         (all-from-out "core/value/convert.rkt")
         (all-from-out "core/opengl/rename.rkt")
         (all-from-out "core/tool/compile.rkt")
         (all-from-out "core/tool/program.rkt")
         (all-from-out "core/tool/error.rkt"))
