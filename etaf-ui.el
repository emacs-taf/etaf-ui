;;; etaf-ui.el --- Official ETAF Component catalog -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Author: ETAF contributors
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (etaf "0.2.1") (ebox "3.0.0"))
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
;; Every Component is keyboard operable through ETAF's key layer.  Tabs,
;; segmented and radio selectors, desktop bars, window controls, tables,
;; lists, trees, calendars, breadcrumbs, steps and tile grids are each one
;; Tab stop entered at their selected item; arrows and C-n/C-p/C-b/C-f move
;; inside them.  Dialogs, drawers, popovers and the media viewer are modal
;; key scopes closed by Escape or C-g.  `?' lists the keys in scope.
;;
;; Component: etaf-button (&key label on-press disabled id ref class color bgcolor border padding font-size font-weight tab-index aria-label help-echo hover-content hover-group pointer use variant)
;; Render a standard pressable Button with a committed callback.
;;
;; DISABLED removes the callback and default focus tab index.  VARIANT is
;; `primary' (accent fill, bold, default), `secondary' (soft accent tint) or
;; `ghost' (inherits its surface, narrower padding); every variant is a
;; borderless single-row pill whose class carries the variant name.
;; Presentation props remain caller-overridable.  Runtime publishes ON-PRESS with the visible Button,
;; so a failed render keeps the previous callback and its captured values.
;; ID reaches the rendered Host so anchor-based surfaces can reference the
;; Button by identity.
;; Native root attributes :pointer, :help-echo, :hover-style and
;; :hover-content request Ebox text-property capabilities.
;; interaction feedback; explicit nil blocks inherited capabilities.
;; Use inside (etaf-view (etaf-button ...)); keyword arguments are component props.
;; A default slot replaces the visible label with ordinary non-interactive
;; content (for example, a title and description). LABEL or ARIA-LABEL still
;; names the single focus/activation target; nested controls are inappropriate.
;;
;; Component: etaf-checkbox (&key checked label on-change disabled bind)
;; Render a controlled Checkbox whose next value is sent to ON-CHANGE.
;; Alternatively, pass an existing writable ref as :bind; its current value
;; supplies CHECKED and the next boolean is written to the same ref.  Non-nil
;; BIND rejects explicitly supplied CHECKED or ON-CHANGE, including nil, with
;; `etaf-view-error'.  Nil BIND leaves the explicit controlled interface active.
;; Native root attributes request Ebox pointer, help and hover feedback,
;; using the same forwarding contract as Button.
;; No additional state is created. External ref writes update the control;
;; disabled activation cannot write. :on-press remains an additive observer.
;; Failed publication retains the old binding target, and unmount releases
;; the control's handlers and subscriptions without owning the caller's ref.
;; Use inside (etaf-view (etaf-checkbox ...)); keyword arguments are component props.
;;
;; Component: etaf-tile-grid (&key rows columns cell-width cell-background cell-text cell-label cell-ref on-cell-press)
;; Render ROWS by COLUMNS fixed cells with stable coordinate identities.
;; Dimensions and CELL-WIDTH (character columns, default 2) are positive integers.
;; Optional callbacks take zero-based ROW and COLUMN. CELL-BACKGROUND returns
;; a color or nil; CELL-TEXT returns one line fitting CELL-WIDTH (default space).
;; CELL-LABEL returns a string for accessibility and help (default "Cell r,c").
;; Read caller refs inside those callbacks to retain property/text boundaries.
;; ON-CELL-PRESS handles keyboard and mouse activation. Without it cells are
;; read-only. CELL-REF returns a distinct supported Host reference per cell;
;; omitted references are instance-local. Caller owns data and lifecycle;
;; the grid does not run timers or maintain a second selection/board state.
;; Invalid dimensions, callbacks or text signal etaf-component-call-error.
;; Use (etaf-view (etaf-tile-grid :rows 8 :columns 12 ...)).
;;
;; Component: etaf-text-grid (&key rows columns row-text row-ref label)
;; Display ROWS fixed text lines, each COLUMNS character columns wide.
;; Dimensions are positive integers. ROW-TEXT is a required callback receiving
;; the zero-based row; return a single-line string whose display width fits
;; COLUMNS. Short rows are padded with spaces. Read refs inside the callback to
;; update individual rows; each row keeps a stable identity. ROW-REF optionally
;; returns distinct Text Host references for retained content updates. Those
;; updates must also fit and pad to COLUMNS; keep the callback's state in sync.
;; LABEL names the read-only surface (default "Text grid"). The component has
;; no focus targets, input handling, timers or terminal escape interpretation.
;; Use monospaced text; wide characters occupy their Emacs display width.
;; Invalid dimensions, callbacks or row content signal etaf-component-call-error.
;; Use (etaf-view (etaf-text-grid :rows 24 :columns 80 :row-text read-row)).
;;
;; Component: etaf-data-grid (&key controller columns row-key on-row-press row-ref row-selected-p loading-label error-label empty-label)
;; Render DATA CONTROLLER state through the public Component DSL.
;;
;; DataGrid shows idle, loading, refreshing, cancelled, error and empty states.
;; Accepted rows stay interactive during pending or failed operations. Status
;; appears above the rows; refresh uses LOADING-LABEL or Refreshing....
;; Cancellation uses ERROR-LABEL or Loading cancelled. Pagination disables
;; page changes while loading or refreshing. Controllers remain caller-owned.
;; Table row Components retain keyed identity and custom cell state across
;; insert, reorder and update. ETAF supplies instance-local Host references and
;; publishes each row callback with its visible data; callers need :row-ref only
;; for explicit external addresses. UI owns no callback or reference cache.
;; COLUMNS use Table's unique keys and optional `:cell' row-to-View functions.
;; Row fields remain business data and are never interpreted as loading status.
;; Use inside (etaf-view (etaf-data-grid ...)); keyword arguments are component props.
;;
;; Component: etaf-label (&key text variant)
;; Render TEXT in a semantic Label with ordinary Box layout. TEXT accepts a
;; value, ref or computed; nil is empty, strings retain their text properties,
;; and other values use their printed representation. VARIANT selects the
;; default, muted, danger, success, strong or heading presentation. Strong and
;; heading emphasize text with weight while retaining the inherited font size.
;; Layout attributes such as :width, :padding, :border and :wrap-mode apply
;; to the Label's Box; its Text child inherits typography and color.
;; Use :width 'stretch to follow the containing width and :wrap-mode 'word
;; for wrapping prose. Reactive text and viewport changes use Ebox reflow.
;; Use inside (etaf-view (etaf-label ...)); keyword arguments are component props.
;;
;; Component: etaf-number-input (&key value label on-change disabled min max bind hide-label ref)
;; Render a controlled stepper NumberInput: a muted LABEL, a − stepper, the
;; value pill and a + stepper.  Steppers change the value by one and disable
;; at MIN/MAX; pressing the value pill, which REF names, reads a number in the
;; minibuffer.  HIDE-LABEL omits the caption for grid forms.
;; Alternatively, :bind accepts an existing writable ref and replaces VALUE
;; plus ON-CHANGE. It uses the same conflict, ownership and publication rules
;; as Checkbox. The current value must be an integer or nil, label a string or
;; nil, and min/max numbers or nil with min <= max. Invalid inputs signal
;; etaf-component-call-error identifying the Component and property. Input
;; configuration is checked before initialization or updated props publish;
;; live values are checked when rendered. Prompt results are checked against
;; the integer and min/max constraints before writing the ref;
;; canceling the native prompt leaves the value unchanged. Custom business
;; validation or transformation uses the explicit VALUE/ON-CHANGE interface.
;; Use inside (etaf-view (etaf-number-input ...)); keyword arguments are component props.
;; The shared native input boundary restores focus to the retained entry.
;; Target removal, unmount or a disabled/inaccessible entry cancels the result
;; before ON-CHANGE or an additive ON-PRESS observer runs.
;;
;; Function: etaf-ui-editor-mode (&optional arg)
;;;###autoload (autoload 'etaf-ui-editor-mode "etaf-ui" nil t)
;; Enable or disable native editing behavior in a caller-owned UI buffer.
;; The mode preserves text, the major-mode keymap, undo, selection and CAPF.
;; It owns an empty hint and edit observation, not window layout or transport.
;; No minibuffer is opened. Disabling removes its overlay/hooks, never text.
;; Framework/native-pane integrations configure it through the functions below.
;; This behavior is not yet a layout-mounted Input/Textarea Component.
;;
;; Function: etaf-ui-editor-configure (&key (placeholder nil placeholder-p) (placeholder-face nil face-p) (on-change nil callback-p))
;;;###autoload (autoload 'etaf-ui-editor-configure "etaf-ui" nil nil)
;; Configure the current editor's hint string, face and edit observer.
;; Enable etaf-ui-editor-mode first. Omitted fields retain existing values;
;; explicit nil ON-CHANGE detaches it. The observer receives the buffer after
;; text changes and must not edit it. Errors propagate without erasing text.
;; Configuration and point movement produce no edit notifications.
;;
;; Function: etaf-ui-editor-value (&optional buffer)
;;;###autoload (autoload 'etaf-ui-editor-value "etaf-ui" nil nil)
;; Return a detached, property-free, widened text value without changing edit
;; state. BUFFER defaults to current and must have the editor behavior enabled.
;;
;; Function: etaf-ui-editor-replace (buffer text &optional expected-tick)
;;;###autoload (autoload 'etaf-ui-editor-replace "etaf-ui" nil nil)
;; Replace native editor text, preserving markers where possible and making
;; one undoable replacement. Return t if accepted; nil on a stale optional
;; buffer-chars-modified-tick. Equal text changes nothing and emits no callback.
;; Applications, not this behavior, decide when a reply permits replacement.
;; Explicit updates may change read-only text. Invalid/stale handles and
;; reentrant replacement signal user-error; observer errors leave accepted
;; text intact. Native hooks still run, and this mode observes the final value.
;;
;; Function: etaf-text-input-begin (runtime ref)
;;;###autoload (autoload 'etaf-text-input-begin "etaf-ui" nil nil)
;; Begin native editing of mounted text input REF in RUNTIME and return it, or
;; nil when REF is unknown, disabled, read-only or already editing. Activation
;; calls this from the field's own callback; call it directly to focus a
;; composer or open a grid cell. Beginning another field first leaves the
;; previous one, keeping its text. Other publications continue while editing.
;;
;; Function: etaf-text-input-end (&optional how)
;;;###autoload (autoload 'etaf-text-input-end "etaf-ui" nil nil)
;; Finish the active text input and return its user text, or nil when none is
;; active. HOW nil submits: the text stays the value and :on-submit receives
;; it. HOW `blur' leaves the field keeping its text, without callbacks. Any
;; other HOW cancels: the value captured at activation is restored through
;; the change callback and :on-cancel receives the abandoned text. The session
;; is released even when a callback signals; the signal then propagates.
;;
;; Function: etaf-text-input-active-p (&optional runtime)
;;;###autoload (autoload 'etaf-text-input-active-p "etaf-ui" nil nil)
;; Return the text input currently editing in RUNTIME, or nil. RUNTIME defaults
;; to the active field's Runtime, so the query works from any buffer.
;;
;; Component: etaf-text-input (&key value bind on-change label placeholder rows width variant disabled read-only submit-on-return on-submit on-cancel on-focus completion-functions keymap hide-label ref)
;; Edit text directly in the application's layout. VALUE/ON-CHANGE or a
;; writable BIND supplies the controlled string; ROWS (default 1) sets the
;; minimum visible lines, so one Component covers single-line inputs and text
;; areas. LABEL defaults to "Text" and HIDE-LABEL omits its muted caption.
;; PLACEHOLDER (default "") shows while the value is empty and never becomes
;; its content. VARIANT `outlined' (default) frames the text in a panel with a
;; hairline border that takes the accent colour while focused, without moving
;; any cell; `plain' draws only the text, for composers inside a styled footer.
;; Editing shows a bar caret and no other focus decoration.
;; Activation starts a native editing session on the field's value inside the
;; application layout: every keystroke reflows only the field, which grows
;; with wrapped or added lines while padding and frame stay intact. Native
;; commands, input-method preedit, undo, kill/yank, word and line motion, and
;; mouse caret placement and selection all act on the value alone, with no
;; minibuffer, frame or extra window. Printing keys reach the field even when
;; the application binds them. Return submits when :submit-on-return is
;; non-nil (default for one row) and otherwise inserts a newline;
;; Shift+Return and C-j insert an unindented newline; C-c C-c and
;; Ctrl+Return submit; C-c C-k, Escape and C-g cancel and restore the
;; activation value; TAB/backtab leave and move application focus; M-TAB
;; completes. A press or click outside the field leaves it, keeping the text.
;; ON-SUBMIT and ON-CANCEL receive the session text; ON-FOCUS runs without
;; arguments once a session begins, by pointer, keyboard or
;; `etaf-text-input-begin'. READ-ONLY stays focusable
;; without a session; DISABLED also removes activation. COMPLETION-FUNCTIONS
;; configures CAPF during the session and KEYMAP adds field-local bindings,
;; which run in the application buffer. Other application changes publish
;; while editing. Invalid props signal contextual `etaf-view-error'.
;; Use inside (etaf-view (etaf-text-input ...)); companion functions above drive
;; it programmatically.
;;
;; Component: etaf-search-field (&key value bind on-change placeholder width icon on-focus on-submit on-cancel on-clear keymap ref)
;; Render a rounded pill search field editing a controlled query through
;; `etaf-text-input', so ON-CHANGE sees every keystroke. VALUE/ON-CHANGE or a
;; writable BIND supplies the query. The pill is three rows tall and its painted
;; surface leaves half a row above and below the text. PLACEHOLDER (default
;; "Search") shows while the query is empty; ICON non-nil adds a magnifier;
;; WIDTH defaults to stretch. A clear button follows a nonempty query: it
;; empties the query, calls ON-CLEAR and keeps editing. A press anywhere on the
;; pill begins editing. ON-FOCUS, ON-SUBMIT, ON-CANCEL and KEYMAP follow
;; etaf-text-input; REF names the input for `etaf-text-input-begin'. Colors come
;; from the :ui-search-* theme tokens.
;; Use (etaf-view (etaf-search-field :bind query :icon t)).
;;
;; Component: etaf-menu (&key label items on-select disabled)
;; Render a Button opening native completion for an action. LABEL defaults to
;; "Actions". ITEMS are plists with unique non-nil scalar :key values, unique
;; nonempty string :label values and optional :disabled. Native choices include
;; only enabled items. ON-SELECT receives the chosen key once, after the input
;; boundary validates the entry and restores focus. Empty input or C-g cancels.
;; No enabled items, nil ON-SELECT or DISABLED disables the Button. Like other
;; inputs, :on-press is an additive observer. Current props supply each published
;; menu; no application value or extra open-state ref is owned by the control.
;; Invalid props signal contextual `etaf-view-error'. Use in `etaf-view'.
;;
;; Function: etaf-confirm-dialog (prompt)
;;;###autoload (autoload 'etaf-confirm-dialog "etaf-ui" nil nil)
;; Ask a nonempty string PROMPT with the native yes/no minibuffer from a Host
;; callback. Return non-nil on confirmation and nil on no; change application
;; state only after confirmation. C-g or invalidated entry ownership aborts the
;; callback. Ebox restores focus to the valid entry; no surface content is edited.
;; Outside a Host event, signal `etaf-event-error'. Invalid PROMPT signals
;; `etaf-view-error'. Compose in a Menu's ON-SELECT or a Button's ON-PRESS.
;;
;; Component: etaf-select (&key value options label placeholder on-change disabled bind presentation hide-label width ref)
;; Choose a controlled value from OPTIONS without leaving the UI.
;; PRESENTATION is `chips', `dropdown' or `auto' (default): chips render each
;; option as an inline pill with the current one filled; a dropdown renders one
;; anchor pill "CAPTION v", which REF names, and lists the options as ghost
;; buttons in a Popover of WIDTH (default (ch 28)) that closes on selection or
;; Escape.  `auto' shows chips for up to four options.  HIDE-LABEL omits the
;; muted caption for grid forms.
;; OPTIONS is an alist of (VALUE . LABEL); values are unique symbols, numbers
;; or strings, labels unique nonempty strings. Nil is a valid option value.
;; A nil VALUE absent from OPTIONS displays PLACEHOLDER; other absent values
;; are errors. An empty list disables activation. LABEL defaults to "Select"
;; and PLACEHOLDER to "—"; both are strings. VALUE may be a ref/computed.
;; ON-CHANGE receives the accepted option value. :bind follows TextInput.
;; Invalid props signal contextual `etaf-view-error'. Use (etaf-view (etaf-select ...)).

