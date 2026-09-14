;;; etaf-ui.el --- Official ETAF Component catalog -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Author: ETAF contributors
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (etaf "0.2.1"))
;; URL: https://github.com/ginqi7/etaf-ui

;;; Commentary:

;; Public API
;;
;; Load this package with (require 'etaf-ui) after adding the repository
;; root to load-path.
;; Only the interfaces listed below are supported for use by other packages.
;; All unlisted symbols and implementation features are internal, including
;; names without a double hyphen. Do not require files below lisp/ from consumers.
;; This Commentary is the authoritative export list; implementations and precise
;; docstrings remain beside their definitions. The manual contains workflows.
;;
;; Component: etaf-button (&key label on-press disabled ref class color bgcolor border padding font-weight tab-index aria-label use variant)
;; Render a standard pressable Button with a committed callback.
;;
;; DISABLED removes the callback and default focus tab index.  Presentation props
;; remain caller-overridable.  Runtime publishes ON-PRESS with the visible Button,
;; so a failed render keeps the previous callback and its captured values.
;; Use inside (etaf-view (etaf-button ...)); keyword arguments are component props.
;;
;; Component: etaf-checkbox (&key checked label on-change disabled bind)
;; Render a controlled Checkbox whose next value is sent to ON-CHANGE.
;; Alternatively, pass an existing writable ref as :bind; its current value
;; supplies CHECKED and the next boolean is written to the same ref.  Non-nil
;; BIND rejects explicitly supplied CHECKED or ON-CHANGE, including nil, with
;; `etaf-view-error'.  Nil BIND leaves the explicit controlled interface active.
;; No additional state is created. External ref writes update the control;
;; disabled activation cannot write. :on-press remains an additive observer.
;; Failed publication retains the old binding target, and unmount releases
;; the control's handlers and subscriptions without owning the caller's ref.
;; Use inside (etaf-view (etaf-checkbox ...)); keyword arguments are component props.
;;
;; Component: etaf-data-grid (&key controller columns row-key on-row-press row-ref row-selected-p loading-label error-label empty-label)
;; Render DATA CONTROLLER state through the public Component DSL.
;;
;; DataGrid owns loading, error, empty, and controller-selection adaptation.
;; Its keyed Range retains row identity across insert, reorder, and update.
;; Setup state owns per-instance fallback refs plus commit-staged stable row
;; actions; failed candidates cannot mutate committed handler inputs.  COLUMNS
;; use Table's unique keys and optional `:cell' row-to-View functions.
;; Use inside (etaf-view (etaf-data-grid ...)); keyword arguments are component props.
;;
;; Component: etaf-label (&key text variant)
;; Render TEXT as a semantic Label.
;; Use inside (etaf-view (etaf-label ...)); keyword arguments are component props.
;;
;; Component: etaf-number-input (&key value label on-change disabled min max bind)
;; Render a controlled minibuffer-backed NumberInput using Button.
;; Alternatively, :bind accepts an existing writable ref and replaces VALUE
;; plus ON-CHANGE. It uses the same conflict, ownership and publication rules
;; as Checkbox. Min/max and integer validation run before writing the ref;
;; canceling the native prompt leaves the value unchanged. Custom business
;; validation or transformation uses the explicit VALUE/ON-CHANGE interface.
;; Use inside (etaf-view (etaf-number-input ...)); keyword arguments are component props.
;;
;; Component: etaf-pagination (&key controller previous-ref next-ref previous-label next-label class color bgcolor border padding aria-label)
;; Render a controlled pager whose callbacks follow its committed CONTROLLER.
;; PREVIOUS-LABEL and NEXT-LABEL override the complete Button captions.
;; Each Button captures its render's Controller; Runtime publishes that callback
;; together with the visible control after a successful render.
;; Use inside (etaf-view (etaf-pagination ...)); keyword arguments are component props.
;;
;; Component: etaf-panel (&key title variant)
;; Render a titled Panel with named header and default slots.
;; Use inside (etaf-view (etaf-panel ...)); keyword arguments are component props.
;;
;; Component: etaf-table (&key columns rows row-key row-ref on-row-press row-selected-p)
;; Render ordinary ROWS as a presentational Table.
;;
;; COLUMNS contain a unique non-nil `:key', optional `:label', `:width',
;; and `:cell' function accepting one row and returning ordinary View content.
;; Integer widths are character capacities; `(fr N)' shares the remaining width
;; by positive weight N.
;; Without `:cell', the key reads a text field from the row.  Cell state belongs
;; in a returned Component, whose Context comes from the consuming Table.
;; ROW-KEY supplies stable identity.  ROW-REF is only needed for caller-owned
;; addresses; interactive rows otherwise receive instance-local references.
;; Interaction and selection are controlled optional inputs; Table never owns
;; application or Data Controller state.
;; Use inside (etaf-view (etaf-table ...)); keyword arguments are component props.
;;

;;; Code:

;;;###autoload
(eval-and-compile
  (add-to-list 'load-path
               (expand-file-name "lisp"
                                 (file-name-directory
                                  (or load-file-name
                                      (bound-and-true-p byte-compile-current-file)
                                      buffer-file-name)))))

(require 'etaf-ui-basic)
(require 'etaf-ui-table)
(require 'etaf-ui-data)

(provide 'etaf-ui)
;;; etaf-ui.el ends here
