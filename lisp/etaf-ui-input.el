;;; etaf-ui-input.el --- Controlled native inputs -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Native Emacs owns editing; Button owns activation; the caller owns the value.

;;; Code:
(require 'etaf-ui-basic)

;;;###autoload
(defun etaf-confirm-dialog (prompt)
  "Ask PROMPT from a Host callback; return non-nil only for native confirmation.
Use in an event callback before changing application data.  Emacs owns the
yes/no minibuffer; Ebox restores the entry's focus and validates its lifetime.
No returns nil; user quit and target invalidation abort the callback."
  (etaf-check-prop :prompt prompt
                   (and (stringp prompt) (not (string-empty-p prompt)))
                   "a nonempty string" 'etaf-confirm-dialog)
  (etaf-call-with-input
   (lambda ()
     (let ((use-dialog-box nil))
       (yes-or-no-p (concat prompt " "))))))

(etaf-ui--define-component etaf-menu (&key (label "Actions") items on-select disabled)
  "Choose an action from ITEMS and pass its key to ON-SELECT.
Each item has a unique scalar :key, nonempty string :label and optional
:disabled.  Disabled items cannot be selected; an empty menu is disabled."
  :render
  (let (choices keys labels)
    (etaf-check-prop :label label (stringp label) "a string" 'etaf-menu)
    (etaf-check-prop :on-select on-select
                     (or (null on-select) (functionp on-select))
                     "a function or nil" 'etaf-menu)
    (etaf-check-prop :items items (proper-list-p items)
                     "a list of menu items" 'etaf-menu)
    (dolist (item items)
      (etaf-check-prop :items item
                       (and (proper-list-p item) (zerop (% (length item) 2)))
                       "item plists with :key, :label and optional :disabled"
                       'etaf-menu)
      (let ((key (plist-get item :key)) (caption (plist-get item :label)))
        (etaf-check-prop :items item
                         (and key
                              (or (symbolp key) (numberp key) (stringp key))
                              (stringp caption) (not (string-empty-p caption))
                              (not (member key keys))
                              (not (member caption labels)))
                         "unique non-nil scalar keys and unique nonempty string labels"
                         'etaf-menu)
        (push key keys)
        (push caption labels)
        (unless (plist-get item :disabled)
          (push (cons caption key) choices))))
    (setq choices (nreverse choices))
    (etaf-node
     'etaf-button
     (list :label (concat label " ▾") :aria-label label :variant 'ghost
           :disabled (or disabled (null choices) (null on-select))
           :on-press
           (unless (or disabled (null choices) (null on-select))
             (lambda ()
               (let* ((selection
                       (etaf-call-with-input
                        (lambda ()
                          (completing-read (concat label ": ")
                                           (mapcar #'car choices) nil t))))
                      (choice (assoc selection choices)))
                 (unless choice (signal 'quit nil))
                 (funcall on-select (cdr choice))))))
     nil)))

(etaf-ui--define-component etaf-text-input
    (&key (value etaf-ui--unsupplied) (label "Text") (placeholder "—")
          (on-change etaf-ui--unsupplied) disabled bind)
  "Edit a controlled string in the native minibuffer.
Use VALUE/ON-CHANGE or writable ref BIND.  Nil VALUE displays as empty text."
  :render
  (let* ((input (etaf-ui--controlled-input 'etaf-text-input :value bind value on-change))
         (current (etaf-ui--reactive-value (car input)))
         (callback (cdr input)))
    (etaf-check-prop :value current (or (null current) (stringp current))
                     "a string or nil" 'etaf-text-input)
    (etaf-check-prop :label label (stringp label) "a string"
                     'etaf-text-input)
    (etaf-check-prop :placeholder placeholder (stringp placeholder)
                     "a string" 'etaf-text-input)
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
    (etaf-check-prop :options options (proper-list-p options)
                     "an alist of unique values and labels" 'etaf-select)
    (setq choices (copy-tree options))
    (dolist (option choices)
      (etaf-check-prop :options options
                       (and (consp option)
                            (or (symbolp (car option))
                                (numberp (car option))
                                (stringp (car option)))
                            (stringp (cdr option))
                            (not (equal (cdr option) ""))
                            (not (member (car option) values))
                            (not (member (cdr option) labels)))
                       "an alist of unique scalar values and unique nonempty string labels"
                       'etaf-select)
      (push (car option) values)
      (push (cdr option) labels))
    (etaf-check-prop :value current
                     (or (null current) (assoc current choices))
                     "nil or a value in :options" 'etaf-select)
    (etaf-check-prop :label label (stringp label) "a string" 'etaf-select)
    (etaf-check-prop :placeholder placeholder (stringp placeholder)
                     "a string" 'etaf-select)
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
Non-nil BIND cannot be combined with explicit VALUE or ON-CHANGE, even nil.
The current value is an integer or nil; LABEL is a string or nil. MIN and
MAX are numbers or nil with MIN <= MAX. Invalid inputs signal
`etaf-component-call-error' identifying the Component and property."
  :validate
  (progn
    (etaf-check-prop :label label (or (null label) (stringp label)) "a string or nil")
    (etaf-check-prop :min min (or (null min) (numberp min)) "a number or nil")
    (etaf-check-prop :max max (or (null max) (numberp max)) "a number or nil")
    (etaf-check-prop :max max (or (null min) (null max) (<= min max))
                     "nil or a bound greater than or equal to :min"))
  :render
  (let* ((input (etaf-ui--controlled-input 'etaf-number-input :value bind value on-change))
         (label (or label "Value"))
         (callback (cdr input))
         (current-value (etaf-ui--reactive-value (car input)))
         (minimum min)
         (maximum max))
    (etaf-check-prop :value current-value (or (null current-value) (integerp current-value))
                     "an integer or nil" 'etaf-number-input)
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
