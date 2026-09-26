# 2026-09-25 conformance 子句里的私有协议：没有高亮，也不能跳转

## 起点

RuntimeViewer 里「很多协议没有高亮、没有语义信息」。截图是 SwiftUI 的两行：

```swift
extension SwiftUI.HostingScrollView: SwiftUI.DocumentViewDelegate {}
extension SwiftUI.HostingScrollViewWithResponsiveScrolling: SwiftUI.ResponsiveScrollingDocumentViewDelegate {}
```

同一屏里 `SwiftUI.AnyPlatformViewHost`、`SwiftUI.ScrollViewHelperDelegate` 是正常的类型颜色，
这两个协议名是白的，点也点不动。RuntimeViewer 的高亮与跳转都取自 `SemanticString` 的两样东西：
每段文字的语义类型（`.type(.protocol, .name)` 之类），和类型引用的 span 标识（被引用类型的 mangled
name，跳转按它查声明）。

## 复现回路

- **`swift-section` 只在 stdout 是终端时上色**：`-o` 写文件、重定向 stdout 都拿不到颜色码。用
  `script -q <输出文件> swift-section … --color-scheme dark` 包一层，颜色码与语义类型一一对应（dark
  方案：类型名 `38;2;208;168;255`，`.standard` 没有颜色码）。
- 同一行里，internal 协议前面有类型颜色码，私有协议什么都没有。
- 全量统计（macOS 27.0 系统 cache 的 SwiftUI interface）：10841 条 conformance 里 58 条协议名没颜色，
  **全部是私有协议**；反过来，私有协议出现在 conformance 子句以外的 28 处（成员类型、泛型约束）
  **全部有颜色**。SwiftUICore、Foundation 同样全部对得上。区分点只有一个：名字是不是私有的，
  以及它是不是写在 conformance 子句里。

## 根因：两层

**MachOSwiftSection 这层**：`printExtensionHeader` 打印协议名用的是
`protocolNode.printSemantic(using: .interfaceTypeBuilderOnly)`，也就是 swift-demangling 的通用打印
引擎，而 interface 里其它所有类型引用都走本模块的 `SemanticTypeNodePrinter`。这是历史遗留：拆分
之前 interface 直接借用 SwiftDump 的 `dumpProtocolName`（dump 路径用的就是引擎），`aa233bc0`
拆出 SwiftDeclarationRendering 时原样内联成了 `printSemantic`，没有看到刻意绕开本模块打印器的理由。
同一行里的 global-actor 属性早就在用 `printThrowingType`。

**swift-demangling 这层**：引擎的 `printEntity` 只给裸 `identifier` 传实体种类（`parentKind`）。
私有名字的形状是 `privateDeclName(判别符, identifier)`，它走的是 `printName(privateDeclName)`，于是：

- 里面的 identifier 拿不到 `parentKind`，`SemanticString` 把它标成 `.standard`——**没有高亮**；
- `printName` 可缓存，缓存会把片段写进一个新建的 sub-target，而新建 target 的 scope 栈是空的，
  名字落在协议自己的类型引用 scope 之外，span 标识为 `nil`——**不能跳转**。这一半在 swift-demangling
  的草案提案 0012 第 2 条里记录过，举的例子正是私有 / 局部名字。

诊断时确认过 remangle 本身没问题：conformance 的协议节点与协议声明的节点结构相同，remangle 出同
一个 mangled name（`…PrivateDoppelgangerProtocol33_82F1A700…LLP`）；标识为 nil 纯粹是 scope 丢了。

**为什么以前没修到**：`633bf8ad`（2026-02-16）修过完全相同的问题——删掉 `Node.parent` 之后本模块
自己的 `NodePrintable` 打印器丢了 `parentKind`，当时给 `printIdentifier` / `printPrivateDeclName`
补上了——但那次只覆盖了本模块的打印器，没有碰 swift-demangling 的引擎。引擎这条路径从语义着色诞生
（2025-06）起就没处理过私有名字：`Node.parent` 时代读的是 identifier 的直接父节点，也就是
`.privateDeclName`，同样落到 `.standard`。不是回归。

## 修法

- **本仓库**：`printExtensionHeader` 改用 `printThrowingType` 打印协议名（抽成
  `printConformanceProtocolName`），与同一行的 global-actor 属性、`where` 子句一致；「节点为 nil →
  空名字但保留子句，抛错 → 整个子句丢弃」的旧语义不变。
- **swift-demangling**（分支 `fix/private-name-parent-kind`）：`printEntity` 把实体种类作为
  `identifierParentKind` 交给三种包裹名字（`privateDeclName` / `localDeclName` /
  `relatedEntityDeclName`），带着它的 `printName` 调用不进缓存——既避免同一个包裹节点被不同种类的实体
  共享时回放错误的种类，也让名字直接写进外层 target、落在实体自己的 scope 里。纯文本不变。

两处独立生效：本仓库的修复单独就能修好 interface（RuntimeViewer 看到的就是它）；引擎的修复让
`printSemantic` 的其余使用者——`dump` 路径、evolution 渲染器的 extension 头——也拿到种类与 scope。

## 验证

- **回归测试，均先确认修复前失败**：
  - 本仓库 `ConformanceProtocolNameSemanticsTests`（fixture 里的
    `AlphaProtocolWitness: PrivateDoppelgangerProtocol`，私有 struct 遵循私有协议）：修复前协议名是
    `.standard` 且 span 标识为 `nil`；修复后是 `.type(.protocol, .name)`，标识等于协议声明的 mangled
    name——正是 RuntimeViewer 跳转时查的键。
  - swift-demangling `NodePrinterWrappedEntityNameTests`：十类名字 × 两种打印选项 × `Node` /
    `NodeReference` 两种表示；撤掉修复时 68 处失败（36 处种类为 nil、28 处 scope 为 nil、共享节点用例
    4 处），修复后全过；swift-demangling 全量 617 个测试通过。
- **端到端，release CLI**：基线 = `next`@`6a324b87` + swift-demangling 0.7.0；候选 = 本修复 +
  swift-demangling 修复（`swift package edit` 指向修复 worktree，不动共享符号链接）。macOS 27.0 系统
  cache：
  - 纯文本：SwiftUI / SwiftUICore / Foundation 的 `interface` 与 `dump` 共 6 对，**全部逐字节一致**
    （合计约 55 万行、32 MB）。
  - 着色：SwiftUI interface 里遵循私有协议的 58 条 conformance 子句，基线 0 条有颜色，候选 58 条全部
    有颜色；SwiftUI 的 conformance dump 里 11892 个私有名字，基线全无颜色，候选全部有颜色。

## 横向排查

- `InterfaceUnionWalker.extensionHeaderText`（evolution 渲染器的 extension 头）同样用
  `printSemantic` 打协议名。它走引擎的实体路径，swift-demangling 修复后自动拿到种类与 scope，不改。
- `SwiftDeclarationPrinter+Headers.swift` 的 `renderLeafName`（diff 路径里私有声明**自身**的名字）同类，
  但叶子是孤立的 `privateDeclName`，引擎修复管不到；目前没有任何消费方按语义类型渲染 diff 输出，
  裁决不修，见 [ReviewAdjudications A47](../ReviewAdjudications.md)。
- 本模块自己的打印器：实体路径（`TypeNodePrintable` / `FunctionNodePrinter` / `VariableNodePrinter`）
  都显式传种类，没有同类。
