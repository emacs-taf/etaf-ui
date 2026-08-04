# etaf-ui

`etaf-ui` is the official ETAF Component catalog. It is a normal optional package above `etaf`; it does not add a second Control or Widget model. Button, Checkbox, Label, Panel, and DataGrid are all ordinary Components with the same View, props, slots, events, and Data contracts.

```elisp
(require 'etaf-ui)

(let ((done (etaf-ref nil)))
  (etaf-view
   (etaf-checkbox
    :checked (etaf-value done)
    :label "Done"
    :on-change (lambda (next) (setf (etaf-value done) next)))))
```

Run `make check EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs` from this directory.
