;;; etaf-ui-m0a-inventory-tests.el --- M0a inventory tests -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'seq)
(require 'etaf-ui)
(declare-function etaf-ui-m0a-component-inventory
                  "../scripts/etaf-ui-m0a-inventory")
(declare-function etaf-ui-m0a-private-consumers
                  "../scripts/etaf-ui-m0a-inventory")
(declare-function etaf-ui-m0a-private-consumer-drift
                  "../scripts/etaf-ui-m0a-inventory")
(declare-function etaf-ui-m0a-inventory
                  "../scripts/etaf-ui-m0a-inventory")
(load-file (expand-file-name "scripts/etaf-ui-m0a-inventory.el"
                            default-directory))

(ert-deftest etaf-ui-m0a-inventory-records-eight-public-components ()
  "Record exactly the eight current public etaf-ui Components."
  (let ((components (etaf-ui-m0a-component-inventory)))
    (should (= 8 (length components)))
    (should
     (equal '(etaf-button etaf-checkbox etaf-data-grid etaf-label
                          etaf-number-input etaf-pagination etaf-panel etaf-table)
            (sort (mapcar (lambda (entry) (plist-get entry :name)) components)
                  (lambda (left right)
                    (string< (symbol-name left) (symbol-name right))))))))

(ert-deftest etaf-ui-m0a-inventory-matches-current-business-props ()
  "Match each declared business prop list to its source definition."
  (dolist (component (etaf-ui-m0a-component-inventory))
    (should (equal (plist-get component :business-props)
                   (plist-get component :observed-business-props)))
    (should-not (plist-get component :drift))))

(ert-deftest etaf-ui-m0a-inventory-separates-host-forwarding-from-props ()
  "Record Host forwarding and single-root guarantees separately from props."
  (dolist (component (etaf-ui-m0a-component-inventory))
    (should (eq 'all-valid-host-attrs
                (plist-get component :forwarded-host-attrs)))
    (should (eq 'single-host-root
                (plist-get component :root-guarantee)))))

(ert-deftest etaf-ui-m0a-components-forward-host-attrs-to-one-mounted-root ()
  "Forward ref, class, and aria-label through every public Component root."
  (let* ((source (etaf-data-memory-source
                  '((:id 1 :name "Ada")) :id-key :id))
         (controller (etaf-data-controller source :auto-load t))
         (buffer (generate-new-buffer-name " *etaf-ui-m0a-forwarding*"))
         (components (etaf-ui-m0a-component-inventory)))
    (unwind-protect
        (progn
          (etaf-mount
           buffer
           (etaf-view
            (column
             (etaf-label :text "Label" :ref 'm0a-label
                         :class "m0a-forwarded" :aria-label "m0a-label")
             (etaf-button :label "Button" :ref 'm0a-button
                          :class "m0a-forwarded" :aria-label "m0a-button")
             (etaf-checkbox :checked nil :label "Checkbox"
                            :ref 'm0a-checkbox :class "m0a-forwarded"
                            :aria-label "m0a-checkbox")
             (etaf-panel :title "Panel" :ref 'm0a-panel
                         :class "m0a-forwarded" :aria-label "m0a-panel"
               (etaf-label :text "Nested"))
             (etaf-number-input :value 1 :label "Number"
                                :ref 'm0a-number-input
                                :class "m0a-forwarded"
                                :aria-label "m0a-number-input")
             (etaf-table :columns '((:key :name :label "Name"))
                         :rows '((:id 1 :name "Ada"))
                         :row-key (lambda (row) (plist-get row :id))
                         :ref 'm0a-table :class "m0a-forwarded"
                         :aria-label "m0a-table")
             (etaf-data-grid
              :controller controller
              :columns '((:key :name :label "Name"))
              :row-key (lambda (row) (plist-get row :id))
              :ref 'm0a-data-grid :class "m0a-forwarded"
              :aria-label "m0a-data-grid")
             (etaf-pagination :controller controller
                              :ref 'm0a-pagination
                              :class "m0a-forwarded"
                              :aria-label "m0a-pagination"))))
          (let ((runtime (etaf-runtime-for-buffer buffer)))
            (should (= 8 (length components)))
            (dolist (component components)
              (let* ((name (plist-get component :name))
                     (suffix (string-remove-prefix "etaf-"
                                                   (symbol-name name)))
                     (ref (intern (concat "m0a-" suffix)))
                     (props (etaf-runtime-host-props-for runtime ref)))
                (should props)
                (should (eq ref (plist-get props :ref)))
                (should (member "m0a-forwarded"
                                (etaf--class-tokens
                                 (plist-get props :class))))
                (should (equal (symbol-name ref)
                               (plist-get props :aria-label)))))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer)))
        (etaf-unmount runtime))
      (when (get-buffer buffer) (kill-buffer buffer))
      (etaf-data-stop controller))))

