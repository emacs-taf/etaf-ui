;;; etaf-ui-m0b-extension-tests.el --- M0b public extension seam -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'etaf-ui)

(defconst etaf-ui-m0b--data-source-file
  (expand-file-name "../etaf-ui-data.el"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "DataGrid production source inspected by the M0b seam tests.")

(defun etaf-ui-m0b--walk (form predicate)
  "Return non-nil when PREDICATE matches FORM or one of its children."
  (or (funcall predicate form)
      (and (consp form)
           (or (etaf-ui-m0b--walk (car form) predicate)
               (etaf-ui-m0b--walk (cdr form) predicate)))))

(defun etaf-ui-m0b--source-forms (file)
  "Read and return every Lisp form in FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (let (forms form)
      (condition-case nil
          (while t
            (setq form (read (current-buffer)))
            (push form forms))
        (end-of-file (nreverse forms))))))

(ert-deftest etaf-ui-m0b-data-grid-production-uses-public-extension-seam ()
  "DataGrid production code contains no ETAF private API call."
  (let ((private
          (cl-loop for form in (etaf-ui-m0b--source-forms
                                etaf-ui-m0b--data-source-file)
                   when (etaf-ui-m0b--walk
                         form
                         (lambda (node)
                           (and (symbolp node)
                                (string-prefix-p "etaf--" (symbol-name node)))))
                   collect form)))
    (should-not private)))

