#lang info
;; ============================================================
;; racket-glsl —— 把本目录当作名为 glsl 的 collection。
;;
;; #lang glsl 是一个普通 Racket 模块环境（body 按 Racket 展开），
;; 只是预先 require 好了 racket-glsl 全套，省去手写：
;;   #lang glsl        → glsl/lang/reader   （reader 层）
;;                       glsl/main          （expander 层：重导 racket/base + 全套）
;;   glsl/core/...     → 具体实现（字符串原语 / 重写器 / 类型 / 工具）
;;   glsl/core-test/...→ 测试（与 core 分开，见 core-test/*.rkt）
;;
;; 安装（在 racket-glsl 的父目录执行其一）：
;;   raco pkg install --link racket-glsl        ; 开发用：链接源码
;;   raco pkg install racket-glsl               ; 一次性拷贝安装
;; 卸载：
;;   raco pkg remove racket-glsl
;; ============================================================

(define collection "glsl")

(define deps '("base" "gui-lib" "rackunit-lib" "opengl"))
(define build-deps '())

(define pkg-desc "GLSL DSL for Racket: #lang glsl + core rewrite/pretty/interface/tool layers")
(define pkg-authors '("lu96"))
(define license '("MIT"))
