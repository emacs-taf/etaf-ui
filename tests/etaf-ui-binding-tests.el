;;; etaf-ui-binding-tests.el --- Controlled ref bindings -*- lexical-binding: t; -*-

;;; Commentary:
;; Compare shorthand and explicit inputs through mounted controls and events.

;;; Code:
(require 'ert)
(require 'etaf-ui)

(ert-deftest etaf-ui-checkbox-binding-shares-the-callers-ref ()
  "Bound and explicit controls render and update the same caller-owned value."
  (let ((done (etaf-ref nil))
        (disabled (etaf-ref nil))
        (buffer (generate-new-buffer " *checkbox-binding*"))
        observed)
    (unwind-protect
        (progn
          (etaf-mount
           buffer
           (etaf-view
            (column
             (etaf-checkbox :bind done :ref 'bound :label "Bound"
                            :disabled (etaf-value disabled)
                            :on-press (lambda () (push (etaf-value done) observed)))
             (etaf-checkbox :checked (etaf-value done) :ref 'explicit :label "Explicit"
                            :on-change (lambda (next) (setf (etaf-value done) next))))))
          (let ((runtime (etaf-runtime-for-buffer buffer)))
            (cl-labels ((check (mark)
                         (let ((text (with-current-buffer buffer (buffer-string))))
                           (should (string-match-p (concat mark " Bound") text))
                           (should (string-match-p (concat mark " Explicit") text)))))
              (check "☐")
              (etaf-dispatch-event runtime 'bound 'press)
              (should (equal '(t) observed))
              (should (eq t (etaf-value done)))
              (check "☑")
              (etaf-dispatch-event runtime 'explicit 'press)
              (should-not (etaf-value done))
              (check "☐")
              (setf (etaf-value done) t)
              (check "☑")
              (setf (etaf-value disabled) t)
              (should-error (etaf-dispatch-event runtime 'bound 'press)
                            :type 'etaf-event-error)
              (should (eq t (etaf-value done)))
              (should (equal '(t) observed))
              (etaf-unmount runtime)
              (let ((text (with-current-buffer buffer (buffer-string))))
                (setf (etaf-value done) nil)
                (should (equal text (with-current-buffer buffer (buffer-string))))))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer))) (etaf-unmount runtime))
      (kill-buffer buffer))))

(ert-deftest etaf-ui-binding-retargets-only-after-successful-publication ()
  "Rejected input cannot replace a control's committed ref or callback."
  (let* ((left (etaf-ref nil)) (right (etaf-ref nil))
         (props (etaf-ref (list :bind left)))
         (buffer (generate-new-buffer " *binding-publication*")))
    (unwind-protect
        (progn
          (etaf-mount buffer
                      (lambda ()
                        (etaf-node 'etaf-checkbox
                                   (append (list :ref 'control :label "Control")
                                           (etaf-value props)) nil)))
          (let ((runtime (etaf-runtime-for-buffer buffer)))
            (should-error (setf (etaf-value props) (list :bind right :checked nil))
                          :type 'etaf-view-error)
            ;; The old handler still writes LEFT. Publication retries the
            ;; invalid root input, leaving the last successful image intact.
            (should-error (etaf-dispatch-event runtime 'control 'press))
            (should (etaf-value left))
            (should-not (etaf-value right))
            (setf (etaf-value props) (list :bind right))
            (etaf-dispatch-event runtime 'control 'press)
            (should (etaf-value right))
            ;; Explicit nil remains a supported controlled value when unbound.
            (setf (etaf-value props) (list :checked nil :on-change #'ignore))
            (etaf-dispatch-event runtime 'control 'press)
            (should (string-match-p "☐ Control" (with-current-buffer buffer (buffer-string))))
            (setf (etaf-value props) (list :bind left))
            (etaf-dispatch-event runtime 'control 'press)
            (should-not (etaf-value left))
            (should (etaf-value right))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer))) (etaf-unmount runtime))
      (kill-buffer buffer))))

(ert-deftest etaf-ui-number-binding-validates-cancel-and-disabled-input ()
  "Accepted edits update the ref; invalid, canceled and disabled edits do not."
  (let ((value (etaf-ref 3)) (disabled (etaf-ref nil))
        (buffer (generate-new-buffer " *number-binding*")))
    (unwind-protect
        (progn
          (etaf-mount buffer
                      (etaf-view (etaf-number-input
                                  :bind value :label "Rows" :ref 'rows :min 1 :max 10
                                  :disabled (etaf-value disabled))))
          (let ((runtime (etaf-runtime-for-buffer buffer)))
            (cl-letf (((symbol-function 'read-number) (lambda (&rest _) 7)))
              (etaf-dispatch-event runtime 'rows 'press))
            (should (= 7 (etaf-value value)))
            (should (string-match-p "Rows 7" (with-current-buffer buffer (buffer-string))))
            (dolist (invalid '(0 11 3.5))
              (cl-letf (((symbol-function 'read-number) (lambda (&rest _) invalid)))
                (should-error (etaf-dispatch-event runtime 'rows 'press) :type 'user-error))
              (should (= 7 (etaf-value value))))
            (cl-letf (((symbol-function 'read-number) (lambda (&rest _) (signal 'quit nil))))
              (should (eq 'canceled
                          (condition-case nil
                              (etaf-dispatch-event runtime 'rows 'press)
                            (quit 'canceled)))))
            (should (= 7 (etaf-value value)))
            (setf (etaf-value value) 4)
            (should (string-match-p "Rows 4" (with-current-buffer buffer (buffer-string))))
            (setf (etaf-value disabled) t)
            (should-error (etaf-dispatch-event runtime 'rows 'press) :type 'etaf-event-error)
            (should (= 4 (etaf-value value)))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer))) (etaf-unmount runtime))
      (kill-buffer buffer))))

(ert-deftest etaf-ui-bindings-report-conflicting-or-read-only-inputs ()
  "Binding errors identify the component, property, received value and expectation."
  (let ((scope (etaf-effect-scope :detached t)) (ref (etaf-ref nil)) computed)
    (unwind-protect
        (progn
          (etaf-scope-run scope (lambda () (setq computed (etaf-computed (lambda () t)))))
          (dolist (control '((etaf-checkbox :checked) (etaf-number-input :value)))
            (dolist (invalid (list (list :bind 42)
                                  (list :bind computed)
                                  (list :bind ref (cadr control) nil)
                                  (list :bind ref :on-change nil)
                                  (list :bind ref :on-change #'ignore)))
              (let* ((err (should-error (etaf-render (etaf-node (car control) invalid nil))
                                       :type 'etaf-view-error))
                     (message (error-message-string err)))
                (should (string-match-p (symbol-name (car control)) message))
                (should (string-match-p "property :" message))
                (should (string-match-p "received .*expected" message))))))
      (etaf-scope-stop scope))))

(provide 'etaf-ui-binding-tests)
;;; etaf-ui-binding-tests.el ends here
