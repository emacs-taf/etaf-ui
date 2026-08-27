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

(defun etaf-ui-test--props-with-class (buffer-name class)
  "Return mounted Host properties with CLASS in BUFFER-NAME."
  (let (found)
    (maphash
     (lambda (_ref props)
       (when (equal (plist-get props :class) class)
         (setq found props)))
     (etaf-runtime-host-props (etaf-runtime-for-buffer buffer-name)))
    found))

(defun etaf-ui-test--paint-color (value property)
  "Return effective paint color from VALUE for Ebox PROPERTY."
  (if (not (tp-paint-slot-p value))
      value
    (let ((spec (tp-paint-slot-spec value)))
      (pcase property
        (:color (plist-get spec :foreground))
        ((or :bgcolor :background-color) (plist-get spec :background))
        (:border-top-color (plist-get spec :overline))
        (:border-bottom-color
         (plist-get (plist-get spec :underline) :color))
        ((or :border-left-color :border-right-color)
         (plist-get spec :background))))))

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

(etaf-define-component etaf-ui-test-token-theme-fixture ()
  "Provide explicit UI Button tokens through ETAF Theme."
  :setup
  (progn
    (etaf-theme-provide
     '(:ui-button-color "token-fg"
       :ui-button-bgcolor "token-bg"
       :ui-button-border "token-border"
       :ui-button-secondary-color "secondary-fg"
       :ui-button-secondary-bgcolor "secondary-bg"
       :ui-button-secondary-border "secondary-border"))
    (lambda ()
      (etaf-view
       (row
        (button :label "Token" :ref 'token-button)
        (button :label "Secondary" :ref 'token-secondary
                :variant 'secondary))))))

(etaf-define-component etaf-ui-test-grid-theme-fixture
    (&key controller theme)
  "Provide a reactive Theme around one DataGrid for palette tests."
  :setup
  (progn
    (etaf-theme-provide (etaf-current-prop :theme))
    (lambda ()
      (etaf-view
       (data-grid
        :controller (etaf-current-prop :controller)
        :columns '((:key :id :label "ID") (:key :name :label "Name"))
        :row-key (lambda (row) (plist-get row :id))
         :selected-key 1)))))

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
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let* ((buffer (get-buffer buffer-name)))
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
            (should-not (plist-get themed :padding))
            (should (equal (plist-get panel :color) "#252A2E"))
            (should (equal (plist-get panel :bgcolor) "#FFFDF8"))
            (should (equal (plist-get panel :padding) '(1 2)))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-button-reads-variant-tokens-from-theme ()
  "Resolve Button presentation defaults from inherited Theme tokens."
  (let ((buffer-name " *etaf-ui-button-token-theme-test*"))
    (unwind-protect
        (progn
          (etaf-mount buffer-name
                      (etaf-view (ui-test-token-theme-fixture)))
          (let ((token (etaf-ui-test--props buffer-name 'token-button))
                (secondary (etaf-ui-test--props buffer-name 'token-secondary)))
            (should (equal "token-fg" (plist-get token :color)))
            (should (equal "token-bg" (plist-get token :bgcolor)))
            (should (equal "token-border" (plist-get token :border)))
            (should (equal "secondary-fg" (plist-get secondary :color)))
            (should (equal "secondary-bg" (plist-get secondary :bgcolor)))
            (should (equal "secondary-border"
                           (plist-get secondary :border)))))
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
            (number-input :label "Rows" :value value :ref 'rows
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
                                    :font-weight 'bold
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
            (should (equal (plist-get props :font-weight) 'bold))
            (should (string-match-p "primary" (plist-get props :class))))
          (etaf-dispatch-event (etaf-runtime-for-buffer buffer-name)
                               'save 'press)
          (should (= presses 1)))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let* ((buffer (get-buffer buffer-name)))
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
            (should (equal (plist-get props :font-weight) 'bold)))
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
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer))))))

(ert-deftest etaf-ui-button-dispatches-without-retained-press-state ()
  "Buttons dispatch through semantic Host state without local press state."
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
                   "enabled"
                   (plist-get (etaf-ui-test--props buffer-name 'health)
                              :class)))
          (should-not (string-match-p
                       "pressed"
                       (plist-get (etaf-ui-test--props buffer-name 'health)
                                  :class)))
            (should (eq before
                        (cdr (assq 'press
                                   (etaf-runtime-handler-for runtime 'health)))))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let* ((buffer (get-buffer buffer-name)))
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
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-checkbox-reactive-value-updates-through-inline-range ()
  "Update a reactive CHECKED source without rerunning Checkbox Component."
  (let ((buffer-name " *etaf-ui-reactive-checkbox-test*")
        (checked (etaf-ref nil))
        (component-renders 0))
    (unwind-protect
        (progn
          (etaf-mount
           buffer-name
           (etaf-view
            (checkbox :label "Live" :ref 'live-checkbox :checked checked
                      :on-change (lambda (value)
                                   (setf (etaf-value checked) value)))))
          (let ((render (symbol-function
                         'etaf--runtime-render-dirty-component)))
            (cl-letf (((symbol-function 'etaf--runtime-render-dirty-component)
                       (lambda (&rest arguments)
                         (cl-incf component-renders)
                         (apply render arguments))))
              (etaf-dispatch-event (etaf-runtime-for-buffer buffer-name)
                                   'live-checkbox 'press)))
          (should (etaf-value checked))
          (should (string-match-p "☑ Live"
                                  (etaf-ui-test--text buffer-name)))
          (should (zerop component-renders)))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-label-reactive-text-updates-through-inline-range ()
  "Update reactive Label text without rerunning its Component."
  (let ((buffer-name " *etaf-ui-reactive-label-test*")
        (text (etaf-ref "One"))
        (component-renders 0))
    (unwind-protect
        (progn
          (etaf-mount buffer-name
                      (etaf-view (label :text text :ref 'live-label)))
          (let ((render (symbol-function
                         'etaf--runtime-render-dirty-component)))
            (cl-letf (((symbol-function 'etaf--runtime-render-dirty-component)
                       (lambda (&rest arguments)
                         (cl-incf component-renders)
                         (apply render arguments))))
              (setf (etaf-value text) "Two")))
          (should (equal "Two" (etaf-ui-test--text buffer-name)))
          (should (zerop component-renders)))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let* ((buffer (get-buffer buffer-name)))
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
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let* ((buffer (get-buffer buffer-name)))
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
                               :font-weight 'bold :width 12))
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
            (should (equal (plist-get label :font-weight) 'bold))
            (should (equal (plist-get label :width) 12)))
          (dolist (label '("Account" "Settings" "Body"))
            (should (string-match-p (regexp-quote label)
                                    (etaf-ui-test--text buffer-name)))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let* ((buffer (get-buffer buffer-name)))
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
            (should (string-match-p
                     "selected" (or (plist-get second :class) "")))
            (should-not (string-match-p
                         "selected" (or (plist-get first :class) ""))))
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
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-data-grid-default-selection-updates-only-delta-hosts ()
  "Controller selection updates old/new row Hosts without rebuilding rows."
  (let* ((source (etaf-data-memory-source
                  '((:id 1 :name "Ada")
                    (:id 2 :name "Grace")
                    (:id 3 :name "Alan"))
                  :id-key :id))
         (controller (etaf-data-controller source :auto-load t))
         (buffer-name " *etaf-ui-grid-keyed-selection-test*")
         (row-renders (make-hash-table :test #'eql))
         (body-renders 0)
         host-updates)
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
                        (intern (format "keyed-row-%d" (plist-get row :id))))
             :on-row-press
             (lambda (row)
               (etaf-data-select-one controller (plist-get row :id))))))
          (etaf-data-select-one controller 1)
          (let* ((runtime (etaf-runtime-for-buffer buffer-name))
                 (text-before (etaf-ui-test--text buffer-name))
                 (third-handler
                  (cdr (assq 'press
                             (etaf-runtime-handler-for runtime 'keyed-row-3))))
                 (old-grid-row (symbol-function 'etaf-ui--grid-row))
                 (old-grid-rows (symbol-function 'etaf-ui--grid-rows))
                 (old-host
                  (symbol-function 'ebox-candidate-replace-host-ref))
                 (old-paint
                  (symbol-function 'ebox-candidate-patch-host-paint)))
            (cl-letf (((symbol-function 'etaf-ui--grid-row)
                       (lambda (&rest args)
                         (let ((key (nth 1 args)))
                           (puthash key (1+ (gethash key row-renders 0))
                                    row-renders))
                         (apply old-grid-row args)))
                      ((symbol-function 'etaf-ui--grid-rows)
                       (lambda (&rest args)
                         (cl-incf body-renders)
                         (apply old-grid-rows args)))
                      ((symbol-function 'ebox-candidate-replace-host-ref)
                       (lambda (candidate ref node)
                         (push ref host-updates)
                         (funcall old-host candidate ref node)))
                      ((symbol-function 'ebox-candidate-patch-host-paint)
                       (lambda (candidate ref old-node new-node)
                         (push ref host-updates)
                         (funcall old-paint candidate ref old-node new-node))))
              ;; Prove direct public selection ref writes use the same keyed
              ;; invalidation path as the selection helpers.
              (setf (etaf-value (etaf-data-selection controller)) '(2)))
            (should (zerop (gethash 1 row-renders 0)))
            (should (zerop (gethash 2 row-renders 0)))
            (should (zerop (gethash 3 row-renders 0)))
            (should (zerop (hash-table-count row-renders)))
            (should (zerop body-renders))
            (should (member 'keyed-row-1 host-updates))
            (should (member 'keyed-row-2 host-updates))
            (should-not (member 'keyed-row-3 host-updates))
            (should (equal text-before (etaf-ui-test--text buffer-name)))
            (should-not
             (string-match-p
              "selected"
              (or (plist-get (etaf-ui-test--props buffer-name 'keyed-row-1)
                             :class)
                  "")))
            (should
             (string-match-p
              "selected"
              (or (plist-get (etaf-ui-test--props buffer-name 'keyed-row-2)
                             :class)
                  "")))
            (should (eq third-handler
                        (cdr (assq
                              'press
                              (etaf-runtime-handler-for runtime
                                                        'keyed-row-3)))))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-data-grid-follows-inherited-theme-color ()
  "Re-render DataGrid rows when only inherited Theme color changes."
  (let* ((theme (etaf-ref '(:color "light-ink"
                             :ui-grid-border "light-grid-border"
                             :ui-grid-selected-fg "light-selected"
                             :ui-grid-selected-bg "light-selected-bg")))
         (source (etaf-data-memory-source
                  '((:id 1 :name "Ada") (:id 2 :name "Grace")) :id-key :id))
         (controller (etaf-data-controller source :auto-load t))
         (buffer-name " *etaf-ui-grid-theme-test*"))
    (unwind-protect
        (progn
          (etaf-mount
           buffer-name
           (etaf-view
            (ui-test-grid-theme-fixture :controller controller :theme theme)))
          (let* ((props (etaf-ui-test--props-with-key buffer-name 1))
                 (background-slot (plist-get props :bgcolor))
                 (border-slot (plist-get props :border-bottom-color)))
          (should (equal "light-selected-bg"
                         (etaf-ui-test--paint-color
                          background-slot :bgcolor)))
          (should (equal "light-grid-border"
                         (etaf-ui-test--paint-color
                          border-slot :border-bottom-color)))
          (should (plist-get (etaf-ui-test--props-with-key buffer-name 1)
                             :border-bottom-p))
          (setf (etaf-value theme) '(:color "dark-ink"
                                      :ui-grid-border "dark-grid-border"
                                      :ui-grid-selected-fg "dark-selected"
                                      :ui-grid-selected-bg "dark-selected-bg"))
          (let ((next (etaf-ui-test--props-with-key buffer-name 1)))
            (should (eq background-slot (plist-get next :bgcolor)))
            (should (eq border-slot (plist-get next :border-bottom-color)))
            (should (equal "dark-selected-bg"
                           (etaf-ui-test--paint-color
                            background-slot :bgcolor)))
            (should (equal "dark-grid-border"
                           (etaf-ui-test--paint-color
                            border-slot :border-bottom-color))))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (when-let* ((buffer (get-buffer buffer-name)))
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
          (should (string-match-p "←" (etaf-ui-test--text buffer-name)))
          (should (string-match-p "→" (etaf-ui-test--text buffer-name)))
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
            (grid :width '(360)
                  :grid-template-columns '((80) (200) (80))
             (text "Left")
             (column
                  :width 'stretch :padding '(0 2) :border "#CBD5E1"
              (pagination :controller controller
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
            (data-grid
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
            (data-grid
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
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (when-let* ((buffer (get-buffer buffer-name)))
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
           (data-grid
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
        (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
          (etaf-unmount runtime))
        (etaf-data-stop controller)
        (when-let* ((buffer (get-buffer buffer-name)))
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
           (data-grid
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
