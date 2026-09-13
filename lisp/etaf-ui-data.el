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

(defun etaf-ui--data-grid-default-row-ref (state controller row)
  "Return STATE's stable internal Host reference for CONTROLLER and ROW.

The controller's validated item identity is the row input.  Like Table's
retained row references, per-instance uninterned symbols prevent cross-grid
collisions and avoid process-global symbol-table growth."
  (let* ((identity (etaf-data-item-identity controller row))
         (cache (plist-get state :row-refs))
         (stage (plist-get state :row-ref-stage))
         (ref (or (gethash identity cache)
                  (and (hash-table-p stage) (gethash identity stage)))))
    (unless ref
      (unless (hash-table-p stage)
        (error "ETAF DataGrid row ref changed outside a keyed candidate"))
      (setq ref (make-symbol (format "etaf-data-grid-row-%s" identity)))
      (puthash identity ref stage))
    ref))

(defun etaf-ui--data-grid-row-ref
    (state row-ref on-row-press controller row)
  "Return a validated stable Host reference for interactive ROW.

An explicit ROW-REF remains caller-owned.  Interactive grids without one use
STATE's CONTROLLER identity fallback; when ON-ROW-PRESS is nil, rows have no
Host reference."
  (when on-row-press
    (let ((ref (if row-ref
                   (funcall row-ref row)
                 (etaf-ui--data-grid-default-row-ref
                  state controller row))))
      (unless ref
        (error "ETAF DataGrid :row-ref must return a non-nil stable ref"))
      ref)))

(defun etaf-ui--data-grid-row-action-entry ()
  "Return one committed-state cell and stable DataGrid handler."
  (let (entry)
    (setq entry (vector nil nil nil))
    (aset entry 2
          (lambda ()
            (let ((current (aref entry 1)))
              (when current
                (funcall current (aref entry 0))))))
    entry))

(defun etaf-ui--data-grid-row-action (state key row callback)
  "Return STATE's stable action for row KEY, staging ROW and CALLBACK.

Committed handlers read only committed cells.  Candidate rendering writes a
private stage that lifecycle hooks promote after successful publication."
  (let* ((cache (plist-get state :row-actions))
         (stage (plist-get state :row-action-stage))
         (committed (gethash key cache)))
    (if (and committed
             (equal-including-properties row (aref committed 0))
             (eq callback (aref committed 1)))
        (aref committed 2)
      (unless (hash-table-p stage)
        (error "ETAF DataGrid handler changed outside a keyed candidate"))
      (let* ((proposal (gethash key stage))
             (entry (or committed (and proposal (aref proposal 0))
                        (etaf-ui--data-grid-row-action-entry))))
        (puthash key (vector entry row callback) stage)
        (aref entry 2)))))

(defun etaf-ui--data-grid-promote-row-actions (state)
  "Promote STATE's staged row actions/refs and prune non-live keys."
  (let ((stage (plist-get state :row-action-stage))
        (live (plist-get state :row-action-live-keys))
        (cache (plist-get state :row-actions))
        (prune-p (plist-get state :row-cache-prune-p)))
    (when (and (hash-table-p stage) (hash-table-p live))
      (maphash
       (lambda (key proposal)
         (let ((entry (aref proposal 0)))
           (aset entry 0 (aref proposal 1))
           (aset entry 1 (aref proposal 2))
           (puthash key entry cache)))
       stage)
      (when prune-p
        (let (removed)
          (maphash (lambda (key _entry)
                     (unless (gethash key live) (push key removed)))
                   cache)
          (dolist (key removed) (remhash key cache))))
      (setf (plist-get state :row-action-stage) nil
            (plist-get state :row-action-live-keys) nil)))
  (let ((stage (plist-get state :row-ref-stage))
        (live (plist-get state :row-ref-live-identities))
        (cache (plist-get state :row-refs))
        (prune-p (plist-get state :row-cache-prune-p)))
    (when (and (hash-table-p stage) (hash-table-p live))
      (maphash (lambda (identity ref) (puthash identity ref cache)) stage)
      (when prune-p
        (let (removed)
          (maphash (lambda (identity _ref)
                     (unless (gethash identity live)
                       (push identity removed)))
                   cache)
          (dolist (identity removed) (remhash identity cache))))
      (setf (plist-get state :row-ref-stage) nil
            (plist-get state :row-ref-live-identities) nil
            (plist-get state :row-cache-prune-p) nil)))
  state)

