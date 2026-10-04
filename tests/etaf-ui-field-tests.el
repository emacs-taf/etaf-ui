;;; etaf-ui-field-tests.el --- In-place text field acceptance -*- lexical-binding: t; -*-

;;; Commentary:
;; The catalog's text input edits the application buffer natively; these
;; scenarios drive activation, typing, submission, cancellation, deferral and
;; cleanup through public ETAF APIs.

;;; Code:
(require 'ert)
(require 'cl-lib)
(require 'etaf-ui)

(defun etaf-ui-field-test--press (key)
  "Invoke the current buffer's binding for KEY through the command loop."
  (call-interactively (key-binding (kbd key))))

(defun etaf-ui-field-test--mount (&rest field-props)
  "Mount a small form with one text input and return (BUFFER . VALUE-REF)."
  (let* ((buffer (generate-new-buffer " *field test*"))
         (value (etaf-ref "初始"))
         (rows (or (plist-get field-props :rows) 1))
         (props (append (list :ref 'field :bind value :label "标题"
                              :placeholder "写点什么" :rows rows)
                        (cl-loop for (key val) on field-props by #'cddr
                                 unless (eq key :rows)
                                 append (list key val)))))
    (etaf-mount
     buffer
     (etaf-node 'column (list :width '(ch 40))
                (list (etaf-node 'etaf-text-input props nil)))
     '(:viewport-width 600 :viewport-height 20))
    (cons buffer value)))

(ert-deftest etaf-ui-text-input-edits-the-application-buffer-in-place ()
  "Activation opens a session; typing updates the controlled value; end republishes."
  (let* ((mounted (etaf-ui-field-test--mount))
         (buffer (car mounted)) (value (cdr mounted)) observed)
    (unwind-protect
        (let ((runtime (etaf-runtime-for-buffer buffer)))
          (should (string-match-p "初始" (with-current-buffer buffer (buffer-string))))
          (should-not (etaf-text-input-active-p runtime))
          (etaf-dispatch-event runtime 'field 'press)
          (should (etaf-text-input-active-p runtime))
          (with-current-buffer buffer (insert " 文本"))
          (should (equal (etaf-value value) "初始 文本"))
          (should (equal (etaf-text-input-end) "初始 文本"))
          (should-not (etaf-text-input-active-p runtime))
          (should (string-match-p "初始 文本" (with-current-buffer buffer (buffer-string))))
          (should (equal (etaf-value value) "初始 文本")))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer))) (etaf-unmount runtime))
      (kill-buffer buffer))))

(ert-deftest etaf-ui-text-input-cancel-restores-the-activation-value ()
  "Cancelling restores the value captured when editing began."
  (let* ((observed nil)
         (mounted (etaf-ui-field-test--mount
                   :on-cancel (lambda (_text) (setq observed t))))
         (buffer (car mounted)) (value (cdr mounted)))
    (unwind-protect
        (let ((runtime (etaf-runtime-for-buffer buffer)))
          (etaf-dispatch-event runtime 'field 'press)
          (with-current-buffer buffer (insert "不要"))
          (should (equal (etaf-value value) "初始不要"))
          (etaf-text-input-end t)
          (should observed)
          (should (equal (etaf-value value) "初始"))
          (should (string-match-p "初始" (with-current-buffer buffer (buffer-string))))
          (should-not (string-match-p "不要" (with-current-buffer buffer (buffer-string)))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer))) (etaf-unmount runtime))
      (kill-buffer buffer))))

(ert-deftest etaf-ui-text-input-submits-on-return-for-one-row ()
  "A single-line field submits its text on Return."
  (let* ((submitted nil)
         (mounted (etaf-ui-field-test--mount
                   :on-submit (lambda (text) (setq submitted text))))
         (buffer (car mounted)))
    (unwind-protect
        (let ((runtime (etaf-runtime-for-buffer buffer)))
          (etaf-dispatch-event runtime 'field 'press)
          (with-current-buffer buffer
            (insert "第一行")
            (etaf-ui-field-test--press "RET"))
          (should (equal submitted "初始第一行"))
          (should-not (etaf-text-input-active-p runtime)))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer))) (etaf-unmount runtime))
      (kill-buffer buffer))))

