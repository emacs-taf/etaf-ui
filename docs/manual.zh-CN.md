# etaf-ui 使用手册

[安装和最小示例](../README.zh-CN.md)。

## 按职责分类的组件目录

组件按其解决的问题分类。容器负责组织内容，反馈组件表达状态，浮层
组件负责定位和关闭，输入组件修改调用方持有的值。所有类别都使用同一套
ETAF View、props、slot、生命周期和 Ebox 宿主交互契约，因此可以组合也可以
独立使用。

| 类别 | 组件 | 所依赖的基础能力 |
| --- | --- | --- |
| 布局与容器 | `etaf-panel`、`etaf-card`、`etaf-divider` | Ebox flow/flex/grid 几何；ETAF 决定显示哪个分支 |
| 受控面板与窗口 | `etaf-resizable-panel`、`etaf-window-chrome`、`etaf-window` | Ebox 定位几何和 gesture；调用方持有坐标、模式和 z-order |
| 桌面导航与平铺 | `etaf-taskbar`、`etaf-workspace-bar`、`etaf-launcher`、`etaf-switcher`、`etaf-splitter`、`etaf-pane-resizer` | Ebox 焦点和 Host；调用方持有应用、窗口及布局状态 |
| 反馈与状态 | `etaf-label`、`etaf-badge`、`etaf-tag`、`etaf-kbd`、`etaf-progress`、`etaf-alert`、`etaf-statistic`、`etaf-empty`、`etaf-skeleton` | Ebox 文本和盒子绘制；调用方持有状态值 |
| 浮层 | `etaf-popover`、`etaf-tooltip`、`etaf-dropdown-menu`、`etaf-context-menu`、`etaf-toast`、`etaf-dialog`、`etaf-drawer` | Ebox 锚点、分层、遮挡和共享面板焦点 |
| 输入与操作 | `etaf-button`、`etaf-checkbox`、`etaf-radio`、`etaf-switch`、`etaf-segmented`、`etaf-slider`、`etaf-text-input`、`etaf-search-field`、`etaf-number-input`、`etaf-select`、`etaf-menu`、`etaf-pagination` | Ebox 目标与焦点；ETAF 管受控回调和值 |
| 导航与集合 | `etaf-tabs`、`etaf-accordion`、`etaf-breadcrumb`、`etaf-steps`、`etaf-tree` | Ebox flow 和焦点；ETAF 发布调用方持有的选择回调 |
| 数据展示 | `etaf-table`、`etaf-data-grid`、`etaf-pagination`、`etaf-list`、`etaf-avatar`、`etaf-timeline`、`etaf-calendar` | ETAF Data Controller 和 Ebox 保留行 |
| 高级组合 | `etaf-date-picker`、`etaf-command-palette` | 复用输入和 Dialog/List；调用方持有值和关闭状态 |

维护中的 Atelier Gallery 将每个类别组合在一个紧凑工作台中。运行
`M-x etaf-ui-gallery-open` 查看它，源码在
[`examples/etaf-ui-gallery.el`](../examples/etaf-ui-gallery.el)。Gallery 是组合验收，
不是另一个控件框架；组件必须可以独立使用，也不能复制 Ebox 的命中、焦点或布局状态。

Library 的两列根据可用宽度换行，各列按自己的内容高度排列。`etaf-list` 用 Button
的默认 slot 组合标题和说明，整个条目只有一个焦点与激活目标；内容不应嵌套其他
可交互控件。`etaf-steps` 的当前步骤和 Tag 的移除状态均由调用方持有。
Gallery 的 Collection browser 将 DataGrid 与 Pagination 连接到同一个 Data Controller。

运行 `make gui-check GUI_EXAMPLE=gallery`，通过当前 emacsclient 重复执行菜单、抽屉、
中文输入、选择、步骤、标签删除、列表和分页。该命令执行 Emacs 本地键盘和鼠标事件；
仍需查看实际截图，不代表操作系统输入法或延迟达标。

在工作区中可用通用工具单独检查同一页面上的连续交互：

```sh
python3 scripts/performance.py run --mode gui --scenario 'gallery.review.steady.*'
```

steady 场景在每组中保留同一个 Gallery，每次点击后验证勾选或取消勾选对应的进度。
原有 `gallery.review.callback` 和 `gallery.review.mouse` 测量重新挂载后的首次点击。
按顺序检查样本，可区分某个切换方向的回退与连续更新过程中不断积累的开销。
包的 `make perf-check` 已包含所有 Gallery 场景。

