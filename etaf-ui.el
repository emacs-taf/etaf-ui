;;; etaf-ui.el --- Official ETAF Component catalog -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Author: ETAF contributors
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (etaf "0.1.0"))
;; URL: https://github.com/ginqi7/etaf-ui

;;; Commentary:

;; The official ETAF catalog is one ordinary Component library.  It does not
;; expose a parallel Control/Widget taxonomy: a DataGrid is a compound
;; Component built from the same View, props, slots, events, and Data APIs.

;;; Code:

(require 'cl-lib)
(require 'etaf)

(declare-function etaf-data-status "etaf-data" (controller))
(declare-function etaf-data-items "etaf-data" (controller))
(declare-function etaf-data-page "etaf-data" (controller))
(declare-function etaf-data-page-size "etaf-data" (controller))
(declare-function etaf-data-total "etaf-data" (controller))
(declare-function etaf-data-previous-page "etaf-data" (controller))
(declare-function etaf-data-next-page "etaf-data" (controller))
(declare-function text "etaf-view" (&rest arguments))
(declare-function row "etaf-view" (&rest arguments))
(declare-function column "etaf-view" (&rest arguments))
(declare-function expr "etaf-view" (&rest arguments))
(declare-function slot "etaf-view" (&rest arguments))

(defun etaf-ui--class-value (base state custom)
  "Return BASE and STATE classes with optional CUSTOM classes."
  (let ((custom (cond
                 ((null custom) nil)
                 ((listp custom) custom)
                 (t (list custom)))))
    (mapconcat (lambda (class) (format "%s" class))
               (cl-remove-if (lambda (class)
                              (or (null class) (equal class "")))
                            (append (list base state) custom))
               " ")))

(defun etaf-ui--interactive-surface-properties (label disabled)
  "Return shared text properties for an interactive LABEL surface.
DISABLED selects a non-pointer help description instead of an activation
affordance.
The properties are deliberately backend-neutral: Ebox turns them into the
native Emacs pointer/hover/help affordances while other renderers may ignore
the optional text properties and keep the semantic role/event contract."
  (if disabled
      (list 'help-echo (format "%s (disabled)" (or label "Control")))
    (list 'pointer 'hand
          'mouse-face 'highlight
          'help-echo (format "%s · RET or mouse-1" (or label "Activate")))))

(defun etaf-ui--button-view
    (label on-press disabled ref class color bgcolor border padding face
           tab-index aria-label use pressed)
  "Return a Button Host showing LABEL.

ON-PRESS and USE provide callbacks and Behaviors.  DISABLED controls whether
the Host is interactive.  REF, CLASS, COLOR, BGCOLOR, BORDER, PADDING, FACE,
TAB-INDEX, and ARIA-LABEL provide Host identity and presentation."
  (let ((class-value (etaf-ui--class-value
                      "etaf-button"
                      (cond (disabled "disabled")
                            (pressed "pressed")
                            (t "enabled"))
                      class))
        (tab-value (unless disabled (or tab-index 0)))
        (label-value (or aria-label label))
        (surface (etaf-ui--interactive-surface-properties label disabled)))
    (if on-press
        (etaf-view
         (text :class class-value :role 'button :ref ref :disabled disabled
               :tab-index tab-value :aria-label label-value
               :color color :bgcolor bgcolor :border border
               :padding padding :face face
               :surface-properties surface
               :use (unless disabled use) :on-press on-press
               (expr :value label)))
      (etaf-view
       (text :class class-value :role 'button :ref ref :disabled disabled
             :tab-index tab-value :aria-label label-value
             :color color :bgcolor bgcolor :border border
             :padding padding :face face
             :surface-properties surface
             :use (unless disabled use) (expr :value label))))))

(defun etaf-ui--column-value (column key)
  "Return KEY from COLUMN, accepting a plist or alist descriptor."
  (if (and (listp column) (keywordp (car column)))
      (plist-get column key)
    (alist-get key column)))

(defun etaf-ui--grid-cell-value (row key)
  "Return KEY from data ROW, accepting a plist, alist, or hash table."
  (cond
   ((hash-table-p row) (gethash key row))
   ((and (proper-list-p row)
         (zerop (% (length row) 2))
         (keywordp (car row)))
    (plist-get row key))
   ((listp row) (alist-get key row))
   (t nil)))

(defun etaf-ui--grid-display-value (row column)
  "Return one single-line display value for ROW and COLUMN.

DataGrid columns are tabular tracks, not prose paragraphs.  Keep each cell on
one visual line and use an ellipsis when a fixed character-width descriptor is
too small; the original ROW remains intact for selection and callbacks."
  (let* ((value (format "%s"
                       (or (etaf-ui--grid-cell-value
                            row (etaf-ui--column-value column :key)) "")))
         (width (etaf-ui--column-value column :width)))
    (if (and (integerp width) (> width 1)
             (> (string-width value) width))
        ;; Leave one character of the declared track for inter-column air;
        ;; Ebox's left justification fills that remainder without changing
        ;; the stable column geometry.
        (truncate-string-to-width value (1- width) 0 nil "…")
      value)))

(defun etaf-ui--grid-header-cell (column)
  "Return one header View for COLUMN."
  (etaf-view
   (text :class "etaf-data-grid-header-cell"
         :width (etaf-ui--column-value column :width)
         (expr :value (format "%s"
                             (or (etaf-ui--column-value column :label)
                                 (etaf-ui--column-value column :key)))))))

(defun etaf-ui--grid-header (columns)
  "Return a View header row for COLUMNS."
  (etaf-view
   (row
    :class "etaf-data-grid-header"
    (expr :value (mapcar #'etaf-ui--grid-header-cell columns)))))

(defun etaf-ui--grid-cell (row column)
  "Return one data cell View for ROW and COLUMN."
  (etaf-view
   (text :width (etaf-ui--column-value column :width)
         (expr :value (etaf-ui--grid-display-value row column)))))

(defun etaf-ui--grid-cells (row columns)
  "Return data cell Views for ROW and COLUMNS."
  (mapcar (lambda (column) (etaf-ui--grid-cell row column)) columns))

(defun etaf-ui--grid-selected-p (row key selected-key row-selected-p)
  "Return whether ROW with KEY matches SELECTED-KEY or ROW-SELECTED-P."
  (or (and row-selected-p (funcall row-selected-p row))
      (and selected-key (equal key selected-key))))

(defun etaf-ui--grid-row-action (cache key row callback)
  "Return CACHE's stable row action for KEY, refreshing ROW and CALLBACK."
  (let ((entry (gethash key cache)))
    (unless entry
      (setq entry (vector row callback nil))
      (aset entry 2
            (lambda ()
              (let ((current (aref entry 1)))
                (when current
                  (funcall current (aref entry 0))))))
      (puthash key entry cache))
    (aset entry 0 row)
    (aset entry 1 callback)
    (aref entry 2)))

(defun etaf-ui--grid-row
    (row columns row-key row-ref on-row-press selected-key row-selected-p
         row-actions)
  "Return a View row for ROW and COLUMNS with the DataGrid contract.

ROW-KEY returns identity; ROW-REF returns the interactive reference;
ON-ROW-PRESS, SELECTED-KEY, and ROW-SELECTED-P control state.  ROW-ACTIONS
owns stable keyed callbacks across Range reevaluation."
  (let* ((key (funcall row-key row))
         (interactive-p (not (null on-row-press)))
         (selected-p (etaf-ui--grid-selected-p
                      row key selected-key row-selected-p))
         host-ref)
    (unless key
      (error "ETAF DataGrid row-key must return a non-nil stable scalar"))
    (when interactive-p
      (unless (functionp row-ref)
        (error "ETAF DataGrid requires :row-ref for interactive rows"))
      (setq host-ref (funcall row-ref row))
      (unless host-ref
        (error "ETAF DataGrid :row-ref must return a non-nil stable ref")))
    (etaf-view
     (row
      :key key
      :class (concat "etaf-data-grid-row"
                     (if selected-p " selected" ""))
      :ref host-ref
      :role (when interactive-p 'button)
      :tab-index (when interactive-p 0)
      :surface-properties
      (when interactive-p
        (etaf-ui--interactive-surface-properties
         (format "Row %s" key) nil))
      :on-press (when interactive-p
                  (etaf-ui--grid-row-action
                   row-actions key row on-row-press))
      (expr :value (etaf-ui--grid-cells row columns))))))

(defun etaf-ui--grid-rows
    (items columns row-key row-ref on-row-press selected-key row-selected-p
           row-actions)
  "Return keyed item Views and prune ROW-ACTIONS outside current ITEMS.
COLUMNS and ROW-KEY describe cells and identity.  ROW-REF, ON-ROW-PRESS,
SELECTED-KEY, and ROW-SELECTED-P provide interaction state."
  (let ((seen (make-hash-table :test #'equal)))
    (prog1
        (mapcar
         (lambda (item)
           (puthash (funcall row-key item) t seen)
           (etaf-ui--grid-row
            item columns row-key row-ref on-row-press selected-key
            row-selected-p row-actions))
         items)
      (maphash (lambda (key _entry)
                 (unless (gethash key seen)
                   (remhash key row-actions)))
               row-actions))))

(defun etaf-ui--button-setup ()
  "Create the retained renderer for one Button instance."
  (let* ((pressed (etaf-ref nil))
         (timer nil)
         (scope (etaf-current-effect-scope))
         (current-callback nil)
         (current-press-p nil)
         (press nil))
    (setq press
          (lambda ()
            (when current-press-p
              (when (timerp timer)
                (cancel-timer timer))
              (setf (etaf-value pressed) t)
              (unwind-protect
                  (when current-callback
                    (funcall current-callback))
                (setq timer
                      (run-at-time
                       0.09 nil
                       (lambda ()
                         (when (etaf-effect-scope-active-p scope)
                           (setf (etaf-value pressed) nil)))))))))
    (etaf-on-unmounted
     (lambda ()
       (when (timerp timer)
         (cancel-timer timer))))
    (lambda ()
      (let* ((label (etaf-current-prop :label))
             (callback (etaf-current-prop :on-press))
             (disabled (etaf-current-prop :disabled))
             (use (etaf-current-prop :use))
             (press-p (and (not disabled) (or callback use))))
        (setq current-callback callback
              current-press-p press-p)
        (let* ((state-pressed (and (not disabled) (etaf-value pressed)))
               (state-class (cond (disabled "disabled")
                                  (state-pressed "pressed")
                                  (t "enabled")))
               (variant (and (not disabled) (etaf-current-prop :variant)))
               (variant-values
                (cond
                 (disabled
                  '(:color "#687386" :bgcolor "#E5E7EB"
                    :border ((1) solid "#9CA3AF") :face normal))
                 ((and (eq variant 'secondary) state-pressed)
                  '(:color "#142235" :bgcolor "#B9DED7"
                    :border ((1) solid "#24736C") :face bold))
                 ((eq variant 'secondary)
                  '(:color "#142235" :bgcolor "#D9EEEA"
                    :border ((1) solid "#2E8B83") :face bold))
                 ((and (eq variant 'ghost) state-pressed)
                  '(:color "#142235" :bgcolor "#EEEAE2"
                    :border ((1) solid "#A79F93") :face normal))
                 ((eq variant 'ghost)
                  '(:color "#142235" :bgcolor "#FFFDF8"
                    :border ((1) solid "#C8C1B6") :face normal))
                 ;; The enabled/pressed catalog defaults used to come from
                 ;; state selectors alone.  Resolve them as props too so an
                 ;; explicit theme can override the same state boundary.
                 (state-pressed
                  '(:color "#FFFFFF" :bgcolor "#1E5A56"
                    :border ((1) solid "#174A47") :face bold))
                 (t
                  '(:color "#FFFFFF" :bgcolor "#2F6B43"
                    :border ((1) solid "#2F6B43") :face bold)))))
          (etaf-ui--button-view
           label (and press-p press) disabled (etaf-current-prop :ref)
           (let ((custom-class (etaf-current-prop :class)))
             (delq nil (list custom-class state-class)))
           (or (etaf-current-prop :color)
               (plist-get variant-values :color))
           (or (etaf-current-prop :bgcolor)
               (plist-get variant-values :bgcolor))
           (or (etaf-current-prop :border)
               (plist-get variant-values :border))
           (etaf-current-prop :padding)
           (or (etaf-current-prop :face)
               (plist-get variant-values :face))
           (etaf-current-prop :tab-index)
           (etaf-current-prop :aria-label)
           use state-pressed))))))

;;;###autoload
(etaf-define-component etaf-button
    (&key label on-press disabled ref class color bgcolor border padding face
          tab-index aria-label use variant)
  "Render a standard pressable button with LABEL and ON-PRESS.

DISABLED removes the callback and the default focus tab index.  Product
appearance is controlled by VARIANT and the shared interactive surface
contract; callers can still override presentation with the ordinary props."
  :styles
  (styles
   ("&" :width max-content)
   ;; State classes carry semantic state only.  Resolved presentation props
   ;; above remain authoritative, so a themed disabled Button cannot inherit
   ;; the catalog's light default surface.
   ("&.disabled" :padding (0 1) :face normal)
   ("&.enabled" :padding (0 1) :face bold)
   ("&.pressed" :padding (0 1) :face bold))
  :setup
  (etaf-ui--button-setup))

(defun etaf-ui--checkbox-view
    (checked label on-change ref disabled class color bgcolor border padding
             face tab-index aria-label)
  "Return LABEL checkbox View with captured CHECKED and ON-PRESS.
REF, DISABLED, CLASS, COLOR, BGCOLOR, BORDER, PADDING, FACE, TAB-INDEX, and
ARIA-LABEL provide its semantic and presentation properties."
  (etaf-view
   (row
    :class (etaf-ui--class-value
            "etaf-checkbox" (if disabled "disabled" "enabled") class)
    :role 'checkbox :ref ref :disabled disabled
    :aria-label (or aria-label label)
    :tab-index (unless disabled (or tab-index 0))
    :color color :bgcolor bgcolor :border border :padding padding :face face
    :surface-properties (etaf-ui--interactive-surface-properties label disabled)
    :on-press on-change
    (text :class "etaf-checkbox-mark" (expr :value (if checked "☑" "☐")))
    (text (expr :value (if label (concat " " label) ""))))))

;;;###autoload
(etaf-define-component etaf-checkbox
    (&key checked label on-change ref disabled class color bgcolor border padding
          face tab-index aria-label)
  "Render a controlled checkbox with CHECKED, LABEL, and ON-CHANGE.

ON-CHANGE receives the next boolean value.  State ownership stays with the
caller, so the Component works with local refs or Data-backed forms."
  :styles
  (styles
   ("&" :width max-content)
   ("&.disabled" :color "#6B7280" :bgcolor "#EEEAE2"
    :border ((1) solid "#9CA3AF") :padding (0 1))
   ("&.enabled" :color "#252A2E" :bgcolor "#DCEBDD"
    :border ((1) solid "#6D8A73") :padding (0 1))
   (".etaf-checkbox-mark" :face bold :width 1))
  :setup
  (let* ((current-checked nil)
         (current-callback nil)
         (press
          (lambda ()
            (when current-callback
              (funcall current-callback (not current-checked))))))
    (lambda ()
      (setq current-checked (etaf-current-prop :checked)
            current-callback
            (when (and (not (etaf-current-prop :disabled))
                       (etaf-current-prop :on-change))
              (etaf-current-prop :on-change)))
      (etaf-ui--checkbox-view
       current-checked (etaf-current-prop :label)
       (and current-callback press)
       (etaf-current-prop :ref) (etaf-current-prop :disabled)
       (etaf-current-prop :class) (etaf-current-prop :color)
       (etaf-current-prop :bgcolor) (etaf-current-prop :border)
       (etaf-current-prop :padding) (etaf-current-prop :face)
       (etaf-current-prop :tab-index) (etaf-current-prop :aria-label)))))

;;;###autoload
(etaf-define-component etaf-label
    (&key text face class color bgcolor border padding ref width)
  "Render TEXT as a semantic label with presentation properties."
  :view
  (expr
   :value
   (etaf-view
    (text :class class :face face :color color :bgcolor bgcolor :border border
          :padding padding :ref ref :width width (expr :value text)))))

;;;###autoload
(etaf-define-component etaf-panel
    (&key title class color bgcolor border padding ref)
  "Render a titled panel with header and default slot projections."
  :styles
  (styles
   ("&" :padding (1 2) :border ((1) solid "#687386")
    :color "#252A2E" :bgcolor "#FFFDF8")
   (".etaf-panel-title" :face bold))
  :view
  (expr
   :value
   (etaf-view
    (column
     :class (etaf-ui--class-value "etaf-panel" nil class)
     :color color :bgcolor bgcolor :border border :padding padding :ref ref
     (expr
      :value
      (when title
        (etaf-view (text :class "etaf-panel-title"
                         (expr :value title)))))
     (slot :name 'header)
     (slot)))))

;;;###autoload
(etaf-define-component etaf-data-grid
    (&key controller columns row-key on-row-press
          row-ref selected-key row-selected-p loading-label error-label
          empty-label)
  "Render rows from reactive DATA CONTROLLER and COLUMNS.

COLUMNS is a list of descriptors such as `(:key :name :label NAME)'.  ROW-KEY
receives each row and must return a stable scalar identity.  Data owns loading,
errors, pagination, mutation, and selection; this Component only projects
those values into ordinary Hosts.  Interactive rows require ROW-REF to return
a stable Host reference."
  :styles
  (styles
   (".etaf-data-grid-header" :face bold :padding (0 1)
    :border ((1) solid "#687386"))
   (".etaf-data-grid-header-cell" :face bold)
   (".etaf-data-grid-row" :padding (0 1)
    :border ((1) solid "#687386"))
   (".selected" :color "#2F6B43"
    :border ((1) solid "#73A982"))
   (".etaf-data-grid-error" :color "#FF6B6B"))
  :setup
  (let ((row-actions (make-hash-table :test #'equal)))
    (lambda ()
      (let ((controller (etaf-current-prop :controller))
            (columns (etaf-current-prop :columns))
            (row-key (etaf-current-prop :row-key))
            (row-ref (etaf-current-prop :row-ref))
            (on-row-press (etaf-current-prop :on-row-press))
            (selected-key (etaf-current-prop :selected-key))
            (row-selected-p (etaf-current-prop :row-selected-p))
            (loading-label (etaf-current-prop :loading-label))
            (error-label (etaf-current-prop :error-label))
            (empty-label (etaf-current-prop :empty-label)))
        (etaf-view
         (column
          :class "etaf-data-grid"
          (expr :value (etaf-ui--grid-header columns))
          (column
           :class "etaf-data-grid-body"
           (expr
            :value
            (progn
              (unless (functionp row-key)
                (error "ETAF DataGrid requires a function-valued :row-key"))
              (when (and on-row-press (not (functionp on-row-press)))
                (error "ETAF DataGrid :on-row-press must be a function"))
              (when (and on-row-press (not (functionp row-ref)))
                (error "ETAF DataGrid requires :row-ref for interactive rows"))
              (when (and row-selected-p (not (functionp row-selected-p)))
                (error "ETAF DataGrid :row-selected-p must be a function"))
              (let ((status (etaf-value (etaf-data-status controller)))
                    (items (etaf-value (etaf-data-items controller))))
                (cond
                 ((eq status 'loading)
                  (etaf-view
                   (text (expr :value (or loading-label "Loading...")))))
                 ((eq status 'error)
                  (etaf-view
                   (text :class "etaf-data-grid-error"
                         (expr :value
                               (or error-label "Unable to load data.")))))
                 ((null items)
                  (etaf-view
                   (text (expr :value (or empty-label "No data.")))))
                 (t
                  (etaf-ui--grid-rows
                   items columns row-key row-ref on-row-press selected-key
                   row-selected-p row-actions))))))
          (slot :name 'footer))))))))

;;;###autoload
(etaf-define-component etaf-pagination
    (&key controller previous-ref next-ref class color bgcolor border padding
          aria-label)
  "Render a compact, accessible pager for DATA CONTROLLER.

The pager owns no data state: page, page-size, total, loading, and error stay
with CONTROLLER.  PREVIOUS-REF and NEXT-REF should be stable public refs when
the pager participates in keyboard/mouse interaction.  The visible glyphs
(`‹' and `›') are paired with labels and help text so the compact control is
readable in both GUI and text review."
  :styles
  (styles
   ("&" :width stretch)
   (".etaf-pagination-label" :face bold)
   (".etaf-pagination-summary" :color "#526174"))
  :setup
  (let* ((current-controller nil)
         (previous
          (lambda ()
            (when current-controller
              (etaf-data-previous-page current-controller))))
         (next
          (lambda ()
            (when current-controller
              (etaf-data-next-page current-controller)))))
    (lambda ()
      (let* ((controller-value (etaf-current-prop :controller))
             (page (max 1 (or (etaf-value (etaf-data-page controller-value)) 1)))
             (page-size (max 1 (or (etaf-value (etaf-data-page-size controller-value)) 1)))
             (total (max 0 (or (etaf-value (etaf-data-total controller-value)) 0)))
             (pages (max 1 (ceiling (/ (float total) page-size))))
             (status (etaf-value (etaf-data-status controller-value)))
             (first-item (if (zerop total) 0 (1+ (* (1- page) page-size))))
             (last-item (min total (* page page-size)))
             (previous-disabled (or (eq status 'loading) (<= page 1)))
             (next-disabled (or (eq status 'loading) (>= page pages))))
        (setq current-controller controller-value)
        (etaf-view
         (row :class (etaf-ui--class-value "etaf-pagination" nil
                                           (etaf-current-prop :class))
              :role 'navigation
              :aria-label (or (etaf-current-prop :aria-label) "Pagination")
              :color (etaf-current-prop :color)
              :bgcolor (etaf-current-prop :bgcolor)
              :border (etaf-current-prop :border)
              :padding (etaf-current-prop :padding)
          (button :label "‹" :ref (etaf-current-prop :previous-ref)
                  :aria-label "Previous page"
                  :disabled previous-disabled
                  :padding '(0 0)
                  :border '((0) solid "transparent")
                  :variant 'secondary
                  :on-press (unless previous-disabled previous))
          (column :flex-grow 1 :flex-shrink 1 :flex-basis '(0) :min-width 0
           (text :class "etaf-pagination-label" :text-align 'center
                 (expr :value (format "Page %d / %d" page pages)))
           (text :class "etaf-pagination-summary" :text-align 'center
                 (expr :value (format "%d–%d of %d"
                                      first-item last-item total))))
          (button :label "›" :ref (etaf-current-prop :next-ref)
                  :aria-label "Next page"
                  :disabled next-disabled
                  :padding '(0 0)
                  :border '((0) solid "transparent")
                  :variant 'secondary
                  :on-press (unless next-disabled next))))))))

(provide 'etaf-ui)

;;; etaf-ui.el ends here
