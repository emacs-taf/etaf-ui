;;; etaf-ui-tests.el --- Public API acceptance -*- lexical-binding: t; -*-

;;; Commentary:
;; Test supported package inputs, outputs, errors and lifecycle.
;; Internal implementation details are outside this contract.

;;; Code:
(require 'cl-lib)
(require 'ert)
(require 'etaf-ui)

(defun etaf-ui-test--text (buffer-name)
  "Return plain text currently published in BUFFER-NAME."
  (with-current-buffer buffer-name
    (string-trim-right (substring-no-properties (buffer-string)))))

(defvar etaf-ui-test-use-count 0)

(etaf-define-behavior etaf-ui-test-press-behavior (&rest attributes)
  "Install a press callback that increments `etaf-ui-test-use-count'."
  (apply #'etaf-behavior-create
         'etaf-ui-test-press
         (append attributes
                 (list :on-press
                       (lambda () (cl-incf etaf-ui-test-use-count))))))

(ert-deftest etaf-ui-button-use-behavior-dispatches-through-host ()
  "Install Button `:use' Behavior and dispatch its merged callback."
  (let ((buffer-name " *etaf-ui-button-use-test*"))
    (setq etaf-ui-test-use-count 0)
    (unwind-protect
        (progn
          (etaf-mount
           buffer-name
           (etaf-view
            (etaf-button :label "Behavior" :ref 'behavior-button
                    :use (list (etaf-ui-test-press-behavior)))))
          (etaf-dispatch-event (etaf-runtime-for-buffer buffer-name)
                               'behavior-button 'press)
          (should (= etaf-ui-test-use-count 1)))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-number-input-validates-and-emits-value ()
  "Prompt-backed number input owns bounds and emits the accepted value."
  (let ((buffer-name " *etaf-ui-number-input-test*")
        (value 3))
    (unwind-protect
        (progn
          (etaf-mount
           buffer-name
           (etaf-view
            (etaf-number-input :label "Rows" :value value :ref 'rows
                          :min 1 :max 10
                          :on-change (lambda (next) (setq value next)))))
          (cl-letf (((symbol-function 'read-number)
                     (lambda (&rest _args) 7)))
            (etaf-dispatch-event (etaf-runtime-for-buffer buffer-name)
                                 'rows 'press))
          (should (= 7 value)))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-button-disabled-preserves-explicit-theme-surface ()
  "A disabled Button keeps explicit dark presentation props in its surface."
  (let ((buffer-name " *etaf-ui-themed-disabled-button-test*"))
    (unwind-protect
        (progn
          (etaf-mount
           buffer-name
           (etaf-view
            (etaf-button :label "Unavailable" :ref 'themed-disabled
                    :disabled t :color "#F4F7FF" :bgcolor "#202C42"
                    :border "#34435A")))
          (let ((position
                 (with-current-buffer buffer-name
                   (goto-char (point-min))
                   (search-forward "Unavailable")
                   (1- (point)))))
            (with-current-buffer buffer-name
              (let ((face (get-text-property position 'face)))
                (should (string-match-p "#202C42" (format "%S" face)))
                (should (string-match-p "#F4F7FF" (format "%S" face)))))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-pagination-is-readable-and-boundary-safe ()
  "Pagination renders labeled controls, stable refs, and page boundaries."
  (let* ((source (etaf-data-memory-source
                  '((:id 1) (:id 2) (:id 3) (:id 4) (:id 5))
                  :id-key :id))
         (controller (etaf-data-controller source :page-size 2 :auto-load t))
         (buffer-name " *etaf-ui-pagination-test*"))
    (unwind-protect
        (progn
          (etaf-mount
           buffer-name
           (etaf-view
            (etaf-pagination :controller controller
                        :previous-ref 'page-previous
                        :next-ref 'page-next)))
          (should (string-match-p "Page 1 / 3" (etaf-ui-test--text buffer-name)))
          (should (string-match-p "‹ Previous" (etaf-ui-test--text buffer-name)))
          (should (string-match-p "Next ›" (etaf-ui-test--text buffer-name)))
          ;; Live Ebox windows reserve two pixels for the exclusive display
          ;; boundary; the pager must stay inside the corresponding 360px row.
          (ebox-surface-update-buffer-viewport (get-buffer buffer-name) 358 20)
          (with-current-buffer buffer-name
            (goto-char (point-min))
            (while (< (point) (point-max))
              (should (<= (ebox-string-pixel-width
                           (buffer-substring (line-beginning-position)
                                             (line-end-position)))
                          360))
              (forward-line 1)))
          (etaf-dispatch-event (etaf-runtime-for-buffer buffer-name)
                               'page-next 'press)
          (should (string-match-p "Page 2 / 3" (etaf-ui-test--text buffer-name)))
          (etaf-dispatch-event (etaf-runtime-for-buffer buffer-name)
                               'page-previous 'press)
          (should (string-match-p "Page 1 / 3" (etaf-ui-test--text buffer-name)))
          (should-error
           (etaf-dispatch-event (etaf-runtime-for-buffer buffer-name)
                                'page-previous 'press)
           :type 'etaf-event-error))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-pagination-composes-inside-a-grid-track ()
  "Pagination must distribute free space inside its assigned Grid track."
  (let* ((source (etaf-data-memory-source
                  '((:id 1) (:id 2) (:id 3) (:id 4) (:id 5))
                  :id-key :id))
         (controller (etaf-data-controller source :page-size 2 :auto-load t))
         (buffer-name " *etaf-ui-pagination-grid-test*"))
    (unwind-protect
        (progn
          (etaf-mount
           buffer-name
           (etaf-view
            (grid :width '(px 360)
                  :grid-template-columns '((px 80) (px 200) (px 80))
             (text "Left")
             (column
                  :width 'stretch :padding '((lh 0) (ch 2)) :border "#CBD5E1"
              (etaf-pagination :controller controller
                          :previous-ref 'nested-page-previous
                          :next-ref 'nested-page-next))
             (text "Right"))))
          (with-current-buffer buffer-name
            (goto-char (point-min))
            (while (< (point) (point-max))
              (should (<= (ebox-string-pixel-width
                           (buffer-substring (line-beginning-position)
                                             (line-end-position)))
                          360))
              (forward-line 1))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-data-grid-keeps-long-cells-on-one-line ()
  "Long tabular values use an ellipsis instead of increasing row height."
  (let* ((source (etaf-data-memory-source
                  '((:id 1 :title "The Cathedral and the Bazaar"))
                  :id-key :id))
         (controller (etaf-data-controller source :page-size 10 :auto-load t))
         (buffer-name " *etaf-ui-grid-truncation-test*"))
    (unwind-protect
        (progn
          (etaf-mount
           buffer-name
           (etaf-view
            (etaf-data-grid
             :controller controller
             :columns '((:key :title :label "Title" :width 22))
             :row-key (lambda (row) (plist-get row :id)))))
          (let ((text (etaf-ui-test--text buffer-name)))
            (should (string-match-p "The Cathedral and the…" text))
            (should-not (string-match-p "The Cathedral and the Bazaar" text))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-data-grid-converts-character-columns-and-keeps-air ()
  "Character column descriptors become pixel widths with a stable gap."
  (let* ((source (etaf-data-memory-source
                  '((:id 1 :progress 64 :kind "Essay")) :id-key :id))
         (controller (etaf-data-controller source :auto-load t))
         (buffer-name " *etaf-ui-grid-column-unit-test*"))
    (unwind-protect
        (progn
          (etaf-mount
           buffer-name
           (etaf-view
            (etaf-data-grid
             :controller controller
             :columns '((:key :progress :label "Progress" :width 8)
                        (:key :kind :label "Kind" :width 7))
             :row-key (lambda (row) (plist-get row :id)))))
          (should (string-match-p "Progress[[:space:]]+Kind"
                                  (etaf-ui-test--text buffer-name))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-data-grid-rejects-nil-row-ref ()
  "Reject an interactive row-ref callback that returns nil."
  (let* ((source (etaf-data-memory-source '((:id 1 :name "Ada"))
                                          :id-key :id))
         (controller (etaf-data-controller source :auto-load t))
         (buffer-name " *etaf-ui-grid-nil-row-ref-test*"))
    (unwind-protect
        (should-error
         (etaf-mount
          buffer-name
          (etaf-view
           (etaf-data-grid
            :controller controller
            :columns '((:key :id :label "ID"))
            :row-key (lambda (row) (plist-get row :id))
            :row-ref (lambda (_row) nil)
            :on-row-press (lambda (_row) t)))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-data-grid-projects-loading-error-and-empty ()
  "Project the Data Controller loading, error, and empty states."
  (dolist (case '((loading . "Loading custom")
                  (error . "Error custom")
                  (empty . "Empty custom")))
    (let* ((source (etaf-data-source
                    :load (lambda (&rest _args)
                            (pcase (car case)
                              ('loading (etaf-async (lambda (_yes _no) nil)))
                              ('error (error "source unavailable"))
                              (_ '(:items nil))))))
           (controller (etaf-data-controller source))
           (buffer-name (format " *etaf-ui-grid-%s-test*" (car case))))
      (unwind-protect
          (progn
            (if (eq (car case) 'error)
                (should-error (etaf-data-load controller))
              (etaf-data-load controller))
            (etaf-mount
             buffer-name
             (etaf-view
              (etaf-data-grid
               :controller controller
               :columns '((:key :id :label "ID"))
               :row-key (lambda (row) (plist-get row :id))
               :loading-label (when (eq (car case) 'loading)
                                (cdr case))
               :error-label (when (eq (car case) 'error)
                              (cdr case))
               :empty-label (when (eq (car case) 'empty)
                              (cdr case)))))
            (should (string-match-p (regexp-quote (cdr case))
                                    (etaf-ui-test--text buffer-name))))
        (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
          (etaf-unmount runtime))
        (etaf-data-stop controller)
        (when-let* ((buffer (get-buffer buffer-name)))
          (kill-buffer buffer))))))

(ert-deftest etaf-ui-data-controls-render-async-refresh-and-cancellation ()
  "Pending reads/writes and failures retain accepted rows, actions and focus."
  (let* (resolve complete-write picked
         (controller
          (etaf-data-controller
           (etaf-data-source
            :load (lambda (&rest _args)
                    (etaf-async (lambda (yes _no) (setq resolve yes) nil)))
            :mutate-v2 (lambda (&rest _args)
                         (etaf-async (lambda (yes _no) (setq complete-write yes) nil))))
           :page-size 1 :initial-result '(:items ((:id 1 :name "Ada")) :total 2)))
         (buffer (generate-new-buffer " *async-grid*")))
    (unwind-protect
        (progn
          (etaf-mount buffer
                      (etaf-view
                       (column
                         (etaf-data-grid :controller controller
                                         :columns '((:key :name :label "Name"))
                                         :row-key (lambda (row) (plist-get row :id))
                                         :row-ref (lambda (_row) 'row)
                                         :on-row-press (lambda (row) (setq picked (plist-get row :name))))
                         (etaf-pagination :controller controller :previous-ref 'previous :next-ref 'next))))
          (let ((runtime (etaf-runtime-for-buffer buffer)))
            (etaf-data-load controller)
            (should (string-match-p "Refreshing" (etaf-ui-test--text buffer)))
            (should (string-match-p "Ada" (etaf-ui-test--text buffer)))
            (should (plist-get (etaf-runtime-host-props-for runtime 'next) :disabled))
            (etaf-dispatch-event runtime 'row 'press)
            (should (equal "Ada" picked))
            (etaf-data-cancel controller)
            (should (string-match-p "Loading cancelled" (etaf-ui-test--text buffer)))
            (should (string-match-p "Ada" (etaf-ui-test--text buffer)))
            (setq picked nil)
            (etaf-dispatch-event runtime 'row 'press)
            (should (equal "Ada" picked))
            (should-not (plist-get (etaf-runtime-host-props-for runtime 'next) :disabled))
            (etaf-data-load controller)
            (funcall resolve '(:items ((:id 1 :name "Grace")) :total 2))
            (should-not (string-match-p "Refreshing" (etaf-ui-test--text buffer)))
            (should (string-match-p "Grace" (etaf-ui-test--text buffer)))
            (etaf-dispatch-event runtime 'row 'press)
            (should (equal "Grace" picked))
            (etaf-focus runtime 'row)
            (etaf-data-mutate controller 'update nil)
            (should (string-match-p "Loading" (etaf-ui-test--text buffer)))
            (should (string-match-p "Grace" (etaf-ui-test--text buffer)))
            (should (eq 'row (etaf-focused-host-ref runtime)))
            (funcall complete-write '(:certainty rolled-back :error (error "Write rejected")))
            (should (string-match-p "Unable to load" (etaf-ui-test--text buffer)))
            (should (string-match-p "Grace" (etaf-ui-test--text buffer)))
            (setq picked nil)
            (etaf-dispatch-event runtime 'row 'press)
            (should (equal "Grace" picked))
            (etaf-data-load controller)
            (funcall resolve '(:items nil :total 0))
            (should (string-match-p "No data" (etaf-ui-test--text buffer)))
            (etaf-data-load controller)
            (should (string-match-p "Refreshing" (etaf-ui-test--text buffer)))
            (should (string-match-p "No data" (etaf-ui-test--text buffer)))
            (funcall resolve '(:items nil :total 0))
            (should-not (string-match-p "Refreshing" (etaf-ui-test--text buffer)))))
      (when (etaf-runtime-for-buffer buffer) (etaf-unmount (etaf-runtime-for-buffer buffer)))
      (etaf-data-stop controller)
      (kill-buffer buffer))))

(ert-deftest etaf-ui-data-grid-requires-stable-row-key ()
  "Reject a DataGrid that cannot identify retained rows."
  (let* ((source (etaf-data-memory-source
                  '((:id 1 :name "Ada"))
                  :id-key :id))
         (controller (etaf-data-controller source :auto-load t))
         (buffer-name " *etaf-ui-grid-row-key-test*"))
    (unwind-protect
        (should-error
         (etaf-mount
          buffer-name
          (etaf-view
           (etaf-data-grid
            :controller controller
            :columns '((:key :id :label "ID"))))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-data-grid-rejects-nil-row-key ()
  "Reject a DataGrid row-key function that returns no identity."
  (let* ((source (etaf-data-memory-source
                  '((:id 1 :name "Ada"))
                  :id-key :id))
         (controller (etaf-data-controller source :auto-load t))
         (buffer-name " *etaf-ui-grid-nil-row-key-test*"))
    (unwind-protect
        (should-error
         (etaf-mount
          buffer-name
          (etaf-view
           (etaf-data-grid
            :controller controller
            :columns '((:key :id :label "ID"))
            :row-key (lambda (_row) nil)))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(provide 'etaf-ui-tests)
;;; etaf-ui-tests.el ends here
