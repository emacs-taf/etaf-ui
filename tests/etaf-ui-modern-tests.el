;;; etaf-ui-modern-tests.el --- Public modern catalog behavior -*- lexical-binding: t; -*-

;;; Code:
(require 'ert)
(require 'etaf-ui)

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
            (let ((library (cl-find-if
                            (lambda (entry)
                              (equal "Component library"
                                     (plist-get (cdr entry) :aria-label)))
                            (etaf-runtime-host-props-entries runtime))))
              (etaf-focus runtime (car library))
              (etaf-activate runtime)
              (should (string-match-p "Selection controls" (buffer-string)))
              (should (string-match-p "Composition patterns" (buffer-string)))
              (should (string-match-p "Preview zoom" (buffer-string))))))
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
                (etaf-tabs :items '((:key one :label "One") (:key two :label "Two"))
                           :active active
                           :on-change (lambda (key) (setf selected key active key)))
                (etaf-accordion
                 :items '((:key details :label "Details" :content "More"))
                 :open open :multiple nil
                 :on-toggle (lambda (keys) (setf (etaf-value open) keys)))
                (etaf-badge :text "Ready" :variant 'success)
                (etaf-progress :value 3 :max 4 :label "Progress"))))
            (let ((runtime (etaf-runtime-for-buffer (current-buffer))))
              (should (string-match-p "Notice" (buffer-string)))
              (should (etaf-runtime-mounted-p runtime))
              (should (string-match-p "Progress" (buffer-string)))))
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
                (etaf-input :type 'text :bind name :label "Name")
                (etaf-input :type 'date :bind launch-date :label "Launch date"))))
            (let ((runtime (etaf-runtime-for-buffer (current-buffer))))
              (should (etaf-runtime-mounted-p runtime))
              (should (string-match-p "Density" (buffer-string)))
              (should (string-match-p "Live updates" (buffer-string)))
              (should (string-match-p "80" (buffer-string)))
              (should (string-match-p "Launch date" (buffer-string)))))
        (when-let* ((runtime (etaf-runtime-for-buffer (current-buffer))))
          (etaf-unmount runtime))))))

;;; etaf-ui-modern-tests.el ends here