(ert-deftest etaf-ui-text-input-multiline-inserts-newlines-until-submit ()
  "A multi-line field inserts newlines on Return and submits explicitly."
  (let* ((submitted nil)
         (mounted (etaf-ui-field-test--mount
                   :rows 3 :on-submit (lambda (text) (setq submitted text))))
         (buffer (car mounted)))
    (unwind-protect
        (let ((runtime (etaf-runtime-for-buffer buffer)))
          (etaf-dispatch-event runtime 'field 'press)
          (with-current-buffer buffer
            (insert "第一行")
            (etaf-ui-field-test--press "RET"))
          (should-not submitted)
          (should (etaf-text-input-active-p runtime))
          (with-current-buffer buffer (insert "第二行"))
          (etaf-text-input-end)
          (should (equal submitted "初始第一行\n第二行")))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer))) (etaf-unmount runtime))
      (kill-buffer buffer))))

(ert-deftest etaf-ui-text-input-placeholder-is-never-the-value ()
  "An empty field shows its placeholder and starts editing from empty text."
  (let* ((buffer (generate-new-buffer " *field placeholder*"))
         (value (etaf-ref nil)))
    (unwind-protect
        (progn
          (etaf-mount buffer
                      (etaf-node 'etaf-text-input
                                 (list :ref 'empty :bind value
                                       :placeholder "写点什么")
                                 nil)
                      '(:viewport-width 600 :viewport-height 20))
          (let ((runtime (etaf-runtime-for-buffer buffer)))
            (should (string-match-p "写点什么" (with-current-buffer buffer (buffer-string))))
            (etaf-dispatch-event runtime 'empty 'press)
            (should-not (string-match-p "写点什么" (with-current-buffer buffer (buffer-string))))
            (with-current-buffer buffer (insert "真实内容"))
            (should (equal (etaf-value value) "真实内容"))
            (etaf-text-input-end t)
            (should (equal (etaf-value value) ""))
            (should (string-match-p "写点什么" (with-current-buffer buffer (buffer-string))))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer))) (etaf-unmount runtime))
      (kill-buffer buffer))))

(ert-deftest etaf-ui-text-input-defers-publication-until-the-session-ends ()
  "Changes elsewhere stay pending while the field owns the buffer text."
  (let* ((buffer (generate-new-buffer " *field deferral*"))
         (value (etaf-ref "draft")) (notice (etaf-ref "一")))
    (unwind-protect
        (progn
          (etaf-mount buffer
                      (etaf-view
                       (column
                        (text :ref 'notice (expr (etaf-value notice)))
                        (expr (etaf-node 'etaf-text-input
                                         (list :ref 'field :bind value :label "标题")
                                         nil))))
                      '(:viewport-width 600 :viewport-height 20))
          (let ((runtime (etaf-runtime-for-buffer buffer)))
            (etaf-dispatch-event runtime 'field 'press)
            (with-current-buffer buffer (insert "!"))
            (setf (etaf-value notice) "二")
            (should (string-match-p "一" (with-current-buffer buffer (buffer-string))))
            (etaf-text-input-end)
            (should (string-match-p "二" (with-current-buffer buffer (buffer-string))))
            (should (string-match-p "draft!" (with-current-buffer buffer (buffer-string))))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer))) (etaf-unmount runtime))
      (kill-buffer buffer))))

(ert-deftest etaf-ui-text-input-disabled-and-read-only-are-not-editable ()
  "Disabled fields refuse activation; read-only fields allow no session."
  (dolist (case '(:disabled :read-only))
    (let* ((mounted (etaf-ui-field-test--mount case t))
           (buffer (car mounted)))
      (unwind-protect
          (let ((runtime (etaf-runtime-for-buffer buffer)))
            (if (eq case :disabled)
                (should-error (etaf-dispatch-event runtime 'field 'press)
                              :type 'etaf-event-error)
              (etaf-dispatch-event runtime 'field 'press))
            (should-not (etaf-text-input-active-p runtime)))
        (when-let* ((runtime (etaf-runtime-for-buffer buffer))) (etaf-unmount runtime))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-text-input-validates-props-and-unmounts-cleanly ()
  "Invalid props are reported in context; unmount closes any session."
  (dolist (props '((:rows 0) (:rows "3") (:label 7) (:placeholder 7)
                   (:completion-functions '(not-a-function))
                   (:keymap "map")))
    (with-temp-buffer
      (should-error (etaf-mount (current-buffer)
                                (etaf-node 'etaf-text-input props nil))
                    :type 'etaf-component-call-error)))
  (let* ((mounted (etaf-ui-field-test--mount))
         (buffer (car mounted)) (value (cdr mounted)))
    (let ((runtime (etaf-runtime-for-buffer buffer)))
      (etaf-dispatch-event runtime 'field 'press)
      (with-current-buffer buffer (insert "未提交"))
      (etaf-unmount runtime)
      (should (equal (etaf-value value) "初始未提交")))
    (kill-buffer buffer)))

(provide 'etaf-ui-field-tests)
;;; etaf-ui-field-tests.el ends here
