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
(declare-function etaf-data-selected-ref "etaf-data" (controller identity))
(declare-function etaf-theme-defaults "etaf-context" (&optional default))
(declare-function text "etaf-view" (&rest arguments))
(declare-function box "etaf-view" (&rest arguments))
(declare-function expr "etaf-view" (&rest arguments))
(declare-function slot "etaf-view" (&rest arguments))

(defconst etaf-ui--default-theme-palette
  '(:ui-fg "#252A2E"
    :ui-bg "#FFFDF8"
    :ui-border "#687386"
    :ui-muted-fg "#526174"
    :ui-danger-fg "#FF6B6B"
    :ui-success-fg "#2F6B43"
    :ui-disabled-fg "#687386"
    :ui-disabled-bg "#E5E7EB"
    :ui-disabled-border "#9CA3AF"
    :ui-button-primary-fg "#FFFFFF"
    :ui-button-primary-bg "#2F6B43"
    :ui-button-primary-border "#2F6B43"
    :ui-button-secondary-fg "#142235"
    :ui-button-secondary-bg "#D9EEEA"
    :ui-button-secondary-border "#2E8B83"
    :ui-button-ghost-fg "#142235"
    :ui-button-ghost-bg "#FFFDF8"
    :ui-button-ghost-border "#C8C1B6"
    :ui-checkbox-enabled-fg "#252A2E"
    :ui-checkbox-enabled-bg "#DCEBDD"
    :ui-checkbox-enabled-border "#6D8A73"
    :ui-checkbox-disabled-fg "#6B7280"
    :ui-checkbox-disabled-bg "#EEEAE2"
    :ui-checkbox-disabled-border "#9CA3AF"
    :ui-grid-border "#687386"
    :ui-grid-selected-fg "#2F6B43"
    :ui-grid-selected-bg "#DCEBDD"
    :ui-grid-error-fg "#FF6B6B"
    :ui-pagination-muted-fg "#526174"
    :ui-panel-fg "#252A2E"
    :ui-panel-bg "#FFFDF8"
    :ui-panel-border "#687386")
  "Default semantic UI palette, centralized outside Component definitions.

Applications normally override these tokens through ETAF Theme.  Keeping the
fallback palette here gives the catalog a useful standalone appearance while
ensuring every Component reads one shared semantic vocabulary.")

(defconst etaf-ui--legacy-theme-aliases
  '((:ui-fg :color)
    (:ui-bg :bgcolor)
    (:ui-border :border)
    (:ui-button-primary-fg :ui-button-color)
    (:ui-button-primary-bg :ui-button-bgcolor)
    (:ui-button-primary-border :ui-button-border)
    (:ui-button-secondary-fg :ui-button-secondary-color)
    (:ui-button-secondary-bg :ui-button-secondary-bgcolor)
    (:ui-button-secondary-border :ui-button-secondary-border)
    (:ui-button-ghost-fg :ui-button-ghost-color)
    (:ui-button-ghost-bg :ui-button-ghost-bgcolor)
    (:ui-button-ghost-border :ui-button-ghost-border)
    (:ui-disabled-fg :ui-button-disabled-color)
    (:ui-disabled-bg :ui-button-disabled-bgcolor)
    (:ui-disabled-border :ui-button-disabled-border))
  "Compatibility aliases for the first ETAF UI Theme token spelling.")

;;;###autoload
(defun etaf-ui-theme-values (&rest requested)
  "Return merged semantic UI Theme values for REQUESTED tokens.

Inherited application tokens win, legacy aliases remain readable, and the
central catalog palette fills only omitted values.  This is the boundary
between generic ETAF Theme Context and etaf-ui's product-independent visual
semantics; individual Components do not own separate color systems.  When
REQUESTED is nil, return the complete catalog token map."
  (let* ((inherited (etaf-theme-defaults))
         (defaults etaf-ui--default-theme-palette)
         ;; Callers that request a subset only need that semantic subset.
         ;; Keeping the full inherited plist is useful for the no-argument
         ;; catalog query, but copying it for every Button/Panel/DataGrid
         ;; render needlessly scales Theme work with application token count.
         (result (unless requested (copy-sequence inherited)))
         (keys (or requested
                   (cl-loop for (key _spec) on defaults by #'cddr
                            collect key))))
    (dolist (key keys)
      (let ((found
             (cond
              ((plist-member inherited key)
               (cons t (plist-get inherited key)))
              (t
               (cl-loop for alias in etaf-ui--legacy-theme-aliases
                        when (and (eq (car alias) key)
                                  (plist-member inherited (cadr alias)))
                        return
                        (cons t (plist-get inherited (cadr alias))))))))
        (setq result
              (plist-put result key
                         (if found (cdr found) (plist-get defaults key)))))
      )
    result))

