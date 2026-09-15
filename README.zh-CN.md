# etaf-ui

源码布局：将仓库根目录加入 `load-path`，然后 require 与包同名的入口。
入口 Commentary 列出公共 API 及用法；内部实现位于 `lisp/`。

`etaf-ui` 是 ETAF 的官方 Component 目录，是建立在 `etaf` 之上的可选独立包。它不增加第二套 Control 或 Widget 模型；Button、Checkbox、Label、Panel、DataGrid 都是使用同一套 View、属性、slot、事件和 Data 契约的普通 Component。


所有 View 都使用准确的注册名称：`etaf-panel`、`etaf-label`、`etaf-button` 和
`etaf-checkbox`。把下面完整例子放进启用 lexical-binding 的 `.el` 文件求值，
再切换到 `*etaf-preferences*` 使用控件。

<!-- etaf-example: preferences -->
```elisp
;;; -*- lexical-binding: t; -*-
(require 'etaf-ui)

(etaf-define-component demo-preferences ()
  :bindings ((done (etaf-ref nil))
             (saved (etaf-ref "Unsaved"))
             (rows (etaf-ref 3)))
  :view
  (etaf-panel :title "Account"
    (slot :name 'header
      (etaf-button :label "Save" :ref 'save-button
                   :on-press (lambda () (setf (etaf-value saved) "Saved"))))
    (etaf-label :text (etaf-value saved))
    (etaf-checkbox :bind done :label "Done" :ref 'done-checkbox)
    (etaf-number-input :bind rows :label "Rows" :ref 'rows-input :min 1 :max 10)
    (text (expr (if (etaf-value done) "Complete" "Pending")))))

(etaf-mount "*etaf-preferences*" (etaf-view (demo-preferences)))
```

[完整用法与接口契约](docs/manual.zh-CN.md)。

浮层界面可用 `etaf-popover`、`etaf-dropdown-menu` 和 `etaf-dialog` 组合普通控件
与 slot。运行 `M-x etaf-ui-surfaces-open` 打开[菜单与偏好设置示例](examples/etaf-ui-surfaces.el)。
定位和遮挡由 Ebox 负责，区域内键盘导航复用 Ebox 的共享焦点。

## 开发

克隆后运行 `make setup-hooks`。提交变更前运行 `make check`；`make structure-check` 用于快速检查目录、命名和引用。

`make check` 运行规范检查、编译及 [tests/acceptance.json](tests/acceptance.json) 中的公共验收场景。`make test` 运行同一套公共 API 测试。清单涵盖全部维护的 Lisp 测试。GUI 与性能验收使用独立入口。
