# etaf-ui Manual

[Installation and first example](../README.md).

## Component catalog by responsibility

The catalog is organized by the job a component performs. This keeps the
public surface composable: a container arranges content, a feedback component
describes state, a floating component owns placement and dismissal, and an
input component changes caller-owned values. Every category uses the same ETAF
View, props, slots, lifecycle and Ebox host interaction contracts.

| Category | Components | Foundation owned by |
| --- | --- | --- |
| Layout and containers | `etaf-panel`, `etaf-card`, `etaf-divider` | Ebox flow/flex/grid geometry; ETAF controls which branch is visible |
| Controlled panels and windows | `etaf-resizable-panel`, `etaf-window-chrome`, `etaf-window` | Ebox positioned geometry and gestures; caller owns coordinates, mode and z-order |
| Desktop navigation and tiling | `etaf-taskbar`, `etaf-workspace-bar`, `etaf-launcher`, `etaf-switcher`, `etaf-splitter` | Ebox focus and Hosts; caller owns applications, windows and layout state |
| Feedback and status | `etaf-label`, `etaf-badge`, `etaf-tag`, `etaf-kbd`, `etaf-progress`, `etaf-alert`, `etaf-statistic`, `etaf-empty`, `etaf-skeleton` | Ebox text and box paint; caller owns the status value |
| Floating surfaces | `etaf-popover`, `etaf-tooltip`, `etaf-dropdown-menu`, `etaf-context-menu`, `etaf-toast`, `etaf-dialog`, `etaf-drawer` | Ebox anchor/layer/occlusion plus shared panel focus |
| Inputs and actions | `etaf-button`, `etaf-checkbox`, `etaf-input`, `etaf-radio`, `etaf-switch`, `etaf-segmented`, `etaf-slider`, `etaf-text-input`, `etaf-number-input`, `etaf-select`, `etaf-menu`, `etaf-pagination` | Ebox target/focus; ETAF owns controlled callbacks and values |
| Navigation and collections | `etaf-tabs`, `etaf-accordion`, `etaf-breadcrumb`, `etaf-steps`, `etaf-tree` | Ebox flow and focus; ETAF publishes caller-owned selection callbacks |
| Data presentation | `etaf-table`, `etaf-data-grid`, `etaf-pagination`, `etaf-list`, `etaf-avatar`, `etaf-timeline`, `etaf-calendar` | ETAF Data Controller and Ebox retained rows |
| Advanced composition | `etaf-date-picker`, `etaf-command-palette` | Shared input and Dialog/List composition; caller owns values and dismissal |

The maintained Atelier Gallery exercises every category in one compact workspace.
Run `M-x etaf-ui-gallery-open` to inspect it; the source is
[`examples/etaf-ui-gallery.el`](../examples/etaf-ui-gallery.el).
It is a composition check, not a separate widget framework: components must
remain useful independently and must not copy Ebox hit testing, focus or
layout state.

Library columns wrap with the available width and follow their own content heights.
`etaf-list` composes title and description through Button’s default slot, giving
each rich row one focus and activation target; do not nest interactive controls
inside that slot. Steps selection and tag removal remain caller-owned. The
Collection browser connects DataGrid and Pagination to one Data Controller. The
advanced panel adds a date picker, month calendar, nested tree and command palette
using the same public Component contracts.

Run `make gui-check GUI_EXAMPLE=gallery` through the existing emacsclient for
menu, drawer, Chinese input, selection, steps, tag removal, list and pagination
workflows. It exercises Emacs-local keyboard and mouse events; inspect the actual
render separately. It does not certify OS input-method behavior or latency.

The package's `make perf-check` includes all Gallery workloads. From the
workspace, a focused continuous interaction check is:

```sh
python3 scripts/performance.py run --mode gui --scenario 'gallery.review.steady.*'
```

The steady scenarios retain one mounted Gallery within each set and verify both
checked and unchecked progress values after every click. The original
`gallery.review.callback` and `gallery.review.mouse` scenarios measure the first
click on fresh mounts. Inspect per-sample results to distinguish directional
fallbacks from costs that accumulate over successive updates.

