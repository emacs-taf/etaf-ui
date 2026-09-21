;;; etaf-ui-desktop-tests.el --- Desktop navigation Component contracts -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'etaf-ui)

(defun etaf-ui-desktop-test--cleanup (buffer)
  "Unmount and remove BUFFER after a desktop Component test."
  (when-let* ((runtime (etaf-runtime-for-buffer buffer)))
    (etaf-unmount runtime))
  (when-let* ((live (get-buffer buffer)))
    (kill-buffer live)))

(defun etaf-ui-desktop-test--ref (runtime label)
  "Return the host ref in RUNTIME whose ARIA label is LABEL."
  (car (cl-find-if
        (lambda (entry)
          (equal label (plist-get (cdr entry) :aria-label)))
        (etaf-runtime-host-props-entries runtime))))

(ert-deftest etaf-ui-taskbar-and-workspace-bar-publish-controlled-actions ()
  "Taskbar and workspace controls expose caller-owned selection callbacks."
  (let ((buffer (generate-new-buffer "*etaf-ui-desktop-bars*")) selected workspace)
    (unwind-protect
        (progn
          (etaf-mount
           buffer
           (etaf-view
           (column :width '(ch 80) :height '(lh 25)
             (etaf-taskbar
              :items '((:key notes :label "Notes" :state active)
                       (:key files :label "Files" :state minimized))
              :active 'notes
              :on-select (lambda (key) (setq selected key)))
             (etaf-workspace-bar
              :workspaces '(main dev)
              :active 'main
              :on-select (lambda (key) (setq workspace key))))))
          (let ((runtime (etaf-runtime-for-buffer buffer)))
            (etaf-dispatch-event runtime
                                 (etaf-ui-desktop-test--ref runtime "Files") 'press)
            (etaf-dispatch-event runtime
                                 (etaf-ui-desktop-test--ref runtime "dev") 'press)
            (should (eq selected 'files))
            (should (eq workspace 'dev))
            (should (string-match-p "Notes" (with-current-buffer buffer (buffer-string))))))
      (etaf-ui-desktop-test--cleanup buffer))))

(ert-deftest etaf-ui-launcher-and-switcher-remain-controlled ()
  "Picker Components render only when OPEN is true and delegate selection."
  (let ((buffer (generate-new-buffer "*etaf-ui-desktop-pickers*"))
        (launcher-open (etaf-ref t)) (switcher-open (etaf-ref nil))
        (selected (etaf-ref 'editor)) picked)
    (unwind-protect
        (progn
          (etaf-mount
           buffer
           (etaf-view
            (column :width '(ch 80) :height '(lh 25)
             (etaf-launcher :open launcher-open
                            :items '((:key editor :label "Editor" :description "Code")
                                     (:key terminal :label "Terminal"))
                            :on-select (lambda (key) (setq picked key))
                            :on-close (lambda () (setf (etaf-value launcher-open) nil)))
             (etaf-switcher :open switcher-open :selected selected
                            :items '((:key editor :label "Editor")
                                     (:key terminal :label "Terminal"))
                            :on-select (lambda (key) (setq picked key))
                            :on-close (lambda () (setf (etaf-value switcher-open) nil))))))
          (should (string-match-p "Applications" (with-current-buffer buffer (buffer-string))))
          (setf (etaf-value launcher-open) nil
                (etaf-value switcher-open) t)
          (etaf-runtime-flush (etaf-runtime-for-buffer buffer))
          (should (string-match-p "Switch application" (with-current-buffer buffer (buffer-string))))
          (should (string-match-p "Editor" (with-current-buffer buffer (buffer-string))))
          (should (eq 'editor (etaf-value selected)))
          (setf (etaf-value switcher-open) nil)
          (etaf-runtime-flush (etaf-runtime-for-buffer buffer))
          (should-not (string-match-p "Switch application" (with-current-buffer buffer (buffer-string)))))
      (etaf-ui-desktop-test--cleanup buffer))))

(ert-deftest etaf-ui-splitter-projects-named-panes-and-divider ()
  "Splitter keeps ratio controlled and exposes an accessible divider gesture."
  (let ((buffer (generate-new-buffer "*etaf-ui-desktop-splitter*")) (ratio (etaf-ref 0.4)) gesture)
    (unwind-protect
        (progn
          (etaf-mount
           buffer
           (etaf-view
            (etaf-splitter :orientation 'horizontal :ratio ratio
                           :on-change (lambda (event) (setq gesture event))
                           (slot :name 'first (etaf-label :text "Files"))
                           (slot :name 'second (etaf-label :text "Preview")))))
          (let* ((runtime (etaf-runtime-for-buffer buffer))
                 (divider (etaf-ui-desktop-test--ref runtime "Resize columns")))
            (should divider)
            (etaf-dispatch-event runtime divider 'drag
                                 '(:phase move :delta (8 . 0)) t)
            (should (equal (plist-get gesture :phase) 'move))
            (should (string-match-p "Files" (with-current-buffer buffer (buffer-string))))
            (should (string-match-p "Preview" (with-current-buffer buffer (buffer-string))))))
      (etaf-ui-desktop-test--cleanup buffer))))

(ert-deftest etaf-ui-window-chrome-uses-macos-traffic-lights ()
  "Window chrome puts red/yellow/green controls on the left of the title."
  (let ((buffer (generate-new-buffer "*etaf-ui-macos-chrome*")))
    (unwind-protect
        (progn
          (etaf-mount
           buffer
           (etaf-view
            (etaf-window-chrome
             :title "Demo"
             :on-close (lambda ())
             :on-minimize (lambda ())
             :on-maximize (lambda ()))))
          (let* ((runtime (etaf-runtime-for-buffer buffer))
                 (controls
                  (cl-remove-if-not
                   (lambda (entry)
                     (member (plist-get (cdr entry) :aria-label)
                             '("Close" "Minimize" "Maximize" "Restore")))
                   (etaf-runtime-host-props-entries runtime))))
            (let ((labels (mapcar (lambda (entry)
                                    (plist-get (cdr entry) :aria-label)) controls))
                  (colors (mapcar (lambda (entry)
                                    (plist-get (cdr entry) :color)) controls))
                  (hover-labels (mapcar (lambda (entry)
                                          (plist-get (cdr entry) :hover-content))
                                        controls)))
            (should (equal '("Close" "Minimize" "Maximize") labels))
            (should (equal '("#FF5F57" "#FEBC2E" "#28C840") colors))
            (should (equal '("⊗" "⊖" "⊕") hover-labels))
            (dolist (entry controls)
              (let ((props (cdr entry)))
                (should (eq 'arrow (plist-get props :pointer)))
                (should (equal "#F3F4F6" (plist-get props :background-color)))
                (should (equal '((px 0) solid "#F3F4F6")
                               (plist-get props :border)))))
            (with-current-buffer buffer
                (should (string-match-p "D" (buffer-string)))))))
      (etaf-ui-desktop-test--cleanup buffer))))

;;; etaf-ui-desktop-tests.el ends here
