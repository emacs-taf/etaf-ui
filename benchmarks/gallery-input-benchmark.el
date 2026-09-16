;;; gallery-input-benchmark.el --- Visible Gallery input audit -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Run gallery-input-benchmark-start through the existing emacsclient.
;; Each sample starts from a fresh, visibly mounted Gallery. Compare direct
;; public dispatch with native keyboard and mouse command paths. This measures
;; Emacs work through redisplay, not hardware or compositor presentation.
;; Trace mode is a separate diagnostic pass and never a latency acceptance run.

;;; Code:
(require 'cl-lib)
(require 'json)
(require 'etaf-ui)
(require 'ebox)

(defvar gallery-input-benchmark-result nil)
(defvar gallery-input-benchmark--jobs nil)
(defvar gallery-input-benchmark--timer nil)
(defvar gallery-input-benchmark--window nil)
(defvar gallery-input-benchmark--buffer nil)
(defvar gallery-input-benchmark--output nil)
(defvar gallery-input-benchmark--trace nil)
(defvar gallery-input-benchmark--require-foreground t)

(defconst gallery-input-benchmark--cases
  '(("Review interactions" "100%" 50)
    ("Activity" "Studio activity" 100)
    ("More" "Open inspector" 100)
    ("Quick help" "Tab to explore" 100)))

(defun gallery-input-benchmark--code ()
  "Identify loaded public entry implementations without traversing functions."
  (vconcat
   (mapcar
    (lambda (symbol)
      (let ((file (symbol-file symbol 'defun)))
        (list :function (symbol-name symbol) :file file
              :sha256 (and file (file-readable-p file)
                           (with-temp-buffer
                             (insert-file-contents-literally file)
                             (secure-hash 'sha256 (current-buffer)))))))
    '(ebox-commit etaf-dispatch-event etaf-ui-gallery-open))))

(defun gallery-input-benchmark--error (condition)
  "Return bounded error text without serializing captured application state."
  (let ((print-length 6) (print-level 4) (print-circle t))
    (error-message-string condition)))

(defun gallery-input-benchmark--write ()
  "Persist the current scalar report outside the checkout."
  (let ((coding-system-for-write 'utf-8-unix))
    (with-temp-file gallery-input-benchmark--output
      (insert (decode-coding-string
               (json-serialize gallery-input-benchmark-result
                               :null-object nil :false-object :false)
               'utf-8))
      (insert "\n"))))

(defun gallery-input-benchmark--check-window ()
  "Require the measured Gallery to occupy the selected live window."
  (unless (and (window-live-p gallery-input-benchmark--window)
               (eq (selected-window) gallery-input-benchmark--window)
               (eq (window-buffer gallery-input-benchmark--window)
                   gallery-input-benchmark--buffer)
               (display-graphic-p (window-frame gallery-input-benchmark--window))
               (eq (frame-visible-p (window-frame gallery-input-benchmark--window)) t)
               (not (active-minibuffer-window)))
    (error "Gallery window changed, became unavailable, or entered a minibuffer")))

(defun gallery-input-benchmark--environment ()
  "Return the identities and geometry that must stay stable within a sample."
  (list :buffer (buffer-name gallery-input-benchmark--buffer)
        :foreground (if (eq (frame-focus-state (selected-frame)) t) t :false)
        :font (format "%s" (frame-parameter nil 'font))
        :width (window-body-width nil t) :height (window-body-height nil t)
        :gc_threshold gc-cons-threshold :gc_percentage gc-cons-percentage))

(defun gallery-input-benchmark--target (runtime label)
  "Find a currently painted public control named LABEL."
  (or (car (cl-find-if
            (lambda (entry)
              (and (equal label (plist-get (cdr entry) :aria-label))
                   (etaf-host-ref-position runtime (car entry))))
            (etaf-runtime-host-props-entries runtime)))
      (error "No painted Gallery control named %s" label)))

(defun gallery-input-benchmark--route (runtime target method)
  "Build one actual METHOD action on TARGET before starting its timer."
  (pcase method
    ("callback" (lambda () (etaf-dispatch-event runtime target 'press)))
    ("keyboard" (lambda ()
                  (etaf-focus runtime target)
                  (execute-kbd-macro (kbd "RET"))))
    ("mouse"
     (let* ((position (etaf-host-ref-position runtime target))
            (posn (posn-at-point position gallery-input-benchmark--window)))
       (unless (and posn (pos-visible-in-window-p position
                                                   gallery-input-benchmark--window))
         (error "Mouse target is outside the visible window"))
       (lambda ()
         (execute-kbd-macro (vector (list 'down-mouse-1 posn)
                                   (list 'mouse-1 posn))))))
    (_ (error "Unknown measurement route: %s" method))))

(defun gallery-input-benchmark--reports ()
  "Return bounded public provider stage facts for this diagnostic sample."
  (vconcat
   (cl-mapcan
    (lambda (operation)
      (mapcar
       (lambda (stage)
         (let ((metadata (etaf-performance-stage-metadata stage)))
           (list :provider (symbol-name (etaf-performance-stage-provider stage))
                 :name (format "%s" (etaf-performance-stage-name stage))
                 :ms (etaf-performance-stage-duration stage)
                 :strategy (format "%s" (plist-get metadata :strategy))
                 :projection (format "%s" (plist-get metadata :projection-kind))
                 :dirty_count (plist-get metadata :dirty-count)
                 :reconciled_objects (plist-get metadata :reconciled-objects)
                 :text_operations (plist-get metadata :tp-text-operations)
                 :property_operations (plist-get metadata :tp-property-operations))))
       (etaf-performance-operation-stages operation)))
    (etaf-performance-records))))

(defun gallery-input-benchmark--measure (job)
  "Measure JOB against the visible mount prepared on the previous event turn."
  (condition-case condition
      (if (and gallery-input-benchmark--require-foreground
               (not (eq (frame-focus-state (selected-frame)) t)))
          (progn
            (push job gallery-input-benchmark--jobs)
            (setq gallery-input-benchmark--timer
                  (run-at-time 0.25 nil #'gallery-input-benchmark--next)))
        (progn
        (gallery-input-benchmark--check-window)
        (with-current-buffer gallery-input-benchmark--buffer
          (redisplay t)
          (let* ((runtime (etaf-runtime-for-buffer (current-buffer)))
                 (case (plist-get job :case))
                 (label (car case))
                 (method (plist-get job :method))
                 (target (gallery-input-benchmark--target runtime label))
                 (action (gallery-input-benchmark--route runtime target method))
                 (before (gallery-input-benchmark--environment))
                 (cpu-start (current-cpu-time))
                 (gc-start gc-elapsed) (gcs-start gcs-done)
                 (started (float-time))
                 action-end finished fault row)
            (condition-case problem
                (progn
                  (if gallery-input-benchmark--trace
                      (etaf-performance-call-operation runtime 'input label action)
                    (funcall action))
                  (setq action-end (float-time))
                  (redisplay t)
                  (setq finished (float-time)))
              ((error quit)
               (setq finished (float-time)
                     fault (gallery-input-benchmark--error problem))))
            (let* ((cpu-end (current-cpu-time))
                   (gc-ms (* 1000.0 (- gc-elapsed gc-start)))
                   (gc-count (- gcs-done gcs-start))
                   (elapsed (* 1000.0 (- finished started)))
                   (after (gallery-input-benchmark--environment))
                   (text (buffer-substring-no-properties (point-min) (point-max)))
                   (correct (and (not fault)
                                 (string-match-p (regexp-quote (cadr case)) text)))
                   (report (ebox-buffer-update-report (current-buffer))))
              (gallery-input-benchmark--check-window)
              (setq row
                    (list :set (plist-get job :set) :label label :method method
                          :trace (if gallery-input-benchmark--trace t :false)
                          :wall_ms elapsed
                          :command_ms (* 1000.0 (- (or action-end finished) started))
                          :redisplay_ms (if action-end (* 1000.0 (- finished action-end)) 0.0)
                          :cpu_ms (* 1000.0
                                     (- (/ (float (car cpu-end)) (cdr cpu-end))
                                        (/ (float (car cpu-start)) (cdr cpu-start))))
                          :gc_ms gc-ms :gc_count gc-count :error fault
                          :correct (if correct t :false)
                          :environment_stable (if (equal before after) t :false)
                          :before before :after after
                          :target_ms (nth 2 case) :hard_limit_ms 500
                          :strategy (format "%s" (plist-get report :strategy))
                          :projection (format "%s" (plist-get report :projection-kind))
                          :dirty_count (plist-get report :dirty-count)
                          :reconciled_objects (plist-get report :reconciled-objects)
                          :text_operations (plist-get report :tp-text-operations)
                          :property_operations (plist-get report :tp-property-operations)
                          :stages (if gallery-input-benchmark--trace
                                      (gallery-input-benchmark--reports) []))))
            (when gallery-input-benchmark--trace (etaf-performance-stop runtime))
            (setf (plist-get gallery-input-benchmark-result :samples)
                  (vconcat (plist-get gallery-input-benchmark-result :samples)
                           (vector row)))
            (gallery-input-benchmark--write)
            (when fault (error "%s" fault))))
        (setq gallery-input-benchmark--timer
              (run-at-time 0.1 nil #'gallery-input-benchmark--next))))
    ((error quit) (gallery-input-benchmark--finish
                   "error" (gallery-input-benchmark--error condition)))))

(defun gallery-input-benchmark--finish (status &optional error-text)
  "Finish with STATUS and bounded ERROR-TEXT, retaining every collected sample."
  (setq gallery-input-benchmark--jobs nil)
  (when (and gallery-input-benchmark--trace
             (buffer-live-p gallery-input-benchmark--buffer))
    (when-let* ((runtime (etaf-runtime-for-buffer gallery-input-benchmark--buffer)))
      (etaf-performance-stop runtime)))
  (setf (plist-get gallery-input-benchmark-result :status) status
        (plist-get gallery-input-benchmark-result :error) error-text)
  (gallery-input-benchmark--write))

(defun gallery-input-benchmark--next ()
  "Prepare one fresh visible Gallery and yield before dispatch."
  (condition-case condition
      (cond
       ((null gallery-input-benchmark--jobs)
        (gallery-input-benchmark--finish "completed"))
       ((and gallery-input-benchmark--require-foreground
             (not (eq (frame-focus-state (selected-frame)) t)))
        (setq gallery-input-benchmark--timer
              (run-at-time 0.25 nil #'gallery-input-benchmark--next)))
       (t
        (gallery-input-benchmark--check-window)
        (let* ((job (pop gallery-input-benchmark--jobs))
               (started (float-time)))
          (with-current-buffer gallery-input-benchmark--buffer
            (etaf-ui-gallery-open gallery-input-benchmark--buffer)
            (redisplay t)
            (setf (plist-get gallery-input-benchmark-result :last_mount_ms)
                  (* 1000.0 (- (float-time) started)))
            (when gallery-input-benchmark--trace
              (etaf-performance-start (etaf-runtime-for-buffer (current-buffer)))
              (etaf-performance-clear)))
          (setq gallery-input-benchmark--timer
                (run-at-time 0.1 nil #'gallery-input-benchmark--measure job)))))
    ((error quit) (gallery-input-benchmark--finish
                   "error" (gallery-input-benchmark--error condition)))))

(defun gallery-input-benchmark-start (output &optional trace allow-background)
  "Write three sets of visible Gallery input comparisons to fresh OUTPUT.
TRACE enables a separate instrumented provider-diagnostic pass. The function
returns promptly; poll gallery-input-benchmark-result for status. By default
sampling waits while Emacs is in the background. ALLOW-BACKGROUND labels such
diagnostic samples without treating them as foreground evidence. Do not print
Runtime objects. Existing frame geometry, GC policy and package code are kept."
  (when (and gallery-input-benchmark--jobs
             (equal (plist-get gallery-input-benchmark-result :status) "running"))
    (user-error "A Gallery input measurement is already running"))
  (when (file-exists-p output) (user-error "Evidence already exists: %s" output))
  (when (active-minibuffer-window) (user-error "An active minibuffer prevents sampling"))
  (unless (display-graphic-p) (user-error "An existing graphical Emacs is required"))
  (setq gallery-input-benchmark--output (expand-file-name output)
        gallery-input-benchmark--window (selected-window)
        gallery-input-benchmark--buffer (get-buffer-create "*ETAF UI Gallery*")
        gallery-input-benchmark--trace trace
        gallery-input-benchmark--require-foreground (not allow-background)
        gallery-input-benchmark--jobs
        (cl-loop for group from 1 to 3 append
                 (cl-loop for case in gallery-input-benchmark--cases append
                          (cl-loop for method in '("callback" "keyboard" "mouse")
                                   collect (list :set group :case case :method method)))))
  (switch-to-buffer gallery-input-benchmark--buffer)
  (setq gallery-input-benchmark-result
        (list :schema 1 :status "running" :error nil
              :boundary "visible native command through forced redisplay return"
              :presentation_measured :false :trace (if trace t :false)
              :foreground_required (if allow-background :false t)
              :emacs emacs-version :pid (emacs-pid) :init user-init-file
              :code (gallery-input-benchmark--code)
              :native_hash (plist-get (ebox-native-reflow-runtime-report) :loaded-module-hash)
              :samples []))
  (gallery-input-benchmark--write)
  (setq gallery-input-benchmark--timer (run-at-time 0.1 nil #'gallery-input-benchmark--next))
  'scheduled)

(defun gallery-input-benchmark-cancel ()
  "Cancel only the benchmark timer, retaining the user's Emacs and all samples."
  (when (timerp gallery-input-benchmark--timer)
    (cancel-timer gallery-input-benchmark--timer))
  (gallery-input-benchmark--finish "cancelled"))

(provide 'gallery-input-benchmark)
;;; gallery-input-benchmark.el ends here
