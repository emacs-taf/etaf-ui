# etaf-ui 使用手册

[安装和最小示例](../README.zh-CN.md)。


Core 不会自动加载 `.etaf`。可选的 Playground 读取 inert 结构源，并显式加载
已注册的 Elisp companion；这个文件格式不会生成更短的 Component alias。
普通本地回调不需要命名 Action，目录组件与应用自己定义的组件使用相同的 props 和 slot API。

Button 和 Checkbox 都是受控组件。`etaf-button` 支持 `:label`、
`:on-press`、`:disabled`、`:ref`，以及最小 presentation 属性
`:class`、`:color`、`:bgcolor`、`:border`、`:padding`、`:font-weight`、
`:tab-index`、`:aria-label` 和公共 Behavior 列表 `:use`。启用按钮默认使用
`button` role 和 `tab-index 0`；禁用按钮仍显示标签和禁用样式，但没有 press
回调、Behavior，也不进入 tab 顺序。`etaf-checkbox` 支持 `:checked`、`:label`、`:on-change`、
`:disabled`、`:ref` 及相同的 presentation 属性。启用时它提供
`checkbox` role、稳定的 `:ref` 和 `tab-index 0`；`:on-change` 接收下一个
布尔值。禁用 checkbox 没有回调或 tab stop。

`etaf-number-input` 是一个受控的轻量输入组件；需要编辑数值时，它使用
Emacs 原生 minibuffer。它支持 `:value`、`:label`、`:on-change`、`:min`、
`:max`、`:ref` 和 `:disabled`，回调接收校验后的整数，ref 仍由调用方持有。

`etaf-text-input` 使用原生 minibuffer 编辑字符串，`etaf-select` 从普通 alist
选择值，例如 `((nil . "进行中") (t . "已完成"))`。两者使用 `:value`／
`:on-change` 或 `:bind`，组合相同的 Button 入口。TAB 到达入口，RET 或鼠标
打开原生输入；`C-g` 取消且不触发修改回调或附加的 press 观察者。关闭后焦点
回到存续入口；入口所属挂载消失、被禁用或不可访问时，输入结果取消。原生
Emacs 管理输入法、光标、选区和撤销，Ebox 继续持有渲染内容。

`etaf-menu` 组合相同的 Button 与原生输入边界，禁用项不进入原生补全候选。
确认对话框直接组合在操作回调中，不需要额外的状态模型：

```elisp
(etaf-define-component task-actions ()
  :bindings ((done (etaf-ref nil)) (result (etaf-ref "准备就绪")))
  :view
  (column
   (etaf-checkbox :label "完成" :bind done)
   (etaf-menu :label "操作"
              :items (list '(:key edit :label "编辑")
                           (list :key 'delete :label "删除" :disabled (not (etaf-value done))))
              :on-select (lambda (action)
                           (pcase action
                             ('edit (setf (etaf-value result) "正在编辑"))
                             ('delete (when (etaf-confirm-dialog "删除这个任务？")
                                        (setf (etaf-value result) "已删除"))))))
   (etaf-label :text (etaf-value result))))

(etaf-mount "*task-actions*" (etaf-view (task-actions)))
```

调用者持有菜单项和业务回调。确认返回布尔值；回答 no 不改数据，`C-g` 中断
当前回调。菜单取消、确认和普通输入都通过 Ebox 将焦点恢复到存续入口。
如果操作随后删除入口，按 Ebox 的普通焦点移除规则处理。精确契约见
[入口文件](../etaf-ui.el)。

表单可以使用普通 ref 保存草稿，并在保存前校验：

```elisp
(etaf-define-component task-draft ()
  :bindings ((title (etaf-ref "新任务")) (done (etaf-ref nil)))
  :view
  (column :item-gap '(lh 1)
   (etaf-text-input :label "标题" :bind title)
   (etaf-select :label "状态" :bind done
                :options '((nil . "进行中") (t . "已完成")))
   (etaf-label :variant 'danger
               :text (if (equal (etaf-value title) "") "标题不能为空" ""))))
```

TextInput 接受空文本，字段校验由表单负责。Select 的标签和值必须分别唯一；
nil 可以作为显式选项值。空选项列表禁用入口。精确属性和错误契约见入口文件。
Task Workbench 演示草稿隔离、字段错误、保存／取消，以及切换任务前确认放弃修改。

