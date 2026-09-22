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

(defvar etaf-ui--window-icon-cache (make-hash-table :test #'equal)
  "Cached text-property SVG glyphs used by traffic-light hover labels.")

(defun etaf-ui--window-icon-size ()
  "Return a traffic-light glyph size that fits the current frame line."
  (let ((line-height (if (display-graphic-p) (frame-char-height) 16)))
    (max 10 (min 16 (- line-height 4)))))

(defun etaf-ui--window-hover-icon (symbol color)
  "Return SYMBOL as a stable hover Text value in traffic-light COLOR.
On graphical displays the returned string carries an SVG `display' text
property: the circle and black operation glyph are one text cell, with no
overlay.  Batch and terminal displays retain the Unicode fallback SYMBOL."
  (let ((text (copy-sequence symbol)))
    (when (and (display-graphic-p)
               (fboundp 'image-type-available-p)
               (image-type-available-p 'svg))
      (let* ((size (etaf-ui--window-icon-size))
             (path
              (pcase symbol
                ("⊗" "M3.5 3.5L10.5 10.5M10.5 3.5L3.5 10.5")
                ("⊖" "M3.5 7H10.5")
                ("⊕" "M3.5 7H10.5M7 3.5V10.5")
                (_ "")))
             (image
              (or (gethash (list symbol color size) etaf-ui--window-icon-cache)
                  (puthash
                   (list symbol color size)
                   (create-image
                    (format
                     "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d' viewBox='0 0 14 14'><circle cx='7' cy='7' r='6.5' fill='%s'/><path d='%s' fill='none' stroke='#111111' stroke-width='1.4' stroke-linecap='round' stroke-linejoin='round'/></svg>"
                     size size color path)
                    'svg t :ascent 'center)
                   etaf-ui--window-icon-cache))))
        (put-text-property 0 (length text) 'display image text)))
    text))

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

(defun etaf-ui--window-action (label aria-label callback color hover-label group)
  "Return a macOS traffic-light action Button node for CALLBACK.
COLOR is the explicit traffic-light foreground used for LABEL."
  (etaf-node 'etaf-button
             (list :label label :aria-label aria-label
                   :variant 'ghost :class "etaf-window-control"
                   :height '(lh 1)
                   :pointer 'arrow
                   :color color :bgcolor "#F3F4F6"
                   :border '((px 0) solid "#F3F4F6")
                   :padding '((lh 0) (ch 0.30))
                   :font-size 14
                   :font-weight 'bold
                   :hover-group group
                   :hover-content (etaf-ui--window-hover-icon hover-label color)
                   :disabled (null callback)
                   :on-press callback)
             nil))

(defun etaf-ui--window-handle (edge on-resize ref use &optional props)
  "Return a resize handle for EDGE with caller-owned input callbacks.
PROPS are appended to the handle node, so a frame can place the handle in a
grid cell or present it like the content it covers."
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
    props
    (when ref (list :ref ref))
    (when use (list :use use))
    (when on-resize
      (list :on-drag (lambda (gesture) (funcall on-resize edge gesture)))))
   (list (etaf-node 'text nil (list " ")))))

(defun etaf-ui--panel-frame (content edges on-resize refs behaviors &optional header header-style)
  "Surround CONTENT with edge-owned resize cells for EDGES.

HEADER, when supplied, owns the frame's first row between the two corner
cells so a caller's title bar reaches both panel borders; HEADER-STYLE
presents those corner cells with the same background and rule, keeping the
covered title row visually closed.  Without HEADER the first row belongs to
the enabled top cells.  The text backend's hit regions are whole rows and
columns, so each enabled side cell keeps the body rows and the bottom cells
keep the last row.  CONTENT spans the panel's remaining body area instead of
shrinking behind reserved handle columns."
  (let* ((left (cl-intersection edges '(left top-left bottom-left)))
         (right (cl-intersection edges '(right top-right bottom-right)))
         (bottom (cl-intersection edges '(bottom bottom-left bottom-right)))
         (top-cells (cl-intersection edges '(top top-left top-right)))
         (handle (lambda (edge placement style)
                   (when (memq edge edges)
                     (etaf-ui--window-handle
                      edge on-resize (cdr (assq edge refs))
                      (cdr (assq edge behaviors))
                      (append placement style)))))
         (title-cell (lambda (corner placement)
                       (or (funcall handle corner placement header-style)
                           (funcall handle 'top placement header-style)))))
    (etaf-node
     'grid
     (list :width 'stretch :height 'stretch
           :grid-template-columns
           (list (if (or left top-cells) '(px 6) '(px 0))
                 '(minmax (px 0) (fr 1))
                 (if (or right top-cells) '(px 6) '(px 0)))
           :grid-template-rows
           (list '(lh 1) '(minmax (lh 0) (fr 1))
                 (if bottom '(lh 1) '(lh 0)))
           :gap '((lh 0) (px 0)))
     (delq
      nil
      (append
       (when header
         (list (etaf-node 'column
                          (list :key 'header :width 'stretch :height '(lh 1)
                                :min-width '(px 0)
                                :grid-column 2 :grid-row 1
                                :overflow 'hidden)
                          header)))
       (list
        (funcall title-cell 'top-left '(:grid-column 1 :grid-row 1))
        (unless header
          (funcall handle 'top '(:grid-column 2 :grid-row 1) nil))
        (funcall title-cell 'top-right '(:grid-column 3 :grid-row 1))
        (etaf-node 'column
                   (list :key 'content :width 'stretch :height 'stretch
                         :min-width '(px 0) :min-height '(lh 0)
                         :grid-column 2 :grid-row 2
                         :overflow 'hidden)
                   content)
        (funcall handle 'left '(:grid-column 1 :grid-row 2) nil)
        (funcall handle 'right '(:grid-column 3 :grid-row 2) nil)
        (funcall handle 'bottom-left '(:grid-column 1 :grid-row 3) nil)
        (funcall handle 'bottom '(:grid-column 2 :grid-row 3) nil)
        (funcall handle 'bottom-right '(:grid-column 3 :grid-row 3) nil)))))))

(defconst etaf-ui--window-resize-edges
  '(top right bottom left top-left top-right bottom-right bottom-left)
  "Supported edge and corner names for resize handles.")

(defconst etaf-ui--window-control-inactive-color "#B7BDC6"
  "Traffic-light color for a window that is not the active one.")

(etaf-define-component etaf-window-controls
    (&key (mode 'normal) (show-minimize t) (show-maximize t) (show-close t)
          (active t)
          on-minimize on-maximize on-restore on-close
          (group 'etaf-window-controls) class)
  "Render reusable macOS-style traffic-light controls.
GROUP is shared by the three buttons so Ebox updates all hover glyphs in one
incremental batch.  ACTIVE selects the macOS presentation: an inactive window
renders all three lights in one gray, while the active window keeps the red,
yellow and green lights.  The component owns no window policy; callbacks
request caller-owned transitions."
  :validate
  (progn
    (etaf-check-prop :mode mode
                     (or (etaf-ref-p mode) (etaf-computed-p mode)
                         (memq mode '(normal minimized maximized)))
                     "normal, minimized or maximized" 'etaf-window-controls)
    (etaf-check-prop :active active
                     (or (etaf-ref-p active) (etaf-computed-p active)
                         (booleanp (etaf-ui--reactive-value active)))
                     "a boolean" 'etaf-window-controls)
    (etaf-check-prop :group group
                     (or (symbolp group) (stringp group) (numberp group))
                     "a scalar hover group key" 'etaf-window-controls)
    (dolist (entry `((:on-minimize . ,on-minimize)
                     (:on-maximize . ,on-maximize)
                     (:on-restore . ,on-restore)
                     (:on-close . ,on-close)))
      (etaf-ui--window-callback (car entry) (cdr entry)
                                'etaf-window-controls)))
  :render
  (let* ((mode (etaf-ui--window-mode mode))
         (active (etaf-ui--reactive-value active))
         (close-color (if active "#FF5F57" etaf-ui--window-control-inactive-color))
         (minimize-color (if active "#FEBC2E" etaf-ui--window-control-inactive-color))
         (maximize-color (if active "#28C840" etaf-ui--window-control-inactive-color))
         (actions
          (append
           (when show-close
             (list (etaf-ui--window-action
                    (etaf-ui--window-hover-icon "⬤" close-color)
                    "Close" on-close close-color "⊗" group)))
           (when show-minimize
             (list (etaf-ui--window-action
                    (etaf-ui--window-hover-icon "⬤" minimize-color)
                    "Minimize" on-minimize minimize-color "⊖" group)))
           (when show-maximize
             (list
              (if (eq mode 'maximized)
                  (etaf-ui--window-action
                   (etaf-ui--window-hover-icon "⬤" maximize-color)
                   "Restore" on-restore maximize-color "⊕" group)
                (etaf-ui--window-action
                 (etaf-ui--window-hover-icon "⬤" maximize-color)
                 "Maximize" on-maximize maximize-color "⊕" group)))))))
    (etaf-node 'flex
               (list :class (etaf-ui--class-value
                             "etaf-window-controls" nil class)
                     :role 'toolbar :aria-label "Window controls"
                     :width 'max-content :height '(lh 1)
                     :align-items 'center :column-gap '(ch 0.15))
               actions)))

(defconst etaf-ui--window-title-style
  (list :background-color "#F8FAFC" :color "#1F2937"
        :border-bottom '((px 1) solid "#CBD5E1"))
  "Presentation shared by a window title bar and its corner resize cells.
The panel copies these properties so the title row keeps one continuous
background and bottom rule across the window's outer columns.")

(etaf-define-component etaf-window-chrome
    (&key title (mode 'normal) (show-minimize t) (show-maximize t)
          (show-close t) (active t)
          on-minimize on-maximize on-restore on-close
          on-move (drag-lock-modifier 'shift)
          group ref class use)
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
      (etaf-ui--window-callback (car entry) (cdr entry) 'etaf-window-chrome))
    (etaf-check-prop :active active
                     (or (etaf-ref-p active) (etaf-computed-p active)
                         (booleanp (etaf-ui--reactive-value active)))
                     "a boolean" 'etaf-window-chrome)
    (etaf-check-prop :drag-lock-modifier drag-lock-modifier
                     (or (null drag-lock-modifier)
                         (memq drag-lock-modifier
                               '(shift control meta super hyper)))
                     "nil or a supported modifier" 'etaf-window-chrome)
    (etaf-check-prop :group group
                     (or (symbolp group) (stringp group) (numberp group))
                     "a scalar hover group key" 'etaf-window-chrome))
  :render
  (let* ((mode (etaf-ui--window-mode mode))
         (group (or group ref 'etaf-window-controls))
         (extra-actions (append (etaf-current-slot 'actions)
                                (etaf-current-slot 'default)))
         (left-actions
          (etaf-node 'etaf-window-controls
                     (list :mode mode :active active
                           :show-minimize show-minimize
                           :show-maximize show-maximize :show-close show-close
                           :on-minimize on-minimize :on-maximize on-maximize
                           :on-restore on-restore :on-close on-close
                           :group group)
                     nil))
         (title-node
          (etaf-node 'box
                     ;; Equal fixed side columns keep the title at the
                     ;; geometric center without a positioned child.  This
                     ;; also preserves Ebox's host line-height invariant.
                     (list :width 'stretch :height '(lh 1)
                           :flex-grow 1 :flex-basis '(px 0)
                           :min-width '(px 0) :text-align 'center
                           :font-weight 'bold :color "#334155")
                     (list (etaf-node 'text (list :font-size 14) (list title)))))
         (right-actions
          (etaf-node 'flex
                     (list :width '(ch 10) :height '(lh 1) :flex-shrink 0
                           :align-items 'center :justify-content 'end)
                     extra-actions))
         )
    (etaf-node 'flex
               (append
                (list :class (etaf-ui--class-value "etaf-window-chrome" mode class)
                      :role 'heading :ref ref
                      :width 'stretch
                      :height '(lh 1) :z-index 30
                      :pointer 'hand :drag-lock-modifier drag-lock-modifier
                      :align-items 'center :justify-content 'center
                      :padding '((lh 0) (ch 0)))
                etaf-ui--window-title-style
                (when on-move (list :on-drag on-move))
                (when use (list :use use)))
               (list (etaf-node 'text nil (list " "))
                     left-actions title-node right-actions))))

(etaf-define-component etaf-resizable-panel
    (&key (x '(px 0)) (y '(lh 0)) width height (position 'absolute)
          z-index (visible t) (min-width '(px 80)) max-width
          (min-height '(lh 2)) max-height (resizable t)
          (resize-edges etaf-ui--window-resize-edges) resize-refs resize-use
          on-resize on-move header-style
          ref id class role use overflow)
  "Render a controlled positioned panel with optional resize handles.

X, Y, WIDTH, HEIGHT, Z-INDEX and visibility are passed to Ebox as geometry;
they may be values, refs or computed values.  ON-MOVE receives a gesture plist
from the panel root, while ON-RESIZE receives EDGE and that gesture plist.
Callbacks must update caller-owned geometry through ETAF's reactive APIs.
RESIZE-EDGES is a list of edge/corner symbols.  The `header' slot, when
supplied, owns the panel's first row between the corner cells; HEADER-STYLE
presents those corner cells like the header so its background and rule stay
closed across the row.  No geometry, constraints, z-order or interaction
state is retained by this Component."
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
         (header (etaf-current-slot 'header))
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
                                               resize-refs resize-use header
                                               header-style))
                 content))))

(etaf-define-component etaf-window
    (&key title (mode 'normal) (x '(px 0)) (y '(lh 0))
          (width '(ch 42)) (height '(lh 16)) z-index (visible t)
          (min-width '(px 160)) max-width (min-height '(lh 2)) max-height
          (resizable t) (resize-edges etaf-ui--window-resize-edges)
          resize-refs resize-use move-use
          on-move on-resize on-focus on-minimize on-maximize on-restore on-close
          (drag-lock-modifier 'shift)
          controls-group (controls-active t)
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
                     (:on-focus . ,on-focus)
                     (:on-minimize . ,on-minimize) (:on-maximize . ,on-maximize)
                     (:on-restore . ,on-restore) (:on-close . ,on-close)))
      (etaf-ui--window-callback (car entry) (cdr entry) 'etaf-window))
    (etaf-check-prop :drag-lock-modifier drag-lock-modifier
                     (or (null drag-lock-modifier)
                         (memq drag-lock-modifier
                               '(shift control meta super hyper)))
                     "nil or a supported modifier" 'etaf-window)
    (etaf-check-prop :controls-active controls-active
                     (or (etaf-ref-p controls-active)
                         (etaf-computed-p controls-active)
                         (booleanp (etaf-ui--reactive-value controls-active)))
                     "a boolean" 'etaf-window))
  :render
  (let* ((mode (etaf-ui--window-mode mode))
         (body (etaf-current-slot 'default))
         (header (etaf-current-slot 'header))
         (actions (etaf-current-slot 'actions))
         (footer (etaf-current-slot 'footer))
         (content
          (etaf-node 'column
                     (append
                      (list :class "etaf-window-content" :width 'stretch
                            :height (if (eq mode 'minimized) '(lh 0) 'stretch)
                            :visibility (if (eq mode 'minimized) 'hidden 'visible)
                            :overflow 'hidden
                            :padding '((lh 1) (ch 1)))
                      (when on-focus
                        (list :on-press on-focus
                              :on-press-capture on-focus)))
                     (append body
                             (when footer
                               (list (etaf-node 'row
                                                (list :class "etaf-window-footer"
                                                      :width 'stretch)
                                                footer))))))
         (chrome
          (etaf-node 'etaf-window-chrome
                     (append (list :title title :mode mode :active controls-active
                                   :show-minimize show-minimize
                           :show-maximize show-maximize :show-close show-close
                           :on-minimize on-minimize :on-maximize on-maximize
                           :on-restore on-restore :on-close on-close
                           :drag-lock-modifier drag-lock-modifier
                           :group controls-group
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
                     :header-style etaf-ui--window-title-style
                     :on-resize on-resize
                     :ref ref :id id :class (etaf-ui--class-value "etaf-window" mode class)
                     :role 'dialog :use use :overflow overflow)
               (list content)
               (list (cons 'header (list chrome))))))

(provide 'etaf-ui-window)
;;; etaf-ui-window.el ends here
