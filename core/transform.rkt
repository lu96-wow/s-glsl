#lang racket/base

;; ============================================================
;; transform.rkt —— 常用变换构造（场景 / 相机约定层）
;;
;; 与 vec-math.rkt 的分工：
;;   vec-math.rkt  = 取用 + 运算（GLSL 内建的 CPU 镜像：dot/cross/normalize/
;;                   mat-mul/inverse/transpose…）——判据是「GLSL 里有对应物」。
;;   transform.rkt = 变换构造（GLSL **没有**这些，是图形学的参数化约定：
;;                   右手系、列主序、角度制）——建立在 vec-math 之上。
;;
;;   模型矩阵（摆物体）：mat4-translate / mat4-rot-x/y/z / mat4-scaling
;;   视图矩阵（摆相机）：mat4-look-at
;;   投影矩阵（镜头）  ：mat4-ortho / mat4-perspective
;;
;; 约定：右手系、列主序、旋转角用「度」。
;; ============================================================

(require "rename-vector.rkt"   ; mat4 构造器
         "vec-math.rkt")       ; vsub / vcross / vnormalize / vdot / vx / vy / vz

(provide mat4-translate mat4-rot-x mat4-rot-y mat4-rot-z mat4-scaling
         mat4-ortho mat4-perspective mat4-look-at)

(define pi (acos -1.0))
(define (rad deg) (* (/ pi 180.0) deg))

;; 平移：单位阵第 4 列放 (x,y,z,1)
(define (mat4-translate x y z)
  (mat4 1.0 0.0 0.0 0.0
        0.0 1.0 0.0 0.0
        0.0 0.0 1.0 0.0
        x   y   z   1.0))

;; 绕 X 轴旋转 deg 度
(define (mat4-rot-x deg)
  (define c (cos (rad deg))) (define s (sin (rad deg)))
  (mat4 1.0 0.0 0.0 0.0
        0.0 c   s   0.0
        0.0 (- s) c 0.0
        0.0 0.0 0.0 1.0))

;; 绕 Y 轴旋转 deg 度
(define (mat4-rot-y deg)
  (define c (cos (rad deg))) (define s (sin (rad deg)))
  (mat4 c     0.0 s   0.0
        0.0   1.0 0.0 0.0
        (- s) 0.0 c   0.0
        0.0   0.0 0.0 1.0))

;; 绕 Z 轴旋转 deg 度
(define (mat4-rot-z deg)
  (define c (cos (rad deg))) (define s (sin (rad deg)))
  (mat4 c     s     0.0 0.0
        (- s) c     0.0 0.0
        0.0   0.0   1.0 0.0
        0.0   0.0   0.0 1.0))

;; 缩放：对角线放 sx/sy/sz
(define (mat4-scaling sx sy sz)
  (mat4 sx  0.0 0.0 0.0
        0.0 sy  0.0 0.0
        0.0 0.0 sz  0.0
        0.0 0.0 0.0 1.0))

;; 正交投影：视景体 l/r/b/t/n/f（左/右/下/上/近/远）
(define (mat4-ortho l r b t n f)
  (define rl (- r l)) (define tb (- t b)) (define fn (- f n))
  (mat4 (/ 2.0 rl) 0.0 0.0 0.0
        0.0 (/ 2.0 tb) 0.0 0.0
        0.0 0.0 (/ -2.0 fn) 0.0
        (- (/ (+ r l) rl)) (- (/ (+ t b) tb)) (- (/ (+ f n) fn)) 1.0))

;; 透视投影：fovy = 垂直视场角（度）；aspect = 宽/高；near/far = 近/远裁剪面
(define (mat4-perspective fovy aspect near far)
  (define f (/ 1.0 (tan (/ (rad fovy) 2.0))))
  (mat4 (/ f aspect) 0.0 0.0 0.0
        0.0 f 0.0 0.0
        0.0 0.0 (/ (+ far near) (- near far)) -1.0
        0.0 0.0 (/ (* 2.0 far near) (- near far)) 0.0))

;; 视图矩阵：相机在 eye，看向 center，头顶朝 up
(define (mat4-look-at eye center up)
  (define f (vnormalize (vsub center eye)))
  (define s (vnormalize (vcross f up)))
  (define u (vcross s f))
  (mat4 (vx s) (vx u) (- (vx f)) 0.0
        (vy s) (vy u) (- (vy f)) 0.0
        (vz s) (vz u) (- (vz f)) 0.0
        (- (vdot s eye)) (- (vdot u eye)) (vdot f eye) 1.0))