(ert-deftest etaf-ui-m0b-inventory-records-private-production-closure ()
  "Record zero current production private consumers and retain M0a history."
  (let* ((entries (seq-filter
                   (lambda (entry) (eq 'production (plist-get entry :scope)))
                   (etaf-ui-m0a-private-consumers)))
         (symbols (delete-dups
                   (mapcar (lambda (entry) (plist-get entry :symbol)) entries))))
    (should-not entries)
    (should-not symbols)
    (should (cl-every (lambda (entry)
                        (and (stringp (plist-get entry :file))
                             (integerp (plist-get entry :line))))
                      entries))
    (let ((drift (etaf-ui-m0a-private-consumer-drift)))
      (should-not (plist-get drift :missing))
      (should-not (plist-get drift :unexpected)))
    (should (= 7 (length etaf-ui-m0a-private-production-callsites)))))

(ert-deftest etaf-ui-m0a-inventory-rejects-an-undeclared-production-callsite ()
  "Report a newly added private production call even when its symbol is known."
  (let ((temporary-root (make-temp-file "etaf-ui-m0a-private-" t)))
    (unwind-protect
        (progn
          (copy-file (expand-file-name "etaf-ui-data.el" default-directory)
                     (expand-file-name "etaf-ui-data.el" temporary-root))
          (with-temp-buffer
            (insert "\n(etaf--expr-create 'undeclared-callsite)\n")
            (append-to-file (point-min) (point-max)
                            (expand-file-name "etaf-ui-data.el"
                                              temporary-root)))
          (should (plist-get
                   (etaf-ui-m0a-private-consumer-drift temporary-root)
                   :unexpected)))
      (delete-directory temporary-root t))))

(ert-deftest etaf-ui-m0a-inventory-records-current-test-consumers ()
  "Record existing private test consumers without counting inventory data."
  (let* ((entries (seq-filter
                   (lambda (entry) (eq 'test (plist-get entry :scope)))
                   (etaf-ui-m0a-private-consumers)))
         (symbols (delete-dups
                   (mapcar (lambda (entry) (plist-get entry :symbol)) entries))))
    (should (= 10 (length entries)))
    (should (= 2 (cl-count 'etaf--class-tokens entries
                           :key (lambda (entry)
                                  (plist-get entry :symbol)))))
    (should (= 4 (cl-count 'etaf--runtime-render-dirty-component entries
                           :key (lambda (entry)
                                  (plist-get entry :symbol)))))
    (should (= 2 (cl-count 'etaf--ebox-box-node entries
                           :key (lambda (entry)
                                  (plist-get entry :symbol)))))
    (should (= 2 (cl-count 'etaf--ebox-text-node entries
                           :key (lambda (entry)
                                  (plist-get entry :symbol)))))
    (should (equal '(etaf--class-tokens etaf--ebox-box-node
                     etaf--ebox-text-node
                     etaf--runtime-render-dirty-component)
                   (sort symbols (lambda (left right)
                                   (string< (symbol-name left)
                                            (symbol-name right))))))))

(ert-deftest etaf-ui-m0b-inventory-labels-public-seam-migration ()
  "Label the zero-private-consumer state as the completed M0b migration."
  (let ((inventory (etaf-ui-m0a-inventory)))
    (should (eq 'M0b (plist-get inventory :milestone)))
    (should (eq 'migrated-public-extension-seam
                (plist-get inventory :evidence-mode)))
    (should
     (equal '(:handler-publication postcommit-promoted
              :fallback-ref instance-scoped-uninterned
              :fixed-width-row single-text-host)
            (plist-get inventory :datagrid-contract)))
    (should (= 7 (length (plist-get inventory
                                    :m0a-private-production-baseline))))
    (should-not
     (seq-filter
      (lambda (entry) (eq 'production (plist-get entry :scope)))
      (plist-get inventory :private-consumers)))))

(provide 'etaf-ui-m0a-inventory-tests)
;;; etaf-ui-m0a-inventory-tests.el ends here
