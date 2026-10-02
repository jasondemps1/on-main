;;; on-main-sly.el --- Sly support for on-main  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jason Dempsey
;; SPDX-License-Identifier: MIT

;; This file is part of on-main.

;;; Commentary:

;; M-x on-main-sly starts a Lisp with Slynk in background threads and the
;; main thread reserved for ON-MAIN:RUN / ON-MAIN:CALL, then connects Sly.
;; With a prefix argument, choose from `sly-lisp-implementations'.

;;; Code:

(require 'on-main)

(defvar sly-lisp-implementations)
(defvar sly-default-lisp)
(defvar sly-slynk-loader-backend)
(declare-function sly-start "sly")
(declare-function sly-slynk-path "sly")
(declare-function sly-to-lisp-filename "sly")
(declare-function sly-eval-async "sly")

;;;###autoload
(defun on-main-sly (&optional prompt)
  "Start a Lisp whose main thread is reserved for ON-MAIN, and connect Sly.
Lisp starts in the directory chosen by `on-main-project-root'.  With
PROMPT (a prefix argument), choose from `sly-lisp-implementations'."
  (interactive "P")
  (require 'sly)
  (let* ((impl (on-main--implementation sly-lisp-implementations
                                        sly-default-lisp prompt))
         (root (on-main-project-root))
         (system (on-main-system root))
         (loader (sly-to-lisp-filename
                  (expand-file-name sly-slynk-loader-backend (sly-slynk-path)))))
    (apply #'sly-start
           :program (plist-get impl :program)
           :program-args (plist-get impl :program-args)
           :directory root
           :name (plist-get impl :name)
           :buffer (on-main--buffer-name "sly" root)
           :init (lambda (port-file _coding-system)
                   (on-main-init-form :slynk loader
                                      (sly-to-lisp-filename port-file)
                                      (sly-to-lisp-filename root)))
           :init-function (on-main--after-connect impl system #'sly-eval-async)
           (append
            (when (plist-member impl :env)
              (list :env (plist-get impl :env)))
            (when (plist-member impl :coding-system)
              (list :coding-system (plist-get impl :coding-system)))))))

(provide 'on-main-sly)
;;; on-main-sly.el ends here