;; Component: etaf-radio (&key value options label on-change disabled bind)
;; Render a controlled single-choice group from an options alist. VALUE/ON-CHANGE
;; or the writable BIND ref owns the selection.
;;
;; Component: etaf-switch (&key checked label on-change disabled bind)
;; Render a controlled binary switch with Checkbox's ownership contract.
;;
;; Component: etaf-segmented (&key value options on-change disabled bind)
;; Render a compact mutually-exclusive selector from an options alist.
;;
;; Component: etaf-slider (&key value min max step label on-change disabled bind)
;; Render a controlled integer value within MIN..MAX aligned to STEP.
;; Left and Right on the focused slider report the value moved by STEP.
;;
;; Component: etaf-range (&key value min max step key-step on-change on-commit disabled color track-color bar-height label ref fill-ref)
;; Render a controlled interactive Range (progress, seek, volume) within MIN..MAX.
;; ON-CHANGE reports intermediate values and ON-COMMIT the released one; the bar
;; paints a Track and a percentage Fill inside one standard row. A retained
;; binding updates FILL-REF's width without re-rendering the Component.
;; MIN/MAX accept numbers or reactive sources. Live bounds are checked by the
;; retained Fill getter; invalid bounds reject publication until corrected.
;; Left and Right on the focused range report the value moved by KEY-STEP
;; (default STEP, else a twentieth of the span) through ON-CHANGE and
;; ON-COMMIT; Home and End report MIN and MAX.

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

