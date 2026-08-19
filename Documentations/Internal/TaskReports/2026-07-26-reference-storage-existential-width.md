# 2026-07-26 引用存储（weak/unowned）对 existential 的宽度修复

## 问题

用户报告 `SwiftUI.StyledTextResponder.gestureGraph` 的字段偏移对不上：RuntimeViewer 与
一份一周前生成的 `swift-section` dump 都显示 `0x128`，但用户看到的反汇编是 `0x120`，怀疑
工具多算了 8 字节。

排查中用户先后补充两条关键信息：iOS 26 系统上看到的是 `0x128`、当前 macOS 上看到的也是
`0x128`。结论因此反转——**真值是 `0x128`，当前 main 算成 `0x120`，是引擎少算了 8 字节**，
用户截图里那份旧输出在这一行上反而是对的。

## 调研

### 钉死真值

用 iOS 26.5 模拟器 runtime 的 `SwiftUICore`（独立文件，非 dyld cache，可直接 `otool`）
逐个反汇编访问器取真实偏移：

```
gestureGraph.setter      ldr x8, [x20, #0x128]   → 0x128
childSubgraph.getter     add x0, x20, #0x118     → 0x118
childViewSubgraph.getter add x0, x20, #0x120     → 0x120
viewSubgraph.getter      ldr x0, [x20, #0x88]    → 0x88
helper.getter            add x0, x20, #0x90      → 0x90
relatedAttribute.getter  ldr w0, [x20, #0x28]    → _view 在 0x28
```

再用 Python 解析 Mach-O，读 `_$s7SwiftUI19StyledTextResponderCN` 的 class metadata：
`instanceSize = 0x148`，恰等于最后一个字段 `0x140 + 8`，完成闭环。

真值与当时 main 的对照（main 每项 −8）：

| 字段 | 真值 | main（修复前） |
|---|---|---|
| `_view` | `0x28` | `0x20` |
| `inputs` | `0x30` | `0x28` |
| `viewSubgraph` | `0x88` | `0x80` |
| `helper` | `0x90` | `0x88` |
| `gestureGraph` | `0x128` | `0x120` |

### 定位

一开始怀疑 `helper`（`ContentResponderHelper<ShapeStyledResponderData<StyledTextContentView>>`）
里的 `data: A?` 算小了，写最小复现验证 `Optional<ShapeStyledResponderData<…>>` 的真实大小
——结果是 32，与引擎一致，说明 `helper` 内部是对的。改看它前面的字段，用 `_ViewInputs`
各字段的 getter 反汇编逐项核对（`preferences 0x30` / `transform 0x3c` / `size 0x48` /
`containerSize 0x50`）也全对。最后落到 `_view` 的真实偏移 `0x28` 上：**基类
`ViewResponder` 的实例大小真值是 40，引擎算 32**。

`ViewResponder` 的两个存储属性是：

```swift
weak var host: (any ViewGraphDelegate)?   // ViewGraphDelegate 是协议
weak var parent: ViewResponder?
```

`host` 是 **weak 的 class-bound existential**，真实占两个字（对象引用 + 协议见证表指针）。
最小复现确认规则：

```
weak var x: (any P)?        → 16    weak var x: AnyObject?        → 8
weak var x: (any P & Q)?    → 24    weak var x: (any @objc P)?    → 8
unowned / unowned(unsafe) 同宽
```

而 `StaticTypeLayoutResolver` 对 `.weak` / `.unowned` / `.unmanaged` 三个 node kind
**无条件返回单字**，于是每少一张见证表就少 8 字节。因为 `ViewResponder` 是基类，误差沿继承
链放大到全部子类的全部字段。

### 为什么旧版本"看起来对"

在 struct XI 传播修好（2026-07-18）之前，`helper` 里的 `data: A?` 因 payload XI 记 0 而多
吃一个 tag 字节、对齐后多 8 字节，恰好抵消基类少的 8 字节，于是 `childSubgraph` 起的偏移
碰巧正确——但 `helper` 及之前的字段一直是错的。两个符号相反的 size 误差互相抵消，是这类
bug 长期隐身的典型原因。

## 最终方案