`gallery.actions.steady.*` 和 `gallery.more.steady.*` 反复打开、关闭菜单。
`gallery.toolbar.sequence.mouse` 在同一页面交替操作两种菜单与 Review，检查其他
组件运行后更新路径是否退化。`gallery.current.toolbar.mouse` 则直接使用当前选中的
Gallery，不重置状态。如果页面来自上一次测量，先通过 emacsclient 调用
`(taf-benchmark-detach-fixture)`，移交该页面的清理责任；当前页面适配器会保持它挂载。
操作顺序为 Actions 两次、Review 两次、More 两次、Review 两次。混合流程用于诊断，
Review 与菜单的独立场景仍分别按 50 ms、100 ms 验收。

## 受控格子网格

`etaf-tile-grid` 可用于棋盘、热力图或座位图，不持有业务数据。行数、列数和
格子宽度是正整数；坐标回调接收从零开始的行、列。`cell-text` 返回能装进
固定字符宽度的单行文字。把 ref 的读取放在 `cell-background` 和 `cell-text`
回调内，每个格子就保留自己的颜色和文字更新边界；相关写入用 `etaf-batch`。
`cell-ref` 可提供显式的公共焦点和事件地址，不传时使用实例独立的引用。
`on-cell-press` 同时用于点击和 TAB/RET；不传时网格只读。

```elisp
(let ((color (etaf-ref "#334155")))
  (etaf-mount "*Tiles*"
    (etaf-view
      (etaf-tile-grid
        :rows 6 :columns 12
        :cell-background (lambda (row column)
                           (if (and (= row 2) (= column 3))
                               (etaf-value color) "#172033"))
        :cell-text (lambda (_row _column) ".")
        :on-cell-press (lambda (row column)
                         (message "选择 %d,%d" row column))))))
```

定时器、搜索算法和数据保存归调用方所有。网格尺寸超过窗口时沿用正常的
布局和视口处理。完整属性契约见[根入口](../etaf-ui.el)。

## 选择 `:view` 还是 `:render`

两种写法都会返回同一种带类型的 ETAF View。通常应优先使用 `:view`：它用
DSL 描述宿主树，编译器可以检查组件 props、slot 和子节点位置。当需要先用
普通 Elisp 计算值、选择分支或生成一组 View 时，才使用 `:render`。此时让
`:render` 返回 `(etaf-view ...)`，并在子节点位置用 `(expr FORM)` 注入字符串、
View 或合法的 View 序列。

```elisp
(etaf-define-component greeting-view (&key name)
  :view
  (row :item-gap '(ch 1)
    (text "你好")
    (text (expr (format "%s！" name)))))

(etaf-define-component greeting-render (&key name items)
  :render
  (let ((caption (if name (format "你好，%s！" name) "你好！")))
    (etaf-view
     (column
       (text (expr caption))
       (expr
        (mapcar (lambda (item)
                  (etaf-view (etaf-label :text item)))
                items))))))
```

第一个定义是静态模板的推荐写法。第二个保留同一套 DSL，同时用普通 Elisp
处理条件和列表遍历；只有程序必须直接构造 View 树时才需要 `etaf-node`。
这不是两套渲染模型，而是编译边界：两者使用同一套 props、slot、保留身份
以及 Ebox 宿主生命周期。

`etaf-text-input` 是目录里唯一的文本字段：`:bind` 或 `value`/`:on-change`
提供受控字符串，`:rows` 区分单行输入与多行文本区。激活后在应用布局内
原生编辑该值，输入法、光标、选区和撤销都是原生的，
不打开 minibuffer、frame 或额外窗口。`etaf-number-input` 与
`etaf-date-picker` 是同一值契约在数字和 ISO 日期上的特化。`etaf-search-field` 把
无边框文本输入包在圆角胶囊里，可选放大镜图标和清除按钮，颜色来自 `:ui-search-*`
主题 token；点击胶囊任意位置即开始编辑：

```elisp
(etaf-view (etaf-search-field :bind query :icon t :placeholder "搜索"))
```

## 浮层与模态组合

