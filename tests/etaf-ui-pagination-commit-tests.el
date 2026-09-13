;;; etaf-ui-pagination-commit-tests.el --- Pager callback publication -*- lexical-binding: t; -*-

;;; Commentary:

;; A controlled pager must operate on the Controller whose UI was committed.
;; A rejected sibling cannot redirect retained buttons to candidate props.

;;; Code:

(require 'ert)
(require 'etaf-ui)

(defun etaf-ui-pagination-test--controller ()
  "Return an independently loaded three-page Controller."
  (etaf-data-controller
   (etaf-data-memory-source '((:id 1) (:id 2) (:id 3)) :id-key :id)
   :page-size 1 :auto-load t))

(ert-deftest etaf-ui-pagination-failed-controller-swap-keeps-live-callbacks ()
  "A rejected A-to-B render leaves both pager buttons bound to A."
  (dolist (case '((next . 3) (previous . 1)))
    (let* ((first (etaf-ui-pagination-test--controller))
           (second (etaf-ui-pagination-test--controller))
           (selected (etaf-ref first))
           (reject t)
           (buffer (generate-new-buffer " *pagination-commit*")))
      (unwind-protect
          (progn
            (etaf-data-set-page first 2)
            (etaf-data-set-page second 2)
            (etaf-mount
             buffer
             (lambda ()
               (etaf-view
                (column
                 (etaf-pagination :controller (etaf-value selected)
                                  :previous-ref 'previous :next-ref 'next)
                 (text (expr (if (and reject (eq (etaf-value selected) second))
                                 (error "Rejected pager sibling")
                               "Accepted sibling")))))))
            (let* ((runtime (etaf-runtime-for-buffer buffer))
                   (generation (etaf-runtime-current-generation runtime))
                   (published (with-current-buffer buffer (buffer-string)))
                   (next-handler (cdr (assq 'press
                                            (etaf-runtime-handler-for runtime 'next)))))
              (should-error (setf (etaf-value selected) second))
              (should (eq generation (etaf-runtime-current-generation runtime)))
              (should (equal-including-properties
                       published (with-current-buffer buffer (buffer-string))))
              (should (eq next-handler
                          (cdr (assq 'press (etaf-runtime-handler-for runtime 'next)))))
              ;; Let the event's later render recover.  This ordinary flag does
              ;; not render or replace the committed callback before the press.
              (setq reject nil)
              (etaf-dispatch-event runtime (car case) 'press)
              (should (= (etaf-value (etaf-data-page first)) (cdr case)))
              (should (= (etaf-value (etaf-data-page second)) 2))))
        (when-let* ((runtime (etaf-runtime-for-buffer buffer)))
          (etaf-unmount runtime))
        (etaf-data-stop first)
        (etaf-data-stop second)
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-pagination-successful-controller-swap-replaces-callbacks ()
  "A successful controller swap publishes its current values and callbacks."
  (let* ((first (etaf-ui-pagination-test--controller))
         (second (etaf-ui-pagination-test--controller))
         (selected (etaf-ref first))
         (caption (etaf-ref "Sibling A"))
         (buffer (generate-new-buffer " *pagination-controller-swap*")))
    (unwind-protect
        (progn
          (etaf-mount
           buffer
           (lambda ()
             (etaf-view
              (column
               (etaf-pagination :controller (etaf-value selected)
                                :previous-ref 'previous :next-ref 'next)
               (text (expr (etaf-value caption)))))))
          (let* ((runtime (etaf-runtime-for-buffer buffer))
                 (next-handler (cdr (assq 'press
                                          (etaf-runtime-handler-for runtime 'next))))
                 (next-bounds (etaf-host-ref-bounds runtime 'next)))
            (setf (etaf-value caption) "Sibling B")
            (should (eq next-handler
                        (cdr (assq 'press (etaf-runtime-handler-for runtime 'next)))))
            (should (equal next-bounds (etaf-host-ref-bounds runtime 'next)))
            (etaf-dispatch-event runtime 'next 'press)
            (should (= (etaf-value (etaf-data-page first)) 2))
            (setf (etaf-value selected) second)
            (should (string-match-p "Page 1 / 3"
                                    (with-current-buffer buffer (buffer-string))))
            (should-error (etaf-dispatch-event runtime 'previous 'press)
                          :type 'etaf-event-error)
            (etaf-dispatch-event runtime 'next 'press)
            (should (= (etaf-value (etaf-data-page second)) 2))
            (should (= (etaf-value (etaf-data-page first)) 2))
            (etaf-dispatch-event runtime 'previous 'press)
            (should (= (etaf-value (etaf-data-page second)) 1))
            (should (= (etaf-value (etaf-data-page first)) 2))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer)))
        (etaf-unmount runtime))
      (etaf-data-stop first)
      (etaf-data-stop second)
      (kill-buffer buffer))))

(ert-deftest etaf-ui-pagination-labels-retain-hit-areas-and-disabled-states ()
  "Localized labels keep complete Button hit areas and boundary semantics."
  (let* ((controller (etaf-ui-pagination-test--controller))
         (empty (etaf-data-controller
                 (etaf-data-memory-source nil :id-key :id)
                 :page-size 1 :auto-load t))
         (selected (etaf-ref controller))
         (buffer (generate-new-buffer " *pagination-labels*")))
    (unwind-protect
        (progn
          (etaf-mount
           buffer
           (lambda ()
             (etaf-view
              (etaf-pagination :controller (etaf-value selected)
                               :previous-ref 'previous :next-ref 'next
                               :previous-label "‹ 上一页" :next-label "下一页 ›"))))
          (let ((runtime (etaf-runtime-for-buffer buffer)))
            (dolist (case '((previous "‹ 上一页" "Previous page")
                            (next "下一页 ›" "Next page")))
              (let* ((ref (car case))
                     (bounds (etaf-host-ref-bounds runtime ref))
                     (props (gethash ref (etaf-runtime-host-props runtime))))
                (should bounds)
                (should (equal (plist-get props :aria-label) (nth 2 case)))
                (with-current-buffer buffer
                  (let ((text (buffer-substring-no-properties
                               (car bounds) (cdr bounds))))
                    (should (string-match-p (regexp-quote (nth 1 case)) text))
                    ;; The clickable Host includes padding on both sides.
                    (should (> (string-width text)
                               (string-width (nth 1 case))))))))
            (should-error (etaf-dispatch-event runtime 'previous 'press)
                          :type 'etaf-event-error)
            (etaf-data-set-page controller 3)
            (should-error (etaf-dispatch-event runtime 'next 'press)
                          :type 'etaf-event-error)
            (etaf-dispatch-event runtime 'previous 'press)
            (should (= (etaf-value (etaf-data-page controller)) 2))
            (setf (etaf-value (etaf-data-status controller)) 'loading)
            (dolist (ref '(previous next))
              (should-error (etaf-dispatch-event runtime ref 'press)
                            :type 'etaf-event-error))
            (setf (etaf-value selected) empty)
            (should (string-match-p "0–0 of 0"
                                    (with-current-buffer buffer (buffer-string))))
            (dolist (ref '(previous next))
              (should-error (etaf-dispatch-event runtime ref 'press)
                            :type 'etaf-event-error))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (etaf-data-stop empty)
      (kill-buffer buffer))))

(ert-deftest etaf-ui-pagination-wraps-complete-controls-in-narrow-space ()
  "A narrow allocation wraps whole controls without clipping page text."
  (let ((controller (etaf-ui-pagination-test--controller))
        (buffer (generate-new-buffer " *pagination-narrow*")))
    (unwind-protect
        (progn
          (etaf-mount
           buffer
           (etaf-view
            (etaf-pagination :controller controller
                             :previous-ref 'previous :next-ref 'next)))
          (dolist (width '(280 180 140))
            (ebox-surface-update-buffer-viewport buffer width 30)
            (with-current-buffer buffer
              (let ((text (buffer-string)))
                (dolist (label '("‹ Previous" "Next ›" "Page 1 / 3" "1–1 of 3"))
                  (should (string-match-p (regexp-quote label) text))))
              (goto-char (point-min))
              (while (< (point) (point-max))
                (should (<= (ebox-string-pixel-width
                             (buffer-substring (line-beginning-position)
                                               (line-end-position)))
                            (+ width 2)))
                (forward-line 1)))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer)))
        (etaf-unmount runtime))
      (etaf-data-stop controller)
      (kill-buffer buffer))))

(ert-deftest etaf-ui-pagination-keeps-explicit-colors-and-semantic-defaults ()
  "Explicit colors remain effective without replacing omitted variant defaults."
  (dolist (styles '(nil (:color "#F01234" :bgcolor "#123456"
                        :border ((px 1) solid "#ABCDEF"))))
    (let ((controller (etaf-ui-pagination-test--controller)))
      (with-temp-buffer
        (unwind-protect
            (progn
              (etaf-data-set-page controller 2)
              (etaf-mount
               (current-buffer)
               (etaf-node
                'column nil
                (list (etaf-node 'etaf-button
                                 '(:label "Reference" :ref reference
                                   :variant secondary) nil)
                      (etaf-node 'etaf-button
                                 '(:label "Disabled" :ref disabled :disabled t) nil)
                      (etaf-node 'etaf-pagination
                                 (append (list :controller controller
                                               :previous-ref 'previous :next-ref 'next)
                                         styles)
                                 nil))))
              (let* ((runtime (etaf-runtime-for-buffer (current-buffer)))
                     (reference (etaf-runtime-host-props-for runtime 'reference))
                     (disabled (etaf-runtime-host-props-for runtime 'disabled)))
                (dolist (ref '(previous next))
                  (let ((props (etaf-runtime-host-props-for runtime ref)))
                    (should (equal (plist-get props :color)
                                   (or (plist-get styles :color)
                                       (plist-get reference :color))))
                    (should (equal (plist-get props :background-color)
                                   (or (plist-get styles :bgcolor)
                                       (plist-get reference :background-color))))
                    (when styles
                      (should (equal (plist-get props :border)
                                     (plist-get styles :border))))))
                (etaf-dispatch-event runtime 'previous 'press)
                (let ((props (etaf-runtime-host-props-for runtime 'previous)))
                  (should (plist-get props :disabled))
                  (should (equal (plist-get props :color) (plist-get disabled :color)))
                  (should (equal (plist-get props :background-color)
                                 (or (plist-get styles :bgcolor)
                                     (plist-get disabled :background-color)))))))
          (when-let* ((runtime (etaf-runtime-for-buffer (current-buffer))))
            (etaf-unmount runtime))
          (etaf-data-stop controller))))))

(provide 'etaf-ui-pagination-commit-tests)
;;; etaf-ui-pagination-commit-tests.el ends here
