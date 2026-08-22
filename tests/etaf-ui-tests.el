;;; etaf-ui-tests.el --- Official ETAF Component tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'etaf-ui)

(defun etaf-ui-test--text (buffer-name)
  "Return plain text currently published in BUFFER-NAME."
  (with-current-buffer buffer-name
    (string-trim-right (substring-no-properties (buffer-string)))))

(defun etaf-ui-test--props (buffer-name ref)
  "Return mounted Host properties for REF in BUFFER-NAME."
  (gethash ref
           (etaf-runtime-host-props
            (etaf-runtime-for-buffer buffer-name))))

(defun etaf-ui-test--props-with-key (buffer-name key)
  "Return mounted Host properties with Host KEY in BUFFER-NAME."
  (let (found)
    (maphash
     (lambda (_ref props)
       (when (equal (plist-get props :key) key)
         (setq found props)))
     (etaf-runtime-host-props (etaf-runtime-for-buffer buffer-name)))
    found))

(defun etaf-ui-test--surface-properties (buffer-name ref)
  "Return interactive text properties at REF's first rendered position."
  (let* ((runtime (etaf-runtime-for-buffer buffer-name))
         (position (etaf-host-ref-position runtime ref)))
    (with-current-buffer buffer-name
      (list (get-text-property position 'pointer)
            (get-text-property position 'mouse-face)
            (get-text-property position 'help-echo)))))

(defvar etaf-ui-test-use-count 0)

(etaf-define-behavior etaf-ui-test-press-behavior (&rest attributes)
  "Install a press callback that increments `etaf-ui-test-use-count'."
  (apply #'etaf-behavior-create
         'etaf-ui-test-press
         (append attributes
                 (list :on-press
                       (lambda () (cl-incf etaf-ui-test-use-count))))))

(etaf-define-component etaf-ui-test-theme-fixture ()
  "Provide Theme defaults for official Component presentation tests."
  :setup
  (progn
    (etaf-theme-provide '(:color "theme-color"
                          :bgcolor "theme-bg"
                          :padding (9 9)))
    (lambda ()
      (etaf-view
       (row
        (button :label "Styled" :ref 'styled-button)
        (button :label "Custom" :ref 'custom-button
                :color "explicit-color")
        (label :text "Themed" :ref 'themed-label
               :color nil :bgcolor nil)
        (panel :title "Styled panel" :ref 'styled-panel))))))

(ert-deftest etaf-ui-button-use-behavior-dispatches-through-host ()
  "Install Button `:use' Behavior and dispatch its merged callback."
  (let ((buffer-name " *etaf-ui-button-use-test*"))
    (setq etaf-ui-test-use-count 0)
    (unwind-protect
        (progn
          (etaf-mount
           buffer-name
           (etaf-view
            (button :label "Behavior" :ref 'behavior-button
                    :use (list (etaf-ui-test-press-behavior)))))
          (etaf-dispatch-event (etaf-runtime-for-buffer buffer-name)
                               'behavior-button 'press)
          (should (= etaf-ui-test-use-count 1)))
      (when-let ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-defaults-use-styles-and-preserve-theme ()
  "Use Component styles for defaults and Theme for omitted properties."
  (let ((buffer-name " *etaf-ui-style-default-test*"))
    (unwind-protect
        (progn
          (etaf-mount buffer-name
                      (etaf-view (ui-test-theme-fixture)))
          (let ((styled (etaf-ui-test--props buffer-name 'styled-button))
                (custom (etaf-ui-test--props buffer-name 'custom-button))
                (themed (etaf-ui-test--props buffer-name 'themed-label))
                (panel (etaf-ui-test--props buffer-name 'styled-panel)))
            (should (equal (plist-get styled :color) "#FFFFFF"))
            (should (equal (plist-get styled :bgcolor) "#2F6B43"))
            (should (equal (plist-get styled :padding) '(0 1)))
            (should (equal (plist-get custom :color) "explicit-color"))
            (should (equal (plist-get custom :bgcolor) "#2F6B43"))
            (should (equal (plist-get themed :color) "theme-color"))
            (should (equal (plist-get themed :bgcolor) "theme-bg"))
            (should (equal (plist-get themed :padding) '(9 9)))
            (should (equal (plist-get panel :color) "#252A2E"))
            (should (equal (plist-get panel :bgcolor) "#FFFDF8"))
            (should (equal (plist-get panel :padding) '(1 2)))))
      (when-let ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-button-dispatches-and-exposes-enabled-props ()
  "Render an enabled button with semantic and presentation properties."
  (let ((buffer-name " *etaf-ui-button-test*")
        (presses 0))
    (unwind-protect
        (progn
          (etaf-mount buffer-name
                      (etaf-view
                       (button :label "Save" :ref 'save
                                    :class "primary"
                                    :color "#FFFFFF"
                                    :bgcolor "#2F6B43"
                                    :border "#2F6B43"
                                    :padding '(0 2)
                                    :face 'bold
                                    :tab-index 3
                                    :aria-label "Save changes"
                                    :on-press (lambda () (cl-incf presses)))))
          (should (string-match-p "Save" (etaf-ui-test--text buffer-name)))
          (let ((props (etaf-ui-test--props buffer-name 'save)))
            (should (equal (plist-get props :role) 'button))
            (should (eq (plist-get props :width) 'max-content))
            (should (equal (plist-get props :tab-index) 3))
            (should (equal (plist-get props :aria-label) "Save changes"))
            (should (equal (plist-get props :color) "#FFFFFF"))
            (should (equal (plist-get props :bgcolor) "#2F6B43"))
            (should (equal (plist-get props :border) "#2F6B43"))
            (should (equal (plist-get props :padding) '(0 2)))
            (should (equal (plist-get props :face) 'bold))
            (should (string-match-p "primary" (plist-get props :class))))
          (etaf-dispatch-event (etaf-runtime-for-buffer buffer-name)
                               'save 'press)
          (should (= presses 1)))
      (when-let ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-button-disabled-is-not-interactive ()
  "A disabled button has no callback and is not a focus candidate."
  (let ((buffer-name " *etaf-ui-disabled-button-test*")
        (presses 0))
    (setq etaf-ui-test-use-count 0)
    (unwind-protect
        (progn
          (etaf-mount buffer-name
                      (etaf-view
                       (row
                        (button :label "Save" :ref 'enabled-save
                                     :on-press (lambda () (cl-incf presses)))
                        (button :label "Delete" :ref 'disabled-delete
                                     :disabled t
                                     :use (list (etaf-ui-test-press-behavior))
                                     :on-press (lambda () (cl-incf presses))))))
          (let ((props (etaf-ui-test--props buffer-name 'enabled-save)))
            (should (equal (plist-get props :color) "#FFFFFF"))
            (should (equal (plist-get props :bgcolor) "#2F6B43"))
            (should (equal (plist-get props :padding) '(0 1)))
            (should (equal (plist-get props :face) 'bold)))
          (let ((props (etaf-ui-test--props buffer-name 'disabled-delete)))
            (should (eq (plist-get props :disabled) t))
            (should-not (plist-get props :tab-index))
            (should (equal (plist-get props :bgcolor) "#E5E7EB"))
            (should (string-match-p "disabled" (plist-get props :class))))
          (should-error
           (etaf-dispatch-event (etaf-runtime-for-buffer buffer-name)
                                'disabled-delete 'press)
           :type 'etaf-event-error)
          (etaf-focus-next (etaf-runtime-for-buffer buffer-name))
          (should (eq (etaf-focused-host-ref
                       (etaf-runtime-for-buffer buffer-name))
                      'enabled-save))
          (should (= presses 0))
          (should (= etaf-ui-test-use-count 0)))
      (when-let ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-button-disabled-preserves-explicit-theme-surface ()
  "A disabled Button keeps explicit dark presentation props in its surface."
  (let ((buffer-name " *etaf-ui-themed-disabled-button-test*"))
    (unwind-protect
        (progn
          (etaf-mount
           buffer-name
           (etaf-view
            (button :label "Unavailable" :ref 'themed-disabled
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
                (should (string-match-p "#F4F7FF" (format "%S" face))))))
      (when-let ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer))))))

(ert-deftest etaf-ui-button-owns-pointer-hover-and-pressed-feedback ()
  "Buttons expose native pointer/hover affordances and a pressed state."
  (let ((buffer-name " *etaf-ui-button-surface-test*")
        (presses 0))
    (unwind-protect
        (progn
          (etaf-mount
           buffer-name
           (etaf-view
            (button :label "Run health check" :ref 'health
                    :variant 'secondary
                    :on-press (lambda () (cl-incf presses)))))
          (let ((surface (etaf-ui-test--surface-properties buffer-name 'health)))
            (should (eq (nth 0 surface) 'hand))
            (should (eq (nth 1 surface) 'highlight))
            (should (string-match-p "RET" (nth 2 surface))))
          (let ((props (etaf-ui-test--props buffer-name 'health)))
            (should (equal (plist-get props :color) "#142235"))
            (should (equal (plist-get props :bgcolor) "#D9EEEA")))
          (let* ((runtime (etaf-runtime-for-buffer buffer-name))
                 (before (cdr (assq 'press
                                    (etaf-runtime-handler-for runtime 'health)))))
            (should (functionp before))
          (etaf-dispatch-event (etaf-runtime-for-buffer buffer-name)
                               'health 'press)
          (should (= presses 1))
          (should (string-match-p
                   "pressed"
                   (plist-get (etaf-ui-test--props buffer-name 'health)
                              :class)))
            (should (eq before
                        (cdr (assq 'press
                                   (etaf-runtime-handler-for runtime 'health)))))))
      (when-let ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-checkbox-is-controlled-and-focusable ()
  "Render a controlled checkbox, toggle it, and retain its focus contract."
  (let ((buffer-name " *etaf-ui-checkbox-test*")
        (checked (etaf-ref nil))
        next)
    (unwind-protect
        (progn
          (etaf-mount buffer-name
                      (etaf-view
                       (checkbox :label "Done" :ref 'done
                                      :checked (etaf-value checked)
                                      :on-change (lambda (value)
                                                   (setq next value)
                                                   (setf (etaf-value checked)
                                                         value)))))
          (should (string-match-p "☐ Done" (etaf-ui-test--text buffer-name)))
          (let ((props (etaf-ui-test--props buffer-name 'done)))
            (should (equal (plist-get props :role) 'checkbox))
            (should (eq (plist-get props :width) 'max-content))
            (should (equal (plist-get props :tab-index) 0))
            (should (equal (plist-get props :ref) 'done)))
          (etaf-dispatch-event (etaf-runtime-for-buffer buffer-name)
                               'done 'press)
          (should (eq next t))
          (should (string-match-p "☑ Done" (etaf-ui-test--text buffer-name)))
          (etaf-focus-next (etaf-runtime-for-buffer buffer-name))
          (should (eq (etaf-focused-host-ref
                       (etaf-runtime-for-buffer buffer-name))
                      'done)))
      (when-let ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-checkbox-disabled-is-not-interactive ()
  "A disabled checkbox has no callback or tab stop and remains visible."
  (let ((buffer-name " *etaf-ui-disabled-checkbox-test*")
        (changes 0))
    (unwind-protect
        (progn
          (etaf-mount buffer-name
                      (etaf-view
                       (row
                        (checkbox :label "Open" :ref 'open-box
                                       :on-change (lambda (_value)
                                                    (cl-incf changes)))
                        (checkbox :label "Closed" :ref 'closed-box
                                       :disabled t
                                       :on-change (lambda (_value)
                                                    (cl-incf changes))))))
          (let ((props (etaf-ui-test--props buffer-name 'closed-box)))
            (should (eq (plist-get props :disabled) t))
            (should-not (plist-get props :tab-index))
            (should (equal (plist-get props :bgcolor) "#EEEAE2"))
            (should (string-match-p "disabled" (plist-get props :class))))
          (should-error
           (etaf-dispatch-event (etaf-runtime-for-buffer buffer-name)
                                'closed-box 'press)
           :type 'etaf-event-error)
          (etaf-focus-next (etaf-runtime-for-buffer buffer-name))
          (should (eq (etaf-focused-host-ref
                       (etaf-runtime-for-buffer buffer-name))
                      'open-box))
          (should (= changes 0)))
      (when-let ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-label-and-panel-expose-presentation-and-slots ()
  "Render Label and Panel presentation props with named/default slots."
  (let ((buffer-name " *etaf-ui-panel-test*"))
    (unwind-protect
        (progn
          (etaf-mount
           buffer-name
           (etaf-view
            (panel :title "Account" :ref 'account-panel
             :class "surface" :color "#252A2E" :bgcolor "#FFFDF8"
             :border "#687386" :padding '(1 2)
             (slot :name 'header
                   (label :text "Settings" :ref 'settings-label
                               :class "eyebrow" :color "#66706A"
                               :face 'bold :width 12))
             (label :text "Body"))))
          (let ((panel (etaf-ui-test--props buffer-name 'account-panel))
                (label (etaf-ui-test--props buffer-name 'settings-label)))
            (should (string-match-p "surface" (plist-get panel :class)))
            (should (equal (plist-get panel :color) "#252A2E"))
            (should (equal (plist-get panel :bgcolor) "#FFFDF8"))
            (should (equal (plist-get panel :border) "#687386"))
            (should (equal (plist-get panel :padding) '(1 2)))
            (should (string-match-p "eyebrow" (plist-get label :class)))
            (should (equal (plist-get label :color) "#66706A"))
            (should (equal (plist-get label :face) 'bold))
            (should (equal (plist-get label :width) 12)))
          (dolist (label '("Account" "Settings" "Body"))
            (should (string-match-p (regexp-quote label)
                                    (etaf-ui-test--text buffer-name)))))
      (when-let ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-data-grid-projects-reactive-controller ()
  "Render DataGrid rows, refs, semantics, selection, and dispatch."
  (let* ((source (etaf-data-memory-source
                  '((:id 1 :name "Ada") (:id 2 :name "Grace"))
                  :id-key :id))
         (controller (etaf-data-controller source :page-size 10 :auto-load t))
         (buffer-name " *etaf-ui-grid-test*")
         pressed)
    (unwind-protect
        (progn
          (etaf-mount
           buffer-name
           (etaf-view
            (data-grid
             :controller controller
             :columns '((:key :id :label "ID")
                        (:key :name :label "Name"))
             :row-key (lambda (row) (plist-get row :id))
             :row-ref (lambda (row)
                        (intern (format "row-%d" (plist-get row :id))))
             :selected-key 2
             :on-row-press (lambda (row) (setq pressed row)))))
          (should (string-match-p "Ada" (etaf-ui-test--text buffer-name)))
          (let ((first (etaf-ui-test--props buffer-name 'row-1))
                (second (etaf-ui-test--props buffer-name 'row-2)))
            (should (equal (plist-get first :role) 'button))
            (should (equal (plist-get first :tab-index) 0))
            (should (equal (plist-get second :role) 'button))
            (should (equal (plist-get second :tab-index) 0))
            (should (string-match-p "selected" (plist-get second :class)))
            (should-not (string-match-p "selected" (plist-get first :class))))
          (let* ((runtime (etaf-runtime-for-buffer buffer-name))
                 (handler (cdr (assq 'press
                                     (etaf-runtime-handler-for runtime
                                                               'row-1)))))
            (etaf-dispatch-event runtime 'row-1 'press)
            (should (equal (plist-get pressed :id) 1))
            (etaf-data-mutate controller 'insert '(:id 3 :name "Alan"))
            (should (eq handler
                        (cdr (assq 'press
                                   (etaf-runtime-handler-for runtime 'row-1)))))
            (should (string-match-p "Alan" (etaf-ui-test--text buffer-name)))
            (should (equal (plist-get (etaf-ui-test--props buffer-name 'row-3)
                                      :tab-index)
                           0))))
      (when-let ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (when-let ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-pagination-is-readable-and-boundary-safe ()
  "Pagination renders Unicode controls, stable refs, and page boundaries."
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
            (pagination :controller controller
                        :previous-ref 'page-previous
                        :next-ref 'page-next)))
          (should (string-match-p "Page 1 / 3" (etaf-ui-test--text buffer-name)))
          (should (string-match-p "‹" (etaf-ui-test--text buffer-name)))
          (should (string-match-p "›" (etaf-ui-test--text buffer-name)))
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
          (should (eq (nth 0 (etaf-ui-test--surface-properties
                              buffer-name 'page-next))
                      'hand))
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
      (when-let ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (when-let ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-data-grid-noninteractive-rows-have-no-focus-contract ()
  "Rows without ON-ROW-PRESS have no role, ref callback, or tab stop."
  (let* ((source (etaf-data-memory-source '((:id 1 :name "Ada"))
                                          :id-key :id))
         (controller (etaf-data-controller source :auto-load t))
         (buffer-name " *etaf-ui-grid-static-row-test*"))
    (unwind-protect
        (progn
          (etaf-mount
           buffer-name
           (etaf-view
            (data-grid
             :controller controller
             :columns '((:key :id :label "ID"))
             :row-key (lambda (row) (plist-get row :id)))))
          (let ((props (etaf-ui-test--props-with-key buffer-name 1)))
            (should-not (plist-get props :role))
            (should-not (plist-get props :tab-index))))
      (when-let ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (when-let ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-data-grid-requires-row-ref-for-interaction ()
  "Reject an interactive DataGrid without a row-ref callback."
  (let* ((source (etaf-data-memory-source '((:id 1 :name "Ada"))
                                          :id-key :id))
         (controller (etaf-data-controller source :auto-load t))
         (buffer-name " *etaf-ui-grid-row-ref-test*"))
    (unwind-protect
        (should-error
         (etaf-mount
          buffer-name
          (etaf-view
           (data-grid
            :controller controller
            :columns '((:key :id :label "ID"))
            :row-key (lambda (row) (plist-get row :id))
            :on-row-press (lambda (_row) t)))))
      (when-let ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (when-let ((buffer (get-buffer buffer-name)))
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
           (data-grid
            :controller controller
            :columns '((:key :id :label "ID"))
            :row-key (lambda (row) (plist-get row :id))
            :row-ref (lambda (_row) nil)
            :on-row-press (lambda (_row) t)))))
      (when-let ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (when-let ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-data-grid-projects-loading-error-and-empty ()
  "Project the Data Controller loading, error, and empty states."
  (dolist (case '((loading . "Loading custom")
                  (error . "Error custom")
                  (empty . "Empty custom")))
    (let* ((source (etaf-data-memory-source '((:id 1 :name "Ada"))
                                            :id-key :id))
           (controller (etaf-data-controller source))
           (buffer-name (format " *etaf-ui-grid-%s-test*" (car case))))
      (unwind-protect
          (progn
            (setf (etaf-value (etaf-data-status controller))
                  (car case))
            (setf (etaf-value (etaf-data-items controller))
                  (when (eq (car case) 'empty) nil))
            (etaf-mount
             buffer-name
             (etaf-view
              (data-grid
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
        (when-let ((runtime (etaf-runtime-for-buffer buffer-name)))
          (etaf-unmount runtime))
        (etaf-data-stop controller)
        (when-let ((buffer (get-buffer buffer-name)))
          (kill-buffer buffer))))))

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
           (data-grid
            :controller controller
            :columns '((:key :id :label "ID"))))))
      (when-let ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (when-let ((buffer (get-buffer buffer-name)))
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
           (data-grid
            :controller controller
            :columns '((:key :id :label "ID"))
            :row-key (lambda (_row) nil)))))
      (when-let ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (when-let ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(provide 'etaf-ui-tests)

;;; etaf-ui-tests.el ends here
