;;; etaf-ui-field.el --- Native in-place text fields -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; The catalog's one text editing Component.  A field is ordinary rendered
;; text until it is activated; activation opens a native editing session over
;; that text in the application's own buffer, so input methods, point,
;; selection and undo stay native while no extra frame, window or per-field
;; surface is created.  Single-line and multi-line fields share the Component;
;; `:rows' selects the visible height.  Applications keep values, drafts and
;; submission policy.

;;; Code:
(require 'cl-lib)
(require 'etaf-ui-basic)
(require 'etaf-ui-input)

(cl-defstruct (etaf-ui--text-input (:constructor etaf-ui--text-input-create))
  runtime ref text-ref props-fn session snapshot last-text active)
(defvar etaf-ui--text-inputs (make-hash-table :test #'eq)
  "Mounted text inputs keyed by Runtime, then by public Host reference.")
(defvar-local etaf-ui--field-active nil
  "Text input owning the current buffer's editing session, if any.")
(defvar etaf-ui--active-text-input nil
  "Text input currently editing, regardless of the current buffer.")
(defvar-local etaf-ui--field-restore nil
  "Buffer-local state replaced while a text input session is active.")

(defun etaf-ui--text-input-table (runtime)
  "Return RUNTIME's text input table, creating it on first use."
  (or (gethash runtime etaf-ui--text-inputs)
      (puthash runtime (make-hash-table :test #'equal) etaf-ui--text-inputs)))

(defun etaf-ui--text-input-find (runtime ref)
  "Return RUNTIME's mounted text input for REF, or nil."
  (and runtime (gethash ref (gethash runtime etaf-ui--text-inputs))))

(defun etaf-ui--text-input-props (field)
  "Return FIELD's committed public inputs."
  (funcall (etaf-ui--text-input-props-fn field)))

(defun etaf-ui--text-input-display (props)
  "Return PROPS' visible field text, never empty so the field stays editable."
  (let ((value (plist-get props :value)))
    (if (or (null value) (equal value ""))
        (let ((placeholder (plist-get props :placeholder)))
          (if (and (stringp placeholder) (not (equal placeholder ""))) placeholder " "))
      value)))

;;;###autoload
(define-minor-mode etaf-ui-field-mode
  "Key bindings for the active in-place text field in the current buffer.
Enabled by the field Component for the duration of a native editing session
and disabled again when it ends.  The renderer's buffer-mode map is suspended
meanwhile so ordinary typing reaches the session."
  :lighter nil
  :keymap (let ((map (make-sparse-keymap)))
            (define-key map (kbd "RET") #'etaf-ui-field--return)
            (define-key map (kbd "<return>") #'etaf-ui-field--return)
            (define-key map (kbd "C-<return>") #'etaf-ui-field--submit)
            (define-key map (kbd "C-c C-c") #'etaf-ui-field--submit)
            (define-key map (kbd "C-c C-k") #'etaf-ui-field--cancel)
            (define-key map (kbd "C-g") #'etaf-ui-field--cancel)
            (define-key map (kbd "<escape>") #'etaf-ui-field--cancel)
            (define-key map (kbd "<S-return>") #'newline)
            (define-key map (kbd "C-j") #'newline)
            (define-key map (kbd "TAB") #'etaf-ui-field--next)
            (define-key map (kbd "<backtab>") #'etaf-ui-field--previous)
            (define-key map (kbd "M-TAB") #'completion-at-point)
            map))

(defun etaf-ui--text-input-submit-on-return-p (field)
  "Return non-nil when FIELD submits on Return."
  (let ((props (etaf-ui--text-input-props field))
        (rows (or (plist-get (etaf-ui--text-input-props field) :rows) 1)))
    (let ((explicit (plist-get props :submit-on-return)))
      (if (eq explicit etaf-ui--unsupplied) (= rows 1) (and explicit t)))))

(defun etaf-ui-field--active ()
  "Return the text input currently editing, from any buffer."
  (or etaf-ui--field-active etaf-ui--active-text-input))

(defun etaf-ui-field--return ()
  "Submit the active field when it submits on Return, else insert a newline."
  (interactive)
  (if (and (etaf-ui-field--active)
           (etaf-ui--text-input-submit-on-return-p (etaf-ui-field--active)))
      (etaf-ui-field--submit)
    (newline)))

(defun etaf-ui-field--submit ()
  "Submit the active field."
  (interactive)
  (etaf-text-input-end))

(defun etaf-ui-field--cancel ()
  "Cancel the active field, restoring its value at activation."
  (interactive)
  (etaf-text-input-end t))

(defun etaf-ui-field--next ()
  "Finish editing and focus the next application control."
  (interactive)
  (let ((runtime (etaf-ui--text-input-runtime (etaf-ui-field--active))))
    (etaf-text-input-end)
    (when runtime (etaf-focus-next runtime))))

(defun etaf-ui-field--previous ()
  "Finish editing and focus the previous application control."
  (interactive)
  (let ((runtime (etaf-ui--text-input-runtime (etaf-ui-field--active))))
    (etaf-text-input-end)
    (when runtime (etaf-focus-previous runtime))))

(defun etaf-ui--text-input-changed (&rest _change)
  "Publish accepted native edits to the active field's owner.
Only the buffer's own change hook calls this.  Unmount erases the buffer
before component cleanup, so ignore changes once the field's Host no longer
has a committed span; a user clearing the field keeps its published span
because publication is deferred during the session."
  (when-let* ((field etaf-ui--field-active)
              (session (etaf-ui--text-input-session field))
              (runtime (etaf-ui--text-input-runtime field))
              ((buffer-live-p (etaf-runtime-buffer runtime)))
              ((etaf-host-ref-bounds runtime
                                     (etaf-ui--text-input-text-ref field))))
    (let ((text (etaf-input-text session)))
      (unless (equal text (etaf-ui--text-input-last-text field))
        (setf (etaf-ui--text-input-last-text field) text)
        (when-let* ((callback (plist-get (etaf-ui--text-input-props field)
                                         :change-handler)))
          (funcall callback text))))))

;;;###autoload
(defun etaf-text-input-begin (runtime ref)
  "Begin native editing of the mounted text input REF in RUNTIME.
Return the input or nil when REF is unknown, disabled or already editing.
Activation normally calls this from the field's own event callback; call it
directly to focus a composer or open a grid cell for editing.  Editing another
field in the same buffer finishes the previous session first."
  (when-let* ((field (etaf-ui--text-input-find runtime ref))
              (props (etaf-ui--text-input-props field)))
    (unless (or (etaf-ui--text-input-active field) (plist-get props :disabled))
      (when etaf-ui--active-text-input (etaf-text-input-end))
      (etaf-ui--text-input-open field props))))

(defun etaf-ui--text-input-open (field props)
  "Open PROPS' native session for FIELD and return the field."
  (let* ((runtime (etaf-ui--text-input-runtime field))
         (buffer (etaf-runtime-buffer runtime))
         (value (plist-get props :value))
         (session (etaf-input-begin runtime (etaf-ui--text-input-text-ref field))))
    (setf (etaf-ui--text-input-session field) session
          (etaf-ui--text-input-snapshot field) (or value "")
          (etaf-ui--text-input-last-text field) nil
          (etaf-ui--text-input-active field) t)
    (setq etaf-ui--active-text-input field)
    (with-current-buffer buffer
      (setq etaf-ui--field-active field)
      (unless etaf-ui--field-restore
        (setq etaf-ui--field-restore
              (list :truncate-lines truncate-lines
                    :ebox-buffer-mode (and (boundp 'ebox-buffer-mode)
                                           ebox-buffer-mode))))
      (setq-local truncate-lines t)
      (when (bound-and-true-p ebox-buffer-mode) (ebox-buffer-mode -1)))
    (when-let* ((bounds (etaf-host-ref-bounds runtime (etaf-ui--text-input-text-ref field))))
      (let ((start (car bounds)) (end (cdr bounds)))
        (with-current-buffer buffer
          ;; The published text may be the placeholder; start from an empty
          ;; draft.  Clearing before the change hook runs keeps a no-op empty
          ;; value from notifying the owner.
          (when (equal (or value "") "")
            (delete-region start end)
            (setq end start))
          ;; The Host's activation keymap sits in a text property and would
          ;; otherwise shadow the field's own Return/TAB bindings.  The
          ;; session's restore brings the original properties back.
          (remove-text-properties (point-min) (point-max) '(keymap nil local-map nil))
          (goto-char (+ start (length (or value "")))))))
    (with-current-buffer buffer
      (add-hook 'after-change-functions #'etaf-ui--text-input-changed nil t)
      (etaf-ui-field-mode 1))
    (setf (etaf-ui--text-input-last-text field) (etaf-input-text session))
    field))

;;;###autoload
(defun etaf-text-input-end (&optional cancel)
  "Finish the active text input's session and return its user text.
CANCEL restores the value captured at activation through the field's change
callback; otherwise the accepted text stays the application's value.  The
field's `:on-submit' (or `:on-cancel') callback runs with the text, and the
Runtime publishes every deferred change afterwards.  Return nil when no field
is active."
  (when-let* ((field etaf-ui--active-text-input)
              (session (etaf-ui--text-input-session field)))
    (let* ((runtime (etaf-ui--text-input-runtime field))
           (buffer (etaf-runtime-buffer runtime))
           (props (etaf-ui--text-input-props field))
           (text (etaf-input-text session)))
      (setf (etaf-ui--text-input-session field) nil
            (etaf-ui--text-input-active field) nil)
      (setq etaf-ui--active-text-input nil)
      (with-current-buffer buffer
        (remove-hook 'after-change-functions #'etaf-ui--text-input-changed t)
        (etaf-ui-field-mode -1)
        (when (eq etaf-ui--field-active field) (setq etaf-ui--field-active nil))
        (when etaf-ui--field-restore
          (setq-local truncate-lines (plist-get etaf-ui--field-restore :truncate-lines))
          (when (plist-get etaf-ui--field-restore :ebox-buffer-mode)
            (ebox-buffer-mode 1))
          (setq etaf-ui--field-restore nil)))
      (etaf-input-end session)
      (if cancel
          (progn
            (when-let* ((callback (plist-get props :change-handler)))
              (funcall callback (or (etaf-ui--text-input-snapshot field) "")))
            (when-let* ((callback (plist-get props :on-cancel)))
              (funcall callback text)))
        (when-let* ((callback (plist-get props :on-submit)))
          (funcall callback text)))
      (setf (etaf-ui--text-input-last-text field) nil)
      (when (etaf-runtime-mounted-p runtime) (etaf-runtime-flush runtime))
      text)))