`gallery.actions.steady.*` and `gallery.more.steady.*` alternate open and closed
menus. `gallery.toolbar.sequence.mouse` interleaves both menus with Review on
one page, exposing updates that become expensive after another component runs.
To inspect the currently selected Gallery without resetting its state, select
`gallery.current.toolbar.mouse`. If the page came from the last benchmark,
first call `(taf-benchmark-detach-fixture)` through emacsclient; otherwise the
runner still owns that fixture's cleanup. The current-page adapter borrows it
and leaves it mounted. Its sequence is Actions twice, Review twice, More twice,
Review twice. Use these mixed operations for diagnosis; the separate Review and
menu workloads keep their respective 50 ms and 100 ms acceptance budgets.

## Choosing `:view` or `:render`

Both forms return the same typed ETAF View. Use `:view` as the normal authoring
form: its DSL describes the host tree and lets the compiler validate component
props, slots and child placement. Use `:render` when ordinary Elisp must first
compute a value, choose a branch, or produce a sequence of Views. Wrap the
resulting DSL in `etaf-view`; use `(expr FORM)` at a child position when FORM
returns a string, View, or proper sequence of Views.

```elisp
(etaf-define-component greeting-view (&key name)
  :view
  (row :item-gap '(ch 1)
    (text "Hello")
    (text (expr (format "%s!" name)))))

(etaf-define-component greeting-render (&key name items)
  :render
  (let ((caption (if name (format "Hello %s!" name) "Hello!")))
    (etaf-view
     (column
       (text (expr caption))
       (expr
        (mapcar (lambda (item)
                  (etaf-view (etaf-label :text item)))
                items))))))
```

The first definition is the preferred static template. The second keeps the
same DSL while using ordinary Elisp for a conditional and a list traversal;
`etaf-node` is only needed when a program must construct a View tree directly.
This is a compiler boundary, not a second rendering model: both definitions
participate in the same props, slots, retained identity and Ebox host lifecycle.

Use `etaf-input` when a form needs one shared field contract. Its `:type`
selects `text`, `password`, `email`, `url`, `number` or ISO `date`; `:bind` or
`value`/`on-change` remains the same for every type. `etaf-text-input` and
`etaf-number-input` remain readable convenience names for the common cases.

## Floating content and modal composition

Use `etaf-dropdown-menu` for a short in-buffer action list; `etaf-menu` remains
the native completion choice for searchable lists. Use `etaf-popover` for
arbitrary content anchored to a unique Host `:id`, and `etaf-dialog` for a
modal form or task. These components compose the same Button, inputs and
slots. Their supported props and lifecycle are listed in [the entry](../etaf-ui.el).

```elisp
;;; -*- lexical-binding: t; -*-
(require 'etaf-ui)
(etaf-define-component preferences-dialog ()
  :bindings ((open (etaf-ref nil)) (enabled (etaf-ref t)))
  :view
  (column :width 'stretch :height '(vh 90)
    (etaf-button :label "Preferences"
                 :on-press (lambda () (setf (etaf-value open) t)))
    (etaf-dialog :open open :title "Preferences"
                 :on-close (lambda () (setf (etaf-value open) nil))
      (etaf-checkbox :bind enabled :label "Notifications")
      (slot :name 'footer
        (etaf-button :label "Done"
                     :on-press (lambda () (setf (etaf-value open) nil)))))))
(etaf-mount "*Preferences*" (etaf-view (preferences-dialog)))
```

The root reserves the floating canvas; absolute panels do not grow normal
flow. Ebox places anchored panels, flips them when space allows, clips to that
canvas and resolves occlusion. A dialog's opaque backdrop blocks covered
controls. Floating content must use the canvas line height; alpha blending
and child frames are outside this rendering contract. A small canvas can clip
content, so reserve sufficient height and choose a width suitable for the app.

Opening focuses the first eligible control. Tab/Shift-Tab and Up/Down cycle
within the panel through ETAF's Ebox focus adapter; Escape/C-g call `on-close`.
The application accepts closing by changing `open`. A dropdown manages only
its own open state and calls `on-select` with an enabled item's key. Popovers
leave outside controls mouse-accessible; outside clicks do not dismiss them.
Dialog backdrops do not dismiss on click. Native Emacs commands remain
available, and this modal interaction policy is not an access-control boundary.