短操作列表使用 buffer 内的 `etaf-dropdown-menu`；需要补全检索时仍可使用原生
`etaf-menu`。`etaf-popover` 把任意内容锚定到唯一的 Host `:id`，`etaf-dialog`
提供模态表单或任务区域。它们组合相同的 Button、输入控件和 slot，完整参数及
生命周期见[公共入口](../etaf-ui.el)。
设置表单可给 `etaf-dialog` 传入限定高度的 `:height '(lh N)` 和 `:compact t`。
面板会在显示目标 buffer 的图形窗口中居中，标题只占一行；内容超出时在面板内
滚动，较小的窗口会限制实际宽高。

```elisp
;;; -*- lexical-binding: t; -*-
(require 'etaf-ui)
(etaf-define-component preferences-dialog ()
  :bindings ((open (etaf-ref nil)) (enabled (etaf-ref t)))
  :view
  (column :width 'stretch :height '(vh 90)
    (etaf-button :label "偏好设置"
                 :on-press (lambda () (setf (etaf-value open) t)))
    (etaf-dialog :open open :title "偏好设置"
                 :on-close (lambda () (setf (etaf-value open) nil))
      (etaf-checkbox :bind enabled :label "接收通知")
      (slot :name 'footer
        (etaf-button :label "完成"
                     :on-press (lambda () (setf (etaf-value open) nil)))))))
(etaf-mount "*Preferences*" (etaf-view (preferences-dialog)))
```

根容器预留浮层画布，绝对定位面板不增大普通流的高度。Ebox 负责锚点定位、
空间允许时翻转、画布裁剪及遮挡。模态框的不透明背景阻止被覆盖的控件接收
命中与焦点。浮层须与画布使用相同行高；不提供透明混合或 child frame。
画布过小会裁剪内容，应用应预留足够高度并选择合适宽度。

打开后焦点进入首个有效控件，Tab／Shift-Tab 和上下方向键通过共享 Ebox
接口在面板内循环。Escape／C-g 调用 `on-close`，应用修改 `open` 接受关闭。
下拉菜单仅管理自身展开状态，选择后将启用项的 key 交给 `on-select`。
Popover 外部控件仍可用鼠标操作，外部点击不自动关闭；模态背景点击也不关闭。
原生 Emacs 命令仍然可用，这个交互策略不作为访问控制边界。

关闭和卸载释放 buffer 局部按键。嵌套面板恢复外层按键及仍有效的原焦点；
菜单打开模态框时保留最初入口作为返回路径。Ebox 始终是当前焦点的权威。
锚点不存在、面板未绘制时不截获按键。slot 保留声明方 Context，表单数据仍
由调用者 ref 管理；需要草稿时，应用分开保存草稿和已接受值，在 footer 的
保存回调中提交。

运行 `M-x etaf-ui-surfaces-open` 查看完整的[菜单、帮助和偏好设置示例](../examples/etaf-ui-surfaces.el)。
用 `make gui-check EMACSCLIENT=/path/to/emacsclient` 在已经打开的图形 Emacs 中
重复检查键盘与鼠标激活、禁用项、原生中文文本输入与取消、嵌套焦点返回、关闭和
卸载后重开。脚本保留示例可见；截图质量、操作系统输入法和前台输入延迟仍需单独验收。
重新打开重置示例状态，关闭 buffer 或调用 `etaf-unmount` 释放 Runtime。

### 媒体查看器

`etaf-media-viewer` 在同一 buffer 内以模态浮层显示一张图片或一段视频。
`open` 与当前条目由应用管理；媒体保持宽高比并适配当前窗口，随窗口尺寸
变化重新排布。视频带有播放控制栏：播放／暂停、前后跳十秒、已播放与总时长、
支持点击和拖动的进度条、播放速度和声音。传入 `:on-previous` 和 `:on-next`
时增加两侧箭头、p/n 键和双指滑动，用于浏览图集。

```elisp
;;; -*- lexical-binding: t; -*-
(require 'etaf-ui)
(etaf-define-component photo-viewer-demo ()
  :bindings ((open (etaf-ref nil)))
  :view
  (column :width 'stretch :height '(vh 100)
    (etaf-button :label "View"
                 :on-press (lambda () (setf (etaf-value open) t)))
    (etaf-media-viewer
     :open open :src (expand-file-name "images/splash.png" data-directory)
     :title "Splash"
     :on-close (lambda () (setf (etaf-value open) nil)))))
(etaf-mount "*Viewer*" (etaf-view (photo-viewer-demo)))
```

