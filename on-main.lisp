;;;; on-main.lisp --- Boot Slynk/Swank with SBCL's main thread reserved for ON-MAIN
;;;;
;;;; SPDX-License-Identifier: MIT
;;;;
;;;; macOS only allows windowing (Cocoa, and so GLFW, SDL, raylib...) on the
;;;; process's main thread. Loading this file starts Slynk or Swank in its own
;;;; threads, then hands the main thread to a queue that runs whatever you send
;;;; it with ON-MAIN:RUN or ON-MAIN:CALL. Loading never returns.
;;;;
;;;; Normally Emacs loads this for you (M-x on-main-sly / M-x on-main-slime),
;;;; binding the CL-USER::*ON-MAIN-...* variables below first.
;;;;
;;;; Terminal use, from your project root:
;;;;   sbcl --load /path/to/on-main.lisp
;;;; then M-x sly-connect (or slime-connect) RET localhost RET 4005.
;;;; Environment variables: ON_MAIN_BACKEND (slynk | swank, default slynk),
;;;; ON_MAIN_LOADER (path to slynk-loader.lisp / swank-loader.lisp),
;;;; ON_MAIN_PORT (default 4005), ON_MAIN_PROJECT_ROOT (default: the current
;;;; directory). Without ON_MAIN_LOADER the loader path is
;;;; requested from a running Emacs via emacsclient (needs `server-start').

(in-package #:cl-user)

(require :asdf)
(require :sb-concurrency)

;;; Configuration, set by Emacs before loading (or left NIL for defaults).

(defvar *on-main-backend* nil
  "Server backend: :SLYNK, :SWANK, or :NONE (no server; used by the tests).")

(defvar *on-main-loader* nil
  "Path to slynk-loader.lisp or swank-loader.lisp.")

(defvar *on-main-port-file* nil
  "Port file the editor is waiting on. NIL means listen on a TCP port instead.")

(defvar *on-main-project-root* nil
  "Directory added to ASDF's search path so the project's .asd is found.
Defaults to $ON_MAIN_PROJECT_ROOT, then the current directory.")

(defvar *on-main-port* nil
  "TCP port for terminal use. Defaults to $ON_MAIN_PORT, then 4005.")

(defvar *on-main-after-start* nil
  "Function to call in a new thread once the server is up, or NIL.")

(defpackage #:on-main
  (:use #:cl)
  (:export #:run #:call #:main-thread-p #:queue-length))

(in-package #:on-main)

;;; Public API

(defvar *queue* (sb-concurrency:make-mailbox :name "on-main")
  "Functions waiting to run on the main thread.")

(defun main-thread-p ()
  "True if the current thread is the process's main thread."
  (eq sb-thread:*current-thread* (sb-thread:main-thread)))

(defun run (function)
  "Queue FUNCTION to run on the main thread and return immediately.
Pass a symbol (e.g. 'my-app::game-loop) so its current definition is used.
Errors inside FUNCTION invoke the debugger on the main thread; its ABORT
restart returns the main thread to the queue."
  (sb-concurrency:send-message *queue* function)
  (values))

(defun call (function &key timeout)
  "Run FUNCTION on the main thread, wait, and return its values.
Errors are re-signalled in the calling thread. While something long-running
(such as a game loop) occupies the main thread, CALL waits for it to finish;
with TIMEOUT (seconds) it signals an error instead of waiting longer."
  (if (main-thread-p)
      (funcall function)
      (let ((reply (sb-concurrency:make-mailbox :name "on-main reply")))
        (run (lambda ()
               (sb-concurrency:send-message
                reply
                (handler-case (cons :ok (multiple-value-list (funcall function)))
                  (error (condition) (cons :error condition))))))
        (multiple-value-bind (result receivedp)
            (sb-concurrency:receive-message reply :timeout timeout)
          (cond ((not receivedp)
                 (error "Main thread didn't respond within ~A s. ~
                         Is a loop running on it?" timeout))
                ((eq (car result) :ok) (values-list (cdr result)))
                (t (error (cdr result))))))))

(defun queue-length ()
  "Number of functions waiting for the main thread."
  (sb-concurrency:mailbox-count *queue*))

;;; Booting the server

(defun env (name)
  (let ((value (sb-ext:posix-getenv name)))
    (and value (plusp (length value)) value)))

(defun backend ()
  (or cl-user::*on-main-backend*
      (let ((name (env "ON_MAIN_BACKEND")))
        (and name (intern (string-upcase name) :keyword)))
      :slynk))

(defun loader-from-emacs (backend)
  "Ask a running Emacs where the editor's loader file lives. NIL on failure."
  (ignore-errors
   (let ((path (read-from-string
                (uiop:run-program
                 (list "emacsclient" "--eval"
                       (ecase backend
                         (:slynk "(expand-file-name sly-slynk-loader-backend (sly-slynk-path))")
                         (:swank "(expand-file-name slime-backend slime-path)")))
                 :output :string))))
     (and (stringp path) (probe-file path) path))))

(defun resolve-loader (backend)
  (or cl-user::*on-main-loader*
      (env "ON_MAIN_LOADER")
      (loader-from-emacs backend)
      (error "Can't find the ~(~A~) loader. Start from Emacs with ~
              M-x on-main-~:*~(~A~), set ON_MAIN_LOADER, or run ~
              `server-start' in Emacs." backend)))

(defun port ()
  (or cl-user::*on-main-port*
      (let ((port (env "ON_MAIN_PORT"))) (and port (parse-integer port)))
      4005))

(defun register-project-root ()
  "Make the project's .asd files findable by ASDF (additive; existing
source-registry configuration, e.g. from ocicl or Quicklisp, is untouched)."
  (let ((root (uiop:ensure-directory-pathname
               (or cl-user::*on-main-project-root*
                   (env "ON_MAIN_PROJECT_ROOT")
                   (uiop:getcwd)))))
    (pushnew root asdf:*central-registry* :test #'equal)))

(defun start-server (backend)
  "Load and start BACKEND's server in its own threads."
  (let ((package (ecase backend (:slynk "SLYNK") (:swank "SWANK")))
        (port-file cl-user::*on-main-port-file*))
    (load (resolve-loader backend))
    (ecase backend
      (:slynk (uiop:symbol-call :slynk-loader :init))
      (:swank (uiop:symbol-call :swank-loader :init :from-emacs (and port-file t))))
    ;; :SPAWN is essential. Other styles serve the connection from the
    ;; calling thread -- the main thread -- and never return.
    (setf (symbol-value (find-symbol "*COMMUNICATION-STYLE*" package)) :spawn)
    (if port-file
        (uiop:symbol-call package :start-server port-file
                          :style :spawn :dont-close t)
        (uiop:symbol-call package :create-server :port (port)
                          :style :spawn :dont-close t))))

(defun serve ()
  "Run queued functions on the main thread, forever."
  (loop
    (with-simple-restart (abort "Return to the on-main queue")
      (funcall (sb-concurrency:receive-message *queue*)))))

(defun boot ()
  (unless (main-thread-p)
    (warn "on-main.lisp was loaded from a non-main thread; ~
           queued functions will never run.")
    (return-from boot))
  (register-project-root)
  (let ((backend (backend)))
    (unless (eq backend :none)
      (start-server backend)))
  (when cl-user::*on-main-after-start*
    (sb-thread:make-thread cl-user::*on-main-after-start*
                           :name "on-main after-start"))
  (serve))

(boot)
