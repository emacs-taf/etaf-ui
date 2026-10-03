;;; etaf-ui-tile-grid-tests.el --- Controlled tile grid acceptance -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Exercise the grid only through the public View, event and Host query APIs.

;;; Code:
(require 'ert)
(require 'etaf-ui)

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
             :cell-background (lambda (row column)
                                (if (and (= row 0) (= column 1))
                                    (etaf-value paint) "#172033"))
             :cell-text (lambda (row column)
                          (if (and (= row 0) (= column 1)) (etaf-value label) "."))
             :on-cell-press (lambda (row column) (push (list row column) presses)))))
          (let* ((runtime (etaf-runtime-for-buffer buffer))
                 (neighbor (etaf-host-ref-bounds runtime 'tile-1-2))
                 (generation (etaf-runtime-generation runtime)))
            (etaf-dispatch-event runtime 'tile-0-1 'press)
            (should (equal presses '((0 1))))
            (etaf-batch
              (setf (etaf-value paint) "#22C55E" (etaf-value label) "S"))
            (should (> (etaf-runtime-generation runtime) generation))
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
                          (:rows 1 :columns 1 :cell-text 42)))
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
