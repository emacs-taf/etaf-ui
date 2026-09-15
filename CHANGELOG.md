# Changelog

## Unreleased

### Changed

- DataGrid composes the same row Components as Table, including row layout,
  selection paint and custom cell state. ETAF owns automatic row references and
  publishes current callback inputs. Address rows by Host reference; callback
  object identity is no longer kept stable by a separate UI cache. Public
  DataGrid props and explicit row references are unchanged.

- DataGrid shows idle, background refresh and cancellation states. Refresh
  retains interactive rows; Pagination disables page changes while refreshing.
  Update ETAF together with UI for the asynchronous Data status contract.

### Fixed

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