Closing or unmounting removes buffer-local shortcuts. Nested panels restore
the enclosing panel's shortcuts and a valid prior target; a menu handing off
to a dialog retains the original trigger as a return route. Ebox remains the
current-focus authority. A panel whose anchor is absent cannot intercept
keys. Slots retain their author's Context; form data stays in caller refs.
For drafts, keep separate draft and accepted values in the application and
apply them from the footer's save callback.

Run `M-x etaf-ui-surfaces-open` for the complete
[menu, help and preferences example](../examples/etaf-ui-surfaces.el). Reopening
resets its state. Closing its buffer or calling `etaf-unmount` disposes it.

To run the repeatable interaction check in the existing graphical Emacs server,
use `make gui-check EMACSCLIENT=/path/to/emacsclient`. It exercises keyboard and
mouse activation, disabled items, native Chinese input and cancellation, nested
focus return, modal closing, and unmount/remount cleanup. It leaves the example
visible; it does not certify screenshot quality or foreground input latency.

## Controlled panels and windows

`etaf-resizable-panel` is the low-level catalog shell for a positioned panel.
`x`, `y`, `width`, `height`, `z-index`, `visible`, and the min/max constraints
are passed to Ebox and may be ordinary values, refs, or computed values.  Set
`resizable` and `resize-edges` to expose edge/corner Hosts.  `on-move` receives
Ebox's drag gesture from the panel root; `on-resize` receives `(edge gesture)`
from a handle.  Callbacks update caller-owned geometry, for example through
`setf` on refs.  The Component does not retain coordinates or choose a layer.
`move-use` and `resize-use` accept caller-provided ETAF Behavior specs for the
title bar and individual edge handles; the corresponding callback props remain
available for one-off adapters.

`etaf-window-controls` is the reusable macOS-style traffic-light component.
Pass the same `group` to related instances to make Ebox update every hover
glyph in one incremental batch. `etaf-window-chrome` composes that component
with a centered title and controlled minimize,
maximize/restore, and close buttons.  The title bar forwards `on-move`
gestures; holding Shift for the initial title press enables Ebox's optional
locked-drag mode, where the first release keeps moving until the next click
or Escape.  Its action callbacks only request a state transition.  `etaf-window`
composes both Components and provides `header`, `actions`, `default`, and
`footer` slots:

```elisp
(etaf-define-component inspector-window ()
  :bindings ((x (etaf-ref '(ch 6))) (y (etaf-ref '(lh 2)))
             (width (etaf-ref '(ch 42))) (height (etaf-ref '(lh 14)))
             (mode (etaf-ref 'normal)))
  :view
  (etaf-window :title "Inspector" :x x :y y :width width :height height
               :mode mode
               :on-move (lambda (_gesture) (ignore x y))
               :on-resize (lambda (_edge _gesture) (ignore x y width height))
               :on-maximize (lambda () (setf (etaf-value mode) 'maximized))
               :on-restore (lambda () (setf (etaf-value mode) 'normal))
    (etaf-label :text "Caller-owned content")))
```

The callbacks in a real application convert the gesture into geometry writes,
or can be supplied by an ETAF Behavior.  The catalog only supplies the gesture
targets and visual composition.  A
maximized or minimized mode does not change geometry, z-order, focus policy,
or workspace membership.  Minimizing hides the body while retaining it in the
Component tree, so caller-owned child state remains mounted.  Build those
rules in the application layer (for example, an `etaf-desktop` package), while
using these Components as its reusable visual shell.

### Desktop navigation and tiling controls

`etaf-taskbar` and `etaf-workspace-bar` are controlled bars for window and
workspace keys. Their item plists contain a scalar `:key` and string `:label`.
The workspace bar may also show caller-owned `:brand` and `:status` text for a
desktop menu/status strip.
taskbar items may also declare `:state` (`active`, `minimized`, or `error`) and
`:disabled`. `on-select`, `on-add`, and `on-close` only request caller-owned
policy changes. `on-launch` can open an application launcher beside the task
buttons.

