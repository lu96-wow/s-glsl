#lang racket/base

;; ============================================================
;; glsl/main.rkt —— #lang glsl 的模块语言
;;
;; 设计：body 仍然是**普通 Racket 模块**（不把整个模块当成 GLSL 解析）。
;; 「#lang glsl」只是省掉一堆手写 require 的“GLSL 环境”：
;;
;;   #lang glsl
;;   (define vert
;;     (glsl (version 330 core)
;;           (layout (location 0) in vec3 aPos)
;;           (uniform mat4 uMVP)
;;           (define (main) void
;;             (set! gl_Position (* uMVP (vec4 aPos 1.0))))))
;;
;;   (use-program (build-program (gl-vertex-shader vert) (gl-fragment-shader frag)))
;;
;; 等价于 #lang racket/base 再加上：
;;   (require "core/rewrite.rkt"        ; (glsl ...) 宏 + glsl-program / 接口反射
;;            "core/rename-vector.rkt"  ; vec2/vec3/mat4/... + ffi/vector
;;            "core/vec-math.rkt"       ; CPU 侧取用/运算（dot/cross/normalize/mat-mul/inverse…）
;;            "core/transform.rkt"      ; 场景/相机变换（look-at/perspective/translate/rot/…）
;;            "core/tool.rkt"           ; compile-shader（文本 → shader + 报错）
;;            "core/program.rkt"        ; link-program / build-program / use-program / ...
;;            "core/opengl-rename.rkt"  ; gl-* 名字
;;            "core/gl-error.rkt")      ; 报错定位/渲染
;;
;; reader 层见 lang/reader.rkt（#lang s-exp syntax/module-reader glsl/main）。
;; 实现都在 core/ 下；本文件只负责「语言外观」＝ 把需要的文件一次 require 好。
;; ============================================================

(require "core/rewrite.rkt"
         "core/rename-vector.rkt"
         "core/vec-math.rkt"      ; CPU 侧向量/矩阵取用与运算
         "core/transform.rkt"     ; 场景/相机变换（look-at/perspective/...）
         "core/tool.rkt"           ; compile-shader
         "core/program.rkt"        ; link/build/use/uniform/delete
         "core/opengl-rename.rkt"
         "core/gl-error.rkt")

;; 重导 racket/base（含 #%module-begin / #%app / #%datum ...），
;; 因此 body 照常按 Racket 语法展开：define / require / provide / lambda ... 都能用。
(provide (all-from-out racket/base)
         ;; racket-glsl 全套（rewrite 已含 core / pretty / glsl-interface / glsl-program）
         (all-from-out "core/rewrite.rkt")
         (all-from-out "core/rename-vector.rkt")
         (all-from-out "core/vec-math.rkt")
         (all-from-out "core/transform.rkt")
         (all-from-out "core/tool.rkt")
         (all-from-out "core/program.rkt")
         (all-from-out "core/opengl-rename.rkt")
         (all-from-out "core/gl-error.rkt"))
