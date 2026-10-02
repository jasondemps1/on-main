;;; on-main-slime.el --- SLIME support for on-main  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jason Dempsey
;; SPDX-License-Identifier: MIT

;; This file is part of on-main.

;;; Commentary:

;; M-x on-main-slime starts a Lisp with Swank in background threads and the
;; main thread reserved for ON-MAIN:RUN / ON-MAIN:CALL, then connects SLIME.
;; With a prefix argument, choose from `slime-lisp-implementations'.

;;; Code:

(require 'on-main)

(defvar slime-lisp-implementations)
(defvar slime-default-lisp)
(defvar slime-backend)
(defvar slime-path)
(declare-function slime-start "slime")
(declare-function slime-to-lisp-filename "slime")
(declare-function slime-eval-async "slime")

;;;###autoload
(defun on-main-slime (&optional prompt)
  "Start a Lisp whose main thread is reserved for ON-MAIN, and connect SLIME.
Lisp starts in the directory chosen by `on-main-project-root'.  With
PROMPT (a prefix argument), choose from `slime-lisp-implementations'."
  (interactive "P")
  (require 'slime)
  (let* ((impl (on-main--implementation slime-lisp-implementations
                                        slime-default-lisp prompt))
         (root (on-main-project-root))
         (system (on-main-system root))
         (loader (slime-to-lisp-filename
                  (expand-file-name slime-backend slime-path))))
    (apply #'slime-start
           :program (plist-get impl :program)
           :program-args (plist-get impl :program-args)
           :directory root
           :name (plist-get impl :name)
           :buffer (on-main--buffer-name "slime" root)
           :init (lambda (port-file _coding-system)
                   (on-main-init-form :swank loader
                                      (slime-to-lisp-filename port-file)
                                      (slime-to-lisp-filename root)))
           :init-function (on-main--after-connect impl system #'slime-eval-async)
           (append
            (when (plist-member impl :env)
              (list :env (plist-get impl :env)))
            (when (plist-member impl :coding-system)
              (list :coding-system (plist-get impl :coding-system)))))))

(provide 'on-main-slime)
;;; on-main-slime.el ends here