`etaf-launcher` and `etaf-switcher` render controlled modal pickers. Items may
include `:description`, `:state`, and `:disabled`; the caller owns the registry,
the `open` ref and application/window lifecycle. `etaf-switcher` accepts a
`selected` key to mark the focused item. Escape and the dialog close button
call `on-close`, preserving ETAF's normal focus-return and shortcut cleanup.

`etaf-splitter` presents two named `first` and `second` slots with a
keyboard-focusable divider. `:orientation` selects a left/right or top/bottom
split, and `:ratio` remains caller-owned. `on-change` receives divider
gestures; pass an ETAF Behavior through `:use` when the application needs
pointer and keyboard ratio updates. The Component never stores layout-tree
state, window identity or persistence data, so the same controls work for a
desktop's floating and tiled managers. When `:overlay` is non-nil, it renders
only the divider over panes that the caller already owns. This is useful when
an application has positioned windows and wants the reusable splitter
interaction without an additional opaque pane. A positioned divider paints
only the content it has, so an overlay caller passes `:divider-content` (a row
of characters for a top/bottom split, one character per row for a left/right
split) and `:z-index` above the panes it separates.

## Basic controls


Core does not automatically load `.etaf` files. The optional Playground reads
inert structural source and explicitly loads its registered Elisp companion;
that file format does not create shorter Component aliases. Local callbacks
need no named Action. Components receive props and slots through the same API
as application-defined Components.

Button and Checkbox are controlled Components. `etaf-button` accepts `:label`,
`:on-press`, `:disabled`, `:ref`, `:id`, and the small presentation set
`:class`, `:color`, `:bgcolor`, `:border`, `:padding`, `:font-size`, `:font-weight`, `:tab-index`, `:help-echo`,
`:hover-content`, `:pointer`, and `:aria-label`, plus `:use` for a public Behavior list. An
enabled button
defaults to role `button` and tab index `0`; a disabled button keeps its label
and disabled styling but has no press handler, Behavior, or tab stop.
Enabled buttons default to the native `arrow` pointer; pass `:pointer 'hand`
for a drag-style affordance. Window title bars use `hand`, while resize handles
use directional resize pointers.
`etaf-checkbox` accepts `:checked`, `:label`,
`:on-change`, `:disabled`, `:ref`, and the same presentation props. It exposes
role `checkbox`, a stable `:ref`, and tab index `0` while enabled. Its
`:on-change` receives the next boolean value; disabled checkboxes have no
handler or tab stop.

`etaf-number-input` is a small controlled input primitive for values edited
through Emacs's native minibuffer. It accepts `:value`, `:label`, `:on-change`,
`:min`, `:max`, `:ref`, and `:disabled`; the callback receives the validated
integer while the caller remains the owner of the ref. The current value must
be an integer or nil, and the label a string or nil. Numeric bounds may be nil;
when both are present, `:min` must not exceed `:max`. Invalid configuration is
rejected before initialization or updated props publish; invalid live values
are rejected when rendered. Errors identify the component and property.

`etaf-text-input` edits strings with the native minibuffer. `etaf-select`
chooses a value from an ordinary alist, such as `((nil . "Pending") (t . "Done"))`.
Both use `:value` / `:on-change` or `:bind`, and compose the same Button entry.
TAB reaches the entry; RET or a mouse click opens native input. `C-g` cancels
without a change callback or additive press observer. Focus returns to the
retained entry; if its mounted target has disappeared, become disabled or
inaccessible, the result is cancelled. Native Emacs owns input methods, cursor,
selection and undo; the rendered surface remains owned by Ebox.

`etaf-menu` composes the same Button and native input boundary for actions.
Disabled items are excluded from native completion. A confirmation dialog can
be composed directly in the selected action, with no additional state model:

