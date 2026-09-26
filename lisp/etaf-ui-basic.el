;;; etaf-ui-basic.el --- Basic reusable ETAF UI Components -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Label, Button, Checkbox, and Panel are the catalog's small semantic
;; building blocks. Compound inputs compose Button through the same contract.

;;; Code:

(require 'cl-lib)
(require 'etaf-ui-style)

(defvar etaf-ui--unsupplied (make-symbol "unsupplied")
  "Distinguish omitted controlled props from explicitly supplied nil.")

(defun etaf-ui--controlled-input (component value-prop bind value on-change)
  "Resolve COMPONENT's BIND or explicit VALUE-PROP and ON-CHANGE.
Return the value source and callback as a cons.  A binding uses the caller's
ref directly; it owns no state or subscription of its own."
  (cl-labels ((invalid (prop received expected)
               (etaf-check-prop prop received nil expected component)))
    (if bind
        (progn
          (unless (etaf-ref-p bind)
            (invalid :bind bind "a writable ETAF ref"))
          (unless (eq value etaf-ui--unsupplied)
            (invalid value-prop value "omission when :bind is supplied"))
          (unless (eq on-change etaf-ui--unsupplied)
            (invalid :on-change on-change "omission when :bind is supplied"))
          (cons bind (lambda (next) (setf (etaf-value bind) next))))
      (unless (or (eq on-change etaf-ui--unsupplied)
                  (null on-change) (functionp on-change))
        (invalid :on-change on-change "a function or nil"))
      (cons (unless (eq value etaf-ui--unsupplied) value)
            (unless (eq on-change etaf-ui--unsupplied) on-change)))))

(defun etaf-ui--class-value (base state custom)
  "Return BASE and STATE classes with optional CUSTOM classes."
  (let ((custom (cond ((null custom) nil)
                      ((listp custom) custom)
                      (t (list custom)))))
    (mapconcat
     (lambda (class) (format "%s" class))
     (cl-remove-if
      (lambda (class) (or (null class) (equal class "")))
      (append (list base state) custom))
     " ")))

(defun etaf-ui--reactive-value (value)
  "Return VALUE, reading it when it is an ETAF reactive source."
  (if (or (etaf-ref-p value) (etaf-computed-p value))
      (etaf-value value)
    value))

(defun etaf-ui--text-value (value)
  "Return VALUE as a Text payload without discarding string properties."
  (setq value (etaf-ui--reactive-value value))
  (cond ((null value) "")
        ((stringp value) value)
        (t (format "%s" value))))

(defun etaf-ui--label-presentation (variant)
  "Return semantic presentation for Label VARIANT."
  (let* ((variant (or variant 'default))
         (color-key
          (pcase variant
            ('muted :ui-muted-fg)
            ('danger :ui-danger-fg)
            ('success :ui-success-fg)
            (_ :ui-fg)))
         (theme (etaf-ui--style-tokens color-key)))
    (list :variant variant
          :color (plist-get theme color-key)
          :font-weight (when (memq variant '(strong heading)) 'bold))))

(etaf-define-component etaf-label (&key text variant)
  "Render TEXT in a semantic Label with ordinary Box layout."
  :view
  (box
   :class (let ((presentation (etaf-ui--label-presentation variant)))
            (etaf-ui--class-value
             "etaf-label"
             (symbol-name (plist-get presentation :variant)) nil))
   :color (plist-get (etaf-ui--label-presentation variant) :color)
   :font-weight
   (plist-get (etaf-ui--label-presentation variant) :font-weight)
   (text (expr (etaf-ui--text-value text)))))

(defun etaf-ui--button-variant-values (variant disabled)
  "Return themed presentation defaults for Button VARIANT and DISABLED.

Buttons are filled single-row pills: `primary' paints the accent, `secondary'
its soft tint and `ghost' inherits its surface.  Outlines
are omitted because a one-row control cannot pad above or below its text, so
a stroke around it always touches the glyphs.  A disabled button keeps its
variant's footprint so toggling availability never shifts its neighbours:
filled variants dim to the disabled surface, a ghost only dims its text."
  (let* ((variant (or variant 'primary))
         (fg (cond (disabled :ui-disabled-fg)
                   ((eq variant 'secondary) :ui-button-secondary-fg)
                   ((eq variant 'ghost) :ui-button-ghost-fg)
                   (t :ui-button-primary-fg)))
         (bg (cond ((eq variant 'ghost) nil)
                   (disabled :ui-disabled-bg)
                   ((eq variant 'secondary) :ui-button-secondary-bg)
                   (t :ui-button-primary-bg)))
         (theme (etaf-ui--style-tokens fg (or bg :ui-disabled-bg))))
    (list :color (plist-get theme fg)
          :bgcolor (and bg (plist-get theme bg))
          :border nil
          :padding (if (memq variant '(primary secondary))
                       '((lh 0) (ch 2))
                     '((lh 0) (ch 1)))
          :font-weight (if (or disabled (eq variant 'ghost)) 'normal 'bold))))

(etaf-define-component etaf-button
    (&key label on-press disabled id ref class color bgcolor border padding
          font-size font-weight tab-index aria-label help-echo hover-content
          pointer hover-group use variant)
  "Render a standard pressable Button with a committed callback.

DISABLED removes the callback and default focus tab index.  Presentation props
remain caller-overridable.  ID reaches the rendered Host so anchor-based
surfaces can reference the Button by identity.  Runtime publishes ON-PRESS with
the visible Button, so a failed render keeps the previous callback and its
captured values."
  :render
  (let* ((label (etaf-ui--text-value label))
         (variant-values (etaf-ui--button-variant-values variant disabled)))
    (etaf-node
     'box
     (append
      (list
       :class (etaf-ui--class-value
               "etaf-button"
               (if disabled "disabled" "enabled")
               (cons (symbol-name (or variant 'primary))
                     (cond ((null class) nil)
                           ((listp class) class)
                           (t (list class)))))
       :ref ref :role 'button :disabled disabled
       :tab-index (unless disabled (or tab-index 0))
       :aria-label (or aria-label label)
       :help-echo help-echo
       :pointer (or pointer (and (not disabled) 'arrow))
       :color (or color (plist-get variant-values :color))
       :background-color (or bgcolor (plist-get variant-values :bgcolor))
       :border (or border (plist-get variant-values :border))
       :padding (or padding (plist-get variant-values :padding))
       :font-size font-size
       :font-weight (or font-weight (plist-get variant-values :font-weight))
       :use use
       :on-press (and (not disabled) on-press))
      (append
       (when id (list :id id))
       (when hover-content (list :hover-content hover-content))
       (when hover-group (list :hover-group hover-group))))
     (or (etaf-current-slot 'default)
         (list (etaf-node 'text nil (list label))))))
  :styles
  (("&" :width max-content)
   ("&.disabled" :font-weight normal)))

(defun etaf-ui--checkbox-variant-values (disabled)
  "Return semantic Theme presentation for a DISABLED Checkbox.
The row inherits its surface; only the mark carries the accent, so a
checkbox reads as a labelled control rather than a boxed field."
  (let* ((prefix (if disabled "disabled" "enabled"))
         (fg (intern (format ":ui-checkbox-%s-fg" prefix)))
         (mark (if disabled :ui-disabled-fg :ui-accent))
         (theme (etaf-ui--style-tokens fg mark)))
    (list :color (plist-get theme fg)
          :mark-color (plist-get theme mark)
          :bgcolor nil
          :border nil)))

(etaf-define-component etaf-checkbox
    (&key (checked etaf-ui--unsupplied) label
          (on-change etaf-ui--unsupplied) disabled bind)
  "Render a controlled Checkbox using CHECKED/ON-CHANGE or writable ref BIND.
Non-nil BIND cannot be combined with explicit CHECKED or ON-CHANGE, even nil."
  :render
  (let* ((input (etaf-ui--controlled-input 'etaf-checkbox :checked bind checked on-change))
         (checked (car input))
         (on-change (cdr input)))
    (etaf-view
     (row
      :class (etaf-ui--class-value
              "etaf-checkbox" (if disabled "disabled" "enabled") nil)
      :role 'checkbox :disabled disabled
      :aria-label (etaf-ui--text-value label)
      :tab-index (unless disabled 0)
      :color (plist-get (etaf-ui--checkbox-variant-values disabled) :color)
      :background-color
      (plist-get (etaf-ui--checkbox-variant-values disabled) :bgcolor)
      :border (plist-get (etaf-ui--checkbox-variant-values disabled) :border)
      :on-press
      (and (not disabled) on-change
           (let ((callback on-change)
                 (source checked))
             (lambda ()
               (funcall callback (not (etaf-ui--reactive-value source))))))
      (box :class "etaf-checkbox-mark"
           :color (plist-get (etaf-ui--checkbox-variant-values disabled) :mark-color)
           (text (expr (if (etaf-ui--reactive-value checked) "☑" "☐"))))
      (text (expr
             (let ((value (etaf-ui--text-value label)))
               (if (string-empty-p value) "" (concat " " value))))))))
  :styles
  (("&" :width max-content)
   ("&.disabled" :padding ((lh 0) (ch 0)))
   ("&.enabled" :padding ((lh 0) (ch 0)))
   (".etaf-checkbox-mark" :font-weight bold :width (ch 1))))

(etaf-define-component etaf-panel (&key title variant)
  "Render a titled Panel with named header and default slots."
  :render
  (let ((theme (etaf-ui--style-tokens
                :ui-panel-fg :ui-panel-bg :ui-panel-border)))
    (etaf-node
     'column
     (list :class (etaf-ui--class-value
                   "etaf-panel" (symbol-name (or variant 'default)) nil)
           :color (plist-get theme :ui-panel-fg)
           :background-color
           (unless (eq variant 'flat) (plist-get theme :ui-panel-bg))
           :border
           (unless (eq variant 'flat)
             (etaf-ui--style-border (plist-get theme :ui-panel-border)))
           :item-gap '(lh 1))
     (append
      (when title
        (list (etaf-node
               'etaf-label
               (list :class "etaf-panel-title" :text title :variant 'strong)
               nil)))
      (etaf-current-slot 'header)
      (etaf-current-slot 'default))))
  :styles
  (("&" :padding ((lh 1) (ch 2)))
   (".etaf-panel-title" :font-weight bold)))

(provide 'etaf-ui-basic)
;;; etaf-ui-basic.el ends here
