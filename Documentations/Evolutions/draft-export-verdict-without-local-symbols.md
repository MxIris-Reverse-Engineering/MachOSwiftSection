# Draft - 没有本地符号的镜像里，扩展中的类型与私有 `@objc` 协议也给出导出结论

- **状态**: In Progress
- **创建日期**: 2026-11-10
- **最后更新**: 2026-11-10
- **所属愿景**: 无
- **关联提案**: [0016](0016-exported-only-interface.md)（重整名一腿拒绝扩展上下文的由来）、[0024](0024-exported-declaration-flag.md)（`exportStatus` 的来历）、[0083](0083-exported-only-marking-mode.md)（标记模式）
- **实现分支 / PR**: `feature/export-verdict-without-local-symbols`（从 `next` 切）

## 摘要

RuntimeViewer 的侧栏把「Not Exported」设为排除后，AppKit 里仍列出几十个带私有鉴别器的类型，例如 `NSView._HitTestMap`、`NSGlassEffectContainerView.GlassGroup`。原因在 `ExportStatus` 的判定：描述符地址上没有符号时，第二条腿把名字重新 mangle 后查导出表，但名字里只要有扩展上下文就放弃，给出 `.descriptorSymbolNameUnresolvable`。macOS 27.2 的共享缓存里，AppKit 没有本地符号（`dump` 里私有成员符号 0 个；Foundation 153 个，SwiftUI 676 个），而 Swift 写在 ObjC 类里的类型必然经过扩展上下文（`(extension in AppKit):__C.NSView`）。所以 AppKit 里这类未导出的类型全部判不出：约 45 个，其中 33 个的名字带私有声明。`swift-section interface --exported-only` 同样把其中 25 个私有类型留在了输出里，Foundation、SwiftUI、SwiftUICore 则一个都没有。另外，Swift 声明的 `@objc` 协议一律不判（`.declarationHasNoSymbol`），AppKit 的 5 个私有协议因此也一直留着。本提案让这两类声明拿到结论。

## 方案

1. ✅ **第二条腿只在遇到带约束的扩展时放弃。** 0016 拒绝扩展上下文的理由只对带约束的扩展成立：编译器只把扩展自己的要求 mangle 进上下文，模型的名字却带着完整签名。不带约束的扩展节点只有模块和被扩展的类型两个子节点，重新 mangle 与编译器的拼写一致（`$s10Foundation15AttributeScopesO6AppKitE0dE10AttributesV010AttachmentB0OMn` 经 `swift-demangle -test-remangle` 原样往返）。`containsExtensionContext(_:)` 改为只认带泛型签名的扩展节点。协议走的是同一条路，一并修好。
2. ✅ **私有声明与局部类型没有符号可判时，判为未导出（第三条腿）。** 编译器给私有、fileprivate 与局部声明的链接不是 public，它们不会进导出表。用 `-enable-private-imports` 编出的镜像会导出私有声明，但那时第一条腿已在描述符上找到导出符号，走不到这里。认法有两种，任一成立即可：
   - 名字的上下文链里有私有声明或局部类型：看自己的名字、外层类型、扩展所扩展的类型；不看泛型实参、扩展的要求和函数签名（`isPrivateOrLocal(_:)`）。
   - 描述符外层有匿名上下文（`isEnclosedByAnonymousContext(_:in:)`）：编译器给私有声明与局部声明套的就是这一层。什么符号都没留的镜像里匿名上下文没有名字，私有类型的名字里就没有鉴别器，只有这一种认得出。

   用在两处：第 1 步之后仍判不出的类型与协议（带约束扩展里的私有类型），以及 `ObjCProtocolDefinition.exportStatus`（它没有描述符，只看名字；原来恒为 `.declarationHasNoSymbol`）。只在镜像有导出信息时判为 `.notExported`，否则是 `.imageHasNoExportInformation`；为此 `SymbolIndexStore` 加了包内接口 `hasExportInformation(in:)`。
3. ✅ **打印器照常过滤。** `printObjCProtocolDefinition` 像 Swift 协议一样经过 `exportFilterVisibility(excluded:)`：`--exported-only` 时去掉，标记模式下标成「开关关闭时才可见」。协议的默认实现扩展随协议一起打印，不另外进 `ExportFilterScope`，公开 API 不变。ObjC 类别（category）遵循的协议全是本镜像未导出的 `@objc` 协议时，这条 conformance 也去掉，同 Swift 类型遵循未导出协议的 conformance 一样；还遵循了别的协议的，整条保留。
4. ✅ **测试。** 新建现编夹具 `ExtensionContextExportFixture`（不开 `-enable-testing`），里面有：嵌在 `extension Int` 和 `extension NSObject` 里的 public、internal、private 类型，私有类型里的嵌套类型，扩展里的协议和局部类型，带约束扩展里的 public、internal 与 private 类型，public 与 private 的 `@objc` 协议，以及只遵循私有协议、同时遵循两种协议的两个 Foundation 类别。它出三个变体，各用自己的模块名分别编译：未剥离、只留 `_symbolic` 符号（AppKit 的形状）、`strip -x`。
   - 两个剥离变体上，扩展里 internal、private 与局部的声明判 `.notExported`，public 的判 `.exported`。修复前前者是 `.descriptorSymbolNameUnresolvable`。
   - 未剥离变体上，凡经过不带约束扩展的名字，重新 mangle 的结果与描述符上的符号逐字相等。这证明第 1 步放开之后不会拼错名字、误删导出的类型。
   - 带约束扩展里，internal 的类型仍判不出，private 的判 `.notExported`（`strip -x` 变体上靠匿名上下文认出）。
   - 私有 `@objc` 协议判 `.notExported`，public 的仍是 `.declarationHasNoSymbol`；`--exported-only` 的 interface 里没有私有协议，也没有只遵循它的类别。原 `SwiftDeclaredObjCProtocolsFixture` 上同样断言；`ObjCProtocolDefinitionIndexingTests` 原来断言所有 `@objc` 协议都是 `.declarationHasNoSymbol`，随之改为私有的那个是 `.notExported`。
   - `ExportStatusTests.remanglingRefusesAConstrainedExtensionContext` 保留不动。
