#lang racket/base

;; ============================================================
;; opengl-rename.rkt —— OpenGL 命名统一层（kebab-case）
;;
;; opengl 包沿用的是 C 的原始命名，两种风格混在一起：
;;   函数：glGenBuffers、glBufferData、glDrawArrays（驼峰式）
;;   常量：GL_ARRAY_BUFFER、GL_TRIANGLES（全大写 + 下划线）
;;
;; 教程统一改成 Racket 习惯的 kebab-case（全小写 + 连字符）：
;;   函数：glGenBuffers    →  gl-gen-buffers
;;         glDrawArrays    →  gl-draw-arrays
;;   常量：GL_ARRAY_BUFFER →  gl-array-buffer
;;         GL_TRIANGLES    →  gl-triangles
;;
;; 换算规则（三条）：
;;   1. 常量：去掉 GL_ 前缀 → 全小写 → 下划线换成连字符
;;        GL_ARRAY_BUFFER → array-buffer → gl-array-buffer
;;   2. 函数：驼峰拆成单词 → 全小写 → 连字符连接
;;        glGenBuffers → gen buffers → gl-gen-buffers
;;   3. 类型后缀（数字 + 字母，如 1f / 3f / iv / fv）算一个单词
;;        glUniform1f   → gl-uniform-1f
;;        glGetShaderiv → gl-get-shader-iv
;;   例外：函数与常量换算后同名时（如 glCullFace 与 GL_CULL_FACE 都成了 gl-cull-face），
;;        函数保留 gl-*，常量（变量）改加 var- 前缀 → var-cull-face。
;;
;; 用法：require 本模块后，代码里只写 kebab-case 的 gl-* 名字；
;;       原始驼峰名不再直接出现在教程代码里。
;;       需要某个还没收录的函数/常量时，按上面三条规则把它补进下面两段。
;; double 精度（dvec/dmat/double）的专属函数也已收录。教程主线用 float，这些先备着。
;; ============================================================

(require opengl)

(provide
 ;; 所有改名都在下面两个 define 段里定义，用 all-defined-out 整体转出，
 ;; 新增/删除名字时无需同步维护 provide 列表。
 (all-defined-out)
 ;; 唯一例外：gl-vector-sizeof 是 opengl 包自带的工具函数（本就 kebab-case），
 ;; 不是本模块 define 出来的，所以仍要显式转出。
 gl-vector-sizeof)

;; ---------- 函数：驼峰 → kebab-case ----------

(define gl-active-texture             glActiveTexture)
(define gl-attach-shader              glAttachShader)
(define gl-begin                      glBegin)
(define gl-bind-buffer                glBindBuffer)
(define gl-bind-framebuffer           glBindFramebuffer)
(define gl-bind-renderbuffer          glBindRenderbuffer)
(define gl-bind-texture               glBindTexture)
(define gl-bind-vertex-array          glBindVertexArray)
(define gl-blend-func                 glBlendFunc)
(define gl-blit-framebuffer           glBlitFramebuffer)
(define gl-buffer-data                glBufferData)
(define gl-buffer-sub-data            glBufferSubData)
(define gl-check-framebuffer-status   glCheckFramebufferStatus)
(define gl-clear                      glClear)
(define gl-clear-color                glClearColor)
(define gl-compile-shader             glCompileShader)
(define gl-create-program             glCreateProgram)
(define gl-create-shader              glCreateShader)
(define gl-cull-face                  glCullFace)
(define gl-delete-framebuffers        glDeleteFramebuffers)
(define gl-delete-program             glDeleteProgram)
(define gl-delete-renderbuffers       glDeleteRenderbuffers)
(define gl-delete-shader              glDeleteShader)
(define gl-delete-textures            glDeleteTextures)
(define gl-depth-mask                 glDepthMask)
(define gl-disable                    glDisable)
(define gl-draw-arrays                glDrawArrays)
(define gl-draw-elements              glDrawElements)
(define gl-draw-elements-instanced    glDrawElementsInstanced)
(define gl-enable                     glEnable)
(define gl-enable-vertex-attrib-array glEnableVertexAttribArray)
(define gl-end                        glEnd)
(define gl-framebuffer-renderbuffer   glFramebufferRenderbuffer)
(define gl-framebuffer-texture-2d     glFramebufferTexture2D)
(define gl-front-face                 glFrontFace)
(define gl-gen-buffers                glGenBuffers)
(define gl-gen-framebuffers           glGenFramebuffers)
(define gl-gen-renderbuffers          glGenRenderbuffers)
(define gl-gen-textures               glGenTextures)
(define gl-gen-vertex-arrays          glGenVertexArrays)
(define gl-generate-mipmap            glGenerateMipmap)
(define gl-get-program-info-log       glGetProgramInfoLog)
(define gl-get-program-iv             glGetProgramiv)
(define gl-get-shader-info-log        glGetShaderInfoLog)
(define gl-get-shader-iv              glGetShaderiv)
(define gl-get-uniform-location       glGetUniformLocation)
(define gl-line-width                 glLineWidth)
(define gl-link-program               glLinkProgram)
(define gl-pixel-store-i              glPixelStorei)
(define gl-renderbuffer-storage       glRenderbufferStorage)
(define gl-renderbuffer-storage-multisample glRenderbufferStorageMultisample)
(define gl-shader-source              glShaderSource)
(define gl-tex-image-2d               glTexImage2D)
(define gl-tex-parameter-i            glTexParameteri)
(define gl-uniform-1f                 glUniform1f)
(define gl-uniform-1i                 glUniform1i)
(define gl-uniform-3f                 glUniform3f)
(define gl-uniform-4f                 glUniform4f)
(define gl-uniform-1d                 glUniform1d)
(define gl-uniform-2d                 glUniform2d)
(define gl-uniform-3d                 glUniform3d)
(define gl-uniform-4d                 glUniform4d)
(define gl-uniform-matrix-2dv         glUniformMatrix2dv)
(define gl-uniform-matrix-3dv         glUniformMatrix3dv)
(define gl-uniform-matrix-4dv         glUniformMatrix4dv)
(define gl-uniform-matrix-4fv         glUniformMatrix4fv)
(define gl-use-program                glUseProgram)
(define gl-vertex-attrib-divisor      glVertexAttribDivisor)
(define gl-vertex-attrib-pointer      glVertexAttribPointer)
(define gl-vertex-attrib-l-pointer    glVertexAttribLPointer)
(define gl-vertex-attrib-l-1d         glVertexAttribL1d)
(define gl-vertex-attrib-l-2d         glVertexAttribL2d)
(define gl-vertex-attrib-l-3d         glVertexAttribL3d)
(define gl-vertex-attrib-l-4d         glVertexAttribL4d)
(define gl-viewport                   glViewport)

