# Changelog

## Unreleased

### Fixed

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

### Added

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
