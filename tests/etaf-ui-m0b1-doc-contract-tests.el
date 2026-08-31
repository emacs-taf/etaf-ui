;;; etaf-ui-m0b1-doc-contract-tests.el --- M0b1 UI documentation contracts -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'seq)
(require 'etaf-ui)
(declare-function etaf-ui-m0a-component-inventory
                  "../scripts/etaf-ui-m0a-inventory")
(load-file (expand-file-name "scripts/etaf-ui-m0a-inventory.el"
                            default-directory))

(defconst etaf-ui-m0b1-doc--readmes
  '("README.md" "README.zh-CN.md")
  "README files governed by the M0b1 etaf-ui documentation contract.")

(defun etaf-ui-m0b1-doc--contents (file)
  "Return FILE contents from the package root."
  (with-temp-buffer
    (insert-file-contents (expand-file-name file default-directory))
    (buffer-string)))

(defun etaf-ui-m0b1-doc--component-table-row (component chinese-p)
  "Return COMPONENT's exact README table row.

Use Chinese punctuation when CHINESE-P is non-nil."
  (format "| `%s` | %s |"
          (plist-get component :name)
          (mapconcat
           (lambda (prop) (format "`:%s`" prop))
           (plist-get component :observed-business-props)
           (if chinese-p "、" ", "))))

(ert-deftest etaf-ui-m0b1-readmes-match-runtime-component-manifest ()
  "Keep the README contract aligned with the runtime-derived inventory."
  (let* ((components (etaf-ui-m0a-component-inventory))
         (grid (seq-find (lambda (entry)
                           (eq (plist-get entry :name) 'etaf-data-grid))
                         components)))
    (should (= 8 (length components)))
    (should
     (equal '(controller columns row-key on-row-press row-ref row-selected-p
                         loading-label error-label empty-label)
            (plist-get grid :observed-business-props)))
    (dolist (file etaf-ui-m0b1-doc--readmes)
      (let ((contents (etaf-ui-m0b1-doc--contents file))
            (chinese-p (string-match-p "zh-CN" file)))
        (should-not (string-match-p ":selected-key" contents))
        (dolist (component components)
          (should
           (string-match-p
            (regexp-quote
             (etaf-ui-m0b1-doc--component-table-row component chinese-p))
            contents))
          (should (eq 'all-valid-host-attrs
                      (plist-get component :forwarded-host-attrs)))
          (should (eq 'single-host-root
                      (plist-get component :root-guarantee))))))))

(ert-deftest etaf-ui-m0b1-readmes-document-forwarding-and-row-ref-fallback ()
  "Document the single-root forwarding and optional row-ref contracts."
  (dolist (file etaf-ui-m0b1-doc--readmes)
    (let ((contents (etaf-ui-m0b1-doc--contents file)))
      (should (string-match-p "M0b1: single-host-root" contents))
      (should (string-match-p "M0b1: row-ref-optional" contents))
      (should (string-match-p "M0b1: business-props" contents)))))

(ert-deftest etaf-ui-m0b1-data-grid-row-ref-current-contract ()
  "Use a controller fallback when row-ref is nil and honor an explicit ref."
  (dolist (explicit '(nil explicit))
    (let* ((source (etaf-data-memory-source '((:id 7 :name "Ada"))
                                            :id-key :id))
           (controller (etaf-data-controller source :auto-load t))
           (buffer-name (generate-new-buffer-name " *etaf-ui-m0b1-row-ref*"))
           pressed)
      (unwind-protect
          (progn
            (etaf-mount
             buffer-name
             (etaf-view
              (etaf-data-grid
               :controller controller
               :columns '((:key :id :label "ID"))
               :row-key (lambda (row) (plist-get row :id))
               :row-ref (when explicit
                          (lambda (row)
                            (intern (format "documented-row-%s"
                                            (plist-get row :id)))))
               :on-row-press (lambda (row) (setq pressed row)))))
            (let ((runtime (etaf-runtime-for-buffer buffer-name))
                  host-ref)
              (maphash
               (lambda (ref props)
                 (when (equal 7 (plist-get props :key))
                   (setq host-ref ref)))
               (etaf-runtime-host-props runtime))
              (should host-ref)
              (when explicit
                (should (eq 'documented-row-7 host-ref)))
              (etaf-dispatch-event runtime host-ref 'press)
              (should (equal 7 (plist-get pressed :id)))))
        (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
          (etaf-unmount runtime))
        (etaf-data-stop controller)
        (when-let* ((buffer (get-buffer buffer-name)))
          (kill-buffer buffer))))))

(provide 'etaf-ui-m0b1-doc-contract-tests)
;;; etaf-ui-m0b1-doc-contract-tests.el ends here
