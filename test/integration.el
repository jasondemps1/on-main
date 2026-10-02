;;; integration.el --- End-to-end test: start a Lisp via on-main and query it  -*- lexical-binding: t; -*-

;; Usage (from the repository root):
;;   emacs -Q --batch -L . -L /path/to/sly   -l test/integration.el -f on-main-test-sly
;;   emacs -Q --batch -L . -L /path/to/slime -l test/integration.el -f on-main-test-slime
;;
;; Creates a throwaway project with an .asd, starts Lisp from a buffer in its
;; src/ directory, and checks that: Lisp started in the project root, the
;; system was auto-loaded, and ON-MAIN:CALL runs on the main thread.
;; Exits 0 on success, 1 on failure.

;;; Code:

(require 'cl-lib)

(defvar on-main-test--failures 0)

(defun on-main-test--check (name ok)
  (princ (format "%s  %s\n" (if ok "ok   " "FAIL ") name))
  (unless ok (cl-incf on-main-test--failures)))

(defun on-main-test--make-project ()
  "Create a temp project with an .asd and a src/ file; return its root."
  (let* ((root (file-name-as-directory (make-temp-file "on-main-it-" t)))
         (src (expand-file-name "src/" root)))
    (make-directory src)
    (with-temp-file (expand-file-name "itproj.asd" root)
      (insert "(asdf:defsystem #:itproj :components ((:module \"src\" :components ((:file \"main\")))))\n"))
    (with-temp-file (expand-file-name "main.lisp" src)
      (insert "(defpackage #:itproj (:use #:cl) (:export #:ping))\n(in-package #:itproj)\n(defun ping () :pong)\n"))
    root))

(defun on-main-test--wait (pred seconds what)
  (let ((deadline (+ (float-time) seconds)))
    (while (and (not (funcall pred)) (< (float-time) deadline))
      (accept-process-output nil 0.2))
    (or (funcall pred)
        (progn (princ (format "TIMEOUT waiting for %s\n" what)) nil))))

(defun on-main-test--run (start connected-p busy-p eval quit)
  (require 'on-main)
  (setq inferior-lisp-program (or (getenv "SBCL") "sbcl")
        on-main-load-system t)
  (let* ((root (on-main-test--make-project))
         (default-directory (expand-file-name "src/" root)))
    (funcall start)
    ;; Wait until connected AND the editor's own setup requests (contribs,
    ;; plus our async system load) have finished, so our synchronous evals
    ;; don't interleave with them.
    (when (on-main-test--wait
           (lambda () (and (funcall connected-p) (not (funcall busy-p))))
           180 "connection")
      (on-main-test--check
       "Lisp started in the project root, not src/"
       (equal (file-truename root)
              (file-truename (funcall eval '(cl:namestring (uiop:getcwd))))))
      (on-main-test--check
       "project system auto-loaded after connecting"
       (on-main-test--wait
        (lambda () (funcall eval '(cl:and (cl:find-package "ITPROJ") cl:t)))
        120 "system load"))
      (on-main-test--check
       "REPL requests run off the main thread"
       (null (funcall eval '(on-main:main-thread-p))))
      (on-main-test--check
       "ON-MAIN:CALL runs on the main thread"
       (eq t (funcall eval '(on-main:call (cl:quote on-main:main-thread-p)
                                          :timeout 5))))
      (on-main-test--check
       "the project's code is callable"
       (equal "PONG" (funcall eval '(cl:symbol-name
                                      (cl:funcall (cl:read-from-string "itproj:ping")))))))
    (ignore-errors (funcall quit))
    (princ (format "%d failure(s)\n" on-main-test--failures))
    (kill-emacs (if (zerop on-main-test--failures) 0 1))))

(defun on-main-test-sly ()
  (require 'on-main-sly)
  (on-main-test--run #'on-main-sly #'sly-connected-p #'sly-busy-p
                     #'sly-eval #'sly-quit-lisp))

(defun on-main-test-slime ()
  (require 'on-main-slime)
  (on-main-test--run #'on-main-slime #'slime-connected-p #'slime-busy-p
                     #'slime-eval #'slime-quit-lisp))

;;; integration.el ends here
