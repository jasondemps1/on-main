;;;; smoke.lisp --- Boot on-main.lisp and check the main-thread queue end to end
;;;;
;;;; Run from the repository root:
;;;;   sbcl --non-interactive --load test/smoke.lisp
;;;; With ON_MAIN_BACKEND=slynk|swank and ON_MAIN_LOADER=/path/to/*-loader.lisp
;;;; it also starts the real server and checks it didn't block the main thread.
;;;; Exit code: 0 all passed, 1 failures, 2 timed out.

(in-package #:cl-user)

(defparameter *on-main-backend*
  (let ((backend (sb-ext:posix-getenv "ON_MAIN_BACKEND")))
    (if (and backend (plusp (length backend)))
        (intern (string-upcase backend) :keyword)
        :none)))
(defparameter *on-main-port* 0)            ; any free port
(defparameter *on-main-after-start*
  (let ((checks (merge-pathnames "checks.lisp" *load-truename*)))
    (lambda () (load checks))))

;; Watchdog: a hang is a failure, not a stuck CI job.
(sb-thread:make-thread
 (lambda ()
   (sleep 60)
   (format t "~&TIMEOUT~%")
   (finish-output)
   (sb-ext:exit :code 2 :abort t))
 :name "watchdog")

(load (merge-pathnames "../on-main.lisp" *load-truename*))
