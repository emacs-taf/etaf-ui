;;; etaf-ui-advanced-tests.el --- Composed advanced UI behavior -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'etaf-ui)

(defun etaf-ui-advanced-test-activate (runtime label)
  "Activate visible LABEL using RUNTIME's public target interface."
  (let ((target (car (cl-find-if
                     (lambda (entry)
                       (and (equal label (plist-get (cdr entry) :aria-label))
                            (etaf-host-ref-position runtime (car entry))))
                     (etaf-runtime-host-props-entries runtime)))))
    (should target)
    (etaf-focus runtime target)
    (etaf-activate runtime)))

(ert-deftest etaf-ui-advanced-components-compose-public-contracts ()
  "DatePicker, Tree, Calendar and CommandPalette keep caller-owned values."
  (let ((buffer (generate-new-buffer " *advanced-components*"))
        (date (etaf-ref "2026-09-16"))
        (expanded (etaf-ref '(root)))
        (palette (etaf-ref nil))
        selected selected-date)
    (unwind-protect
        (with-current-buffer buffer
          (etaf-mount
           buffer
           (etaf-view
            (column :width '(ch 120) :height '(lh 50)
              (etaf-date-picker :bind date :label "Release date")
              (etaf-tree
               :items '((:key root :label "Release"
                          :children ((:key design :label "Design"))))
               :expanded expanded
               :on-toggle (lambda (keys) (setf (etaf-value expanded) keys))
               :on-select (lambda (key) (setq selected key)))
              (etaf-calendar :month '(2026 9) :value 16
                             :on-change (lambda (next) (setq selected-date next)))
              (etaf-button :label "Open palette"
                           :on-press (lambda () (setf (etaf-value palette) t)))
              (etaf-command-palette
               :open palette :title "Commands"
               :items '((:key open :title "Open" :description "Open item"))
               :on-select (lambda (key) (setq selected key))
               :on-close (lambda () (setf (etaf-value palette) nil))))))
          (let ((runtime (etaf-runtime-for-buffer buffer)))
            (should (string-match-p "Release date" (buffer-string)))
            (etaf-ui-advanced-test-activate runtime "September 16")
            (should (equal selected-date '(2026 9 16)))
            (etaf-ui-advanced-test-activate runtime "Release")
            (should-not (string-match-p "Design" (buffer-string)))
            (etaf-ui-advanced-test-activate runtime "Release")
            (etaf-ui-advanced-test-activate runtime "Design")
            (should (eq selected 'design))
            (etaf-ui-advanced-test-activate runtime "Open palette")
            (should (string-match-p "Commands" (buffer-string)))
            (should (string-match-p "Open item" (buffer-string)))
            (etaf-ui-advanced-test-activate runtime "Open")
            (should (eq selected 'open))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer)))
        (etaf-unmount runtime))
      (kill-buffer buffer))))

;;; etaf-ui-advanced-tests.el ends here
