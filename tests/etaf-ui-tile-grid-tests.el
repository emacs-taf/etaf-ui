;;; -*- lexical-binding: t; -*-
;;; etaf-ui-tile-grid-tests.el --- Controlled tile grid acceptance

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Exercise the grid only through the public View, event and Host query APIs.

;;; Code:
(require 'ert)
(require 'etaf-ui)

(ert-deftest etaf-ui-tile-grid-preserves-cell-metrics-in-resized-containers ()
  "Resizing a container preserves cell dimensions, text and activation coordinates."
  (let ((buffer (generate-new-buffer " *responsive tiles*")) selected)
    (unwind-protect
        (progn
          (etaf-mount buffer
                      (etaf-view
                       (etaf-tile-grid
                        :rows 2 :columns 4 :cell-width 2 :width '(vw 100)
                        :cell-ref (lambda (r c) (intern (format "responsive-%d-%d" r c)))
                        :cell-text (lambda (_r c) (number-to-string c))
                        :on-cell-press (lambda (r c) (setq selected (list r c)))))
                      '(:viewport-width 800 :viewport-height 10))
          (let ((runtime (etaf-runtime-for-buffer buffer)))
            (dolist (width '(800 400 1200))
              (etaf-runtime-refit runtime width 10)
              (dotimes (column 4)
                (let ((ref (intern (format "responsive-0-%d" column))))
                  (should (equal (etaf-host-ref-size runtime ref) (cons (* 2 (frame-char-width)) 1))))))
            (etaf-dispatch-event runtime 'responsive-1-3 'press)
            (should (equal selected '(1 3)))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer))) (etaf-unmount runtime))
      (kill-buffer buffer))))

(ert-deftest etaf-ui-tile-grid-follows-replaced-projection-callbacks ()
  "Replacing callbacks updates retained cell text, help and colors."
  (let ((buffer (generate-new-buffer " *tile callbacks*"))
        (alternate (etaf-ref nil)))
    (unwind-protect
        (progn
          (etaf-mount
           buffer
           (etaf-view
            (etaf-tile-grid
             :rows 1 :columns 1 :cell-ref (lambda (_r _c) 'tile)
             :cell-text (if (etaf-value alternate) (lambda (_r _c) "B") (lambda (_r _c) "A"))
             :cell-label (if (etaf-value alternate) (lambda (_r _c) "Second") (lambda (_r _c) "First"))
             :cell-color (if (etaf-value alternate) (lambda (_r _c) "#00FF00") (lambda (_r _c) "#FF0000")))))
          (setf (etaf-value alternate) t)
          (let* ((runtime (etaf-runtime-for-buffer buffer))
                 (props (etaf-runtime-host-props-for runtime 'tile)))
            (should (equal (plist-get props :aria-label) "Second"))
            (should (equal (plist-get props :color) "#00FF00"))
            (should (with-current-buffer buffer
                      (string-match-p "B" (buffer-substring-no-properties (point-min) (point-max)))))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer))) (etaf-unmount runtime))
      (kill-buffer buffer))))

(ert-deftest etaf-ui-tile-grid-controls-coordinates-and-retains-neighbors ()
  "Local caller writes repaint a tile without changing neighboring identities."
  (let ((buffer (generate-new-buffer " *tiles*"))
        (paint (etaf-ref "#334155")) (label (etaf-ref ".")) presses)
    (unwind-protect
        (progn
          (etaf-mount
           buffer
           (etaf-view
            (etaf-tile-grid
             :rows 2 :columns 3
             :cell-ref (lambda (row column) (intern (format "tile-%d-%d" row column)))
             :cell-label (lambda (row column) (format "Seat %d-%d" row column))
             :cell-color (lambda (_row _column) (etaf-value paint))
             :cell-background (lambda (row column)
                                (if (and (= row 0) (= column 1))
                                    (etaf-value paint) "#172033"))
             :cell-text (lambda (row column)
                          (if (and (= row 0) (= column 1)) (etaf-value label) "."))
             :on-cell-press (lambda (row column) (push (list row column) presses)))))
          (let* ((runtime (etaf-runtime-for-buffer buffer))
                 (neighbor (etaf-host-ref-bounds runtime 'tile-1-2))
                 (generation (etaf-runtime-revision runtime)))
            (etaf-dispatch-event runtime 'tile-0-1 'press)
            (should (equal presses '((0 1))))
            (should (equal (plist-get (etaf-runtime-host-props-for runtime 'tile-0-1)
                                     :aria-label) "Seat 0-1"))
            (should (equal (plist-get (etaf-runtime-host-props-for runtime 'tile-0-1)
                                     :help-echo) "Seat 0-1"))
            (etaf-batch
              (setf (etaf-value paint) "#22C55E" (etaf-value label) "S"))
            (should (> (etaf-runtime-revision runtime) generation))
            (should (equal (plist-get (etaf-runtime-host-props-for runtime 'tile-0-1) :color)
                           "#22C55E"))
            (should (equal (plist-get (etaf-runtime-host-props-for runtime 'tile-0-1)
                                     :background-color) "#22C55E"))
            (should (equal neighbor (etaf-host-ref-bounds runtime 'tile-1-2)))
            (let ((bounds (etaf-host-ref-bounds runtime 'tile-0-1)))
              (should (with-current-buffer buffer
                        (string-match-p "S" (buffer-substring-no-properties
                                              (car bounds) (cdr bounds))))))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer))) (etaf-unmount runtime))
      (kill-buffer buffer))))

(ert-deftest etaf-ui-tile-grid-read-only-and-invalid-input ()
  "Read-only grids have no callbacks; bad dimensions and labels fail explicitly."
  (let ((buffer (generate-new-buffer " *tiles-readonly*")))
    (unwind-protect
        (progn
          (etaf-mount buffer (etaf-view (etaf-tile-grid :rows 1 :columns 2)))
          (should-not (etaf-runtime-handler-entries (etaf-runtime-for-buffer buffer)))
          (etaf-unmount (etaf-runtime-for-buffer buffer))
          (dolist (props '((:rows 0 :columns 2) (:rows 2 :columns -1)
                          (:rows 1 :columns 1 :cell-width 0)
                          (:rows 1 :columns 1 :cell-text 42)
                          (:rows 1 :columns 1 :cell-label 42)))
            (should-error (etaf-mount buffer (etaf-node 'etaf-tile-grid props nil))
                          :type 'etaf-component-call-error))
          (should-error
           (etaf-mount buffer
                       (etaf-view (etaf-tile-grid :rows 1 :columns 1
                                                 :cell-text (lambda (_r _c) "too wide"))))
           :type 'etaf-component-call-error))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer))) (etaf-unmount runtime))
      (kill-buffer buffer))))

(provide 'etaf-ui-tile-grid-tests)
;;; etaf-ui-tile-grid-tests.el ends here
