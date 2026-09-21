;;; etaf-ui-window.el --- Controlled movable and resizable surfaces -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Window and panel shells are presentational, controlled Components.  They
;; project caller-owned geometry to Ebox and report gestures to caller-owned
;; callbacks.  They deliberately do not keep window state, assign z-order or
;; implement a workspace/window manager.

;;; Code:

(require 'cl-lib)
(require 'etaf-ui-basic)

(defun etaf-ui--window-callback (property value component)
  "Validate optional callback VALUE for COMPONENT PROPERTY."
  (etaf-check-prop property value (or (null value) (functionp value))
                   "a function or nil" component)
  value)

(defun etaf-ui--window-mode (mode)
  "Return the live symbolic MODE value for a controlled window."
  (let ((mode (etaf-ui--reactive-value mode)))
    (etaf-check-prop :mode mode (memq mode '(normal minimized maximized))
                     "normal, minimized or maximized" 'etaf-window)
    mode))

(defun etaf-ui--window-action (label aria-label callback color hover-label)
  "Return a macOS traffic-light action Button node for CALLBACK.
COLOR is the explicit traffic-light foreground used for LABEL."
  (etaf-node 'etaf-button
             (list :label label :aria-label aria-label
                   :variant 'ghost :class "etaf-window-control"
                   :height '(lh 1)
                   :pointer 'arrow
                   :color color :bgcolor "#F3F4F6"
                   :border '((px 0) solid "#F3F4F6")
                   :padding '((lh 0) (ch 0.25))
                   :font-size 18
                   :font-weight 'bold
                   :hover-content hover-label
                   :disabled (null callback)
                   :on-press callback)
             nil))

(defun etaf-ui--window-handle (edge on-resize ref use)
  "Return a flow resize handle for EDGE with caller-owned input callbacks."
  (etaf-node
   'box
   (append
    (list :key edge :class (format "etaf-window-resize-handle %s" edge)
          :width 'stretch :height 'stretch :overflow 'hidden
          :role 'separator :aria-label (format "Resize %s" edge)
          :pointer (cond ((memq edge '(top bottom)) 'vdrag)
                         ((memq edge '(left right)) 'hdrag)
                         (t 'nhdrag))
          :tab-index (when (or on-resize use) 0))
    (when ref (list :ref ref))
    (when use (list :use use))
    (when on-resize
      (list :on-drag (lambda (gesture) (funcall on-resize edge gesture)))))
   (list (etaf-node 'text nil (list " ")))))

(defun etaf-ui--panel-frame (content edges on-resize refs behaviors)
  "Surround CONTENT with disjoint resize cells for EDGES.
The text backend's vertical hit regions are whole rows.  Reserving them in
flow keeps the title, buttons and body visible and independently interactive."
  (let* ((left (cl-intersection edges '(left top-left bottom-left)))
         (right (cl-intersection edges '(right top-right bottom-right)))
         (bottom (cl-intersection edges '(bottom bottom-left bottom-right)))
         (cells '(top-left top top-right left content right
                  bottom-left bottom bottom-right)))
    (etaf-node
     'grid
     (list :width 'stretch :height 'stretch
           :grid-template-columns
           (list (if left '(px 6) '(px 0)) '(minmax (px 0) (fr 1))
                 (if right '(px 6) '(px 0)))
           :grid-template-rows
                   (list '(lh 0) '(minmax (lh 0) (fr 1))
                 (if bottom '(lh 1) '(lh 0)))
           :gap '((lh 0) (px 0)))
     (mapcar
      (lambda (cell)
        (cond
         ((eq cell 'content)
          (etaf-node 'column
                     (list :key 'content :width 'stretch :height 'stretch
                           :min-width '(px 0) :min-height '(lh 0)
                           :overflow 'hidden)
                     content))
         ((memq cell edges)
          (etaf-ui--window-handle cell on-resize (cdr (assq cell refs))
                                  (cdr (assq cell behaviors))))
         (t (etaf-node 'box (list :key cell :width 'stretch :height 'stretch) nil))))
      cells))))

(defconst etaf-ui--window-resize-edges
  '(top right bottom left top-left top-right bottom-right bottom-left)
  "Supported edge and corner names for resize handles.")

(etaf-define-component etaf-window-chrome
    (&key title (mode 'normal) (show-minimize t) (show-maximize t)
          (show-close t) on-minimize on-maximize on-restore on-close
          on-move ref class use)
  "Render a controlled window title bar and caller-owned action callbacks.

ON-MOVE receives Ebox's gesture plist from the title bar.  The component does
not change geometry; callers update their X/Y refs (or use an ETAF Behavior).
MODE only selects the visible maximize/restore action.  Named `actions' and
default slots are projected after the built-in controls."
  :validate
  (progn
    (etaf-check-prop :mode mode
                     (or (etaf-ref-p mode) (etaf-computed-p mode)
                         (memq mode '(normal minimized maximized)))
                     "normal, minimized or maximized" 'etaf-window-chrome)
    (dolist (entry `((:on-minimize . ,on-minimize)
                     (:on-maximize . ,on-maximize)
                     (:on-restore . ,on-restore)
                     (:on-close . ,on-close)
                     (:on-move . ,on-move)))
      (etaf-ui--window-callback (car entry) (cdr entry) 'etaf-window-chrome)))
  :render
  (let* ((mode (etaf-ui--window-mode mode))
         (actions
          ;; Keep the controls in the same left-to-right order as macOS:
          ;; close (red), minimize (yellow), maximize/restore (green).
          (append
           (when show-close
             (list (etaf-ui--window-action "●" "Close" on-close "#FF5F57" "⊗")))
           (when show-minimize
             (list (etaf-ui--window-action "●" "Minimize" on-minimize "#FEBC2E" "⊖")))
           (when show-maximize
             (list (if (eq mode 'maximized)
                       (etaf-ui--window-action "●" "Restore" on-restore "#28C840" "⊕")
                     (etaf-ui--window-action "●" "Maximize" on-maximize "#28C840" "⊕"))))
           nil))
         (extra-actions (append (etaf-current-slot 'actions)
                                (etaf-current-slot 'default)))
         (left-actions
          (etaf-node 'flex
                     (list :width '(ch 10) :height '(lh 1) :flex-shrink 0
                           :align-items 'center :justify-content 'start)
                     actions))
         (title-node
          (etaf-node 'box
                     ;; Equal fixed side columns keep the title at the
                     ;; geometric center without a positioned child.  This
                     ;; also preserves Ebox's host line-height invariant.
                     (list :width 'stretch :height '(lh 1)
                           :flex-grow 1 :flex-basis '(px 0)
                           :min-width '(px 0) :text-align 'center
                           :font-weight 'bold :color "#334155")
                     (list (etaf-node 'text (list :font-size 13) (list title)))))
         (right-actions
          (etaf-node 'flex
                     (list :width '(ch 10) :height '(lh 1) :flex-shrink 0
                           :align-items 'center :justify-content 'end)
                     extra-actions))
         )
    (etaf-node 'flex
               (append
                (list :class (etaf-ui--class-value "etaf-window-chrome" mode class)
                      :role 'heading :ref ref :width 'stretch :height '(lh 1) :z-index 30
                      :pointer 'hand
                      :align-items 'center :justify-content 'center
                      ;; Child columns own their horizontal breathing room so
                      ;; the bottom rule spans the complete chrome box.
                      :padding '((lh 0) (ch 0))
                      :background-color "#F8FAFC" :color "#1F2937"
                      :border-bottom '((px 1) solid "#CBD5E1"))
                (when on-move (list :on-drag on-move))
                (when use (list :use use)))
               (list (etaf-node 'text nil (list " "))
                     left-actions title-node right-actions))))

(etaf-define-component etaf-resizable-panel
    (&key (x '(px 0)) (y '(lh 0)) width height (position 'absolute)
          z-index (visible t) (min-width '(px 80)) max-width
          (min-height '(lh 2)) max-height (resizable t)
          (resize-edges etaf-ui--window-resize-edges) resize-refs resize-use
          on-resize on-move
          ref id class role use overflow)
  "Render a controlled positioned panel with optional resize handles.

X, Y, WIDTH, HEIGHT, Z-INDEX and visibility are passed to Ebox as geometry;
they may be values, refs or computed values.  ON-MOVE receives a gesture plist
from the panel root, while ON-RESIZE receives EDGE and that gesture plist.
Callbacks must update caller-owned geometry through ETAF's reactive APIs.
RESIZE-EDGES is a list of edge/corner symbols.  No geometry, constraints,
z-order or interaction state is retained by this Component."
  :validate
  (progn
    (etaf-check-prop :position position (memq position '(absolute relative))
                     "absolute or relative" 'etaf-resizable-panel)
    (etaf-check-prop :resizable resizable (booleanp resizable)
                     "a boolean" 'etaf-resizable-panel)
    (etaf-check-prop :resize-edges resize-edges
                     (and (proper-list-p resize-edges)
                          (cl-every (lambda (edge)
                                     (memq edge etaf-ui--window-resize-edges))
                                   resize-edges))
                     "a list of supported resize edges" 'etaf-resizable-panel)
    (etaf-check-prop :resize-refs resize-refs
                     (or (null resize-refs)
                         (and (proper-list-p resize-refs)
                              (cl-every
                               (lambda (entry)
                                 (and (consp entry)
                                      (memq (car entry) etaf-ui--window-resize-edges)
                                      (or (symbolp (cdr entry))
                                          (functionp (cdr entry)))))
                               resize-refs)))
                     "an edge-to-reference alist" 'etaf-resizable-panel)
    (etaf-check-prop :resize-use resize-use
                     (or (null resize-use)
                         (and (proper-list-p resize-use)
                              (cl-every
                               (lambda (entry)
                                 (and (consp entry)
                                      (memq (car entry) etaf-ui--window-resize-edges)))
                               resize-use)))
                     "an edge-to-Behavior alist" 'etaf-resizable-panel)
    (etaf-ui--window-callback :on-resize on-resize 'etaf-resizable-panel)
    (etaf-ui--window-callback :on-move on-move 'etaf-resizable-panel))
  :render
  (let* ((visible (etaf-ui--reactive-value visible))
         (theme (etaf-ui--style-tokens :ui-panel-fg :ui-panel-bg :ui-panel-border))
         (content (etaf-current-slot 'default))
         (framed (and resizable resize-edges (or on-resize resize-use))))
    (etaf-node 'box
               (append
                (list :class (etaf-ui--class-value "etaf-resizable-panel" nil class)
                      :position position :left (etaf-ui--reactive-value x)
                      :top (etaf-ui--reactive-value y)
                      :width (etaf-ui--reactive-value width)
                      :height (etaf-ui--reactive-value height)
                      :z-index (etaf-ui--reactive-value z-index) :visibility (if visible 'visible 'hidden)
                      :min-width (etaf-ui--reactive-value min-width)
                      :max-width (etaf-ui--reactive-value max-width)
                      :min-height (etaf-ui--reactive-value min-height)
                      :max-height (etaf-ui--reactive-value max-height)
                      :color (plist-get theme :ui-panel-fg)
                      :background-color (plist-get theme :ui-panel-bg)
                      :border (etaf-ui--style-border (plist-get theme :ui-panel-border))
                      :overflow (or overflow 'hidden) :ref ref :role (or role 'region)
                      :on-drag on-move :use use)
                (when id (list :id id)))
               (if framed
                   (list (etaf-ui--panel-frame content resize-edges on-resize
                                               resize-refs resize-use))
                 content))))

(etaf-define-component etaf-window
    (&key title (mode 'normal) (x '(px 0)) (y '(lh 0))
          (width '(ch 42)) (height '(lh 16)) z-index (visible t)
          (min-width '(px 160)) max-width (min-height '(lh 2)) max-height
          (resizable t) (resize-edges etaf-ui--window-resize-edges)
          resize-refs resize-use move-use
          on-move on-resize on-minimize on-maximize on-restore on-close
          (show-minimize t) (show-maximize t) (show-close t)
          ref id chrome-ref class use overflow)
  "Render a controlled window shell from `etaf-resizable-panel'.

The shell owns only presentation.  The caller owns MODE, X/Y, WIDTH/HEIGHT,
Z-INDEX and visibility and changes them through refs or ordinary props.  The
title bar forwards ON-MOVE gestures; resize handles forward EDGE and gesture
to ON-RESIZE.  Action callbacks merely request a state transition.  Slots are
`header' (extra title-bar content), `actions' (extra title-bar actions),
`default' (window body) and `footer'."
  :validate
  (progn
    (etaf-check-prop :mode mode
                     (or (etaf-ref-p mode) (etaf-computed-p mode)
                         (memq mode '(normal minimized maximized)))
                     "normal, minimized or maximized" 'etaf-window)
    (dolist (entry `((:on-move . ,on-move) (:on-resize . ,on-resize)
                     (:on-minimize . ,on-minimize) (:on-maximize . ,on-maximize)
                     (:on-restore . ,on-restore) (:on-close . ,on-close)))
      (etaf-ui--window-callback (car entry) (cdr entry) 'etaf-window)))
  :render
  (let* ((mode (etaf-ui--window-mode mode))
         (body (etaf-current-slot 'default))
         (header (etaf-current-slot 'header))
         (actions (etaf-current-slot 'actions))
         (footer (etaf-current-slot 'footer))
         (content
          (etaf-node 'column
                     (list :class "etaf-window-content" :width 'stretch
                           :height (if (eq mode 'minimized) '(lh 0) 'stretch)
                           :visibility (if (eq mode 'minimized) 'hidden 'visible)
                           :overflow 'hidden
                           :padding '((lh 1) (ch 1)))
                     (append body
                             (when footer
                               (list (etaf-node 'row
                                                (list :class "etaf-window-footer"
                                                      :width 'stretch)
                                                footer))))))
         (chrome
          (etaf-node 'etaf-window-chrome
                     (append (list :title title :mode mode :show-minimize show-minimize
                           :show-maximize show-maximize :show-close show-close
                           :on-minimize on-minimize :on-maximize on-maximize
                           :on-restore on-restore :on-close on-close
                           :ref chrome-ref)
                             (when on-move (list :on-move on-move))
                             (when move-use (list :use move-use)))
                     header
                     (list (cons 'actions actions)))))
    (etaf-node 'etaf-resizable-panel
               (list :x x :y y :width width :height height :position 'absolute
                     :z-index z-index :visible visible :min-width min-width
                     :max-width max-width :min-height min-height :max-height max-height
                     :resizable (and resizable (not (eq mode 'minimized)))
                     :resize-edges resize-edges :resize-refs resize-refs
                     :resize-use resize-use
                     :on-resize on-resize
                     :ref ref :id id :class (etaf-ui--class-value "etaf-window" mode class)
                     :role 'dialog :use use :overflow overflow)
               (list (etaf-node 'column
                                (list :class "etaf-window-layout" :width 'stretch
                                      :height 'stretch)
                                (list chrome content))))))

(provide 'etaf-ui-window)
;;; etaf-ui-window.el ends here
