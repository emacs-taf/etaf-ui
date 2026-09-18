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

(defun etaf-ui-benchmark--gallery (label expected route mode)
  "Build a fresh Gallery and prepare LABEL through ROUTE in MODE."
  (let ((buffer (generate-new-buffer " *TAF Gallery*")) runtime target position observing)
    (etaf-ui-gallery-open buffer)
    (setq runtime (etaf-runtime-for-buffer buffer))
    (list
     :buffer buffer :environment #'etaf-ui-benchmark--environment
     :prepare
     (lambda ()
       (setq target
             (or (car (cl-find-if
                       (lambda (entry) (equal label (plist-get (cdr entry) :aria-label)))
                       (etaf-runtime-host-props-entries runtime)))
                 (error "Gallery target is absent: %s" label)))
       (when (eq route 'mouse)
         (unless (eq mode 'gui) (error "Mouse requires GUI mode"))
         (let ((point (etaf-host-ref-position runtime target)))
           (unless (and point (pos-visible-in-window-p point (selected-window)))
             (error "Gallery mouse target is not visible: %s" label))
           (setq position (posn-at-point point (selected-window))))))
     :invoke
     (lambda (_sample)
       (let ((action
              (lambda ()
                (pcase route
                  ('callback (etaf-dispatch-event runtime target 'press))
                  ('keyboard (etaf-focus runtime target) (execute-kbd-macro (kbd "RET")))
                  ('mouse (execute-kbd-macro (vector (list 'down-mouse-1 position)
                                                   (list 'mouse-1 position))))))))
         ;; Pressed-state publication precedes ETAF's application callback;
         ;; release/focus publication can follow it. Observe the complete input
         ;; operation so those provider commits are not reported as outside Ebox.
         ;; Latency and profiler passes retain the unobserved native route.
         (if observing
             (etaf-performance-call-operation runtime 'input label action)
           (funcall action))))
     :verify (lambda ()
               (with-current-buffer buffer
                 (and (etaf-runtime-for-buffer buffer)
                      (not (null (string-match-p (regexp-quote expected)
                                                (buffer-substring-no-properties (point-min) (point-max))))))))
     :observe (lambda (sink)
                (let ((finish (etaf-ui-benchmark--observe runtime buffer sink)))
                  (setq observing t)
                  (lambda ()
                    (setq observing nil)
                    (funcall finish))))
     :cleanup (lambda ()
                (when (buffer-live-p buffer)
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
       :version 1 :modes (if (eq route 'callback) '(batch gui) '(gui))
       :required-providers '(ebox)
       :budget-ms (nth 3 case) :impact (nth 4 case)
       :description (format "%s via %s%s" label route
                            (if (eq route 'keyboard) " (focus then RET)" ""))
       :setup (lambda (mode) (etaf-ui-benchmark--gallery label expected method mode))))))

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
