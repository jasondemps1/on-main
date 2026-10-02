;;; on-main.el --- Run Lisp GUI code on the main thread from Sly or SLIME  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jason Dempsey

;; Author: Jason Dempsey
;; Version: 0.1.0
;; Package-Requires: ((emacs "31.1"))
;; Keywords: lisp, languages, tools
;; URL: https://github.com/jasondemps1/on-main
;; SPDX-License-Identifier: MIT

;;; Commentary:

;; macOS only allows windowing (Cocoa, and so GLFW, SDL, raylib...) on a
;; process's main thread, but Sly and SLIME give that thread to a REPL and
;; evaluate your code elsewhere.  `on-main-sly' and `on-main-slime' start
;; SBCL so that Slynk/Swank run in background threads and the main thread
;; runs whatever you send it with ON-MAIN:RUN or ON-MAIN:CALL.
;;
;; This file holds the shared machinery; the commands live in
;; on-main-sly.el and on-main-slime.el.

;;; Code:

(require 'cl-lib)
(require 'project)
(require 'inf-lisp)                     ; for `inferior-lisp-program'

(defgroup on-main nil
  "Run Lisp GUI code on the main thread from Sly or SLIME."
  :group 'lisp
  :prefix "on-main-")

(defconst on-main--directory
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory this package was loaded from.")

(defcustom on-main-lisp-file (expand-file-name "on-main.lisp" on-main--directory)
  "Lisp file that boots the server and runs the queue on the main thread."
  :type 'file)

(defcustom on-main-project-root 'asd
  "How to pick the directory Lisp starts in.
`asd': the nearest directory at or above `default-directory' containing
an .asd file.  `project': the current project.el root.
`default-directory': the current buffer's directory.  A function is
called with no arguments and must return a directory.  The first two
fall back to `default-directory' when nothing is found."
  :type '(choice (const :tag "Nearest .asd" asd)
                 (const :tag "project.el root" project)
                 (const :tag "Current directory" default-directory)
                 (function :tag "Custom function")))

(defcustom on-main-load-system nil
  "If non-nil, load the project's ASDF system once connected.
The system is the .asd in the start directory named after that
directory, or else the one with the shortest name."
  :type 'boolean)

;;; Project root and system

(defun on-main--asd-directory-p (dir)
  "Return non-nil if DIR contains an .asd file."
  (directory-files dir nil "\\.asd\\'" t))

(defun on-main-project-root ()
  "Directory to start Lisp in, according to `on-main-project-root'."
  (file-name-as-directory
   (expand-file-name
    (pcase on-main-project-root
      ('asd (or (locate-dominating-file default-directory
                                        #'on-main--asd-directory-p)
                default-directory))
      ('project (if-let* ((project (project-current)))
                    (project-root project)
                  default-directory))
      ('default-directory default-directory)
      ((pred functionp) (funcall on-main-project-root))
      (other (user-error "Invalid `on-main-project-root': %S" other))))))

(defun on-main-system (root)
  "Name of the main ASDF system in ROOT, or nil if it has no .asd files."
  (let ((systems (mapcar #'file-name-base
                         (directory-files root nil "\\.asd\\'")))
        (dir (file-name-nondirectory (directory-file-name root))))
    (or (car (member dir systems))
        (car (sort systems (lambda (a b) (< (length a) (length b))))))))

;;; Lisp implementation

(defun on-main--implementation (table default-name prompt)
  "Pick a Lisp from TABLE (`sly-lisp-implementations' format).
DEFAULT-NAME is used unless PROMPT is non-nil, in which case the user
chooses.  With an empty TABLE, `inferior-lisp-program' is used.
Returns a plist with :name, :program and :program-args, plus any
:env, :coding-system and :init-function from the entry."
  (if (null table)
      (let ((command (split-string-and-unquote inferior-lisp-program)))
        (list :name (intern (file-name-nondirectory (car command)))
              :program (car command)
              :program-args (cdr command)))
    (let* ((name (if prompt
                     (intern (completing-read
                              "Lisp: " (mapcar (lambda (e) (symbol-name (car e))) table)
                              nil t))
                   (or default-name (caar table))))
           (entry (or (assq name table)
                      (user-error "No Lisp named %s" name))))
      (cl-destructuring-bind (name (program &rest args) &rest keys) entry
        (append (list :name name :program program :program-args args)
                (cl-loop for key in '(:env :coding-system :init-function)
                         when (plist-member keys key)
                         append (list key (plist-get keys key))))))))

;;; What gets sent to Lisp

(defun on-main-init-form (backend loader port-file root)
  "Return the form to load `on-main-lisp-file'.
BACKEND is :slynk or :swank.  LOADER, PORT-FILE and ROOT (the project
directory, added to ASDF's search path) are Lisp filenames."
  (let ((file (expand-file-name on-main-lisp-file)))
    (unless (file-exists-p file)
      (user-error "Missing %s" file))
    ;; One form, so buffered input can't split it.
    (format "(progn (defparameter cl-user::*on-main-backend* %s) (defparameter cl-user::*on-main-loader* %S) (defparameter cl-user::*on-main-port-file* %S) (defparameter cl-user::*on-main-project-root* %S) (load %S))\n\n"
            backend loader port-file root file)))

(defun on-main--buffer-name (editor root)
  "Name for the inferior Lisp buffer of EDITOR started in ROOT."
  (format "*on-main %s %s*" editor
          (file-name-nondirectory (directory-file-name root))))

(defun on-main--after-connect (impl system eval-async)
  "Function to run once connected.
Calls IMPL's own :init-function, then loads SYSTEM with EVAL-ASYNC if
`on-main-load-system' is set."
  (let ((user-fn (plist-get impl :init-function)))
    (lambda ()
      (when user-fn (funcall user-fn))
      (when (and on-main-load-system system)
        (message "on-main: loading system %s..." system)
        (funcall eval-async `(asdf:load-system ,system)
                 (lambda (_) (message "on-main: loaded system %s" system)))))))

(provide 'on-main)
;;; on-main.el ends here
