;;; etaf-ui-modern-tests.el --- Public modern catalog behavior -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'etaf-ui)

(defun etaf-ui-modern-test-activate (runtime label)
  "Activate the visible LABEL through RUNTIME's public target interface."
  (let ((target
         (car (cl-find-if
               (lambda (entry)
                 (and (equal label (plist-get (cdr entry) :aria-label))
                      (etaf-host-ref-position runtime (car entry))))
               (etaf-runtime-host-props-entries runtime)))))
    (should target)
    (etaf-focus runtime target)
    (etaf-activate runtime)))

(defun etaf-ui-modern-test-find-text (text)
  "Scroll the mounted example until TEXT is painted."
  (let ((attempts 0))
    (while (and (< attempts 12)
                (not (string-match-p (regexp-quote text) (buffer-substring-no-properties
                                                         (point-min) (point-max)))))
      (cl-incf attempts)
      (goto-char (point-min))
      (call-interactively (key-binding (kbd "C-v"))))
    (should (string-match-p (regexp-quote text) (buffer-substring-no-properties
                                              (point-min) (point-max))))))

(ert-deftest etaf-ui-gallery-mounts-composed-catalog-and-opens-tooltip ()
  "The Gallery mounts all catalog categories and toggles a controlled tooltip."
  (let ((buffer (etaf-ui-gallery-open)))
    (unwind-protect
        (with-current-buffer buffer
          (let ((runtime (etaf-runtime-for-buffer (current-buffer))))
            (should (string-match-p "A workspace for things worth making" (buffer-string)))
            (should (string-match-p "Creative brief" (buffer-string)))
            (should (etaf-host-ref-position runtime 'gallery-help))
            (etaf-focus runtime 'gallery-help)
            (etaf-activate runtime)
            (should (string-match-p "Tab to explore" (buffer-string)))
            (should (etaf-host-ref-position runtime 'gallery-profile))
            (let ((find-control
                   (lambda (label)
                     (cl-find-if
                      (lambda (entry)
                        (equal label (plist-get (cdr entry) :aria-label)))
                      (etaf-runtime-host-props-entries runtime)))))
              (etaf-focus runtime (car (funcall find-control "More")))
              (etaf-activate runtime)
              (etaf-focus runtime (car (funcall find-control "Open inspector")))
              (etaf-activate runtime)
              (should (string-match-p "Workspace inspector" (buffer-string)))
              (should (string-match-p "Live composition" (buffer-string)))
              (etaf-focus runtime (car (funcall find-control "Close inspector")))
              (etaf-activate runtime))
            (let ((library (cl-find-if
                            (lambda (entry)
                              (equal "Component library"
                                     (plist-get (cdr entry) :aria-label)))
                            (etaf-runtime-host-props-entries runtime))))
              (etaf-focus runtime (car library))
              (etaf-activate runtime)
              (etaf-ui-modern-test-find-text "Selection controls")
              (etaf-ui-modern-test-find-text "Preview zoom")
              (etaf-ui-modern-test-find-text "Navigation & context")
              (etaf-ui-modern-test-activate runtime "Build")
              (etaf-ui-modern-test-find-text "Composition patterns")
              (etaf-ui-modern-test-find-text "Collection browser"))))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (when-let* ((runtime (etaf-runtime-for-buffer (current-buffer))))
            (etaf-unmount runtime)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-feedback-and-navigation-render-public-contracts ()
  "Feedback and navigation Components render and dispatch through public refs."
  (with-temp-buffer
    (let ((active (etaf-ref 'one))
          (open (etaf-ref nil))
          (selected nil))
      (unwind-protect
          (progn
            (etaf-mount
             (current-buffer)
             (etaf-view
              (column :width '(ch 80) :height '(lh 25)
                (etaf-alert :title "Notice" :message "Ready" :variant 'info)
                (etaf-tabs :items '((:key one :label "One" :count 17)
                                    (:key two :label "Two"))
                           :active active
                           :on-change (lambda (key) (setf selected key (etaf-value active) key)))
                (etaf-accordion
                 :items '((:key details :label "Details" :content "More"))
                 :open open :multiple nil
                 :on-toggle (lambda (keys) (setf (etaf-value open) keys)))
                (etaf-badge :text "Ready" :variant 'success)
                (etaf-breadcrumb :items '("Home" "Collection" "Item")
                                 :on-select (lambda (index) (setq selected index)))
                (etaf-progress :value 3 :max 4 :label "Progress"))))
            (let ((runtime (etaf-runtime-for-buffer (current-buffer))))
              (should (string-match-p "Notice" (buffer-string)))
              (should (etaf-runtime-mounted-p runtime))
              (should (string-match-p "Progress" (buffer-string)))
              (should (string-match-p "17" (buffer-string)))
              (etaf-ui-modern-test-activate runtime "Two")
              (should (eq selected 'two))
              (should (eq (etaf-value active) 'two))
              (etaf-ui-modern-test-activate runtime "> Details")
              (should (equal (etaf-value open) '(details)))
              (should (string-match-p "More" (buffer-string)))
              (etaf-ui-modern-test-activate runtime "Home")
              (should (equal selected 0))
              (etaf-ui-modern-test-activate runtime "Collection")
              (should (equal selected 1))))
        (when-let* ((runtime (etaf-runtime-for-buffer (current-buffer))))
          (etaf-unmount runtime))))))

(ert-deftest etaf-ui-tabs-address-items-by-ref ()
  "A tab item's optional :ref reaches the rendered control."
  (with-temp-buffer
    (let ((active (etaf-ref 'one))
          (selected nil))
      (unwind-protect
          (progn
            (etaf-mount
             (current-buffer)
             (etaf-view
              (column :width '(ch 40)
                (etaf-tabs :items '((:key one :label "One" :ref one-tab)
                                    (:key two :label "Two" :ref two-tab))
                           :active active
                           :on-change (lambda (key)
                                        (setf selected key
                                              (etaf-value active) key))))))
            (let ((runtime (etaf-runtime-for-buffer (current-buffer))))
              (should (etaf-host-ref-position runtime 'two-tab))
              (etaf-dispatch-event runtime 'two-tab 'press)
              (should (eq selected 'two))
              (should (eq (etaf-value active) 'two))))
        (when-let* ((runtime (etaf-runtime-for-buffer (current-buffer))))
          (etaf-unmount runtime))))))

(ert-deftest etaf-ui-tabs-keep-every-label-in-place-when-switching ()
  "Switching the active tab never moves any tab label."
  (with-temp-buffer
    (let ((active (etaf-ref 'one)))
      (unwind-protect
          (progn
            (etaf-mount
             (current-buffer)
             (etaf-view
              (column :width '(ch 60)
                (etaf-tabs :items '((:key one :label "One" :count 3)
                                    (:key two :label "Two")
                                    (:key three :label "Three"))
                           :active active
                           :on-change (lambda (key) (setf (etaf-value active) key))))))
            (cl-flet ((columns ()
                        (mapcar (lambda (label)
                                  (save-excursion
                                    (goto-char (point-min))
                                    (search-forward label)
                                    (- (current-column) (length label))))
                                '("One" "Two" "Three"))))
              (let ((before (columns)))
                (setf (etaf-value active) 'three)
                (should (equal (columns) before))
                (setf (etaf-value active) 'two)
                (should (equal (columns) before)))))
        (when-let* ((runtime (etaf-runtime-for-buffer (current-buffer))))
          (etaf-unmount runtime))))))

(ert-deftest etaf-ui-selection-components-render-public-contracts ()
  "Selection Components render controlled values through the public DSL."
  (with-temp-buffer
    (let ((choice (etaf-ref 'cozy))
          (kind (etaf-ref 'brand))
          (enabled (etaf-ref t))
          (zoom (etaf-ref 80))
          (name (etaf-ref "Atelier"))
          (launch-date (etaf-ref "2026-09-16")))
      (unwind-protect
          (progn
            (etaf-mount
             (current-buffer)
             (etaf-view
              (column :width '(ch 80) :height '(lh 25)
                (etaf-radio :bind choice :label "Density"
                            :options '((compact . "Compact") (cozy . "Cozy")))
                (etaf-segmented :bind kind
                                :options '((brand . "Brand") (product . "Product")))
                (etaf-switch :bind enabled :label "Live updates")
                (etaf-slider :bind zoom :label "Zoom" :min 40 :max 120 :step 10)
                (etaf-text-input :bind name :label "Name")
                (etaf-date-picker :bind launch-date :label "Launch date"))))
            (let ((runtime (etaf-runtime-for-buffer (current-buffer))))
              (should (etaf-runtime-mounted-p runtime))
              (should (string-match-p "Density" (buffer-string)))
              (should (string-match-p "Live updates" (buffer-string)))
              (should (string-match-p "80" (buffer-string)))
              (should (string-match-p "Launch date" (buffer-string)))))
        (when-let* ((runtime (etaf-runtime-for-buffer (current-buffer))))
          (etaf-unmount runtime))))))

(ert-deftest etaf-ui-composition-components-render-public-contracts ()
  "Tag, Kbd, Steps and List compose with caller-owned selection callbacks."
  (with-temp-buffer
    (let ((current (etaf-ref 'one)) (selected nil) (closed nil))
      (unwind-protect
          (progn
            (etaf-mount
             (current-buffer)
             (etaf-view
              (column :width '(ch 80) :height '(lh 25)
                (etaf-tag :text "Ready" :variant 'success :closable t
                          :on-close (lambda () (setq closed t)))
                (etaf-kbd :keys '("Ctrl" "K"))
                (row :item-gap '(ch 1)
                  (etaf-avatar :name "Mina")
                  (etaf-avatar :name "")
                  (etaf-avatar :name "Ada" :initials "AL" :size '(ch 4)
                               :lines 2 :background "#2563eb")
                  (etaf-avatar :name "Zed" :src "/nonexistent/photo.png"))
                (etaf-steps
                 :current current
                 :items '((:key one :label "Plan") (:key two :label "Build"))
                 :on-change (lambda (key) (setf (etaf-value current) key)))
                (etaf-list
                 :items '((:key one :title "Overview" :description "Start here")
                          (:key two :title "Details" :description "Keep composing"))
                 :on-select (lambda (key) (setf selected key))))))
            (let ((runtime (etaf-runtime-for-buffer (current-buffer))))
              (should (etaf-runtime-mounted-p runtime))
              (should (string-match-p "Ready" (buffer-string)))
              (should (string-match-p "Ctrl" (buffer-string)))
              (should (string-match-p "MI" (buffer-string)))
              (should (string-match-p (regexp-quote "?") (buffer-string)))
              ;; Text frames fall back to initials even with a photo source.
              (should (string-match-p "ZE" (buffer-string)))
              (should-error (etaf-render (etaf-view (etaf-avatar :name "x" :shape 'star))))
              (let ((start (string-match "AL" (buffer-string))))
                (should start)
                (should (member '(:background "#2563eb")
                                (get-text-property (1+ start) 'face))))
              (should (string-match-p "Build" (buffer-string)))
              (should (string-match-p "1  Plan" (buffer-string)))
              (should (string-match-p "2  Build" (buffer-string)))
              (should (string-match-p "Keep composing" (buffer-string)))
              (etaf-ui-modern-test-activate runtime "Build")
              (should (eq (etaf-value current) 'two))
              (etaf-ui-modern-test-activate runtime "Details")
              (should (eq selected 'two))
              (etaf-ui-modern-test-activate runtime "Remove Ready")
              (should closed)))
        (when-let* ((runtime (etaf-runtime-for-buffer (current-buffer))))
          (etaf-unmount runtime))))))

(ert-deftest etaf-ui-composition-components-reject-invalid-props ()
  "Invalid shortcut keys, duplicate list identities and absent steps are rejected."
  (dolist (view '((etaf-kbd :keys ("Ctrl" 2))
                  (etaf-list :items ((:key same :title "First")
                                     (:key same :title "Second")))
                  (etaf-tabs :items ((:key one :label "One" :count (1 2)))
                             :active one :on-change ignore)
                  (etaf-steps :items ((:key one :label "Plan")) :current missing)))
    (with-temp-buffer
      (should-error (etaf-mount (current-buffer) (etaf-node (car view) (cdr view) nil))
                    :type 'etaf-view-error))))

;;; etaf-ui-modern-tests.el ends here
