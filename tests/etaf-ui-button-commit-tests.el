;;; etaf-ui-button-commit-tests.el --- Button callback publication -*- lexical-binding: t; -*-

;;; Commentary:

;; Public Button callbacks follow the same commit boundary as their visible UI.

;;; Code:

(require 'ert)
(require 'etaf-ui)

(ert-deftest etaf-ui-button-callback-uses-only-committed-props ()
  "A later sibling failure cannot replace the live Button callback."
  (let ((label (etaf-ref "A"))
        (buffer (generate-new-buffer " *button-commit*"))
        events)
    (unwind-protect
        (progn
          (etaf-mount
           buffer
           (lambda ()
             (let ((caption (etaf-value label)))
               (etaf-view
                (column
                 (etaf-button :ref 'button-commit :label caption
                  :on-press (lambda () (push caption events)))
                 (text (expr (if (equal (etaf-value label) "Rejected")
                                 (error "Rejected sibling")
                               "Sibling"))))))))
          (let ((runtime (etaf-runtime-for-buffer buffer)))
            (etaf-dispatch-event runtime 'button-commit 'press)
            (setf (etaf-value label) "B")
            (etaf-dispatch-event runtime 'button-commit 'press)
            (let ((published (with-current-buffer buffer (buffer-string)))
                  (generation (etaf-runtime-current-generation runtime)))
              (should-error (setf (etaf-value label) "Rejected"))
              (should (eq generation (etaf-runtime-current-generation runtime)))
              (should (equal-including-properties
                       published (with-current-buffer buffer (buffer-string)))))
            (etaf-dispatch-event runtime 'button-commit 'press)
            (should (equal '("B" "B" "A") events))
            (setf (etaf-value label) "C")
            (etaf-dispatch-event runtime 'button-commit 'press)
            (should (equal '("C" "B" "B" "A") events))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer)))
        (etaf-unmount runtime))
      (kill-buffer buffer))))

(ert-deftest etaf-ui-button-stable-callback-keeps-handler-identity ()
  "An unchanged caller callback remains stable through presentation updates."
  (let ((label (etaf-ref "A"))
        (callback #'ignore)
        (buffer (generate-new-buffer " *button-stable-callback*")))
    (unwind-protect
        (progn
          (etaf-mount
           buffer
           (lambda ()
             (etaf-view
              (etaf-button :ref 'button-stable :label (etaf-value label)
                           :on-press callback))))
          (let* ((runtime (etaf-runtime-for-buffer buffer))
                 (handler (cdr (assq 'press
                                      (etaf-runtime-handler-for
                                       runtime 'button-stable)))))
            (setf (etaf-value label) "B")
            (should (eq handler
                        (cdr (assq 'press
                                   (etaf-runtime-handler-for
                                    runtime 'button-stable)))))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer)))
        (etaf-unmount runtime))
      (kill-buffer buffer))))

(provide 'etaf-ui-button-commit-tests)
;;; etaf-ui-button-commit-tests.el ends here