```elisp
(etaf-define-component task-actions ()
  :bindings ((done (etaf-ref nil)) (result (etaf-ref "Ready")))
  :view
  (column
   (etaf-checkbox :label "Done" :bind done)
   (etaf-menu :label "Actions"
              :items (list '(:key edit :label "Edit")
                           (list :key 'delete :label "Delete" :disabled (not (etaf-value done))))
              :on-select (lambda (action)
                           (pcase action
                             ('edit (setf (etaf-value result) "Editing"))
                             ('delete (when (etaf-confirm-dialog "Delete this task?")
                                        (setf (etaf-value result) "Deleted"))))))
   (etaf-label :text (etaf-value result))))

(etaf-mount "*task-actions*" (etaf-view (task-actions)))
```

The caller owns the items and business callbacks. Confirmation returns a
boolean; no leaves data unchanged, while `C-g` aborts the current callback.
Menu cancellation, confirmation and ordinary inputs all restore the same
retained entry through Ebox. If the action subsequently removes that entry,
normal Ebox focus removal applies. The API contracts are in [the entry](../etaf-ui.el).

A form can keep its draft in ordinary refs and validate before saving:

```elisp
(etaf-define-component task-draft ()
  :bindings ((title (etaf-ref "New task")) (done (etaf-ref nil)))
  :view
  (column :item-gap '(lh 1)
   (etaf-text-input :label "Title" :bind title)
   (etaf-select :label "State" :bind done
                :options '((nil . "Pending") (t . "Done")))
   (etaf-label :variant 'danger
               :text (if (equal (etaf-value title) "") "Title is required" ""))))
```

TextInput accepts empty text; field validation is the form's responsibility.
Select labels and values must be unique; a nil value can represent an explicit
option. An empty options list disables the entry. See the root entry for exact
prop/error contracts. Task Workbench demonstrates draft isolation, field errors,
save/cancel and confirmation before discarding edits when changing tasks.

For controls that directly change an existing ref, use `:bind`:

```elisp
(etaf-define-component preferences ()
  :bindings ((done (etaf-ref nil)) (rows (etaf-ref 3)))
  :view
  (column
   (etaf-checkbox :label "Done" :bind done)
   (etaf-number-input :label "Rows" :bind rows :min 1 :max 10)))
```

This is an ordinary UI Component prop, not a View directive. Checkbox reads
the ref as its checked source, TextInput, Select and NumberInput read it as their value source, and
the change callback writes to that same ref. External writes also update the
control; no second state is created. Disabled activation cannot write. Cancel
and validation failure preserve the value. Unmount releases control handlers
and subscriptions without owning the ref; rejected publication keeps the old
binding target.

A non-nil `:bind` must be a writable ref. Do not also supply `:checked`/`:value`
or `:on-change`, even explicitly as nil. Conflicts signal `etaf-view-error`
with the component, property, received value and expected input. `:bind nil`
leaves the explicit interface active. Additional `:on-press` observers retain
the existing event order and can read the updated value. For business validation,
transformation or database operations, use explicit value and `:on-change`
props instead of hiding those operations in a ref binding.

The catalog uses one semantic Theme vocabulary for color roles. The main
tokens are `:ui-fg`, `:ui-bg`, `:ui-border`, `:ui-muted-fg`,
`:ui-disabled-*`, `:ui-button-primary-*`, `:ui-button-secondary-*`,
`:ui-button-ghost-*`, `:ui-checkbox-*`, `:ui-table-*`,
`:ui-data-grid-error-fg`, `:ui-pagination-muted-fg`, and `:ui-panel-*`.
Applications provide these through ETAF's
`etaf-theme-provide`; legacy `:ui-button-color`-style aliases remain accepted
for compatibility. For light/dark colors, keep the semantic tokens in an
application-owned plist and pass it to `etaf-theme-resolve-palette` with an
explicit `light` or `dark` mode. The result uses the same Theme contract;
the UI catalog does not depend on a renderer-specific palette registry.

Component `:styles` declarations own default appearance. A non-nil
presentation prop supplied by the caller overrides normal defaults; ECSS
importance still applies. An omitted or nil prop leaves
the inherited Theme/default style available. Button has the deliberately small
`primary`, `secondary`, and `ghost` visual vocabulary; it is a visual variant
set, not a second widget taxonomy.

Enabled buttons and checkboxes expose a numeric tab stop and a semantic role.
Disabled controls retain their text and disabled appearance while suppressing
activation and tab navigation. Runtime composes explicit `:on-*` callbacks
with Behavior callbacks; UI declares the control and its visual state.