需要直接修改一个已有 ref 时，可以使用 `:bind`：

```elisp
(etaf-define-component preferences ()
  :bindings ((done (etaf-ref nil)) (rows (etaf-ref 3)))
  :view
  (column
   (etaf-checkbox :label "Done" :bind done)
   (etaf-number-input :label "Rows" :bind rows :min 1 :max 10)))
```

这是 UI 组件的普通属性，不是新的 View 指令。Checkbox 将 ref 用作 checked
来源，TextInput、Select 和 NumberInput 将其用作 value 来源，修改回调写回同一个 ref。外部写入
也会更新控件，不产生第二份状态。禁用控件不能写入；取消或校验失败不改值。
卸载释放控件的订阅与回调，ref 仍归调用者；失败发布保留旧绑定目标。

非 nil `:bind` 必须是可写 ref，不能同时显式传入 `:checked`／`:value` 或
`:on-change`，即使它们是 nil。冲突以 `etaf-view-error` 报告组件、属性、
收到的值和期望输入。`:bind nil` 等同于不使用绑定。`:on-press` 仍按既有
顺序追加执行，可以观察修改后的值。需要业务校验、值转换或数据库操作时，
使用原有的值与 `:on-change` 接口；不要把这些操作藏入 ref 绑定。

目录统一使用语义化的 Theme 色彩 vocabulary，主要 token 包括
`:ui-fg`、`:ui-bg`、`:ui-border`、`:ui-muted-fg`、`:ui-disabled-*`、
`:ui-button-primary-*`、`:ui-button-secondary-*`、`:ui-button-ghost-*`、
`:ui-checkbox-*`、`:ui-table-*`、`:ui-data-grid-error-fg`、
`:ui-pagination-muted-fg` 和 `:ui-panel-*`。应用通过 ETAF 的
`etaf-theme-provide` 提供这些 token；旧的 `:ui-button-color` 一类 alias
仍兼容。`etaf-ui` 不依赖 TP，也不直接依赖 renderer-specific palette
registry；如果应用想使用 TP 的亮/暗 palette 数据，应先通过可选的
`etaf-theme-tp` adapter 转成同一份 ETAF Theme plist，再交给 UI 目录。

Component 的 `:styles` 声明负责默认外观。调用者提供的非 nil presentation
属性覆盖普通默认值，importance 仍遵循 ECSS；省略或传 nil 时，继承的 Theme/默认样式仍可生效。Button
只提供刻意收敛的 `primary`、`secondary`、`ghost` 三种视觉 variant；这是
视觉状态集合，不是第二套 widget 分类体系。

启用的 Button 与 Checkbox 提供数字 tab stop 和语义 role。禁用控件保留文字和
禁用样式，同时阻止激活与 tab 导航。显式 `:on-*` 回调和 Behavior 回调由 Runtime
组合；UI 声明控件与视觉状态。

需要原生反馈时，可向控件传入 `:pointer 'hand :help-echo "保存修改"
:hover-style '(:text-decoration-line underline)`。这些根属性经 ETAF 使用 Ebox
能力，TextInput、NumberInput、Select 和 Menu 通过 Button 组合也支持它们。
省略属性保留继承的反馈，显式 nil 移除对应能力。需要禁用时隐藏反馈，应让这些
属性读取同一个禁用状态。指针离开后悬停结束，不产生 ETAF 保留视觉状态。

间距由父布局负责：`row` 和 `column` 使用 `:item-gap`，例如
`(row :item-gap '(ch 1) ...)`；`flex` 和 `grid` 使用 `:gap`。尤其需要将 `row :gap`
迁移为 `row :item-gap`。相邻控件保留明确间距，让 hover 和命中范围各自独立。

根事件透传按顺序追加：业务动作、由内到外的 wrapper callback、最后按声明顺序
运行的 Behavior。给 Checkbox 增加 `:on-press` 不会替换它的 `:on-change` 转换。
每个声明执行一次，错误会中断后续回调。wrapper 的 `:use` 列表顺序连接，重复
Behavior name 在安装前报错。

