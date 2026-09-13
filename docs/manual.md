# etaf-ui Manual

[Installation and first example](../README.md).


Core does not automatically load `.etaf` files. The optional Playground reads
inert structural source and explicitly loads its registered Elisp companion;
that file format does not create shorter Component aliases. Local callbacks
need no named Action. Components receive props and slots through the same API
as application-defined Components.

Button and Checkbox are controlled Components. `etaf-button` accepts `:label`,
`:on-press`, `:disabled`, `:ref`, and the small presentation set
`:class`, `:color`, `:bgcolor`, `:border`, `:padding`, `:font-weight`, `:tab-index`,
and `:aria-label`, plus `:use` for a public Behavior list. An enabled button
defaults to role `button` and tab index `0`; a disabled button keeps its label
and disabled styling but has no press handler, Behavior, or tab stop.
`etaf-checkbox` accepts `:checked`, `:label`,
`:on-change`, `:disabled`, `:ref`, and the same presentation props. It exposes
role `checkbox`, a stable `:ref`, and tab index `0` while enabled. Its
`:on-change` receives the next boolean value; disabled checkboxes have no
handler or tab stop.

`etaf-number-input` is a small controlled input primitive for values edited
through Emacs's native minibuffer. It accepts `:value`, `:label`, `:on-change`,
`:min`, `:max`, `:ref`, and `:disabled`; the callback receives the validated
integer while the caller remains the owner of the ref.

The catalog uses one semantic Theme vocabulary for color roles. The main
tokens are `:ui-fg`, `:ui-bg`, `:ui-border`, `:ui-muted-fg`,
`:ui-disabled-*`, `:ui-button-primary-*`, `:ui-button-secondary-*`,
`:ui-button-ghost-*`, `:ui-checkbox-*`, `:ui-table-*`,
`:ui-data-grid-error-fg`, `:ui-pagination-muted-fg`, and `:ui-panel-*`.
Applications provide these through ETAF's
`etaf-theme-provide`; legacy `:ui-button-color`-style aliases remain accepted
for compatibility. `etaf-ui` does not depend on TP or on a renderer-specific
palette registry. If an application wants TP's light/dark palette data, the
optional `etaf-theme-tp` adapter converts it into the same ETAF Theme plist
before the UI catalog sees it.

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

The parent owns spacing: use `(row :item-gap 1 ...)` or
`(column :item-gap 1 ...)`; `flex` and `grid` use `:gap`. In particular, migrate
`row :gap` to `row :item-gap`. Keep an explicit gap between adjacent controls
so each has a separate hover and hit range.

Root event forwarding appends the business action, inner-to-outer wrapper
callbacks, then Behaviors in declaration order. For Checkbox, adding
`:on-press` does not replace its `:on-change` conversion. Errors stop the chain;
each declaration runs once. Wrapper `:use` lists concatenate and duplicate
Behavior names are rejected before installation.

