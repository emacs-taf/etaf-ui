;;; etaf-ui-window-tests.el --- Controlled panel and window contracts -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'etaf-ui)

(ert-deftest etaf-ui-window-keeps-geometry-and-mode-controlled ()
  "Window geometry is projected from caller refs and mode only changes content."
  (let ((buffer-name " *etaf-ui-window-controlled-test*")
        (x (etaf-ref '(px 4)))
        (y (etaf-ref '(lh 1)))
        (mode (etaf-ref 'normal)))
    (unwind-protect
        (progn
          (etaf-mount
           buffer-name
           (etaf-view
            (etaf-window :title "Inspector" :ref 'window
                         :chrome-ref 'window-chrome
                         :x x :y y :width '(px 260) :height '(lh 12)
                         :mode mode
                         (etaf-label :text "Body"))))
          (let* ((runtime (etaf-runtime-for-buffer buffer-name))
                 (properties (etaf-runtime-host-props-for runtime 'window)))
            (should (equal (plist-get properties :position) 'absolute))
            (should (equal (plist-get properties :left) (etaf-value x)))
            (should (equal (plist-get properties :top) (etaf-value y)))
            (should (string-match-p "Body"
                                    (with-current-buffer buffer-name
                                      (buffer-string))))
            (setf (etaf-value mode) 'minimized)
            (should-not (string-match-p "Body"
                                        (with-current-buffer buffer-name
                                          (buffer-string))))
            (should (equal (plist-get (etaf-runtime-host-props-for runtime 'window)
                                      :left)
                           (etaf-value x)))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-window-forwards-chrome-and-resize-gestures ()
  "Title and handle gestures reach caller callbacks with their public payloads."
  (let ((buffer-name " *etaf-ui-window-gesture-test*")
        moves resizes actions)
    (unwind-protect
        (progn
          (etaf-mount
           buffer-name
           (etaf-view
            (etaf-window :title "Inspector" :ref 'window
                         :chrome-ref 'window-chrome
                         :resize-refs '((right . window-resize-right))
                         :width '(px 260) :height '(lh 12)
                         :on-move (lambda (gesture) (push gesture moves))
                         :on-resize (lambda (edge gesture)
                                      (push (list edge gesture) resizes))
                         :on-close (lambda () (push 'close actions))
                         (etaf-label :text "Body"))))
          (let ((runtime (etaf-runtime-for-buffer buffer-name)))
            (etaf-dispatch-event runtime 'window-chrome 'drag
                                 '(:phase move :delta (3 . 4)) t)
            (etaf-dispatch-event runtime 'window-resize-right 'drag
                                 '(:phase end :delta (8 . 0)) t)
            (etaf-dispatch-event runtime
                                 ;; Close is the final generated Button in the
                                 ;; chrome and is intentionally tested through
                                 ;; its semantic label lookup below.
                                 (car (cl-find-if
                                       (lambda (entry)
                                         (equal "Close"
                                                (plist-get (cdr entry) :aria-label)))
                                       (etaf-runtime-host-props-entries runtime)))
                                 'press)
            (should (= (length moves) 1))
            (should (equal (caar resizes) 'right))
            (should (equal (plist-get (cadar resizes) :phase) 'end))
            (should (equal actions '(close)))))
      (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
        (etaf-unmount runtime))
      (when-let* ((buffer (get-buffer buffer-name)))
        (kill-buffer buffer)))))

(ert-deftest etaf-ui-resizable-panel-rejects-unknown-edge ()
  "Resize edge input is checked before a Component is mounted."
  (should-error
   (etaf-mount " *etaf-ui-window-invalid-test*"
               (etaf-view
                (etaf-resizable-panel :resize-edges '(diagonal))))
   :type 'etaf-component-call-error)
  (when-let* ((buffer (get-buffer " *etaf-ui-window-invalid-test*")))
    (kill-buffer buffer)))

;;; etaf-ui-window-tests.el ends here
