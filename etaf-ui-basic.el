;;; etaf-ui-basic.el --- Basic reusable ETAF UI Components -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Label, Button, Checkbox, and Panel are the catalog's small semantic
;; building blocks.  NumberInput is the first compound Component and composes
;; Button instead of duplicating its interaction contract.

;;; Code:

(require 'cl-lib)
(require 'etaf-ui-style)

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

(etaf-ui--define-component etaf-label (&key text variant)
  "Render TEXT as a semantic Label."
  :view
  (text
   :class (let ((presentation (etaf-ui--label-presentation variant)))
            (etaf-ui--class-value
             "etaf-label"
             (symbol-name (plist-get presentation :variant)) nil))
   :color (plist-get (etaf-ui--label-presentation variant) :color)
   :font-weight
   (plist-get (etaf-ui--label-presentation variant) :font-weight)
   (expr (etaf-ui--text-value text))))

(defun etaf-ui--button-variant-values (variant disabled)
  "Return themed presentation defaults for Button VARIANT and DISABLED."
  (let* ((fg (cond (disabled :ui-disabled-fg)
                   ((eq variant 'secondary) :ui-button-secondary-fg)
                   ((eq variant 'ghost) :ui-button-ghost-fg)
                   (t :ui-button-primary-fg)))
         (bg (cond (disabled :ui-disabled-bg)
                   ((eq variant 'secondary) :ui-button-secondary-bg)
                   ((eq variant 'ghost) :ui-button-ghost-bg)
                   (t :ui-button-primary-bg)))
         (border-key
          (cond (disabled :ui-disabled-border)
                ((eq variant 'secondary) :ui-button-secondary-border)
                ((eq variant 'ghost) :ui-button-ghost-border)
                (t :ui-button-primary-border)))
         (theme (etaf-ui--style-tokens fg bg border-key)))
    (list :color (plist-get theme fg)
          :bgcolor (plist-get theme bg)
          :border (etaf-ui--style-border (plist-get theme border-key))
          :font-weight (if (or disabled (eq variant 'ghost)) 'normal 'bold))))

(etaf-ui--define-component etaf-button
    (&key label on-press disabled ref class color bgcolor border padding
          font-weight tab-index aria-label use variant)
  "Render a standard pressable Button with a committed callback.

DISABLED removes the callback and default focus tab index.  Presentation props
remain caller-overridable.  Runtime publishes ON-PRESS with the visible Button,
so a failed render keeps the previous callback and its captured values."
  :render
  (let* ((label (etaf-ui--text-value label))
         (variant-values
          (etaf-ui--button-variant-values
           (and (not disabled) variant) disabled)))
    (etaf-node
     'box
     (list
      :class (etaf-ui--class-value
              "etaf-button"
              (if disabled "disabled" "enabled")
              class)
      :ref ref :role 'button :disabled disabled
      :tab-index (unless disabled (or tab-index 0))
      :aria-label (or aria-label label)
      :color (or color (plist-get variant-values :color))
      :background-color (or bgcolor (plist-get variant-values :bgcolor))
      :border (or border (plist-get variant-values :border))
      :padding padding
      :font-weight (or font-weight (plist-get variant-values :font-weight))
      :use use
      :on-press (and (not disabled) on-press))
     (list (etaf-node 'text nil (list label)))))
  :styles
  (styles
   ("&" :width max-content)
   ("&.disabled" :padding ((lh 0) (ch 1)) :font-weight normal)
   ("&.enabled" :padding ((lh 0) (ch 1)) :font-weight bold)))

(defun etaf-ui--checkbox-variant-values (disabled)
  "Return semantic Theme presentation for a DISABLED Checkbox."
  (let* ((prefix (if disabled "disabled" "enabled"))
         (fg (intern (format ":ui-checkbox-%s-fg" prefix)))
         (bg (intern (format ":ui-checkbox-%s-bg" prefix)))
         (border-key (intern (format ":ui-checkbox-%s-border" prefix)))
         (theme (etaf-ui--style-tokens fg bg border-key)))
    (list :color (plist-get theme fg)
          :bgcolor (plist-get theme bg)
          :border (etaf-ui--style-border (plist-get theme border-key)))))

(etaf-ui--define-component etaf-checkbox
    (&key checked label on-change disabled)
  "Render a controlled Checkbox whose next value is sent to ON-CHANGE."
  :view
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
    (text (expr (if (etaf-ui--reactive-value checked) "☑" "☐"))))
   (text (expr
          (let ((value (etaf-ui--text-value label)))
            (if (string-empty-p value) "" (concat " " value))))))
  :styles
  (styles
   ("&" :width max-content)
   ("&.disabled" :padding ((lh 0) (ch 1)))
   ("&.enabled" :padding ((lh 0) (ch 1)))
   (".etaf-checkbox-mark" :font-weight bold :width (ch 1))))

(etaf-ui--define-component etaf-panel (&key title variant)
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
             (etaf-ui--style-border (plist-get theme :ui-panel-border))))
     (append
      (when title
        (list (etaf-node
               'etaf-label
               (list :class "etaf-panel-title" :text title :variant 'strong)
               nil)))
      (etaf-current-slot 'header)
      (etaf-current-slot 'default))))
  :styles
  (styles
   ("&" :padding ((lh 1) (ch 2)))
   (".etaf-panel-title" :font-weight bold)))

(etaf-ui--define-component etaf-number-input
    (&key value label on-change disabled min max)
  "Render a controlled minibuffer-backed NumberInput using Button."
  :render
  (let ((label (or label "Value"))
        (callback on-change)
        (current-value value)
        (minimum min)
        (maximum max))
    (etaf-node
     'etaf-button
     (list
      :label (format "%s %s ✎" label (or current-value "—"))
      :disabled disabled :variant 'ghost
      :on-press
      (unless disabled
        (lambda ()
          (let ((next (read-number
                       (format "%s: " label) (or current-value 0))))
            (unless (and (integerp next)
                         (or (null minimum) (>= next minimum))
                         (or (null maximum) (<= next maximum)))
              (user-error "%s must be an integer from %s to %s"
                          label (or minimum "—") (or maximum "—")))
            (when callback (funcall callback next))))))
     nil)))

(provide 'etaf-ui-basic)
;;; etaf-ui-basic.el ends here
