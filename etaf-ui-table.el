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

(defun etaf-ui--table-cell-value (row key)
  "Return KEY from ROW, accepting a plist, alist, or hash table."
  (cond
   ((hash-table-p row) (gethash key row))
   ((and (proper-list-p row)
         (zerop (% (length row) 2))
         (keywordp (car row)))
    (plist-get row key))
   ((listp row) (alist-get key row))
   (t nil)))

(defun etaf-ui--table-fit-text (value column)
  "Return VALUE fitted to COLUMN's declared character capacity."
  (let* ((value (format "%s" (or value "")))
         (width (etaf-ui--column-value column :width)))
    (if (and (integerp width) (> width 0)
             (> (string-width value) width))
        (truncate-string-to-width value width 0 nil "…")
      value)))

(defun etaf-ui--table-track-width (column gap-p)
  "Return COLUMN width with one character gap when GAP-P is non-nil."
  (let ((width (etaf-ui--column-value column :width)))
    (if (and gap-p (integerp width) (> width 0))
        (1+ width)
      width)))

(defun etaf-ui--table-header-cell (column gap-p)
  "Return one Label header for COLUMN, adding air when GAP-P is non-nil."
  (etaf-node
   'box
   (list :class "etaf-table-header-cell"
         :width (etaf-ui--table-track-width column gap-p)
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
  (when (and columns
             (cl-every
              (lambda (column)
                (let ((width (etaf-ui--column-value column :width)))
                  (and (integerp width) (> width 0))))
              columns))
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
  (let ((theme (etaf-ui--style-tokens :ui-table-border))
        (fixed-text (etaf-ui--table-fixed-header-text columns)))
    (etaf-node
     'row
     (list :class "etaf-table-header"
           :border-bottom-width 1 :border-bottom-style 'solid
           :border-bottom-color (plist-get theme :ui-table-border))
     (if fixed-text
         (list (etaf-node 'text nil (list fixed-text)))
       (cl-loop for column in columns
                for tail on columns
                collect
                (etaf-ui--table-header-cell column (cdr tail)))))))

(defun etaf-ui--table-cell (row column gap-p)
  "Return one Label cell for ROW and COLUMN using GAP-P."
  (etaf-node
   'box
   (list :class "etaf-table-cell"
         :width (etaf-ui--table-track-width column gap-p)
         :wrap-mode 'none)
   (list
    (etaf-node
     'text nil
     (list
      (etaf-ui--table-fit-text
       (etaf-ui--table-cell-value
        row (etaf-ui--column-value column :key))
       column))))))

(defun etaf-ui--table-cells (row columns)
  "Return cell Components for ROW using COLUMNS."
  (cl-loop for column in columns
           for tail on columns
           collect
           (etaf-ui--table-cell row column (cdr tail))))

(defun etaf-ui--table-fixed-row-text (row columns)
  "Return one fixed-width ROW string for COLUMNS, or nil when not applicable."
  (when (and columns
             (cl-every
              (lambda (column)
                (let ((width (etaf-ui--column-value column :width)))
                  (and (integerp width) (> width 0))))
              columns))
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
COLUMNS with fixed positive character widths use one padded Text Host;
otherwise retain the general per-cell Box path."
  (if-let* ((text (etaf-ui--table-fixed-row-text row columns)))
      (list (etaf-node 'text nil (list text)))
    (etaf-ui--table-cells row columns)))

(defun etaf-ui--table-entries (rows row-key)
  "Return `(KEY . ROW)' entries for ROWS using ROW-KEY.
ETAF validates keys and uniqueness."
  (unless (functionp row-key)
    (error "ETAF Table requires a function-valued :row-key"))
  (mapcar (lambda (row) (cons (funcall row-key row) row)) rows))

(defun etaf-ui--table-row-node
    (row identity columns row-ref on-row-press row-selected-p)
  "Return one canonical row Host for ROW and stable IDENTITY.

This helper is shared by the retained presentational Table Component and the
DataGrid's keyed hot path.  Keeping the row itself as a Host avoids creating a
second Component boundary for every visible item while preserving the same
selection, event, and style contract.  COLUMNS define the visible cells;
ROW-REF, ON-ROW-PRESS, and ROW-SELECTED-P define optional interaction."
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
      (unless (functionp row-ref)
        (error "ETAF Table requires :row-ref for interactive rows"))
      (setq host-ref (funcall row-ref row))
      (unless host-ref
        (error "ETAF Table row reference must be non-nil")))
    (etaf-node
     'row
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
             (lambda () (funcall callback row-value))))
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

COLUMNS contain `:key', optional `:label', and optional character `:width'.
ROW-KEY supplies stable identity.  Interaction and selection are controlled
optional inputs; Table never owns application or Data Controller state."
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
