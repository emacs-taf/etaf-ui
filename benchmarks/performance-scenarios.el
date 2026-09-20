;;; performance-scenarios.el --- Public application interaction workloads -*- lexical-binding: t; -*-

;;; Commentary:
;; The shared driver owns sampling, profiling, timeouts and artifacts. These
;; adapters declare only application setup, real input and visible correctness.

;;; Code:
(require 'cl-lib)
(require 'etaf-ui)
(require 'ebox)
(declare-function taf-benchmark-register "performance-driver" (id &rest properties))

(defun etaf-ui-benchmark--observe (runtime buffer sink)
  "Observe RUNTIME in unique BUFFER and deliver public reports to SINK."
  (etaf-performance-start runtime)
  (let ((before (mapcar (lambda (operation)
                         (cons (plist-get operation :runtime-id) (plist-get operation :id)))
                       (plist-get (etaf-performance-report-data) :operations))))
    (lambda ()
      (etaf-performance-stop runtime)
      (dolist (operation (plist-get (etaf-performance-report-data) :operations))
        (when (and (equal (plist-get operation :buffer-name) (buffer-name buffer))
                   (not (member (cons (plist-get operation :runtime-id)
                                      (plist-get operation :id)) before)))
          (dolist (stage (plist-get operation :stages))
            (funcall sink (append (list :provider (plist-get stage :provider)
                                       :stage (plist-get stage :stage)
                                       :duration-ms (plist-get stage :duration-ms))
                                 (plist-get stage :metadata)))))))))

(defun etaf-ui-benchmark--environment ()
  "Return stable capability facts and the loaded native artifact identity."
  (let ((native (ebox-native-reflow-runtime-report)))
    (list :native_available (if (plist-get native :available-p) t :false)
          :native_layout (if (plist-get native :layout-ready-p) t :false)
          :native_hash (plist-get native :loaded-module-hash)
          :native_path (plist-get native :loaded-module-path)
          :render_gc_threshold ebox-render-gc-cons-threshold
          :render_gc_percentage ebox-render-gc-cons-percentage)))

(defun etaf-ui-benchmark--gallery (label expected route mode &optional steps existing-buffer)
  "Prepare Gallery LABEL through ROUTE in MODE and verify EXPECTED text.
STEPS cycles through public activations and visible expectations on one mount.
EXISTING-BUFFER borrows a mounted page without resetting or disposing it."
  (let ((buffer (or existing-buffer (generate-new-buffer " *TAF Gallery*")))
        (invocations 0) viewport-ready runtime target position observing step expected-text expected-visible)
    (unless existing-buffer (etaf-ui-gallery-open buffer))
    (setq runtime (etaf-runtime-for-buffer buffer))
    (unless runtime (error "The selected buffer has no mounted ETAF application"))
    (list
     :buffer buffer :environment #'etaf-ui-benchmark--environment
     :ready
     (lambda ()
       (unless (or existing-buffer viewport-ready)
         ;; SETUP mounts before the driver displays the buffer. Resolve the
         ;; actual containing viewport once it is visible, outside timing.
         (ebox-rerender-buffer-with-context
          buffer
          (if (eq mode 'gui) (ebox-viewport-window-width (selected-window))
            (* 120 (frame-char-width)))
          (if (eq mode 'gui) (window-body-height (selected-window)) 40))
         (setq viewport-ready t))
       t)
     :prepare
     (lambda ()
       (setq step (if steps (nth (% invocations (length steps)) steps)
                    (list :label label :text expected :visible t)))
       (let* ((text (with-current-buffer buffer
                      (buffer-substring-no-properties (point-min) (point-max))))
              (alternatives (plist-get step :alternate)))
         (setq expected-text (plist-get step :text)
               expected-visible (plist-get step :visible))
         (when alternatives
           (setq expected-text
                 (cond ((string-match-p (regexp-quote (car alternatives)) text) (cadr alternatives))
                       ((string-match-p (regexp-quote (cadr alternatives)) text) (car alternatives))
                       (t (error "The current Gallery does not show either expected value")))
                 expected-visible t))
         (when (plist-get step :toggle)
           (setq expected-visible
                 (not (string-match-p (regexp-quote expected-text) text)))))
       (unless (plist-get step :keys)
         (setq target
             (or (car (cl-find-if
                       (lambda (entry) (equal (plist-get step :label)
                                              (plist-get (cdr entry) :aria-label)))
                       (etaf-runtime-host-props-entries runtime)))
                 (error "Gallery target is absent: %s" (plist-get step :label))))
       (when (eq route 'mouse)
         (unless (eq mode 'gui) (error "Mouse requires GUI mode"))
         (let ((point (etaf-host-ref-position runtime target)))
           (unless (and point (pos-visible-in-window-p point (selected-window)))
             (error "Gallery mouse target is not visible: %s" label))
           (setq position (posn-at-point point (selected-window)))))))
     :invoke
     (lambda (_sample)
       (let ((action
              (lambda ()
                (if-let* ((keys (plist-get step :keys)))
                    (execute-kbd-macro (kbd keys))
                  (pcase route
                  ('callback (etaf-dispatch-event runtime target 'press))
                  ('keyboard (etaf-focus runtime target) (execute-kbd-macro (kbd "RET")))
                  ('mouse (execute-kbd-macro (vector (list 'down-mouse-1 position)
                                                   (list 'mouse-1 position)))))))))
         ;; Pressed-state publication precedes ETAF's application callback;
         ;; release/focus publication can follow it. Observe the complete input
         ;; operation so those provider commits are not reported as outside Ebox.
         ;; Latency and profiler passes retain the unobserved native route.
         (if observing
             (etaf-performance-call-operation
              runtime 'input (or (plist-get step :label) (plist-get step :keys)) action)
           (funcall action)))
       (cl-incf invocations))
     :outcome
     (lambda ()
       ;; Read the accepted last commit after timing, without enabling tracing
       ;; or changing the event boundary of the latency sample itself.
       (let ((report (ebox-buffer-update-report buffer)))
         (list :strategy (format "%s" (plist-get report :strategy))
               :projection (format "%s" (plist-get report :projection-kind))
               :dirty_count (plist-get report :dirty-count)
               :root_owner (if (member (plist-get report :constraint-root-node-id)
                                      (plist-get report :owner-ids)) t :false)
               :reconciled (plist-get report :reconciled-objects)
               :text_operations (plist-get report :publication-text-operations)
               :property_operations (plist-get report :publication-property-operations))))
     :verify (lambda ()
               (with-current-buffer buffer
                 (and (etaf-runtime-for-buffer buffer)
                      (eq (not (null (string-match-p
                                     (regexp-quote expected-text)
                                     (buffer-substring-no-properties (point-min) (point-max)))))
                          (not (null expected-visible))))))
     :observe (lambda (sink)
                (let ((finish (etaf-ui-benchmark--observe runtime buffer sink)))
                  (setq observing t)
                  (lambda ()
                    (setq observing nil)
                    (funcall finish))))
     :cleanup (lambda ()
                (when (and (not existing-buffer) (buffer-live-p buffer))
                  (when (etaf-runtime-for-buffer buffer) (etaf-unmount runtime))
                  (kill-buffer buffer))))))

(dolist (case '(("review" "Review interactions" "100%" 50 local)
                ("activity" "Activity" "Studio activity" 100 overlay)
                ("menu" "More" "Open inspector" 100 overlay)
                ("help" "Quick help" "Tab to explore" 100 overlay)))
  (dolist (route '(callback keyboard mouse))
    (let ((label (nth 1 case)) (expected (nth 2 case)) (method route))
      (taf-benchmark-register
       (format "gallery.%s.%s" (car case) route)
       :version 2 :modes (if (eq route 'callback) '(batch gui) '(gui))
       :required-providers '(ebox)
       :budget-ms (nth 3 case) :impact (nth 4 case)
       :description (format "%s via %s%s" label route
                            (if (eq route 'keyboard) " (focus then RET)" ""))
       :setup (lambda (mode) (etaf-ui-benchmark--gallery label expected method mode))))))

(dolist (route '(callback keyboard mouse))
  (let ((method route))
    (taf-benchmark-register
     (format "gallery.review.steady.%s" route)
     :version 2 :modes (if (eq route 'callback) '(batch gui) '(gui))
     :isolation 'series :required-providers '(ebox)
     :budget-ms 50 :impact 'local
     :description (format "Repeated Review toggles on one mounted Gallery via %s" route)
     :setup (lambda (mode)
              (etaf-ui-benchmark--gallery
               "Review interactions" "100%" method mode
               '((:label "Review interactions" :alternate ("67%" "100%"))))))))

(dolist (case '(("actions" "Actions" "Refresh workspace")
                ("more" "More" "Open inspector")))
  (dolist (route '(callback mouse))
    (let ((name (car case)) (label (cadr case)) (marker (nth 2 case)) (method route))
      (taf-benchmark-register
       (format "gallery.%s.steady.%s" name route)
       :version 2 :modes (if (eq route 'callback) '(batch gui) '(gui))
       :isolation 'series :required-providers '(ebox)
       :budget-ms 100 :impact 'overlay
       :description (format "Repeated %s open/close on one mounted Gallery via %s" label route)
       :setup (lambda (mode)
                (etaf-ui-benchmark--gallery
                 label marker method mode
                 (list (list :label label :text marker :toggle t))))))))

(defconst etaf-ui-benchmark--toolbar-steps
  '((:label "Actions" :text "Refresh workspace" :toggle t)
    (:label "Actions" :text "Refresh workspace" :toggle t)
    (:label "Review interactions" :alternate ("67%" "100%"))
    (:label "Review interactions" :alternate ("67%" "100%"))
    (:label "More" :text "Open inspector" :toggle t)
    (:label "More" :text "Open inspector" :toggle t)
    (:label "Review interactions" :alternate ("67%" "100%"))
    (:label "Review interactions" :alternate ("67%" "100%")))
  "Public overlay and content operations exercised on one retained page.")

(dolist (route '(callback mouse))
  (let ((method route))
    (taf-benchmark-register
     (format "gallery.tabs.steady.%s" route)
     :version 1 :modes (if (eq route 'callback) '(batch gui) '(gui))
     :isolation 'series :required-providers '(ebox)
     :budget-ms 100 :impact 'subtree
     :description (format "Library, Preferences and Workspace replacement via %s" route)
     :setup (lambda (mode)
              (etaf-ui-benchmark--gallery
               nil nil method mode
               '((:label "Component library" :text "Signals & status" :visible t)
                 (:label "Preferences" :text "Studio preferences" :visible t)
                 (:label "Workspace" :text "Release checklist" :visible t)))))))

(dolist (existing '(nil t))
  (let ((borrow existing))
    (taf-benchmark-register
     (if borrow "gallery.current.toolbar.mouse" "gallery.toolbar.sequence.mouse")
     :version (if borrow 1 2) :modes '(gui) :isolation 'series :required-providers '(ebox)
     :budget-ms 100 :impact 'mixed
     :description (if borrow "Actions, Review and More on the existing selected Gallery"
                    "Actions, Review and More alternated on one mounted Gallery")
     :setup (lambda (mode)
              (etaf-ui-benchmark--gallery
               nil nil 'mouse mode etaf-ui-benchmark--toolbar-steps
               (and borrow (window-buffer (selected-window))))))))

(taf-benchmark-register
 "etaf.counter" :version 1 :modes '(batch gui) :isolation 'series
 :required-providers '(ebox)
 :budget-ms 10 :impact 'local :description "Minimal reactive counter with visible text verification"
 :setup
 (lambda (_mode)
   (let ((buffer (generate-new-buffer " *TAF counter*"))
         (count (etaf-ref 0)) (expected 0) runtime)
     (etaf-mount buffer
                 (etaf-view
                  (box :ref 'counter :width '(ch 20) :tab-index 0
                       :on-press (lambda () (cl-incf (etaf-value count)))
                    (text (expr (format "Count: %d" (etaf-value count)))))))
     (setq runtime (etaf-runtime-for-buffer buffer))
     (list :buffer buffer :environment #'etaf-ui-benchmark--environment
           :invoke (lambda (_sample)
                     (cl-incf expected)
                     (etaf-dispatch-event runtime 'counter 'press))
           :verify (lambda ()
                     (with-current-buffer buffer
                       (and (= expected (etaf-value count))
                            (not (null (string-match-p (format "Count: %d" expected) (buffer-string)))))))
           :observe (lambda (sink) (etaf-ui-benchmark--observe runtime buffer sink))
           :cleanup (lambda ()
                      (when (buffer-live-p buffer)
                        (when (etaf-runtime-for-buffer buffer) (etaf-unmount runtime))
                        (kill-buffer buffer)))))))

;;; performance-scenarios.el ends here