For native feedback, pass `:pointer 'hand :help-echo "Save changes"
:hover-style '(:text-decoration-line underline)` to a control. These root
attributes use Ebox capabilities through ETAF, including TextInput, NumberInput,
Select and Menu composed from Button. Omission preserves inherited feedback;
explicit nil removes it. Tie these attributes to the same disabled input when
feedback should disappear while disabled. Hover ends when the pointer leaves
and does not create retained ETAF visual state. `:hover-content` is a one-line
text replacement handled by Ebox's retained text-property update path; it does
not create an Emacs overlay.

The parent owns spacing: use `(row :item-gap '(ch 1) ...)` or
`(column :item-gap '(lh 1) ...)`; `flex` and `grid` use `:gap`. In particular, migrate
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
`:width`, `:border`, `:padding`, `:wrap-mode`, and `:ref`. Its Box owns layout;
the contained Text inherits typography. For a paragraph that follows its parent,
use `(etaf-label :text description :width 'stretch :wrap-mode 'word)`.
`description` may be a plain value, ref or computed; updates reflow the same
Label. Use `:wrap-mode 'none` with `:overflow 'hidden` to clip without soft wrapping,
or omit geometry for an intrinsic caption. A raw `text` Host remains available
when the caller wants Text without a layout container.
`etaf-panel` accepts `:title`, the same
surface presentation props, and projects the named `header` slot plus the
default slot.

<!-- M0b1: business-props -->
The public Component business props are derived from the definitions and kept
separate from forwarded Host attributes:

| Component | Business props |
| --- | --- |
| `etaf-label` | `:text`, `:variant` |
| `etaf-button` | `:label`, `:on-press`, `:disabled`, `:id`, `:ref`, `:class`, `:color`, `:bgcolor`, `:border`, `:padding`, `:font-size`, `:font-weight`, `:tab-index`, `:aria-label`, `:help-echo`, `:hover-content`, `:hover-group`, `:pointer`, `:use`, `:variant` |
| `etaf-checkbox` | `:checked`, `:label`, `:on-change`, `:disabled`, `:bind` |
| `etaf-panel` | `:title`, `:variant` |
| `etaf-number-input` | `:value`, `:label`, `:on-change`, `:disabled`, `:min`, `:max`, `:bind` |
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

DataGrid shows `Not loaded.` before the first request. During background
refresh it keeps existing rows interactive and shows `:loading-label` or
`Refreshing...`. Accepted rows also remain visible and interactive while writes
are pending and after failure or cancellation; status appears above the rows. Cancellation shows `:error-label` or `Loading cancelled.`;
errors and first loading retain their existing labels. Pagination disables
page changes during both loading and refreshing. The caller owns the Controller
and uses its cancel/reload API; UI keeps no second request state.

DataGrid composes the same row Components as Table. `:row-key` supplies the
non-nil stable scalar identity used to retain each row and its custom cell
Components. Without `:row-ref`, ETAF provides the row's instance-local Host
reference, so multiple grids can display the same data without collisions.
An explicit `:row-ref` function supplies a caller-owned address and must return
a non-nil stable reference for each interactive row.

Ordinary row callbacks capture the displayed row and handler. ETAF publishes
them with the corresponding successful render and releases them with the row;
applications need no callback cache or post-update synchronization. Use Host
references for addressing, not callback object identity. Loading status comes
from the Data Controller; arbitrary fields in a row remain business data.
Table and DataGrid iterate the supplied row objects directly. Replace a row
object to update its input, including replacements with equal contents; keep
its key to retain cell state and focus. In-place mutation is not reactive.

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
Custom cell Components can use ordinary unkeyed internal Hosts; there is no
need to repeat the row or column key on each nested node.

Cell functions use their row argument and normal lexical captures. Their
Context is the consuming Table/Grid location; they do not recover the author's
props, `etaf-state`, or private styles. Return an ordinary Component when a
cell needs its own state, styles, or lifecycle, and create persistent refs and
watches in that Component's `:bindings` or `:setup`. Capture an author's stable ref before
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