;; Component: etaf-resizable-panel (&key x y width height position z-index visible min-width max-width min-height max-height resizable resize-edges resize-refs resize-use on-resize on-move header-style drag-lock-modifier font-size font-family ref id class role use overflow)
;; Render a controlled positioned panel and optional edge/corner resize handles.
;; Geometry props are passed to Ebox and may be values, refs or computed values;
;; CLASS may also be a ref or computed so a caller's mode class changes stay a
;; Host property binding.  A panel with a `header' slot is always framed so the
;; header row reaches both borders even when resizing is disabled.
;; ON-MOVE receives a gesture plist; ON-RESIZE receives EDGE and that gesture.
;; DRAG-LOCK-MODIFIER defaults to nil; a supported modifier enables Ebox's
;; release-independent gestures on the panel and all enabled resize handles.
;; A second primary-button press confirms; Escape cancels through the same
;; callbacks.  Geometry restoration remains the caller's responsibility.
;; The `header' slot owns the first row between the corner cells, HEADER-STYLE
;; presents those cells like the header, and the default slot fills the body
;; area, so a caller's title bar reaches both panel borders.
;; Callers own geometry updates and constraints.  This component stores no
;; state, does not assign z-order and does not implement a window manager.
;; FONT-SIZE and FONT-FAMILY default to nil, inheriting the surrounding
;; typography (the Emacs default font without an authored ancestor override).
;; An explicit FONT-SIZE is a positive number in CSS reference pixels.
;; Positioned content must fit its containing canvas's shared line height;
;; Ebox rejects a font whose resolved line height exceeds that canvas.