Escape、C-g、q、关闭按钮，以及鼠标点击标题栏、媒体和底栏之外的背景都会请求
`on-close`；键盘激活不会经由背景关闭。打开期间查看器按键优先于应用按键，
其他可打印键不起作用，buffer 光标隐藏，关闭后焦点回到原控件。遮罩覆盖根画布
的首个视口，因此应挂载在一个窗口高的根节点中。

### 表情回应

`etaf-reactions` 渲染一行表情回应标签，例如聊天消息下方的表情计数。
条目由调用方持有：`on-toggle` 报告被点击的 key 后由调用方更新条目。
已选中的标签使用强调色，尺寸不变。`:choices` 会在末尾增加一个与回应标签同样式的
标签，点击后弹出表情选择浮层，选项排成方格均匀、对齐的网格。

```elisp
;;; -*- lexical-binding: t; -*-
(require 'etaf-ui)
(etaf-define-component reactions-demo ()
  :bindings ((items (etaf-ref (list (list :key "👍" :label "👍" :count 3)))))
  :view
  (column :width 'stretch :height '(lh 10)
    (etaf-reactions
     :items items
     :choices '(("👍" . "👍") ("❤" . "❤") ("🎉" . "🎉"))
     :on-toggle
     (lambda (key)
       (let* ((old (cl-find key (etaf-value items)
                            :key (lambda (item) (plist-get item :key))
                            :test #'equal))
              (chosen (not (plist-get old :chosen)))
              (count (+ (or (plist-get old :count) 0) (if chosen 1 -1)))
              (rest (cl-remove old (etaf-value items))))
         (setf (etaf-value items)
               (if (> count 0)
                   (append rest (list (list :key key :label key
                                            :count count :chosen chosen)))
                 rest)))))))
(etaf-mount "*Reactions*" (etaf-view (reactions-demo)))
```

这一行不会换行，条目数量应与容器宽度相适应。

## 受控面板与窗口

面板和窗口默认继承所在环境的字体；没有上层显式覆盖时，使用 Emacs
当前的默认字体。`etaf-resizable-panel` 的 `font-size`、
`etaf-window-chrome` 的 `title-font-size`，以及 `etaf-window` 的
`title-font-size` / `content-font-size` 接受 nil（继承）或正数 CSS
参考像素。它不是 Emacs 的点数：16 CSS 像素等于 12 点。标题与正文
独立继承，覆盖一侧不会改变另一侧的默认字号。标题控件以及正文中的
标签、按钮、输入框和页脚继承各自区域的字体，应用显式样式仍可覆盖。
`font-family` 同样默认为 nil；字符串值覆盖继承的字体族。

