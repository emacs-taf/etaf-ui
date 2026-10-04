# Changelog

## Unreleased

### Added

- Native editor integrations can share an empty hint, edit observation and
  revision-guarded value replacement through `etaf-ui-editor-mode`. Existing
  editing keys, completion, selection and undo remain native; stale external
  updates cannot erase newer edits, even after undo restores identical text.

- `etaf-tile-grid` provides caller-controlled rectangular cells with stable
  coordinate identities, local reactive color/text, and shared keyboard/mouse
  activation. It contains no board state, algorithms or animation timers.

- `etaf-ui-icon-lines` exposes the existing line-safe icon text resolver for
  retained text cells, without requiring a positioned icon overlay.

- `etaf-ui-toggle-icon` renders one icon that switches between two names, or
  between two colours for one name, through retained Host text. A reactive
  `:value` publishes a text update instead of rebuilding the view; keep it in
  an absolutely positioned panel to use that retained path, and every other
  placement still renders correctly through an ordinary publication.
- `etaf-ui-window-resize-open` mounts a runnable catalog window whose title
  moves and whose eight handles resize through controlled Behaviors, with
  Shift-locked gestures and Escape restoring the starting rectangle.
  `benchmarks/performance-scenarios.el` registers `window.resize.*`
  workloads comparing direct Ebox geometry publication with mounted
  reactive state, plus the native corner gesture.
- `etaf-ui-dismiss-outside-press` closes every mounted floating surface whose
  panel the current press missed. A shell root calls it from `:on-press` and
  `:on-press-capture` to give unpainted modals and popovers click-outside
  dismissal; a surface opened by the same press stays open.
- Desktop Components read their colors from Desktop Theme tokens
  (`:ui-shell-*`, `:ui-accent*`, `:ui-window-*`, `:ui-divider-bg`,
  `:ui-picker-item-*`) inside retained Host properties, so a Theme provided
  with `etaf-theme-provide`, including a reactive one, restyles bars, window
  chrome, dividers and pickers through paint slots without re-rendering.
  Picker rows render a bold caption above a muted description on a full-width
  tinted row with an accent marker for the selected item.
- `etaf-splitter` overlay dividers accept refs or computeds for
  `:overlay-rect` (and its entries), `:z-index`, `:divider-content` and the
  new `:visible` property. A layout policy repositions, relabels or hides
  dividers through retained cells without re-rendering the tree.
- `etaf-workspace-bar` `:layout-label` accepts a ref or computed. The layout
  control reserves a fixed width so a changed label publishes as a prepared
  Text update instead of re-rendering the bar.
- `etaf-dialog` accepts `:close-label nil` to omit its default footer button
  so a confirmation footer can order its own Cancel and commit actions.
- `etaf-select` accepts `:presentation` (`auto`, `chips` or `dropdown`),
  `:hide-label`, `:width` and `:ref`. Selection stays in the UI: up to four
  options render as inline chips, more render an anchor pill that opens a
  Popover listing the options. `etaf-number-input` renders `−`/`+` steppers
  around its value pill and accepts `:hide-label`; `etaf-text-input` accepts
  `:hide-label`.
- The shared `svg` icon set adds `star`, `radio`, `disc`, `chart`, `mic` and
  `clock`, so applications can keep library and status surfaces in the same
  line-icon style as their player controls.

### Changed

- `etaf-range` paints a track with an accent Fill overlay: the Fill is an
  absolutely positioned Host painted above the track, so the split is visible
  in every context while the track keeps the row's measurable width. A caller
  may advance the Fill through ETAF's retained geometry update without
  republishing the View, and a press or drag re-proportions the two parts
  through the component's own ref before the caller's value arrives. The bar
  advertises the hand pointer.
- Traffic-light controls use one-cell ASCII marks when SVG is unavailable,
  avoiding fallback symbol fonts with taller physical text rows.

- Checkbox, radio, switch, selection, disclosure and close markers use ASCII
  characters from the inherited text font. This avoids symbol-font fallback
  increasing an entire Emacs physical row and shifting neighboring panes.
  Checkbox markers reserve three character cells for `[x]` and `[ ]`.

- Window shells, title bars and traffic lights inherit the surrounding Emacs
  typography by default instead of forcing 14 CSS pixels (10.5 points).
  Window title/body sizes can independently override inheritance with positive
  CSS pixel values; panel `font-family` now reaches its rendered content.

- Traffic-light SVG glyphs fill with `currentColor`, so the control Host's
  `:color` paints them. Focus changes no longer replace the glyph Text, and
  an inactive window's lights use the `:ui-window-title-fg` Theme token in
  graphical and textual Emacs alike. The window title row gives its content
  column a zero flex basis so the row lays out in a single render.
