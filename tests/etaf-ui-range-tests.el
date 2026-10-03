;;; etaf-ui-range-tests.el --- Public API acceptance -*- lexical-binding: t; -*-

;;; Commentary:
;; Test supported package inputs, outputs, errors and lifecycle.
;; Internal implementation details are outside this contract.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'etaf-ui)

(defmacro etaf-ui-range-test--with-range (clause &rest body)
  "Mount an `etaf-range' with CLAUSE's props and bind its runtime.
CLAUSE is (RUNTIME PROP VALUE ...); RUNTIME receives (BUFFER . RUNTIME)."
  (declare (indent 1) (debug (form body)))
  (let ((runtime (car clause))
        (props (cdr clause)))
    `(let ((buffer (generate-new-buffer " *etaf-ui-range*")))
       (unwind-protect
           (save-window-excursion
             (delete-other-windows)
             (set-window-buffer (selected-window) buffer)
             (etaf-mount buffer (lambda () (etaf-view (flex :flex-direction 'column :align-items 'stretch
                                                   :width '(vw 100) :height '(vh 100)
                                                   (etaf-range ,@props))))
                         '(:viewport-width 240 :viewport-height 8))
             (etaf-runtime-flush (etaf-runtime-for-buffer buffer))
             (let ((,runtime (cons buffer (etaf-runtime-for-buffer buffer))))
               ,@body))
         (when-let* ((live (etaf-runtime-for-buffer buffer)))
           (etaf-unmount live))
         (when (buffer-live-p buffer) (kill-buffer buffer))))))

(defun etaf-ui-range-test--pixels (entry host)
  "Return HOST's painted (LEFT WIDTH) inside ENTRY's mounted buffer."
  (pcase-let* ((`(,buffer . ,runtime) entry)
               (bounds (etaf-host-ref-bounds runtime host)))
    (should bounds)
    (with-current-buffer buffer
      (let ((start (car bounds)) (end (cdr bounds)))
        (list (ebox-string-pixel-width
               (buffer-substring (save-excursion (goto-char start)
                                                 (line-beginning-position))
                                 start))
              (ebox-string-pixel-width (buffer-substring start end)))))))

(defun etaf-ui-range-test--dispatch (entry host kind ratio &optional phase)
  "Dispatch KIND for HOST in ENTRY at RATIO, with drag PHASE when given."
  (pcase-let* ((`(,buffer . ,runtime) entry)
               (`(,left ,width) (etaf-ui-range-test--pixels entry host))
               (x (+ left (* ratio width)))
               (payload (list :phase phase :host-ref host :window (selected-window)
                              :buffer buffer :position (cons x 0))))
    (etaf-dispatch-event runtime host kind payload t)))

