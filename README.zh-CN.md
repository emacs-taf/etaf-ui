# etaf-ui

`etaf-ui` 是 ETAF 的官方 Component 目录，是建立在 `etaf` 之上的可选独立包。它不增加第二套 Control 或 Widget 模型；Button、Checkbox、Label、Panel、DataGrid 都是使用同一套 View、属性、slot、事件和 Data 契约的普通 Component。

```elisp
(require 'etaf-ui)

(let ((done (etaf-ref nil)))
  (etaf-view
   (panel :title "Account"
    (slot :name 'header
          (button :label "Save" :ref 'save-button
                  :on-press (lambda () (message "saved"))))
    (label :text "Preferences")
    (checkbox :checked (etaf-value done) :label "Done"
              :ref 'done-checkbox
              :on-change (lambda (next)
                           (setf (etaf-value done) next))))))
```

`.etaf` 文件的结构使用已注册的短标签（`panel`、`label`、`button`、
`checkbox`、`data-grid`）。配套 `.el` 文件负责响应式值、Action、Behavior
和回调；其中 `etaf-view` 也使用同一组短标签。Elisp 定义和 API 文档仍使用
规范的 `etaf-*` 名称。

Button 和 Checkbox 都是受控组件。`etaf-button` 支持 `:label`、
`:on-press`、`:disabled`、`:ref`，以及最小 presentation 属性
`:class`、`:color`、`:bgcolor`、`:border`、`:padding`、`:face`、
`:tab-index`、`:aria-label` 和公共 Behavior 列表 `:use`。启用按钮默认使用
`button` role 和 `tab-index 0`；禁用按钮仍显示标签和禁用样式，但没有 press
回调、Behavior，也不进入 tab 顺序。`etaf-checkbox` 支持 `:checked`、`:label`、`:on-change`、
`:disabled`、`:ref` 及相同的 presentation 属性。启用时它提供
`checkbox` role、稳定的 `:ref` 和 `tab-index 0`；`:on-change` 接收下一个
布尔值。禁用 checkbox 没有回调或 tab stop。

`etaf-number-input` 是一个受控的轻量输入组件；需要编辑数值时，它使用
Emacs 原生 minibuffer。它支持 `:value`、`:label`、`:on-change`、`:min`、
`:max`、`:ref` 和 `:disabled`，回调接收校验后的整数，ref 仍由调用方持有。

目录统一使用语义化的 Theme 色彩 vocabulary，主要 token 包括
`:ui-fg`、`:ui-bg`、`:ui-border`、`:ui-muted-fg`、`:ui-disabled-*`、
`:ui-button-primary-*`、`:ui-button-secondary-*`、`:ui-button-ghost-*`、
`:ui-checkbox-*`、`:ui-grid-*` 和 `:ui-panel-*`。应用通过 ETAF 的
`etaf-theme-provide` 提供这些 token；旧的 `:ui-button-color` 一类 alias
仍兼容。`etaf-ui` 不依赖 TP，也不直接依赖 renderer-specific palette
registry；如果应用想使用 TP 的亮/暗 palette 数据，应先通过可选的
`etaf-theme-tp` adapter 转成同一份 ETAF Theme plist，再交给 UI 目录。

Component 的 `:styles` 声明负责默认外观。调用者提供的非 nil presentation
属性会覆盖默认值；省略或传 nil 时，继承的 Theme/默认样式仍可生效。Button
只提供刻意收敛的 `primary`、`secondary`、`ghost` 三种视觉 variant；这是
视觉状态集合，不是第二套 widget 分类体系。

启用的 button 和 checkbox 共享同一套交互反馈：小手指针、原生 `mouse-face`
悬停反馈、可读的 `help-echo`、数字 tab stop 和语义 role。指针离开后 hover
自动结束，点击不会产生 retained 视觉状态。禁用控件保留文字和禁用样式，但
没有回调、指针激活或 tab stop。
显式 `:on-*` 回调和 Behavior 回调的组合由 Runtime 负责；UI 包只声明控件和
视觉状态。

间距由父布局负责，而不是由 Button 偷塞。相邻控件应放在带明确横向 `:gap`
的 `row`/`flex` 中，这样每个控件的 mouse-face 和命中范围才保持语义独立。

`etaf-label` 支持 `:text`、`:face`、`:class`、`:color`、`:bgcolor`、`:width`、
`:border`、`:padding` 和 `:ref`。`etaf-panel` 支持 `:title`、相同的
surface presentation 属性，并投影命名的 `header` slot 和默认 slot。

DataGrid 支持列描述、函数型 `:row-key`，以及可选的
`:loading-label`、`:error-label`、`:empty-label`、`:selected-key` 或函数型
`:row-selected-p`。提供 `:on-row-press` 后，每一行都是可交互 button：必须
提供 `:row-ref`，它对每一行返回非 nil 的稳定 Host ref；行会获得
`button` role 和 `tab-index 0`，且回调接收该行。没有 `:on-row-press` 时，
行没有回调或 tab stop。`:row-key` 仍然是 retained row 必须具备的非 nil
稳定标量 identity。DataGrid 按 row key 保留唯一 action closure，因此 selection
或 Data Range 更新不会为未变化的行重建 handler。
整数列 `:width` 表示可读字符容量，不是裸像素；DataGrid 原样使用 Ebox 原生字符单位，
并在非末列之间保留一个原生字符间距。

`etaf-pagination` 是受控 Data Component。它接收 Data controller 以及稳定的
`:previous-ref`、`:next-ref`，显示易读的 `←`/`→` 控件和 `Page N / M` 摘要；
加载中或已经位于首/末页时会禁用对应动作。它不拥有页码状态，并复用 Button
的交互契约。

键盘焦点使用 ETAF 的公共 Runtime 端口：用
`(etaf-focus-next runtime)` 在带数值且非负 `:tab-index` 的可见 Host 之间
移动；需要代码触发动作时使用
`(etaf-dispatch-event runtime ref 'press)`。禁用控件和不可交互的 DataGrid
行不会进入 tab 顺序。

在该目录运行 `make check EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs`。
