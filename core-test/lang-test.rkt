#lang glsl

;; ============================================================
;; lang-test.rkt —— #lang glsl 顶层入口端到端测试（非 GL）
;;
;; 运行：racket core-test/lang-test.rkt
;; 验证 #lang glsl 把三部分都装好：
;;   Part 1 语言：(glsl ...) 宏 / 接口反射 / 源映射 / glsl-unquote
;;   Part 2 值层：GLSL 风格构造与运算（vec3 / vadd / mat4-* / glsl-struct / gl-vec）
;;   Part 3+胶水：gl-* 与 compile-shader / link-program 可用
;; 注意：本文件是「(glsl) 外」的普通 Racket 代码；同一符号 vec3 在 (glsl ...) 内是
;;       GLSL 类型、在这里是 f32vector 构造函数——两套命名空间互不干扰。
;; ============================================================

(require rackunit racket/string)

;; ---------- (glsl ...) 宏 → glsl-program ----------

(define vert
  (glsl (version 330 core)
        (layout (location 0) in vec3 aPos)
        (layout (location 1) in vec3 aColor)
        (uniform mat4 uMVP)
        (out vec3 vColor)
        (define (main) void
          (set! vColor aColor)
          (set! gl_Position (* uMVP (vec4 aPos 1.0))))))

(check-true (glsl-program? vert))

(define src (glsl-program-src vert))
(check-true (string-contains? src "#version 330 core"))
(check-true (string-contains? src "layout(location = 0) in vec3 aPos;"))
(check-true (string-contains? src "gl_Position = (uMVP * vec4(aPos, 1.0));"))

;; ---------- 接口反射 ----------

(define ifc (glsl-program-interface vert))
(define mvp (glsl-interface-ref ifc 'uMVP))
(check-true (and mvp #t))
(check-true (glsl-var-has-qualifier? mvp 'uniform))
(check-equal? (glsl-type-name (glsl-var-type mvp)) 'mat4)
(check-equal? (glsl-var-layout-ref (glsl-interface-ref ifc 'aPos) 'location) 0)
(check-equal? (map glsl-var-name (glsl-interface-vars-with-qualifier ifc 'in))
              '(aPos aColor))
(check-equal? (map glsl-var-name (glsl-interface-vars-with-kind ifc 'sampler)) '())

;; ---------- 源映射（行级：GLSL 行 → 顶层 form） ----------

(define uMVP-line
  (for/first ([l (in-list (string-split src "\n"))] [i (in-naturals 1)]
              #:when (string=? l "uniform mat4 uMVP;"))
    i))
(check-true (and uMVP-line #t))
(check-true (and (glsl-program-lookup vert uMVP-line) #t))

;; ---------- glsl-unquote ----------

(define injected "#define N 8")
(define frag
  (glsl (version 330 core)
        (glsl-unquote injected)
        (out vec4 F)
        (define (main) void
          (set! F (vec4 1.0 0.5 0.2 1.0)))))
(check-true (string-contains? (glsl-program-src frag) "#define N 8"))

;; ---------- CPU 侧值 API（GLSL 风格名） ----------

(check-true (f32vector? (vec3 1.0 2.0 3.0)))
(check-equal? (f32vector->list (vadd (vec2 1.0 2.0) (vec2 3.0 4.0))) '(4.0 6.0))
(check-equal? (vcount (vec4 1.0 2.0 3.0 4.0)) 4)
(check-equal? (glsl-size 'vec3) 3)
(check-equal? (glsl-byte-size 'vec3) 12)
(check-equal? (glsl-stride-bytes 'vec3 'vec2) 20)

(define M (mat4-look-at (vec3 0.0 0.0 5.0) (vec3 0.0 0.0 0.0) (vec3 0.0 1.0 0.0)))
(check-equal? (vz (mat4-mul-vec M (vec4 0.0 0.0 0.0 1.0))) -5.0)

(glsl-struct vertex (vec3 pos) (vec3 color))
(define v0 (vertex (vec3 1.0 2.0 3.0) (vec3 1.0 0.0 0.0)))
(check-equal? (f32vector->list (vertex->f32vector v0)) '(1.0 2.0 3.0 1.0 0.0 0.0))
(check-equal? (vertex-stride) 24)
(check-equal? (vertex-field-offset 'color) 12)
(check-equal? (vertex-field-size 'pos) 3)

(define gv (gl-vec (vec2 -0.5 -0.5) (vec2 0.5 -0.5) (vec2 0.0 0.5)))
(check-equal? (gl-vec-count gv) 3)
(check-equal? (f32vector->list (gl-vec->f32vector gv)) '(-0.5 -0.5 0.5 -0.5 0.0 0.5))

;; ---------- Part 3 + 胶水符号可用 ----------

(check-true (procedure? gl-create-shader))
(check-true (procedure? compile-shader))
(check-true (procedure? link-program))
(check-true (procedure? parse-gl-error-log))

(displayln "lang 全部测试通过")
