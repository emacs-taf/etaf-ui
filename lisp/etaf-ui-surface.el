;;; etaf-ui-surface.el --- Composable retained floating panels -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Ebox owns placement, occlusion and focus. These Components own the panel
;; presentation, dismissal policy and native keyboard shortcuts.

;;; Code:
(require 'etaf-ui-input)
(require 'etaf-ui-feedback)
(require 'ebox)

(defvar ebox-viewport-height)
(defvar ebox-viewport-width)

(defvar-local etaf-ui--surface-return-stack nil
  "Saved return routes for open surfaces, newest first; not current focus.")

(defvar etaf-ui--open-surfaces nil
  "Mounted floating panels as (RUNTIME . PANEL) entries, newest first.")

;;;###autoload
(defun etaf-ui-dismiss-outside-press ()
  "Dismiss every mounted floating surface the current press did not land in.
Call from the `:on-press' or `:on-press-capture' callback of a Host enclosing
the application, such as a shell root.  Each dialog, launcher, switcher,
popover, menu or drawer mounted in the event's Runtime whose panel does not
contain the pressed Host receives its dismissal, which requests its
`:on-close'.  A surface opened by the press being handled is not mounted yet
and stays open.  Return the number of surfaces dismissed.  Outside an event
callback signal `etaf-event-error'."
  (let ((runtime (etaf-current-runtime))
        (dismissed 0))
    (unless runtime
      (signal 'etaf-event-error
              (list "Dismissing surfaces requires a Host event callback")))
    (dolist (entry (copy-sequence etaf-ui--open-surfaces))
      (when (and (eq (car entry) runtime)
                 (memq entry etaf-ui--open-surfaces)
                 (not (etaf-event-target-within-p (cdr entry))))
        (condition-case nil
            (progn
              (etaf-dispatch-event runtime (cdr entry) 'dismiss)
              (cl-incf dismissed))
          ;; A surface without `:on-close' or one already removed by an
          ;; earlier dismissal has nothing left to request.
          (etaf-event-error nil))))
    dismissed))

(defun etaf-ui--surface-keys (buffer panel tag return-targets)
  "Install BUFFER-local shortcuts for committed PANEL under unique TAG.
Retain RETURN-TARGETS for nested handoff and return cleanup.
Target selection and navigation stay with the public Runtime."
  (let ((map (make-sparse-keymap)))
    (cl-labels ((command (function)
                  (lambda ()
                    (interactive)
                    (when-let* ((runtime (etaf-runtime-for-buffer buffer)))
                      (funcall function runtime)))))
      (dolist (key '("<escape>" "C-g"))
        (keymap-set map key
                    (command (lambda (runtime)
                               (etaf-dispatch-event runtime panel 'dismiss)))))
      (dolist (key '("TAB" "<tab>" "<down>"))
        (keymap-set map key
                    (command (lambda (runtime) (etaf-focus-within runtime panel 1)))))
      (dolist (key '("<backtab>" "S-TAB" "<up>"))
        (keymap-set map key
                    (command (lambda (runtime) (etaf-focus-within runtime panel -1)))))
      (dolist (key '("RET" "<return>"))
        (keymap-set map key (command #'etaf-activate))))
    ;; A retained panel can stop painting when its anchor disappears. Resolve
    ;; availability at key lookup, so such a panel cannot intercept commands.
    (map-keymap
     (lambda (key binding)
       (define-key map (vector key)
                   `(menu-item "" ,binding
                               :filter ,(lambda (command)
                                          (when-let* ((runtime (etaf-runtime-for-buffer buffer))
                                                      ;; An unmounted or not yet
                                                      ;; committed panel has no
                                                      ;; address; treat it as
                                                      ;; unavailable rather than
                                                      ;; failing the key lookup.
                                                      ((ignore-errors
                                                         (etaf-host-ref-position
                                                          runtime panel))))
                                            command)))))
     map)
    (let ((entry (cons tag map)) (route (cons tag return-targets)))
      (with-current-buffer buffer
        (set (make-local-variable tag) t)
        (setq-local minor-mode-overriding-map-alist
                    (cons entry minor-mode-overriding-map-alist))
        (push route etaf-ui--surface-return-stack))
      (lambda ()
        (when (buffer-live-p buffer)
          (with-current-buffer buffer
            (setq minor-mode-overriding-map-alist
                  (delq entry minor-mode-overriding-map-alist))
            (setq etaf-ui--surface-return-stack (delq route etaf-ui--surface-return-stack))
            (kill-local-variable tag)))))))

(etaf-define-component etaf-ui--open-surface
    (&key anchor (placement 'bottom-start) side (width '(ch 32)) height
          title on-close modal center compact (backdrop t))
  "Render one open floating surface and own its keyboard attachment."
  :bindings
  ((panel (etaf-local-ref 'panel))
   (buffer (current-buffer))
   (return-focus
    (delete-dups
     (delq nil (cons (when-let* ((runtime (etaf-runtime-for-buffer buffer)))
                       (etaf-focused-host-ref runtime))
                     (copy-sequence (cdar etaf-ui--surface-return-stack))))))
   (tag (make-symbol "etaf-ui-surface-keys"))
   (cleanup nil)
   (registration nil))
  :setup
  (progn
    (etaf-on-mounted
     (lambda ()
       (setq cleanup (etaf-ui--surface-keys buffer panel tag return-focus))
       (let ((runtime (or (etaf-current-runtime)
                          (etaf-runtime-for-buffer buffer))))
         (when runtime
           (setq registration (cons runtime panel))
           (push registration etaf-ui--open-surfaces))
         ;; A surface closed before its mount hook settles leaves PANEL
         ;; unresolved; an unknown position is simply nothing to focus.
           (when (and runtime
                      (ignore-errors (etaf-host-ref-position runtime panel)))
           ;; A surface without a focusable child does not need a second
           ;; publication just to focus its -1 panel root.  Keymap-based
           ;; dismissal remains buffer-local; interactive surfaces still
           ;; focus their first eligible child through Ebox.
           (ignore-errors (etaf-focus-within runtime panel))))))
    (etaf-on-unmounted
     (lambda ()
       (when cleanup (funcall cleanup))
       (when registration
         (setq etaf-ui--open-surfaces (delq registration etaf-ui--open-surfaces)
               registration nil))
       (when-let* ((runtime (etaf-runtime-for-buffer buffer))
                   ((etaf-runtime-mounted-p runtime)))
         (catch 'restored
           (dolist (target return-focus)
             (when (etaf-host-ref-position runtime target)
               (condition-case nil
                   (progn (etaf-focus runtime target) (throw 'restored t))
                 (etaf-event-error nil)))))))))
  :render
  (let* ((theme (etaf-ui--style-tokens :ui-panel-fg :ui-panel-bg :ui-panel-border))
         (target-buffer
          (if-let* ((runtime (etaf-current-runtime)))
              (etaf-runtime-buffer runtime)
            (current-buffer)))
         (display-window (and (display-graphic-p)
                              (get-buffer-window target-buffer t)))
         (viewport-width
          (or (and display-window
                   (ebox-viewport-window-width display-window))
              (and (numberp ebox-viewport-width) ebox-viewport-width)))
         (viewport-height
          (or (and display-window (window-body-height display-window))
              (and (numberp ebox-viewport-height) ebox-viewport-height)))
         (viewport-height-known
          (and (display-graphic-p)
               (numberp viewport-height) (> viewport-height 0)))
         (viewport-width-known
          (and (display-graphic-p)
               (numberp viewport-width) (> viewport-width 0)))
         (requested-width-px
          (pcase width
            (`(ch ,(and n (pred numberp)))
             (* (max 1 (frame-char-width)) n))
            (`(px ,(and n (pred numberp))) n)))
         (bounded-width-px
          (when (and center viewport-width-known requested-width-px)
            (min requested-width-px
                 (max 1 (- viewport-width
                           (* 2 (max 1 (frame-char-width))))))))
         (requested-height-rows
          (pcase height (`(lh ,(and n (pred integerp))) n)))
         (bounded-height-rows
          (when requested-height-rows
            (if viewport-height-known
                (min requested-height-rows (max 1 (- viewport-height 4)))
              requested-height-rows)))
         (center-left
          (when bounded-width-px
            (list 'px
                  (max 0 (floor (/ (- viewport-width bounded-width-px) 2))))))
         ;; Without a known height the panel sizes to its content, so a
         ;; modest offset keeps a short dialog in the upper third rather than
         ;; guessing a center for an unknown extent.
         (center-top
          (when (and center viewport-height-known)
            (list 'lh
                  (if bounded-height-rows
                      (max 0 (floor (/ (- viewport-height bounded-height-rows)
                                       2)))
                    (max 1 (floor (/ viewport-height 5)))))))
         (content
          (etaf-node
           'column
           (list :ref panel :class "etaf-floating-panel"
                 :role (if modal 'dialog 'group) :tab-index -1
                 :aria-label title :keymap nil :on-dismiss on-close
                 :position 'absolute :layer 'root :z-index 1001
                 :anchor anchor :placement placement
                 :left (cond (anchor '(px 0))
                             ((eq side 'left) '(px 0))
                             ((eq side 'right)
                             (list 'calc (list '- '(% 100) width)))
                             (center-left center-left)
                             (t '(px 0)))
                 :top (cond (anchor '(lh 0))
                            ((memq side '(left right)) '(lh 0))
                            (center-top center-top)
                            (t '(lh 2)))
                 :height (cond ((memq side '(left right)) '(% 100))
                               (bounded-height-rows
                                (list 'lh bounded-height-rows)))
                 :max-height (when modal
                               (if bounded-height-rows
                                   (list 'lh bounded-height-rows)
                                 (when viewport-height-known '(% 80))))
                 :width (if bounded-width-px
                            (list 'px bounded-width-px)
                          width)
                 :item-gap (if compact '(lh 0)
                             (if (or modal side) '(lh 1) '(lh 0)))
                 :padding (if compact '((lh 0) (ch 1))
                            '((lh 1) (ch 2)))
                 :color (plist-get theme :ui-panel-fg)
                 :background-color (plist-get theme :ui-panel-bg)
                 :overflow (when (and modal viewport-height-known) 'scroll)
                 :border (etaf-ui--style-border (plist-get theme :ui-panel-border)))
           (append
            (when title
              (list (etaf-node 'etaf-label (list :text title :variant 'strong) nil)))
            (etaf-current-slot 'default)
            (etaf-current-slot 'footer)))))
    (if (and modal backdrop)
        (etaf-node 'fragment nil
                   (list
                    (etaf-node 'box
                               (list :position 'absolute :layer 'root
                                     :left '(px 0) :top '(lh 0)
                                     :width '(% 100) :height '(% 100)
                                     :z-index 1001
                                     :class "etaf-modal-backdrop"
                                     :background-color "#243039"
                                     :role 'presentation :keymap nil)
                               nil)
                    content))
      ;; A Desktop may request an unpainted modal while retaining its
      ;; application surface underneath.  The panel's retained focus/keymap
      ;; policy still owns keyboard dismissal and navigation.
      (if modal
          (etaf-node 'fragment nil (list content))
        content))))

(etaf-define-component etaf-popover
    (&key open anchor (placement 'bottom-start) (width '(ch 32)) title on-close)
  "Show controlled OPEN content anchored to a semantic ID."
  :validate
  (progn
    (etaf-check-prop :on-close on-close (functionp on-close) "a function")
    (etaf-check-prop :anchor anchor
                     (and anchor (or (symbolp anchor)
                                     (and (stringp anchor) (not (string-empty-p anchor)))))
                     "a nonempty semantic ID")
    (etaf-check-prop :title title (or (null title) (stringp title)) "a string or nil"))
  :render
  (when (etaf-ui--reactive-value open)
    (etaf-node 'etaf-ui--open-surface
               (list :anchor anchor :placement placement :width width :title title :on-close on-close)
               (etaf-current-slot 'default)
               (list (cons 'footer (etaf-current-slot 'footer))))))

(etaf-define-component etaf-dialog
    (&key open (title "Dialog") (width '(ch 48)) height compact
          (close-label "Close") on-close (backdrop t))
  "Show a controlled modal panel with default content and a footer slot.
When BACKDROP is nil, retain the underlying surface's paint while keeping the
panel as a root-layer projection; the caller owns any outside-click policy.
HEIGHT optionally fixes the panel to text rows, bounded by the visible window;
COMPACT keeps the title at one text row without extra panel spacing."
  :validate
  (progn
    (etaf-check-prop :on-close on-close (functionp on-close) "a function")
    (etaf-check-prop :title title (stringp title) "a string")
    (etaf-check-prop :height height
                     (or (null height)
                         (and (proper-list-p height)
                              (= (length height) 2)
                              (eq (car height) 'lh)
                              (integerp (cadr height))
                              (> (cadr height) 0)))
                     "nil or (lh POSITIVE-INTEGER)" 'etaf-dialog)
    (etaf-check-prop :compact compact (booleanp compact) "a boolean" 'etaf-dialog)
    (etaf-check-prop :close-label close-label (stringp close-label) "a string"))
  :render
  (when (etaf-ui--reactive-value open)
    (etaf-node 'etaf-ui--open-surface
               (list :modal t :center t :backdrop backdrop :title title
                     :width width :height height :compact compact
                     :on-close on-close)
               (etaf-current-slot 'default)
               (list (cons 'footer
                           (append (etaf-current-slot 'footer)
                                   (list (etaf-node 'etaf-button
                                                    (list :label close-label :variant 'ghost :on-press on-close)
                                   nil))))))))

(etaf-define-component etaf-tooltip
    (&key open anchor text (placement 'top-start) on-close)
  "Show short controlled TEXT near ANCHOR.
Tooltip visibility is controlled by OPEN; applications may toggle it from a
button or another host event. It does not invent a second hover event system."
  :validate
  (progn
    (etaf-check-prop :text text (stringp (etaf-ui--reactive-value text))
                     "a string or reactive string" 'etaf-tooltip)
    (etaf-check-prop :on-close on-close (functionp on-close)
                     "a function" 'etaf-tooltip))
  :render
  (when (etaf-ui--reactive-value open)
    (etaf-node 'etaf-popover
               (list :open t :anchor anchor :placement placement :width '(ch 32)
                     :on-close on-close)
               (list (etaf-node 'etaf-label
                                (list :text text :variant 'default) nil)))))

(etaf-define-component etaf-toast
    (&key open anchor message (title "Notification") (variant 'info) on-close)
  "Show controlled MESSAGE as a dismissible anchored notification.
The caller owns OPEN and chooses when the toast is removed; VARIANT controls
the message's semantic color. Anchored placement follows Popover."
  :validate
  (progn
    (etaf-check-prop :message message (stringp (etaf-ui--reactive-value message))
                     "a string or reactive string" 'etaf-toast)
    (etaf-check-prop :title title (stringp title) "a string" 'etaf-toast)
    (etaf-check-prop :on-close on-close (functionp on-close)
                     "a function" 'etaf-toast))
  :render
  (when (etaf-ui--reactive-value open)
    (etaf-node 'etaf-popover
               (list :open t :anchor anchor :placement 'top-end :width '(ch 42)
                     :title title :on-close on-close)
               (list (etaf-node 'column nil
                                (list (etaf-node 'etaf-badge
                                                 (list :text (capitalize (symbol-name variant))
                                                       :variant variant) nil)
                                      (etaf-node 'etaf-label
                                                 (list :text message) nil)))))))

(etaf-define-component etaf-dropdown-menu
    (&key (label "Actions") items on-select disabled (width '(ch 28)))
  "Open an anchored menu of ITEMS and pass the selected key to ON-SELECT."
  :bindings ((open (etaf-ref nil))
             (anchor (symbol-name (gensym "etaf-menu-"))))
  :render
  (progn
    (etaf-ui--check-menu-items items 'etaf-dropdown-menu)
    (etaf-check-prop :label label (stringp label) "a string" 'etaf-dropdown-menu)
    (etaf-check-prop :on-select on-select (or (null on-select) (functionp on-select))
                     "a function or nil" 'etaf-dropdown-menu)
    (let ((enabled (and (not disabled) on-select
                        (cl-some (lambda (item) (not (plist-get item :disabled))) items))))
      (etaf-node 'fragment nil (list
       (etaf-node 'etaf-button
                  (list :id anchor :label (concat label " ▾") :aria-label label
                        :disabled (not enabled) :variant 'secondary
                        :on-press (lambda () (setf (etaf-value open) (not (etaf-value open)))))
                  nil)
       (etaf-node
        'etaf-popover
        (list :open (and enabled (etaf-value open)) :anchor anchor :width width
              :on-close (lambda () (setf (etaf-value open) nil)))
        (mapcar
         (lambda (item)
           (let ((key (plist-get item :key)))
                        (etaf-node 'etaf-button
                        (list :key key :label (plist-get item :label)
                              :variant 'ghost :disabled (plist-get item :disabled)
                              :on-press (lambda ()
                                          (setf (etaf-value open) nil)
                                          (funcall on-select key)))
                        nil)))
         items)))))))

(etaf-define-component etaf-context-menu
    (&key (label "More") items on-select disabled (width '(ch 30)))
  "Render a compact context action surface from ITEMS.
The trigger is an ordinary Ebox Button so keyboard, mouse and focus behavior
remain shared with DropdownMenu; applications may place it beside any target."
  :render
  (etaf-node 'etaf-dropdown-menu
             (list :label label :items items :on-select on-select
                   :disabled disabled :width width)
             nil))

(etaf-define-component etaf-drawer
    (&key open (title "Drawer") (placement 'right) (width '(ch 42))
          (modal t) on-close)
  "Show a controlled side DRAWER with default content.
PLACEMENT is `left' or `right'.  ON-CLOSE is required; OPEN and form data
remain caller-owned."
  :validate
  (progn
    (etaf-check-prop :placement placement (memq placement '(left right))
                     "left or right" 'etaf-drawer)
    (etaf-check-prop :modal modal (booleanp modal) "a boolean" 'etaf-drawer)
    (etaf-check-prop :title title (or (null title) (stringp title))
                     "a string or nil" 'etaf-drawer)
    (etaf-check-prop :on-close on-close (functionp on-close)
                     "a function" 'etaf-drawer))
  :render
  (when (etaf-ui--reactive-value open)
    (etaf-node 'etaf-ui--open-surface
               (list :modal modal :placement 'top-start :side placement
                     :width (list 'min width '(% 100))
                     :title title :on-close on-close)
               (etaf-current-slot 'default)
               (list (cons 'footer (etaf-current-slot 'footer))))))

(provide 'etaf-ui-surface)
;;; etaf-ui-surface.el ends here