- Buttons are borderless pills. `primary` fills the accent in bold,
  `secondary` uses the soft accent tint and `ghost` inherits its surface with
  narrower padding; the variant name is part of the Button class. Checkboxes,
  radios and switches drop their border and background: a selected control
  and the checkbox mark paint the secondary button tint
  (`:ui-button-secondary-fg` on `:ui-button-secondary-bg`), as does the
  selected launcher or switcher row, so they stay crisp inside a dialog
  while a Desktop dims the shell's accent tokens.
  The fallback palette no longer defines `:ui-button-*-border`,
  `:ui-selection-*` or `:ui-checkbox-*-bg/-border`; Themes may drop them.
- Floating surfaces share one card anatomy: a one-row header with the title
  under a hairline, a body padded by one row and two columns, and a
  right-aligned footer. Dialogs and drawers add a pointer-only x named
  "Dismiss" to the header; the dialog's default close button is `secondary`. A fixed dialog
  height needs the body rows plus five instead of seven.
- Desktop bars render pill items separated by one column; the taskbar
  launcher is a `primary` button and the workspace layout control a
  `secondary` one. Picker rows pad two columns and mark the selected item with
  `*` in bold; unselected captions use normal weight.

### Removed

- `etaf-taskbar` and `etaf-workspace-bar` no longer accept `:accent-color`;
  selection paints the `:ui-accent` and `:ui-accent-soft-bg` Theme tokens.
  Provide a Theme with those tokens to change the accent.

### Fixed

- `etaf-divider` keeps an unlabelled horizontal rule continuous: the one
  character column gap is reserved only when a label is present.

- A disabled button keeps its variant's padding and, for `ghost`, its
  transparent surface, so disabling a stepper or chip no longer widens it
  or fills it with the disabled surface.
- Inactive window traffic lights are gray again in graphical Emacs. The SVG
  glyph received a deferred Theme token instead of a color, which made every
  inactive control render as a black circle.
- `etaf-workspace-bar` renders a single space when its `:status` is nil or
  empty, so the status Text keeps owning its row. An empty string made Ebox
  paint the blank as box-owned pixels, which rejected the retained
  publication of every later status change and fell back to a structural
  re-render on each workspace switch.
- `etaf-launcher` and `etaf-switcher` items show their caption above the
  optional description instead of replacing it, and their Dialog is sized to
  the item list and centered. Modal Dialogs without an explicit `:height`
  no longer stretch to 80% of the window. Both pickers accept `:backdrop`
  so a Desktop can keep its surface painted under the modal.

- `etaf-window` forwards `drag-lock-modifier` to every edge and corner resize
  handle as well as its title. Modified resize gestures can continue after
  release, confirm on the next press, or cancel through the existing Ebox
  gesture contract. Standalone `etaf-resizable-panel` supports the same
  property with locking disabled by default; explicit nil disables locking.

- Workspace status uses a clipped single-row region; layout and settings
  actions stay at the right edge when status length changes. Long titles no
  longer push these controls out of the bar.

- Native text and number inputs omit decorative edit glyphs, and native
  Select/Menu controls use an ASCII marker. Opening forms no longer increases
  line height through a taller fallback font for those decorations.

- `etaf-dialog` can use a bounded row height and compact single-row title.
  Centering measures the window displaying its buffer, so a modal no longer
  falls back to the left edge when no dynamic Ebox viewport is bound.

- An inactive window renders all three macOS traffic lights in one gray and
  the active window keeps red, yellow and green.  `etaf-window` exposes
  `:controls-active` and `etaf-desktop` sets it from the focused window.

- `etaf-window` renders its title bar across the complete panel width.  The
  frame no longer reserves handle columns inside the panel: side and bottom
  cells own the panel's outer tracks, the header owns the title row, and its
  two corner cells keep the top edge resizable while the title keeps the move
  gesture.  Title backgrounds and bottom rules stay closed across the window.

- `etaf-splitter` overlay dividers accept `:divider-content` and `:z-index`.
  A positioned divider paints only the content it has, so a caller that owns
  the panes supplies the divider's rendered extent and stacking order.

- `etaf-splitter` accepts a caller-owned `:overlay-rect` so nested and
  constrained split dividers can occupy the exact gap reserved by the layout.

- Gallery diagnostic traces include the complete input operation, including
  Ebox pressed-state and focus publications outside the application callback.
  Latency and profiler passes continue measuring the unobserved input route.

- `etaf-button` forwards `:id` to the rendered Host, so anchor-based surfaces
  that reference a Button by identity resolve it instead of depending on a
  focus reference.
- Floating surfaces treat an unmounted or not-yet-committed panel as
  unavailable during key lookup and mount settling instead of failing the
  activation that is already mid-flight.

### Changed

- `etaf-window`, `etaf-window-chrome` and `etaf-window-controls` publish a
  reactive `:mode` or `:visible` change as retained Host property bindings
  (mode classes, panel visibility and the collapsed content column) instead
  of re-rendering the shell. The green traffic light is one stable "Zoom"
  control that restores a maximized window and maximizes any other; the
  separate "Maximize"/"Restore" labels are gone. `etaf-resizable-panel`
  accepts a ref or computed `:class`, and `etaf-taskbar` item `:state`
  values may be refs or computed. Desktop bar item tones read their active
  and state sources unconditionally so their bindings stay prepared.

