;;; etaf-ui-feedback.el --- Status and feedback ETAF Components -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Presentational Components share semantic Theme tokens and caller-owned values.

;;; Code:
(require 'etaf-ui-basic)

(defun etaf-ui--feedback-keys (variant)
  "Return foreground, background and border palette keys for VARIANT."
  (pcase variant
    ('success '(:ui-success-fg :ui-success-bg :ui-success-border))
    ('warning '(:ui-warning-fg :ui-warning-bg :ui-warning-border))
    ('danger '(:ui-danger-fg :ui-danger-bg :ui-danger-border))
    ('info '(:ui-info-fg :ui-info-bg :ui-info-border))
    (_ '(:ui-fg :ui-bg :ui-border))))

(defun etaf-ui--feedback-theme (variant)
  "Return foreground, background and border tokens for VARIANT."
  (mapcar (lambda (key) (etaf-theme-token key (plist-get etaf-ui--style-palette key)))
          (etaf-ui--feedback-keys variant)))

(etaf-define-component etaf-badge (&key text (variant 'neutral))
  "Render compact TEXT status with semantic VARIANT styling."
  :render
  (let ((theme (etaf-ui--feedback-theme variant)))
    (etaf-view
     (box :class "etaf-badge" :role 'status :width 'max-content
          :padding-inline '(ch 1) :font-weight 'bold
          :color (nth 0 theme) :background-color (nth 1 theme)
       (text (expr (etaf-ui--text-value text)))))))

(etaf-define-component etaf-divider (&key (orientation 'horizontal) label)
  "Render a horizontal or vertical separator with optional horizontal LABEL."
  :validate
  (etaf-check-prop :orientation orientation (memq orientation '(horizontal vertical))
                   "horizontal or vertical" 'etaf-divider)
  :render
  (if (eq orientation 'vertical)
      (etaf-view
       (box :class "etaf-divider" :width '(px 1) :height 'stretch
            :background-color (etaf-theme-token :ui-border "#687386")))
    (etaf-view
     (flex :class "etaf-divider" :width 'stretch :align-items 'center
           :column-gap (when label '(ch 1))
       (box :flex-grow 1 :flex-basis '(px 0) :min-width '(px 0)
            :height '(lh 1) :border-bottom
            (etaf-ui--style-border (etaf-theme-token :ui-border "#687386")))
       (expr (when label (etaf-view (etaf-label :text label :variant 'muted))))
       (box :flex-grow 1 :flex-basis '(px 0) :min-width '(px 0)
            :height '(lh 1) :border-bottom
            (etaf-ui--style-border (etaf-theme-token :ui-border "#687386")))))))

(etaf-define-component etaf-progress (&key value (max 100) label (variant 'success))
  "Render VALUE out of positive MAX; both accept numbers or reactive values."
  :render
  (let* ((value (etaf-ui--reactive-value value))
         (max (etaf-ui--reactive-value max))
         (theme (etaf-ui--feedback-theme variant)))
    (etaf-check-prop :max max (and (numberp max) (> max 0))
                     "a positive number" 'etaf-progress)
    (etaf-check-prop :value value (and (numberp value) (<= 0 value max))
                     "a number from zero through :max" 'etaf-progress)
    (let ((percent (round (/ (* 100.0 value) max))))
      (etaf-view
       (column :class "etaf-progress" :width 'stretch
         (row :item-gap '(ch 1)
           (etaf-label :text label :variant 'strong)
           (etaf-label :text (format "%d%%" percent) :variant 'muted))
         (box :width 'stretch :height '(lh 1)
              :background-color (etaf-theme-token :ui-progress-track "#E2E8F0")
           (box :width (list '% percent) :height '(lh 1)
                :background-color (nth 0 theme))))))))

(etaf-define-component etaf-alert
    (&key title message (variant 'info) dismissible on-dismiss)
  "Render status text; DISMISSIBLE invokes caller-owned ON-DISMISS."
  :validate
  (progn
    (etaf-check-prop :title title (or (null title) (stringp title))
                     "a string or nil" 'etaf-alert)
    (etaf-check-prop :on-dismiss on-dismiss (or (not dismissible) (functionp on-dismiss))
                     "a function when dismissible" 'etaf-alert))
  :render
  (let ((theme (etaf-ui--feedback-theme variant)))
    (etaf-view
     (flex :class "etaf-alert" :width 'stretch :role 'alert
           :padding '((lh 1) (ch 2)) :column-gap '(ch 1)
           :color (nth 0 theme) :background-color (nth 1 theme)
       (column :flex-grow 1 :min-width '(px 0)
         (etaf-label :text title :variant 'strong :color (nth 0 theme))
         (etaf-label :text message :color (nth 0 theme) :wrap-mode 'word))
       (expr
        (when dismissible
          (etaf-view
           (etaf-button :label "×" :variant 'ghost :aria-label "Dismiss"
                        :on-press on-dismiss))))))))

(etaf-define-component etaf-statistic (&key label value trend)
  "Render a three-line metric; callers own its container spacing and surface."
  :view
  (column :class "etaf-statistic"
    (etaf-label :text label :variant 'muted)
    (etaf-label :text value :variant 'heading)
    (etaf-label :text trend :variant 'success)))

(etaf-define-component etaf-empty
    (&key (title "Nothing here") description action-label on-action)
  "Render an empty state with optional description and action."
  :validate
  (etaf-check-prop :on-action on-action (or (null action-label) (functionp on-action))
                   "a function when :action-label is supplied" 'etaf-empty)
  :view
  (column :class "etaf-empty" :width 'stretch :padding '((lh 1) (ch 2))
          :cross-align 'center :item-gap '(lh 1)
    (etaf-label :text title :variant 'strong)
    (etaf-label :text description :variant 'muted)
    (expr (when action-label
            (etaf-view (etaf-button :label action-label :on-press on-action))))))

(etaf-define-component etaf-skeleton (&key (width 'stretch) (height '(lh 1)))
  "Render a loading placeholder with WIDTH and HEIGHT."
  :view
  (box :class "etaf-skeleton" :width width :height height
       :background-color (etaf-theme-token :ui-progress-track "#E2E8F0")))

(etaf-define-component etaf-card (&key title description (variant 'default))
  "Render a reusable surface with optional TITLE and DESCRIPTION slots."
  :render
  (let ((theme (etaf-ui--style-tokens :ui-panel-fg :ui-panel-bg :ui-panel-border)))
    (etaf-view
     (column :class (format "etaf-card %s" variant) :width 'stretch
             :padding '((lh 1) (ch 2))
             :color (plist-get theme :ui-panel-fg)
             :background-color (plist-get theme :ui-panel-bg)
             :border (etaf-ui--style-border (plist-get theme :ui-panel-border))
             :item-gap '(lh 1)
       (expr (when title (etaf-view (etaf-label :text title :variant 'strong))))
       (expr (when description (etaf-view (etaf-label :text description :variant 'muted))))
       (expr (etaf-current-slot 'default))))))

(defvar etaf-ui--avatar-cache (make-hash-table :test #'equal)
  "Round avatar image descriptors keyed by their source and pixel size.")

(defun etaf-ui--avatar-columns (size lines)
  "Return the integer column count of avatar SIZE, LINES high."
  (cond ((natnump size) (max 1 size))
        ((and (consp size) (eq (car size) 'ch) (natnump (cadr size)))
         (max 1 (cadr size)))
        (t (* 2 lines))))

(defun etaf-ui--avatar-photo (src)
  "Return (MIME . BASE64) for avatar photo SRC, or nil when unreadable."
  (let* ((descriptor (and (consp src) (eq (car src) 'image) (cdr src)))
         (file (if descriptor (plist-get descriptor :file) src))
         (data (and descriptor (plist-get descriptor :data)))
         (type (or (and descriptor (plist-get descriptor :type))
                   (and (stringp file) (image-supported-file-p file)))))
    (when (and (null data) (stringp file) (file-readable-p file))
      (setq data (with-temp-buffer
                   (set-buffer-multibyte nil)
                   (insert-file-contents-literally file)
                   (buffer-string))))
    (when (and (stringp data) (memq type '(png jpeg gif webp svg)))
      (cons (format "image/%s" (if (eq type 'svg) "svg+xml" type))
            (base64-encode-string
             (if (multibyte-string-p data) (encode-coding-string data 'binary) data)
             t)))))

(defun etaf-ui--avatar-image (src initials foreground background columns lines)
  "Return a round avatar descriptor COLUMNS by LINES cells, or nil.
SRC is a photo source; without a readable photo, draw INITIALS in
FOREGROUND on a BACKGROUND circle."
  (when (and (display-images-p) (image-type-available-p 'svg))
    (let* ((cw (frame-char-width)) (lh (frame-char-height))
           (key (list src initials foreground background columns lines cw lh)))
      (or (gethash key etaf-ui--avatar-cache)
          (let* ((width (* columns cw)) (height (* lines lh))
                 (d (min width height)) (r (/ d 2.0))
                 (cx (/ width 2.0)) (cy (/ height 2.0))
                 (photo (and src (etaf-ui--avatar-photo src)))
                 (body
                  (if photo
                      (format "<defs><clipPath id='c'><circle cx='%s' cy='%s' r='%s'/></clipPath></defs><image x='%s' y='%s' width='%d' height='%d' preserveAspectRatio='xMidYMid slice' clip-path='url(#c)' xlink:href='data:%s;base64,%s'/>"
                              cx cy r (- cx r) (- cy r) d d (car photo) (cdr photo))
                    (format "<circle cx='%s' cy='%s' r='%s' fill='%s'/><text x='%s' y='%s' text-anchor='middle' dominant-baseline='central' font-family='%s' font-weight='bold' font-size='%s' fill='%s'>%s</text>"
                            cx cy r background cx cy
                            (xml-escape-string (or (face-attribute 'default :family nil t) "sans-serif"))
                            (round (* d (if (> (length initials) 1) 0.38 0.46)))
                            foreground (xml-escape-string initials)))))
            (when (> (hash-table-count etaf-ui--avatar-cache) 1024)
              (clrhash etaf-ui--avatar-cache))
            (puthash key
                     (list 'image :type 'svg
                           :data (format "<svg xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink' width='%d' height='%d' viewBox='0 0 %d %d'>%s</svg>"
                                         width height width height body))
                     etaf-ui--avatar-cache))))))

(etaf-define-component etaf-avatar (&key name initials src (size '(ch 5))
                                        (variant 'info) (lines 3) background
                                        (shape 'circle))
  "Render an AVATAR with caller-provided NAME tooltip text.
SRC is an optional photo file or image descriptor.  On graphical frames
SHAPE `circle' draws the photo, or the initials on a colored disc, as a
round image; `square' and text frames use an initials box.  LINES sets its
height; BACKGROUND replaces VARIANT's colors with white initials on it."
  :validate
  (etaf-check-prop :shape shape (memq shape '(circle square))
                   "circle or square" 'etaf-avatar)
  :render
  (let* ((name (etaf-ui--text-value name))
         (initials (etaf-ui--text-value initials))
         (initials (if (string-empty-p initials)
                       (if (string-empty-p name) "?"
                         (upcase (substring name 0 (min 2 (length name)))))
                     initials))
         (theme (etaf-ui--feedback-theme variant)))
    (unless (and (integerp lines) (> lines 0))
      (signal 'wrong-type-argument (list 'natnump lines)))
    (let* ((columns (etaf-ui--avatar-columns size lines))
           (keys (etaf-ui--feedback-keys variant))
           ;; Only the avatar's own two colors are resolved: other palette
           ;; entries may be deferred tokens (hover fills), which a palette
           ;; resolution would reject as colors.
           (palette (and (eq shape 'circle)
                         (etaf-theme-resolve-palette
                          (list (nth 0 keys) (plist-get etaf-ui--style-palette (nth 0 keys))
                                (nth 1 keys) (plist-get etaf-ui--style-palette (nth 1 keys)))
                          (etaf-theme-current-mode))))
           (image (and (eq shape 'circle)
                       (etaf-ui--avatar-image
                        (etaf-ui--reactive-value src) initials
                        (if background "#FFFFFF"
                          (plist-get palette (nth 0 (etaf-ui--feedback-keys variant))))
                        (or background
                            (plist-get palette (nth 1 (etaf-ui--feedback-keys variant))))
                        columns lines))))
      (if image
          (etaf-view
           (box :class "etaf-avatar" :role 'img :aria-label name
                :width (list 'ch columns) :height (list 'lh lines)
                :flex-shrink 0
             (image :src image :columns columns :rows lines)))
        (etaf-view
         (box :class "etaf-avatar" :role 'img :aria-label name :width size
              :height (list 'lh lines) :box-sizing 'border-box
              :padding-top (list 'lh (/ (1- lines) 2))
              :text-align 'center :font-weight 'bold
              :color (if background "#FFFFFF" (nth 0 theme))
              :background-color (or background (nth 1 theme))
              :border (unless background (nth 2 theme))
           (text (expr initials))))))))

(etaf-define-component etaf-timeline (&key items)
  "Render chronological ITEMS with :title, :content and optional :status."
  :validate
  (etaf-check-prop :items items (and (proper-list-p items) items)
                   "a nonempty list of item plists" 'etaf-timeline)
  :render
  (etaf-view
   (column :class "etaf-timeline" :width 'stretch :item-gap '(lh 1)
     (expr
      (mapcar
       (lambda (item)
         (etaf-view
          (row :item-gap '(ch 1)
            (etaf-badge :text (or (plist-get item :status) "Update") :variant 'info)
            (column :item-gap '(lh 0)
              (etaf-label :text (plist-get item :title) :variant 'strong)
              (etaf-label :text (plist-get item :content) :variant 'muted)))))
       items)))))

(etaf-define-component etaf-tag
    (&key text (variant 'neutral) closable on-close)
  "Render a compact TAG with optional caller-owned close action."
  :validate
  (etaf-check-prop :on-close on-close (or (not closable) (functionp on-close))
                   "a function when closable" 'etaf-tag)
  :render
  (let ((theme (etaf-ui--feedback-theme variant)))
    (etaf-view
     (row :class "etaf-tag" :item-gap '(ch 1) :width 'max-content
          :padding-inline '(ch 1) :background-color (nth 1 theme)
       (etaf-label :text text :color (nth 0 theme))
       (expr (when closable
               (etaf-view
                (etaf-button :label "×"
                             :aria-label (format "Remove %s" (etaf-ui--text-value text))
                             :variant 'ghost :color (nth 0 theme) :bgcolor (nth 1 theme)
                             :border (nth 1 theme)
                             :on-press on-close))))))))

(etaf-define-component etaf-kbd (&key keys)
  "Render keyboard KEYS as a compact accessible keycap group."
  :validate
  (etaf-check-prop :keys keys
                   (and (proper-list-p keys) keys
                        (cl-every (lambda (key) (and (stringp key)
                                                    (not (string-empty-p key)))) keys))
                   "a nonempty list of strings" 'etaf-kbd)
  :view
  (row :class "etaf-kbd" :item-gap '(ch 1) :width 'max-content
    (expr (mapcar (lambda (key)
                    (etaf-view
                     (box :padding '((lh 0) (ch 1)) :border
                          (etaf-ui--style-border (etaf-theme-token :ui-border "#687386"))
                       (text (expr key)))))
                  keys))))

(provide 'etaf-ui-feedback)
;;; etaf-ui-feedback.el ends here
