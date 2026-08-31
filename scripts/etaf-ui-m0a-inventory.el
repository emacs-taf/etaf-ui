;;; etaf-ui-m0a-inventory.el --- M0a Component inventory -*- lexical-binding: t; -*-

;;; Commentary:
;; Machine-readable current-behavior inventory.  This file deliberately
;; records private consumers as drift; M0a does not turn the M0b target into a
;; failing current gate.

;;; Code:
(require 'cl-lib)
(require 'seq)

(defconst etaf-ui-m0a--package-root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Absolute etaf-ui package root used by the inventory.")

(defconst etaf-ui-m0a-public-component-contracts
  '((:name etaf-label
     :business-props (text variant)
     :forwarded-host-attrs all-valid-host-attrs
     :root-guarantee single-host-root
     :definition "etaf-ui-basic.el")
    (:name etaf-button
     :business-props (label on-press disabled ref class color bgcolor border
                            padding font-weight tab-index aria-label use variant)
     :forwarded-host-attrs all-valid-host-attrs
     :root-guarantee single-host-root
     :definition "etaf-ui-basic.el")
    (:name etaf-checkbox
     :business-props (checked label on-change disabled)
     :forwarded-host-attrs all-valid-host-attrs
     :root-guarantee single-host-root
     :definition "etaf-ui-basic.el")
    (:name etaf-panel
     :business-props (title variant)
     :forwarded-host-attrs all-valid-host-attrs
     :root-guarantee single-host-root
     :definition "etaf-ui-basic.el")
    (:name etaf-number-input
     :business-props (value label on-change disabled min max)
     :forwarded-host-attrs all-valid-host-attrs
     :root-guarantee single-host-root
     :definition "etaf-ui-basic.el")
    (:name etaf-table
     :business-props (columns rows row-key row-ref on-row-press row-selected-p)
     :forwarded-host-attrs all-valid-host-attrs
     :root-guarantee single-host-root
     :definition "etaf-ui-table.el")
    (:name etaf-data-grid
     :business-props (controller columns row-key on-row-press row-ref
                                 row-selected-p loading-label error-label
                                 empty-label)
     :forwarded-host-attrs all-valid-host-attrs
     :root-guarantee single-host-root
     :definition "etaf-ui-data.el")
    (:name etaf-pagination
     :business-props (controller previous-ref next-ref class color bgcolor
                                 border padding aria-label)
     :forwarded-host-attrs all-valid-host-attrs
     :root-guarantee single-host-root
     :definition "etaf-ui-data.el"))
  "Observed contracts of the eight public etaf-ui Components.

`all-valid-host-attrs' names the core single-root Component forwarding rule;
it is not a claim that every attribute is a declared business prop.")

(defconst etaf-ui-m0a-private-production-callsites
  '((:symbol etaf--expr-create :scope production
     :file "etaf-ui-data.el" :line 93)
    (:symbol etaf--expr-create :scope production
     :file "etaf-ui-data.el" :line 106)
    (:symbol etaf--expr-create :scope production
     :file "etaf-ui-data.el" :line 114)
    (:symbol etaf--expr-create :scope production
     :file "etaf-ui-data.el" :line 234)
    (:symbol etaf--view-call :scope production
     :file "etaf-ui-data.el" :line 278)
    (:symbol etaf--view-call :scope production
     :file "etaf-ui-data.el" :line 284)
    (:symbol etaf--slot-projection-create :scope production
     :file "etaf-ui-data.el" :line 286))
  "Exact M0a baseline of production calls into private ETAF functions.")

(defconst etaf-ui-m0b-private-production-callsites nil
  "M0b target and current production calls into private ETAF functions.")

(defun etaf-ui-m0a--read-top-level-forms (file)
  "Return top-level forms and source lines read from FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let (forms form start)
      (condition-case nil
          (while t
            (setq start (point)
                  form (read (current-buffer)))
            (push (list :form form :line (line-number-at-pos start)) forms))
        (end-of-file nil))
      (nreverse forms))))

(defun etaf-ui-m0a--component-definitions ()
  "Return public Component definitions observed in package product files."
  (let (result)
    (dolist (file (directory-files etaf-ui-m0a--package-root t
                                   "\\`etaf-ui-.*\\.el\\'"))
      (dolist (entry (etaf-ui-m0a--read-top-level-forms file))
        (let ((form (plist-get entry :form)))
          (when (and (eq (car-safe form) 'etaf-define-component)
                     (symbolp (cadr form))
                     (not (string-prefix-p "etaf-ui--"
                                           (symbol-name (cadr form)))))
            (let ((arguments (nth 2 form)))
              (push (list :name (cadr form)
                          :business-props
                          (seq-filter #'symbolp
                                      (cdr (memq '&key arguments)))
                          :definition
                          (file-relative-name file etaf-ui-m0a--package-root)
                          :line (plist-get entry :line))
                    result))))))
    (sort result (lambda (left right)
                   (string< (symbol-name (plist-get left :name))
                            (symbol-name (plist-get right :name)))))))

(defun etaf-ui-m0a-component-inventory ()
  "Return the current eight-Component contract with observed source lines."
  (let ((definitions (etaf-ui-m0a--component-definitions)))
    (mapcar
     (lambda (contract)
       (let* ((name (plist-get contract :name))
              (observed (seq-find
                         (lambda (entry) (eq name (plist-get entry :name)))
                         definitions)))
         (append (copy-sequence contract)
                 (list :observed-business-props
                       (plist-get observed :business-props)
                       :observed-definition (plist-get observed :definition)
                       :line (plist-get observed :line)
                       :drift
                       (unless (and observed
                                    (equal (plist-get contract :business-props)
                                           (plist-get observed :business-props))
                                    (equal (plist-get contract :definition)
                                           (plist-get observed :definition)))
                         'contract-mismatch)))))
     etaf-ui-m0a-public-component-contracts)))

(defun etaf-ui-m0a--private-occurrences-in-file (file scope root call-only)
  "Return active private occurrences in FILE under SCOPE and ROOT.

When CALL-ONLY is non-nil, record only symbols in function-call position.
The linear scanner excludes strings and both line and block comments."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let ((block-depth 0)
          in-string
          escaped
          result)
      (while (< (point) (point-max))
        (cond
         ((> block-depth 0)
          (cond ((looking-at "#|")
                 (setq block-depth (1+ block-depth))
                 (forward-char 2))
                ((looking-at "|#")
                 (setq block-depth (1- block-depth))
                 (forward-char 2))
                (t (forward-char 1))))
         (in-string
          (let ((character (char-after)))
            (forward-char 1)
            (cond (escaped (setq escaped nil))
                  ((eq character ?\\) (setq escaped t))
                  ((eq character ?\") (setq in-string nil)))))
         ((looking-at "#|")
          (setq block-depth 1)
          (forward-char 2))
         ((eq (char-after) ?\;)
          (forward-line 1))
         ((eq (char-after) ?\")
          (setq in-string t)
          (forward-char 1))
         ((eq (char-after) ??)
          ;; Skip an Emacs Lisp character literal, including ?\\X.
          (forward-char (min (if (eq (char-after (1+ (point))) ?\\) 3 2)
                             (- (point-max) (point)))))
         ((and call-only (eq (char-after) ?\())
          (forward-char 1)
          (skip-chars-forward " \t\r\n")
          (when (looking-at "\\(etaf--[[:alnum:]-]+\\)\\_>")
            (push (list :symbol (intern (match-string-no-properties 1))
                        :scope scope
                        :file (file-relative-name file root)
                        :line (line-number-at-pos (point)))
                  result)))
         ((and (not call-only)
               (looking-at "\\_<\\(etaf--[[:alnum:]-]+\\)\\_>"))
          (push (list :symbol (intern (match-string-no-properties 1))
                      :scope scope
                      :file (file-relative-name file root)
                      :line (line-number-at-pos (point)))
                result)
          (goto-char (match-end 1)))
         (t (forward-char 1))))
      (nreverse result))))

(defun etaf-ui-m0a-private-consumers (&optional root)
  "Return active core-private consumers below ROOT.

ROOT defaults to the etaf-ui package root."
  (let* ((root (file-name-as-directory
                (or root etaf-ui-m0a--package-root)))
         (tests-directory (expand-file-name "tests" root))
         (files (append
                 (directory-files root t
                                  "\\`etaf-ui-.*\\.el\\'")
                 (when (file-directory-p tests-directory)
                   (directory-files tests-directory t "\\.el\\'"))))
        result)
    (dolist (file files)
      ;; The inventory's own expectation literals are evidence vocabulary,
      ;; not calls into the private API under inventory.
      (unless (string-suffix-p "etaf-ui-m0a-inventory-tests.el" file)
        (setq result
              (nconc result
                     (if (string-match-p "/tests/" file)
                         (etaf-ui-m0a--private-occurrences-in-file
                          file 'test root nil)
                       (etaf-ui-m0a--private-occurrences-in-file
                        file 'production root t))))))
    result))

(defun etaf-ui-m0a-private-consumer-drift (&optional root)
  "Return current M0b production private-call drift below optional ROOT."
  (let ((observed
         (seq-filter
          (lambda (entry) (eq 'production (plist-get entry :scope)))
          (etaf-ui-m0a-private-consumers root))))
    (list :expected etaf-ui-m0b-private-production-callsites
          :observed observed
          :missing (seq-remove (lambda (entry) (member entry observed))
                               etaf-ui-m0b-private-production-callsites)
          :unexpected
          (seq-remove (lambda (entry)
                        (member entry etaf-ui-m0b-private-production-callsites))
                      observed))))

(defun etaf-ui-m0a-inventory ()
  "Return the complete machine-readable etaf-ui M0a inventory."
  (list :schema-version 1
        :milestone 'M0b
        :evidence-mode 'migrated-public-extension-seam
        :datagrid-contract
        '(:handler-publication postcommit-promoted
          :fallback-ref instance-scoped-uninterned
          :fixed-width-row single-text-host)
        :components (etaf-ui-m0a-component-inventory)
        :m0a-private-production-baseline
        etaf-ui-m0a-private-production-callsites
        :private-consumers (etaf-ui-m0a-private-consumers)
        :private-production-drift (etaf-ui-m0a-private-consumer-drift)))

(defun etaf-ui-m0a-inventory-batch ()
  "Print `etaf-ui-m0a-inventory' for a batch evidence run."
  (prin1 (etaf-ui-m0a-inventory))
  (terpri))

(provide 'etaf-ui-m0a-inventory)
;;; etaf-ui-m0a-inventory.el ends here
