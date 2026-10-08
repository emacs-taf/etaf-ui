;;; etaf-ui-media.el --- In-buffer image and video viewer -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; A modal viewer drawn on the application's root layer.  The media is sized
;; to the live viewport at its own aspect ratio; video gets a transport bar
;; driven by the public `etaf-video' control functions.

;;; Code:
(require 'etaf-ui-surface)
(require 'etaf-ui-icon)
(require 'etaf-ui-selection)

(defconst etaf-ui--media-colors
  '(:scrim "#0E1116" :fg "#E8ECF1" :muted "#8E99A8" :control "#C9D1DB"
    :track "#2A313B")
  "Fixed dark palette of the viewer, independent of the application theme.")

(defconst etaf-ui--media-speeds '(1 1.25 1.5 2 0.5)
  "Playback rates cycled by the speed control.")

(defconst etaf-ui--media-gutter 6
  "Columns reserved on each side of the stage for navigation arrows.")

(defun etaf-ui--media-color (key)
  "Return the viewer palette color KEY."
  (plist-get etaf-ui--media-colors key))

(defun etaf-ui--media-clock (seconds)
  "Return SECONDS as M:SS, or H:MM:SS from one hour."
  (let ((total (max 0 (floor (or seconds 0)))))
    (if (>= total 3600)
        (format "%d:%02d:%02d" (/ total 3600) (/ (% total 3600) 60) (% total 60))
      (format "%d:%02d" (/ total 60) (% total 60)))))

(defun etaf-ui--media-natural-size (kind src size)
  "Return the pixel (WIDTH . HEIGHT) of SRC of KIND, preferring SIZE."
  (or (and (consp size) (numberp (car size)) (numberp (cdr size))
           (> (car size) 0) (> (cdr size) 0)
           size)
      (pcase kind
        ('image
         (when (display-images-p)
           (ignore-errors
             (image-size (if (stringp src) (create-image src) src) t))))
        ('video
         (ignore-errors
           (let ((info (etaf-video-source-info src)))
             (when (and (numberp (plist-get info :width))
                        (numberp (plist-get info :height)))
               (cons (plist-get info :width) (plist-get info :height)))))))
      '(16 . 9)))

(defun etaf-ui--media-grid (natural width-px rows upscale)
  "Fit NATURAL pixel size into WIDTH-PX by ROWS lines as (COLUMNS . ROWS).
Keep the aspect ratio; enlarge beyond the natural size only when UPSCALE."
  (let* ((cw (max 1 (frame-char-width)))
         (lh (max 1 (frame-char-height)))
         (width (float (max 1 (car natural))))
         (height (float (max 1 (cdr natural))))
         (scale (min (/ width-px width) (/ (* rows lh) height)))
         (scale (if upscale scale (min scale 1.0))))
    (cons (max 2 (min (max 2 (floor width-px cw)) (round (/ (* width scale) cw))))
          (max 1 (min rows (round (/ (* height scale) lh)))))))

(defun etaf-ui--media-printing-guard (map)
  "Bind printing characters unbound in MAP to `ignore' and return MAP.
