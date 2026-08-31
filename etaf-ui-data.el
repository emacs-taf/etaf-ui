;;; etaf-ui-data.el --- Data-aware ETAF UI Components -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; DataGrid and Pagination adapt ETAF Data Controller state onto basic
;; Components.  They do not duplicate Table or Button behavior.

;;; Code:

(require 'etaf-ui-table)

(declare-function etaf-data-status "etaf-data" (controller))
(declare-function etaf-data-items "etaf-data" (controller))
(declare-function etaf-data-page "etaf-data" (controller))
(declare-function etaf-data-page-size "etaf-data" (controller))
(declare-function etaf-data-total "etaf-data" (controller))
(declare-function etaf-data-previous-page "etaf-data" (controller))
(declare-function etaf-data-next-page "etaf-data" (controller))
(declare-function etaf-data-selected-ref "etaf-data" (controller identity))
(declare-function etaf-data-item-identity "etaf-data" (controller item))

(defun etaf-ui--data-grid-default-row-ref (controller row)
  "Return a stable internal Host reference for CONTROLLER ROW.

DataGrid owns this fallback so the presentational Table can keep its stricter
interactive-row contract.  The controller's validated item identity is the
only input, making the reference stable across keyed Range updates."
  (intern (format "etaf-data-grid-row-%s"
                 (etaf-data-item-identity
                  controller row))))

(defun etaf-ui--data-grid-row-ref (row-ref on-row-press controller row)
  "Return a validated stable Host reference for interactive ROW.

An explicit ROW-REF remains caller-owned.  Interactive grids without one use
the CONTROLLER identity fallback; when ON-ROW-PRESS is nil, rows have no Host
reference."
  (when on-row-press
    (let ((ref (if row-ref
                   (funcall row-ref row)
                 (etaf-ui--data-grid-default-row-ref controller row))))
      (unless ref
        (error "ETAF DataGrid :row-ref must return a non-nil stable ref"))
      ref)))

(defun etaf-ui--data-grid-row-action (cache key row callback)
  "Return CACHE's stable press action for row KEY.

The vector is retained by DataGrid setup state; only its current ROW and
CALLBACK change across renders.  Unchanged keyed rows therefore keep the same
handler identity and avoid rebuilding behavior resources."
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

(defun etaf-ui--data-grid-row-selected-p (controller row row-selected-p)
  "Return whether ROW is selected in CONTROLLER or by ROW-SELECTED-P."
  (or (and row-selected-p (funcall row-selected-p row))
      (etaf-value
       (etaf-data-selected-ref
        controller (etaf-data-item-identity controller row)))))

(defun etaf-ui--data-grid-row
    (controller entry columns row-ref on-row-press row-selected-p row-actions
                theme)
  "Return one retained DataGrid row for keyed ENTRY.
CONTROLLER owns selection identity; ROW-REF, ON-ROW-PRESS, and ROW-SELECTED-P
define the interaction contract.  ROW-ACTIONS retains callback identity, and
THEME is the resolved table-paint snapshot for this item."
  (let* ((key (car entry))
         (row (cdr entry))
         (border-color (plist-get theme :ui-table-border))
         (selected-p
          (etaf-ui--data-grid-row-selected-p
           controller row row-selected-p)))
    (unless key
      (error "ETAF DataGrid row-key must return a non-nil stable scalar"))
    (etaf-node
     'row
     (list :key key
           :class (concat "etaf-table-row" (when selected-p " selected"))
           :ref (etaf-ui--data-grid-row-ref
                 row-ref on-row-press controller row)
           :role (when on-row-press 'button)
           :tab-index (when on-row-press 0)
           :color (when selected-p
                    (plist-get theme :ui-table-selected-fg))
           :background-color (when selected-p
                               (plist-get theme :ui-table-selected-bg))
           :border-bottom-width 1
           :border-bottom-style 'solid
           :border-bottom-color border-color
           :on-press
           (and on-row-press
                (etaf-ui--data-grid-row-action
                 row-actions key row on-row-press)))
     (etaf-ui--table-cells row columns border-color))))

(defun etaf-ui--data-grid-state-label (key text &optional class color)
  "Return TEXT as a non-row DataGrid state label identified by KEY.
CLASS and COLOR optionally style the label."
  (etaf-node 'etaf-label
             (list :key key :text text :class class :color color)
             nil))

(defun etaf-ui--data-grid-body-entries
    (controller row-key loading-label error-label empty-label)
  "Return public keyed Range entries for CONTROLLER and labels.
ROW-KEY identifies successful rows.  Loading, error, and empty states use one
stable sentinel entry so every body state remains below the same Range.
LOADING-LABEL, ERROR-LABEL, and EMPTY-LABEL override default state text."
  (let* ((status (etaf-value (etaf-data-status controller)))
         (items (etaf-value (etaf-data-items controller))))
    (cond
     ((and (eq status 'success) items)
      (etaf-ui--table-entries items row-key))
     ((and (eq status 'loading) (null items))
      (list (cons 'loading
                  (list :etaf-data-grid-state 'loading
                        :text (or loading-label "Loading...")))))
     ((and (eq status 'error) (null items))
      (list (cons 'error
                  (list :etaf-data-grid-state 'error
                        :text (or error-label "Unable to load data.")))))
     (t
      (list (cons 'empty
                  (list :etaf-data-grid-state 'empty
                        :text (or empty-label "No data."))))))))

(defun etaf-ui--data-grid-state-entry-node (entry)
  "Return the state label View represented by keyed ENTRY."
  (let* ((state (cdr entry))
         (kind (plist-get state :etaf-data-grid-state))
         (theme (and (eq kind 'error)
                     (etaf-ui--style-tokens :ui-data-grid-error-fg))))
    (etaf-ui--data-grid-state-label
     kind (plist-get state :text)
     (when (eq kind 'error) "etaf-data-grid-error")
     (and theme (plist-get theme :ui-data-grid-error-fg)))))

(etaf-define-component etaf-ui--data-grid-body-item
    (&key controller entry columns row-ref on-row-press row-selected-p
          row-actions)
  "Render one retained keyed DataGrid ENTRY with a cached row action."
  :view
  (expr
   (if (plist-get (cdr entry) :etaf-data-grid-state)
       (etaf-ui--data-grid-state-entry-node entry)
     (etaf-ui--data-grid-row
      controller entry columns row-ref on-row-press row-selected-p row-actions
      (etaf-ui--style-tokens
       :ui-table-border :ui-table-selected-fg :ui-table-selected-bg)))))

;;;###autoload
(etaf-define-component etaf-data-grid
    (&key controller columns row-key on-row-press row-ref row-selected-p
          loading-label error-label empty-label)
  "Render DATA CONTROLLER state through the public Component DSL.

DataGrid owns loading, error, empty, and controller-selection adaptation.
Its keyed Range retains row identity across insert, reorder, and update; setup
state only caches stable row action closures."
  :setup (list :row-actions (make-hash-table :test #'equal))
  :view
  (column
   :class "etaf-data-grid etaf-table"
   :color (plist-get (etaf-ui--style-tokens :ui-fg) :ui-fg)
   (etaf-ui--table-header :columns columns)
   (column
    :class "etaf-table-body"
    (etaf-ui--data-grid-body-item
     :for (entry
           (etaf-ui--data-grid-body-entries
            controller row-key loading-label error-label empty-label))
     :key (car entry)
     :controller controller :entry entry :columns columns
     :row-ref row-ref :on-row-press on-row-press
     :row-selected-p row-selected-p
     :row-actions (plist-get (etaf-state) :row-actions)))
   (slot :name 'footer)))

;;;###autoload
(etaf-define-component etaf-pagination
    (&key controller previous-ref next-ref class color bgcolor border padding
          aria-label)
  "Render a controlled pager for DATA CONTROLLER with retained controls."
  :setup
  (let* ((state (list :controller nil))
         (page-value
          (lambda ()
            (let ((controller (plist-get state :controller)))
              (max 1 (or (and controller
                               (etaf-value (etaf-data-page controller)))
                          1)))))
         (page-size-value
          (lambda ()
            (let ((controller (plist-get state :controller)))
              (max 1 (or (and controller
                               (etaf-value (etaf-data-page-size controller)))
                          1)))))
         (total-value
          (lambda ()
            (let ((controller (plist-get state :controller)))
              (max 0 (or (and controller
                               (etaf-value (etaf-data-total controller)))
                          0)))))
         (pages-value
          (lambda ()
            (max 1 (ceiling (/ (float (funcall total-value))
                               (funcall page-size-value))))))
         (loading-p
          (lambda ()
            (let ((controller (plist-get state :controller)))
              (and controller
                   (eq (etaf-value (etaf-data-status controller))
                       'loading)))))
         (previous-disabled
          (lambda ()
            (or (funcall loading-p) (<= (funcall page-value) 1))))
         (next-disabled
          (lambda ()
            (or (funcall loading-p)
                (>= (funcall page-value) (funcall pages-value)))))
         (previous
          (lambda ()
            (let ((controller (plist-get state :controller)))
              (when (and controller
                         (not (funcall previous-disabled)))
                (etaf-data-previous-page controller)))))
         (next
          (lambda ()
            (let ((controller (plist-get state :controller)))
              (when (and controller
                         (not (funcall next-disabled)))
                (etaf-data-next-page controller))))))
    (plist-put state :page-value page-value)
    (plist-put state :page-size-value page-size-value)
    (plist-put state :total-value total-value)
    (plist-put state :pages-value pages-value)
    (plist-put state :loading-p loading-p)
    (plist-put state :previous-disabled previous-disabled)
    (plist-put state :next-disabled next-disabled)
    (plist-put state :previous previous)
    (plist-put state :next next)
    state)
  :render
  (let* ((state (etaf-state))
         (controller-value controller))
    (setf (plist-get state :controller) controller-value)
    (let* ((theme (etaf-ui--style-tokens
                   :ui-fg :ui-bg :ui-disabled-fg
                   :ui-pagination-muted-fg))
           (parent-color (or color (plist-get theme :ui-fg)))
           (parent-bgcolor (or bgcolor (plist-get theme :ui-bg)))
           (arrow-border (or border '(0 solid "transparent")))
           (page (funcall (plist-get state :page-value)))
           (page-size (funcall (plist-get state :page-size-value)))
           (total (funcall (plist-get state :total-value)))
           (pages (funcall (plist-get state :pages-value)))
           (previous-disabled
            (funcall (plist-get state :previous-disabled)))
           (next-disabled
            (funcall (plist-get state :next-disabled)))
           (first-item (if (zerop total) 0
                         (1+ (* (1- page) page-size))))
           (last-item (min total (* page page-size))))
      (etaf-node
       'flex
       (list :class (etaf-ui--class-value "etaf-pagination" nil class)
             :width 'stretch :flex-direction 'row :align-items 'center
             :role 'navigation :aria-label (or aria-label "Pagination")
             :color parent-color :background-color parent-bgcolor
             :box-sizing 'border-box :padding (or padding '(0 1))
             :gap '(0 (1)))
       (list
        (etaf-node
         'column
         (list :width 'max-content
               :flex-grow 0 :flex-shrink 0 :flex-basis 'auto)
         (list
          (etaf-node
           'etaf-button
           (list :label "←" :ref previous-ref
                 :aria-label "Previous page"
                 :disabled previous-disabled :padding '(0 0)
                 :border arrow-border
                 :color (if previous-disabled
                            (plist-get theme :ui-disabled-fg)
                          parent-color)
                 :background-color parent-bgcolor :font-weight 'bold
                 :on-press (plist-get state :previous))
           nil)))
        (etaf-node
         'column
         (list :flex-grow 1 :flex-shrink 1 :flex-basis '(0) :min-width 0)
         (list
          (etaf-node
           'box
           (list :class "etaf-pagination-label" :text-align 'center
                 :wrap-mode 'none :min-width 'max-content)
           (list (format "Page %d / %d" page pages)))
          (etaf-node
           'box
           (list :class "etaf-pagination-summary" :text-align 'center
                 :color (plist-get theme :ui-pagination-muted-fg)
                 :wrap-mode 'none :min-width 'max-content)
           (list (format "%d–%d of %d" first-item last-item total)))))
        (etaf-node
         'column
         (list :width 'max-content
               :flex-grow 0 :flex-shrink 0 :flex-basis 'auto)
         (list
          (etaf-node
           'etaf-button
           (list :label "→" :ref next-ref
                 :aria-label "Next page"
                 :disabled next-disabled :padding '(0 0)
                 :border arrow-border
                 :color (if next-disabled
                            (plist-get theme :ui-disabled-fg)
                          parent-color)
                 :background-color parent-bgcolor :font-weight 'bold
                 :on-press (plist-get state :next))
           nil)))))))
  :styles
  (styles
   ("&" :width stretch)
   (".etaf-pagination-label" :font-weight bold)))

(provide 'etaf-ui-data)
;;; etaf-ui-data.el ends here
