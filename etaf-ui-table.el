;;; etaf-ui-table.el --- Presentational Table Component for ETAF UI -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Table renders ordinary rows and columns.  It owns no loading, database,
;; pagination, or selection state; callers provide optional controlled row
;; interaction.  DataGrid adapts ETAF Data onto this Component.

;;; Code:

(require 'cl-lib)
(require 'etaf-ui-basic)

(defun etaf-ui--column-value (column key)
  "Return KEY from COLUMN, accepting a plist or alist descriptor."
  (if (and (listp column) (keywordp (car column)))
      (plist-get column key)
    (alist-get key column)))

(defun etaf-ui--table-validate-columns (columns)
  "Return COLUMNS after checking stable identities and optional cell functions."
  (unless (proper-list-p columns)
    (error "ETAF Table :columns must be a proper list"))
  (let ((seen (make-hash-table :test #'equal)))
    (cl-loop for column in columns for index from 1 do
             (let ((key (etaf-ui--column-value column :key))
                   (cell (etaf-ui--column-value column :cell))
                   (width (etaf-ui--column-value column :width)))
               (unless (and key (or (symbolp key) (stringp key) (integerp key)))
                 (error "ETAF Table column %d :key must be a non-nil symbol, integer, or string; got %S"
                        index key))
               (when (gethash key seen)
                 (error "ETAF Table column %d duplicates :key %S; use a unique key and :cell to repeat a field"
                        index key))
               (puthash key t seen)
               (when (and cell (not (functionp cell)))
                 (error "ETAF Table column %d (%S) :cell must be a function of one row; got %S"
                        index key cell))
               (when (and (consp width) (eq (car width) 'fr)
                          (not (and (proper-list-p width) (= (length width) 2)
                                    (numberp (cadr width)) (> (cadr width) 0))))
                 (error "ETAF Table column %d (%S) :width must use (fr POSITIVE-WEIGHT); got %S"
                        index key width)))))
  columns)

(defun etaf-ui--table-cell-value (row key)
  "Return KEY from ROW, accepting a plist, alist, or hash table."
  (cond
   ((hash-table-p row) (gethash key row))
   ((and (proper-list-p row)
         (zerop (% (length row) 2))
         (keywordp (car row)))
    (plist-get row key))
   ((listp row) (alist-get key row nil nil #'equal))
   (t nil)))

(defun etaf-ui--table-fit-text (value column)
  "Return VALUE fitted to COLUMN's declared character capacity."
  (let* ((value (format "%s" (or value "")))
         (width (etaf-ui--column-value column :width)))
    (if (and (integerp width) (> width 0)
             (> (string-width value) width))
        (truncate-string-to-width value width 0 nil "…")
      value)))

(defun etaf-ui--table-fixed-text-columns-p (columns)
  "Return non-nil when COLUMNS can share the compact fixed-text path."
  (and columns
       (cl-every
        (lambda (column)
          (let ((width (etaf-ui--column-value column :width)))
            (and (not (etaf-ui--column-value column :cell))
                 (integerp width) (> width 0))))
        columns)))

(defun etaf-ui--table-grid (columns cells)
  "Allocate CELLS with shared COLUMNS tracks and one character between them."
  (etaf-node
   'grid
   (list :width 'stretch
         :grid-template-columns
         (mapcar (lambda (column)
                   (or (etaf-ui--column-value column :width) 'max-content))
                 columns)
         :column-gap 1)
   cells))

(defun etaf-ui--table-header-cell (column)
  "Return one header for COLUMN inside its allocated Grid track."
  (etaf-node
   'box
   (list :class "etaf-table-header-cell"
         :width 'stretch :overflow 'hidden
         :wrap-mode 'none)
   (list
    (etaf-node
     'text nil
     (list
      (etaf-ui--table-fit-text
       (or (etaf-ui--column-value column :label)
           (etaf-ui--column-value column :key))
       column))))))

(defun etaf-ui--table-fixed-header-text (columns)
  "Return one fixed-width header string for COLUMNS, or nil."
  (when (etaf-ui--table-fixed-text-columns-p columns)
    (mapconcat
     (lambda (column)
       (let* ((width (etaf-ui--column-value column :width))
              (value
               (etaf-ui--table-fit-text
                (or (etaf-ui--column-value column :label)
                    (etaf-ui--column-value column :key))
                column)))
         (concat value
                 (make-string (max 0 (- width (string-width value))) ?\s))))
     columns " ")))

(defun etaf-ui--table-header (columns)
  "Return a Table header row for COLUMNS."
  (etaf-ui--table-validate-columns columns)
  (let ((theme (etaf-ui--style-tokens :ui-table-border))
        (fixed-text (etaf-ui--table-fixed-header-text columns)))
    (etaf-node
     'row
     (append
      (unless fixed-text '(:padding (0 0)))
      (list :class "etaf-table-header"
            :border-bottom-width 1 :border-bottom-style 'solid
            :border-bottom-color (plist-get theme :ui-table-border)))
     (if fixed-text
         (list (etaf-node 'text nil (list fixed-text)))
       (list (etaf-ui--table-grid
              columns (mapcar #'etaf-ui--table-header-cell columns)))))))

(defun etaf-ui--table-cell (row column)
  "Return COLUMN's ordinary View cell for ROW inside its allocated track.
Custom cell functions run at this consuming position; Component output owns
its usual Context, styles, state, and lifecycle."
  (etaf-node
   'box
   (list :key (etaf-ui--column-value column :key)
         :class "etaf-table-cell"
         :width 'stretch
         :overflow 'hidden
         :wrap-mode 'none)
   (list
    (if-let* ((cell (etaf-ui--column-value column :cell)))
        (etaf-view (expr (funcall cell row)))
      (etaf-node
       'text nil
       (list
        (etaf-ui--table-fit-text
         (etaf-ui--table-cell-value
          row (etaf-ui--column-value column :key))
         column)))))))

(defun etaf-ui--table-cells (row columns)
  "Return cell Components for ROW using COLUMNS."
  (cl-loop for column in columns
           collect
           (etaf-ui--table-cell row column)))

(defun etaf-ui--table-fixed-row-text (row columns)
  "Return one fixed-width ROW string for COLUMNS, or nil when not applicable."
  (when (etaf-ui--table-fixed-text-columns-p columns)
    (mapconcat
     (lambda (column)
       (let* ((width (etaf-ui--column-value column :width))
              (value
               (etaf-ui--table-fit-text
                (etaf-ui--table-cell-value
                 row (etaf-ui--column-value column :key))
                column)))
         (concat value
                 (make-string (max 0 (- width (string-width value))) ?\s))))
     columns " ")))

(defun etaf-ui--table-row-children (row columns)
  "Return the smallest presentation-equivalent child list for ROW.
COLUMNS with fixed positive character widths use one padded Text Host.
Other cells always share a Grid parent, preserving their identity when column
widths change between fixed and fractional tracks."
  (if-let* ((text (etaf-ui--table-fixed-row-text row columns)))
      (list (etaf-node 'text nil (list text)))
    (list (etaf-ui--table-grid columns (etaf-ui--table-cells row columns)))))

(defun etaf-ui--table-entries (rows row-key)
  "Return `(KEY . ROW)' entries for ROWS using ROW-KEY.
ETAF validates keys and uniqueness."
  (unless (functionp row-key)
    (error "ETAF Table requires a function-valued :row-key"))
  (mapcar (lambda (row) (cons (funcall row-key row) row)) rows))

(defun etaf-ui--table-row-node
    (row identity columns row-ref on-row-press row-selected-p)
  "Return one canonical row Host for ROW and stable IDENTITY.

The retained Table row shares its cell construction with DataGrid's keyed
hot path.  COLUMNS define the visible cells;
ROW-REF, ON-ROW-PRESS, and ROW-SELECTED-P define optional interaction.
Without ROW-REF the Host receives ETAF's usual instance-local reference."
  (let* ((callback on-row-press)
         (row-value row)
         (interactive-p (not (null callback)))
         (selected-p
          (progn
            (when (and row-selected-p (not (functionp row-selected-p)))
              (error "ETAF Table :row-selected-p must be a function"))
            (and row-selected-p (funcall row-selected-p row))))
         (host-ref nil)
         (theme (etaf-ui--style-tokens
                 :ui-table-border :ui-table-selected-fg
                 :ui-table-selected-bg)))
    (when interactive-p
      (unless (functionp on-row-press)
        (error "ETAF Table :on-row-press must be a function"))
      (when (and row-ref (not (functionp row-ref)))
        (error "ETAF Table :row-ref must be a function"))
      (when row-ref
        (setq host-ref (funcall row-ref row))
        (unless host-ref
          (error "ETAF Table :row-ref must return a non-nil stable ref"))))
    (etaf-node
     'row
     (append
      (unless (etaf-ui--table-fixed-text-columns-p columns) '(:padding (0 0)))
      (list :key identity
            :class (concat "etaf-table-row" (if selected-p " selected" ""))
            :ref host-ref :role (when interactive-p 'button)
            :tab-index (when interactive-p 0)
            :color
            (when selected-p (plist-get theme :ui-table-selected-fg))
            :background-color
            (when selected-p (plist-get theme :ui-table-selected-bg))
            :border-bottom-width 1 :border-bottom-style 'solid
            :border-bottom-color (plist-get theme :ui-table-border)
            :on-press
            (when interactive-p
              (lambda () (funcall callback row-value)))))
     (etaf-ui--table-row-children row columns))))

(etaf-ui--define-component etaf-ui--table-header (&key columns)
  "Render one retained Table header."
  :render (etaf-ui--table-header columns)
  :styles
  (styles
   (".etaf-table-header" :font-weight bold :padding (0 1))
   (".etaf-table-header-cell" :font-weight bold)))

(etaf-ui--define-component etaf-ui--table-row
    (&key row identity columns row-ref on-row-press row-selected-p)
  "Render one retained Table ROW with stable IDENTITY."
  :render
  (etaf-ui--table-row-node
   row identity columns row-ref on-row-press row-selected-p)
  :styles
  (styles
   (".etaf-table-row" :padding (0 1))))

(etaf-ui--define-component etaf-table
    (&key columns rows row-key row-ref on-row-press row-selected-p)
  "Render ordinary ROWS as a presentational Table.

COLUMNS contain a unique non-nil `:key', optional `:label', `:width',
and `:cell' function accepting one row and returning ordinary View content.
Integer widths are character capacities; `(fr N)' shares the remaining width
by positive weight N.
Without `:cell', the key reads a text field from the row.  Cell state belongs
in a returned Component, whose Context comes from the consuming Table.
ROW-KEY supplies stable identity.  ROW-REF is only needed for caller-owned
addresses; interactive rows otherwise receive instance-local references.
Interaction and selection are controlled optional inputs; Table never owns
application or Data Controller state."
  :view
  (column
   :class "etaf-table"
   :color (plist-get (etaf-ui--style-tokens :ui-fg) :ui-fg)
   (etaf-ui--table-header :columns columns)
   (column :class "etaf-table-body"
     (etaf-ui--table-row
      :for (entry (etaf-ui--table-entries rows row-key))
      :key (car entry)
      :row (cdr entry) :identity (car entry) :columns columns
      :row-ref row-ref :on-row-press on-row-press
      :row-selected-p row-selected-p))))

(provide 'etaf-ui-table)
;;; etaf-ui-table.el ends here