禁用输入取 OR，外层 nil 不能启用内部已经禁用的控件。禁用时 dispatch 和 focus
抛出 `etaf-event-error`，禁用 cell 控件会阻止指针激活落到父行，输入 Behavior
也不会安装。透传 `:role` 或 `:aria-checked` 等组件所有的 aria 状态时，冲突值会
导致输入错误；调用方仍可覆盖 `:aria-label` 与 `:aria-description`。完整规则见
[交互与迁移说明](https://gitea.gklazycat.heiyu.space/geekinney/etaf/src/branch/main/docs/manual.zh-CN.md#interaction-migration)。

`etaf-label` 支持 `:text`、`:class`、`:color`、`:bgcolor`、`:font-weight`、
`:width`、`:border`、`:padding`、`:wrap-mode` 和 `:ref`。Box 负责布局，
内部 Text 继承字体和颜色。随父容器宽度换行的段落可写为
`(etaf-label :text description :width 'stretch :wrap-mode 'word)`。
`description` 可以是普通值、ref 或 computed；更新会重新排版同一个 Label。
`:wrap-mode 'none` 配合 `:overflow 'hidden` 表示不软换行并裁剪超宽内容；
短标签可以省略几何属性，使用内容固有尺寸。只需要 Text 而不需要布局容器时，
直接使用 `text` Host。
`etaf-panel` 支持 `:title`、相同的
surface presentation 属性，并投影命名的 `header` slot 和默认 slot。

<!-- M0b1: business-props -->
公共 Component 的 business props 由实际定义导出，并与透传的 Host 属性分开：

| Component | Business props |
| --- | --- |
| `etaf-label` | `:text`、`:variant` |
| `etaf-button` | `:label`、`:on-press`、`:disabled`、`:ref`、`:class`、`:color`、`:bgcolor`、`:border`、`:padding`、`:font-weight`、`:tab-index`、`:aria-label`、`:use`、`:variant` |
| `etaf-checkbox` | `:checked`、`:label`、`:on-change`、`:disabled`、`:bind` |
| `etaf-panel` | `:title`、`:variant` |
| `etaf-number-input` | `:value`、`:label`、`:on-change`、`:disabled`、`:min`、`:max`、`:bind` |
| `etaf-table` | `:columns`、`:rows`、`:row-key`、`:row-ref`、`:on-row-press`、`:row-selected-p` |
| `etaf-data-grid` | `:controller`、`:columns`、`:row-key`、`:on-row-press`、`:row-ref`、`:row-selected-p`、`:loading-label`、`:error-label`、`:empty-label` |
| `etaf-pagination` | `:controller`、`:previous-ref`、`:next-ref`、`:previous-label`、`:next-label`、`:class`、`:color`、`:bgcolor`、`:border`、`:padding`、`:aria-label` |

<!-- M0b1: single-host-root -->
目录中的每个公共 Component 都只挂载一个 Host root。未被作为 business prop
消费的所有合法 Host 属性（例如 `:ref`、`:class` 和 `:aria-label`）都会透传到
该 root；透传规则并不意味着这些属性都是每个 Component 的 business prop。

DataGrid 支持列描述、函数型 `:row-key`，以及可选的
`:loading-label`、`:error-label`、`:empty-label` 或函数型
`:row-selected-p`。提供 `:on-row-press` 后，每一行都是带 `button` role 和
`tab-index 0` 的可交互 button，且回调接收该行；没有 `:on-row-press` 时，行
没有回调或 tab stop。

`etaf-table` 的交互行也可省略 `:row-ref`，框架会提供属于当前保留实例的稳定引用。
只有外部 focus、测试或集成需要直接寻址时才提供 ref，不要根据行文字拼接全局
symbol。row key 负责数据身份，ref 负责交互 Host 地址。

DataGrid 在首次请求前显示 `Not loaded.`；后台刷新保留可交互的旧行，并显示
`:loading-label` 或 `Refreshing...`。已有行在等待写入、失败和取消后同样保留显示
和交互；状态显示在行列表上方。取消显示 `:error-label` 或 `Loading cancelled.`，
错误和首次加载沿用现有标签。Pagination 在加载和刷新期间禁用翻页。Controller
由调用者拥有，取消和重载使用其公共 API；UI 不维护第二份请求状态。

<!-- M0b1: row-ref-optional -->
DataGrid 的 `:row-ref` 是可选项。交互式 grid 省略它时，DataGrid 会根据
controller 持有的 row identity 派生稳定的内部 Host ref。fallback ref 不会
进入全局 symbol table，并按每个 retained DataGrid instance 隔离，因此多个 grid
可以安全复用相同行 identity；显式提供它时，该回调拥有 identity，并且必须为
每一行返回非 nil 的稳定 Host ref。
`:row-key` 仍然是 retained row 必须具备的非 nil 稳定标量 identity。
DataGrid 按 row key 保留唯一 action closure，因此 selection 或 Data Range
更新不会为未变化的行重建 handler。
整数列 `:width` 表示可读字符容量，不是裸像素；DataGrid 原样使用 Ebox 原生字符单位，
并在非末列之间保留一个原生字符间距。使用 `:width '(fr 1)` 让列填充剩余宽度；
多个 fractional 列按正数权重分配这部分空间。例如让
`(:key :title :width (fr 1))` 与
`(:key :actions :width 22 :cell render-actions)` 配合，可以在保留操作控件空间的
同时自适应标题宽度。表头和数据行使用相同的轨道及间距。自适应 cell 按分配的
宽度裁剪，不会挤宽相邻列。固定列仍保留声明的空间，父布局需要容纳这些控件
及列间距。

自定义 cell 的列宽在固定值与 fractional 值之间切换时，其 Component 状态保持。
全固定列的纯文本表格仍保留紧凑的文本渲染路径。

### 自定义 cell 与列迁移

Table 与 DataGrid 共用列契约。每一列都必须有唯一且非 nil 的 `:key`
（symbol、整数或字符串），纯展示列也一样。默认 cell 将该字段显示为文字。
`:cell` 函数接收一个 row，返回 nil、字符串、typed Host 或 Component View，
或这些值组成的 proper sequence。Table 拥有 cell 宽度并裁剪溢出；纯文本表格
继续使用原有的紧凑表示。

下面将 `:name` 字段用两个不同的 column key 展示，并在第三列放入普通 Button。
行选择与 Open 按钮分别执行自己的动作：

<!-- etaf-example: cells -->
```elisp
;;; -*- lexical-binding: t; -*-
(require 'etaf-ui)

(etaf-mount
 "*etaf-cell-demo*"
 (etaf-view
  (etaf-table
   :rows '((:id 1 :name "Ada"))
   :row-key (lambda (row) (plist-get row :id))
   :on-row-press (lambda (row) (message "Select %s" (plist-get row :name)))
   :columns
   (list
    '(:key :name :label "Name" :width 12)
    (list :key :name-upper :label "Uppercase" :width 12
          :cell (lambda (row) (upcase (plist-get row :name))))
    (list :key :open :label "Action" :width 10
          :cell
          (lambda (row)
            (etaf-view
             (etaf-button
              :label "Open"
              :on-press (lambda ()
                          (message "Open %s" (plist-get row :name)))))))))))
```

迁移重复字段列时，保留一列的 `:key :name`，为另一列指定 `:name-upper` 等唯一
key，再通过 `:cell` 读取原来的 `:name` 字段。缺失或重复 column key 都会报错。
row key 与 column key 让 cell 身份在重排时保留；改变 key 会替换该 cell 实例。

cell 函数使用 row 参数与普通词法捕获，Context 来自消费它的 Table/Grid 挂载
位置，不会恢复作者的 props、`etaf-state` 或私有样式。cell 需要自己的状态、样式
或生命周期时，返回普通 Component，在它的 `:bindings` 或 `:setup` 中创建持久 ref 和 watch。
若有意共享作者的 ref，应在创建回调前捕获稳定句柄；不要在每次 cell 函数调用时
创建持久状态。

`etaf-pagination` 是受控 Data Component。它接收 Data controller 以及稳定的
`:previous-ref`、`:next-ref`，使用带内边距的 secondary Button（`‹ Previous` /
`Next ›`），中间显示 `Page N / M` 与条数摘要。空间不足时，完整控件和摘要
自然换行。加载中或已经位于首/末页时会禁用对应动作。它不拥有页码状态，
并复用 Button 的交互契约和 Theme token。可选的 `:previous-label`、
`:next-label` 替换完整按钮文案，例如 `"‹ 上一页"`、`"下一页 ›"`；稳定的英文
无障碍标签保持不变。

键盘焦点使用 ETAF 的公共 Runtime 端口：用
`(etaf-focus-next runtime)` 在带数值且非负 `:tab-index` 的可见 Host 之间
移动；需要代码触发动作时使用
`(etaf-dispatch-event runtime ref 'press)`。禁用控件和不可交互的 DataGrid
行不会进入 tab 顺序。

在该目录运行 `make check EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs`。