定位窗口共享所在画布的物理文本行网格。显式字体必须满足画布的行高
限制；Ebox 在发布前拒绝解析后行高更大的字体，保留此前已提交的画面
和输入。相同 CSS 字号的自定义字形仍可能选择具有不同指标的后备字体，
所以仅检查字号不能证明实际物理行高。参见 Ebox 手册的
[定位组合契约](https://forgejo.vhkd.top/emacs-taf/ebox/src/branch/main/docs/manual.zh-CN.md)。

交通灯在 SVG 可用时使用受限于 frame 行高的图像；无 SVG 时使用继承
字体的单格 ASCII `o`，悬停显示 `x`、`-`、`+`，保持同一组动作目标。

`etaf-resizable-panel` 是定位面板的底层目录组件。`x`、`y`、`width`、
`height`、`z-index`、`visible` 以及最小／最大约束会直接交给 Ebox，值可以
是普通值、ref 或 computed。启用 `resizable` 和 `resize-edges` 后会生成边缘及
角落的 Host。面板拖拽时 `on-move` 收到 Ebox gesture plist，调整大小时
`on-resize` 收到 `(edge gesture)`。回调由调用方通过 ETAF 响应式 API 更新几何；
组件不保存坐标、不决定图层。标题栏可通过 `move-use`、各边缘可通过
`resize-use` 接收调用方提供的 ETAF Behavior；一次性场景仍可直接使用回调。

像下面的示例一样，直接把几何 ref 或 computed 传给外壳。实时读取归定位 Host
的属性，因此移动或缩放不会重建面板框架、内容 slot 或手势绑定。在构造父 View
时先读取这些值，则会让父级依赖每次几何变化。

`etaf-window-controls` 是可复用的 macOS 风格三色窗口按钮组件；相同的 `group`
会让 Ebox 在一次增量发布中同时更新三个 hover 符号。`etaf-window-chrome` 组合它
并提供受控标题栏以及最小化、最大化／恢复和关闭按钮，标题栏
把拖拽 gesture 交给 `on-move`。`etaf-window` 的 `drag-lock-modifier` 同时作用于
标题栏和所有启用的边、角缩放手柄，默认是 `shift`；设置为 `super` 使用 Super
修饰键，设置为 nil 禁用锁定。带修饰键首次按下后，第一次释放仍继续跟随；
下一次主按钮按下以该位置确认结束，Escape 取消。几何恢复由回调或受控 Behavior
负责。独立 `etaf-resizable-panel` 也接受此属性，但默认是 nil。
`etaf-window` 组合这两个组件，并提供 `header`、
`actions`、`default`、`footer` 四个 slot：

```elisp
(etaf-define-component inspector-window ()
  :bindings ((x (etaf-ref '(ch 6))) (y (etaf-ref '(lh 2)))
             (width (etaf-ref '(ch 42))) (height (etaf-ref '(lh 14)))
             (mode (etaf-ref 'normal)))
  :view
  (etaf-window :title "Inspector" :x x :y y :width width :height height
               :mode mode
               :on-move (lambda (_gesture) (ignore x y))
               :on-resize (lambda (_edge _gesture) (ignore x y width height))
               :on-maximize (lambda () (setf (etaf-value mode) 'maximized))
               :on-restore (lambda () (setf (etaf-value mode) 'normal))
    (etaf-label :text "Caller-owned content")))
```

真实应用的回调应把 gesture 转换为几何写入，也可以由 ETAF Behavior 提供；目录
组件只提供交互目标和视觉组合。最大化、最小化不会自动修改几何、z-order、焦点
策略或工作区归属。最小化只隐藏正文并保留它在 Component 树中，因此调用方拥有的
子状态仍然保持挂载。这些规则应在应用层（例如 `etaf-desktop`）中实现。

### 桌面导航与平铺控件

`etaf-taskbar` 和 `etaf-workspace-bar` 是受控的窗口栏和工作区栏。每个项目
plist 至少包含标量 `:key` 和字符串 `:label`；任务栏项目还可以声明
`:state`（`active`、`minimized` 或 `error`）以及 `:disabled`。`on-select`、
`on-add` 和 `on-close` 只请求调用方改变策略；`on-launch` 可以打开调用方拥有的
应用启动器。工作区栏还可以显示调用方提供的 `:brand` 和 `:status` 文本，用于桌面的菜单／状态带。

两个栏的 `:active` 都可以接收标量键、ref 或 computed。工作区 `:status` 可以
接收字符串、nil、ref 或 computed，nil 会清空状态文本。父 View 应直接传入这些
来源：选中状态由保留按钮的绘制属性读取，状态文本由 Text 表达式读取。项目增删
仍通过普通列表属性表达。两个栏也支持纯 `etaf-render`。
工作区状态占据单行中的剩余宽度；文本变化时，布局和设置操作固定在右侧。
过长或多行状态仅显示第一行中能够容纳的前缀，不修改调用方持有的值，也不自动
添加省略号。

`etaf-launcher` 和 `etaf-switcher` 提供受控的模态选择器。项目可以包含
`:description`、`:state` 和 `:disabled`；应用注册表、`open` ref 及应用／窗口
生命周期仍由调用方持有。`etaf-switcher` 用 `selected` 标记当前焦点项目。
Escape 和关闭按钮调用 `on-close`，继续使用 ETAF 的焦点返回和快捷键清理规则。

`etaf-splitter` 用命名的 `first` 和 `second` slot 呈现两个面板，并提供可通过
键盘聚焦的分隔条。`:orientation` 选择左右或上下分割，`:ratio` 由调用方控制。
`on-change` 接收分隔条 gesture；需要用指针或键盘修改比例时，可以通过 `:use`
传入 ETAF Behavior。组件不保存布局树、窗口身份或持久化状态，因此浮动管理器和
平铺管理器可以复用同一套控件。传入非 nil 的 `:overlay` 时只渲染分隔线，底层面板
仍由调用方拥有，适合窗口已经通过桌面布局定位、只需要复用分隔交互的场景。定位式
分隔线只绘制自身内容；调用方需提供 `:divider-content` 和位于面板上层的
`:z-index`。自行分配分割几何的调用方可传入 `:overlay-rect`：`:left`、`:width`
使用 `(px N)`，`:top`、`:height` 使用 `(lh N)`。矩形相对于定位父节点，
可使嵌套分割线与实际保留的间隔对齐；未传入时仍按 `:ratio` 定位。

`etaf-pane-resizer` 是一个用于固定宽度面板（例如会话旁的聊天列表）的细分隔条。像素
宽度由调用方持有：每次拖动都通过 `on-change` 报告候选宽度（受 `:min`、`:max` 限制），
`on-end` 收到最终宽度，例如用于保存。

```elisp
(etaf-view
 (row (box :width (list 'px (etaf-value width)) "列表")
      (etaf-pane-resizer :size width :min 240 :max 520
                         :on-change (lambda (w) (etaf-set-value width w)))
      (box :flex-grow 1 "会话")))
```

## 应用内原生编辑行为

ETAF Pi 等已有编辑窗格的集成可在可编辑 buffer 上复用 `etaf-ui-editor-mode`。
它提供空内容提示和编辑观察，保留原有 major mode、快捷键、补全、光标、选区和撤销；
不打开 minibuffer，也不在每次输入字符时调度渲染。

```elisp
(require 'etaf-ui)
(let ((buffer (get-buffer-create "*Embedded editor example*")))
  (with-current-buffer buffer
    (text-mode)
    (etaf-ui-editor-mode 1)
    (etaf-ui-editor-configure
     :placeholder "在这里输入"
     :on-change (lambda (editor)
                  (message "%d characters" (length (etaf-ui-editor-value editor))))))
```

集成方拥有该 buffer 的显示和释放。关闭行为或切换 major mode 时移除其提示和回调，
不删除正文。配置变化不触发编辑事件。观察回调收到 buffer 而非每次预先复制的字符串，
需要正文时再取；回调错误向上传播，已经接受的编辑仍保留，不得在回调里再次替换该编辑器。

异步操作由应用捕获正文及 `buffer-chars-modified-tick`，并决定成功后是否清空。
向 `etaf-ui-editor-replace` 传入该 tick，可拒绝修改之后才到达的更新，
即使用户编辑后撤销回相同字符串也不误清；失败时无需替换。
外部值与现值相同时保留选区、撤销和修改标记；真正的替换可以撤销。
显式更新可修改只读正文，用户原生输入仍受 `buffer-read-only` 保护。

这是共享的编辑行为，**尚不是可在任意布局中挂载的 Input/Textarea 组件**。
编辑窗格的位置仍由集成方管理。发送、确认及持久草稿属于应用，Ebox 不拥有编辑器或发送状态。
完整接口签名以根入口为准。

## 基础控件

内置状态标记使用 ASCII：Checkbox 和 Switch 显示 `[x]` / `[ ]`，Radio
显示 `(o)` / `( )`，选中项用 `*`，展开状态用 `v` / `>`。标记继承控件
字体，避免缺失符号字形触发较高的后备字体并撑高整条 Emacs 物理行。
应用自行提供的文字仍可能触发后备字体；CSS 字号相同不能证明实际字形
行高相同。


Core 不会自动加载 `.etaf`。可选的 Playground 读取 inert 结构源，并显式加载
已注册的 Elisp companion；这个文件格式不会生成更短的 Component alias。
普通本地回调不需要命名 Action，目录组件与应用自己定义的组件使用相同的 props 和 slot API。

Button 和 Checkbox 都是受控组件。`etaf-button` 支持 `:label`、
`:on-press`、`:disabled`、`:ref`，以及最小 presentation 属性
`:class`、`:color`、`:bgcolor`、`:border`、`:padding`、`:font-size`、`:font-weight`、`:help-echo`、
`:tab-index`、`:aria-label`、`:hover-content`、`:pointer` 和公共 Behavior 列表 `:use`。启用按钮默认使用
`button` role 和 `tab-index 0`；禁用按钮仍显示标签和禁用样式，但没有 press
回调、Behavior，也不进入 tab 顺序。`etaf-checkbox` 支持 `:checked`、`:label`、`:on-change`、
`:disabled`、`:ref` 及相同的 presentation 属性。启用时它提供
`checkbox` role、稳定的 `:ref` 和 `tab-index 0`；`:on-change` 接收下一个
布尔值。禁用 checkbox 没有回调或 tab stop。

`etaf-number-input` 是一个受控的轻量输入组件；需要编辑数值时，它使用
Emacs 原生 minibuffer。它支持 `:value`、`:label`、`:on-change`、`:min`、
`:max`、`:ref` 和 `:disabled`，回调接收校验后的整数，ref 仍由调用方持有。
当前值必须是整数或 nil，标签必须是字符串或 nil。上下界为数字或 nil；同时
指定时 `:min` 不能大于 `:max`。无效配置在初始化或新 props 发布前拒绝，
无效实时值在渲染时拒绝，错误会指出组件和属性。

`etaf-text-input` 原地显示值：激活后对该值开启原生编辑会话。Emacs 命令、
输入法、撤销、kill/yank 以及鼠标定位光标和选区都只作用于值本身；每次按键只
重排该字段，字段随折行或新增行长高，内边距和边框保持完整。应用绑定了的可打印
键仍会输入到字段里。单行字段按 RET 提交，多行字段按 RET 换行；Shift+RET 与
C-j 换行；C-c C-c 或 Ctrl+Return 提交；Escape、C-c C-k 和 C-g 取消并恢复激活
时的值。在字段外按下或点击会离开字段并保留文本。
`etaf-text-input-begin`、`etaf-text-input-end` 与 `etaf-text-input-active-p`
可用于程序化控制会话；`(etaf-text-input-end 'blur)` 离开字段且不触发回调。

字段嵌入应用时的集成注意：

- 编辑字段期间，应用其他状态照常发布。值、草稿与提交策略归应用，框架不存
  应用值。`:on-change` 收到每次编辑后的值。
- 卸载时活动字段直接离开并保留文本，不触发提交或取消回调。
- 字段 `:keymap` 中的绑定作为命令在应用 buffer 中执行；其他按键编辑值。

`etaf-select` 从普通 alist
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
仍兼容。应用需要亮/暗配色时，把语义 token 保存在自己持有的 plist 中，
使用 `etaf-theme-resolve-palette` 并显式传入 `light` 或 `dark` 模式。
解析结果遵循同一份 Theme contract，UI 目录不依赖渲染器的 palette registry。

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
[交互与迁移说明](https://gitea.gklazycat.heiyu.space/emacs-taf/etaf/src/branch/main/docs/manual.zh-CN.md#interaction-migration)。

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
| `etaf-button` | `:label`、`:on-press`、`:disabled`、`:id`、`:ref`、`:class`、`:color`、`:bgcolor`、`:border`、`:padding`、`:font-size`、`:font-weight`、`:tab-index`、`:aria-label`、`:help-echo`、`:hover-content`、`:hover-group`、`:pointer`、`:use`、`:variant` |
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

DataGrid 与 Table 组合相同的行组件。`:row-key` 提供非 nil 的稳定标量身份，
用于保留每一行及其自定义 cell 组件。省略 `:row-ref` 时，ETAF 为行提供实例
局部 Host 引用，多个 Grid 可以显示相同数据而不发生冲突。显式 `:row-ref`
函数提供调用方拥有的地址，必须为每个交互行返回非 nil 的稳定引用。

普通行回调捕获当前显示的行与处理函数；ETAF 随成功渲染发布它们，并在移除
该行时释放。应用不需要维护回调缓存或更新后的同步操作。通过 Host 引用寻址，
不依赖回调对象的身份。加载状态来自 Data Controller，行中的任意字段仍是
业务数据。
Table 与 DataGrid 直接迭代传入的行对象。替换行对象会更新输入，即使新旧内容
相等；保留 key 则保留 cell 状态和焦点。原地修改对象不会触发响应式更新。

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
自定义 cell 组件内部可以使用普通的无 key 宿主，不需要在每层节点重复行或列的 key。

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
传入非 nil 的 `:overlay` 时只渲染分隔线，底层面板仍由调用方拥有，适合窗口已经
通过桌面布局定位、只需要复用分隔交互的场景。
