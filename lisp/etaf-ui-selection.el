;;; etaf-ui-selection.el --- Selection and value controls -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Selection controls are controlled Components.  They compose Button and
;; preserve the same VALUE/ON-CHANGE or writable REF contract as Checkbox.

;;; Code:

(require 'cl-lib)
(require 'etaf-ui-basic)

(defun etaf-ui--selection-options (options component)
  "Validate alist OPTIONS for COMPONENT and return it unchanged."
  (etaf-check-prop :options options (and (proper-list-p options) options)
                   "a nonempty alist of scalar values and labels" component)
  (let (values labels)
    (dolist (option options)
      (etaf-check-prop :options option
                       (and (consp option)
                            (or (symbolp (car option))
                                (numberp (car option))
                                (stringp (car option)))
                            (stringp (cdr option))
                            (not (string-empty-p (cdr option)))
                            (not (member (car option) values))
                            (not (member (cdr option) labels)))
                       "an alist with unique scalar values and labels" component)
      (push (car option) values)
      (push (cdr option) labels)))
  options)

(defun etaf-ui--selection-colors (selected disabled)
  "Return (FG BG BORDER) for SELECTED and DISABLED selection controls.
Selection controls are tonal pills like Buttons: a selected control paints
the secondary button tint, an unselected one inherits its surface, and no
control carries an outline.  The secondary tokens are dialog tokens, so a
selected control stays crisp inside a modal above a dimmed shell."
  (let* ((fg (cond (disabled :ui-disabled-fg)
                   (selected :ui-button-secondary-fg)
                   (t :ui-fg)))
         (bg (cond (disabled :ui-disabled-bg)
                   (selected :ui-button-secondary-bg)))
         (theme (etaf-ui--style-tokens fg (or bg :ui-disabled-bg))))
    (list (plist-get theme fg) (and bg (plist-get theme bg)) nil)))

(etaf-define-component etaf-radio
    (&key (value etaf-ui--unsupplied) options (label "Choice")
          (on-change etaf-ui--unsupplied) disabled bind)
  "Render a controlled single-choice RADIO group.
OPTIONS is an alist of unique scalar values and labels.  VALUE/ON-CHANGE or
the writable BIND ref owns the selected value; the Component owns no state."
  :render
  (let* ((input (etaf-ui--controlled-input 'etaf-radio :value bind value on-change))
         (current (etaf-ui--reactive-value (car input)))
         (callback (cdr input)))
    (etaf-ui--selection-options options 'etaf-radio)
    (etaf-check-prop :label label (stringp label) "a string" 'etaf-radio)
    (etaf-check-prop :value current
                     (or (null current) (assoc current options))
                     "nil or a value in :options" 'etaf-radio)
    (etaf-view
     (column :class "etaf-radio-group" :role 'radiogroup :width 'stretch
       (etaf-label :text label :variant 'strong)
       (row :item-gap '(ch 1)
         (expr
          (mapcar
           (lambda (option)
             (let* ((key (car option))
                    (caption (cdr option))
                    (selected (equal key current))
                    (colors (etaf-ui--selection-colors selected disabled)))
               (etaf-view
                (etaf-button
                 :label (concat (if selected "(o) " "( ) ") caption)
                 :aria-label caption :variant 'ghost :disabled disabled
                 :color (nth 0 colors) :bgcolor (nth 1 colors)
                 :border (nth 2 colors)
                 :on-press (and (not disabled) callback
                                (lambda () (funcall callback key)))))))
           options)))))))

(etaf-define-component etaf-switch
    (&key (checked etaf-ui--unsupplied) (label "Switch")
          (on-change etaf-ui--unsupplied) disabled bind)
  "Render a controlled binary SWITCH using CHECKED/ON-CHANGE or BIND."
  :render
  (let* ((input (etaf-ui--controlled-input 'etaf-switch :checked bind checked on-change))
         (current (etaf-ui--reactive-value (car input)))
         (callback (cdr input))
         (colors (etaf-ui--selection-colors current disabled)))
    (etaf-check-prop :checked current (booleanp current) "a boolean" 'etaf-switch)
    (etaf-check-prop :label label (stringp label) "a string" 'etaf-switch)
    (etaf-view
     (etaf-button
      :label (format "%s %s" (if current "[x]" "[ ]") label)
      :aria-label label :variant 'ghost :disabled disabled
      :color (nth 0 colors) :bgcolor (nth 1 colors) :border (nth 2 colors)
      :on-press (and (not disabled) callback
                     (lambda () (funcall callback (not current))))))))

(etaf-define-component etaf-segmented
    (&key (value etaf-ui--unsupplied) options (on-change etaf-ui--unsupplied)
          disabled bind)
  "Render a compact controlled SEGMENTED selector from OPTIONS."
  :render
  (let* ((input (etaf-ui--controlled-input 'etaf-segmented :value bind value on-change))
         (current (etaf-ui--reactive-value (car input)))
         (callback (cdr input)))
    (etaf-ui--selection-options options 'etaf-segmented)
    (etaf-check-prop :value current
                     (or (null current) (assoc current options))
                     "nil or a value in :options" 'etaf-segmented)
    (etaf-view
     (row :class "etaf-segmented" :role 'tablist :item-gap '(ch 2)
       (expr
        (mapcar
         (lambda (option)
           (let* ((key (car option)) (caption (cdr option))
                  (selected (equal key current)))
             (etaf-view
              (etaf-button :label (if selected (concat "* " caption) caption)
                           :aria-label caption
                           :variant (if selected 'secondary 'ghost)
                           :disabled disabled
                           :on-press (and (not disabled) callback
                                          (lambda () (funcall callback key)))))))
         options))))))

(etaf-define-component etaf-slider
    (&key (value etaf-ui--unsupplied) (min 0) (max 100) (step 1)
          (label "Value") (on-change etaf-ui--unsupplied) disabled bind)
  "Render a controlled numeric SLIDER using the native number prompt.
VALUE must be an integer in MIN..MAX; STEP is a positive integer.  The
native prompt keeps editing accessible while the Component remains reusable."
  :validate
  (progn
    (etaf-check-prop :min min (integerp min) "an integer" 'etaf-slider)
    (etaf-check-prop :max max (and (integerp max) (<= min max))
                     "an integer greater than or equal to :min" 'etaf-slider)
    (etaf-check-prop :step step (and (integerp step) (> step 0))
                     "a positive integer" 'etaf-slider)
    (etaf-check-prop :label label (stringp label) "a string" 'etaf-slider))
  :render
  (let* ((input (etaf-ui--controlled-input 'etaf-slider :value bind value on-change))
         (current (etaf-ui--reactive-value (car input)))
         (callback (cdr input)))
    (etaf-check-prop :value current
                     (and (integerp current) (<= min current max)
                          (zerop (% (- current min) step)))
                     "an integer aligned to :step within :min..:max" 'etaf-slider)
    (etaf-view
     (column :class "etaf-slider" :width 'stretch
       (row :item-gap '(ch 1)
         (etaf-label :text label :variant 'strong)
         (etaf-label :text (format "%d" current) :variant 'muted))
       (etaf-button :label (format "◀  %d  ▶" current) :variant 'secondary
                    :disabled disabled :aria-label label
                    :on-press
                    (and (not disabled) callback
                         (lambda ()
                           (let ((next (etaf-call-with-input
                                        (lambda ()
                                          (read-number (format "%s (%d-%d): " label min max)
                                                       current)))))
                             (unless (and (integerp next) (<= min next max)
                                          (zerop (% (- next min) step)))
                               (user-error "%s must be aligned to %d from %d to %d"
                                           label step min max))
                             (funcall callback next)))))))))

;;; ---------------------------------------------------------------------------
;;; Range
;;; ---------------------------------------------------------------------------

(defun etaf-ui--range-ratio-at-gesture (gesture track)
  "Return the pointer's fraction along GESTURE's TRACK Host, or nil.
TRACK names the measured Host; GESTURE's own :host-ref is used when TRACK is
nil, so a caller that omits the component's :ref still hit-tests the element
the pointer pressed."
  (let* ((window (plist-get gesture :window))
         (buffer (or (plist-get gesture :buffer)
                     (and (window-live-p window) (window-buffer window))))
         (host (or track (plist-get gesture :host-ref)))
         (xy (plist-get gesture :position))
         (runtime (and buffer (etaf-runtime-for-buffer buffer)))
         (bounds (and runtime host (etaf-host-ref-bounds runtime host))))
    (when (and bounds (consp xy) (numberp (car xy)))
      (with-current-buffer buffer
        (let* ((start (car bounds))
               (end (cdr bounds))
               (origin (save-excursion (goto-char start) (line-beginning-position)))
               ;; Pixel measurement still belongs to the engine layer; the
               ;; ETAF wrapper lands with the framework measurement pass.
               (left (ebox-string-pixel-width (buffer-substring origin start)))
               (width (ebox-string-pixel-width (buffer-substring start end))))
          (when (> width 0)
            (max 0.0 (min 1.0 (/ (- (float (car xy)) left) width)))))))))

(defun etaf-ui--range-value-at-ratio (ratio min max step)
  "Return RATIO of the MIN..MAX span clamped to the bounds and snapped to STEP."
  (let ((clamped (max min (min max (+ min (* ratio (- max min)))))))
    (if (null step)
        clamped
      (let ((snapped (+ min (* step (fround (/ (- clamped min) (float step)))))))
        (max min (min max (if (and (integerp min) (integerp max) (integerp step))
                              (round snapped)
                            snapped)))))))

(etaf-define-component etaf-range
    (&key value (min 0) (max 100) step on-change on-commit disabled
          color track-color (bar-height 40) label ref fill-ref)
  "Render an interactive horizontal RANGE: progress, seek or volume bar.

VALUE is a number or reactive source within MIN..MAX, and is snapped to STEP
when STEP is non-nil.  The range is controlled: it never stores the value.
A pointer click reports the pointed value through ON-CHANGE and ON-COMMIT;
dragging reports intermediate values through ON-CHANGE and the released value
through ON-COMMIT.  Both callbacks receive one number.

The bar paints a Track and a Fill as absolutely positioned Hosts inside one
standard row, so it never changes the line height.  FILL-REF names the Fill
Host and REF names the Track Host; a caller may prepare an Ebox update on
FILL-REF and replace its `:width' percentage without republishing the View.
BAR-HEIGHT is the painted thickness as a percentage of that row (default 40)."
  :validate
  (progn
    (etaf-check-prop :min min (numberp min) "a number" 'etaf-range)
    (etaf-check-prop :max max (and (numberp max) (> max min))
                     "a number greater than :min" 'etaf-range)
    (etaf-check-prop :step step (or (null step) (and (numberp step) (> step 0)))
                     "a positive number or nil" 'etaf-range)
    (etaf-check-prop :bar-height bar-height (and (integerp bar-height) (> bar-height 0)
                                                  (<= bar-height 100))
                     "an integer percentage from 1 through 100" 'etaf-range)
    (etaf-check-prop :on-change on-change (or (null on-change) (functionp on-change))
                     "a function or nil" 'etaf-range)
    (etaf-check-prop :on-commit on-commit (or (null on-commit) (functionp on-commit))
                     "a function or nil" 'etaf-range)
    (etaf-check-prop :disabled disabled (booleanp disabled) "a boolean" 'etaf-range))
  :bindings ((rule (make-string 512 ?─)))
  :render
  (let* ((raw (etaf-ui--reactive-value value))
         (ratio (if (numberp raw)
                    (max 0.0 (min 1.0 (/ (float (- raw min)) (- max min))))
                  0.0))
         (percent (list '% (* 100.0 ratio)))
         (report (lambda (gesture commit)
                   (when-let* ((ratio (etaf-ui--range-ratio-at-gesture gesture ref)))
                     (let ((next (etaf-ui--range-value-at-ratio ratio min max step)))
                       (if commit
                           (when on-commit (funcall on-commit next))
                         (when on-change (funcall on-change next))))))))
    (etaf-view
     (flex :flex-direction 'row :class "etaf-range" :width 'stretch :height '(lh 1)
          :position 'relative :overflow 'hidden
          :role 'slider :tab-index (unless disabled 0)
          :aria-label (or label "Range")
          :disabled disabled
          :on-press (and (not disabled)
                         (lambda (gesture)
                           (funcall report gesture nil)
                           (funcall report gesture t)))
          :on-drag (and (not disabled)
                        (lambda (gesture)
                          (funcall report gesture (eq (plist-get gesture :phase) 'end))))
          :ref ref :id (and ref (symbol-name ref))
       ;; The track is ordinary flow content: it gives the row its width and a
       ;; measurable text span for pointer hit-testing and tests.
       (box :height '(lh 1) :overflow 'hidden :flex-grow 1 :flex-basis '(px 0)
            :min-width '(px 0)
            :color (or track-color (etaf-theme-token :ui-range-track "#C9CED6"))
         (text (expr rule)))
       ;; The fill is an absolutely positioned Host: a prepared geometry update
       ;; replaces its width without a View publication.  Flow children cannot
       ;; be resized in place (their neighbours move), which is why the fill is
       ;; an overlay painted above the track.
       (box :position 'absolute :left '(px 0) :top '(lh 0)
            :width percent :height '(lh 1) :overflow 'hidden
            :color (or color (etaf-theme-token :ui-range-fill "#D8232A"))
            :ref fill-ref :id (and fill-ref (symbol-name fill-ref))
         (text (expr rule)))))))

(provide 'etaf-ui-selection)
;;; etaf-ui-selection.el ends here
