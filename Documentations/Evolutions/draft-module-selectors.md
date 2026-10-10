# Draft - 适配 SE-0491：interface 与 dump 可用模块选择器（`Module::Name`）写限定名

- **状态**: In Progress
- **创建日期**: 2026-10-10
- **最后更新**: 2026-10-10
- **关联提案**: swift-demangling 提案 `draft-module-selectors`（`DemangleOptions.useModuleSelectors`，本提案的 dump 一侧与 interface 的委托打印都建在它上面）

## 摘要

[SE-0491](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0491-module-selectors.md)（Swift 6.3 实现）给源码加了 `Module::Name` 写法：名字前带上它来自的模块，查找只认这个模块，不会被同名的类型、成员或局部变量挡住——典型的坑是模块里有个与模块同名的类型（`XCTest` 模块里的 `XCTest` 类），这时 `XCTest.XCTestCase` 会被当成去 `XCTest` 类里找嵌套类型。提案不改 ABI，二进制里没有任何新东西要读，影响只在「名字怎么写」。

Swift 6.4 编译器生成 `.swiftinterface` 时默认就用这种写法：Xcode 27 SDK 里 Swift、Foundation、AppKit、_Concurrency 的接口全是 `Swift::Int`、`Foundation::Date.Foundation::FormatStyle`、`~Swift::Copyable`（SwiftUI 关掉了）。本库一直写 `Swift.Int`。本提案加一个默认关闭的开关，打开后 interface 和 dump 按编译器写接口文件的同一套规则输出。

## 方案

**规则**（与编译器 `TypePrinter::shouldPrintModuleSelector` / `printQualifiedType` 一致，swift-demangling 与本库的 interface 打印器各实现一份，算法相同）：

- 模块与它限定的名字之间写 `::`。
- 嵌套类型的每一层都带上**声明它的模块**：最近一层 extension 的模块，没有 extension 就是上下文链根上的模块。于是本模块在 `Swift.Duration` 的 extension 里声明的类型写成 `Swift::Duration.ModuleSelectorFixture::LocalFormat`——这个出处在点号写法里整个丢失。
- 不加：局部类型（上下文链经过函数、闭包、匿名上下文）；类型参数的关联类型 `A.Element`（SE-0491 明文禁止）。
- 由 C 导入成别的类型成员的类型（`NSAttributedString.Key`，TypeIndexing 给出的 Swift 写法带点号）每一层都带解析出的模块：`Foundation::NSAttributedString.Foundation::Key`，与 SDK 接口相同；`__C` 解析不出真实模块时嵌套层不加选择器。
- 手写的限定名一起改：`Builtin.`、`Swift.AnyObject`、`~Swift.Copyable` / `~Swift.Escapable`。

**开关与接线**：

- interface：`SwiftDeclarationPrintConfiguration.usesModuleSelectors`（默认关）。节点打印器在创建时从委托读一次，存在打印上下文里，所以同一个打印器的记忆化片段不会混两种写法。CLI `interface --module-selectors`，SwiftSectionKit `InterfaceRequest.usesModuleSelectors`。
- dump：`DemangleOptions.useModuleSelectors`（swift-demangling 新选项）。CLI `dump --enable-module-selectors`，经 `DemangleOptionGroup` 进 `DumpRequest.demangleOptions`。
- 不透明类型约束（`some Swift::Collection<Swift::Int>`）由 provider 拼成文字交回，`OpaqueTypeResolving.opaqueType(forNode:index:)` 因此加了 `usesModuleSelectors` 参数；provider 用来匹配协议事实的名字仍是 `opaqueTypeBuilderOnly` 的点号写法，只有交回的文字换写法。
- extension 的声明头（`extension Swift::Duration {`）原先直接拿 `ExtensionName.name` 显示——那是按固定预设印出、兼作查找 key 的点号写法。`ExtensionName.print` 加了 `usesModuleSelectors` 参数（默认关），打印头部时按配置传入，`name` 本身不变。这一处是扫漏测试在实现中途抓出来的。
- `~Swift.Copyable` / `~Swift.Escapable` 不再是写死的文字，而是两个常驻的协议类型节点，交给当前的类型打印器 / resolver 去印，于是自动跟随任何拼写选项，富文本里也成了真正的协议引用。节点必须常驻：interface 打印器按节点地址记忆化片段，临时节点释放后地址复用会串缓存。

**不动**：dump 注释里的 ObjC 运行时名字（`-[Swift.__StringStorage characterAtIndex:]`、`ObjC ancestor chain: Swift.__SwiftNativeNSDictionary → …`）——那是运行时给 Swift 类起的类名字符串，原样照抄，不是 Swift 源码里的限定名；查找 key（`Swift.Int` 之类的内部字符串，用固定预设打印，从不带这个选项）；ABI diff / snapshot；TypeIndexing（它读 SourceKit 生成的接口，编译器只在写 `.swiftinterface` 时才用模块选择器）；RuntimeViewer（选项默认关，加设置项另议）。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-10 | Created as Draft：适配 SE-0491，swift-demangling 加一个使用 module selector 的选项 | 用户要求「适配一下这个提案，顺便改一下 swift-demangling，加一个 options 使用 module-selector」 |
| 2026-10-10 | 嵌套类型每一层都带模块（照编译器），不只在最外层 | 用户选定。与 Xcode 27 SDK 接口一致，并保留嵌套类型由哪个模块的 extension 声明的信息 |
| 2026-10-10 | 默认关闭；interface 与 dump 都接 | 打开即改变每一份输出与快照；dump 已有逐个 demangle 选项的 `--enable-/--disable-` 开关，新选项照样接，成本几乎为零 |
| 2026-10-10 | `~Swift.Copyable` 改由类型打印器 / resolver 印协议节点，不在原处按开关二选一 | 拼写从此只有一个来源。代价：开关关闭时，凡显示标准库模块的选项组合文字不变；不显示的（如 `--demangle-options simplified`）从 `~Swift.Copyable` 变成 `~Copyable`，与它对其余标准库名字的写法一致；富文本里它从一个「其他类型名」变成模块 + 协议两段 |
| 2026-10-10 | `OpaqueTypeResolving.opaqueType` 加 `usesModuleSelectors` 参数，不给默认实现 | 解析器角色协议按约定不带默认实现，签名漂移要在编译期暴露；已知实现方只有本库的 provider（RuntimeViewer 只构造它）。若改成让 provider 在构造时自带开关，配置与 provider 会各说各话 |
| 2026-10-10 | 验证 | 新测试 27 个全过，interface 扫漏测试在修 extension 头之前失败；全量 2370 个测试 / 453 个套件只剩本机早已存在的两条 `MultiPayloadEnumDescriptorCacheTests`；macOS 27 的 libswiftCore / Observation / Synchronization 打开开关后 interface 零残留，dump 只剩注释里的 ObjC 运行时类名；libswiftCore 与 SDK 接口共有的 107 条嵌套类型路径逐层模块一致。渲染 A/B 另记 |
