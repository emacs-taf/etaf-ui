;;; etaf-ui-surfaces-gui.el --- Native floating UI interaction check -*- lexical-binding: t; -*-

;;; Commentary:
;; Loaded by scripts/run-gui-check.sh in an existing graphical Emacs server.
;; Exercise native command bindings and minibuffer input in the dedicated
;; example buffer. This is not an OS input-method or latency certification.

;;; Code:
(require 'etaf-ui)
(require 'cl-lib)
(defvar etaf-ui-gui-interactions nil)
(defvar etaf-ui-gui-steps nil)
(defvar etaf-ui-gui-original-keys nil)
(defvar etaf-ui-gui-expected-quit nil)

(defun etaf-ui-gui-runtime ()
  (or (etaf-runtime-for-buffer "*ETAF UI Surfaces*") (error "Fixture is unmounted")))
(defun etaf-ui-gui-control (label)
  (let ((runtime (etaf-ui-gui-runtime)))
    (car (cl-find-if
          (lambda (entry)
            (and (equal label (plist-get (cdr entry) :aria-label))
                 (etaf-host-ref-position runtime (car entry))))
          (etaf-runtime-host-props-entries runtime)))))
(defun etaf-ui-gui-expect (test format-string &rest args)
  (unless test (apply #'error format-string args)))
(defun etaf-ui-gui-focused (label)
  (etaf-ui-gui-expect
   (equal (etaf-focused-host-ref (etaf-ui-gui-runtime))
          (or (etaf-ui-gui-control label) (error "Missing control %s" label)))
   "Expected focus on %s" label))
(defun etaf-ui-gui-key (keys)
  (execute-kbd-macro (kbd keys)))
(defun etaf-ui-gui-tab-to (label)
  (let* ((runtime (etaf-ui-gui-runtime))
         (target (or (etaf-ui-gui-control label) (error "Missing control %s" label)))
         (limit (1+ (length (etaf-runtime-host-props-entries runtime)))))
    (while (and (> limit 0) (not (equal target (etaf-focused-host-ref runtime))))
      (etaf-ui-gui-key "TAB") (cl-decf limit))
    (etaf-ui-gui-focused label)))
(defun etaf-ui-gui-press (label)
  (etaf-ui-gui-tab-to label) (etaf-ui-gui-key "RET"))
(defun etaf-ui-gui-visible (label expected)
  (etaf-ui-gui-expect (eq (and (etaf-ui-gui-control label) t) expected)
                         "Visibility mismatch for %s" label))
(defun etaf-ui-gui-text (text)
  (etaf-ui-gui-expect (string-match-p (regexp-quote text) (buffer-string))
                         "Missing rendered text %s" text))
(defun etaf-ui-gui-input (text &optional cancel)
  (let ((entered nil))
    (setq etaf-ui-gui-expected-quit cancel)
    (minibuffer-with-setup-hook
        (lambda ()
          (setq entered t)
          (delete-minibuffer-contents)
          (setq unread-command-events
                (append (listify-key-sequence (vconcat text (kbd (if cancel "C-g" "RET"))))
                        unread-command-events)))
      (etaf-ui-gui-press "名称"))
    (etaf-ui-gui-expect entered "Native minibuffer was not entered")
    (etaf-ui-gui-expect (not (active-minibuffer-window)) "Minibuffer stayed active")
    (etaf-ui-gui-focused "名称")))
(defun etaf-ui-gui-mouse (label)
  (let* ((ref (or (etaf-ui-gui-control label) (error "Missing mouse target %s" label)))
         (position (etaf-host-ref-position (etaf-ui-gui-runtime) ref)))
    (redisplay t)
    (let ((data (posn-at-point position (selected-window))))
      (etaf-ui-gui-expect (and data (pos-visible-in-window-p position)) "Mouse target offscreen")
      (execute-kbd-macro (vector (list 'down-mouse-1 data) (list 'mouse-1 data))))))

(defun etaf-ui-gui-next-step ()
  (when etaf-ui-gui-steps
    (let* ((step (pop etaf-ui-gui-steps))
           (label (car step)))
      (condition-case problem
          (progn
            (etaf-ui-gui-expect
             (and (not (active-minibuffer-window))
                  (equal (buffer-name (window-buffer (selected-window))) "*ETAF UI Surfaces*"))
             "Selected window drifted or another minibuffer is active")
            (with-current-buffer "*ETAF UI Surfaces*"
              (let ((command-errors nil) (etaf-ui-gui-expected-quit nil))
                (let ((command-error-function
                       (lambda (data _context _caller) (push data command-errors))))
                  (funcall (cdr step)))
                (etaf-ui-gui-expect
                 (or (not command-errors)
                     (and etaf-ui-gui-expected-quit
                          (= (length command-errors) 1)
                          (memq 'quit (get (caar command-errors) 'error-conditions))))
                 "Native command errors: %S" command-errors))
              (redisplay t))
            (push (list label 'passed) etaf-ui-gui-interactions)
            (if etaf-ui-gui-steps (run-at-time 0.15 nil #'etaf-ui-gui-next-step)
              (push '(complete passed) etaf-ui-gui-interactions)))
        ((error quit)
         (push (list label 'failed (error-message-string problem)) etaf-ui-gui-interactions)
         (setq etaf-ui-gui-steps nil))))))

;;;###autoload
(defun etaf-ui-gui-interactions-start ()
  "Run the example's interaction sequence in the existing graphical frame."
  (unless (display-graphic-p) (user-error "GUI checks require a graphical Emacs frame"))
  (when (active-minibuffer-window) (user-error "Finish the active minibuffer before GUI checks"))
  (when-let* ((runtime (etaf-runtime-for-buffer "*ETAF UI Surfaces*")))
    (etaf-unmount runtime))
  (setq etaf-ui-gui-interactions nil
        etaf-ui-gui-steps
        (list
         (cons "mount" (lambda ()
                         (etaf-ui-surfaces-open)
                         (setq etaf-ui-gui-original-keys
                               (mapcar (lambda (key) (key-binding (kbd key))) '("<escape>" "C-g")))
                         (etaf-ui-gui-text "准备就绪")))
         (cons "dropdown-keyboard-open" (lambda () (etaf-ui-gui-press "操作") (etaf-ui-gui-focused "编辑偏好")))
         (cons "dropdown-down" (lambda () (etaf-ui-gui-key "<down>") (etaf-ui-gui-focused "复制工作空间")))
         (cons "dropdown-skip-disabled-wrap" (lambda () (etaf-ui-gui-key "TAB") (etaf-ui-gui-focused "编辑偏好")))
         (cons "dropdown-backtab" (lambda () (etaf-ui-gui-key "<backtab>") (etaf-ui-gui-focused "复制工作空间")))
         (cons "dropdown-up" (lambda () (etaf-ui-gui-key "<up>") (etaf-ui-gui-focused "编辑偏好")))
         (cons "dropdown-select" (lambda () (etaf-ui-gui-press "复制工作空间") (etaf-ui-gui-text "已复制工作空间") (etaf-ui-gui-visible "编辑偏好" nil) (etaf-ui-gui-focused "操作")))
         (cons "dropdown-escape" (lambda () (etaf-ui-gui-press "操作") (etaf-ui-gui-key "<escape>") (etaf-ui-gui-visible "编辑偏好" nil) (etaf-ui-gui-focused "操作")))
         (cons "dropdown-c-g" (lambda () (etaf-ui-gui-press "操作") (etaf-ui-gui-key "C-g") (etaf-ui-gui-visible "编辑偏好" nil) (etaf-ui-gui-focused "操作")))
         (cons "menu-dialog-handoff" (lambda () (etaf-ui-gui-press "操作") (etaf-ui-gui-key "RET") (etaf-ui-gui-visible "编辑偏好" nil) (etaf-ui-gui-focused "名称")))
         (cons "native-chinese-input" (lambda () (etaf-ui-gui-input "中文交互验收") (etaf-ui-gui-text "中文交互验收")))
         (cons "native-input-cancel" (lambda () (etaf-ui-gui-input "未提交草稿" t) (etaf-ui-gui-text "中文交互验收") (etaf-ui-gui-expect (not (string-match-p "未提交草稿" (buffer-string))) "Cancelled draft published")))
         (cons "dialog-checkbox" (lambda () (etaf-ui-gui-press "接收通知") (etaf-ui-gui-text "☐ 接收通知")))
         (cons "dialog-focus-cycle" (lambda () (etaf-ui-gui-tab-to "关闭") (etaf-ui-gui-key "TAB") (etaf-ui-gui-focused "名称") (etaf-ui-gui-key "<backtab>") (etaf-ui-gui-focused "关闭")))
         (cons "dialog-close-return-menu-trigger" (lambda () (etaf-ui-gui-key "RET") (etaf-ui-gui-visible "名称" nil) (etaf-ui-gui-focused "操作") (etaf-ui-gui-text "通知已关闭")))
         (cons "dialog-direct-open-complete" (lambda () (etaf-ui-gui-press "偏好设置") (etaf-ui-gui-press "完成") (etaf-ui-gui-visible "名称" nil) (etaf-ui-gui-focused "偏好设置") (etaf-ui-gui-text "偏好已更新")))
         (cons "dialog-escape" (lambda () (etaf-ui-gui-press "偏好设置") (etaf-ui-gui-key "<escape>") (etaf-ui-gui-focused "偏好设置")))
         (cons "dialog-c-g" (lambda () (etaf-ui-gui-press "偏好设置") (etaf-ui-gui-key "C-g") (etaf-ui-gui-focused "偏好设置")))
         (cons "help-open-close" (lambda () (etaf-ui-gui-press "帮助") (etaf-ui-gui-focused "知道了") (etaf-ui-gui-key "RET") (etaf-ui-gui-visible "知道了" nil) (etaf-ui-gui-focused "帮助")))
         (cons "help-escape" (lambda () (etaf-ui-gui-press "帮助") (etaf-ui-gui-key "<escape>") (etaf-ui-gui-focused "帮助")))
         (cons "mouse-dropdown-open" (lambda () (etaf-ui-gui-mouse "操作") (etaf-ui-gui-visible "编辑偏好" t)))
         (cons "mouse-disabled-item" (lambda () (etaf-ui-gui-mouse "删除（不可用）") (etaf-ui-gui-visible "编辑偏好" t)))
         (cons "mouse-menu-dialog" (lambda () (etaf-ui-gui-mouse "编辑偏好") (etaf-ui-gui-focused "名称")))
         (cons "mouse-checkbox" (lambda () (etaf-ui-gui-mouse "接收通知") (etaf-ui-gui-text "☑ 接收通知")))
         (cons "mouse-dialog-close" (lambda () (etaf-ui-gui-mouse "关闭") (etaf-ui-gui-visible "名称" nil) (etaf-ui-gui-focused "操作")))
         (cons "mouse-help" (lambda () (etaf-ui-gui-mouse "帮助") (etaf-ui-gui-mouse "知道了") (etaf-ui-gui-focused "帮助")))
         (cons "shortcuts-restored" (lambda () (etaf-ui-gui-expect (equal etaf-ui-gui-original-keys (mapcar (lambda (key) (key-binding (kbd key))) '("<escape>" "C-g"))) "Dismissal keys leaked")))
         (cons "unmount-with-open-dialog" (lambda () (etaf-ui-gui-press "偏好设置") (etaf-unmount (etaf-ui-gui-runtime)) (etaf-ui-gui-expect (not (etaf-runtime-for-buffer (current-buffer))) "Runtime survived unmount")))
         (cons "remount-interaction" (lambda () (etaf-ui-surfaces-open) (etaf-ui-gui-press "操作") (etaf-ui-gui-key "<escape>") (etaf-ui-gui-focused "操作") (etaf-ui-gui-text "准备就绪")))))
  (switch-to-buffer (get-buffer-create "*ETAF UI Surfaces*"))
  (run-at-time 0.1 nil #'etaf-ui-gui-next-step)
  'scheduled)
