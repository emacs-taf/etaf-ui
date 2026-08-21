# 决策：由 `etaf-ui` 持有交互契约

## 背景

Playground 需要让 `.etaf` 结构和 Elisp 回调通过公共 ETAF Runtime 挂载后，
组件仍然清晰可见并可用键盘访问。原本的纯文本 Host 不像可操作控件，禁用
控件也可能看起来仍可聚焦；DataGrid 行还缺少用于 dispatch 和 focus 的公共
identity。

## 决策

Button 和 Checkbox 自己负责 disabled 语义：保留可见状态，但禁用时移除回调
和 tab index；启用时发布 role、稳定 ref 和默认 tab index。DataGrid 保留稳定
标量 `row-key` 校验，并要求交互行通过显式 `row-ref` 回调得到稳定 Host ref；
只有交互行发布 button 语义和 tab index。选中状态只使用最小的
`selected-key`/`row-selected-p` 属性。

这些规则属于目录组件，因为它们是组件不变量，而不是 Playground 的样式。
如果每个示例重新补齐，就会产生分叉的事件与焦点行为，并把错误隐藏在仅供
示例使用的补偿逻辑中。

DataGrid 动态行放在稳定的 body Host 下，增删行时不会使 retained header/footer
的 surface scope 失效。
