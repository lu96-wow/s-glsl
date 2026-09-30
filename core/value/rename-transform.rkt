#lang racket/base

;; ============================================================
;; 值层 · value/rename-transform.rkt —— GLSL 风格命名（场景变换）
;;
;; 纯 alias：value/transform.rkt 的 Racket 名 → GLSL 名。零逻辑。
;; ============================================================

(require "transform.rkt")

(provide mat4-translate mat4-rot-x mat4-rot-y mat4-rot-z
         mat4-scaling mat4-ortho mat4-perspective mat4-look-at)

(define mat4-translate translation-matrix)
(define mat4-rot-x rotation-x-matrix)
(define mat4-rot-y rotation-y-matrix)
(define mat4-rot-z rotation-z-matrix)
(define mat4-scaling scaling-matrix)
(define mat4-ortho ortho-matrix)
(define mat4-perspective perspective-matrix)
(define mat4-look-at look-at-matrix)
