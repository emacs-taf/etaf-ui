;;; etaf-ui-desktop.el --- Reusable desktop navigation Components -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Presentational Components used by desktop hosts and application shells.
;; These Components deliberately keep all selection, workspace, window and
;; layout state in their callers.  They expose ordinary ETAF callbacks and
;; Behaviors, so a desktop policy can use the same controls in floating and
;; tiled layouts without creating another input or focus system.

;;; Code:

(require 'cl-lib)
(require 'etaf-ui-basic)
(require 'etaf-ui-surface)
(require 'etaf-ui-style)

(defun etaf-ui--desktop-scalar-key-p (key)
  "Return non-nil when desktop navigation KEY is a stable scalar."
  (or (symbolp key) (stringp key) (numberp key)))

(defun etaf-ui--desktop-items (items component &optional title-key)
  "Validate desktop ITEM plists for COMPONENT and return them.
TITLE-KEY is the plist key used for the visible caption, defaulting to
`:label'.  An optional :description is accepted for launcher/switcher rows."
  (let ((title-key (or title-key :label)) keys)
    (etaf-check-prop :items items (proper-list-p items)
                     "a list of item plists" component)
    (dolist (item items)
      (etaf-check-prop
       :items item
       (and (proper-list-p item)
            (zerop (% (length item) 2))
            (plist-member item :key)
            (etaf-ui--desktop-scalar-key-p (plist-get item :key))
            (stringp (plist-get item title-key))
            (not (string-empty-p (plist-get item title-key)))
            (not (member (plist-get item :key) keys))
            (or (null (plist-get item :description))
                (stringp (plist-get item :description)))
            (or (null (plist-get item :ref))
                (symbolp (plist-get item :ref))))
       "items with unique scalar :key and nonempty caption" component)
      (push (plist-get item :key) keys))
    items))

(defun etaf-ui--desktop-item-caption (item title-key)
  "Return ITEM's TITLE-KEY caption.

State is communicated by the surrounding button presentation.  Keeping the
caption free of marker glyphs avoids a noisy taskbar and leaves the text width
stable as focus changes."
  (plist-get item title-key))

(etaf-define-component etaf-taskbar
    (&key items active on-select on-launch (launcher-label "Applications") class)
  "Render a controlled TASKBAR for desktop windows.

ITEMS are plists with scalar :key and nonempty string :label.  Optional
:state is `active', `minimized', `error' or nil and :disabled suppresses
activation.  ACTIVE may be a value or ref and marks the focused item.  The
caller owns all window state; ON-SELECT receives an item key and ON-LAUNCH,
when supplied, opens the caller's launcher."
  :validate
  (progn
    (etaf-ui--desktop-items items 'etaf-taskbar)
    (dolist (item items)
      (etaf-check-prop :disabled (plist-get item :disabled)
                       (booleanp (plist-get item :disabled)) "a boolean"
                       'etaf-taskbar)
      (etaf-check-prop :state (plist-get item :state)
                       (memq (plist-get item :state) '(nil active minimized error))
                       "nil, active, minimized or error" 'etaf-taskbar))
    (etaf-check-prop :active active
                     (or (null active) (etaf-ui--reactive-value active)
                         (cl-some (lambda (item)
                                   (equal (etaf-ui--reactive-value active)
                                          (plist-get item :key))) items))
                     "a taskbar key or nil" 'etaf-taskbar)
    (etaf-check-prop :on-select on-select
                     (or (null on-select) (functionp on-select))
                     "a function or nil" 'etaf-taskbar)
    (etaf-check-prop :on-launch on-launch
                     (or (null on-launch) (functionp on-launch))
                     "a function or nil" 'etaf-taskbar)
    (etaf-check-prop :launcher-label launcher-label (stringp launcher-label)
                     "a string" 'etaf-taskbar))
  :render
  (let ((active (etaf-ui--reactive-value active)))
    (etaf-node
     'row
     (list :class (etaf-ui--class-value "etaf-taskbar" nil class)
           :role 'toolbar :aria-label "Taskbar" :width 'stretch
           :height '(lh 1) :item-gap '(ch 0.5)
           :padding '((lh 0) (ch 1))
           :background-color "#F7F9FC"
           :color "#243447"
           :border '((px 1) solid "#D8E1EA"))
     (append
      (when on-launch
         (list (etaf-node 'etaf-button
                         (list :label launcher-label
                               :aria-label launcher-label :variant 'ghost
                               :class "etaf-taskbar-launcher"
                               :color "#29435C" :bgcolor "#E5EEF7"
                               :border '((px 1) solid "#C3D3E2")
                               :padding '((lh 0) (ch 1))
                               :ref 'etaf-taskbar-launcher
                               :on-press on-launch)
                         nil)))
      (or
       (mapcar
        (lambda (item)
          (let* ((key (plist-get item :key))
                 (selected (equal key active))
                 (disabled (plist-get item :disabled))
                 (state (plist-get item :state))
                 (caption (etaf-ui--desktop-item-caption item :label)))
            (etaf-node
             'etaf-button
             (list :key key :label caption
                   :ref (plist-get item :ref)
                   :aria-label (plist-get item :label)
                   :class (if selected "etaf-taskbar-item active"
                            (if (eq state 'minimized)
                                "etaf-taskbar-item minimized"
                              "etaf-taskbar-item"))
                   :color (cond (selected "#0B63CE")
                                ((eq state 'minimized) "#8A98A8")
                                (t "#52606D"))
                   :bgcolor (cond (selected "#DCEBFF")
                                  ((eq state 'minimized) "#F1F4F7")
                                  (t "#F7F9FC"))
                   :border (cond
                            (selected '((px 1) solid "#74A9E6"))
                            ((eq state 'minimized)
                             '((px 1) solid "#B8C4CF"))
                            (t '((px 1) solid "#F7F9FC")))
                   :font-weight (if selected 'bold 'normal)
                   :padding '((lh 0) (ch 0.75))
                   :disabled disabled
                   :variant 'ghost
                   :on-press (and on-select (not disabled)
                                  (lambda () (funcall on-select key))))
             nil)))
        items)
       (list (etaf-node 'etaf-label
                        (list :text "No windows" :variant 'muted) nil)))))))

(etaf-define-component etaf-workspace-bar
    (&key workspaces active on-select on-add on-close (add-label "New workspace")
          brand status class)
  "Render controlled WORKSPACES as an accessible workspace switcher bar.

WORKSPACES may contain scalar keys or plists with :key, :label, optional
:description and :disabled.  ACTIVE marks the selected workspace.  ON-SELECT
receives a key; ON-ADD and ON-CLOSE are optional caller-owned policy actions.
No workspace is created, removed or persisted by this Component."
  :validate
  (progn
    (etaf-check-prop :workspaces workspaces (proper-list-p workspaces)
                     "a list of workspace keys or item plists"
                     'etaf-workspace-bar)
    (dolist (workspace workspaces)
      (when (listp workspace)
        (etaf-ui--desktop-items (list workspace) 'etaf-workspace-bar))
      (when (not (listp workspace))
        (etaf-check-prop :workspace workspace
                         (etaf-ui--desktop-scalar-key-p workspace)
                         "a scalar key or item plist" 'etaf-workspace-bar)))
    (etaf-check-prop :on-select on-select
                     (or (null on-select) (functionp on-select))
                     "a function or nil" 'etaf-workspace-bar)
    (etaf-check-prop :on-add on-add (or (null on-add) (functionp on-add))
                     "a function or nil" 'etaf-workspace-bar)
    (etaf-check-prop :on-close on-close
                     (or (null on-close) (functionp on-close))
                     "a function or nil" 'etaf-workspace-bar)
    (etaf-check-prop :add-label add-label (stringp add-label)
                     "a string" 'etaf-workspace-bar)
    (etaf-check-prop :brand brand (or (null brand) (stringp brand))
                     "a string or nil" 'etaf-workspace-bar)
    (etaf-check-prop :status status (or (null status) (stringp status))
                     "a string or nil" 'etaf-workspace-bar))
  :render
  (let ((active (etaf-ui--reactive-value active))
        (items
         (mapcar
          (lambda (workspace)
            (if (listp workspace)
                workspace
              (list :key workspace :label (format "%s" workspace))))
          workspaces)))
    (etaf-node
     'flex
     (list :class (etaf-ui--class-value "etaf-workspace-bar" nil class)
           :role 'tablist :aria-label "Workspaces" :width 'stretch
           :height '(lh 1) :column-gap '(ch 0.5)
           :align-items 'center
           :padding '((lh 0) (ch 1))
           :background-color "#F7F9FC"
           :color "#243447"
           :border '((px 1) solid "#D8E1EA"))
     (append
      (when brand
        (list (etaf-node 'text
                         (list :font-weight 'bold :color "#334155")
                         (list brand))))
      (mapcar
       (lambda (item)
         (let* ((key (plist-get item :key))
                (selected (equal key active))
                (disabled (plist-get item :disabled)))
           (etaf-node
            'etaf-button
            (list :key key :label (plist-get item :label)
                  :ref (or (plist-get item :ref)
                           (intern (format "etaf-workspace-%s" key)))
                  :aria-label (plist-get item :label)
                  :variant 'ghost
                  :class (if selected "etaf-workspace-item active"
                           "etaf-workspace-item")
                  :color (if selected "#0B63CE" "#52606D")
                  :bgcolor (if selected "#E2EEFF" "#F7F9FC")
                  :border (if selected
                              '((px 1) solid "#74A9E6")
                            '((px 1) solid "#F7F9FC"))
                  :font-weight (if selected 'bold 'normal)
                  :padding '((lh 0) (ch 0.75))
                  :disabled disabled
                  :on-press (and on-select (not disabled)
                                 (lambda () (funcall on-select key))))
            nil)))
       items)
      (when on-add
        (list (etaf-node 'etaf-button
                         (list :label "+" :aria-label add-label
                               :variant 'ghost :on-press on-add)
                         nil)))
      (when on-close
        (list (etaf-node 'etaf-button
                         (list :label "×" :aria-label "Close workspace bar"
                               :variant 'ghost :on-press on-close)
                         nil)))
      (when status
        (list
         (etaf-node 'box
                    (list :width 'stretch :height '(lh 1)
                          :flex-grow 1 :flex-basis '(px 0)
                          :min-width '(px 0))
                    nil)
         (etaf-node 'box
                    (list :class "etaf-workspace-status"
                          :width 'max-content :height '(lh 1)
                          :padding '((lh 0) (ch 1))
                          :background-color "#EAF2FD"
                          :color "#0B63CE"
                          :font-weight 'bold
                          :border '((px 1) solid "#C2D8F2"))
                    (list (etaf-node 'text nil (list status))))))))))

(defun etaf-ui--desktop-launcher-items (items component)
  "Validate launcher ITEMS and return them unchanged."
  (etaf-ui--desktop-items items component)
  (dolist (item items)
    (etaf-check-prop :disabled (plist-get item :disabled)
                     (booleanp (plist-get item :disabled)) "a boolean"
                     component)
    (etaf-check-prop :state (plist-get item :state)
                     (memq (plist-get item :state) '(nil active minimized error))
                     "nil, active, minimized or error" component))
  items)

(defun etaf-ui--desktop-picker-body (items on-select selected class)
  "Build a picker body for ITEMS with ON-SELECT and SELECTED key.
CLASS names the body for styling."
  (etaf-node
   'column
   (list :class class :width 'stretch :item-gap '(lh 1))
   (mapcar
    (lambda (item)
      (let* ((key (plist-get item :key))
             (disabled (plist-get item :disabled))
             (is-selected (and selected (equal key selected)))
             (caption (etaf-ui--desktop-item-caption item :label))
             (description (plist-get item :description)))
         (etaf-node
         'etaf-button
         (list :key key :label (if is-selected (concat "◆ " caption) caption)
               :ref (plist-get item :ref)
               :aria-label (plist-get item :label)
               :disabled disabled
               :variant (if is-selected 'secondary 'ghost)
               :on-press (and on-select (not disabled)
                              (lambda () (funcall on-select key))))
         (when description
           (list (etaf-node 'etaf-label
                            (list :text description :variant 'muted) nil))))))
    items)))

(etaf-define-component etaf-launcher
    (&key open (title "Applications") items on-select on-close
          (close-label "Close"))
  "Render a controlled application LAUNCHER in a modal Dialog.

ITEMS use :key/:label and optional :description, :state and :disabled.  The
launcher owns no registry or open state.  ON-SELECT receives the selected key;
the caller normally closes OPEN after handling it.  ON-CLOSE is required when
OPEN is true so Escape and the close button remain accessible."
  :validate
  (progn
    (etaf-ui--desktop-launcher-items items 'etaf-launcher)
    (etaf-check-prop :on-select on-select (functionp on-select)
                     "a function" 'etaf-launcher)
    (etaf-check-prop :on-close on-close (functionp on-close)
                     "a function" 'etaf-launcher)
    (etaf-check-prop :title title (stringp title) "a string" 'etaf-launcher)
    (etaf-check-prop :close-label close-label (stringp close-label)
                     "a string" 'etaf-launcher))
  :render
  (when (etaf-ui--reactive-value open)
    (etaf-node 'etaf-dialog
               (list :open open :title title :close-label close-label
                     :on-close on-close :width '(ch 56))
               (list (etaf-ui--desktop-picker-body items on-select nil
                                                   "etaf-launcher-list")))))

(etaf-define-component etaf-switcher
    (&key open (title "Switch application") items selected on-select on-close
          (close-label "Close"))
  "Render a controlled application/window SWITCHER in a modal Dialog.

The presentation is shared with `etaf-launcher', but SELECTED marks the
currently focused item.  ON-SELECT receives a key and the caller controls
whether the switcher closes, changes focus or changes workspace."
  :validate
  (progn
    (etaf-ui--desktop-launcher-items items 'etaf-switcher)
    (let ((selected-value (etaf-ui--reactive-value selected)))
      (etaf-check-prop :selected selected-value
                       (or (null selected-value)
                           (cl-some (lambda (item)
                                     (equal selected-value (plist-get item :key))) items))
                     "a key from :items or nil" 'etaf-switcher)
    (etaf-check-prop :on-select on-select (functionp on-select)
                     "a function" 'etaf-switcher)
    (etaf-check-prop :on-close on-close (functionp on-close)
                     "a function" 'etaf-switcher)
    (etaf-check-prop :title title (stringp title) "a string" 'etaf-switcher)
    (etaf-check-prop :close-label close-label (stringp close-label)
                     "a string" 'etaf-switcher)))
  :render
  (let ((selected (etaf-ui--reactive-value selected)))
    (when (etaf-ui--reactive-value open)
      (etaf-node 'etaf-dialog
                 (list :open open :title title :close-label close-label
                       :on-close on-close :width '(ch 56))
                 (list (etaf-ui--desktop-picker-body items on-select selected
                                                     "etaf-switcher-list"))))))

(etaf-define-component etaf-splitter
    (&key (orientation 'horizontal) (ratio 0.5) (min-ratio 0.1)
          (max-ratio 0.9) on-change use class overlay)
  "Render a controlled split layout with a keyboard-focusable divider.

HORIZONTAL splits left/right; VERTICAL splits top/bottom.  RATIO is the first
pane's fraction and is caller-owned.  ON-CHANGE receives the raw divider
gesture and USE may contain an ETAF Behavior that converts that gesture into a
new ratio.  Named `first' and `second' slots hold the pane Views.  The
Component never stores a ratio or window/layout policy."
  :validate
  (progn
    (etaf-check-prop :orientation orientation (memq orientation '(horizontal vertical))
                     "horizontal or vertical" 'etaf-splitter)
    (etaf-check-prop :ratio ratio
                     (and (numberp (etaf-ui--reactive-value ratio))
                          (<= min-ratio (etaf-ui--reactive-value ratio) max-ratio))
                     "a ratio within the configured bounds" 'etaf-splitter)
    (etaf-check-prop :min-ratio min-ratio (and (numberp min-ratio) (> min-ratio 0) (< min-ratio 1))
                     "a fraction between zero and one" 'etaf-splitter)
    (etaf-check-prop :max-ratio max-ratio (and (numberp max-ratio) (> max-ratio 0) (< max-ratio 1)
                                               (<= min-ratio max-ratio))
                     "a fraction no smaller than min-ratio" 'etaf-splitter)
    (etaf-check-prop :on-change on-change (or (null on-change) (functionp on-change))
                     "a function or nil" 'etaf-splitter)
    (etaf-check-prop :overlay overlay (booleanp overlay)
                     "a boolean" 'etaf-splitter))
  :render
  (let* ((ratio (float (etaf-ui--reactive-value ratio)))
         (first-width (list '% (round (* 100 ratio))))
         (first (etaf-current-slot 'first))
         (second (etaf-current-slot 'second))
         (divider-props
          (list :class "etaf-splitter-divider" :role 'separator :tab-index 0
                :aria-label (if (eq orientation 'horizontal)
                                "Resize columns" "Resize rows")
                :pointer (if (eq orientation 'horizontal) 'hdrag 'vdrag)
                :use use :on-drag on-change
                :background-color (etaf-theme-token :ui-border "#687386")))
         (divider
          (if overlay
              (etaf-node
               'box
               (append divider-props
                       (if (eq orientation 'horizontal)
                           (list :position 'absolute
                                 :left (list '% (round (* 100 ratio)))
                                 :top '(lh 0) :width '(px 3) :height 'stretch)
                         (list :position 'absolute :left '(px 0)
                               :top (list '% (round (* 100 ratio)))
                               :width 'stretch :height '(lh 1))))
               nil)
            (if (eq orientation 'horizontal)
                (etaf-node 'box
                           (append divider-props
                                   (list :width '(px 3) :height 'stretch)) nil)
              (etaf-node 'box
                         (append divider-props
                                 (list :width 'stretch :height '(lh 1))) nil))))
         (props (list :class (etaf-ui--class-value "etaf-splitter" nil class)
                      :width 'stretch :height 'stretch
                      :overflow 'hidden)))
    (if overlay
        divider
      (if (eq orientation 'horizontal)
        (etaf-node 'flex (append props (list :flex-direction 'row))
                   (list
                    (etaf-node 'box (list :width first-width :height 'stretch
                                          :overflow 'hidden) first)
                    divider
                    (etaf-node 'box (list :flex-grow 1 :min-width '(px 0)
                                          :height 'stretch :overflow 'hidden)
                               second)))
      (etaf-node 'flex (append props (list :flex-direction 'column))
                 (list
                  (etaf-node 'box (list :height (list '% (round (* 100 ratio)))
                                        :width 'stretch :overflow 'hidden) first)
                  divider
                  (etaf-node 'box (list :flex-grow 1 :min-height '(lh 0)
                                        :width 'stretch :overflow 'hidden)
                             second)))))))

(provide 'etaf-ui-desktop)
;;; etaf-ui-desktop.el ends here
