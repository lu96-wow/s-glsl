#lang racket/base

;; ============================================================
;; control-flow-gl-test.rkt —— 控制流嵌套的 GL 实编译测试
;;
;; 运行：racket core-test/control-flow-gl-test.rkt   （需要显示器 + GL 3.3+）
;; 把多层 when/for/while/do-while/cond/switch + break/continue/discard 的 GLSL
;; 真的交给驱动编译链接，确认语法被接受（不只是文本层正确）。
;; ============================================================

(require rackunit
         ffi/vector
         racket/gui
         "../core/opengl/rename.rkt"
         "../core/glsl/rewrite.rkt"
         "../core/tool/program.rkt")

;; 离屏 GL 上下文（同 double-test）
(define cfg (new gl-config%))
(send cfg set-legacy? #f)
(send cfg set-double-buffered #t)
(define frame (new frame% (label "control-flow-gl-test")))
(define canvas (new canvas% (style '(gl no-autoclear)) (gl-config cfg) (parent frame)))

(define vert-src
  (glsl (version 330 core)
        (layout (location 0) in vec2 aPos)
        (uniform int uMode)
        (out vec3 vColor)
        (define (main) void
          (float acc 0.0)
          ;; for > when > while(continue) + do-while
          (for (int i 0) (< i 4) (++ i)
            (when (> (float i) 0.0)
              (int j 0)
              (while (< j 3)
                (when (= j 1)
                  (++ j)
                  (continue))
                (+= acc (float j))
                (++ j))
              (do-while (< acc 100.0)
                (*= acc 1.5)))
            ;; cond = if / else if / else，含 break
            (cond [(= i 2) (break)]
                  [(> i 3) (set! acc 0.0)]
                  [else    (+= acc 1.0)]))
          ;; switch 嵌套（case 内再 for）
          (switch uMode
            [case 0 (for (int k 0) (< k 2) (++ k) (set! acc (+ acc (float k))))]
            [case 1 (when (> acc 0.0) (set! acc (* acc 2.0)))]
            [default (set! acc 0.3)])
          (set! vColor (vec3 acc acc acc))
          (set! gl_Position (vec4 aPos 0.0 1.0)))))

(define frag-src
  (glsl (version 330 core)
        (in vec3 vColor)
        (out vec4 FragColor)
        (define (main) void
          ;; for > when > discard
          (for (int i 0) (< i 4) (++ i)
            (when (< (x vColor) 0.5) (discard)))
          (set! FragColor (vec4 vColor 1.0)))))

(send canvas with-gl-context
  (lambda ()
    (define prog (build-program (gl-vertex-shader vert-src)
                                (gl-fragment-shader frag-src)))
    (check-true (> prog 0))
    (displayln "control-flow GL compile ok")))