1. `.weak` / `.unowned` / `.unmanaged` 改为按 referent 决定宽度：剥掉 `Optional` 包装后，
   若 referent 是 existential（`protocolList` 系列 / `symbolicExtendedExistentialType`），
   复用现成的 `existentialLayout` 取容器宽度；否则维持单字。
2. XI 与 bitwise-takable 按「字」拆开：引用字贡献修饰符自己的 XI（weak 0 / unowned 1 /
   unowned(unsafe) 饱和），见证表字是普通指针贡献饱和值，容器取 max。takable 由 referent
   定——existential 引用计数未知，`unowned`(safe) 走 unknown-refcounting 表示 → 非
   takable（实测 VWT 佐证），`unowned(unsafe)` 恒 takable，`weak` 恒非 takable。
3. existential 里有解析不到的协议时抛 `unknown` 降级，不猜宽度（宽度错会静默推移后续所有
   字段）。

## 实际执行

- `Sources/SwiftLayout/StaticTypeLayoutResolver.swift`：新增 `ReferenceStorageKind` 与
  `referenceStorageLayout(forNode:storage:in:)` / `referentType(of:)`。
- fixture `Tests/Projects/SymbolTests/SymbolTestsCore/WeakUnownedReferences.swift`：新增 6 个
  引用存储 × existential 的 struct（单协议 / 协议组合 / `AnyObject` / `@objc` 协议 /
  `unowned` / `unowned(unsafe)`）+ 类与子类各一（pin 后续字段偏移与子类起点）。
- `Tests/SwiftLayoutTests/WholeTypeLayoutVsRuntimeTests.swift`：7 组参数化宽度 pin（各自
  与 runtime VWT 五元组交叉验证）+ 类级偏移 pin。
- 重建 fixture、`regen-baselines`、重录两份快照。

## 验证

- iOS 26.5 `SwiftUICore` 的 `StyledTextResponder` 十个字段全部与反汇编真值逐一吻合，末尾
  `0x140 + 8 = 0x148` 等于 metadata 的 `instanceSize`。
- `swift test --skip IntegrationTests`：1255 tests / 241 suites 全绿。
- baseline 漂移经逐行审查**只含 offset/address/pointer 字段**（fixture 二进制增大导致的统一
  平移 +6336），无任何语义字段变化；两份快照的 diff 是**纯新增**（238 行插入、0 删除），
  既有输出一字未改——说明本修复没有改变任何既有 fixture 类型的渲染结果。
- **整文件基线已重录**为 `MachOSwiftSection-Baselines/main-7410710/`（62 份，取代
  `main-27726bc/`，后续迭代以新版为准）。相对旧基线差异 **6/62**，全部是本修复的预期修正：
  只出现在带布局注释的 `-full` 变体上，且 6 份差异文件的**非注释内容哈希逐份相同**（声明结构
  零变化）。`DyldCache` 18/18 与 `Image` 6/6 逐字节一致——`Image` 走 MachOImage 路径、字段
  偏移直读运行时 metadata，**它一字未变正是修复的旁证**（静态侧向 ground truth 收敛）。
  旧基线抓到的第二个真实案例：`SwiftData.WeakAnyPersistentObject.boxed`
  （`weak var boxed: (any PersistentModel)?`）从 8 字节修正为 16，其后的
  `persistentIdentifier` 从 `0x8` 修正到 `0x10`。

## 与计划的偏差

1. **`unowned` over existential 的 bitwise-takable**：初版按「修饰符自身的 flag」建模为
   takable，被 `WholeTypeLayoutVsRuntimeTests` 的 VWT 对照当场抓出（runtime 为非 takable）。
   查证后确认 existential 引用计数未知 → unknown-refcounting 表示，改为按 referent 决定。
   这条不是猜出来的，是测试逼出来的。
2. **嵌套 `@objc` 协议解析不到**（新发现的独立缺口）：嵌套声明的 `@objc` 协议其旧式 ObjC
   名带父上下文（`_TtPO<module><parent><name>_`），而 `ObjCProtocolIndex` 只解析两段式
   `_TtP<module><name>_`。fixture 因此把 `@objc` 协议改放文件作用域，缺口本身留待后续，
   已记入 `StaticLayoutEngine.md`。
