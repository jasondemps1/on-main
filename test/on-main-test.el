;;; on-main-test.el --- Unit tests for on-main  -*- lexical-binding: t; -*-

;; Run: emacs -Q --batch -L . -l test/on-main-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'on-main)

(defmacro on-main-test--with-tree (files &rest body)
  "Create FILES (relative paths) under a temp dir bound to `root', run BODY."
  (declare (indent 1))
  `(let ((root (file-name-as-directory (make-temp-file "on-main-ut-" t))))
     (unwind-protect
         (progn
           (dolist (f ,files)
             (let ((path (expand-file-name f root)))
               (make-directory (file-name-directory path) t)
               (unless (string-suffix-p "/" f) (write-region "" nil path))))
           ,@body)
       (delete-directory root t))))

(ert-deftest on-main-root-finds-nearest-asd ()
  (on-main-test--with-tree '("app.asd" "src/deep/x.lisp")
    (let ((default-directory (expand-file-name "src/deep/" root))
          (on-main-project-root 'asd))
      (should (equal (file-truename (on-main-project-root)) (file-truename root))))))

(ert-deftest on-main-root-falls-back-to-default-directory ()
  (on-main-test--with-tree '("src/")
    (let ((default-directory (expand-file-name "src/" root))
          (on-main-project-root 'asd))
      ;; Only meaningful if no .asd exists above the temp dir.
      (unless (locate-dominating-file root #'on-main--asd-directory-p)
        (should (equal (on-main-project-root) default-directory))))))

(ert-deftest on-main-root-custom-function ()
  (let ((on-main-project-root (lambda () "/tmp/somewhere")))
    (should (equal (on-main-project-root) "/tmp/somewhere/"))))

(ert-deftest on-main-system-prefers-directory-name ()
  (on-main-test--with-tree '("a.asd" "zz-tests.asd")
    (let* ((proj (expand-file-name "myproj/" root)))
      (make-directory proj)
      (dolist (f '("myproj-tests.asd" "myproj.asd" "m.asd"))
        (write-region "" nil (expand-file-name f proj)))
      (should (equal (on-main-system proj) "myproj")))))

(ert-deftest on-main-system-shortest-name-otherwise ()
  (on-main-test--with-tree '("thing-tests.asd" "thing.asd")
    (should (equal (on-main-system root) "thing"))))

(ert-deftest on-main-system-none ()
  (on-main-test--with-tree '("README")
    (should (null (on-main-system root)))))

(ert-deftest on-main-implementation-from-table ()
  (let ((table '((ccl ("ccl64"))
                 (sbcl ("sbcl" "--dynamic-space-size" "4096")
                       :env ("FOO=1") :coding-system utf-8-unix))))
    (should (equal (on-main--implementation table 'sbcl nil)
                   '(:name sbcl :program "sbcl"
                     :program-args ("--dynamic-space-size" "4096")
                     :env ("FOO=1") :coding-system utf-8-unix)))
    (should (equal (plist-get (on-main--implementation table nil nil) :name) 'ccl))))

(ert-deftest on-main-implementation-from-inferior-lisp-program ()
  (let ((inferior-lisp-program "/opt/homebrew/bin/sbcl --noinform"))
    (should (equal (on-main--implementation nil nil nil)
                   '(:name sbcl :program "/opt/homebrew/bin/sbcl"
                     :program-args ("--noinform"))))))

(ert-deftest on-main-init-form-shape ()
  (let ((form (on-main-init-form :slynk "/s/slynk-loader.lisp" "/tmp/port" "/p/")))
    (should (string-match-p "\\`(progn " form))
    (should (string-match-p "(defparameter cl-user::\\*on-main-backend\\* :slynk)" form))
    (should (string-match-p "\"/s/slynk-loader.lisp\"" form))
    (should (string-match-p "\\*on-main-project-root\\* \"/p/\"" form))
    (should (string-match-p (regexp-quote (prin1-to-string (expand-file-name on-main-lisp-file)))
                            form))))

(ert-deftest on-main-init-form-missing-lisp-file ()
  (let ((on-main-lisp-file "/nonexistent/on-main.lisp"))
    (should-error (on-main-init-form :swank "l" "p" "r") :type 'user-error)))

;;; on-main-test.el ends here
