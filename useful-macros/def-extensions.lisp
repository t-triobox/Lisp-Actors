;; -*- mode: Lisp; coding: UTF-8 -*-
;; Define-Extensions for Common Lisp
;; DM/RAL 02/21
;; ----------------------------------

(defpackage :com.ral.useful-macros.def-extensions
  (:use :common-lisp :com.ral.useful-macros)
  (:export
   :λ
   :∂
   :µ
   :lambda*
   :defun*
   :labels*
   :flet*
   :deflex
   ))

(in-package #:com.ral.useful-macros.def-extensions)

#+:LISPWORKS
(progn
  (editor:bind-string-to-key "λ" #\not-sign) ;; Option-L on Mac keyboard
  (editor:setup-indent "µ" 1)
  (editor:setup-indent "∂" 1)
  (editor:setup-indent "λ" 1)
  #|
  (editor:setup-indent "define" 1)
  (editor:setup-indent "define*" 1)
  (editor:setup-indent "define-macro" 1)
  (editor:setup-indent "define-generic" 1)
  (editor:setup-indent "define-method" 1)
  |#
  (editor:setup-indent "lambda*" 1 2 8)
  (editor:setup-indent "defun*"  2 2 7)
  (editor:setup-indent "labels*" 1 2 4 'flet)
  (editor:setup-indent "flet*"   1 2 4 'flet)
  (editor:setup-indent "deflex" 1 2 4))

;; --------------------------------------------------

(defun parse-body (body &key documentation whole)
  "Parses BODY into (values remaining-forms declarations doc-string).
Documentation strings are recognized only if DOCUMENTATION is true.
Syntax errors in body are signalled and WHOLE is used in the signal
arguments when given."
  (let (doc decls current)
    (tagbody
     :declarations
     (setf current (car body))
     (when (and documentation (stringp current) (cdr body))
       (if doc
           (error "Too many documentation strings in ~S." (or whole body))
         (push (pop body) doc)) ;; Alexandira fails here...
       (go :declarations))
     (when (and (listp current) (eql (first current) 'declare))
       (push (pop body) decls)
       (go :declarations)))
    (values body (nreverse decls) doc)))

(defun is-lambda-list-keyword? (arg)
  (member arg lambda-list-keywords))

(unless (fboundp 'dotted-list-p)
  ;; Lispworks already has this function, but SBCL does not
  (defun dotted-list-p (lst)
    (and (consp lst)
         (do  ((hd  (cdr lst)  (cdr hd)))
             ((not (consp hd))  (not (null hd)))
           ))))

(defun destr-lambda-list-p (args)
  (and (consp args)
       (or (eq (car args) '&whole)
           (dotted-list-p args)
           (some 'consp (subseq args 0
                                (position-if #'is-lambda-list-keyword? args))
                 ))))

(defun is-underscore? (x)
  (and (symbolp x)
       (string= "_" (string x))))

(defun us-conv (args)
  (labels ((conv (args igns)
             (cond ((atom args)
                    (if (is-underscore? args)
                        (let ((usarg (gensym)))
                          (values usarg (cons usarg igns)))
                      (values args igns)))
                   (t
                    (multiple-value-bind (new-hd new-igns)
                        (conv (car args) igns)
                      (multiple-value-bind (new-tl new-igns)
                          (conv (cdr args) new-igns)
                        (values (cons new-hd new-tl) new-igns))))
                   )))
    (multiple-value-bind (new-args igns)
        (conv args nil)
      (if (listp new-args)
          (values new-args igns)
        (values `(&rest ,new-args) igns))
      )))

(defun decl-us (igns)
  (when igns
    `((declare (ignore ,@igns)))
    ))

(defun wrap-assembly (name args &rest body)
  (multiple-value-bind (wargs wigns)
      (us-conv args)
    (if (destr-lambda-list-p wargs)
        (let ((g!args (gensym)))
          (multiple-value-bind (body-forms decls docstr)
              (parse-body body :documentation t)
            `(,name (&rest ,g!args)
                    ,@docstr
                    (destructuring-bind ,wargs ,g!args
                      ,@decls
                      ,@(decl-us wigns)
                      ,@body-forms))
            ))
      ;; else
      `(,name ,wargs ,@(decl-us wigns) ,@body))
    ))
  
(defun wrap-bindings (hd bindings body)
  `(,hd ,(mapcar (lambda (form)
                   (apply #'wrap-assembly form))
                 bindings)
        ,@body))

;; ---------------------------------------

(defmacro µ (name args &body body)
  `(defmacro ,name ,args ,@body))

(defmacro ∂ (name args &body body)
  `(defun* ,name ,args ,@body))

(defmacro λ (args &body body)
  `(lambda* ,args ,@body))

#+:LISPWORKS
(dspec:define-dspec-alias µ (name)
  `(defmacro ,name))

#+:LISPWORKS
(dspec:define-dspec-alias ∂ (name)
  `(defun ,name))

#+:LISPWORKS
(dspec:define-dspec-alias defun* (name)
  `(defun ,name))

;; ---------------------------------------

(µ defun* (name args &body body)
  `(defun ,@(apply #'wrap-assembly name args body)))

(µ lambda* (args &body body)
  (apply #'wrap-assembly 'lambda args body))

#|
(µ define (item &body body)
  (if (consp item)
      `(defun ,(car item) ,(cdr item) ,@body)
    `(deflex ,item ,@body)))
  
(µ define* ((name . args) &body body)
  `(defun* ,name ,args ,@body))

(µ define-macro ((name . args) &body body)
  `(defmacro ,name ,args ,@body))

(µ define-generic ((name . args) &body body)
  `(defgeneric ,name ,args ,@body))

(µ define-method ((name . args) &body body)
  (if (keywordp (car args))
      `(defmethod ,name ,(car args) ,(cdr args) ,@body)
    `(defmethod ,name ,args ,@body)))
|#

(µ labels* (bindings &body body)
  (wrap-bindings 'labels bindings body))
  
(µ flet* (bindings &body body)
  (wrap-bindings 'flet bindings body))
  
(defmacro deflex (var val &optional (doc nil docp))
  "Define a top level (global) lexical VAR with initial value VAL,
  which is assigned unconditionally as with DEFPARAMETER. If a DOC
  string is provided, it is attached to both the name |VAR| and the
  name *STORAGE-FOR-DEFLEX-VAR-|VAR|* as a documentation string of
  kind 'VARIABLE. The new VAR will have lexical scope and thus may be
  shadowed by LET bindings without affecting its dynamic (global) value."
  (let* ((s0 (symbol-name '#:*storage-for-deflex-var-))
	 (s1 (symbol-name var))
	 (s2 (symbol-name '#:*))
	 (s3 (symbol-package var))	; BUGFIX [see above]
	 (backing-var (intern (concatenate 'string s0 s1 s2) s3)))
    ;; Note: The DEFINE-SYMBOL-MACRO must be the last thing we do so
    ;; that the value of the form is the symbol VAR.
    (if docp
      `(progn
         ;; dbm/ral - 02/22 put symbol-macro first, to support self-recursive defs
	 (define-symbol-macro ,var ,backing-var)
	 (defparameter ,backing-var ,val ,doc)
	 (setf (documentation ',var 'variable) ,doc)
         ',var)
      `(progn
	 (define-symbol-macro ,var ,backing-var)
	 (defparameter ,backing-var ,val)
         ',var)))
  ;;; DEFLEX is
  ;;; Copyright (c) 2003-2007, 2011 Rob Warnock <rpw3@rpw3.org>.
  ;;; All Rights Reserved.
  ;;;
  ;;; Permission to use, copy, modify, and/or distribute this software for any
  ;;; purpose with or without fee is hereby granted, provided that the above
  ;;; copyright notice and this permission notice appear in all copies.
  ;;;
  ;;; THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
  ;;; WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
  ;;; MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
  ;;; ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
  ;;; WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
  ;;; ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
  ;;; OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
)