Disabled inputs combine with OR; outer nil cannot enable an internally disabled
control. Disabled dispatch and focus signal `etaf-event-error`; disabled cell
controls block pointer activation from falling through to their parent row.
Disabled input Behaviors are not installed. A conflicting fallthrough `:role`
or owned aria state, such as `:aria-checked`, is an input error; accessible
`:aria-label` and `:aria-description` remain caller-overridable. See the
[interaction and migration rules](https://gitea.gklazycat.heiyu.space/geekinney/etaf/src/branch/main/docs/manual.md#interaction-migration)
for the complete contract.

`etaf-label` accepts `:text`, `:class`, `:color`, `:bgcolor`, `:font-weight`,
`:width`, `:border`, `:padding`, and `:ref`.
`etaf-panel` accepts `:title`, the same
surface presentation props, and projects the named `header` slot plus the
default slot.

<!-- M0b1: business-props -->
The public Component business props are derived from the definitions and kept
separate from forwarded Host attributes:

| Component | Business props |
| --- | --- |
| `etaf-label` | `:text`, `:variant` |
| `etaf-button` | `:label`, `:on-press`, `:disabled`, `:ref`, `:class`, `:color`, `:bgcolor`, `:border`, `:padding`, `:font-weight`, `:tab-index`, `:aria-label`, `:use`, `:variant` |
| `etaf-checkbox` | `:checked`, `:label`, `:on-change`, `:disabled` |
| `etaf-panel` | `:title`, `:variant` |
| `etaf-number-input` | `:value`, `:label`, `:on-change`, `:disabled`, `:min`, `:max` |
| `etaf-table` | `:columns`, `:rows`, `:row-key`, `:row-ref`, `:on-row-press`, `:row-selected-p` |
| `etaf-data-grid` | `:controller`, `:columns`, `:row-key`, `:on-row-press`, `:row-ref`, `:row-selected-p`, `:loading-label`, `:error-label`, `:empty-label` |
| `etaf-pagination` | `:controller`, `:previous-ref`, `:next-ref`, `:previous-label`, `:next-label`, `:class`, `:color`, `:bgcolor`, `:border`, `:padding`, `:aria-label` |

<!-- M0b1: single-host-root -->
Every public catalog Component mounts exactly one Host root. All valid Host
attributes that are not consumed as business props—such as `:ref`, `:class`,
and `:aria-label`—are forwarded to that root. This forwarding rule does not
make those attributes business props of every Component.

DataGrid accepts column descriptors, a function-valued `:row-key`, and the
optional `:loading-label`, `:error-label`, `:empty-label`, or function-valued
`:row-selected-p`. When `:on-row-press` is supplied, every row is an
interactive button with role `button` and tab index `0`; the callback receives
the row. Without `:on-row-press`, rows have no callback or tab stop.

Interactive `etaf-table` rows may also omit `:row-ref`; the framework supplies
stable references scoped to the retained Table instance. Supply refs only for
external focus, tests, or integration addresses; do not derive global symbols
from row labels. Row keys identify data; refs identify interactive Hosts.

<!-- M0b1: row-ref-optional -->
`:row-ref` is optional for DataGrid. When it is omitted on an interactive
grid, DataGrid derives a stable internal Host reference from the row identity
owned by the controller. Fallback refs are uninterned and scoped to each
retained DataGrid instance, so separate grids may share row identities without
colliding. When `:row-ref` is supplied, the callback owns that identity and
must return a non-nil stable Host reference for every row. `:row-key`
remains a required non-nil stable scalar identity for retained rows. DataGrid
retains one action closure per row key, so selection or Data Range updates do
not recreate handlers for unchanged rows.
An integer column `:width` is readable character capacity, not a raw pixel
value. DataGrid passes Ebox's native character unit through and reserves one
native character between non-final tracks. Use `:width '(fr 1)` to let a column
fill the remaining width; multiple fractional columns share that space by
their positive weights. For example, `(:key :title :width (fr 1))` next to
`(:key :actions :width 22 :cell render-actions)` lets the title adapt while
reserving room for the action controls. Headers and rows use the same tracks
and gap. Fractional cells clip to their allocation without widening neighboring
columns. Fixed tracks still reserve their declared space, so the containing
layout must provide enough width for those controls and gaps.

Changing a custom cell's column width between fixed and fractional values does
not replace its Component state. All-fixed text-only tables retain their compact
text rendering path.

### Custom cells and column migration

Table and DataGrid share the column contract. Every column needs a unique,
non-nil `:key` (symbol, integer, or string), including presentation-only columns.
The default cell reads that field as text. A `:cell` function receives one row
and returns nil, a string, a typed Host or Component View, or a proper sequence
of those values. Table owns cell width and clips overflow; text-only tables
keep their existing compact representation.

The example repeats the `:name` field with two distinct column keys and puts an
ordinary Button in a third column. Select the row or activate Open independently:

<!-- etaf-example: cells -->
```elisp
;;; -*- lexical-binding: t; -*-
(require 'etaf-ui)

(etaf-mount
 "*etaf-cell-demo*"
 (etaf-view
  (etaf-table
   :rows '((:id 1 :name "Ada"))
   :row-key (lambda (row) (plist-get row :id))
   :on-row-press (lambda (row) (message "Select %s" (plist-get row :name)))
   :columns
   (list
    '(:key :name :label "Name" :width 12)
    (list :key :name-upper :label "Uppercase" :width 12
          :cell (lambda (row) (upcase (plist-get row :name))))
    (list :key :open :label "Action" :width 10
          :cell
          (lambda (row)
            (etaf-view
             (etaf-button
              :label "Open"
              :on-press (lambda ()
                          (message "Open %s" (plist-get row :name)))))))))))
```

To migrate duplicate field columns, keep one `:key :name`, give the other a
unique key such as `:name-upper`, and use `:cell` to read the original `:name`
field. Missing or duplicate column keys are errors. Row and column keys retain
cell identity across reordering; changing a key replaces that cell instance.

Cell functions use their row argument and normal lexical captures. Their
Context is the consuming Table/Grid location; they do not recover the author's
props, `etaf-state`, or private styles. Return an ordinary Component when a
cell needs its own state, styles, or lifecycle, and create persistent refs and
watches in that Component's `:setup`. Capture an author's stable ref before
building a callback when sharing it is intentional. Do not create persistent
state on each cell-function call.

`etaf-pagination` is a controlled Data Component. It accepts a Data controller
plus stable `:previous-ref` and `:next-ref` values, renders padded secondary
Buttons (`‹ Previous` / `Next ›`) around a centered `Page N / M` and item-count
summary, and disables the boundary action while a
page is loading or already at the first/last page. It owns no page state and
uses the same Button interaction contract and Theme tokens. Narrow allocations
wrap the complete controls and summary. Optional `:previous-label` and
`:next-label` replace the complete captions, for example `"‹ 上一页"` and
`"下一页 ›"`; the stable English accessibility labels remain unchanged.

Keyboard focus uses ETAF's public runtime ports: call
`(etaf-focus-next runtime)` to move through visible Hosts with a numeric
non-negative `:tab-index`, and dispatch through
`(etaf-dispatch-event runtime ref 'press)` when an action must be invoked by
code. Disabled controls and non-interactive DataGrid rows are omitted from
that tab order.

Run `make check EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs` from this directory.