### Added

- `etaf-workspace-bar` accepts a caller-owned ref or computed `:status` value;
  nil clears the status text. Both desktop bars retain their input targets
  while ref or computed selection values change.

- Gallery Review has continuous callback, keyboard and mouse performance
  scenarios that reuse one page and verify both directions of the toggle.
  First-click scenarios remain available separately.
- Add Drawer and ContextMenu compositions using the existing floating surface,
  with bounded side placement, modal blocking, keyboard dismissal and focus return.
- Add Tag, Kbd, Steps and List. Button accepts non-interactive default-slot
  content, so rich list rows share the standard focus and activation contract.
- Add DatePicker, Tree, Calendar and CommandPalette as compositions of the
  shared input, navigation, list and Dialog surfaces.
- Atelier Gallery includes responsive catalog columns, a paginated collection
  browser, dismissible tags, steps and an inspector drawer. Run
  `make gui-check GUI_EXAMPLE=gallery` for its native Emacs interaction workflow.

- `etaf-popover`, `etaf-dropdown-menu` and `etaf-dialog` provide in-buffer
  floating content, disabled action items and modal composition. They share
  Ebox positioning, occlusion and scoped focus through ETAF; closing and
  nested handoff restore a valid prior entry. Escape/C-g dismiss and Tab or
  arrow keys navigate. The application owns dialog state and form values.
- `etaf-ui-surfaces-open` opens a runnable composition example. These
  components require ETAF's `etaf-focus-within` and its Ebox provider.

### Changed

- Gallery performance checks use the shared workspace runner and registered
  scenarios. Use `--diagnose` for separate phase, CPU and allocation passes and
  `--baseline` to compare saved evidence. `PERF_TOOL` selects the workspace tool
  when the package is checked out separately. Replace `--trace` with `--diagnose`
  and `--output FILE` with `--output-dir DIRECTORY`; previous Gallery JSON files
  are not compatible with the shared runner's baseline schema.

- DataGrid composes the same row Components as Table, including row layout,
  selection paint and custom cell state. ETAF owns automatic row references and
  publishes current callback inputs. Address rows by Host reference; callback
  object identity is no longer kept stable by a separate UI cache. Public
  DataGrid props and explicit row references are unchanged.

- DataGrid shows idle, background refresh and cancellation states. Refresh
  retains interactive rows; Pagination disables page changes while refreshing.
  Update ETAF together with UI for the asynchronous Data status contract.

### Fixed

- `etaf-divider` keeps an unlabelled horizontal rule continuous: the one
  character column gap is reserved only when a label is present.

- Passive Tooltip and Toast surfaces no longer move focus to an empty panel
  root after mounting. Their dismissal keymap remains active while the extra
  focus-only Ebox publication is avoided, reducing overlay interaction latency.
- Avatar derives visible initials from its name when initials are omitted.
  Steps retain each label and number, and Breadcrumb callbacks report the
  selected index instead of the final loop index.
- Panel content has consistent vertical spacing; Gallery columns follow their
  own content height instead of stretching small sections to match neighbours.

- NumberInput rejects malformed labels, bounds and current values with component
  and property context. UI input checks share ETAF's `etaf-check-prop`; update
  ETAF together with UI for this input validation contract.

- Custom cells continue publishing state changes after combined row and column
  reordering. Table and DataGrid use Ebox's shared source identity matching;
  row Components no longer repeat their key on an internal Host. Update Ebox
  together with UI for the corrected Range identity behavior.

- Table and DataGrid pass original rows through keyed iteration, preserving
  unchanged input identities. Replacement row objects update callbacks even
  when contents match, while stable keys retain cell state and focus.

- DataGrid no longer interprets a row's `:etaf-data-grid-state` or `:text`
  business fields as loading/error metadata.

- Label now supports its documented width, padding and border attributes.
  It composes an Ebox Box and Text, so constrained prose can wrap and reflow
  after content or viewport changes. The `etaf-label` class and forwarded
  attributes address the Box; selectors explicitly requiring a Text root
  should use `.etaf-label` instead. Raw `text` Hosts remain unchanged.

- Native pointer, help and hover feedback can be requested through control
  root attributes with the updated ETAF bridge. Correct the manual's claim
  that all controls provide this feedback by default.

- Empty accepted DataGrid pages still announce background refresh while preserving their empty-state message.

### Added

- Add Menu actions with disabled choices and a composable native confirmation
  dialog. Both reuse the existing Button/input ownership and focus behavior.

- Keep accepted DataGrid rows and their actions visible during pending writes, errors and cancellation, with separate status text.

- Add TextInput and Select with controlled values or `:bind`. All native inputs, including NumberInput, use the shared target lifetime and focus boundary; update ETAF and Ebox together.

- Checkbox and NumberInput accept `:bind` with an existing writable ETAF ref.
  The controls read and update that same ref through their controlled interface.
  Explicit value or `:on-change` props conflict with a non-nil binding, including
  explicit nil. Existing value/callback usage remains available for business
  operations and transformations.
