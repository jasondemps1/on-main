;;;; checks.lisp --- Assertions run by smoke.lisp once on-main has booted.
;;;; Loaded in a non-main thread, after the ON-MAIN package exists.

(in-package #:cl-user)

(defvar *failures* 0)

(defmacro check (name form)
  `(handler-case
       (if ,form
           (format t "~&ok    ~A~%" ,name)
           (progn (incf *failures*) (format t "~&FAIL  ~A~%" ,name)))
     (error (e)
       (incf *failures*)
       (format t "~&FAIL  ~A: ~A~%" ,name e))))

(format t "~&backend: ~S~%" *on-main-backend*)

(check "this checking thread is not the main thread"
       (not (on-main:main-thread-p)))

(unless (eq *on-main-backend* :none)
  (check "server uses the :spawn communication style"
         (eq :spawn
             (symbol-value
              (find-symbol "*COMMUNICATION-STYLE*"
                           (ecase *on-main-backend*
                             (:slynk "SLYNK") (:swank "SWANK")))))))

(check "CALL runs on the main thread"
       (on-main:call #'on-main:main-thread-p :timeout 5))

(check "CALL returns multiple values"
       (equal '(1 2)
              (multiple-value-list
               (on-main:call (lambda () (values 1 2)) :timeout 5))))

(check "CALL accepts a symbol"
       (eq t (on-main:call 'on-main:main-thread-p :timeout 5)))

(check "CALL re-signals errors in the caller"
       (eq :caught
           (handler-case (on-main:call (lambda () (error "boom")) :timeout 5)
             (error () :caught))))

(check "RUN returns immediately with no values"
       (null (multiple-value-list (on-main:run (constantly nil)))))

(check "CALL times out while the main thread is busy"
       (progn
         (on-main:run (lambda () (sleep 1)))
         (eq :timed-out
             (handler-case (on-main:call (constantly t) :timeout 0.2)
               (error () :timed-out)))))

(check "the queue drains once the main thread is free"
       (on-main:call (constantly t) :timeout 5))

(format t "~&~D failure(s)~%" *failures*)
(finish-output)
(sb-ext:exit :code (if (zerop *failures*) 0 1) :abort t)