(defun etaf-ui-theme-tokens (&rest requested)
  "Return deferred semantic Theme tokens for REQUESTED UI keys.

Catalog defaults and legacy aliases are encoded as nested token fallbacks, so
Host lowering can update paint properties without making the current
Component render depend on the Theme source."
  (let ((keys (or requested
                  (cl-loop for (key _spec) on etaf-ui--default-theme-palette
                           by #'cddr collect key)))
        result)
    (dolist (key keys result)
      (let* ((default (plist-get etaf-ui--default-theme-palette key))
             (alias (cadr (assq key etaf-ui--legacy-theme-aliases)))
             (fallback (if alias (etaf-theme-token alias default) default)))
        (setq result
              (plist-put result key (etaf-theme-token key fallback)))))))

(defun etaf-ui--theme-border (value)
  "Return Ebox border VALUE, preserving complete caller-owned specs.

Semantic Theme border tokens conventionally contain a color string.  The
catalog turns a hex color into its one-cell border shape; an existing border
plist or a legacy caller-owned string remains untouched for compatibility."
  (cond
   ((etaf-theme-token-p value)
    (etaf-theme-token (nth 1 value) (nth 2 value)
                      #'etaf-ui--theme-border))
   ((and (stringp value)
         (string-match-p "\\`#[[:xdigit:]]+\\'" value))
    (list (list 1) 'solid value))
   (t value)))

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

(defun etaf-ui--reactive-value (value)
  "Return VALUE, reading it when it is an ETAF reactive source."
  (if (or (etaf-ref-p value) (etaf-computed-p value))
      (etaf-value value)
    value))

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
         (border (cond (disabled :ui-disabled-border)
                       ((eq variant 'secondary) :ui-button-secondary-border)
                       ((eq variant 'ghost) :ui-button-ghost-border)
                       (t :ui-button-primary-border)))
         (theme (etaf-ui-theme-tokens fg bg border)))
    (list :color (plist-get theme fg)
          :bgcolor (plist-get theme bg)
          :border (etaf-ui--theme-border (plist-get theme border))
          :font-weight (if (or disabled (eq variant 'ghost)) 'normal 'bold))))

(defun etaf-ui--button-view
    (label on-press disabled ref class color bgcolor border padding font-weight
           tab-index aria-label use)
  "Return a Button Host showing LABEL.

ON-PRESS and USE provide callbacks and Behaviors.  DISABLED controls whether
the Host is interactive.  REF, CLASS, COLOR, BGCOLOR, BORDER, PADDING, FACE,
TAB-INDEX, and ARIA-LABEL provide Host identity and presentation."
  (let ((class-value (etaf-ui--class-value
                      "etaf-button"
                      (if disabled "disabled" "enabled")
                      class))
        (tab-value (unless disabled (or tab-index 0)))
        (label-value (or aria-label label)))
    (if on-press
        (etaf-view
         (box :class class-value :role 'button :ref ref :disabled disabled
               :tab-index tab-value :aria-label label-value
               :color color :bgcolor bgcolor :border border
               :padding padding :font-weight font-weight
               :use (unless disabled use) :on-press on-press
          (text (expr :value label))))
      (etaf-view
       (box :class class-value :role 'button :ref ref :disabled disabled
             :tab-index tab-value :aria-label label-value
             :color color :bgcolor bgcolor :border border
             :padding padding :font-weight font-weight
             :use (unless disabled use)
        (text (expr :value label)))))))

(defun etaf-ui--checkbox-variant-values (theme disabled)
  "Return semantic Theme values from THEME for DISABLED Checkbox state."
  (let ((prefix (if disabled "disabled" "enabled")))
    (list :color (plist-get theme
                            (intern (format ":ui-checkbox-%s-fg" prefix)))
          :bgcolor (plist-get theme
                              (intern (format ":ui-checkbox-%s-bg" prefix)))
          :border
          (etaf-ui--theme-border
           (plist-get theme
                      (intern (format ":ui-checkbox-%s-border" prefix)))))))

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

(defun etaf-ui--grid-fit-text (value column)
  "Return VALUE fitted to COLUMN's declared character capacity."
  (let* ((value (format "%s" (or value "")))
         (width (etaf-ui--column-value column :width)))
    (if (and (integerp width) (> width 0)
             (> (string-width value) width))
        (truncate-string-to-width value width 0 nil "…")
      value)))

(defun etaf-ui--grid-display-value (row column)
  "Return one single-line display value for ROW and COLUMN.

DataGrid columns are tabular tracks, not prose paragraphs.  Keep each cell on
one visual line and use an ellipsis when a fixed character-width descriptor is
too small; the original ROW remains intact for selection and callbacks."
  (etaf-ui--grid-fit-text
   (etaf-ui--grid-cell-value row (etaf-ui--column-value column :key))
   column))

(defun etaf-ui--grid-track-width (column gap-p)
  "Return COLUMN width with one native-character gap when GAP-P is non-nil."
  (let ((width (etaf-ui--column-value column :width)))
    (if (and gap-p (integerp width) (> width 0))
        (1+ width)
      width)))

(defun etaf-ui--grid-header-cell (column gap-p)
  "Return one header View for COLUMN, adding air when GAP-P is non-nil."
  (etaf--view-call
   'box
   (list :class "etaf-data-grid-header-cell"
         :width (etaf-ui--grid-track-width column gap-p))
   (list
    (etaf--view-call
     'text nil
     (list
      (etaf-ui--grid-fit-text
       (or (etaf-ui--column-value column :label)
           (etaf-ui--column-value column :key))
       column))))))

(defun etaf-ui--grid-header (columns theme)
  "Return a View header row for COLUMNS using semantic THEME colors."
  (etaf-view
   (row :class "etaf-data-grid-header"
        :border (etaf-ui--theme-border
                 (plist-get theme :ui-grid-border))
    (expr :value
          (cl-loop for column in columns
                   for tail on columns
                   collect (etaf-ui--grid-header-cell
                            column (cdr tail)))))))

(defun etaf-ui--grid-cell (row column gap-p host-ref)
  "Return one data cell View for ROW and COLUMN using HOST-REF and GAP-P."
  (etaf--view-call
   'box
   (list :ref host-ref :width (etaf-ui--grid-track-width column gap-p))
   (list
    (etaf--view-call
     'text nil (list (etaf-ui--grid-display-value row column))))))

(defun etaf-ui--grid-cells (row columns cell-refs)
  "Return data cell Views for ROW and COLUMNS using stable CELL-REFS."
  (cl-loop for column in columns
           for tail on columns
           for index from 0
           collect
           (etaf-ui--grid-cell
            row column (cdr tail)
            (or (gethash index cell-refs)
                (puthash index (gensym "etaf-data-grid-cell-")
                         cell-refs)))))

(defun etaf-ui--grid-selected-p
    (row key selected-key row-selected-p selected-ref)
  "Return whether ROW with KEY is selected.
ROW-SELECTED-P and SELECTED-KEY preserve custom controlled selection;
SELECTED-REF supplies the controller-backed keyed default."
  (or (and row-selected-p (funcall row-selected-p row))
      (and selected-key (equal key selected-key))
      (and selected-ref (etaf-value selected-ref))))

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
    (row key columns row-ref on-row-press selected-key row-selected-p
         selected-ref row-actions theme internal-row-ref cell-refs)
  "Return a View row for ROW and COLUMNS using THEME and the DataGrid contract.

KEY is ROW's stable identity; ROW-REF returns the interactive reference;
ON-ROW-PRESS, SELECTED-KEY, ROW-SELECTED-P, and SELECTED-REF control state.
ROW-ACTIONS owns stable keyed callbacks across body reevaluation."
  (let* ((interactive-p (not (null on-row-press)))
         (selected-p
          (lambda ()
            (etaf-ui--grid-selected-p
             row key selected-key row-selected-p selected-ref)))
         (host-ref internal-row-ref))
    (unless key
      (error "ETAF DataGrid row-key must return a non-nil stable scalar"))
    (when interactive-p
      (unless (functionp row-ref)
        (error "ETAF DataGrid requires :row-ref for interactive rows"))
      (setq host-ref (funcall row-ref row))
      (unless host-ref
        (error "ETAF DataGrid :row-ref must return a non-nil stable ref")))
    (etaf--view-call
     'row
     (list :key key
           :class
           (etaf--expr-create
            :thunk (lambda ()
                     (concat "etaf-data-grid-row"
                             (if (funcall selected-p) " selected" ""))))
           :ref host-ref
           :role (when interactive-p 'button)
           :tab-index (when interactive-p 0)
           :border-bottom-p t
           :border-bottom-color (plist-get theme :ui-grid-border)
           :on-press (when interactive-p
                       (etaf-ui--grid-row-action
                        row-actions key row on-row-press))
           :bgcolor
           (etaf--expr-create
            :thunk (lambda ()
                     (when (funcall selected-p)
                       (plist-get theme :ui-grid-selected-bg)))))
     (etaf-ui--grid-cells row columns cell-refs))))

(defun etaf-ui--grid-row-state (states key)
  "Return STATES' retained internal row and cell refs for KEY."
  (or (gethash key states)
      (let ((state (cons (gensym "etaf-data-grid-row-")
                         (make-hash-table :test #'eql))))
        (puthash key state states)
        state)))

(defun etaf-ui--grid-keyed-items
    (items row-key row-actions row-states)
  "Return validated `(KEY . ITEM)' entries and prune retained row caches."
  (let ((seen (make-hash-table :test #'equal)) entries)
    (dolist (item items)
      (let ((key (funcall row-key item)))
        (unless key
          (error "ETAF DataGrid row-key must return a non-nil stable scalar"))
        (when (gethash key seen)
          (error "ETAF DataGrid row-key must be unique: %S" key))
        (puthash key t seen)
        (push (cons key item) entries)))
    (maphash
     (lambda (key _entry)
       (unless (gethash key seen)
         (remhash key row-actions)
         (remhash key row-states)))
     row-actions)
    (nreverse entries)))

(defun etaf-ui--grid-rows
    (controller items columns row-key row-ref on-row-press selected-key
                row-selected-p row-actions row-states &optional theme)
  "Return keyed Host rows and prune caches outside current ITEMS.
CONTROLLER owns keyed default selection refs.  COLUMNS and ROW-KEY describe
cells and identity.  ROW-REF, ON-ROW-PRESS, SELECTED-KEY, and ROW-SELECTED-P
provide interaction state.  ROW-ACTIONS and ROW-STATES retain callback and
internal Host identities.  THEME optionally supplies resolved colors."
  (let* ((theme (or theme
                    ;; Resolve Theme once in the retained DataGrid owner
                    ;; of doing it independently in every row Component.
                    (etaf-ui-theme-tokens :ui-grid-border
                                          :ui-grid-selected-fg
                                          :ui-grid-selected-bg)))
         (entries
          (etaf-ui--grid-keyed-items
           items row-key row-actions row-states)))
    (mapcar
     (lambda (entry)
       (let* ((key (car entry))
              (item (cdr entry))
              (state (etaf-ui--grid-row-state row-states key)))
         (etaf-ui--grid-row
          item key columns row-ref on-row-press selected-key row-selected-p
          (unless (or row-selected-p selected-key)
            (etaf-data-selected-ref controller key))
          row-actions theme (car state) (cdr state))))
     entries)))

(defun etaf-ui--grid-body-items
  (controller status items columns row-key row-ref on-row-press selected-key
                row-selected-p row-actions row-states theme loading-label
                error-label empty-label)
  "Return CONTROLLER DataGrid body items for STATUS and ITEMS.
COLUMNS and ROW-KEY describe rows; ROW-REF and ON-ROW-PRESS add interaction.
SELECTED-KEY, ROW-SELECTED-P, and ROW-ACTIONS preserve controlled behavior.
THEME supplies colors, while LOADING-LABEL, ERROR-LABEL, and EMPTY-LABEL
customize state messages.  The parent Component directly owns the result."
  (unless (functionp row-key)
    (error "ETAF DataGrid requires a function-valued :row-key"))
  (when (and on-row-press (not (functionp on-row-press)))
    (error "ETAF DataGrid :on-row-press must be a function"))
  (when (and on-row-press (not (functionp row-ref)))
    (error "ETAF DataGrid requires :row-ref for interactive rows"))
  (when (and row-selected-p (not (functionp row-selected-p)))
    (error "ETAF DataGrid :row-selected-p must be a function"))
  (cond
    ((eq status 'loading)
     (list (etaf--view-call 'text nil
                            (list (or loading-label "Loading...")))))
    ((eq status 'error)
     (list
      (etaf--view-call
       'text
       (list :class "etaf-data-grid-error"
             :color (plist-get (etaf-ui-theme-tokens :ui-grid-error-fg)
                               :ui-grid-error-fg))
       (list (or error-label "Unable to load data.")))))
    ((null items)
     (list (etaf--view-call 'text nil
                            (list (or empty-label "No data.")))))
    (t
     (etaf-ui--grid-rows
      controller items columns row-key row-ref on-row-press selected-key
      row-selected-p row-actions row-states theme))))

(defun etaf-ui--button-setup ()
  "Create the retained renderer for one Button instance."
  (let* ((current-callback nil)
         (current-press-p nil)
         (press nil))
    (setq press
          (lambda ()
            (when current-press-p
              (when current-callback
                (funcall current-callback)))))
    (lambda ()
      (let* ((label (etaf-current-prop :label))
             (callback (etaf-current-prop :on-press))
             (disabled (etaf-current-prop :disabled))
             (use (etaf-current-prop :use))
             (press-p (and (not disabled) (or callback use))))
        (setq current-callback callback
              current-press-p press-p)
        (let* ((variant (and (not disabled) (etaf-current-prop :variant)))
               (variant-values
                (etaf-ui--button-variant-values variant disabled)))
          (etaf-ui--button-view
           label (and press-p press) disabled (etaf-current-prop :ref)
           (etaf-current-prop :class)
           (or (etaf-current-prop :color)
               (plist-get variant-values :color))
           (or (etaf-current-prop :bgcolor)
               (plist-get variant-values :bgcolor))
           (or (etaf-current-prop :border)
               (plist-get variant-values :border))
           (etaf-current-prop :padding)
           (or (etaf-current-prop :font-weight)
               (plist-get variant-values :font-weight))
           (etaf-current-prop :tab-index)
           (etaf-current-prop :aria-label)
           use))))))

;;;###autoload
(etaf-define-component etaf-button
    (&key label on-press disabled ref class color bgcolor border padding font-weight
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
   ("&.disabled" :padding (0 1) :font-weight normal)
   ("&.enabled" :padding (0 1) :font-weight bold))
  :setup
  (etaf-ui--button-setup))

(etaf-define-component etaf-number-input
    (&key value label on-change ref disabled min max aria-label)
  "Render a controlled minibuffer-backed numeric input.

VALUE is displayed as a Button.  Activating it reads a number through
Emacs's native minibuffer, validates optional MIN and MAX bounds, and calls
ON-CHANGE with the accepted integer.  The Component owns prompting and
validation; the caller owns the value and subsequent state write."
  :setup
  (let ((callback (etaf-current-prop :on-change)))
    (lambda ()
      (let* ((value (etaf-current-prop :value))
             (label (or (etaf-current-prop :label) "Value"))
             (min-value (etaf-current-prop :min))
             (max-value (etaf-current-prop :max))
             (disabled (etaf-current-prop :disabled))
             (ref (etaf-current-prop :ref))
             (aria-label (etaf-current-prop :aria-label)))
        (etaf-view
         (button
          :label (format "%s %s ✎" label (or value "—"))
          :ref ref :disabled disabled
          :aria-label (or aria-label label)
          :variant 'ghost
          :on-press
          (unless disabled
            (lambda ()
              (let ((next (read-number
                           (format "%s: " label) (or value 0))))
                (unless (and (integerp next)
                             (or (null min-value) (>= next min-value))
                             (or (null max-value) (<= next max-value)))
                  (user-error "%s must be an integer from %s to %s"
                              label (or min-value "—") (or max-value "—")))
                (when callback (funcall callback next)))))))))))

(defun etaf-ui--checkbox-view
    (checked label on-change ref disabled class color bgcolor border padding
             font-weight tab-index aria-label)
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
    :color color :bgcolor bgcolor :border border :padding padding :font-weight font-weight
    :on-press on-change
    (box :class "etaf-checkbox-mark"
     (text (expr :value
                 (if (etaf-ui--reactive-value checked) "☑" "☐"))))
    (text (expr :value (if label (concat " " label) ""))))))

;;;###autoload
(etaf-define-component etaf-checkbox
    (&key checked label on-change ref disabled class color bgcolor border padding
          font-weight tab-index aria-label)
  "Render a controlled checkbox with CHECKED, LABEL, and ON-CHANGE.

CHECKED may be a boolean or an ETAF reactive source.  ON-CHANGE receives the
next boolean value.  State ownership stays with the caller, so the Component
works with local refs or Data-backed forms."
  :styles
  (styles
   ("&" :width max-content)
   ;; Color, background, and border are resolved through the shared semantic
   ;; Theme map in :setup; styles keep only geometry defaults.
   ("&.disabled" :padding (0 1))
   ("&.enabled" :padding (0 1))
   (".etaf-checkbox-mark" :font-weight bold :width 1))
  :setup
  (let* ((current-checked nil)
         (current-callback nil)
         (press
          (lambda ()
            (when current-callback
              (funcall current-callback
                       (not (etaf-ui--reactive-value current-checked)))))))
    (lambda ()
      (let* ((theme (etaf-ui-theme-tokens :ui-fg :ui-bg
                                          :ui-checkbox-enabled-fg
                                          :ui-checkbox-enabled-bg
                                          :ui-checkbox-enabled-border
                                          :ui-checkbox-disabled-fg
                                          :ui-checkbox-disabled-bg
                                          :ui-checkbox-disabled-border))
             (variant-values
              (etaf-ui--checkbox-variant-values
               theme (etaf-current-prop :disabled))))
        (setq current-checked (etaf-current-prop :checked)
            current-callback
            (when (and (not (etaf-current-prop :disabled))
                       (etaf-current-prop :on-change))
              (etaf-current-prop :on-change)))
        (etaf-ui--checkbox-view
         current-checked (etaf-current-prop :label)
         (and current-callback press)
         (etaf-current-prop :ref) (etaf-current-prop :disabled)
         (etaf-current-prop :class)
         (or (etaf-current-prop :color)
             (plist-get variant-values :color))
         (or (etaf-current-prop :bgcolor)
             (plist-get variant-values :bgcolor))
         (or (etaf-current-prop :border)
             (plist-get variant-values :border))
         (etaf-current-prop :padding) (etaf-current-prop :font-weight)
         (etaf-current-prop :tab-index) (etaf-current-prop :aria-label))))))

;;;###autoload
(etaf-define-component etaf-label
    (&key text font-weight class color bgcolor border padding ref width)
  "Render TEXT as a semantic label with presentation properties.
TEXT may be an ordinary value or an ETAF reactive source."
  :view
  (expr
   :value
   (if (or border padding width)
       (etaf-view
        (box :class class :font-weight font-weight :color color
             :bgcolor bgcolor :border border :padding padding
             :ref ref :width width
         (text (expr :value (etaf-ui--reactive-value text)))))
     (etaf-view
      (text :class class :font-weight font-weight :color color
            :bgcolor bgcolor :ref ref
            (expr :value (etaf-ui--reactive-value text)))))))

(defun etaf-ui--panel-view (title class color bgcolor border padding ref)
  "Render a themed Panel View.
Arguments are TITLE, CLASS, COLOR, BGCOLOR, BORDER, PADDING, and REF."
  (let ((theme (etaf-ui-theme-tokens :ui-panel-fg :ui-panel-bg
                                     :ui-panel-border)))
    (etaf-view
     (column
      :class (etaf-ui--class-value "etaf-panel" nil class)
      :color (or color (plist-get theme :ui-panel-fg))
      :bgcolor (or bgcolor (plist-get theme :ui-panel-bg))
      :border (or border
                  (etaf-ui--theme-border
                   (plist-get theme :ui-panel-border)))
      :padding padding :ref ref
      (expr
       :value
       (when title
         (etaf-view (text :class "etaf-panel-title"
                          (expr :value title)))))
      (slot :name 'header)
      (slot)))))

;;;###autoload
(etaf-define-component etaf-panel
    (&key title class color bgcolor border padding ref)
  "Render a titled panel with header and default slot projections."
  :styles
  (styles
   ("&" :padding (1 2))
   (".etaf-panel-title" :font-weight bold))
  :view
  (expr :value
        (etaf-ui--panel-view title class color bgcolor border padding ref)))

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
   (".etaf-data-grid-header" :font-weight bold :padding (0 1))
   (".etaf-data-grid-header-cell" :font-weight bold)
   (".etaf-data-grid-row" :padding (0 1))
   ;; Selection color and error color are dynamic semantic props below, so
  ;; this Component style scope contains geometry only.
   )
  :setup
  (let ((row-actions (make-hash-table :test #'equal))
        (row-states (make-hash-table :test #'equal))
        current-controller current-columns current-row-key current-row-ref
        current-on-row-press current-selected-key current-row-selected-p
        current-loading-label current-error-label current-empty-label
        body-config body-expr body-thunk body-range-snapshot body-range-item)
    (setq
     body-thunk
     (lambda ()
       (let* ((status
               (etaf-value (etaf-data-status current-controller)))
              (items
               (etaf-value (etaf-data-items current-controller)))
              (theme
               (etaf-ui-theme-tokens :ui-grid-border
                                     :ui-grid-selected-bg)))
         (etaf-ui--grid-body-items
          current-controller status items current-columns current-row-key
          current-row-ref current-on-row-press current-selected-key
          current-row-selected-p row-actions row-states theme
         current-loading-label current-error-label current-empty-label))))
    (setq
     body-range-snapshot
     (lambda ()
       (let ((status (etaf-value (etaf-data-status current-controller)))
             (items (etaf-value (etaf-data-items current-controller))))
         (when (and (eq status 'success) items)
           (let ((theme
                  (etaf-ui-theme-tokens :ui-grid-border
                                        :ui-grid-selected-bg)))
             (list
              :items
              (etaf-ui--grid-keyed-items
               items current-row-key row-actions row-states)
              :context theme))))))
    (setq
     body-range-item
     (lambda (entry theme)
       (let* ((key (car entry))
              (item (cdr entry))
              (state (etaf-ui--grid-row-state row-states key)))
         (etaf-ui--grid-row
          item key current-columns current-row-ref current-on-row-press
          current-selected-key current-row-selected-p
          (unless (or current-row-selected-p current-selected-key)
            (etaf-data-selected-ref current-controller key))
          row-actions theme (car state) (cdr state)))))
    (lambda ()
      (let* ((controller (etaf-current-prop :controller))
             (columns (etaf-current-prop :columns))
             (row-key (etaf-current-prop :row-key))
             (row-ref (etaf-current-prop :row-ref))
             (on-row-press (etaf-current-prop :on-row-press))
             (selected-key (etaf-current-prop :selected-key))
             (row-selected-p (etaf-current-prop :row-selected-p))
             (loading-label (etaf-current-prop :loading-label))
             (error-label (etaf-current-prop :error-label))
             (empty-label (etaf-current-prop :empty-label))
             (config
              (list controller columns row-key row-ref on-row-press
                    selected-key row-selected-p loading-label error-label
                    empty-label))
             (theme (etaf-ui-theme-tokens :ui-fg :ui-grid-border))
             (theme-color (plist-get theme :ui-fg)))
        (unless (eq controller current-controller)
          (clrhash row-actions)
          (clrhash row-states))
        (setq current-controller controller
              current-columns columns
              current-row-key row-key
              current-row-ref row-ref
              current-on-row-press on-row-press
              current-selected-key selected-key
              current-row-selected-p row-selected-p
              current-loading-label loading-label
              current-error-label error-label
              current-empty-label empty-label)
        (unless (equal-including-properties config body-config)
          (setq body-config (copy-tree config)
                body-expr
                (etaf--expr-create
                 :token (gensym "etaf-data-grid-body-")
                 :thunk body-thunk
                 :range-snapshot body-range-snapshot
                 :range-key #'car
                 :range-item body-range-item)))
        (etaf--view-call
         'column
         (list :class "etaf-data-grid" :color theme-color)
         (list
          (etaf-ui--grid-header columns theme)
          (etaf--view-call
           'column (list :class "etaf-data-grid-body")
           (list body-expr))
          (etaf--slot-projection-create
           :name 'footer :token 'etaf-ui-data-grid-footer :fallback nil)))))))

;;;###autoload
(etaf-define-component etaf-pagination
    (&key controller previous-ref next-ref class color bgcolor border padding
          aria-label)
  "Render a compact, accessible pager for DATA CONTROLLER.

The pager owns no data state: page, page-size, total, loading, and error stay
with CONTROLLER.  PREVIOUS-REF and NEXT-REF should be stable public refs when
the pager participates in keyboard/mouse interaction.  The visible glyphs
(`←' and `→') are paired with labels and help text so the compact control is
readable in both GUI and text review."
  :styles
  (styles
   ("&" :width stretch)
   (".etaf-pagination-label" :font-weight bold))
  :setup
  (let* ((current-controller nil)
         (current-parent-color nil)
         (current-parent-bgcolor nil)
         (page-value
          (lambda ()
            (max 1 (or (etaf-value
                        (etaf-data-page current-controller))
                       1))))
         (page-size-value
          (lambda ()
            (max 1 (or (etaf-value
                        (etaf-data-page-size current-controller))
                       1))))
         (total-value
          (lambda ()
            (max 0 (or (etaf-value
                        (etaf-data-total current-controller))
                       0))))
         (pages-value
          (lambda ()
            (max 1 (ceiling (/ (float (funcall total-value))
                               (funcall page-size-value))))))
         (loading-p
          (lambda ()
            (eq (etaf-value (etaf-data-status current-controller))
                'loading)))
         (previous-disabled
          (lambda ()
            (or (funcall loading-p) (<= (funcall page-value) 1))))
         (next-disabled
          (lambda ()
            (or (funcall loading-p)
                (>= (funcall page-value) (funcall pages-value)))))
         (previous
          (lambda ()
            (when (and current-controller
                       (not (funcall previous-disabled)))
              (etaf-data-previous-page current-controller))))
         (next
          (lambda ()
            (when (and current-controller
                       (not (funcall next-disabled)))
              (etaf-data-next-page current-controller)))))
    (lambda ()
      (let* ((controller-value (etaf-current-prop :controller))
             (theme (etaf-ui-theme-tokens :ui-fg :ui-bg
                                          :ui-disabled-fg
                                          :ui-pagination-muted-fg))
             (parent-color (or (etaf-current-prop :color)
                               (plist-get theme :ui-fg)))
             (parent-bgcolor (or (etaf-current-prop :bgcolor)
                                 (plist-get theme :ui-bg)))
             (arrow-border '((0) solid "transparent")))
        (setq current-controller controller-value
              current-parent-color parent-color
              current-parent-bgcolor parent-bgcolor)
        (etaf-view
         (flex
               :class (etaf-ui--class-value "etaf-pagination" nil
                                            (etaf-current-prop :class))
               :width 'stretch
               :flex-direction 'row
               :align-items 'center
               :role 'navigation
               :aria-label (or (etaf-current-prop :aria-label) "Pagination")
               :color parent-color
               :bgcolor parent-bgcolor
               :border (etaf-current-prop :border)
               :box-sizing 'border-box
               :padding (or (etaf-current-prop :padding) '(0 1))
               :gap '(0 (1))
          (column :width 'max-content
                  :flex-grow 0 :flex-shrink 0 :flex-basis 'auto
           (button :label "←" :ref (etaf-current-prop :previous-ref)
                   :aria-label "Previous page"
                   :disabled (funcall previous-disabled)
                   :padding '(0 0)
                   :border arrow-border
                   :color (if (funcall previous-disabled)
                              (plist-get theme :ui-disabled-fg)
                            current-parent-color)
                   :bgcolor current-parent-bgcolor
                   :font-weight 'bold
                   :on-press previous))
          (column
               :flex-grow 1 :flex-shrink 1 :flex-basis '(0) :min-width 0
           (box :class "etaf-pagination-label" :text-align 'center
                :wrap-mode 'none :min-width 'max-content
            (text
             (expr :value
                   (format "Page %d / %d"
                           (funcall page-value)
                           (funcall pages-value)))))
           (box :class "etaf-pagination-summary" :text-align 'center
                :color (plist-get theme :ui-pagination-muted-fg)
                :wrap-mode 'none :min-width 'max-content
            (text
             (expr :value
                   (let* ((page (funcall page-value))
                          (page-size (funcall page-size-value))
                          (total (funcall total-value))
                          (first-item
                           (if (zerop total)
                               0
                             (1+ (* (1- page) page-size))))
                          (last-item (min total (* page page-size))))
                     (format "%d–%d of %d"
                             first-item last-item total))))))
          (column :width 'max-content
                  :flex-grow 0 :flex-shrink 0 :flex-basis 'auto
           (button :label "→" :ref (etaf-current-prop :next-ref)
                   :aria-label "Next page"
                   :disabled (funcall next-disabled)
                   :padding '(0 0)
                   :border arrow-border
                   :color (if (funcall next-disabled)
                              (plist-get theme :ui-disabled-fg)
                            current-parent-color)
                   :bgcolor current-parent-bgcolor
                   :font-weight 'bold
                   :on-press next))))))))

(provide 'etaf-ui)

;;; etaf-ui.el ends here
