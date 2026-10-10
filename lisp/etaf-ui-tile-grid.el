;;; etaf-ui-tile-grid.el --- Controlled rectangular tile grid -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Coordinate callbacks project caller-owned data into independently retained
;; cells.  This component owns layout and activation, not board state or timers.

;;; Code:
(require 'etaf-ui-basic)

(etaf-define-component etaf-ui--tile
    (&key row column cell-width cell-background cell-text cell-ref on-cell-press)
  :bindings ((local (etaf-local-ref 'tile)))
  :view
  (box :class "etaf-tile-grid-cell"
       :ref (if cell-ref (funcall cell-ref row column) local)
       :width (list 'ch cell-width) :height '(lh 1)
       :wrap-mode 'none :overflow 'hidden :text-align 'center
       :background-color (when cell-background (funcall cell-background row column))
       :role (if on-cell-press 'button 'cell)
       :aria-label (format "Cell %d,%d" row column)
       :help-echo (format "Cell %d,%d" row column)
       :tab-index (when on-cell-press 0)
       :on-press (when on-cell-press
                   (lambda () (funcall on-cell-press row column)))
       (text (expr (let ((label (if cell-text (funcall cell-text row column) " ")))
                     (etaf-check-prop :cell-text label
                                      (and (stringp label)
                                           (not (string-match-p "[\n\r]" label))
                                           (<= (string-width label) cell-width))
                                      "single-line text fitting :cell-width"
                                      'etaf-tile-grid)
                     label))))
  :styles (("&:focus" :text-decoration-line underline)))

(etaf-define-component etaf-tile-grid
    (&key rows columns (cell-width 2) cell-background cell-text cell-ref on-cell-press)
  "Render a fixed rectangular grid through zero-based coordinate callbacks."
  :validate
  (progn
    (dolist (entry (list (cons :rows rows) (cons :columns columns)
                        (cons :cell-width cell-width)))
      (etaf-check-prop (car entry) (cdr entry)
                       (and (integerp (cdr entry)) (> (cdr entry) 0))
                       "a positive integer" 'etaf-tile-grid))
    (dolist (entry (list (cons :cell-background cell-background)
                        (cons :cell-text cell-text) (cons :cell-ref cell-ref)
                        (cons :on-cell-press on-cell-press)))
      (etaf-check-prop (car entry) (cdr entry)
                       (or (null (cdr entry)) (functionp (cdr entry)))
                       "a coordinate callback or nil" 'etaf-tile-grid)))
  :view
  (column :class "etaf-tile-grid" :role 'grid :focus-group 'grid
          :width (list 'ch (* columns cell-width))
          (row :for (r (number-sequence 0 (1- rows))) :key r :role 'row
               (etaf-ui--tile :for (c (number-sequence 0 (1- columns))) :key c
                             :row r :column c :cell-width cell-width
                             :cell-background cell-background :cell-text cell-text
                             :cell-ref cell-ref :on-cell-press on-cell-press))))

(provide 'etaf-ui-tile-grid)
;;; etaf-ui-tile-grid.el ends here