;;;###autoload
(defun etaf-text-input-active-p (&optional runtime)
  "Return the text input currently editing in RUNTIME, or nil.
RUNTIME defaults to the Runtime of the active field, so this query works from
any buffer."
  (when (and etaf-ui--active-text-input
             (or (null runtime)
                 (eq runtime (etaf-ui--text-input-runtime etaf-ui--active-text-input))))
    etaf-ui--active-text-input))

(etaf-define-component etaf-text-input
    (&key (value etaf-ui--unsupplied) bind (on-change etaf-ui--unsupplied)
          (label "Text") (placeholder "") (rows 1) (width 'stretch)
          disabled read-only (submit-on-return etaf-ui--unsupplied)
          on-submit on-cancel completion-functions keymap hide-label ref)
  "Edit text directly inside the application's layout.
VALUE/ON-CHANGE or a writable BIND supplies the controlled string; ROWS sets
the minimum visible lines (1 is a single-line input, more is a text area).
Activation starts a native editing session over the field's own published
text, so input methods, point, selection and undo work without a minibuffer,
frame or extra window.  Return submits when `:submit-on-return' is non-nil
(default for one row); Shift+Return and C-j insert a newline; C-c C-c and
Ctrl+Return submit; C-c C-k, Escape and C-g cancel and restore the activation
value; TAB and backtab finish and move application focus; M-TAB completes.

ON-SUBMIT and ON-CANCEL receive the session text.  PLACEHOLDER shows while the
value is empty and never becomes its content.  READ-ONLY allows focus and
copy but no session; DISABLED also removes activation.  COMPLETION-FUNCTIONS
configures CAPF during the session and KEYMAP adds field-local bindings.
The Runtime publishes changes deferred during the session and republishes the
accepted value when it ends."
  :bindings ((runtime (etaf-current-runtime))
             (field-ref (etaf-local-ref 'field))
             (text-ref (etaf-local-ref 'field-text))
             (field (etaf-ui--text-input-create
                     :runtime runtime :ref (or ref field-ref) :text-ref text-ref)))
  :validate
  (progn
    (etaf-check-prop :rows rows (and (integerp rows) (> rows 0))
                     "a positive line count" 'etaf-text-input)
    (etaf-check-prop :label label (stringp label) "a string" 'etaf-text-input)
    (etaf-check-prop :placeholder placeholder (stringp placeholder) "a string"
                     'etaf-text-input)
    (etaf-check-prop :width width
                     (or (symbolp width) (consp width)) "an Ebox length" 'etaf-text-input)
    (dolist (callback (list on-submit on-cancel))
      (etaf-check-prop :callback callback (or (null callback) (functionp callback))
                       "a function or nil" 'etaf-text-input))
    (etaf-check-prop :completion-functions completion-functions
                     (and (proper-list-p completion-functions)
                          (cl-every #'functionp completion-functions))
                     "a list of completion functions" 'etaf-text-input)
    (etaf-check-prop :keymap keymap (or (null keymap) (keymapp keymap))
                     "a keymap or nil" 'etaf-text-input))
  :setup
  (let ((sources (mapcar (lambda (name) (cons name (etaf-prop name)))
                         '(:value :bind :on-change :placeholder :rows :disabled
                           :read-only :submit-on-return :on-submit :on-cancel
                           :completion-functions :keymap))))
    (setf (etaf-ui--text-input-props-fn field)
          (lambda ()
            (let (props)
              (dolist (entry sources)
                (setq props (plist-put props (car entry) (etaf-value (cdr entry)))))
              (let* ((input (etaf-ui--controlled-input
                             'etaf-text-input :value (plist-get props :bind)
                             (plist-get props :value) (plist-get props :on-change)))
                     (text (etaf-ui--reactive-value (car input))))
                (etaf-check-prop :value text
                                 (or (null text) (stringp text))
                                 "a string or nil" 'etaf-text-input)
                (plist-put (plist-put props :value text) :change-handler (cdr input))))))
    (etaf-on-mounted
     (lambda ()
       (puthash (etaf-ui--text-input-ref field) field
                (etaf-ui--text-input-table (etaf-ui--text-input-runtime field)))))
    (etaf-on-unmounted
     (lambda ()
       (when (etaf-ui--text-input-active field) (etaf-text-input-end))
       (let* ((runtime (etaf-ui--text-input-runtime field))
              (table (gethash runtime etaf-ui--text-inputs)))
         (when table
           (remhash (etaf-ui--text-input-ref field) table)
           (when (= (hash-table-count table) 0) (remhash runtime etaf-ui--text-inputs)))))))
  :render
  (let* ((props (etaf-ui--text-input-props field))
         (current (plist-get props :value))
         (empty (or (null current) (equal current "")))
         (lines (if empty 0 (cl-count ?\n (plist-get props :value))))
         (height (max rows (1+ lines))))
    (etaf-ui--input-field
     label hide-label
     (list
      (etaf-node
       'box
       (list :ref (or ref field-ref) :role 'textbox :aria-label label
             :tab-index (unless disabled 0) :disabled disabled
             :width width :height (list 'lh height) :overflow 'hidden
             :padding '((lh 0) (ch 1))
             :background-color (etaf-ui--style-token :ui-panel-bg)
             :color (etaf-ui--style-token :ui-panel-fg)
             :on-press (unless disabled
                         (if read-only
                             (lambda () nil)
                           (lambda ()
                             (etaf-text-input-begin runtime (or ref field-ref)))))
             :class "etaf-text-input")
       (list (etaf-node
              'text
              (list :ref text-ref
                    :color (if empty
                               (etaf-ui--style-token :ui-muted-fg)
                             (etaf-ui--style-token :ui-panel-fg)))
              (list (etaf-ui--text-input-display props)))))))))

(provide 'etaf-ui-field)
;;; etaf-ui-field.el ends here
