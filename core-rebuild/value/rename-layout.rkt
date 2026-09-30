#lang racket/base

;; ============================================================
;; 值层 · value/rename-layout.rkt —— GLSL 风格命名（交错布局）
;;
;; 纯 alias + 宏外观：value/layout.rkt 的 Racket 名 → GLSL 名。零逻辑。
;;   glsl-struct：把 shader 里的 struct 镜像到 CPU 侧。
;; ============================================================

(require "layout.rkt"
         (for-syntax racket/base racket/syntax "type.rkt"))

(provide glsl-struct)

(define-syntax (glsl-struct stx)
  (syntax-case stx ()
    [(_ Name (type field) ...)
     (let* ([types     (syntax->list #'(type ...))]
            [fields    (syntax->list #'(field ...))]
            [type-syms (map syntax->datum types)])
       (when (null? fields)
         (error 'glsl-struct "至少需要一个字段"))
       (define kinds (map type-kind type-syms))
       (when (and (memq 'f32 kinds) (memq 'f64 kinds))
         (error 'glsl-struct "字段不能混用 float/double 精度：~s" type-syms))
       (define all-same? (andmap (lambda (k) (eq? k (car kinds))) kinds))
       (define pack-fmt
         (if all-same?
             (case (car kinds)
               [(f32) "~a->f32vector"]
               [(f64) "~a->f64vector"]
               [(s32) "~a->s32vector"]
               [(u32) "~a->u32vector"])
             "~a->bytes"))
       (with-syntax
         ([types-list   (datum->syntax #'Name type-syms)]
          [to-vec       (format-id #'Name pack-fmt #'Name)]
          [stride-fn    (format-id #'Name "~a-stride" #'Name)]
          [field-offset (format-id #'Name "~a-field-offset" #'Name)]
          [field-size   (format-id #'Name "~a-field-size" #'Name)]
          [(field-acc ...)
           (map (lambda (f) (format-id #'Name "~a-~a" #'Name f)) fields)]
          [(field-clause ...)
           (for/list ([f fields] [i (in-naturals)])
             #`[(#,f) #,i])])
         #'(begin
             (struct Name (field ...) #:transparent)
             (define (to-vec rec)
               (pack-record 'types-list (field-acc rec) ...))
             (define (stride-fn)
               (record-stride-bytes 'types-list))
             (define (field-offset f)
               (list-ref (record-field-offsets 'types-list)
                         (case f
                           field-clause ...
                           [else (error 'field-offset "未知字段：~s" f)])))
             (define (field-size f)
               (record-field-size 'types-list
                                  (case f
                                    field-clause ...
                                    [else (error 'field-size "未知字段：~s" f)]))))))]))
