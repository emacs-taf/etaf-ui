;;; etaf-ui-style.el --- Internal styling for ETAF UI Components -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Private catalog styling.  ETAF owns Theme; this module only supplies
;; fallback values for the semantic tokens consumed by official Components.

;;; Code:

(require 'cl-lib)
(require 'etaf)

(defvar etaf-ui--component-definition-signatures
  (make-hash-table :test #'eq)
  "Exact catalog definitions already installed in the current process.")

(defmacro etaf-ui--define-component (name arguments &rest clauses)
  "Define catalog Component NAME once for exact ARGUMENTS and CLAUSES.

`package.el' may reload dependency files after byte compilation.  Identical
catalog definitions are idempotent across that reload, while a changed
definition still reaches `etaf-define-component' and therefore requires the
public `etaf-component-redefine-run' boundary."
  (declare (indent 2) (debug defun))
  (let ((signature
         (secure-hash 'sha256
                      (prin1-to-string (list name arguments clauses)))))
    `(unless (equal
              (gethash ',name etaf-ui--component-definition-signatures)
              ,signature)
       (prog1
           (etaf-define-component ,name ,arguments ,@clauses)
         (puthash ',name ,signature
                  etaf-ui--component-definition-signatures)))))

(defconst etaf-ui--style-palette
  '(:ui-fg "#252A2E"
    :ui-bg "#FFFDF8"
    :ui-border "#687386"
    :ui-muted-fg "#526174"
    :ui-danger-fg "#FF6B6B"
    :ui-success-fg "#2F6B43"
    :ui-disabled-fg "#687386"
    :ui-disabled-bg "#E5E7EB"
    :ui-disabled-border "#9CA3AF"
    :ui-button-primary-fg "#FFFFFF"
    :ui-button-primary-bg "#2F6B43"
    :ui-button-primary-border "#2F6B43"
    :ui-button-secondary-fg "#142235"
    :ui-button-secondary-bg "#D9EEEA"
    :ui-button-secondary-border "#2E8B83"
    :ui-button-ghost-fg "#142235"
    :ui-button-ghost-bg "#FFFDF8"
    :ui-button-ghost-border "#C8C1B6"
    :ui-checkbox-enabled-fg "#252A2E"
    :ui-checkbox-enabled-bg "#DCEBDD"
    :ui-checkbox-enabled-border "#6D8A73"
    :ui-checkbox-disabled-fg "#6B7280"
    :ui-checkbox-disabled-bg "#EEEAE2"
    :ui-checkbox-disabled-border "#9CA3AF"
    :ui-table-border "#687386"
    :ui-table-selected-fg "#2F6B43"
    :ui-table-selected-bg "#DCEBDD"
    :ui-data-grid-error-fg "#FF6B6B"
    :ui-pagination-muted-fg "#526174"
    :ui-panel-fg "#252A2E"
    :ui-panel-bg "#FFFDF8"
    :ui-panel-border "#687386")
  "Fallback values for semantic tokens used by ETAF UI Components.")

(defun etaf-ui--style-tokens (&rest keys)
  "Return deferred ETAF Theme values for private catalog token KEYS."
  (let (result)
    (dolist (key keys result)
      (setq result
            (plist-put
             result key
             (etaf-theme-token key (plist-get etaf-ui--style-palette key)))))))

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
