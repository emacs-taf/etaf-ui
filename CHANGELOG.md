# Changelog

## Unreleased

### Changed

- DataGrid shows idle, background refresh and cancellation states. Refresh
  retains interactive rows; Pagination disables page changes while refreshing.
  Update ETAF together with UI for the asynchronous Data status contract.


### Added

- Add TextInput and Select with controlled values or `:bind`. All native inputs, including NumberInput, use the shared target lifetime and focus boundary; update ETAF and Ebox together.

- Checkbox and NumberInput accept `:bind` with an existing writable ETAF ref.
  The controls read and update that same ref through their controlled interface.
  Explicit value or `:on-change` props conflict with a non-nil binding, including
  explicit nil. Existing value/callback usage remains available for business
  operations and transformations.
