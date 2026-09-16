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
;; Native root attributes :pointer, :help-echo and :hover-style request Ebox
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
;; default, muted, danger, success, strong or heading presentation.
;; Layout attributes such as :width, :padding, :border and :wrap-mode apply
;; to the Label's Box; its Text child inherits typography and color.
;; Use :width 'stretch to follow the containing width and :wrap-mode 'word
;; for wrapping prose. Reactive text and viewport changes use Ebox reflow.
;; Use inside (etaf-view (etaf-label ...)); keyword arguments are component props.
;;
;; Component: etaf-number-input (&key value label on-change disabled min max bind)
;; Render a controlled minibuffer-backed NumberInput using Button.
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
;; Component: etaf-text-input (&key value label placeholder on-change disabled bind)
;; Edit a controlled string with native `read-string'. Nil VALUE is empty.
;; LABEL defaults to "Text"; PLACEHOLDER defaults to "—" for empty values.
;; Both must be strings. VALUE may also be a ref/computed holding string or nil.
;; ON-CHANGE receives the accepted string, including empty input. Use :bind
;; for a writable ref under Checkbox's conflict and ownership rules.
;; Application validation belongs in ON-CHANGE or in the form's draft logic.
;; The Button entry supports TAB, RET and mouse activation. Native Emacs owns
;; editing and quit; Ebox owns focus return and retained target validity.
;; Cancel, error or invalidated ownership emits neither change nor observer.
;; Invalid props signal `etaf-view-error' identifying the Component/property.
;; Use inside (etaf-view (etaf-text-input ...)); no explicit Host ref is needed.
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
;; Component: etaf-select (&key value options label placeholder on-change disabled bind)
;; Choose a controlled value using native completion over OPTIONS labels.
;; OPTIONS is an alist of (VALUE . LABEL); values are unique symbols, numbers
;; or strings, labels unique nonempty strings. Nil is a valid option value.
;; A nil VALUE absent from OPTIONS displays PLACEHOLDER; other absent values
;; are errors. An empty list disables activation. LABEL defaults to "Select"
;; and PLACEHOLDER to "—"; both are strings. VALUE may be a ref/computed.
;; ON-CHANGE receives the accepted option value. :bind and native cancellation
;; follow TextInput; selection requires a matching label. Invalid props signal
;; contextual `etaf-view-error'. Use (etaf-view (etaf-select ...)).

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

;; Component: etaf-input (&key type value label placeholder on-change disabled bind min max step)
;; Render one controlled native input. TYPE is text, password, email, url,
;; number or date; specialized input components use the same value contract.
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
;; Rows retain their application object identity. A replacement row updates
;; callbacks even with equal contents; its stable key preserves cell state.
;; Use inside (etaf-view (etaf-table ...)); keyword arguments are component props.
;;

;; Component: etaf-popover (&key open anchor placement width title on-close)
;; Show controlled OPEN content on Ebox's root layer, anchored to a unique
;; semantic ID. OPEN can be a value, ref or computed; ON-CLOSE requests closing
;; without owning application state. Default PLACEMENT is bottom-start and
;; WIDTH is (ch 32). Other placements follow Ebox's anchor contract. TITLE is
;; optional. Default and footer slots retain their author Context and state.
;; Opening focuses the first eligible control (or the panel when empty).
;; TAB/Shift-TAB and arrow keys navigate within the panel; Escape/C-g request
;; close. Closing restores a still-valid prior focus. Shortcuts are buffer-local
;; and disposed with the open panel. Outside controls remain mouse-accessible.
;; The application root must reserve a canvas height for floating content.
;; Ebox owns clipping, flipping, occlusion and layout. No child frame is created.
;;
;; Component: etaf-dialog (&key open title width close-label on-close)
;; Show a controlled modal panel using the same floating surface as Popover.
;; TITLE defaults to Dialog and WIDTH to (ch 48). Default content and footer
;; slots compose ordinary Components; a CLOSE-LABEL button (default "Close")
;; requests ON-CLOSE.
;; The opaque backdrop covers the root canvas, blocking covered controls and
;; their focus targets. It does not close on a backdrop click. Keyboard
;; navigation, dismissal and focus return follow Popover. The backdrop uses
;; solid paint; Ebox does not provide alpha blending. Dialogs own no form data.
;;
;; Component: etaf-dropdown-menu (&key label items on-select disabled width)
;; Render a Button and an anchored Popover of menu items. LABEL defaults to
;; Actions; WIDTH defaults to (ch 28). ITEMS use etaf-menu's item contract.
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
;; Component: etaf-avatar (&key name initials size variant)
;; Render a compact initials avatar with semantic color and accessible name.
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
;; Component: etaf-tabs (&key items active on-change variant)
;; Render controlled tabs from unique scalar keys and labels. ON-CHANGE receives
;; the selected key; content can be composed with ordinary conditional Views.
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
;; Function: etaf-ui-surfaces-open ()
;;;###autoload (autoload 'etaf-ui-surfaces-open "etaf-ui" nil t)
;; Mount the runnable floating-component example in *ETAF UI Surfaces* and
;; return its buffer. Interactive calls display it. Reopening resets its
;; application state; unmount the Runtime or close the buffer to dispose it.

;; Function: etaf-ui-gallery-open ()
;;;###autoload (autoload 'etaf-ui-gallery-open "etaf-ui" nil t)
;; Mount the integrated catalog Gallery and return its buffer. It exercises
;; layout, feedback, navigation, input, data and floating Components.
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
(require 'etaf-ui-input)
(require 'etaf-ui-selection)
(require 'etaf-ui-feedback)
(require 'etaf-ui-navigation)
(require 'etaf-ui-surface)
(require 'etaf-ui-table)
(require 'etaf-ui-data)

(autoload 'etaf-ui-surfaces-open "examples/etaf-ui-surfaces" nil t)
(autoload 'etaf-ui-gallery-open "examples/etaf-ui-gallery" nil t)

(provide 'etaf-ui)
;;; etaf-ui.el ends here
