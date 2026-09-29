#lang racket/base

;; ============================================================
;; tool.rkt —— GLSL 文本 → shader 对象 + 报错封装层
;;
;; 只做一件事：把一段 GLSL 文本编译成 shader 对象，并把编译报错讲清楚。
;;   ① compile-shader：文本（glsl-program 或字符串）→ 编译好的 shader 对象
;;   ② 失败时三段式报错：OpenGL 日志 / 美化 GLSL + 报错行 / 源文件对应行
;;      （解析 / 定位 / 渲染在 gl-error.rkt，本文件负责触发与抛出）
;;
;; 明确不管：
;;   - 链接 / program 组装 / 启用 / uniform / 释放  → program.rkt
;;   - 高级编译（link 前绑定、program pipeline、UBO/SSBO、二进制）→ 调用方
;;    直接用 gl-*；本层只封装「最常见的一次编译」。
;;
;; glShaderSource 的 ffi 细节（字符串数组 + s32vector 长度数组）留在本层，
;; 因为它是"编译"这件事本身的一部分。
;; ============================================================

(require "pretty.rkt"        ; glsl-pretty（裸字符串先美化，报错行号才对齐）
         "glsl-program.rkt"  ; glsl-program? / glsl-program-src
         "opengl-rename.rkt" ; gl-create-shader / gl-shader-source / gl-compile-shader / ...
         "gl-error.rkt"      ; parse-gl-error-log / locate-gl-error / render-error
         ffi/vector)         ; s32vector

(provide compile-shader)

;; ---------- 内部：编译信息日志 ----------

;; 取 info log：get-iv 查长度、get-log 取内容，拼成 UTF-8 字符串
(define (info-log get-iv get-log obj)
  (define len (get-iv obj gl-info-log-length))
  (define-values (actual log) (get-log obj len))
  (bytes->string/utf-8 log #\? 0 actual))

(define (shader-info-log shader)
  (info-log gl-get-shader-iv gl-get-shader-info-log shader))

;; ---------- 编译：一段 GLSL 文本 → 一个着色器对象 ----------

;; type 是任意着色器阶段：gl-vertex-shader / gl-tess-control-shader /
;; gl-tess-evaluation-shader / gl-geometry-shader / gl-fragment-shader。
;; 编译失败自动抛错，错误消息带 GLSL 报错日志 + 源映射。
(define (compile-shader type src)
  ;; 先统一成"美化后的字符串"再编译，报错行号因此对齐美化版：
  ;;   glsl-program（(glsl ...) 的产物）→ 它的 src 已经是美化串，直接用；
  ;;   裸字符串 → 现做 glsl-pretty。
  (define src* (if (glsl-program? src) (glsl-program-src src) (glsl-pretty src)))
  (define shader (gl-create-shader type))
  ;; gl-shader-source 的 C 签名要"字符串数组 + 每段长度数组"：
  ;; 长度数组必须是 s32vector（32 位有符号整数向量）。纯 ffi 细节，藏在这里。
  (gl-shader-source shader 1 (vector src*) (s32vector (string-length src*)))
  (gl-compile-shader shader)
  (when (zero? (gl-get-shader-iv shader gl-compile-status))
    (define log (shader-info-log shader))
    ;; 源映射上下文：glsl-program 才有映射；裸字符串只有美化源码（无 form 提示）
    (define ctx (if (glsl-program? src) src src*))
    (define located (map (lambda (e) (locate-gl-error ctx e))
                         (parse-gl-error-log log)))
    ;; 这个 shader 是本函数创建的，编译失败也要释放，否则句柄丢失就泄漏
    (gl-delete-shader shader)
    (error 'compile-shader
           "shader compile failed:\n\n~a"
           (render-error log ctx located)))
  shader)