(ert-deftest etaf-ui-m0b-data-grid-public-range-retains-handler-and-root ()
  "Insert/reorder/update retain handlers and avoid a root replacement."
  (let* ((rows (cl-loop for id from 1 to 12
                        collect (list :id id :name (format "Row %d" id))))
         (source (etaf-data-memory-source rows :id-key :id))
         (controller (etaf-data-controller source :page-size 120 :auto-load t))
         (buffer-name " *etaf-ui-m0b-grid-retention*")
         (root-replacements 0)
         (materialized 0)
         update-materialized
         pressed)
    (unwind-protect
        (progn
          (etaf-mount
           buffer-name
           (etaf-view
            (etaf-data-grid
             :controller controller
             :columns '((:key :id :label "ID")
                        (:key :name :label "Name"))
             :row-key (lambda (row) (plist-get row :id))
             :row-ref (lambda (row)
                        (intern (format "m0b-row-%d" (plist-get row :id))))
             :on-row-press (lambda (row) (setq pressed row)))))
          (let* ((runtime (etaf-runtime-for-buffer buffer-name))
                 (handler
                  (cdr (assq 'press
                             (etaf-runtime-handler-for runtime 'm0b-row-6))))
                 (old-root (symbol-function 'ebox-candidate-replace-root))
                 (old-box (symbol-function 'etaf--ebox-box-node))
                 (old-text (symbol-function 'etaf--ebox-text-node)))
            (cl-letf (((symbol-function 'ebox-candidate-replace-root)
                       (lambda (&rest arguments)
                         (cl-incf root-replacements)
                         (apply old-root arguments)))
                      ((symbol-function 'etaf--ebox-box-node)
                       (lambda (&rest arguments)
                         (cl-incf materialized)
                         (apply old-box arguments)))
                      ((symbol-function 'etaf--ebox-text-node)
                       (lambda (&rest arguments)
                         (cl-incf materialized)
                         (apply old-text arguments))))
              (setf (etaf-value (etaf-data-items controller))
                    (cl-loop for row in rows
                             if (= 6 (plist-get row :id))
                             collect '(:id 6 :name "Row six updated")
                             else collect row))
              (setq update-materialized materialized)
              (etaf-data-mutate controller 'insert
                                '(:id 13 :name "Row 13"))
              (etaf-data-mutate controller 'update
                                '(:id 6 :name "Row six updated")))
            (should (zerop root-replacements))
            ;; One local update stays well below materializing all 12 rows and
            ;; their two cells (at least 60 Ebox nodes).
            (should (< update-materialized 30))
            (should (eq handler
                        (cdr (assq
                              'press
                              (etaf-runtime-handler-for runtime 'm0b-row-6)))))
            (etaf-dispatch-event runtime 'm0b-row-6 'press)
            (should (equal "Row six updated" (plist-get pressed :name)))
            (should (string-match-p
                     "Row six updated"
                     (with-current-buffer buffer-name
                       (substring-no-properties (buffer-string)))))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-m0b-data-grid-enumerates-120-items-once-per-turn ()
  "A 120-row update enumerates the public Range once and stays item-local."
  (let* ((row-key-calls 0)
         (rows (cl-loop for id from 1 to 120
                        collect (list :id id :name (format "Row %d" id))))
         (source (etaf-data-memory-source rows :id-key :id))
         (controller (etaf-data-controller source :page-size 120 :auto-load t))
         (buffer-name " *etaf-ui-m0b-grid-scale*"))
    (unwind-protect
        (progn
          (etaf-mount
           buffer-name
           (etaf-view
            (etaf-data-grid
             :controller controller
             :columns '((:key :id :label "ID"))
             :row-key (lambda (row)
                        (cl-incf row-key-calls)
                        (plist-get row :id)))))
          (setq row-key-calls 0)
          (etaf-data-mutate controller 'update
                            '(:id 60 :name "Changed"))
          (should (= 120 row-key-calls)))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-m0b-data-grid-footer-reorder-and-key-rollback ()
  "Public slot projection and keyed rollback preserve the committed grid."
  (let* ((rows '((:id 1 :name "Ada") (:id 2 :name "Grace")))
         (source (etaf-data-memory-source rows :id-key :id))
         (controller (etaf-data-controller source :page-size 10 :auto-load t))
         (buffer-name " *etaf-ui-m0b-grid-footer*")
         pressed)
    (unwind-protect
        (progn
          (etaf-mount
           buffer-name
           (etaf-view
            (etaf-data-grid
             :controller controller
             :columns '((:key :name :label "Name"))
             :row-key (lambda (row) (plist-get row :id))
             :row-ref (lambda (row)
                        (intern (format "m0b-footer-row-%d"
                                        (plist-get row :id))))
             :on-row-press (lambda (row) (setq pressed row))
             (slot :name 'footer (etaf-label :text "Grid footer")))))
          (let* ((runtime (etaf-runtime-for-buffer buffer-name))
                 (handler
                  (cdr (assq 'press
                             (etaf-runtime-handler-for
                              runtime 'm0b-footer-row-1)))))
            (should (string-match-p
                     "Grid footer"
                     (with-current-buffer buffer-name
                       (substring-no-properties (buffer-string)))))
            (setf (etaf-value (etaf-data-items controller))
                  (reverse rows))
            (should (eq handler
                        (cdr (assq
                              'press
                              (etaf-runtime-handler-for
                               runtime 'm0b-footer-row-1)))))
            (etaf-dispatch-event runtime 'm0b-footer-row-1 'press)
            (should (= 1 (plist-get pressed :id)))
            (let ((generation (etaf-runtime-current-generation runtime))
                  (text (with-current-buffer buffer-name (buffer-string))))
              (should-error
               (setf (etaf-value (etaf-data-items controller))
                     '((:id 1 :name "A") (:id 1 :name "duplicate")))
               :type 'etaf-component-call-error)
              (should (eq generation
                          (etaf-runtime-current-generation runtime)))
              (should (equal-including-properties
                       text (with-current-buffer buffer-name
                              (buffer-string)))))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-m0b-data-grid-late-row-failure-keeps-committed-handler ()
  "Do not leak an early candidate row when a later row fails rendering."
  (let* ((old-rows '((:id 1 :name "Committed") (:id 2 :name "Stable")))
         (new-rows '((:id 1 :name "UNCOMMITTED")
                     (:id 2 :name "Late failure")))
         (source (etaf-data-memory-source old-rows :id-key :id))
         (controller (etaf-data-controller source :page-size 10 :auto-load t))
         (buffer-name " *etaf-ui-m0b-grid-late-failure*")
         fail-late pressed)
    (unwind-protect
        (progn
          (etaf-mount
           buffer-name
           (etaf-view
            (etaf-data-grid
             :controller controller
             :columns '((:key :name :label "Name"))
             :row-key (lambda (row) (plist-get row :id))
             :row-ref
             (lambda (row)
               (unless (and fail-late (= 2 (plist-get row :id)))
                 (intern (format "late-row-%s" (plist-get row :id)))))
             :on-row-press (lambda (row) (setq pressed row)))))
          (let* ((runtime (etaf-runtime-for-buffer buffer-name))
                 (generation (etaf-runtime-current-generation runtime))
                 (text (with-current-buffer buffer-name (buffer-string)))
                 (handler
                  (cdr (assq 'press
                             (etaf-runtime-handler-for runtime 'late-row-1)))))
            (setq fail-late t)
            (should-error
             (setf (etaf-value (etaf-data-items controller)) new-rows))
            (should (eq generation
                        (etaf-runtime-current-generation runtime)))
            (should (equal-including-properties
                     text (with-current-buffer buffer-name (buffer-string))))
            (should (eq handler
                        (cdr (assq
                              'press
                              (etaf-runtime-handler-for runtime 'late-row-1)))))
            (etaf-dispatch-event runtime 'late-row-1 'press)
            (should (equal "Committed" (plist-get pressed :name)))
            (setq fail-late nil)
            (setf (etaf-value (etaf-data-items controller)) old-rows)
            (setf (etaf-value (etaf-data-items controller)) new-rows)
            (should (eq handler
                        (cdr (assq
                              'press
                              (etaf-runtime-handler-for runtime 'late-row-1)))))
            (etaf-dispatch-event runtime 'late-row-1 'press)
            (should (equal "UNCOMMITTED" (plist-get pressed :name)))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-m0b-data-grid-prunes-committed-handler-cache ()
  "Bound the stable handler cache to currently retained interactive keys."
  (let* ((rows-a '((:id 1 :name "A") (:id 2 :name "B")
                   (:id 3 :name "C")))
         (rows-b '((:id 4 :name "D") (:id 5 :name "E")
                   (:id 6 :name "F")))
         (source (etaf-data-memory-source rows-a :id-key :id))
         (controller (etaf-data-controller source :page-size 10 :auto-load t))
         (buffer-name " *etaf-ui-m0b-grid-handler-prune*")
         state)
    (unwind-protect
        (progn
          (let ((promote
                 (symbol-function 'etaf-ui--data-grid-promote-row-actions)))
            (cl-letf
                (((symbol-function 'etaf-ui--data-grid-promote-row-actions)
                  (lambda (candidate-state)
                    (setq state candidate-state)
                    (funcall promote candidate-state))))
              (etaf-mount
               buffer-name
               (etaf-view
                (etaf-data-grid
                 :controller controller
                 :columns '((:key :name :label "Name"))
                 :row-key (lambda (row) (plist-get row :id))
                 :row-ref (lambda (row)
                            (intern (format "prune-row-%s"
                                            (plist-get row :id))))
                 :on-row-press #'ignore)))))
          (should state)
          (let* ((runtime (etaf-runtime-for-buffer buffer-name))
                 (cache (plist-get state :row-actions)))
            (should (= 3 (hash-table-count cache)))
            (dolist (key '(1 2 3))
              (etaf-data-mutate controller 'delete key))
            (dolist (row rows-b)
              (etaf-data-mutate controller 'insert row))
            (should (= 3 (hash-table-count cache)))
            (dolist (key '(1 2 3)) (should-not (gethash key cache)))
            (dolist (key '(4 5 6)) (should (gethash key cache)))
            (dolist (key '(4 5 6))
              (etaf-data-mutate controller 'delete key))
            (should (zerop (hash-table-count cache)))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-m0b-data-grid-default-refs-are-instance-scoped ()
  "Keep fallback refs distinct across grids and typed row identities."
  (let* ((rows '((:id foo :name "Symbol") (:id "foo" :name "String")))
         (source (etaf-data-memory-source rows :id-key :id))
         (controller (etaf-data-controller source :page-size 10 :auto-load t))
         (buffer-name " *etaf-ui-m0b-grid-default-ref-scope*"))
    (unwind-protect
        (progn
          (etaf-mount
           buffer-name
           (etaf-view
            (column
             (etaf-data-grid
              :controller controller
              :columns '((:key :name :label "Name"))
              :row-key (lambda (row) (plist-get row :id))
              :on-row-press #'ignore)
             (etaf-data-grid
              :controller controller
              :columns '((:key :name :label "Name"))
              :row-key (lambda (row) (plist-get row :id))
              :on-row-press #'ignore))))
          (let (refs)
            (maphash
             (lambda (ref props)
               (when (member (plist-get props :key) '(foo "foo"))
                 (push ref refs)))
             (etaf-runtime-host-props
              (etaf-runtime-for-buffer buffer-name)))
            (should (= 4 (length refs)))
            (should (= 4 (length (delete-dups (copy-sequence refs)))))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-m0b-data-grid-error-status-beats-retained-items ()
  "Show the error state when a failed reload retains previously loaded rows."
  (let* ((rows '((:id 1 :name "Existing")))
         (source (etaf-data-memory-source rows :id-key :id))
         (controller (etaf-data-controller source :page-size 10 :auto-load t))
         (buffer-name " *etaf-ui-m0b-grid-retained-error*"))
    (unwind-protect
        (progn
          (etaf-mount
           buffer-name
           (etaf-view
            (etaf-data-grid
             :controller controller
             :columns '((:key :name :label "Name"))
             :row-key (lambda (row) (plist-get row :id))
             :error-label "Retained load failed"
             :empty-label "EMPTY-LABEL")))
          (setf (etaf-value (etaf-data-status controller)) 'error)
          (let ((text (with-current-buffer buffer-name
                        (substring-no-properties (buffer-string)))))
            (should (string-match-p "Retained load failed" text))
            (should-not (string-match-p "EMPTY-LABEL" text))
            (should-not (string-match-p "Existing" text))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(provide 'etaf-ui-m0b-extension-tests)
;;; etaf-ui-m0b-extension-tests.el ends here