(ert-deftest etaf-ui-range-registers-track-and-fill-hosts ()
  "A mounted Range registers its Track and Fill Hosts for retained updates.
Painted proportions need a graphical frame and are checked by the GUI pass;
this batch contract covers the Host identities every retained update needs."
  (etaf-ui-range-test--with-range (entry :value 25 :ref 'range-track :fill-ref 'range-fill)
    (pcase-let* ((`(,buffer . ,runtime) entry)
                 (refs (mapcar #'car (etaf-runtime-host-props-entries runtime))))
      (should (etaf-host-ref-bounds runtime 'range-track))
      (should (memq 'range-fill refs)))))

(ert-deftest etaf-ui-range-fill-moves-through-retained-geometry ()
  "A caller moves the Fill in place through ETAF's retained geometry update.
The Fill is an absolutely positioned Host, so a playing position advances
without publishing a new View."
  (etaf-ui-range-test--with-range (entry :value 25 :ref 'range-track :fill-ref 'range-fill)
    (pcase-let* ((`(,buffer . ,runtime) entry)
                 (before (etaf-host-ref-bounds runtime 'range-fill))
                 (generation (etaf-runtime-generation runtime)))
      (should before)
      (etaf-runtime-update-host-geometries
       runtime (list (cons 'range-fill (list :width '(% 75)))))
      (etaf-runtime-flush runtime)
      (let ((after (etaf-host-ref-bounds runtime 'range-fill)))
        (should (and after
                     (> (- (cdr after) (car after))
                        (- (cdr before) (car before)))))
        (should (= (etaf-runtime-generation runtime) generation))))))

(ert-deftest etaf-ui-range-press-reports-change-and-commit ()
  "A click reports the pointed value through on-change and on-commit."
  (let (events)
    (etaf-ui-range-test--with-range
        (entry :value 0 :ref 'range-track :fill-ref 'range-fill
               :on-change (lambda (value) (push (cons :change value) events))
               :on-commit (lambda (value) (push (cons :commit value) events)))
      (etaf-ui-range-test--dispatch entry 'range-track 'press 0.75)
      (should (= (length events) 2))
      (should (eq (caar events) :commit))
      (should (eq (caadr events) :change))
      (dolist (event events)
        (should (< (abs (- (cdr event) 75)) 1.5))))))

(ert-deftest etaf-ui-range-drag-reports-live-values-and-commits-on-release ()
  "Dragging reports intermediate values, commits at the end and drops a cancel."
  (let ((value (etaf-ref 0)) changes commits handler)
    (etaf-ui-range-test--with-range
        (entry :value value :ref 'range-track :fill-ref 'range-fill
               :on-change (lambda (value) (push value changes))
               :on-commit (lambda (value) (push value commits)))
      (setq handler (plist-get (cdr (assq 'range-track (etaf-runtime-host-props-entries (cdr entry)))) :on-drag))
      (etaf-ui-range-test--dispatch entry 'range-track 'drag 0.25 'start)
      (etaf-ui-range-test--dispatch entry 'range-track 'drag 0.5 'move)
      (etaf-ui-range-test--dispatch entry 'range-track 'drag 0.6 'cancel)
      (should (null commits))
      (etaf-ui-range-test--dispatch entry 'range-track 'drag 0.75 'end)
      (should (= (length changes) 3))
      (should (= (length commits) 1))
      (should (< (abs (- (car (last changes)) 25)) 1.5))
      (should (< (abs (- (car commits) 75)) 1.5))
      (etaf-runtime-flush (cdr entry))
      (should (eq handler (plist-get (cdr (assq 'range-track (etaf-runtime-host-props-entries (cdr entry)))) :on-drag)))
      (let ((before (etaf-host-ref-bounds (cdr entry) 'range-fill)))
        (etaf-set-value value 20)
        (etaf-runtime-flush (cdr entry))
        (let ((after (etaf-host-ref-bounds (cdr entry) 'range-fill)))
          (should (< (- (cdr after) (car after)) (- (cdr before) (car before))))))
      (should (eq handler (plist-get (cdr (assq 'range-track (etaf-runtime-host-props-entries (cdr entry)))) :on-drag))))))

(ert-deftest etaf-ui-range-snaps-to-the-step-and-clamps-the-ends ()
  "Pointer values snap to :step and never escape :min..:max."
  (let (reported)
    (etaf-ui-range-test--with-range
        (entry :value 0 :min 0 :max 100 :step 10 :ref 'range-track :fill-ref 'range-fill
               :on-commit (lambda (value) (push value reported)))
      (etaf-ui-range-test--dispatch entry 'range-track 'press 0.46)
      (etaf-ui-range-test--dispatch entry 'range-track 'press 1.0)
      (should (equal reported '(100 50))))))

(ert-deftest etaf-ui-range-disabled-rejects-pointer-events ()
  "A disabled Range dispatches no callback and rejects pointer events."
  (let (reported)
    (etaf-ui-range-test--with-range
        (entry :value 40 :disabled t :ref 'range-track :fill-ref 'range-fill
               :on-change (lambda (value) (push value reported))
               :on-commit (lambda (value) (push value reported)))
      (should-error (etaf-ui-range-test--dispatch entry 'range-track 'press 0.5))
      (should (null reported)))))

(ert-deftest etaf-ui-range-validates-its-input ()
  "Invalid numeric props fail before the Range paints."
  (should-error
   (etaf-ui-range-test--with-range (entry :value 5 :min 10 :max 0)
     (ignore entry))))

(provide 'etaf-ui-range-tests)
;;; etaf-ui-range-tests.el ends here
