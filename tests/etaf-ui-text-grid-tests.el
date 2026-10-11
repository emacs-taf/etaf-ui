;;; -*- lexical-binding: t; -*-
;;; etaf-ui-text-grid-tests.el --- Fixed-width text surface acceptance

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Code:
(require 'ert)
(require 'etaf-ui)

(ert-deftest etaf-ui-text-grid-updates-rows-with-stable-extents ()
  "Rows retain width, neighbors and text when the caller changes one value."
  (let ((buffer (generate-new-buffer " *text-grid*"))
        (rows (vector (etaf-ref "@...") (etaf-ref "中"))))
    (unwind-protect
        (progn
          (etaf-mount buffer
                      (etaf-view
                       (etaf-text-grid
                        :rows 2 :columns 4 :label "Map"
                        :row-ref (lambda (row) (if (zerop row) 'first 'second))
                        :row-text (lambda (row) (etaf-value (aref rows row))))))
          (let* ((runtime (etaf-runtime-for-buffer buffer))
                 (neighbor (etaf-host-ref-bounds runtime 'second)))
            (should-not (etaf-runtime-handler-entries runtime))
            (setf (etaf-value (aref rows 0)) ".@..")
            (should (equal neighbor (etaf-host-ref-bounds runtime 'second)))
            (dolist (pair '((first . ".@..") (second . "中  ")))
              (let ((bounds (etaf-host-ref-bounds runtime (car pair))))
                (should (equal (with-current-buffer buffer
                                 (buffer-substring-no-properties (car bounds) (cdr bounds)))
                               (cdr pair)))))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer))) (etaf-unmount runtime))
      (kill-buffer buffer))))

(ert-deftest etaf-ui-text-grid-rejects-invalid-shapes-and-text ()
  "Invalid shapes and text fail before publication."
  (let ((buffer (generate-new-buffer " *text-grid-invalid*")))
    (unwind-protect
        (progn
          (dolist (props '((:rows 0 :columns 2) (:rows 1 :columns 0)
                          (:rows 1 :columns 2 :row-text 42)))
            (should-error (etaf-mount buffer (etaf-node 'etaf-text-grid props nil))
                          :type 'etaf-component-call-error))
          (dolist (content '("wide" "a\nb" "a\rb" "a\tb" 42))
            (should-error
             (etaf-mount buffer
                         (etaf-view
                          (etaf-text-grid :rows 1 :columns 2
                                          :row-text (lambda (_row) content))))
             :type 'etaf-component-call-error)))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer))) (etaf-unmount runtime))
      (kill-buffer buffer))))

(provide 'etaf-ui-text-grid-tests)
;;; etaf-ui-text-grid-tests.el ends here
