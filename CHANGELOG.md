# Changelog

## Unreleased

### Removed

- The package manual `docs/manual.md` is replaced by the [UI chapters](https://etaf.top/ui-overview/) of the ETAF Reference Manual, which the README and the package Commentary link.

### Fixed

- Button, menu and toggle hover fills are derived from the application
  Theme when it names no hover colour: the catalog used fixed light tints,
  which turned into light text on a light fill under a dark application
  (a ghost label dropped to 2.2:1 contrast).  A Theme that provides
  `:ui-button-ghost-hover-bg`, `:ui-button-secondary-hover-bg`,
  `:ui-button-primary-hover-bg` or `:ui-accent-soft-bg` still wins.
- A linked inline code span that is also a code link keeps one
  `:text-decoration-line` instead of building a duplicate View property and
  failing to render.
- A Button keeps its label on one line: it no longer shrinks below its
  content in a narrow Flex line, so a toolbar wraps its buttons as whole
  items instead of splitting their text.  Tabs inherit this because their
  tabs are Buttons.
- A caller-supplied `:keymap` that binds framework-reserved keys (`Escape`,
  `Tab`, `?`, the arrows, `M-g`, `C-g`) is rejected with an
  `etaf-component-call-error` naming them, instead of silently replacing the
  framework binding.
- Full-bleed window side and bottom handles stay above the body for pointer
  feedback and dragging, including after geometry changes.
- Ordinary window body space uses the arrow pointer when pressed to focus;
  child controls retain their own pointer semantics.

### Changed

- A modal surface's default backdrop keeps the application painted and dims
  it through Ebox's `:backdrop-filter`, so covered text and images stay
  visible while covered controls keep their blocked pointers and focus
  targets.  `:backdrop` nil now paints no backdrop at all.

- Tile grids retain equal projected cell values, reducing rendering work when
  a shared observation changes only a few cells.

### Added

- Buttons and rendered links react to the pointer: an enabled,
  unselected Button paints its variant's hover token
  (`:ui-button-primary-hover-bg', `:ui-button-secondary-hover-bg' or
  `:ui-button-ghost-hover-bg') while hovered and declares `aria-selected'
  so selected tabs and segments keep their selected presentation, and a
  markdown link carries the `:accent-soft' palette color as its hover
  face.
- `etaf-pane-resizer` accepts `:ref` and puts it on the rendered divider,
  so a caller can focus or address the resize handle.
- `etaf-ui-markdown-parse`, `etaf-ui-markdown-view-block` and
  `etaf-ui-markdown-view-blocks` parse and render Markdown documents into
  ordinary ETAF Views.  The renderer takes the document tree and a `:palette`
  alist, and delegates links, footnotes, media, code blocks and code spans
  to caller callbacks (a `:code-link` callback can turn a code span into a
  link while it keeps its code style), so the previewer, the manual reader
  and other document views share one rendering path.  A `:code-bg' palette
  entry colors inline code and default code blocks, falling back to
  `:panel' when absent, so a document can keep code readable on tinted
  panels.  Table columns share the width by content, keep a short
  unbreakable run such as a CJK word whole, and wrap longer cells at word
  boundaries; the `:line-grid' environment keeps every line at the
  standard height for documents that scroll beside other content.
- `etaf-ui-svg-*` composes validated, XML-escaped SVG scenes and returns image
  descriptors for image sources and image Hosts such as `etaf-tile-grid`
  `:cell-image`, keeping ordinary box layout, focus and terminal text fallback.
- Tile grids can display caller-owned images or SVG in fixed multirow cells
  through `:cell-image` and `:cell-height`, retaining keyboard/mouse targets
  and text fallback. `:on-cell-focus` reports coordinates for media focus cues.
- `etaf-window` and `etaf-resizable-panel` accept `:full-bleed`: the default
  slot spans the panel's full body and enabled handles paint after it, so the
  body reaches the frame edges.  Pair it with handles whose cells sit in the
  header or in the body's own margin when the body must stay seamless.
- `etaf-text-grid` displays fixed-width character surfaces with independent
  retained rows, Unicode width validation and caller-owned data.
- `etaf-tile-grid` accepts `:cell-label` for meaningful accessibility names
  and help text while keeping its existing coordinate and activation contract.
- `etaf-tile-grid` accepts `:cell-color` to control each cell's foreground
  independently from its background, including reactive Theme colors.
- `etaf-window` wraps its body slot in a viewport region, so content rendered
  in the window reads the space it was given as `(PIXELS . ROWS)` with
  `etaf-viewport`.

- Catalog Components are fully keyboard operable through ETAF Host keys.
  Selectors, bars, tables, lists, trees, calendars and grids are single Tab
  stops navigated with arrows and `C-n`/`C-p`/`C-b`/`C-f`; `etaf-window` runs
  `:on-focus` when keyboard focus enters it, and moves with `M-<arrow>` and
  resizes with `M-S-<arrow>` from anywhere inside it;
  `etaf-range` and `etaf-slider` change with Left/Right (`etaf-range` adds
  Home/End and `:key-step`); splitter dividers and `etaf-pane-resizer` step with
  arrows; tree branches open with Right and close with Left.
- `etaf-ui-icon` and `etaf-ui-toggle-icon` accept `:tab-index`; a negative
  value keeps a pressable icon clickable but out of Tab order. They also accept
  `:aria-label`, which names them in `etaf-palette` and defaults to a string
  `:help-echo`.

- `etaf-search-field` renders a rounded search pill with an optional
  magnifier and a clear control, coloured by new `:ui-search-bg` and
  `:ui-search-fg` theme tokens.
- `etaf-pane-resizer` is a draggable divider reporting a caller-owned pane
  width clamped to `:min` and `:max`.
- `etaf-dropdown-menu` accepts `:icon` for an icon trigger and `:placement`
  for the menu's side; `etaf-text-input` accepts `:on-focus`.

- `etaf-media-viewer` shows an image or video in an in-buffer modal viewer
  that fits the live window, with a full video transport bar (play/pause,
  ten-second skips, clickable and draggable seek bar, speed, sound), gallery
  arrows, keys and swipes, and closing by Escape, q, the close control or a
  pointer press outside the media.

- `etaf-reactions` renders controlled reaction chips with counts, an
  accent tint for chosen ones that never changes their size, and an optional
  picker popover.

- `etaf-text-input` accepts `:variant 'plain` for a borderless field inside
  a styled container such as a chat composer; the default `outlined` field
  keeps its frame.

- The icon set adds `pin`, `bell-off`, `send`, `reply`, `users`, `megaphone`,
  `at`, a filled status `dot`, `info`, `menu`, `more-vertical`, `sidebar`,
  `eye` for view counts, and `smile`, `image`, `video`, `file` and
  `paperclip` for reaction and attachment affordances, with font glyphs, SVG
  shapes and line-safe text fallbacks.

- `etaf-avatar` accepts `:lines` for multi-row list avatars and
  `:background` for a solid identity color with white initials.
- `etaf-avatar` accepts `:src` for a photo and `:shape`; on graphical frames
  the default `circle` shape renders the photo, or the initials on a colored
  disc, as a round image. Use `:shape 'square` for the previous initials box.

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
  `:value` publishes a text update instead of rebuilding the view in every
  placement.
- `etaf-ui-window-resize-open` mounts a runnable catalog window whose title
  moves and whose eight handles resize through controlled Behaviors, with
  Shift-locked gestures and Escape restoring the starting rectangle.
  `benchmarks/performance-scenarios.el` registers `window.resize.*`
  workloads comparing a direct `etaf-runtime-update-host-geometry` commit
  with mounted reactive state, plus the native corner gesture.
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

- `etaf-window` no longer adds a built-in inset around its body slot.  The
  window provides the full body rectangle up to the frame's resize handles
  and content owns its own spacing, so an application can fill its window
  edge to edge.
- `etaf-text-input` edits its value in a native session inside the layout:
  the field grows with wrapped or new lines while keeping its padding and
  frame, mouse clicks and drags place the caret and select, printing keys
  bound by the application still type, and other application changes keep
  publishing while it is edited. Pressing outside or unmounting leaves the
  field and keeps its text instead of cancelling.
  `etaf-text-input-end`'s optional argument is now HOW: nil submits, `blur`
  leaves without callbacks and any other value cancels. Code that inserted
  text into the application buffer during a session must type keys instead.

- An outlined `etaf-text-input` keeps one reserved hairline frame and
  recolours it with the accent while focused; editing shows a bar caret
  instead of a blinking underline, and nothing moves when focus changes.

- The catalog runs on ETAF's fine-grained retained runtime and requires it.
  Component APIs are unchanged; each reactive prop now updates only its own
  retained node, and a failing update leaves the committed controls in place
  until the next write retries it.  Interactions report
  `etaf-runtime-revision` rather than generation or publication counters.

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

- `etaf-range` without `:ref` now seeks on pointer clicks and drags.
- `etaf-tabs` gives every tab the same padding in both variants, so labels
  keep their positions when the active tab changes.
- An icon inside a control no longer hides the control's tooltip.
- Open popovers, dialogs and drawers keep their navigation and close keys
  when the application binds the same keys through an emulation map.
- Surfaces and the media viewer now hide the cursor and install their keys in
  the mounted application buffer even when opened from another buffer.

- A stretched `etaf-text-input` next to a label or icon in a row fills the
  remaining width, and long lines wrap back to the field's column.

- Reopening a text input whose value spans several rows edits that value
  with the caret at its end, instead of the first row's layout padding.
- A text input begun by a key command, or emptied while editing, keeps the
  caret inside the field; typed text no longer lands beside it.
- An icon missing from the requested, default and `sys` sets now resolves
  through the built-in `svg` set (or its text variant) before falling back to
  its printed name.

- `etaf-number-input` keeps its `−`/`+` steppers and value on one line inside
  another wrapping row, such as the desktop settings grid. Ebox measures a
  field that stretches inside a wrapping parent at the whole row, so an
  embedded field with an explicit width sizes its own row to that width
  instead of forcing every stepper onto its own line.
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