;; ---------- 常量：全大写下划线 → kebab-case ----------

(define gl-array-buffer            GL_ARRAY_BUFFER)
(define gl-blend                   GL_BLEND)
(define gl-ccw                     GL_CCW)
(define gl-clamp-to-edge           GL_CLAMP_TO_EDGE)
(define gl-color-attachment0       GL_COLOR_ATTACHMENT0)
(define gl-color-buffer-bit        GL_COLOR_BUFFER_BIT)
(define gl-compile-status          GL_COMPILE_STATUS)
(define var-cull-face               GL_CULL_FACE)
(define gl-cw                      GL_CW)
(define gl-depth-attachment        GL_DEPTH_ATTACHMENT)
(define gl-depth-buffer-bit        GL_DEPTH_BUFFER_BIT)
(define gl-depth-component16       GL_DEPTH_COMPONENT16)
(define gl-depth-component24       GL_DEPTH_COMPONENT24)
(define gl-depth-test              GL_DEPTH_TEST)
(define gl-double                  GL_DOUBLE)
(define gl-draw-framebuffer        GL_DRAW_FRAMEBUFFER)
(define gl-dynamic-draw            GL_DYNAMIC_DRAW)
(define gl-element-array-buffer    GL_ELEMENT_ARRAY_BUFFER)
(define gl-false                   GL_FALSE)
(define gl-float                   GL_FLOAT)
(define gl-fragment-shader         GL_FRAGMENT_SHADER)
(define gl-framebuffer             GL_FRAMEBUFFER)
(define gl-framebuffer-complete    GL_FRAMEBUFFER_COMPLETE)
(define gl-geometry-shader         GL_GEOMETRY_SHADER)
(define gl-info-log-length         GL_INFO_LOG_LENGTH)
(define gl-line-loop               GL_LINE_LOOP)
(define gl-line-strip              GL_LINE_STRIP)
(define gl-linear                  GL_LINEAR)
(define gl-linear-mipmap-linear    GL_LINEAR_MIPMAP_LINEAR)
(define gl-lines                   GL_LINES)
(define gl-link-status             GL_LINK_STATUS)
(define gl-nearest                 GL_NEAREST)
(define gl-one-minus-src-alpha     GL_ONE_MINUS_SRC_ALPHA)
(define gl-points                  GL_POINTS)
(define gl-r8                      GL_R8)
(define gl-read-framebuffer        GL_READ_FRAMEBUFFER)
(define gl-red                     GL_RED)
(define gl-renderbuffer            GL_RENDERBUFFER)
(define gl-repeat                  GL_REPEAT)
(define gl-rgba                    GL_RGBA)
(define gl-rgba8                   GL_RGBA8)
(define gl-src-alpha               GL_SRC_ALPHA)
(define gl-static-draw             GL_STATIC_DRAW)
(define gl-stream-draw             GL_STREAM_DRAW)
(define gl-tess-control-shader     GL_TESS_CONTROL_SHADER)
(define gl-tess-evaluation-shader  GL_TESS_EVALUATION_SHADER)
(define gl-texture0                GL_TEXTURE0)
(define gl-texture-2d              GL_TEXTURE_2D)
(define gl-texture-mag-filter      GL_TEXTURE_MAG_FILTER)
(define gl-texture-min-filter      GL_TEXTURE_MIN_FILTER)
(define gl-texture-wrap-s          GL_TEXTURE_WRAP_S)
(define gl-texture-wrap-t          GL_TEXTURE_WRAP_T)
(define gl-triangle-fan            GL_TRIANGLE_FAN)
(define gl-triangle-strip          GL_TRIANGLE_STRIP)
(define gl-triangles               GL_TRIANGLES)
(define gl-unpack-alignment        GL_UNPACK_ALIGNMENT)
(define gl-unsigned-byte           GL_UNSIGNED_BYTE)
(define gl-unsigned-int            GL_UNSIGNED_INT)
(define gl-unsigned-short          GL_UNSIGNED_SHORT)
(define gl-vertex-shader           GL_VERTEX_SHADER)

;; gl-vector-sizeof 是 opengl 包自带的 Racket 工具函数，本来就 kebab-case，
;; 不是本模块 define 出来的——所以靠显式 provide 转出（all-defined-out 不含它）。
