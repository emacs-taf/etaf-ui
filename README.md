# etaf-ui

Source layout: add the repository root to `load-path` and use
`(require 'etaf-ui)`. The supported API and usage notes are in
[`etaf-ui.el`](etaf-ui.el); implementation modules live in `lisp/`.

`etaf-ui` is the official ETAF Component catalog. It is a normal optional package above `etaf`; it does not add a second Control or Widget model. Button, Checkbox, Label, Panel, and DataGrid are all ordinary Components with the same View, props, slots, events, and Data contracts.


Use the exact registered names `etaf-panel`, `etaf-label`, `etaf-button`, and
`etaf-checkbox` in every View. Evaluate this complete example in a lexical-binding
`.el` file, then switch to `*etaf-preferences*` to use its controls.

<!-- etaf-example: preferences -->
```elisp
;;; -*- lexical-binding: t; -*-
(require 'etaf-ui)

(etaf-define-component demo-preferences ()
  :bindings ((done (etaf-ref nil))
             (saved (etaf-ref "Unsaved"))
             (rows (etaf-ref 3)))
  :view
  (etaf-panel :title "Account"
    (slot :name 'header
      (etaf-button :label "Save" :ref 'save-button
                   :on-press (lambda () (setf (etaf-value saved) "Saved"))))
    (etaf-label :text (etaf-value saved))
    (etaf-checkbox :bind done :label "Done" :ref 'done-checkbox)
    (etaf-number-input :bind rows :label "Rows" :ref 'rows-input :min 1 :max 10)
    (text (expr (if (etaf-value done) "Complete" "Pending")))))

(etaf-mount "*etaf-preferences*" (etaf-view (demo-preferences)))
```

[Complete usage and interface contracts](docs/manual.md).

For a complete modern composition, run `M-x etaf-ui-gallery-open` to inspect
the maintained Atelier workspace. It combines the catalog's layout, feedback,
navigation, input, data and floating Components in one caller-owned flow.

For in-buffer floating UI, compose `etaf-popover`, `etaf-dropdown-menu` and
`etaf-dialog` with ordinary controls and slots. Run `M-x etaf-ui-surfaces-open`
for the [menu and preferences example](examples/etaf-ui-surfaces.el).
Placement and occlusion come from Ebox; panel navigation uses its shared focus.
Run `make gui-check` against the existing graphical Emacs server for the
maintained keyboard/mouse interaction workflow.
Use `make gui-check GUI_EXAMPLE=gallery` for the integrated Gallery workflow,
including drawer handoff, Chinese input, controlled selection and pagination.

Run `make perf-check PERF_ARGS='--diagnose'` from the development
workspace to measure the existing graphical Emacs. The shared runner uses the
registered Gallery callback, keyboard and mouse scenarios, with three sets of
ten samples and separate phase, CPU and allocation passes. Budgets remain
50 ms for the checkbox, 100 ms for floating UI and a separate 500 ms hard limit.
`PERF_TOOL=/path/to/workspace/scripts/performance.py` selects the same tool for
a separate checkout. The workspace's `docs/manual.md` documents baseline
comparison, source freshness and evidence boundaries.

Gallery Review has separate first-click and repeated-toggle workloads.
`gallery.review.callback` and `gallery.review.mouse` mount a fresh page for each
sample; `gallery.review.steady.callback` and `gallery.review.steady.mouse` retain
one page within each set and alternate checked/unchecked values. Use both when
checking updates: a fast first click does not establish steady interaction cost.

## Development

After cloning, run `make setup-hooks`. Before submitting a change, run `make check`; `make structure-check` is the fast organization gate.

`make check` runs structure checks, compilation and the public acceptance scenarios listed in [tests/acceptance.json](tests/acceptance.json). `make test` runs the same public API suite. The inventory covers every maintained Lisp test. GUI and performance checks use separate targets.

## Source layout

Add the repository root to `load-path` and require `etaf-ui`. The root entry
loads the implementation in `lisp/` and documents the supported public APIs in
its Commentary. Package archives include both the root entry and `lisp/`.
