# Draft - 没有本地符号的镜像里，扩展中的类型与私有 `@objc` 协议也给出导出结论

- **状态**: Accepted
- **创建日期**: 2026-11-10
- **最后更新**: 2026-11-10
- **所属愿景**: 无
- **关联提案**: [0016](0016-exported-only-interface.md)（重整名一腿拒绝扩展上下文的由来）、[0024](0024-exported-declaration-flag.md)（`exportStatus` 的来历）、[0083](0083-exported-only-marking-mode.md)（标记模式）
- **实现分支 / PR**: `feature/export-verdict-without-local-symbols`（从 `next` 切）

## 摘要

RuntimeViewer 的侧栏把「Not Exported」设为排除后，AppKit 里仍列出几十个带私有鉴别器的类型，例如 `NSView._HitTestMap`、`NSGlassEffectContainerView.GlassGroup`。原因在 `ExportStatus` 的判定：描述符地址上没有符号时，第二条腿把名字重新 mangle 后查导出表，但名字里只要有扩展上下文就放弃，给出 `.descriptorSymbolNameUnresolvable`。macOS 27.2 的共享缓存里，AppKit 没有本地符号（`dump` 里私有成员符号 0 个；Foundation 153 个，SwiftUI 676 个），而 Swift 写在 ObjC 类里的类型必然经过扩展上下文（`(extension in AppKit):__C.NSView`）。所以 AppKit 里这类未导出的类型全部判不出：约 45 个，其中 33 个的名字带私有声明。`swift-section interface --exported-only` 同样把其中 25 个私有类型留在了输出里，Foundation、SwiftUI、SwiftUICore 则一个都没有。另外，Swift 声明的 `@objc` 协议一律不判（`.declarationHasNoSymbol`），AppKit 的 5 个私有协议因此也一直留着。本提案让这两类声明拿到结论。

## 方案

1. **第二条腿只在遇到带约束的扩展时放弃。** 0016 拒绝扩展上下文的理由只对带约束的扩展成立：编译器只把扩展自己的要求 mangle 进上下文，模型的名字却带着完整签名。不带约束的扩展节点只有模块和被扩展的类型两个子节点，重新 mangle 与编译器的拼写一致（`$s10Foundation15AttributeScopesO6AppKitE0dE10AttributesV010AttachmentB0OMn` 经 `swift-demangle -test-remangle` 原样往返）。`containsExtensionContext(_:)` 改为只认带泛型签名的扩展节点。协议走的是同一条路，一并修好。
2. **私有声明与局部类型没有符号可判时，判为未导出。** 名字的上下文链里有私有声明或函数时（看自己的名字、外层类型、扩展所扩展的类型、声明局部类型的函数；不看泛型实参、扩展的要求和函数签名），编译器给它的链接不是 public，它不会进导出表。这条推断用在两处：`ObjCProtocolDefinition.exportStatus`（现在恒为 `.declarationHasNoSymbol`），以及第 1 步之后仍判不出的类型与协议，即带约束扩展里的私有类型。只在镜像有导出信息时这样判。用 `-enable-private-imports` 编出的镜像会导出私有声明，但那时第一条腿已在描述符上找到导出符号，走不到这条推断。
3. **打印器照常过滤。** `printObjCProtocolDefinition` 像 Swift 协议一样经过 `exportFilterVisibility(excluded:)`：`--exported-only` 时去掉，标记模式下标成「开关关闭时才可见」。协议的扩展随协议一起打印，不另外进 `ExportFilterScope`，公开 API 不变。
4. **测试。** 照 `ExportedOnlyFixture` 新建一个现编的夹具（不开 `-enable-testing`），里面有：嵌在 `extension Int` 和 `extension NSObject` 里的 public、internal、private 类型，私有类型里的嵌套类型，带约束扩展里的 internal 与 private 类型，以及 public 与 private 的 `@objc` 协议。夹具另出一份 `strip -x` 后重签的副本。
   - 剥离副本上，internal 与 private 的类型判 `.notExported`，public 的判 `.exported`。修复前前者是 `.descriptorSymbolNameUnresolvable`，所以测试先红。
   - 未剥离副本上，凡经过不带约束扩展的名字，重新 mangle 的结果与描述符上的符号逐字相等。这证明第 1 步放开之后不会拼错名字、误删导出的类型。
   - 带约束扩展里，internal 的类型仍判不出，private 的判 `.notExported`。
   - 私有 `@objc` 协议判 `.notExported`，public 的仍是 `.declarationHasNoSymbol`；`--exported-only` 打印的 interface 里没有私有协议。
   - `ExportStatusTests.remanglingRefusesAConstrainedExtensionContext` 保留不动。
5. **文档。** `ExportStatus` 的文档注释里「前两个无结论 case 在发布的二进制上不出现」这条实测，补上 AppKit 这个反例；`Internal/ExportedOnlyInterfaceFiltering.md` 与 `Internal/Modules/SwiftDeclaration.md` 里「重整名拒绝扩展上下文」的说法同批改掉。

下游：RuntimeViewer 抬 pin 之后，侧栏对类型自动生效；它构造 `@objc` 协议条目时现在不读 `exportStatus`，要改一行，并在 RuntimeViewer 的 ResolvedIssues 里记下这次问题。

没有询问就采用的假设：

- 第 2 步的推断不只用在 `@objc` 协议上，也用在带约束扩展里的私有类型上：理由相同，而要解决的就是「排除未导出之后不应再看到私有声明」。
- RuntimeViewer 里用户手动做出的特化不在本提案范围。它的私有声明来自泛型实参，描述符属于原型，沿用原型的结论本来就对。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-11-10 | Created as Draft | RuntimeViewer 把未导出的类型设为排除后，仍显示带私有鉴别器的 AppKit 类型；调查定位到本库的导出判定。用户选定在本库修，并决定私有的 `@objc` 协议也当作未导出。 |
| 2026-11-10 | 用户批准，开始实现 | 在功能分支 `feature/export-verdict-without-local-symbols` 上实现；构建与测试按惯例放到 JH's Mac Studio Ultra 上跑。 |
