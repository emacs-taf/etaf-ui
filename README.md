# etaf-ui

Source layout: runtime code lives in `lisp/`; add that directory to `load-path`
when using a checkout. Update older checkout configurations from the repository
root to its `lisp/` subdirectory.

`etaf-ui` is the official ETAF Component catalog. It is a normal optional package above `etaf`; it does not add a second Control or Widget model. Button, Checkbox, Label, Panel, and DataGrid are all ordinary Components with the same View, props, slots, events, and Data contracts.


Use the exact registered names `etaf-panel`, `etaf-label`, `etaf-button`, and
`etaf-checkbox` in every View. Evaluate this complete example in a lexical-binding
`.el` file, then switch to `*etaf-preferences*` to use its controls.

<!-- etaf-example: preferences -->
```elisp
;;; -*- lexical-binding: t; -*-
(require 'etaf-ui)

(etaf-define-component demo-preferences ()
  :setup (list (etaf-ref nil) (etaf-ref "Unsaved"))
  :render
  (let* ((state (etaf-state))
         (done (car state))
         (saved (cadr state)))
    (etaf-view
     (etaf-panel :title "Account"
       (slot :name 'header
         (etaf-button :label "Save" :ref 'save-button
                      :on-press (lambda ()
                                  (setf (etaf-value saved) "Saved"))))
       (etaf-label :text (etaf-value saved))
       (etaf-checkbox :checked (etaf-value done) :label "Done"
                      :ref 'done-checkbox
                      :on-change (lambda (next)
                                   (setf (etaf-value done) next)))
       (text (expr (if (etaf-value done) "Complete" "Pending")))))))

(etaf-mount "*etaf-preferences*" (etaf-view (demo-preferences)))
```

[Complete usage and interface contracts](docs/manual.md).

## Development

After cloning, run `make setup-hooks`. Before submitting a change, run `make check`; `make structure-check` is the fast organization gate. The shared rules are in [AGENTS.md](AGENTS.md).

`make check` runs structure checks, compilation and the public acceptance scenarios listed in [tests/acceptance.json](tests/acceptance.json). `make test` runs the broader regression suite; GUI and performance checks remain explicit targets. The acceptance inventory is selected by user-visible contracts, not by current pass/fail status.