5. ✅ **文档。** `ExportStatus` 的文档注释补上 AppKit 这个反例和第三条腿；`Internal/ExportedOnlyInterfaceFiltering.md`、`Internal/Modules/SwiftDeclaration.md` 与术语表里「重整名拒绝扩展上下文」的说法同批改掉；`--exported-only` 的帮助文字、`InterfaceRequest` 的注释和 README 原写「没有导出证据的一律保留」，补上私有与局部声明这个例外。

下游：RuntimeViewer 抬 pin 之后，侧栏对类型自动生效；它构造 `@objc` 协议条目时现在不读 `exportStatus`，要改一行。它自己逐条打印 ObjC 类别的 conformance，第 3 步的类别规则也要照做一遍。并在 RuntimeViewer 的 ResolvedIssues 里记下这次问题。

没有询问就采用的假设：

- 第 2 步的推断不只用在 `@objc` 协议上，也用在带约束扩展里的私有类型上：理由相同，而要解决的就是「排除未导出之后不应再看到私有声明」。
- RuntimeViewer 里用户手动做出的特化不在本提案范围。它的私有声明来自泛型实参，描述符属于原型，沿用原型的结论本来就对。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-11-10 | Created as Draft | RuntimeViewer 把未导出的类型设为排除后，仍显示带私有鉴别器的 AppKit 类型；调查定位到本库的导出判定。用户选定在本库修，并决定私有的 `@objc` 协议也当作未导出。 |
| 2026-11-10 | 用户批准，开始实现 | 在功能分支 `feature/export-verdict-without-local-symbols` 上实现；构建与测试按惯例放到 JH's Mac Studio Ultra 上跑。 |
| 2026-11-10 | 夹具出三个变体，每个用自己的模块名分别编译 | 只做 `strip -x` 覆盖不到 AppKit：AppKit 留着 `_symbolic` 符号，私有鉴别器还原得出，所以另做一个只留 `_symbolic` 的变体。起初从一次编译复制出三份，测试却在剥离副本的描述符上查到了本地符号：各镜像的缓存按 `LC_UUID` 认文件，复制品共用一个 UUID，剥离副本读到的是未剥离那份的符号索引。 |
| 2026-11-10 | 第三条腿除了看名字，也看描述符外层有没有匿名上下文 | `strip -x` 的变体里匿名上下文没有名字，带约束扩展里的私有类型名字中没有鉴别器，光看名字判不出；匿名上下文是编译器给私有与局部声明套的，结构上就在。 |
| 2026-11-10 | 只遵循私有 `@objc` 协议的 ObjC 类别也在 `--exported-only` 时去掉 | 修复后用新编的 swift-section 跑 AppKit，私有类型与扩展都没了，只剩 `extension __C.NSTextList: AppKit._TitleProviding {}`。Swift 类型遵循未导出协议的 conformance 本来就会去掉，这里同样处理；类别还遵循了别的协议时整条保留，不靠猜删。 |
| 2026-11-10 | 新增包内接口 `SymbolIndexStore.hasExportInformation(in:)`，不公开 | 第三条腿要分清镜像有没有导出信息，只有本库自己用。 |
| 2026-11-10 | 全量测试的 43 个失败判为基线既有，不在本分支处理 | 在 JH's Mac Studio Ultra（macOS 27.2，Xcode 27.2）上，`SymbolTestsCore` 按 CI 的方式（ad-hoc 签名）现编，`swift test --skip IntegrationTests` 有 43 个测试失败，全是 ABI 层描述符偏移与基线不等一类（另有 `KeyPathComputedPropertyBodyTests`、`ThunkOnlyObjCMemberTests`）。在 `next`（`bd1df364`）上用同一份夹具跑同一批测试，失败的测试一个不差、也没有多出来，与本改动无关。 |
| 2026-11-10 | 实现完成，待用户看过后收尾 | 验证都在 JH's Mac Studio Ultra 上：撤掉判定修复时，扩展中的类型、私有 `@objc` 协议与往返重整共 8 组测试变红，恢复后全绿；单撤类别规则时只有它那一条变红。最终提交上 `SwiftInterfaceTests`、`SwiftIndexingTests` 与 `SwiftSectionKitTests` 只剩 4 个失败，都在上一行的基线集合里。用新编的 swift-section 对 macOS 27.2 的 AppKit 跑 `interface --exported-only --emit-private-source-files`：修复前留下 25 个私有类型、32 个扩展，修复后一个带私有鉴别器的声明都不剩，`NSTextList` 遵循 `_TitleProviding` 的类别也不在了。没有另写实现说明或使用指南：实现说明 `Internal/ExportedOnlyInterfaceFiltering.md` 已同批更新；没有新术语，术语表只改了已有词条。 |
