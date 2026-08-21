# Decision: Keep interaction contracts in `etaf-ui`

## Context

The playground needs components that remain visibly meaningful and keyboard
addressable when its `.etaf` structure and Elisp callbacks are mounted through
the public ETAF Runtime. Bare text Hosts made enabled controls hard to see,
while disabled controls could still look focusable. DataGrid rows also lacked a
public identity for dispatch and focus.

## Decision

Button and Checkbox own their disabled semantics: they keep visible state but
remove their callback and tab index when disabled. Enabled controls publish a
role, stable ref, and default tab index. DataGrid keeps stable scalar
`row-key` validation and requires an explicit `row-ref` callback for
interactive rows; only those rows publish button semantics and tab index.
Selection is represented by the small `selected-key`/`row-selected-p` props.

These rules belong in the catalog because they are component invariants, not
playground styling. Making each example re-add them would create divergent
event and focus behavior and would hide failures behind example-only
compensation.

The dynamic DataGrid rows are nested under a stable body Host so adding or
removing rows does not invalidate the retained header/footer surface scope.
