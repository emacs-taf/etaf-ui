;;; -*- lexical-binding: t; -*-
;;; etaf-ui-text-grid.el --- Controlled fixed-width text rows

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Display caller-owned character surfaces with one retained boundary per row.

;;; Code:
(require 'etaf-ui-basic)

(etaf-define-component etaf-ui--text-grid-row
    (&key row columns row-text row-ref)
  :bindings ((local (etaf-local-ref 'text-row)))
  :view
  (box :width (list 'ch columns) :height '(lh 1)
       :wrap-mode 'none :overflow 'hidden
       (text :ref (if row-ref (funcall row-ref row) local)
             (expr
              (let ((content (funcall row-text row)))
                (etaf-check-prop
                 :row-text content
                 (and (stringp content)
                      (not (string-match-p "[\n\r\t]" content))
                      (<= (string-width content) columns))
                 "single-line text without tabs fitting :columns" 'etaf-text-grid)
                (concat content (make-string (- columns (string-width content)) ?\s)))))))

(etaf-define-component etaf-text-grid
    (&key rows columns row-text row-ref (label "Text grid"))
  "Display caller-owned text in fixed-width, independently retained rows."
  :validate
  (progn
    (dolist (entry (list (cons :rows rows) (cons :columns columns)))
      (etaf-check-prop (car entry) (cdr entry)
                       (and (integerp (cdr entry)) (> (cdr entry) 0))
                       "a positive integer" 'etaf-text-grid))
    (etaf-check-prop :row-text row-text (functionp row-text)
                     "a row callback" 'etaf-text-grid)
    (etaf-check-prop :row-ref row-ref (or (null row-ref) (functionp row-ref))
                     "a row callback or nil" 'etaf-text-grid)
    (etaf-check-prop :label label (stringp label) "a string" 'etaf-text-grid))
  :view
  (column :class "etaf-text-grid" :width (list 'ch columns)
          :role 'img :aria-label label
          (etaf-ui--text-grid-row :for (r (number-sequence 0 (1- rows))) :key r
                                 :row r :columns columns
                                 :row-text row-text :row-ref row-ref)))

(provide 'etaf-ui-text-grid)
;;; etaf-ui-text-grid.el ends here