(defun etaf-ui--data-grid-dispose-row-actions (state)
  "Release all committed and staged row actions in STATE."
  (clrhash (plist-get state :row-actions))
  (clrhash (plist-get state :row-refs))
  (setf (plist-get state :row-action-stage) nil
        (plist-get state :row-action-live-keys) nil
        (plist-get state :row-ref-stage) nil
        (plist-get state :row-ref-live-identities) nil
        (plist-get state :row-cache-prune-p) nil)
  state)

(defun etaf-ui--data-grid-row-selected-p (controller row row-selected-p)
  "Return whether ROW is selected in CONTROLLER or by ROW-SELECTED-P."
  (or (and row-selected-p (funcall row-selected-p row))
      (etaf-value
       (etaf-data-selected-ref
        controller (etaf-data-item-identity controller row)))))

(defun etaf-ui--data-grid-row
    (state controller entry columns row-ref on-row-press row-selected-p theme)
  "Return one retained DataGrid row for keyed ENTRY.
CONTROLLER owns selection identity; ROW-REF, ON-ROW-PRESS, and ROW-SELECTED-P
define the interaction contract.  STATE retains callback identity and stages
candidate values; THEME is the resolved table-paint snapshot for this item."
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
                 state row-ref on-row-press controller row)
           :role (when on-row-press 'button)
           :tab-index (when on-row-press 0)
           :color (when selected-p
                    (plist-get theme :ui-table-selected-fg))
           :background-color (when selected-p
                               (plist-get theme :ui-table-selected-bg))
           :border-bottom-width '(px 1)
           :border-bottom-style 'solid
           :border-bottom-color border-color
           :on-press
           (and on-row-press
                (etaf-ui--data-grid-row-action
                 state key row on-row-press)))
     (etaf-ui--table-row-children row columns))))

(defun etaf-ui--data-grid-state-label (key text &optional class color)
  "Return TEXT as a non-row DataGrid state label identified by KEY.
CLASS and COLOR optionally style the label."
  (etaf-node 'etaf-label
             (list :key key :text text :class class :color color)
             nil))

