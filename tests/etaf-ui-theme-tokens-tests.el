;;; -*- lexical-binding: t; -*-
;;; etaf-ui-theme-tokens-tests.el --- Application palette to catalog tokens

(require 'ert)
(require 'etaf-ui)

(ert-deftest etaf-ui-theme-tokens-maps-palette-roles ()
  "Each supplied role becomes every catalog token that names it."
  (let ((tokens (etaf-ui-theme-tokens
                 '(:bg "#FAFAF7" :fg "#1D2B36" :panel "#FFFFFF" :track "#DCE4EA"
                   :border "#D5DEE6" :muted "#6C7E8C" :dim "#9AAAB6"
                   :accent "#0E7C7B" :accent-fg "#F0FFFF" :accent-soft "#DCEFEF"
                   :danger "#A93B4A" :info "#2C5F86"))))
    (dolist (expected '((:ui-bg . "#FAFAF7") (:ui-fg . "#1D2B36")
                        (:ui-window-bg . "#FAFAF7") (:ui-panel-fg . "#1D2B36")
                        (:ui-panel-bg . "#FFFFFF") (:ui-shell-bg . "#FFFFFF")
                        (:ui-disabled-bg . "#FFFFFF") (:ui-progress-track . "#DCE4EA")
                        (:ui-range-track . "#DCE4EA") (:ui-border . "#D5DEE6")
                        (:ui-divider-bg . "#D5DEE6") (:ui-table-border . "#D5DEE6")
                        (:ui-muted-fg . "#6C7E8C") (:ui-button-ghost-fg . "#6C7E8C")
                        (:ui-disabled-fg . "#9AAAB6")
                        (:ui-checkbox-disabled-fg . "#9AAAB6")
                        (:ui-accent . "#0E7C7B") (:ui-button-primary-bg . "#0E7C7B")
                        (:ui-table-selected-fg . "#0E7C7B")
                        (:ui-accent-fg . "#F0FFFF") (:ui-button-primary-fg . "#F0FFFF")
                        (:ui-accent-soft-bg . "#DCEFEF")
                        (:ui-table-selected-bg . "#DCEFEF")
                        (:ui-danger-fg . "#A93B4A") (:ui-data-grid-error-fg . "#A93B4A")
                        (:ui-info-fg . "#2C5F86")))
      (should (equal (cons (car expected) (plist-get tokens (car expected)))
                     expected)))))

(ert-deftest etaf-ui-theme-tokens-derives-omitted-roles ()
  "Omitted roles derive from the surface, the text and the background's lightness."
  (let ((light (etaf-ui-theme-tokens '(:bg "#FFFFFF" :fg "#000000")))
        (dark (etaf-ui-theme-tokens '(:bg "#000000" :fg "#FFFFFF" :accent "#FF0000"))))
    (should (equal (plist-get light :ui-panel-bg) "#FFFFFF"))
    (should (equal (plist-get light :ui-border) "#D1D1D1"))
    (should (equal (plist-get light :ui-muted-fg) "#595959"))
    (should (equal (plist-get light :ui-disabled-fg) "#595959"))
    (should (equal (plist-get light :ui-accent) "#000000"))
    (should (equal (plist-get light :ui-accent-fg) "#FFFFFF"))
    (should (equal (plist-get light :ui-success-fg) "#1A7F37"))
    (should (equal (plist-get light :ui-success-bg) "#E4F0E7"))
    (should (equal (plist-get dark :ui-success-fg) "#3FB950"))
    (should (equal (plist-get dark :ui-accent-soft-bg) "#290000"))
    (should (equal (plist-get dark :ui-info-fg) "#FF0000"))
    (should (equal (plist-get dark :ui-info-border) "#590000"))))

(ert-deftest etaf-ui-theme-tokens-rejects-invalid-palettes ()
  "A palette without both base colors, with an unknown role or a non-string fails."
  (should-error (etaf-ui-theme-tokens '(:fg "#000000")) :type 'wrong-type-argument)
  (should-error (etaf-ui-theme-tokens '(:bg "#FFFFFF" :fg "#000000" :surface "#EEEEEE"))
                :type 'wrong-type-argument)
  (should-error (etaf-ui-theme-tokens '(:bg "#FFFFFF" :fg 0)) :type 'wrong-type-argument)
  (should-error (etaf-ui-theme-tokens '(:bg "#FFFFFF" :fg)) :type 'wrong-type-argument))

(etaf-define-component etaf-ui-theme-tokens-test--form (&key theme)
  "A form whose catalog controls follow THEME."
  :setup (etaf-theme-provide theme)
  :view
  (column :width '(ch 40)
    (etaf-text-input :ref 'field :value "Draft" :hide-label t :width '(ch 24))))

(ert-deftest etaf-ui-theme-tokens-paint-catalog-components ()
  "Provided palette tokens paint catalog controls, and a key placed first wins."
  (let ((buffer (generate-new-buffer " *theme tokens test*"))
        (theme (etaf-ref (etaf-ui-theme-tokens
                          '(:bg "#101925" :fg "#E5EDF7" :panel "#182334"
                            :border "#67788E")))))
    (unwind-protect
        (let (runtime)
          (etaf-mount buffer
                      (etaf-view (etaf-ui-theme-tokens-test--form :theme theme))
                      '(:viewport-width 600 :viewport-height 20))
          (setq runtime (etaf-runtime-for-buffer buffer))
          (let ((field (etaf-runtime-host-props-for runtime 'field)))
            (should (equal (plist-get field :background-color) "#182334"))
            (should (equal (plist-get field :border) '((px 1) solid "#67788E"))))
          (etaf-set-value theme (append '(:ui-panel-bg "#203048") (etaf-value theme)))
          (let ((field (etaf-runtime-host-props-for runtime 'field)))
            (should (equal (plist-get field :background-color) "#203048"))))
      (when-let* ((mounted (etaf-runtime-for-buffer buffer)))
        (etaf-unmount mounted))
      (kill-buffer buffer))))

(provide 'etaf-ui-theme-tokens-tests)
;;; etaf-ui-theme-tokens-tests.el ends here
