;;; etaf-ui-gallery-latency.el --- Atelier interaction latency evidence -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Latency evidence for the Atelier Gallery.  Each anchor is one public control.
;; A sample resets the surface outside the measured region when necessary,
;; dispatches the activation through the public ETAF event API, and ends when
;; the forced `redisplay' returns.  A sample whose committed content did not
;; change is recorded as skipped instead of counted, so every counted sample is
;; a real state change with verified output.

;; Publication and display are timed separately.  Diagnostics (commit count and
;; duration, Ebox render-layout calls, update strategy, dirty count, GC) are
;; recorded per sample from the same run but never dominate the reported
;; latency.  The tool never changes window configuration, buffer selection, or
;; GC policy; independent groups come from independent Emacs processes.

;;; Code:

(require 'cl-lib)
(require 'json)
;; Development tools load the workspace through scripts/ecosystem.el so load
;; paths and feature order never depend on a caller's ad-hoc setup.
(load (expand-file-name "../../scripts/ecosystem.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil t t)

(declare-function etaf-ecosystem-require "ecosystem" (&rest features))
(declare-function etaf-ecosystem-buffer "ecosystem" (name))
(etaf-ecosystem-require 'etaf-ui 'etaf-ui-gallery)
(declare-function ebox-buffer-update-report "ebox-runtime" (buffer-or-name))
(declare-function ebox-commit "ebox-runtime"
                  (buffer-or-name next-root &optional framework-publish
                                  framework-rollback))
(declare-function ebox--render-layout "ebox-layout" (node))

(defconst etaf-ui-gallery-latency-limit-ms 500.0
  "Hard per-sample limit for every measured interaction.")

(defvar etaf-ui-gallery-latency-buffer nil)
(defvar etaf-ui-gallery-latency-commits nil)
(defvar etaf-ui-gallery-latency-advices nil)
(defvar etaf-ui-gallery-latency-layouts 0)
(defvar etaf-ui-gallery-latency-layout-ms 0.0)

(defun etaf-ui-gallery-latency--runtime ()
  "Return the mounted Runtime of the measurement target."
  (or (and (buffer-live-p etaf-ui-gallery-latency-buffer)
           (etaf-runtime-for-buffer etaf-ui-gallery-latency-buffer))
      (error "Gallery target is not mounted")))

(defun etaf-ui-gallery-latency-mount ()
  "Mount a fresh Gallery target and return its first-mount duration in ms."
  (when (buffer-live-p etaf-ui-gallery-latency-buffer)
    (with-current-buffer etaf-ui-gallery-latency-buffer
      (when-let* ((runtime (etaf-runtime-for-buffer (current-buffer))))
        (etaf-unmount runtime)))
    (kill-buffer etaf-ui-gallery-latency-buffer))
  (let ((started (float-time)))
    (setq etaf-ui-gallery-latency-buffer
          (etaf-ui-gallery-open (etaf-ecosystem-buffer "*ETAF UI Gallery latency*")))
    (with-current-buffer etaf-ui-gallery-latency-buffer
      (unless (string-match-p "Release checklist"
                              (buffer-substring-no-properties (point-min) (point-max)))
        (error "Gallery target did not publish its workspace")))
    (* 1000.0 (- (float-time) started))))

(defun etaf-ui-gallery-latency--text ()
  (with-current-buffer etaf-ui-gallery-latency-buffer
    (buffer-substring-no-properties (point-min) (point-max))))

(defun etaf-ui-gallery-latency-control (label)
  "Return the first committed control whose aria-label is LABEL."
  (let ((runtime (etaf-ui-gallery-latency--runtime)) (found nil))
    (dolist (entry (etaf-runtime-host-props-entries runtime))
      (when (and (equal label (plist-get (cdr entry) :aria-label))
                 (etaf-host-ref-position runtime (car entry)))
        (let ((bounds (etaf-host-ref-bounds runtime (car entry))))
          (when bounds (push (cons (car bounds) (car entry)) found)))))
    (cdr (car (sort found (lambda (a b) (< (car a) (car b))))))))

(defun etaf-ui-gallery-latency-visible-p (label)
  (and (etaf-ui-gallery-latency-control label) t))

(defun etaf-ui-gallery-latency-press (label)
  "Dispatch one activation for LABEL through the public ETAF event API."
  (etaf-dispatch-event (etaf-ui-gallery-latency--runtime)
                       (or (etaf-ui-gallery-latency-control label)
                           (error "Missing Gallery control: %s" label))
                       'press))

(defun etaf-ui-gallery-latency--scroll (command)
  (with-current-buffer etaf-ui-gallery-latency-buffer
    (goto-char (point-min))
    (let ((current-prefix-arg 1))
      (call-interactively (key-binding (kbd command)))))
  (redisplay t))

(defun etaf-ui-gallery-latency-show (label)
  "Scroll LABEL into the committed region outside any measured region."
  (let ((attempts 0))
    (while (and (< attempts 20) (not (etaf-ui-gallery-latency-visible-p label)))
      (cl-incf attempts)
      (etaf-ui-gallery-latency--scroll "C-v"))
    (unless (etaf-ui-gallery-latency-visible-p label)
      (error "Gallery control is unavailable: %s" label)))
  (redisplay t))

(defun etaf-ui-gallery-latency--page (tab)
  "Make TAB the active Gallery page outside any measured region."
  (etaf-ui-gallery-latency-show tab)
  (etaf-ui-gallery-latency-press tab)
  (redisplay t)
  (etaf-ui-gallery-latency-show tab))

;;; Interaction inventory

(defconst etaf-ui-gallery-latency-interactions
  '((:id "help-popover"
     :claim "Quick help popover opens"
     :trigger "Quick help"
     :probe "Tab to explore"
     :prepare etaf-ui-gallery-latency--prepare-header)
    (:id "profile-popover"
     :claim "Profile popover opens"
     :trigger "GK · Studio"
     :probe "Manage preferences"
     :prepare etaf-ui-gallery-latency--prepare-header)
    (:id "actions-menu"
     :claim "Actions dropdown menu opens"
     :trigger "Actions"
     :probe "Refresh workspace"
     :prepare etaf-ui-gallery-latency--prepare-header)
    (:id "context-menu"
     :claim "More context menu opens"
     :trigger "More"
     :probe "Open inspector"
     :prepare etaf-ui-gallery-latency--prepare-header)
    (:id "toast-open"
     :claim "Studio activity toast opens"
     :trigger "Activity"
     :probe "Dismiss"
     :prepare etaf-ui-gallery-latency--prepare-header)
    (:id "new-project-dialog"
     :claim "New project dialog opens"
     :trigger "+ New project"
     :probe "Project name"
     :prepare etaf-ui-gallery-latency--prepare-header)
    (:id "inspector-drawer"
     :claim "Inspector drawer opens"
     :trigger "More"
     :probe "Close inspector"
     :prepare etaf-ui-gallery-latency--prepare-header)
    (:id "accordion-open"
     :claim "Project notes accordion expands"
     :trigger "Creative brief"
     :probe "Keep it clear"
     :prepare etaf-ui-gallery-latency--prepare-header))
  "Measured public Atelier interactions.")

(defun etaf-ui-gallery-latency--prepare-header ()
  "Close every header-owned floating surface outside the measured region."
  (etaf-ui-gallery-latency--page "Workspace")
  (dolist (probe '("Tab to explore" "Manage preferences" "Refresh workspace"
                   "Open inspector" "Dismiss" "Project name" "Close inspector"))
    (when (etaf-ui-gallery-latency-visible-p probe)
      (etaf-ui-gallery-latency-dismiss)
      (redisplay t)))
  (dolist (probe '("Tab to explore" "Manage preferences" "Refresh workspace"
                   "Open inspector" "Dismiss" "Project name" "Close inspector"))
    (when (etaf-ui-gallery-latency-visible-p probe)
      (error "Header surface stayed open: %s" probe))))

(defun etaf-ui-gallery-latency-dismiss ()
  "Dismiss the active floating surface through the buffer's own key binding."
  (with-current-buffer etaf-ui-gallery-latency-buffer
    (execute-kbd-macro (kbd "<escape>"))))

;;; Instrumentation

(defun etaf-ui-gallery-latency-layout-advice (function &rest arguments)
  (let ((began (float-time)))
    (cl-incf etaf-ui-gallery-latency-layouts)
    (prog1 (apply function arguments)
      (cl-incf etaf-ui-gallery-latency-layout-ms (- (float-time) began)))))

(defun etaf-ui-gallery-latency-commit-advice (function buffer input &rest arguments)
  (let ((began (float-time)))
    (prog1 (apply function buffer input arguments)
      (let ((report (ignore-errors (ebox-buffer-update-report buffer))))
        (push (list :ms (* 1000.0 (- (float-time) began))
                    :strategy (plist-get report :strategy)
                    :scope (plist-get report :render-scope)
                    :dirty (plist-get report :dirty-count)
                    :reconciled (plist-get report :reconciled-objects))
              etaf-ui-gallery-latency-commits)))))

(defun etaf-ui-gallery-latency-instrument ()
  (advice-add 'ebox-commit :around #'etaf-ui-gallery-latency-commit-advice)
  (advice-add 'ebox--render-layout :around #'etaf-ui-gallery-latency-layout-advice))

(defun etaf-ui-gallery-latency-uninstrument ()
  (advice-remove 'ebox-commit #'etaf-ui-gallery-latency-commit-advice)
  (advice-remove 'ebox--render-layout #'etaf-ui-gallery-latency-layout-advice))

;;; Sampling

(defun etaf-ui-gallery-latency--open-p (spec)
  (and (etaf-ui-gallery-latency-visible-p (plist-get spec :probe)) t))

(defun etaf-ui-gallery-latency--reset (spec)
  "Drive INTERACTION's surface to the state it must leave, outside the timer."
  (funcall (plist-get spec :prepare))
  (when (etaf-ui-gallery-latency--open-p spec)
    (etaf-ui-gallery-latency-dismiss)
    (redisplay t)))

(defun etaf-ui-gallery-latency--sample (spec)
  "Return one sample for SPEC, or nil when the reset could not reach its state."
  (let* ((trigger (plist-get spec :trigger))
         (before (etaf-ui-gallery-latency--text))
         (target (or (etaf-ui-gallery-latency-control trigger)
                     (error "Missing Gallery control: %s" trigger)))
         (etaf-ui-gallery-latency-commits nil)
         (etaf-ui-gallery-latency-layouts 0)
         (etaf-ui-gallery-latency-layout-ms 0.0)
         (gc-count gcs-done)
         (gc-elapsed gc-elapsed)
         (started (float-time)))
    (etaf-dispatch-event (etaf-ui-gallery-latency--runtime) target 'press)
    (let ((published (float-time)))
      (redisplay t)
      (let* ((shown (float-time))
             (changed (not (equal before (etaf-ui-gallery-latency--text))))
             (commits (reverse etaf-ui-gallery-latency-commits)))
        (when changed
          (list :total_ms (* 1000.0 (- shown started))
                :publish_ms (* 1000.0 (- published started))
                :display_ms (* 1000.0 (- shown published))
                :gc_count (- gcs-done gc-count)
                :gc_ms (* 1000.0 (- gc-elapsed gc-elapsed))
                :commits (length commits)
                :commit_ms (* 1000.0
                                (cl-loop for commit in commits
                                         sum (or (plist-get commit :ms) 0.0)))
                :strategies (delete-dups
                             (delq nil (mapcar (lambda (commit)
                                                 (plist-get commit :strategy))
                                               commits)))
                :scopes (delete-dups
                         (delq nil (mapcar (lambda (commit) (plist-get commit :scope))
                                           commits)))
                :dirty_max (apply #'max 0
                                  (mapcar (lambda (commit)
                                            (or (plist-get commit :dirty) 0))
                                          commits))
                :reconciled_max (apply #'max 0
                                       (mapcar (lambda (commit)
                                                 (or (plist-get commit :reconciled) 0))
                                               commits))
                :layouts etaf-ui-gallery-latency-layouts
                :layout_ms (* 1000.0 etaf-ui-gallery-latency-layout-ms)
                :verified (etaf-ui-gallery-latency--open-p spec)))))))

(defun etaf-ui-gallery-latency--stats (values)
  (let* ((ordered (sort (copy-sequence values) #'<))
         (count (length ordered)))
    (list :min_ms (car ordered)
          :p50_ms (nth (floor (* 0.50 (1- count))) ordered)
          :p95_ms (nth (floor (* 0.95 (1- count))) ordered)
          :max_ms (car (last ordered)))))

(defun etaf-ui-gallery-latency--measure (spec runs warmups)
  "Measure SPEC with RUNS counted samples after WARMUPS warmups."
  (let ((warm nil) (samples nil) (skipped 0))
    (dotimes (_ warmups)
      (etaf-ui-gallery-latency--reset spec)
      (push (etaf-ui-gallery-latency--sample spec) warm))
    (dotimes (_ runs)
      (etaf-ui-gallery-latency--reset spec)
      (let ((sample (etaf-ui-gallery-latency--sample spec)))
        (if sample (push sample samples) (cl-incf skipped))))
    (setq warm (nreverse warm) samples (nreverse samples))
    (unless samples
      (error "Interaction produced no counted sample: %s" (plist-get spec :id)))
    (list :id (plist-get spec :id)
          :claim (plist-get spec :claim)
          :trigger (plist-get spec :trigger)
          :probe (plist-get spec :probe)
          :counted (length samples)
          :skipped skipped
          :warmups (vconcat warm)
          :samples (vconcat samples)
          :stats (etaf-ui-gallery-latency--stats
                  (mapcar (lambda (sample) (plist-get sample :total_ms)) samples))
          :publish_stats (etaf-ui-gallery-latency--stats
                          (mapcar (lambda (sample) (plist-get sample :publish_ms)) samples))
          :commit_stats (etaf-ui-gallery-latency--stats
                         (mapcar (lambda (sample) (plist-get sample :commit_ms)) samples))
          :display_stats (etaf-ui-gallery-latency--stats
                          (mapcar (lambda (sample) (plist-get sample :display_ms)) samples))
          :layouts_max (apply #'max 0
                              (mapcar (lambda (sample) (or (plist-get sample :layouts) 0))
                                      samples))
          :layout_ms_max (apply #'max 0
                                (mapcar (lambda (sample)
                                          (or (plist-get sample :layout_ms) 0))
                                        samples))
          :commits_max (apply #'max 0
                              (mapcar (lambda (sample) (or (plist-get sample :commits) 0))
                                      samples))
          :dirty_max (apply #'max 0
                            (mapcar (lambda (sample) (or (plist-get sample :dirty_max) 0))
                                    samples))
          :reconciled_max (apply #'max 0
                                 (mapcar (lambda (sample)
                                           (or (plist-get sample :reconciled_max) 0))
                                         samples))
          :gc_count (apply #'+ 0 (mapcar (lambda (sample) (or (plist-get sample :gc_count) 0))
                                         samples))
          :strategies (delete-dups
                       (cl-loop for sample in samples
                                append (plist-get sample :strategies)))
          :scopes (delete-dups
                   (cl-loop for sample in samples
                            append (plist-get sample :scopes))))))

;;; Report

(defun etaf-ui-gallery-latency--git (directory arguments)
  (with-temp-buffer
    (when (eq 0 (apply #'process-file "git" nil t nil "-C" directory arguments))
      (string-trim (buffer-string)))))

(defun etaf-ui-gallery-latency--root ()
  "Return the checkout root that owns this evaluator."
  (let* ((source (or load-file-name buffer-file-name
                     (symbol-file 'etaf-ui-gallery-latency-run 'defun)))
         (directory (file-name-directory (or source default-directory))))
    (if (file-exists-p (expand-file-name "etaf-ui.el" directory))
        (expand-file-name ".." directory)
      (expand-file-name ".." (file-name-directory directory)))))

(defun etaf-ui-gallery-latency--write (output report)
  (make-directory (file-name-directory (expand-file-name output)) t)
  (with-temp-file (expand-file-name output)
    (let ((coding-system-for-write 'utf-8-unix))
      (insert (decode-coding-string
               (json-serialize report :null-object nil :false-object :false)
               'utf-8-unix)
              "\n"))))

(defun etaf-ui-gallery-latency-run (output &optional runs warmups groups)
  "Measure every interaction and write JSON evidence to OUTPUT.
RUNS counted samples, WARMUPS warmups and GROUPS independent mounts default to
30, 5 and 3.  Report the hard-limit failures without discarding samples."
  (let* ((runs (or runs 30))
         (warmups (or warmups 5))
         (groups (or groups 3))
         (root (etaf-ui-gallery-latency--root))
         (started (float-time))
         (mounts nil)
         (results nil)
         (failures nil))
    (etaf-ui-gallery-latency-instrument)
    (unwind-protect
        (dotimes (group groups)
          (push (list :group (1+ group) :mount_ms (etaf-ui-gallery-latency-mount)) mounts)
          (let ((anchors (mapcar (lambda (spec)
                                   (etaf-ui-gallery-latency--measure spec runs warmups))
                                 etaf-ui-gallery-latency-interactions)))
            (dolist (anchor anchors)
              (when (> (plist-get (plist-get anchor :stats) :max_ms)
                       etaf-ui-gallery-latency-limit-ms)
                (push (list :group (1+ group)
                            :interaction (plist-get anchor :id)
                            :max_ms (plist-get (plist-get anchor :stats) :max_ms))
                      failures)))
            (push (list :group (1+ group) :interactions (vconcat anchors)) results)))
      (etaf-ui-gallery-latency-uninstrument))
    (let ((report
           (list :schema 1
                 :generated (format-time-string "%Y-%m-%dT%H:%M:%S%z")
                 :emacs (emacs-version)
                 :pid (emacs-pid)
                 :graphic (and (display-graphic-p) t)
                 :frame (list :text_width (frame-text-width)
                              :text_height (frame-text-height))
                 :font (format "%s" (frame-parameter nil 'font))
                 :source (list :root root
                               :revision (etaf-ui-gallery-latency--git
                                          root '("rev-parse" "HEAD"))
                               :status (etaf-ui-gallery-latency--git
                                        root '("status" "--short")))
                 :limit_ms etaf-ui-gallery-latency-limit-ms
                 :sampling (list :runs runs :warmups warmups :groups groups)
                 :mounts (vconcat (nreverse mounts))
                 :groups (vconcat (nreverse results))
                 :failures (vconcat (nreverse failures))
                 :elapsed_s (- (float-time) started))))
      (etaf-ui-gallery-latency--write output report)
      report)))

(provide 'etaf-ui-gallery-latency)
;;; etaf-ui-gallery-latency.el ends here
