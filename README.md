# etaf-ui

`etaf-ui` is the official ETAF Component catalog. It is a normal optional package above `etaf`; it does not add a second Control or Widget model. Button, Checkbox, Label, Panel, and DataGrid are all ordinary Components with the same View, props, slots, events, and Data contracts.

```elisp
(require 'etaf-ui)

(let ((done (etaf-ref nil)))
  (etaf-view
   (panel :title "Account"
    (slot :name 'header
          (button :label "Save" :ref 'save-button
                  :on-press (lambda () (message "saved"))))
    (label :text "Preferences")
    (checkbox :checked (etaf-value done) :label "Done"
              :ref 'done-checkbox
              :on-change (lambda (next)
                           (setf (etaf-value done) next))))))
```

In `.etaf` files use the short registered tags (`panel`, `label`, `button`,
`checkbox`, and `data-grid`) for structure.  The companion `.el` file owns
reactive values, Actions, Behaviors, and callbacks; keep the `etaf-view` tree
made from those same short tags.  Canonical `etaf-*` names remain the Elisp
definition and API names.

Button and Checkbox are controlled Components. `etaf-button` accepts `:label`,
`:on-press`, `:disabled`, `:ref`, and the small presentation set
`:class`, `:color`, `:bgcolor`, `:border`, `:padding`, `:face`, `:tab-index`,
and `:aria-label`, plus `:use` for a public Behavior list. An enabled button
defaults to role `button` and tab index `0`; a disabled button keeps its label
and disabled styling but has no press handler, Behavior, or tab stop.
`etaf-checkbox` accepts `:checked`, `:label`,
`:on-change`, `:disabled`, `:ref`, and the same presentation props. It exposes
role `checkbox`, a stable `:ref`, and tab index `0` while enabled. Its
`:on-change` receives the next boolean value; disabled checkboxes have no
handler or tab stop.

Component `:styles` declarations own default appearance. A non-nil
presentation prop supplied by the caller wins; an omitted or nil prop leaves
the inherited Theme/default style available. Button has the deliberately small
`primary`, `secondary`, and `ghost` visual vocabulary; it is a visual variant
set, not a second widget taxonomy.

Enabled buttons and checkboxes expose the same interaction affordances: a hand
pointer, native `mouse-face` hover feedback, a readable `help-echo`, a numeric
tab stop, and a semantic role. Hover ends when the pointer leaves; activation
does not create retained visual state. Disabled controls retain their text and disabled appearance but expose
no callback, pointer activation, or tab stop. The Runtime owns composition of
an explicit `:on-*` callback with a Behavior callback; the UI package only
declares the control and its visual state.

Spacing is owned by the parent layout, not by Button. Put adjacent controls in
a `row`/`flex` with an explicit horizontal `:gap`; this keeps each control's
mouse-face and hit range semantically separate.

`etaf-label` accepts `:text`, `:face`, `:class`, `:color`, `:bgcolor`, `:width`,
`:border`, `:padding`, and `:ref`. `etaf-panel` accepts `:title`, the same
surface presentation props, and projects the named `header` slot plus the
default slot.

DataGrid accepts column descriptors, a function-valued `:row-key`, and the
optional `:loading-label`, `:error-label`, `:empty-label`, `:selected-key`, or
function-valued `:row-selected-p`. When `:on-row-press` is supplied, every
row is an interactive button: `:row-ref` is required, must return a non-nil
stable Host reference for each row, and the row receives role `button` and
tab index `0`. `:on-row-press` receives the row. Without `:on-row-press`, rows
have no callback or tab stop. `:row-key` remains a required non-nil stable
scalar identity for retained rows. DataGrid retains one action closure per
row key, so selection or data Range updates do not recreate handlers for
unchanged rows.
An integer column `:width` is readable character capacity, not a raw pixel
value. DataGrid passes Ebox's native character unit through and reserves one
native character between non-final tracks.

`etaf-pagination` is a controlled Data Component. It accepts a Data controller
plus stable `:previous-ref` and `:next-ref` values, renders readable `←`/`→`
controls and a `Page N / M` summary, and disables the boundary action while a
page is loading or already at the first/last page. It owns no page state and
uses the same Button interaction contract.

Keyboard focus uses ETAF's public runtime ports: call
`(etaf-focus-next runtime)` to move through visible Hosts with a numeric
non-negative `:tab-index`, and dispatch through
`(etaf-dispatch-event runtime ref 'press)` when an action must be invoked by
code. Disabled controls and non-interactive DataGrid rows are omitted from
that tab order.

Run `make check EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs` from this directory.
