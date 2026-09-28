;;; etaf-ui-selection.el --- Selection and value controls -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Selection controls are controlled Components.  They compose Button and
;; preserve the same VALUE/ON-CHANGE or writable REF contract as Checkbox.

;;; Code:

(require 'cl-lib)
(require 'etaf-ui-basic)

(defun etaf-ui--selection-options (options component)
  "Validate alist OPTIONS for COMPONENT and return it unchanged."
  (etaf-check-prop :options options (and (proper-list-p options) options)
                   "a nonempty alist of scalar values and labels" component)
  (let (values labels)
    (dolist (option options)
      (etaf-check-prop :options option
                       (and (consp option)
                            (or (symbolp (car option))
                                (numberp (car option))
                                (stringp (car option)))
                            (stringp (cdr option))
                            (not (string-empty-p (cdr option)))
                            (not (member (car option) values))
                            (not (member (cdr option) labels)))
                       "an alist with unique scalar values and labels" component)
      (push (car option) values)
      (push (cdr option) labels)))
  options)

(defun etaf-ui--selection-colors (selected disabled)
  "Return (FG BG BORDER) for SELECTED and DISABLED selection controls.
Selection controls are tonal pills like Buttons: a selected control paints
the secondary button tint, an unselected one inherits its surface, and no
control carries an outline.  The secondary tokens are dialog tokens, so a
selected control stays crisp inside a modal above a dimmed shell."
  (let* ((fg (cond (disabled :ui-disabled-fg)
                   (selected :ui-button-secondary-fg)
                   (t :ui-fg)))
         (bg (cond (disabled :ui-disabled-bg)
                   (selected :ui-button-secondary-bg)))
         (theme (etaf-ui--style-tokens fg (or bg :ui-disabled-bg))))
    (list (plist-get theme fg) (and bg (plist-get theme bg)) nil)))

(etaf-define-component etaf-radio
    (&key (value etaf-ui--unsupplied) options (label "Choice")
          (on-change etaf-ui--unsupplied) disabled bind)
  "Render a controlled single-choice RADIO group.
OPTIONS is an alist of unique scalar values and labels.  VALUE/ON-CHANGE or
the writable BIND ref owns the selected value; the Component owns no state."
  :render
  (let* ((input (etaf-ui--controlled-input 'etaf-radio :value bind value on-change))
         (current (etaf-ui--reactive-value (car input)))
         (callback (cdr input)))
    (etaf-ui--selection-options options 'etaf-radio)
    (etaf-check-prop :label label (stringp label) "a string" 'etaf-radio)
    (etaf-check-prop :value current
                     (or (null current) (assoc current options))
                     "nil or a value in :options" 'etaf-radio)
    (etaf-view
     (column :class "etaf-radio-group" :role 'radiogroup :width 'stretch
       (etaf-label :text label :variant 'strong)
       (row :item-gap '(ch 1)
         (expr
          (mapcar
           (lambda (option)
             (let* ((key (car option))
                    (caption (cdr option))
                    (selected (equal key current))
                    (colors (etaf-ui--selection-colors selected disabled)))
               (etaf-view
                (etaf-button
                 :label (concat (if selected "(o) " "( ) ") caption)
                 :aria-label caption :variant 'ghost :disabled disabled
                 :color (nth 0 colors) :bgcolor (nth 1 colors)
                 :border (nth 2 colors)
                 :on-press (and (not disabled) callback
                                (lambda () (funcall callback key)))))))
           options)))))))

(etaf-define-component etaf-switch
    (&key (checked etaf-ui--unsupplied) (label "Switch")
          (on-change etaf-ui--unsupplied) disabled bind)
  "Render a controlled binary SWITCH using CHECKED/ON-CHANGE or BIND."
  :render
  (let* ((input (etaf-ui--controlled-input 'etaf-switch :checked bind checked on-change))
         (current (etaf-ui--reactive-value (car input)))
         (callback (cdr input))
         (colors (etaf-ui--selection-colors current disabled)))
    (etaf-check-prop :checked current (booleanp current) "a boolean" 'etaf-switch)
    (etaf-check-prop :label label (stringp label) "a string" 'etaf-switch)
    (etaf-view
     (etaf-button
      :label (format "%s %s" (if current "[x]" "[ ]") label)
      :aria-label label :variant 'ghost :disabled disabled
      :color (nth 0 colors) :bgcolor (nth 1 colors) :border (nth 2 colors)
      :on-press (and (not disabled) callback
                     (lambda () (funcall callback (not current))))))))

(etaf-define-component etaf-segmented
    (&key (value etaf-ui--unsupplied) options (on-change etaf-ui--unsupplied)
          disabled bind)
  "Render a compact controlled SEGMENTED selector from OPTIONS."
  :render
  (let* ((input (etaf-ui--controlled-input 'etaf-segmented :value bind value on-change))
         (current (etaf-ui--reactive-value (car input)))
         (callback (cdr input)))
    (etaf-ui--selection-options options 'etaf-segmented)
    (etaf-check-prop :value current
                     (or (null current) (assoc current options))
                     "nil or a value in :options" 'etaf-segmented)
    (etaf-view
     (row :class "etaf-segmented" :role 'tablist :item-gap '(ch 2)
       (expr
        (mapcar
         (lambda (option)
           (let* ((key (car option)) (caption (cdr option))
                  (selected (equal key current)))
             (etaf-view
              (etaf-button :label (if selected (concat "* " caption) caption)
                           :aria-label caption
                           :variant (if selected 'secondary 'ghost)
                           :disabled disabled
                           :on-press (and (not disabled) callback
                                          (lambda () (funcall callback key)))))))
         options))))))

(etaf-define-component etaf-slider
    (&key (value etaf-ui--unsupplied) (min 0) (max 100) (step 1)
          (label "Value") (on-change etaf-ui--unsupplied) disabled bind)
  "Render a controlled numeric SLIDER using the native number prompt.
VALUE must be an integer in MIN..MAX; STEP is a positive integer.  The
native prompt keeps editing accessible while the Component remains reusable."
  :validate
  (progn
    (etaf-check-prop :min min (integerp min) "an integer" 'etaf-slider)
    (etaf-check-prop :max max (and (integerp max) (<= min max))
                     "an integer greater than or equal to :min" 'etaf-slider)
    (etaf-check-prop :step step (and (integerp step) (> step 0))
                     "a positive integer" 'etaf-slider)
    (etaf-check-prop :label label (stringp label) "a string" 'etaf-slider))
  :render
  (let* ((input (etaf-ui--controlled-input 'etaf-slider :value bind value on-change))
         (current (etaf-ui--reactive-value (car input)))
         (callback (cdr input)))
    (etaf-check-prop :value current
                     (and (integerp current) (<= min current max)
                          (zerop (% (- current min) step)))
                     "an integer aligned to :step within :min..:max" 'etaf-slider)
    (etaf-view
     (column :class "etaf-slider" :width 'stretch
       (row :item-gap '(ch 1)
         (etaf-label :text label :variant 'strong)
         (etaf-label :text (format "%d" current) :variant 'muted))
       (etaf-button :label (format "◀  %d  ▶" current) :variant 'secondary
                    :disabled disabled :aria-label label
                    :on-press
                    (and (not disabled) callback
                         (lambda ()
                           (let ((next (etaf-call-with-input
                                        (lambda ()
                                          (read-number (format "%s (%d-%d): " label min max)
                                                       current)))))
                             (unless (and (integerp next) (<= min next max)
                                          (zerop (% (- next min) step)))
                               (user-error "%s must be aligned to %d from %d to %d"
                                           label step min max))
                             (funcall callback next)))))))))

(provide 'etaf-ui-selection)
;;; etaf-ui-selection.el ends here
