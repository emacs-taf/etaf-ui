;;; etaf-ui-style.el --- Internal styling for ETAF UI Components -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Private catalog styling.  ETAF owns Theme; this module only supplies
;; fallback values for the semantic tokens consumed by official Components.

;;; Code:

(require 'cl-lib)
(require 'etaf)

(defconst etaf-ui--style-palette
  '(:ui-fg "#252A2E"
    :ui-bg "#FFFDF8"
    :ui-border "#687386"
    :ui-muted-fg "#526174"
    :ui-danger-fg "#FF6B6B"
    :ui-success-fg "#2F6B43"
    :ui-success-bg "#DCEBDD"
    :ui-success-border "#6D8A73"
    :ui-danger-bg "#FFF0F0"
    :ui-danger-border "#CF6A6A"
    :ui-warning-fg "#8A4B08"
    :ui-warning-bg "#FFF3D6"
    :ui-warning-border "#D99A2B"
    :ui-info-fg "#155E75"
    :ui-info-bg "#E0F2FE"
    :ui-info-border "#38A3C7"
    :ui-disabled-fg "#687386"
    :ui-disabled-bg "#E5E7EB"
    :ui-disabled-border "#9CA3AF"
    ;; Buttons and selection controls are tonal pills: primary fills the
    ;; accent, secondary and selected states use its soft tint.
    :ui-button-primary-fg "#FFFFFF"
    :ui-button-primary-bg "#2F6FE4"
    :ui-button-secondary-fg "#1F4FB0"
    :ui-button-secondary-bg "#DCE7FA"
    :ui-button-ghost-fg "#252A2E"
    :ui-checkbox-enabled-fg "#252A2E"
    :ui-checkbox-disabled-fg "#6B7280"
    :ui-table-border "#687386"
    :ui-table-selected-fg "#2F6B43"
    :ui-table-selected-bg "#DCEBDD"
    :ui-data-grid-error-fg "#FF6B6B"
    :ui-pagination-muted-fg "#526174"
    :ui-panel-fg "#252A2E"
    :ui-panel-bg "#FFFDF8"
    :ui-panel-border "#687386"
    :ui-playing-card-bg "#F7F4EC"
    :ui-playing-card-black "#253546"
    :ui-playing-card-red "#B73951"
    :ui-playing-card-back-bg "#315C76"
    :ui-playing-card-back-fg "#BFD8E5"
    :ui-playing-card-empty-bg "#E7EDF1"
    :ui-playing-card-empty-fg "#788B99"
    :ui-playing-card-selected-bg "#F6D994"
    :ui-playing-card-hover-bg "#FBE8B8"
    ;; Desktop surface tokens.  Bars, windows, dividers and pickers read
    ;; these so a Desktop Theme restyles the whole shell through paint slots.
    :ui-accent "#2F6FE4"
    :ui-accent-fg "#FFFFFF"
    :ui-accent-soft-bg "#DCE7FA"
    :ui-shell-bg "#E3E9F0"
    :ui-shell-fg "#16202C"
    :ui-shell-muted-fg "#66727F"
    :ui-shell-item-fg "#4A5664"
    :ui-shell-item-minimized-fg "#98A3AF"
    :ui-window-bg "#FFFFFF"
    :ui-window-fg "#16202C"
    :ui-window-border "#D6DEE7"
    :ui-window-title-bg "#F7F9FC"
    :ui-window-title-fg "#7B8794"
    :ui-window-title-active-fg "#16202C"
    :ui-divider-bg "#DCE3EB"
    :ui-search-bg "#EEF2F6"
    :ui-search-fg "#16202C"
    :ui-picker-item-bg "#F7F9FC"
    :ui-picker-item-fg "#16202C"
    :ui-picker-item-muted-fg "#66727F")
  "Fallback values for semantic tokens used by ETAF UI Components.")

(defun etaf-ui--style-tokens (&rest keys)
  "Return deferred ETAF Theme values for private catalog token KEYS."
  (let (result)
    (dolist (key keys result)
      (setq result
            (plist-put
             result key
             (etaf-theme-token key (plist-get etaf-ui--style-palette key)))))))

(defun etaf-ui--style-token (key)
  "Return the deferred ETAF Theme value for private catalog token KEY."
  (etaf-theme-token key (plist-get etaf-ui--style-palette key)))

(defun etaf-ui--style-border (value)
  "Return canonical border VALUE from a semantic ETAF Theme value."
  (cond
   ((etaf-theme-token-p value)
    (etaf-theme-token (nth 1 value) (nth 2 value)
                      #'etaf-ui--style-border))
   ((and (stringp value)
         (string-match-p "\\`#[[:xdigit:]]+\\'" value))
    (list '(px 1) 'solid value))
   (t value)))

(provide 'etaf-ui-style)
;;; etaf-ui-style.el ends here
