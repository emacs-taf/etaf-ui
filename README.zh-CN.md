# etaf-ui

`etaf-ui` 是 ETAF 的官方 Component 目录，是建立在 `etaf` 之上的可选独立包。它不增加第二套 Control 或 Widget 模型；Button、Checkbox、Label、Panel、DataGrid 都是使用同一套 View、属性、slot、事件和 Data 契约的普通 Component。

```elisp
(require 'etaf-ui)

(let ((done (etaf-ref nil)))
  (etaf-view
   (etaf-checkbox
    :checked (etaf-value done)
    :label "Done"
    :on-change (lambda (next) (setf (etaf-value done) next)))))
```

在该目录运行 `make check EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs`。