(defun etaf-ui--data-grid-body-entries
    (state controller row-key on-row-press row-ref
           loading-label error-label empty-label)
  "Return keyed Range entries and begin STATE's candidate action stage.
CONTROLLER and ROW-KEY identify successful rows.  ON-ROW-PRESS and ROW-REF
determine which current keys retain committed handlers and fallback refs.
LOADING-LABEL, ERROR-LABEL, and EMPTY-LABEL override the state text."
  (let* ((status (etaf-value (etaf-data-status controller)))
         (items (etaf-value (etaf-data-items controller)))
         (entries
          (cond
           ((eq status 'loading)
            (list (cons 'loading
                        (list :etaf-data-grid-state 'loading
                              :text (or loading-label "Loading...")))))
           ((eq status 'error)
            (list (cons 'error
                        (list :etaf-data-grid-state 'error
                              :text (or error-label
                                        "Unable to load data.")))))
           (items (etaf-ui--table-entries items row-key))
           (t
            (list (cons 'empty
                        (list :etaf-data-grid-state 'empty
                              :text (or empty-label "No data.")))))))
         (stage (make-hash-table :test #'equal))
         (live (make-hash-table :test #'equal))
         (ref-stage (make-hash-table :test #'equal))
         (ref-live (make-hash-table :test #'equal)))
    (when (and on-row-press items (not (memq status '(loading error))))
      (dolist (entry entries) (puthash (car entry) t live))
      (unless row-ref
        (dolist (row items)
          (puthash (etaf-data-item-identity controller row) t ref-live))))
    (setf (plist-get state :row-action-stage) stage
          (plist-get state :row-action-live-keys) live
          (plist-get state :row-ref-stage) ref-stage
          (plist-get state :row-ref-live-identities) ref-live
          (plist-get state :row-cache-prune-p)
          (not (memq status '(loading error))))
    entries))

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

(etaf-ui--define-component etaf-ui--data-grid-body-item
    (&key controller entry columns row-ref on-row-press row-selected-p
          grid-state)
  "Render one retained keyed DataGrid ENTRY with a cached row action."
  :render
  (if (plist-get (cdr entry) :etaf-data-grid-state)
      (etaf-ui--data-grid-state-entry-node entry)
    (etaf-ui--data-grid-row
     grid-state controller entry columns row-ref on-row-press row-selected-p
     (etaf-ui--style-tokens
      :ui-table-border :ui-table-selected-fg :ui-table-selected-bg))))

(etaf-ui--define-component etaf-data-grid
    (&key controller columns row-key on-row-press row-ref row-selected-p
          loading-label error-label empty-label)
  "Render DATA CONTROLLER state through the public Component DSL.

DataGrid owns loading, error, empty, and controller-selection adaptation.
Its keyed Range retains row identity across insert, reorder, and update.
Setup state owns per-instance fallback refs plus commit-staged stable row
actions; failed candidates cannot mutate committed handler inputs.  COLUMNS
use Table's unique keys and optional `:cell' row-to-View functions."
  :setup
  (let ((state
         (list :row-actions (make-hash-table :test #'equal)
               :row-action-stage nil
               :row-action-live-keys nil
               :row-refs (make-hash-table :test #'equal)
               :row-ref-stage nil
               :row-ref-live-identities nil
               :row-cache-prune-p nil)))
    (etaf-on-mounted
     (lambda () (etaf-ui--data-grid-promote-row-actions state)))
    (etaf-on-updated
     (lambda () (etaf-ui--data-grid-promote-row-actions state)))
    (etaf-on-unmounted
     (lambda () (etaf-ui--data-grid-dispose-row-actions state)))
    state)
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
            (etaf-state) controller row-key on-row-press row-ref
            loading-label error-label empty-label))
     :key (car entry)
     :controller controller :entry entry :columns columns
     :row-ref row-ref :on-row-press on-row-press
     :row-selected-p row-selected-p
     :grid-state (etaf-state)))
   (slot :name 'footer)))

(etaf-ui--define-component etaf-pagination
    (&key controller previous-ref next-ref previous-label next-label
          class color bgcolor border padding aria-label)
  "Render a controlled pager whose callbacks follow its committed CONTROLLER.
PREVIOUS-LABEL and NEXT-LABEL override the complete Button captions.
Each Button captures its render's Controller; Runtime publishes that callback
together with the visible control after a successful render."
  :render
  (let ((controller-value controller))
    (let* ((theme (etaf-ui--style-tokens
                   :ui-fg :ui-bg :ui-pagination-muted-fg))
           (parent-color (or color (plist-get theme :ui-fg)))
           (parent-bgcolor (or bgcolor (plist-get theme :ui-bg)))
           (page (max 1 (or (and controller-value
                                 (etaf-value (etaf-data-page controller-value)))
                            1)))
           (page-size
            (max 1 (or (and controller-value
                            (etaf-value (etaf-data-page-size controller-value)))
                       1)))
           (total (max 0 (or (and controller-value
                                  (etaf-value (etaf-data-total controller-value)))
                             0)))
           (pages (max 1 (ceiling (/ (float total) page-size))))
           (loading-p (and controller-value
                           (eq (etaf-value (etaf-data-status controller-value))
                               'loading)))
           (previous-disabled (or loading-p (<= page 1)))
           (next-disabled (or loading-p (>= page pages)))
           (first-item (if (zerop total) 0
                         (1+ (* (1- page) page-size))))
           (last-item (min total (* page page-size))))
      (etaf-node
       'flex
       (list :class (etaf-ui--class-value "etaf-pagination" nil class)
             :width 'stretch :flex-direction 'row :align-items 'center
             :flex-wrap 'wrap :justify-content 'center
             :role 'navigation :aria-label (or aria-label "Pagination")
             :color parent-color :background-color parent-bgcolor
             :box-sizing 'border-box :padding (or padding '((lh 0) (ch 1)))
             :gap '((lh 1) (px 16)))
       (list
        (etaf-node
         'column
         (list :width 'max-content
               :flex-grow 0 :flex-shrink 0 :flex-basis 'auto)
         (list
          (etaf-node
           'etaf-button
           (list :label (or previous-label "‹ Previous") :ref previous-ref
                 :aria-label "Previous page"
                 :disabled previous-disabled :padding '((lh 0) (ch 2))
                 :variant 'secondary :border border
                 :color (and (not previous-disabled) color) :bgcolor bgcolor
                 :on-press
                 (lambda () (etaf-data-previous-page controller-value)))
           nil)))
        (etaf-node
         'column
         (list :width 'max-content
               :flex-grow 0 :flex-shrink 0 :flex-basis 'auto)
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
           (list :label (or next-label "Next ›") :ref next-ref
                 :aria-label "Next page"
                 :disabled next-disabled :padding '((lh 0) (ch 2))
                 :variant 'secondary :border border
                 :color (and (not next-disabled) color) :bgcolor bgcolor
                 :on-press
                 (lambda () (etaf-data-next-page controller-value)))
           nil)))))))
  :styles
  (("&" :width stretch)
   (".etaf-pagination-label" :font-weight bold)))

(provide 'etaf-ui-data)
;;; etaf-ui-data.el ends here