;; Component: etaf-window-controls (&key mode show-minimize show-maximize show-close active on-minimize on-maximize on-restore on-close group class)
;; Render reusable macOS-style traffic-light controls.  GROUP is forwarded to
;; Ebox hover grouping so all controls update in one incremental batch.  ACTIVE
;; selects the macOS presentation: an inactive window shows one gray for all
;; three lights and the active window keeps red, yellow and green.  The green
;; "Zoom" control has one stable target: it calls ON-RESTORE while MODE is
;; `maximized' and ON-MAXIMIZE otherwise.  MODE and ACTIVE may be scalars,
;; refs or computed values; the rendered structure never depends on them.
;; SVG lights fit the frame line. Without SVG, inherited one-cell ASCII `o'
;; marks show `x', `-' and `+' on hover, preserving the same action targets.
;;
;; Component: etaf-window-chrome (&key title mode show-minimize show-maximize show-close active on-minimize on-maximize on-restore on-close on-move drag-lock-modifier title-font-size font-family group ref class use)
;; Render a controlled title bar with minimize, zoom and close action
;; buttons; MODE may be a scalar, ref or computed and only changes classes.  The title bar forwards drag gestures to ON-MOVE; its
;; `drag-lock-modifier' defaults to `shift' for a release-independent drag.
;; Actions
;; only request caller-owned state transitions; `actions' and default slots
;; append custom controls/content. TITLE-FONT-SIZE and FONT-FAMILY default to
;; nil to inherit; an explicit size is a positive CSS reference pixel number.
;; The title, traffic lights and custom controls share the title-bar typography.
;; Within a positioned window, the font must fit its canvas's shared line height;
;; Ebox rejects a larger resolved font before publishing the candidate.

;; Component: etaf-window (&key title mode x y width height z-index visible min-width max-width min-height max-height resizable resize-edges resize-refs resize-use move-use on-move on-resize on-focus drag-lock-modifier title-font-size content-font-size font-family controls-group controls-active on-minimize on-maximize on-restore on-close show-minimize show-maximize show-close ref id chrome-ref class use overflow)
;; Compose a controlled Window shell from `etaf-resizable-panel' and
;; `etaf-window-chrome'.  MODE, geometry, visibility and callbacks remain
;; caller-owned.  Slots are `header', `actions', `default' and `footer'.  The
;; default slot is wrapped in one viewport region, so a Component rendered in
;; the body reads the space it was given as `(PIXELS . ROWS)` with
;; `etaf-viewport'.  The window adds no inset of its own: the body rectangle
;; reaches the frame's resize handles and content owns its inner spacing.
;; Maximizing or
;; minimizing never changes geometry or global focus/z-order policy.  MODE and
;; VISIBLE may be refs or computed values: their changes publish as Host
;; property bindings (mode classes, panel visibility and the collapsed content
;; column) without re-rendering the shell, so the Component is stateful and
;; requires a mounted Runtime rather than `etaf-render'.  ON-FOCUS
;; runs for body activation, through ETAF's explicit ancestor capture hook
;; when a nested body control is pressed, and when keyboard focus enters the
;; window, so Tab and arrows activate it like a click.  DRAG-LOCK-MODIFIER defaults to shift
;; and applies to both the title bar and all resize handles.  Set it to super
;; for a Super-modified press or nil to disable locking everywhere.
;; With focus anywhere in the window, M-arrows move it through the title
;; bar's ON-MOVE or MOVE-USE and M-S-arrows resize it through the right,
;; bottom or bottom-right handle, one cell per press; the edge handles are
;; not Tab stops.
;; TITLE-FONT-SIZE and CONTENT-FONT-SIZE default to nil and inherit independently;
;; positive CSS reference pixel numbers override only their own region.
;; FONT-FAMILY defaults to nil and otherwise selects the family for both regions.
;; All positioned content must fit the containing canvas's shared line height.
;; A larger resolved font is rejected by Ebox before publication; the previous
;; committed pixels and input remain available. Custom text may still select
;; fallback glyph fonts with different metrics even at an equal CSS font size.
;;
;; Component: etaf-taskbar (&key items active on-select on-launch launcher-label class)
;; Render a controlled taskbar for window items.  ITEMS use scalar :key and
;; string :label, with optional :state (`active', `minimized' or `error', or a
;; ref or computed of one) and :disabled.  Callers own window state; ON-SELECT receives a key and
;; ON-LAUNCH opens a caller-owned application launcher.  ACTIVE accepts a
;; scalar key, nil, ref or computed; matching items show selection.  Colors
;; come from the Desktop Theme tokens below; provide a Theme to restyle.
;;
;; Component: etaf-workspace-bar (&key workspaces active on-select on-add on-close add-label brand status layout-label layout-action settings-label settings-action class)
;; Render accessible workspace tabs.  WORKSPACES may be scalar keys or item
;; plists with :key/:label.  Callbacks request caller-owned workspace changes;
;; this Component creates no workspace state.  LAYOUT-LABEL/LAYOUT-ACTION and
;; SETTINGS-LABEL/SETTINGS-ACTION optionally add trailing caller-owned controls.
;; ACTIVE accepts a scalar key, nil, ref or computed.  STATUS accepts a string,
;; nil, ref or computed; nil clears status text.  LAYOUT-LABEL accepts a
;; string, ref or computed of strings; the layout control keeps a fixed width
;; so a changed label rewrites only its own text.  Reactive sources
;; remain caller-owned and are read at their retained Host properties or Text
;; payload.  Status occupies the remaining single-row space and clips excess
;; text; layout and settings actions stay at the right edge as status length
;; changes.
;;
;; Desktop Theme tokens.  The desktop Components (`etaf-taskbar',
;; `etaf-workspace-bar', `etaf-window', `etaf-splitter', `etaf-launcher',
;; `etaf-switcher' and their pickers) read these semantic tokens through
;; `etaf-theme-token' inside retained Host properties, so a Theme provided
;; with `etaf-theme-provide' (scalar, ref or computed) restyles the whole
;; shell through paint slots without re-rendering:
;;   `:ui-shell-bg' `:ui-shell-fg' `:ui-shell-muted-fg' `:ui-shell-item-fg'
;;   `:ui-shell-item-minimized-fg' (bars and their items),
;;   `:ui-accent' `:ui-accent-fg' `:ui-accent-soft-bg' (bar selection and the
;;   launcher control), `:ui-window-bg' `:ui-window-fg' `:ui-window-border'
;;   `:ui-window-title-bg' `:ui-window-title-fg' `:ui-window-title-active-fg'
;;   (window chrome; inactive traffic lights use `:ui-window-title-fg'),
;;   `:ui-divider-bg' (splitter dividers) and `:ui-picker-item-bg'
;;   `:ui-picker-item-fg' `:ui-picker-item-muted-fg' (launcher and switcher
;;   rows).  Dialogs keep using `:ui-panel-*'; a selected picker row, chip,
;;   radio, switch or checkbox mark paints `:ui-button-secondary-fg' on
;;   `:ui-button-secondary-bg', dialog tokens that a Desktop keeps crisp while
;;   it dims the shell tokens behind a modal.  Without a provided Theme the
;;   Components paint their light fallback colors.
;;
;; Component: etaf-launcher (&key open title items on-select on-close close-label backdrop)
;; Render a controlled modal application launcher from item plists.  The
;; caller owns the registry and OPEN state; ON-SELECT receives a selected key.
;; Items show their :label caption with an optional muted :description below
;; it.  The Dialog is centered and sized to its items.  BACKDROP defaults to
;; t; nil keeps the underlying surface painted so a Desktop can dim it through
;; its own Theme instead of covering it.
;;
;; Component: etaf-switcher (&key open title items selected on-select on-close close-label backdrop)
;; Render a controlled modal application/window switcher.  SELECTED marks the
;; caller-owned active item and ON-SELECT receives a key.  Presentation,
;; sizing and BACKDROP follow `etaf-launcher'.
;;
;; Component: etaf-splitter (&key orientation ratio min-ratio max-ratio on-change use class overlay z-index divider-content overlay-rect visible)
;; Render a controlled horizontal or vertical split with named `first' and
;; `second' slots.  RATIO remains caller-owned; ON-CHANGE receives divider
;; gestures and USE can install an ETAF Behavior for keyboard/pointer updates.
;; OVERLAY renders only the divider over caller-owned panes.  OVERLAY-RECT is an
;; optional exact positioned rectangle using :left/:width in `(px N)' and
;; :top/:height in `(lh N)'; it keeps nested or constrained dividers aligned
;; with the caller's pane allocation.  Without it the overlay follows RATIO.
;; With OVERLAY-RECT, the rectangle and its :left/:top/:width/:height entries,
;; Z-INDEX, DIVIDER-CONTENT and VISIBLE accept refs or computeds: the divider
;; binds them as retained Host properties, so a layout policy moves, relabels
;; or hides dividers by writing cells instead of re-rendering the tree.
;; VISIBLE defaults to t; a hidden divider keeps its identity and gestures off.
;; The focused divider steps like a one-cell drag with the arrows across it.
;;
;; Component: etaf-pane-resizer (&key size side min max on-change on-end line background)
;; Render a vertical divider that resizes an adjacent fixed-width pane. SIZE is
;; the pane's caller-owned width in pixels (a number, ref or computed). SIDE
;; `right' (default) places the divider on the pane's right so dragging right
;; widens it; `left' serves a pane to the divider's right. Each drag move passes
;; the candidate width, clamped to MIN and MAX pixels when given, to ON-CHANGE;
;; ON-END receives the final width. LINE (default t) draws a hairline in the
;; divider color beside the pane over BACKGROUND. The divider is wide enough to
;; grab and never moves other cells while dragging.  With a callback it is a
;; Tab stop whose Left and Right step the width one column.
;; Use (etaf-view (etaf-pane-resizer :size width :on-change #'set-width)).
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
;; Rows retain their application object identity. A replacement row updates
;; callbacks even with equal contents; its stable key preserves cell state.
;; Use inside (etaf-view (etaf-table ...)); keyword arguments are component props.
;;

;; Component: etaf-popover (&key open anchor placement width title on-close)
;; Show controlled OPEN content on Ebox's root layer, anchored to a unique
;; semantic ID. OPEN can be a value, ref or computed; ON-CLOSE requests closing
;; without owning application state. Default PLACEMENT is bottom-start and
;; WIDTH is (ch 32). Other placements follow Ebox's anchor contract. TITLE is
;; optional. Every floating surface shares one card anatomy: a one-row header
;; with the title under a hairline, a body padded by one row and two columns,
;; and a right-aligned footer row. Default and footer slots retain their
;; author Context and state.
;; Opening focuses the first eligible control (or the panel when empty).
;; TAB/Shift-TAB and arrow keys navigate within the panel; Escape/C-g request
;; close. Closing restores a still-valid prior focus. Shortcuts are buffer-local
;; and disposed with the open panel; they outrank application key maps,
;; including emulation maps, while it is open.  Outside controls remain
;; mouse-accessible.
;; The application root must reserve a canvas height for floating content.
;; Ebox owns clipping, flipping, occlusion and layout. No child frame is created.
;;
;; Component: etaf-dialog (&key open title width height compact close-label on-close backdrop)
;; Show a controlled modal panel using the same floating surface as Popover.
;; TITLE defaults to Dialog and WIDTH to (ch 48).  HEIGHT optionally fixes the
;; panel to `(lh N)' rows, bounded by the visible window.  COMPACT removes
;; the body's vertical air so short forms stay dense.  The panel centers in
;; the window that displays its buffer when that window is graphical.
;; The header shows TITLE and a pointer-only x that requests ON-CLOSE; initial
;; focus still lands on the first body control.  Default content and footer
;; slots compose ordinary Components; a secondary CLOSE-LABEL button (default
;; "Close") ends the footer and requests ON-CLOSE; CLOSE-LABEL nil omits it so
;; the footer slot orders every action, for example [Cancel] [Delete].  A fixed
;; HEIGHT needs the body rows plus five for header, body air and footer.
;; The opaque backdrop covers the root canvas, blocking covered controls and
;; their focus targets. It does not close on a backdrop click; a shell root
;; may call `etaf-ui-dismiss-outside-press' from its press callbacks to close
;; surfaces on outside presses. Keyboard
;; navigation, dismissal and focus return follow Popover. The backdrop uses
;; solid paint; Ebox does not provide alpha blending. Set BACKDROP nil for an
;; application-owned unpainted modal projection when the underlying surface
;; must remain visible. Dialogs own no form data.
;;
;; Component: etaf-media-viewer (&key open kind src source-size title subtitle caption duration on-close on-previous on-next autoplay)
;; Show one image, video or audio file in a controlled modal viewer over the
;; application, inside the same buffer.  KIND is `image' (default), `video'
;; or `audio'.  SRC is an `image' Host source (a file or image descriptor) or
;; an `etaf-video' source; for `audio' it is the audio file SRC played through
;; ffplay.  SOURCE-SIZE is the media's pixel (WIDTH . HEIGHT); without it the
;; viewer reads the image or probes the video once.  The media keeps its aspect
;; ratio and fits the live viewport, following window resizes; images are
;; not enlarged beyond their natural size, video fills the stage.  DURATION,
;; seconds, gives an audio file its total time.  The header
;; shows TITLE and SUBTITLE, default slot children (for example download or
;; share buttons) and a close control; an image's footer shows CAPTION, and
;; an audio stage shows it under the speaker placeholder.
;; Video and audio start when AUTOPLAY (default t) and get a transport bar:
;; play and pause, back and forward ten seconds, elapsed and total time, a seek
;; bar, the playback speed and sound.  Clicking the media toggles playback.
;; ON-PREVIOUS and ON-NEXT, when functions, add side arrows, the p/n keys and
;; two-finger swipes for browsing a gallery; with images the arrow keys
;; browse too, with video they seek five seconds.  Escape, C-g, q, the close
;; control and a press on the backdrop outside the header, media and footer
;; request ON-CLOSE.  Space or k toggles playback, j/l seek ten seconds, m
;; toggles sound and . cycles the speed.  While open the viewer's keys
;; outrank application keys, other printing keys do nothing, and focus
;; returns to the prior control on close.  The viewer covers the root
;; canvas's first viewport on a fixed dark scrim, so mount it in an
;; application whose root is one window tall, such as a (vh 100) shell.
;;
;; Component: etaf-reactions (&key items on-toggle choices add-label)
;; Render one row of controlled reaction chips, for example under a chat
;; message.  ITEMS are plists with a unique non-nil :key, a nonempty string
;; :label (usually an emoji), an optional natural :count shown after it and a
;; boolean :chosen that tints the chip with the accent; ITEMS may be a value
;; or ref.  Chosen and unchosen
;; chips share padding and weight, so toggling never moves a neighbour; only
;; a count gaining a digit widens its chip.  Pressing a chip calls ON-TOGGLE
;; with its key; the caller updates ITEMS.  CHOICES, an alist of (KEY . LABEL),
;; adds a trailing smile chip named ADD-LABEL (default "Add reaction") that
;; opens a Popover of the choices in rows of six; picking one closes it and
;; calls ON-TOGGLE with that key.  The row does not wrap, so keep ITEMS short
;; enough for its container.  Invalid props signal `etaf-view-error'.
;; Use (etaf-view (etaf-reactions :items items :on-toggle #'toggle)).
;;
;; Component: etaf-dropdown-menu (&key label items on-select disabled width icon placement)
;; Render a Button and an anchored Popover of menu items. LABEL defaults to
;; Actions; WIDTH defaults to (ch 28). ITEMS use etaf-menu's item contract and
;; may carry an :icon shown before the label. ICON makes the trigger that icon,
;; with LABEL as its help text and accessible name. PLACEMENT (default
;; bottom-start) follows etaf-popover.
;; Enabled selection closes the menu and invokes ON-SELECT once with its key.
;; Disabled items remain visible and cannot be activated or focused. Empty
;; menus or nil ON-SELECT disable the trigger. Open state and the unique anchor
;; belong to each retained Component; application data remains caller-owned.
;; Keyboard shortcuts and focus return follow Popover. Use native etaf-menu
;; when completion matching, rather than an in-buffer menu, suits the task.
;;
;; Component: etaf-badge (&key text variant)
;; Render compact semantic status text using neutral, success, warning, danger
;; or info styling. The value is caller-owned and may be reactive.
;;
;; Component: etaf-divider (&key orientation label)
;; Render a horizontal or vertical separator, optionally with a centered label.
;;
;; Component: etaf-progress (&key value max label variant)
;; Render a determinate progress bar. VALUE and MAX are numeric (or reactive)
;; with 0 <= VALUE <= MAX and MAX > 0. LABEL is optional.
;;
;; Component: etaf-alert (&key title message variant dismissible on-dismiss)
;; Render an alert with semantic styling. A dismissible alert invokes ON-DISMISS;
;; the caller decides whether its state remains visible.
;;
;; Component: etaf-statistic (&key label value trend)
;; Render a compact metric card from caller-owned display values.
;;
;; Component: etaf-empty (&key title description action-label on-action)
;; Render an empty state with optional action callback.
;;
;; Component: etaf-skeleton (&key width height)
;; Render a neutral loading placeholder without owning loading state.

;; Component: etaf-card (&key title description variant)
;; Render a reusable titled surface with default content slots.
;;
;; Component: etaf-avatar (&key name initials src size variant lines background shape)
;; Render a compact avatar with semantic color and accessible name.
;; SIZE is its width (`(ch N)' or an integer column count for round avatars);
;; LINES (default 3, a positive integer) its height, so a one- or two-line
;; list row can carry it. BACKGROUND, a color, replaces VARIANT with white
;; initials on that color, for per-person colors such as chat senders.
;; SRC is an optional photo: a local image file or an Emacs image descriptor
;; with :type and :data or :file. SHAPE `circle' (default) draws, on
;; graphical frames with SVG, the photo clipped to a disc, or the initials on
;; a colored disc when SRC is nil or unreadable; `square' and text frames use
;; an initials box with the initials on its (upper) middle line. Round images
;; are cached by source and cell size; pass `equal'-stable sources.
;;
;; Component: etaf-timeline (&key items)
;; Render chronological item plists containing :title, :content and :status.
;;
;; Component: etaf-tag (&key text variant closable on-close)
;; Render a compact semantic tag; an optional close action remains caller-owned.
;; A closable tag requires ON-CLOSE. It reports dismissal without removing
;; itself; the caller decides whether to retain it.
;;
;; Component: etaf-kbd (&key keys)
;; Render a keyboard shortcut as accessible keycaps from a nonempty string list.
;;
;; Component: etaf-steps (&key items current on-change)
;; Render ordered step buttons. ITEMS contain :key and :label; CURRENT and the
;; callback are controlled by the caller.
;; Keys and nonempty labels must be unique; CURRENT is a value/ref/computed
;; containing one of the keys. ON-CHANGE is optional and receives a selected key.
;;
;; Component: etaf-list (&key items on-select)
;; Render a selectable list. ITEMS contain :key, :title and optional
;; :description; selection is reported to ON-SELECT.
;; Keys are unique and titles are nonempty strings; an empty list is allowed.
;; Each row composes one Button with title/description content. ON-SELECT is
;; optional; no selection state is created by the List.
;;
;; Component: etaf-date-picker (&key value label placeholder on-change disabled bind)
;; Semantic date input on the catalog's native text field. The controlled
;; value is an ISO `YYYY-MM-DD' string or nil; typing a partial date keeps the
;; last accepted value and submitting rejects an invalid date with a readable
;; error instead of writing it.
;;
;; Component: etaf-tree (&key items expanded on-toggle on-select)
;; Render nested items with caller-owned expanded keys and selection callbacks.
;; Right opens and Left closes the focused branch through ON-TOGGLE.
;;
;; Component: etaf-calendar (&key month value on-change label)
;; Render a controlled month grid; MONTH is `(YEAR MONTH)' and ON-CHANGE gets
;; `(YEAR MONTH DAY)'.
;;
;; Component: etaf-command-palette (&key open title items on-select on-close)
;; Compose a modal Dialog and List for caller-owned command selection.
;;
;; Component: etaf-tabs (&key items active on-change variant)
;; Render controlled tabs from unique scalar keys and labels.  An item may
;; carry a scalar :count and a symbol :ref, so callers can address a tab by
;; name.  ON-CHANGE receives the selected key; content can be composed with
;; ordinary conditional Views.
;;
;; Component: etaf-accordion (&key items open on-toggle multiple)
;; Render controlled disclosure sections. Items contain :key, :label and
;; string or zero-argument function :content. OPEN is a list of expanded keys.
;;
;; Component: etaf-breadcrumb (&key items on-select)
;; Render a navigation trail of strings; ON-SELECT receives a zero-based index.
;;
;; Component: etaf-tooltip (&key open anchor text placement on-close)
;; Show controlled short text near an anchor using Popover placement. The caller
;; controls visibility; no second hover event system is introduced.
;;
;; Component: etaf-toast (&key open anchor message title variant on-close)
;; Show a controlled dismissible anchored notification. The caller owns its
;; lifecycle and message state.

;; Component: etaf-context-menu (&key label items on-select disabled width)
;; Compose a keyboard and mouse accessible context action trigger from the
;; DropdownMenu contract.
;;
;; Component: etaf-drawer (&key open title placement width modal on-close)
;; Show a controlled left or right side surface with default and footer slots.
;; PLACEMENT defaults to right, WIDTH to (ch 42), and MODAL to t. Width is
;; constrained to the root canvas. OPEN accepts a value/ref/computed; ON-CLOSE
;; must be a function. Focus, dismissal, return and disposal follow Dialog.
;;
;; Function: etaf-ui-dismiss-outside-press ()
;;;###autoload (autoload 'etaf-ui-dismiss-outside-press "etaf-ui")
;; Dismiss every mounted floating surface (dialog, launcher, switcher,
;; popover, menu or drawer) in the current event's Runtime whose panel does
;; not contain the pressed Host, requesting each one's ON-CLOSE, and return
;; the number dismissed.  Call it from the `:on-press' or `:on-press-capture'
;; callback of a Host enclosing the application, such as a shell root, to give
;; unpainted (`:backdrop' nil) modals and popovers click-outside dismissal.
;; A surface opened by the press being handled is not mounted yet and stays
;; open.  Outside a Host event callback it signals `etaf-event-error'.
;;
;; Function: etaf-ui-surfaces-open ()
;;;###autoload (autoload 'etaf-ui-surfaces-open "etaf-ui" nil t)
;; Mount the runnable floating-component example in *ETAF UI Surfaces* and
;; return its buffer. Interactive calls display it. Reopening resets its
;; application state; unmount the Runtime or close the buffer to dispose it.

;; Function: etaf-ui-gallery-open (&optional buffer-or-name)
;;;###autoload (autoload 'etaf-ui-gallery-open "etaf-ui" nil t)
;; Mount the integrated catalog Gallery and return its buffer. It exercises
;; layout, feedback, navigation, input, data and floating Components.  An
;; explicit name allows independent mounts; interactive calls display it.
;;
;; Function: etaf-ui-window-resize-open (&optional buffer-or-name)
;;;###autoload (autoload 'etaf-ui-window-resize-open "etaf-ui" nil t)
;; Mount a controlled catalog window with a fixed body and independent peer.
;; Interactive calls show the buffer. The title moves; eight native handles
;; resize; Shift locks and Escape restores the starting rectangle. Reopening
;; replaces only an existing example mount. Unmount or kill it to dispose.
;; This example is a GUI workload, not a performance certification.
;;
;; Component: etaf-ui-icon (&key name set size color face lines min-width help-echo on-press tab-index aria-label id class ref)
;; Render NAME in one standard row, or exactly two with :lines 2. SIZE defaults
;; to 1.0 and is clamped within those rows; font ascent and descent must each
;; fit the default baseline. MIN-WIDTH is in cells (default 2). ON-PRESS is a
;; zero-argument callback on the complete box, with ordinary ETAF focus/events.
;; A pressable icon is a Tab stop with TAB-INDEX (default 0); a negative
;; TAB-INDEX keeps it clickable but out of Tab order, for example when its
;; enclosing list already owns the keyboard. ARIA-LABEL names it in
;; `etaf-palette' and defaults to a string HELP-ECHO, then NAME.
;; FACE accepts a face name or plist; only foreground/background are used so
;; caller typography cannot enlarge the icon. COLOR overrides its foreground.
;; SVG uses currentColor and cached centered images. On graphical frames with
;; SVG, font sets draw their glyph as SVG text in the same canvas, so ink that
;; exceeds the font's declared ascent/descent is never clipped by the row.
;; Two-row icons use slices of one canvas. Without graphical SVG, font sets
;; use their clamped face as text; two-row icons reserve both rows and put a
;; line-safe text variant in the first row.
;; Resolve NAME in SET, then `etaf-ui-icon-default-set', then sys, then svg
;; (its line-safe text variant without graphical SVG), then show the name as
;; plain text (control/non-ASCII characters are escaped). Absent
;; fonts/glyphs follow the same lookup; terminal font sets use text variants.
;; An unknown explicitly requested/default set is a usage error, wrapped by
;; ETAF during rendering. Invalid geometry/callback props fail before publish.
;; Use (etaf-view (etaf-ui-icon :name 'play :set 'svg :on-press action)).
;;
;; Function: etaf-ui-icon (name &key set (size 1.0) color face (lines 1) (min-width 2) help-echo on-press tab-index aria-label id class ref)
;;;###autoload (autoload 'etaf-ui-icon "etaf-ui" nil nil)
;; Return the same typed icon View from ordinary Elisp with positional NAME.
;; Pass it directly to etaf-mount, or use the Component's :name form in the DSL.
;; The component contract above governs rendering, lookup and box ownership.
;;
;; Function: etaf-ui-icon-lines (name &key set (size 1.0) color face (lines 1))
;;;###autoload (autoload 'etaf-ui-icon-lines "etaf-ui" nil nil)
;; Return owned propertized strings for one or two standard icon rows.
;; Resolution, fallback and colouring match etaf-ui-icon. SIZE must be positive;
;; LINES must be 1 or 2. Invalid names/sets follow the icon component contract.
;; Resolve once in a Component binding and select these strings from retained
;; Host text expressions instead of adding a positioned overlay. Returned
;; strings are independent; shared image values must not be mutated.
;;
;; Component: etaf-ui-toggle-icon (&key value off on set size color on-color face lines min-width help-echo on-press tab-index aria-label id class ref)
;; Render one icon that switches between OFF and ON through retained Host
;; text instead of repainting the View. VALUE is a boolean or a reactive
;; source; both variants resolve while rendering and each row then reads
;; VALUE directly, so a change publishes a retained text update. OFF and ON
;; may name the same icon when only ON-COLOR differs, which turns a colour
;; state into the same retained update. ON-COLOR defaults to COLOR. SET,
;; SIZE, FACE, LINES, MIN-WIDTH (cells, default 2), HELP-ECHO, ON-PRESS,
;; TAB-INDEX, ID, CLASS and REF match `etaf-ui-icon'; the complete box is the
;; ON-PRESS target. ARIA-LABEL defaults to a string HELP-ECHO, then "OFF / ON".
;; Use (etaf-view (etaf-ui-toggle-icon :value playing :off 'play :on 'pause)).
;;
;; Variable: etaf-ui-icon-default-set
;; Registered fallback style, initially nerd. Bind or set it before rendering.
;; Registry changes/default changes take effect on the next render; existing
;; mounted values remain valid and are not implicitly rerendered.
;;
;; Function: etaf-ui-icon-set-register (name spec)
;;;###autoload (autoload 'etaf-ui-icon-set-register "etaf-ui" nil nil)
;; Register symbolic NAME with SPEC, replacing a previous registration, and
;; return NAME. Font SPEC: :kind font, :family string, positive float :height
;; relative to default, :glyphs alist of symbolic names to single glyphs.
;; SVG SPEC: :kind svg, :viewbox four numbers with positive width/height,
;; :paths alist of names to SVG bodies and/or :draw alist of names to nullary
;; functions returning bodies, :inset nonnegative pixels (default 2). Bodies
;; use currentColor; draw functions must be pure, and their output is cached.
;; Optional :fallback alist supplies printable ASCII strings; absent entries
;; display their name. Invalid specs signal user-error without replacement.
;; Treat stored specs as immutable; re-register to invalidate cached variants.
;; Font maps must contain actual glyphs, never substitute Unicode codepoints
;; for missing icons. The GUI check enforces actual family/coverage for every
;; registered name. Font sets share one face per frame/clamped size; SVG sets
;; share one image sizing policy. No style-specific branches are needed.
;;
;; Function: etaf-ui-icon-set-remove (name)
;;;###autoload (autoload 'etaf-ui-icon-set-remove "etaf-ui" nil nil)
;; Remove NAME and invalidate cached variants; absent NAME is harmless.
;; Return nil. Existing rendered values remain valid until the next render.
;;
;; Function: etaf-ui-icon-sets ()
;;;###autoload (autoload 'etaf-ui-icon-sets "etaf-ui" nil nil)
;; Return registered set names in registration order. Built-ins are nerd, fa,
;; material, octicons, sys and svg. Their semantic coverage can differ.
;;
;; Function: etaf-ui-icon-set-spec (name)
;;;###autoload (autoload 'etaf-ui-icon-set-spec "etaf-ui" nil nil)
;; Return the stored immutable SPEC or nil for an unregistered NAME.
;;
;; Function: etaf-ui-icon-names (&optional set)
;;;###autoload (autoload 'etaf-ui-icon-names "etaf-ui" nil nil)
;; Return SET's own names, or the union of all sets when nil. This query never
;; performs fallback lookup. Unknown non-nil SET signals user-error.
;;
;; Function: etaf-ui-icon-metrics (set &optional frame)
;;;###autoload (autoload 'etaf-ui-icon-metrics "etaf-ui" nil nil)
;; Return :family :height :line-pixel-height :line-height :fit for SET/FRAME
;; before clamping. Font row metrics include default ascent/descent; missing
;; fonts report nil pixel height/fit. In batch/TTY the declared relative height
;; gives an estimate, not a font-availability guarantee. SVG reports its line
;; box. FRAME defaults to selected-frame; an unknown SET signals user-error.

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
(require 'etaf-ui-icon)
(require 'etaf-ui-input)
(require 'etaf-ui-field)
(require 'etaf-ui-editor)
(require 'etaf-ui-selection)
(require 'etaf-ui-feedback)
(require 'etaf-ui-navigation)
(require 'etaf-ui-surface)
(require 'etaf-ui-reactions)
(require 'etaf-ui-media)
(require 'etaf-ui-table)
(require 'etaf-ui-data)
(require 'etaf-ui-tile-grid)
(require 'etaf-ui-text-grid)
(require 'etaf-ui-advanced)
(require 'etaf-ui-window)
(require 'etaf-ui-desktop)

(autoload 'etaf-ui-surfaces-open "examples/etaf-ui-surfaces" nil t)
(autoload 'etaf-ui-gallery-open "examples/etaf-ui-gallery" nil t)
(autoload 'etaf-ui-window-resize-open "examples/etaf-ui-window-resize" nil t)

(provide 'etaf-ui)
;;; etaf-ui.el ends here
