;;; etaf-ui-surface-tests.el --- Floating panel public behavior -*- lexical-binding: t; -*-

;;; Commentary:
;; Exercise catalog Components through their rendered controls and native keys.

;;; Code:
(require 'ert)
(require 'etaf-ui)
(require 'ebox)

(defun etaf-ui-surface-test--control (runtime label)
  "Find the visible control with LABEL in RUNTIME's public Host properties."
  (car (cl-find-if
        (lambda (entry)
          (and (equal label (plist-get (cdr entry) :aria-label))
               (etaf-host-ref-position runtime (car entry))))
        (etaf-runtime-host-props-entries runtime))))

(defun etaf-ui-surface-test--key (key)
  "Execute the native command bound to KEY in the current test buffer."
  (let ((command (key-binding (kbd key))))
    (should (commandp command))
    (call-interactively command)))

(ert-deftest etaf-ui-drawer-composes-both-sides-and-restores-focus ()
  "Both modal drawer edges retain controlled values and restore their opener."
  (dolist (side '(left right))
    (with-temp-buffer
      (let ((open (etaf-ref nil)) (checked (etaf-ref nil)))
        (unwind-protect
            (progn
              (etaf-mount
               (current-buffer)
               (etaf-view
                (column :width '(ch 80) :height '(lh 25)
                  (etaf-button :ref 'open :label "Inspect"
                               :on-press (lambda () (setf (etaf-value open) t)))
                  (etaf-drawer :open open :placement side :title "Inspector"
                               :on-close (lambda () (setf (etaf-value open) nil))
                    (etaf-checkbox :bind checked :label "Reviewed")
                    (slot :name 'footer
                      (etaf-button :label "Done"
                                   :on-press (lambda () (setf (etaf-value open) nil))))))))
              (let ((runtime (etaf-runtime-for-buffer (current-buffer))))
                (etaf-focus runtime 'open)
                (etaf-activate runtime)
                (should-not (etaf-host-ref-position runtime 'open))
                (should (string-match-p "Inspector" (buffer-string)))
                (etaf-activate runtime)
                (should (etaf-value checked))
                (etaf-ui-surface-test--key "<escape>")
                (should-not (etaf-value open))
                (should (eq 'open (etaf-focused-host-ref runtime)))
                (etaf-activate runtime)
                (should (etaf-value checked))
                (etaf-focus runtime (etaf-ui-surface-test--control runtime "Done"))
                (etaf-activate runtime)
                (should-not (etaf-value open))
                (should (eq 'open (etaf-focused-host-ref runtime)))))
          (when-let* ((runtime (etaf-runtime-for-buffer (current-buffer))))
            (etaf-unmount runtime)))))))

(ert-deftest etaf-ui-dropdown-opens-navigates-selects-and-restores-focus ()
  "A dropdown renders its items, skips disabled ones and invokes selection once."
  (with-temp-buffer
    (let (selected)
      (unwind-protect
          (progn
            (etaf-mount
             (current-buffer)
             (etaf-view
              (column :width '(ch 80) :height '(lh 25)
                (etaf-dropdown-menu
                 :label "Actions"
                 :items '((:key edit :label "Edit") (:key delete :label "Delete" :disabled t)
                          (:key copy :label "Copy"))
                 :on-select (lambda (key) (push key selected)))
                (etaf-button :label "Outside" :on-press #'ignore))))
            (let* ((runtime (etaf-runtime-for-buffer (current-buffer)))
                   (trigger (etaf-ui-surface-test--control runtime "Actions"))
                   (before-map (key-binding (kbd "<escape>"))))
              (should trigger)
              (etaf-focus runtime trigger)
              (etaf-activate runtime)
              (should (string-match-p "Edit" (buffer-string)))
              (should (string-match-p "Delete" (buffer-string)))
              (should (equal (etaf-focused-host-ref runtime)
                          (etaf-ui-surface-test--control runtime "Edit")))
              (etaf-ui-surface-test--key "<down>")
              (should (equal (etaf-focused-host-ref runtime)
                          (etaf-ui-surface-test--control runtime "Copy")))
              (etaf-ui-surface-test--key "TAB")
              (should (equal (etaf-focused-host-ref runtime)
                          (etaf-ui-surface-test--control runtime "Edit")))
              (etaf-ui-surface-test--key "RET")
              (should (equal selected '(edit)))
              (should-not (string-match-p "Delete" (buffer-string)))
              (should (equal trigger (etaf-focused-host-ref runtime)))
              (should (eq before-map (key-binding (kbd "<escape>"))))
              (etaf-activate runtime)
              (etaf-ui-surface-test--key "<escape>")
              (should (equal selected '(edit)))
              (should (equal trigger (etaf-focused-host-ref runtime)))))
        (when-let* ((runtime (etaf-runtime-for-buffer (current-buffer))))
          (etaf-unmount runtime))))))

(ert-deftest etaf-ui-dialog-composes-slots-and-blocks-covered-controls ()
  "The modal canvas covers background targets and returns focus after closing."
  (with-temp-buffer
    (let ((open (etaf-ref nil)) (value (etaf-ref nil)) (background 0))
      (unwind-protect
          (progn
            (etaf-mount
             (current-buffer)
             (etaf-view
              (column :width '(ch 80) :height '(lh 25)
                (etaf-button :ref 'entry :label "Open dialog"
                             :on-press (lambda () (setf (etaf-value open) t)))
                (etaf-button :ref 'background :label "Background"
                             :on-press (lambda () (cl-incf background)))
                (etaf-dialog :open open :title "Preferences"
                             :on-close (lambda () (setf (etaf-value open) nil))
                  (etaf-checkbox :bind value :label "Enabled")
                  (slot :name 'footer
                    (etaf-button :label "Save"
                                 :on-press (lambda () (setf (etaf-value open) nil))))))))
            (let ((runtime (etaf-runtime-for-buffer (current-buffer))))
              (etaf-focus runtime 'entry)
              (etaf-activate runtime)
              (should (string-match-p "Preferences" (buffer-string)))
              (should-not (etaf-host-ref-position runtime 'background))
              (should-error (etaf-focus runtime 'background) :type 'etaf-event-error)
              (etaf-activate runtime)
              (should (etaf-value value))
              (dotimes (_ 5)
                (etaf-ui-surface-test--key "TAB")
                (should-not (memq (etaf-focused-host-ref runtime) '(entry background))))
              (etaf-ui-surface-test--key "C-g")
              (should-not (etaf-value open))
              (should (eq 'entry (etaf-focused-host-ref runtime)))
              (should (etaf-host-ref-position runtime 'background))
              (should (= background 0))))
        (when-let* ((runtime (etaf-runtime-for-buffer (current-buffer))))
          (etaf-unmount runtime))))))

(ert-deftest etaf-ui-dismisses-surfaces-on-presses-outside-their-panel ()
  "A root press capture closes open surfaces the press missed, keeping the hit one."
  (with-temp-buffer
    (let ((open (etaf-ref nil)) (value (etaf-ref nil)) (background 0)
          (dismissed nil))
      (unwind-protect
          (progn
            (etaf-mount
             (current-buffer)
             (etaf-view
              (column :ref 'root :width '(ch 80) :height '(lh 25)
                      :on-press-capture
                      (lambda () (push (etaf-ui-dismiss-outside-press) dismissed))
                (etaf-button :ref 'entry :label "Open dialog"
                             :on-press (lambda () (setf (etaf-value open) t)))
                (etaf-button :ref 'background :label "Background"
                             :on-press (lambda () (cl-incf background)))
                (etaf-dialog :open open :title "Preferences" :backdrop nil
                             :on-close (lambda () (setf (etaf-value open) nil))
                  (etaf-checkbox :ref 'enabled :bind value :label "Enabled")))))
            (let ((runtime (etaf-runtime-for-buffer (current-buffer))))
              (etaf-dispatch-event runtime 'entry 'press)
              (should (etaf-value open))
              (should (string-match-p "Preferences" (buffer-string)))
              (etaf-dispatch-event runtime 'enabled 'press)
              (should (etaf-value value))
              (should (etaf-value open))
              (etaf-dispatch-event runtime 'background 'press)
              (should (= background 1))
              (should-not (etaf-value open))
              (should-not (string-match-p "Preferences" (buffer-string)))
              (etaf-dispatch-event runtime 'background 'press)
              (should (equal dismissed '(0 1 0 0)))
              (should-error (etaf-ui-dismiss-outside-press)
                            :type 'etaf-event-error)))
        (when-let* ((runtime (etaf-runtime-for-buffer (current-buffer))))
          (etaf-unmount runtime))))))

(ert-deftest etaf-ui-dialog-compact-height-keeps-one-row-header ()
  "A compact dialog uses the requested height and no extra header gap."
  (with-temp-buffer
    (let ((open (etaf-ref t)))
      (unwind-protect
          (progn
            (etaf-mount
             (current-buffer)
             (etaf-view
              (column :width '(ch 80) :height '(lh 30)
                (etaf-label :text "Background")
                (etaf-dialog :open open :title "Settings"
                             :width '(ch 42) :height '(lh 18) :compact t
                             :backdrop nil
                             :on-close (lambda () (setf (etaf-value open) nil))
                  (etaf-label :text "One-row content")))))
            (let* ((runtime (etaf-runtime-for-buffer (current-buffer)))
                   (panel
                    (cl-find-if
                     (lambda (entry)
                       (equal "etaf-floating-panel"
                              (plist-get (cdr entry) :class)))
                     (etaf-runtime-host-props-entries runtime)))
                   (props (cdr panel)))
              (should panel)
              (should (equal '(lh 18) (plist-get props :height)))
              (should (equal '(lh 0) (plist-get props :item-gap)))
              (should (equal '((lh 0) (ch 1)) (plist-get props :padding)))
              (should (string-match-p "Background" (buffer-string)))
              (setf (etaf-value open) nil)
              (should (string-match-p "Background" (buffer-string)))))
        (when-let* ((runtime (etaf-runtime-for-buffer (current-buffer))))
          (etaf-unmount runtime))))))

(ert-deftest etaf-ui-floating-surfaces-nest-and-release-buffer-shortcuts ()
  "A menu inside a dialog restores the dialog keys, then the buffer's keys."
  (with-temp-buffer
    (let ((open (etaf-ref t)) (before (key-binding (kbd "<escape>"))))
      (unwind-protect
          (progn
            (etaf-mount
             (current-buffer)
             (etaf-view
              (column :width '(ch 80) :height '(lh 30)
                (etaf-dialog :open open :title "Outer"
                             :on-close (lambda () (setf (etaf-value open) nil))
                  (etaf-dropdown-menu :label "Nested"
                                      :items '((:key one :label "Nested choice"))
                                      :on-select #'ignore)))))
            (let* ((runtime (etaf-runtime-for-buffer (current-buffer)))
                   (trigger (etaf-ui-surface-test--control runtime "Nested"))
                   (dialog-key (key-binding (kbd "<escape>"))))
              (etaf-focus runtime trigger)
              (etaf-activate runtime)
              (should (etaf-ui-surface-test--control runtime "Nested choice"))
              (should-not (eq dialog-key (key-binding (kbd "<escape>"))))
              (etaf-ui-surface-test--key "<escape>")
              (should (etaf-value open))
              (should (equal trigger (etaf-focused-host-ref runtime)))
              (should (eq dialog-key (key-binding (kbd "<escape>"))))
              (etaf-activate runtime)
              (etaf-unmount runtime)
              (should (eq before (key-binding (kbd "<escape>"))))))
        (when-let* ((runtime (etaf-runtime-for-buffer (current-buffer))))
          (etaf-unmount runtime))))))

(ert-deftest etaf-ui-popover-keeps-instance-state-and-independent-open-inputs ()
  "Two controlled popovers have independent state and clean up their slots."
  (with-temp-buffer
    (let ((open (etaf-ref nil)) (count (etaf-ref 0)))
      (unwind-protect
          (progn
            (etaf-mount
             (current-buffer)
             (etaf-view
              (column :width '(ch 90) :height '(lh 25)
                (etaf-button :ref 'first :id "first" :label "First"
                             :on-press (lambda () (setf (etaf-value open) t)))
                (etaf-popover :open open :anchor "first"
                              :on-close (lambda () (setf (etaf-value open) nil))
                  (etaf-button :label "Increment" :on-press (lambda () (cl-incf (etaf-value count)))))
                (etaf-popover :open nil :anchor "absent" :on-close #'ignore
                  (text "Not open")))))
            (let ((runtime (etaf-runtime-for-buffer (current-buffer))))
              (etaf-focus runtime 'first)
              (etaf-activate runtime)
              (etaf-activate runtime)
              (should (= 1 (etaf-value count)))
              (should-not (string-match-p "Not open" (buffer-string)))
              (setf (etaf-value open) nil)
              (should (eq 'first (etaf-focused-host-ref runtime)))
              (should-not (etaf-ui-surface-test--control runtime "Increment"))))
        (when-let* ((runtime (etaf-runtime-for-buffer (current-buffer))))
          (etaf-unmount runtime))))))

(ert-deftest etaf-ui-nested-dialog-covers-parent-and-restores-its-controls ()
  "A nested modal blocks the outer panel and restores it on close."
  (with-temp-buffer
    (let ((inner (etaf-ref nil)) (outer (etaf-ref t)))
      (unwind-protect
          (progn
            (etaf-mount
             (current-buffer)
             (etaf-view
              (column :width '(ch 80) :height '(lh 30)
                (etaf-dialog :open outer :title "Outer" :on-close #'ignore
                  (etaf-button :ref 'nested-entry :label "Open inner"
                               :on-press (lambda () (setf (etaf-value inner) t)))
                  (etaf-dialog :open inner :title "Inner" :width '(ch 32)
                               :on-close (lambda () (setf (etaf-value inner) nil))
                    (text "Inner content"))))))
            (let ((runtime (etaf-runtime-for-buffer (current-buffer))))
              (etaf-focus runtime 'nested-entry)
              (etaf-activate runtime)
              (should (string-match-p "Inner content" (buffer-string)))
              (should-not (etaf-host-ref-position runtime 'nested-entry))
              (etaf-ui-surface-test--key "<escape>")
              (should-not (etaf-value inner))
              (should (eq 'nested-entry (etaf-focused-host-ref runtime)))))
        (when-let* ((runtime (etaf-runtime-for-buffer (current-buffer))))
          (etaf-unmount runtime))))))

(ert-deftest etaf-ui-unpainted-popover-does-not-capture-keys ()
  "An unavailable anchor leaves the mounted buffer's ordinary keys usable."
  (with-temp-buffer
    (let ((before (key-binding (kbd "<escape>"))))
      (unwind-protect
          (progn
            (etaf-mount
             (current-buffer)
             (etaf-view
              (column :width '(ch 80) :height '(lh 20)
                (etaf-popover :open t :anchor "absent" :on-close #'ignore
                  (etaf-button :label "Not visible" :on-press #'ignore)))))
            (should-not (string-match-p "Not visible" (buffer-string)))
            (should (eq before (key-binding (kbd "<escape>")))))
        (when-let* ((runtime (etaf-runtime-for-buffer (current-buffer))))
          (etaf-unmount runtime))))))

(ert-deftest etaf-ui-surfaces-example-composes-menu-dialog-and-input ()
  "The runnable example hands menu focus to a dialog and back to its trigger."
  (let ((buffer (etaf-ui-surfaces-open)))
    (unwind-protect
        (with-current-buffer buffer
          (let* ((runtime (etaf-runtime-for-buffer buffer))
                 (trigger (etaf-ui-surface-test--control runtime "操作")))
            (etaf-focus runtime trigger)
            (etaf-activate runtime)
            (etaf-activate runtime)
            (should-not (etaf-ui-surface-test--control runtime "编辑偏好"))
            (should (etaf-ui-surface-test--control runtime "名称"))
            (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "新工作空间")))
              (etaf-activate runtime))
            (should (string-match-p "新工作空间" (buffer-string)))
            (etaf-ui-surface-test--key "<escape>")
            (should (equal trigger (etaf-focused-host-ref runtime)))
            (should (string-match-p "新工作空间" (buffer-string)))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer))) (etaf-unmount runtime))
      (kill-buffer buffer))))

(provide 'etaf-ui-surface-tests)
;;; etaf-ui-surface-tests.el ends here
