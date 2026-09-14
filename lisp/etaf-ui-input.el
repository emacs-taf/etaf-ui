;;; etaf-ui-input.el --- Controlled native inputs -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Native Emacs owns editing; Button owns activation; the caller owns the value.

;;; Code:
(require 'etaf-ui-basic)

(defun etaf-ui--input-check (component prop value valid expected)
  "Report COMPONENT PROP VALUE when VALID is nil, describing EXPECTED input."
  (unless valid
    (signal 'etaf-view-error
            (list (format "Component %S property %S received %S; expected %s"
                          component prop value expected)))))

(etaf-ui--define-component etaf-text-input
    (&key (value etaf-ui--unsupplied) (label "Text") (placeholder "—")
          (on-change etaf-ui--unsupplied) disabled bind)
  "Edit a controlled string in the native minibuffer.
Use VALUE/ON-CHANGE or writable ref BIND.  Nil VALUE displays as empty text."
  :render
  (let* ((input (etaf-ui--controlled-input 'etaf-text-input :value bind value on-change))
         (current (etaf-ui--reactive-value (car input)))
         (callback (cdr input)))
    (etaf-ui--input-check 'etaf-text-input :value current
                          (or (null current) (stringp current)) "a string or nil")
    (etaf-ui--input-check 'etaf-text-input :label label (stringp label) "a string")
    (etaf-ui--input-check 'etaf-text-input :placeholder placeholder (stringp placeholder) "a string")
    (etaf-node
     'etaf-button
     (list :label (format "%s %s ✎" label (if (or (null current) (equal current "")) placeholder current))
           :aria-label label :disabled disabled :variant 'ghost
           :on-press
           (unless disabled
             (lambda ()
               (let ((next (etaf-call-with-input
                            (lambda () (read-string (concat label ": ") (or current ""))))))
                 (when callback (funcall callback next))))))
     nil)))

(etaf-ui--define-component etaf-select
    (&key (value etaf-ui--unsupplied) options (label "Select") (placeholder "—")
          (on-change etaf-ui--unsupplied) disabled bind)
  "Choose a controlled VALUE from an alist of (VALUE . LABEL) OPTIONS.
Values and nonempty string labels must be unique.  Use VALUE/ON-CHANGE or BIND."
  :render
  (let* ((input (etaf-ui--controlled-input 'etaf-select :value bind value on-change))
         (current (etaf-ui--reactive-value (car input)))
         (callback (cdr input))
         choices
         values labels)
    (etaf-ui--input-check 'etaf-select :options options (proper-list-p options) "an alist of unique values and labels")
    (setq choices (copy-tree options))
    (dolist (option choices)
      (etaf-ui--input-check
       'etaf-select :options options
       (and (consp option) (or (symbolp (car option)) (numberp (car option)) (stringp (car option)))
            (stringp (cdr option)) (not (equal (cdr option) ""))
            (not (member (car option) values)) (not (member (cdr option) labels)))
       "an alist of unique scalar values and unique nonempty string labels")
      (push (car option) values)
      (push (cdr option) labels))
    (etaf-ui--input-check 'etaf-select :value current
                          (or (null current) (assoc current choices)) "nil or a value in :options")
    (etaf-ui--input-check 'etaf-select :label label (stringp label) "a string")
    (etaf-ui--input-check 'etaf-select :placeholder placeholder (stringp placeholder) "a string")
    (let ((caption (cdr (assoc current choices))))
      (etaf-node
       'etaf-button
       (list :label (format "%s %s ▾" label (or caption placeholder))
             :aria-label label :disabled (or disabled (null choices)) :variant 'ghost
             :on-press
             (unless (or disabled (null choices))
               (lambda ()
                 (let* ((selected (etaf-call-with-input
                                   (lambda ()
                                     (completing-read (concat label ": ")
                                                      (mapcar #'cdr choices) nil t nil nil caption))))
                        (option (rassoc selected choices)))
                   (unless option (user-error "%s: select an available option" label))
                   (when callback (funcall callback (car option)))))))
       nil))))

(etaf-ui--define-component etaf-number-input
    (&key (value etaf-ui--unsupplied) label
          (on-change etaf-ui--unsupplied) disabled min max bind)
  "Render a minibuffer NumberInput using VALUE/ON-CHANGE or writable ref BIND.
Non-nil BIND cannot be combined with explicit VALUE or ON-CHANGE, even nil."
  :render
  (let* ((input (etaf-ui--controlled-input 'etaf-number-input :value bind value on-change))
         (label (or label "Value"))
         (callback (cdr input))
         (current-value (etaf-ui--reactive-value (car input)))
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
          (let ((next (etaf-call-with-input
                       (lambda () (read-number (format "%s: " label) (or current-value 0))))))
            (unless (and (integerp next)
                         (or (null minimum) (>= next minimum))
                         (or (null maximum) (<= next maximum)))
              (user-error "%s must be an integer from %s to %s"
                          label (or minimum "—") (or maximum "—")))
            (when callback (funcall callback next))))))
     nil)))

(provide 'etaf-ui-input)
;;; etaf-ui-input.el ends here