A modal viewer keeps the application underneath from receiving letters."
  (dotimes (offset 95)
    (let ((key (vector (+ 32 offset))))
      (unless (lookup-key map key)
        (define-key map key #'ignore))))
  map)

(etaf-define-component etaf-ui--media-control
    (&key icon label help on-press (width 4) ref)
  "Render one fixed-width transport control: an icon or a short LABEL."
  :render
  (etaf-node
   'box
   (list :width (list 'ch width) :height '(lh 1) :text-align 'center
         :flex-shrink 0
         :color (etaf-ui--media-color :control) :role 'button
         :aria-label help :help-echo help :tab-index -1 :ref ref
         :hover-style (list :color (etaf-ui--media-color :fg))
         :on-press on-press)
   (list (if icon
             (etaf-node 'etaf-ui-icon
                        (list :name icon :set 'svg :size 0.9 :min-width width
                              :color (etaf-ui--media-color :control))
                        nil)
           (etaf-node 'text nil (list label))))))

(etaf-define-component etaf-ui--media-viewer-open
    (&key kind src source-size title subtitle caption on-close on-previous
          on-next autoplay)
  "Render the open viewer and own its keys and video polling."
  :bindings
  ((panel (etaf-local-ref 'panel))
   (header (etaf-local-ref 'header))
   (stage (etaf-local-ref 'stage))
   (footer (etaf-local-ref 'footer))
   (buffer (if-let* ((runtime (etaf-current-runtime)))
               (etaf-runtime-buffer runtime)
             (current-buffer)))
   (handle (make-symbol "etaf-media-viewer"))
   (kind-input (etaf-prop 'kind))
   (close-input (etaf-prop 'on-close))
   (previous-input (etaf-prop 'on-previous))
   (next-input (etaf-prop 'on-next))
   (playing (etaf-ref nil :name "media-playing"))
   (position (etaf-ref 0 :name "media-position"))
   (duration (etaf-ref 0 :name "media-duration"))
   (speed (etaf-ref 1 :name "media-speed"))
   (audio (etaf-ref etaf-video-audio :name "media-audio"))
   (clock (etaf-computed
           (lambda ()
             (format "%s / %s"
                     (etaf-ui--media-clock (etaf-value position))
                     (etaf-ui--media-clock (etaf-value duration))))))
   (progress (etaf-computed
              (lambda ()
                (let ((total (etaf-value duration)))
                  (if (> total 0)
                      (min 100 (* 100.0 (/ (etaf-value position) total)))
                    0)))))
   (natural-cache (make-hash-table :test #'equal))
   (return-focus
    (when-let* ((runtime (etaf-runtime-for-buffer buffer)))
      (delq nil (list (etaf-focused-host-ref runtime)))))
   (tag (make-symbol "etaf-ui-media-keys"))
   (timer nil)
   (cursor-restore nil)
   (cleanup nil)
   (registration nil)
   (video-p (lambda () (eq (etaf-value kind-input) 'video)))
   (control (lambda (function &rest args)
              (when (funcall video-p)
                (condition-case nil (apply function handle args)
                  (user-error nil)))))
   (poll (lambda ()
           (when (funcall video-p)
             (when-let* ((state (ignore-errors (etaf-video-state handle))))
               (etaf-set-value playing (and (plist-get state :playing) t))
               (etaf-set-value position (or (plist-get state :position) 0))
               (etaf-set-value duration (or (plist-get state :duration) 0))))))
   (toggle (lambda ()
             (funcall control #'etaf-video-toggle-playback)
             (funcall poll)))
   (seek-to-seconds (lambda (seconds)
                      (let ((target (max 0 (if (> (etaf-value duration) 0)
                                               (min seconds (etaf-value duration))
                                             seconds))))
                        (funcall control #'etaf-video-seek target)
                        (etaf-set-value position target))))
   (seek-by (lambda (delta)
              (funcall seek-to-seconds (+ (etaf-value position) delta))))
   (seek-to (lambda (percent)
              (when (> (etaf-value duration) 0)
                (funcall seek-to-seconds
                         (* (etaf-value duration) (/ percent 100.0))))))
   (cycle-speed (lambda ()
                  (etaf-set-value
                   speed (or (cadr (member (etaf-value speed) etaf-ui--media-speeds))
                             (car etaf-ui--media-speeds)))))
   (toggle-audio (lambda () (etaf-update-value audio #'not)))
   (navigate (lambda (direction)
               (let ((callback (etaf-value (if (eq direction 'next)
                                               next-input
                                             previous-input))))
                 (when (functionp callback) (funcall callback)))))
   (close (lambda ()
            (let ((callback (etaf-value close-input)))
              (when (functionp callback) (funcall callback)))))
   (outside (lambda ()
              (cond
               ;; RET or SPC with point on the surface is the play key.
               ((not (etaf-event-pointer-p)) (funcall toggle))
               ((not (or (etaf-event-target-within-p header)
                         (etaf-event-target-within-p stage)
                         (etaf-event-target-within-p footer)))
                (funcall close)))))
   (swipe (lambda (direction)
            (funcall navigate (if (eq direction 'left) 'next 'previous)))))
  :setup
  (let ((map (make-sparse-keymap)))
    (dolist (binding
             `(("q" . ,close)
               ("SPC" . ,toggle) ("k" . ,toggle)
               ("<left>" . ,(lambda ()
                              (if (funcall video-p) (funcall seek-by -5)
                                (funcall navigate 'previous))))
               ("<right>" . ,(lambda ()
                               (if (funcall video-p) (funcall seek-by 5)
                                 (funcall navigate 'next))))
               ("j" . ,(lambda () (funcall seek-by -10)))
               ("l" . ,(lambda () (funcall seek-by 10)))
               ("p" . ,(lambda () (funcall navigate 'previous)))
               ("n" . ,(lambda () (funcall navigate 'next)))
               ("m" . ,toggle-audio)
               ("." . ,cycle-speed)))
      (let ((function (cdr binding)))
        (keymap-set map (car binding) (lambda () (interactive) (funcall function)))))
    (etaf-ui--media-printing-guard map)
    (etaf-on-mounted
     (lambda ()
       (setq cleanup (etaf-ui--surface-keys buffer panel tag return-focus map))
       ;; The viewer owns the whole window; a text cursor has no target.
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (setq cursor-restore (list (local-variable-p 'cursor-type) cursor-type))
           (setq-local cursor-type nil)))
       (when-let* ((runtime (or (etaf-current-runtime)
                                (etaf-runtime-for-buffer buffer))))
         (setq registration (cons runtime panel))
         (push registration etaf-ui--open-surfaces)
         ;; The panel itself takes focus, so Space and arrows reach the
         ;; viewer instead of activating a focused control.
         (ignore-errors (etaf-focus runtime panel)))
       (setq timer (run-at-time 0.25 0.25
                                (lambda ()
                                  (if (buffer-live-p buffer)
                                      (funcall poll)
                                    (cancel-timer timer)))))))
    (etaf-on-unmounted
     (lambda ()
       (when timer (cancel-timer timer) (setq timer nil))
       (when cleanup (funcall cleanup))
       (when (and cursor-restore (buffer-live-p buffer))
         (with-current-buffer buffer
           (if (car cursor-restore)
               (setq-local cursor-type (cadr cursor-restore))
             (kill-local-variable 'cursor-type)))
         (setq cursor-restore nil))
       (when registration
         (setq etaf-ui--open-surfaces (delq registration etaf-ui--open-surfaces)
               registration nil))
       (when-let* ((runtime (etaf-runtime-for-buffer buffer))
                   ((etaf-runtime-mounted-p runtime)))
         (dolist (target return-focus)
           (when (etaf-host-ref-position runtime target)
             (ignore-errors (etaf-focus runtime target))))))))
  :render
  (let* ((viewport (etaf-runtime-viewport))
         (lines (max 8 (or (cdr viewport) 24)))
         (cw (max 1 (frame-char-width)))
         (video (eq kind 'video))
         (stage-rows (max 3 (- lines 6)))
         (stage-px (max (* 4 cw)
                        (- (car viewport) (* 2 etaf-ui--media-gutter cw))))
         (natural (or (gethash (cons kind src) natural-cache)
                      (puthash (cons kind src)
                               (etaf-ui--media-natural-size kind src source-size)
                               natural-cache)))
         (grid (etaf-ui--media-grid natural stage-px stage-rows video))
         (fg (etaf-ui--media-color :fg))
         (muted (etaf-ui--media-color :muted))
         (accent (plist-get (etaf-ui--style-tokens :ui-accent) :ui-accent)))
    (cl-flet ((arrow (icon callback help)
                (etaf-node 'flex
                           (list :width (list 'ch etaf-ui--media-gutter)
                                 :height (list 'lh stage-rows)
                                 :justify-content 'center :align-items 'center)
                           (when callback
                             (list (etaf-node 'etaf-ui--media-control
                                              (list :icon icon :help help
                                                    :on-press callback)
                                              nil)))))
              (air () (etaf-node 'box (list :height '(lh 1)) nil)))
      (etaf-node
       'column
       (list :ref panel :role 'dialog :aria-label (or title "Media")
             :tab-index -1 :keymap nil :on-dismiss on-close
             :position 'absolute :layer 'root :z-index 1001
             :left '(px 0) :top '(lh 0) :width '(% 100) :height (list 'lh lines)
             :background-color (etaf-ui--media-color :scrim) :color fg
             :pointer 'arrow :on-press outside :on-swipe swipe)
       (list
        (air)
        ;; Header: title and subtitle on the left, author actions and close.
        (etaf-node
         'flex
         (list :ref header :width 'stretch :height '(lh 1)
               :justify-content 'space-between :align-items 'center
               :padding '((lh 0) (ch 2)))
         (list
          (etaf-node 'box (list :flex-grow 1 :min-width '(ch 0) :height '(lh 1)
                                :overflow 'hidden :wrap-mode 'none)
                     (list (etaf-node 'text (list :font-weight 'bold)
                                      (list (or title "")))
                           (etaf-node 'text (list :color muted)
                                      (list (if subtitle (concat "  " subtitle) "")))))
          (etaf-node 'flex (list :height '(lh 1) :align-items 'center
                                 :column-gap '(ch 1))
                     (append (etaf-current-slot 'default)
                             (list (etaf-node 'etaf-ui--media-control
                                              (list :icon 'close :help "Close (Esc)"
                                                    :on-press close)
                                              nil))))))
        (air)
        ;; Stage: the media centered between optional navigation arrows.
        (etaf-node
         'flex
         (list :width 'stretch :height (list 'lh stage-rows) :align-items 'center)
         (list
          (arrow 'chevron-left on-previous "Previous (p)")
          (etaf-node
           'flex
           (list :flex-grow 1 :min-width '(ch 0) :height (list 'lh stage-rows)
                 :justify-content 'center :align-items 'center)
           (list
            (etaf-node
             'box
             (list :ref stage :width (list 'ch (car grid)) :height (list 'lh (cdr grid))
                   :overflow 'hidden
                   :on-press (when video toggle)
                   :help-echo (when video "Play / pause (Space)"))
             (list
              (if video
                  (etaf-node 'etaf-video
                             (list :src src :columns (car grid) :rows (cdr grid)
                                   :handle handle :autoplay autoplay
                                   :audio audio :speed speed)
                             nil)
                (etaf-node 'image (list :src src :columns (car grid)
                                        :rows (cdr grid))
                           nil))))))
          (arrow 'chevron-right on-next "Next (n)")))
        (air)
        ;; Footer: the transport bar for video, the caption for images.
        (if video
            (etaf-node
             'flex
             (list :ref footer :width 'stretch :height '(lh 1) :align-items 'center
                   :padding (list '(lh 0) (list 'ch etaf-ui--media-gutter))
                   :column-gap '(ch 1))
             (list
              (etaf-node 'etaf-ui-toggle-icon
                         (list :value playing :off 'play :on 'pause :set 'svg
                               :size 0.9 :min-width 4
                               :color (etaf-ui--media-color :control)
                               :help-echo "Play / pause (Space)"
                               :on-press toggle)
                         nil)
              (etaf-node 'etaf-ui--media-control
                         (list :label "−10" :help "Back 10 seconds (j)"
                               :on-press (lambda () (funcall seek-by -10)))
                         nil)
              (etaf-node 'etaf-ui--media-control
                         (list :label "+10" :help "Forward 10 seconds (l)"
                               :on-press (lambda () (funcall seek-by 10)))
                         nil)
              (etaf-node 'box (list :width '(ch 17) :height '(lh 1) :text-align 'center
                                    :flex-shrink 0 :color muted)
                         (list (etaf-view (text (expr (etaf-value clock))))))
              (etaf-node 'flex (list :flex-grow 1 :flex-basis '(ch 0)
                                     :min-width '(ch 4) :height '(lh 1))
                         (list (etaf-node 'etaf-range
                                          (list :min 0 :max 100 :bar-height 35
                                                :value progress
                                                :color accent
                                                :track-color (etaf-ui--media-color :track)
                                                :label "Seek"
                                                :on-commit seek-to)
                                          nil)))
              (etaf-node 'etaf-ui--media-control
                         (list :label (format "%gx" (etaf-value speed)) :width 6
                               :help "Playback speed (.)"
                               :on-press cycle-speed)
                         nil)
              (etaf-node 'etaf-ui-toggle-icon
                         (list :value audio :off 'volume-mute :on 'volume :set 'svg
                               :size 0.9 :min-width 4
                               :color (etaf-ui--media-color :control)
                               :help-echo "Sound (m)"
                               :on-press toggle-audio)
                         nil)))
          (etaf-node 'box (list :ref footer :width 'stretch :height '(lh 1)
                                :overflow 'hidden :wrap-mode 'none
                                :text-align 'center :color muted)
                     (list (or caption ""))))
        (air))))))

(etaf-define-component etaf-media-viewer
    (&key open (kind 'image) src source-size title subtitle caption on-close
          on-previous on-next (autoplay t))
  "Show SRC of KIND in a controlled modal viewer over the application."
  :validate
  (progn
    (etaf-check-prop :kind kind (memq kind '(image video)) "image or video")
    (etaf-check-prop :on-close on-close (functionp on-close) "a function")
    (etaf-check-prop :on-previous on-previous
                     (or (null on-previous) (functionp on-previous))
                     "a function or nil")
    (etaf-check-prop :on-next on-next (or (null on-next) (functionp on-next))
                     "a function or nil")
    (etaf-check-prop :source-size source-size
                     (or (null source-size)
                         (and (consp source-size)
                              (natnump (car source-size)) (natnump (cdr source-size))
                              (> (car source-size) 0) (> (cdr source-size) 0)))
                     "nil or (WIDTH . HEIGHT) in pixels")
    (etaf-check-prop :title title (or (null title) (stringp title)) "a string or nil")
    (etaf-check-prop :subtitle subtitle (or (null subtitle) (stringp subtitle))
                     "a string or nil")
    (etaf-check-prop :caption caption (or (null caption) (stringp caption))
                     "a string or nil"))
  :render
  (when (etaf-ui--reactive-value open)
    (etaf-node 'etaf-ui--media-viewer-open
               (list :kind kind :src src :source-size source-size :title title
                     :subtitle subtitle :caption caption :on-close on-close
                     :on-previous on-previous :on-next on-next :autoplay autoplay)
               (etaf-current-slot 'default))))

(provide 'etaf-ui-media)
;;; etaf-ui-media.el ends here
