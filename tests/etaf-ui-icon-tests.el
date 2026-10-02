;;; etaf-ui-icon-tests.el --- Public icon facility contracts -*- lexical-binding: t; -*-

;;; Commentary:
;; The batch suite observes registry values, rendered text properties and
;; ordinary ETAF Host bounds/events.  Physical fonts belong to icon-check.

;;; Code:

(require 'ert)
(require 'etaf-ui)

(ert-deftest etaf-ui-icon-registry-replaces-removes-and-validates ()
  "Registration round-trips specs, replaces atomically and removes names."
  (let ((spec '(:kind font :family "Monospace" :height 1.0 :glyphs ((play . "p")))))
    (unwind-protect
        (progn
          (should (eq (etaf-ui-icon-set-register 'test-icons spec) 'test-icons))
          (should (equal (etaf-ui-icon-set-spec 'test-icons) spec))
          (should (memq 'test-icons (etaf-ui-icon-sets)))
          (should (equal (etaf-ui-icon-names 'test-icons) '(play)))
          (should-not (memq 'pause (etaf-ui-icon-names 'test-icons)))
          (should (equal (cdr (assq 'play (plist-get (etaf-ui-icon-set-spec 'test-icons) :glyphs))) "p"))
          (should-error (etaf-ui-icon-set-register 'test-icons '(:kind font :height -1.0)) :type 'user-error)
          (should (equal (etaf-ui-icon-set-spec 'test-icons) spec))
          (etaf-ui-icon-set-register 'test-icons '(:kind font :family "Monospace" :height 0.5 :glyphs ((pause . "P"))))
          (should (equal (etaf-ui-icon-names 'test-icons) '(pause)))
          (etaf-ui-icon-set-remove 'test-icons)
          (should-not (etaf-ui-icon-set-spec 'test-icons))
          (should-not (memq 'test-icons (etaf-ui-icon-sets)))
          (should-not (etaf-ui-icon-set-remove 'test-icons))
          (should-error (etaf-ui-icon-names 'test-icons) :type 'user-error)
          (should-error (etaf-ui-icon-metrics 'test-icons) :type 'user-error))
      (etaf-ui-icon-set-remove 'test-icons))))

(ert-deftest etaf-ui-icon-lookup-distinguishes-missing-name-and-set ()
  "Absent names fall through styles; an unknown style is a usage error."
  (let ((etaf-ui-icon-default-set 'test-default))
    (unwind-protect
        (progn
          (etaf-ui-icon-set-register 'test-partial '(:kind svg :viewbox [0 0 14 14] :paths ((local . "<path/>")) :fallback ((local . "L"))))
          (etaf-ui-icon-set-register 'test-default '(:kind svg :viewbox [0 0 14 14] :paths ((play . "<path/>")) :fallback ((play . "D"))))
          (cl-letf (((symbol-function 'image-type-available-p) (lambda (_type) nil)))
            (should (string-match-p "D" (ebox-render (etaf-render (etaf-ui-icon 'play :set 'test-partial)))))
            (should (string-match-p "L" (ebox-render (etaf-render (etaf-ui-icon 'local :set 'test-partial)))))
            (should (string-match-p "never-an-icon" (ebox-render (etaf-render (etaf-ui-icon 'never-an-icon :set 'test-partial))))))
          (should-not (memq 'play (etaf-ui-icon-names 'test-partial)))
          (should (memq 'local (etaf-ui-icon-names)))
          (should-error (etaf-render (etaf-ui-icon 'play :set 'never-a-set))))
      (etaf-ui-icon-set-remove 'test-partial)
      (etaf-ui-icon-set-remove 'test-default))))

(ert-deftest etaf-ui-icon-svg-unavailable-has-printable-text-properties ()
  "Unavailable SVG uses the documented ASCII mark with native paint properties."
  (cl-letf (((symbol-function 'image-type-available-p) (lambda (_type) nil)))
    (let* ((output (ebox-render (etaf-render (etaf-ui-icon 'play :set 'svg :color "#123456"))))
           (position (string-match ">" output)))
      (should position)
      (should-not (get-text-property position 'display output))
      (should (get-text-property position 'face output))
      (should (>= (string-width (car (split-string output "\n"))) 2)))))

(ert-deftest etaf-ui-icon-box-keeps-two-rows-width-and-full-target ()
  "The two-row icon reserves both rows and a minimum-width pressable Host."
  (let ((buffer (generate-new-buffer " *etaf-ui-icon-test*")) (count 0))
    (unwind-protect
        (progn
          (etaf-mount buffer
                      (etaf-view (etaf-ui-icon :name 'play :set 'svg :lines 2
                                             :min-width 6 :ref 'icon :id 'play-icon
                                             :help-echo "Play" :class "player"
                                             :on-press (lambda () (cl-incf count)))))
          (let* ((runtime (etaf-runtime-for-buffer buffer))
                 (props (etaf-runtime-host-props-for runtime 'icon))
                 (bounds (etaf-host-ref-bounds runtime 'icon)))
            (should (equal (plist-get props :height) '(lh 2)))
            (should (equal (plist-get props :min-width) '(ch 6)))
            (should (eq (plist-get props :role) 'button))
            (should (equal (plist-get props :help-echo) "Play"))
            (should (string-match-p "player" (plist-get props :class)))
            (with-current-buffer buffer
              (let ((rows (split-string (buffer-substring (car bounds) (cdr bounds)) "\n")))
                (should (= (length rows) 2))
                (should (cl-every (lambda (row) (>= (ebox-string-pixel-width row)
                                                  (* 6 (frame-char-width)))) rows))))
            (etaf-dispatch-event runtime 'icon 'press)
            (should (= count 1))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer))) (etaf-unmount runtime))
      (kill-buffer buffer))))

(ert-deftest etaf-ui-icon-metrics-estimates-fit-without-gui ()
  "Frame-less batch metrics distinguish a fitting and an oversized declaration."
  (unwind-protect
      (progn
        (etaf-ui-icon-set-register 'test-metrics '(:kind font :family "Synthetic" :height 1.0 :glyphs ((play . "p"))))
        (cl-letf (((symbol-function 'display-graphic-p) (lambda (&optional _frame) nil)))
          (let ((fit (etaf-ui-icon-metrics 'test-metrics)))
            (should (equal (plist-get fit :family) "Synthetic"))
            (should (= (plist-get fit :height) 1.0))
            (should (= (plist-get fit :line-pixel-height) (frame-char-height)))
            (should (plist-get fit :fit)))
          (etaf-ui-icon-set-register 'test-metrics '(:kind font :family "Synthetic" :height 3.0 :glyphs ((play . "p"))))
          (let ((large (etaf-ui-icon-metrics 'test-metrics)))
            (should (> (plist-get large :line-pixel-height) (plist-get large :line-height)))
            (should-not (plist-get large :fit)))))
    (etaf-ui-icon-set-remove 'test-metrics)))

(ert-deftest etaf-ui-icon-validates-box-and-supports-registered-draw ()
  "A registered SVG draw style needs no renderer changes; invalid boxes fail."
  (unwind-protect
      (progn
        (etaf-ui-icon-set-register 'test-draw
                                  (list :kind 'svg :viewbox [0 0 14 14]
                                        :draw (list (cons 'play (lambda () "<path d='M2 2L12 7L2 12Z'/>")))
                                        :fallback '((play . "P"))))
        (should (equal (etaf-ui-icon-names 'test-draw) '(play)))
        (should (stringp (ebox-render (etaf-render (etaf-ui-icon 'play :set 'test-draw)))))
        (dolist (props '((:size 0) (:size -2) (:lines 3) (:min-width 0) (:on-press invalid)))
          (should-error (etaf-render (apply #'etaf-ui-icon 'play props)))))
    (etaf-ui-icon-set-remove 'test-draw)))

(defun etaf-ui-icon-test--foregrounds (text position)
  "Return the foreground colours recorded at POSITION in TEXT."
  (let ((face (get-text-property position 'face text)))
    (cl-loop for entry in (if (listp face) face (list face))
             when (and (consp entry) (plist-get entry :foreground))
             collect (plist-get entry :foreground))))

(ert-deftest etaf-ui-toggle-icon-switches-glyph-and-paint-through-value ()
  "A reactive VALUE switches both glyph and paint without remounting the box."
  (cl-letf (((symbol-function 'image-type-available-p) (lambda (_type) nil)))
    (let ((buffer (generate-new-buffer " *etaf-ui-toggle-icon*"))
          (playing (etaf-ref nil)))
      (unwind-protect
          (progn
            (etaf-ui-icon-set-register
             'test-toggle
             '(:kind svg :viewbox [0 0 14 14] :paths ((stop . "<path/>") (play . "<path/>"))
               :fallback ((stop . "S") (play . "P"))))
            (etaf-mount
             buffer
             (etaf-view
              (box :width '(ch 10) :height '(lh 2) :position 'relative
                (box :position 'absolute :left '(px 0) :top '(lh 0)
                     :width '(% 100) :height '(% 100) :z-index 0
                  (etaf-ui-toggle-icon :value playing :off 'stop :on 'play
                                       :set 'test-toggle :min-width 3 :color "#334455"
                                       :on-color "#AA1122" :ref 'toggle :help-echo "Play/Pause")))))
            (let* ((runtime (etaf-runtime-for-buffer buffer))
                   (text (lambda () (with-current-buffer buffer (buffer-string))))
                   (position-of (lambda (mark) (string-match mark (funcall text)))))
              (let ((props (etaf-runtime-host-props-for runtime 'toggle)))
                (should (equal (plist-get props :min-width) '(ch 3)))
                (should (equal (plist-get props :height) '(lh 1)))
                (should (eq (plist-get props :role) 'img))
                (should (equal (plist-get props :help-echo) "Play/Pause"))
                (should (equal (plist-get props :aria-label) "stop / play")))
              (should (string-match-p "S" (funcall text)))
              (should-not (string-match-p "P" (funcall text)))
              (should (member "#334455"
                              (etaf-ui-icon-test--foregrounds
                               (funcall text) (funcall position-of "S"))))
              (etaf-set-value playing t)
              (should (string-match-p "P" (funcall text)))
              (should-not (string-match-p "S" (funcall text)))
              (should (member "#AA1122"
                              (etaf-ui-icon-test--foregrounds
                               (funcall text) (funcall position-of "P"))))
              ;; A plain boolean is a settled variant, not a reactive source.
              (should (equal (plist-get (etaf-runtime-host-props-for runtime 'toggle) :height)
                             '(lh 1)))))
        (when-let* ((runtime (etaf-runtime-for-buffer buffer))) (etaf-unmount runtime))
        (kill-buffer buffer)
        (etaf-ui-icon-set-remove 'test-toggle)))))

;;; etaf-ui-icon-tests.el ends here
