# 2026-09-09 读取 TypeImportInfo，C 导入类型按运行时规则定名字和种类

对应提案：[0023-type-import-info-identity](../../Evolutions/0023-type-import-info-identity.md)

## 问题

上游能力盘点里排第一的缺口。C 导入类型的 type context descriptor 名字后面跟着 import info（ABI 名 / 符号命名空间 / 关联实体名），我们只读了 `hasImportInfo` flag。描述符推出的 demangling 树与符号 demangle 出的树因此在名字和种类上不一致。用户指定与改名一起先做。

## 调研

**ABI**（`swift/ABI/TypeIdentity.h`，IRGen `TypeContextDescriptorBuilderBase::computeIdentity` / `addName`）：名字后追加以空字符分隔的分量，空串结束。`N` 是 ABI 名，`S` 是符号命名空间，`R` 是关联实体名。IRGen 设 ABI 名的条件是 clang 声明的名字与 Swift 用户可见名不同（`swift_name`、typedef 名与 tag 名不同、`NS_ERROR_ENUM` 合成类型的原始类型名）；typedef 与 ObjC 兼容别名提升为独立类型时命名空间写 `t`；`ClangImporterSynthesizedTypeAttr` 的合成类型写关联实体名。

**改写规则**（运行时 `stdlib/public/runtime/Demangle.cpp` 的 `_swift_buildDemanglingForContext`，与 `lib/AST/ASTMangler.cpp` 的 `tryAppendClangName` 一致）：名字用 `getABIName()`；`isCTypedef()` 改 `TypeAlias`；否则 `_isCImportedTagType()`（descriptor 是 enum 或 struct、非 typedef、非关联实体、父级模块是 C 导入）改 `Structure`；关联实体包 `RelatedEntityDeclName`。AST mangler 对所有 Clang `TagDecl` 都发 `V`，注释原话是「A Clang enum is not always imported as a Swift enum」。

**Remote 版落后于运行时**：`Remote/MetadataReader.h` 只在 `importInfo` 存在时才做 tag 枚举改 structure，没有 import info 的 NS_ENUM 被它留成 enum。编译器实测（`_mangledTypeName`）：

| 类型 | mangling | `_typeName` |
|------|----------|-------------|
| `CGColor` | `So10CGColorRefa` | `__C.CGColorRef` |
| `CFString` | `So11CFStringRefa` | `__C.CFStringRef` |
| `ComparisonResult` | `So18NSComparisonResultV` | `__C.NSComparisonResult` |
| `NSTextAlignment` | `So15NSTextAlignmentV` | `__C.NSTextAlignment` |
| `Decimal` | `So9NSDecimala` | `__C.NSDecimal` |
| `CMTime` | `So6CMTimea` | `__C.CMTime` |
| `NSRange` | `So8_NSRangeV` | `__C._NSRange` |
| `DispatchQueue` | `So17OS_dispatch_queueC` | `OS_dispatch_queue` |
| `CKError` | `SC11CKErrorCodeLeV` | `__C_Synthesized.related decl 'e' for CKErrorCode` |
| `CKError.Code` | `So11CKErrorCodeV` | `__C.CKErrorCode` |

**哪些路径受影响**：IRGen `IRGenMangler.cpp` 的 `CanSymbolicReference` 对 C 导入的 struct / enum、CF 类、foreign reference type 都返回 true，所以字段类型里这些类型是指向描述符的 symbolic reference，走 `buildContextDescriptorMangling`；ObjC 类没有 Swift 描述符，字段里是 `So17OS_dispatch_queueC` 这样的字符串，不受本批影响。`__C` 描述符本身在 `__swift5_types` 里（`ForeignStructTopLevelLayoutTests` 靠这一点找 `Decimal`），SwiftLayout 的 `ImageReference` 按 demangle 出的限定名索引它们。

**下游的种类敏感点**：`SwiftLayout.StaticTypeLayoutResolver.layout(forTypeNode:)` 按 `.class` / `.structure` / `.enum` 分派，没有 `.typeAlias`；`NodeTypeNaming.unwrappedNominal` 同样不认 `.typeAlias`，会让索引漏掉这些描述符；`NestedFieldOffsetTree` 用 `nominalCategory` 决定要不要展开子字段；`Node.identifier` 对 `relatedEntityDeclName` 会退回到 DFS 第一个 identifier，也就是实体标签 `e`，所有合成错误 struct 会撞同一个键。TypeIndexing 的 `CImportedTypeNameCategory(nodeKind:)` 对 `.typeAlias` 走 `default` 归 `.other`，`.other` 查 Tags / Typedefs 两张改名表并适用 CF `Ref` 剥除规则，不用改。

## 方案

见提案。ABI 层新增 `TypeImportInfo` 与 `TypeContextDescriptorProtocol.typeImportInfo(in:)` 三态读法；`SymbolicDemangler.cImportedTypeIdentity` 做四条改写，`isCImportedContext` 沿父级 demangling 的首孩子走到 module 节点判断；SwiftLayout 新增 `.typeAlias` 分派（builtin 索引优先，再按解析到的描述符种类分派）、`unwrappedNominal` 接受 `.typeAlias`、`declaredName` 把关联实体名按打印形式作键、`NestedFieldOffsetTree` 对 `.typeAlias` 用描述符种类决定展开。

## 实际执行

按方案落地，几处在写的时候才定下的细节：

- `typeImportInfo(in machO:)` 通过 `MachOContext(machO)` 转到 `ReadingContext` 版本，不再第三次手写读取循环；in-process 版本用 `String(cString:)` 直接走指针。三态入口都先看 `hasImportInfo`，未置位直接返回 nil，不读任何字节。
- 解析照 `TypeImportInfo::collect` 的非断言模式：首字符不认识或值为空的分量忽略，不让整个名字失败。
- `cImportedTypeIdentity` 对非 `.identifier` 的名字节点不做 ABI 名覆盖：匿名上下文里的 `privateDeclName` 不可能是 C 导入类型。
- `__C.Decimal` 在 SwiftLayout 三个测试里写死的期望改为 `__C.NSDecimal`，这是真值变化，不是迁就实现。
- `TypeImportInfo` 的六个 public 成员登记进覆盖白名单的 `pureDataUtility` 组：读取路径由 `TypeContextDescriptorProtocolTests.typeImportInfo` 钉住，解析由 `CImportedTypeIdentityRuleTests` 钉住。`TypeContextDescriptorProtocolBaseline` 的 Entry 增加三个 import-info 字段，并新增 `foreignDecimal` 条目（picker `struct_ForeignDecimal`），baseline 经 `regen-baselines --suite TypeContextDescriptorProtocol` 重生成：`Decimal` 的 ABI 名 `NSDecimal`、命名空间 `t`、无关联实体。

写测试时纠正的两处认知：

1. `NSRange` 的描述符不在 fixture 自己的 `__swift5_types` 里。Foundation overlay 拥有 `$sSo8_NSRangeVMn`，fixture 通过 bind 符号引用它，走的是 `_buildContextManglingForSymbol` 的符号路径，所以「从描述符读 import info」的断言对它不成立，改为只在 mangling 断言里覆盖。
2. 指针版 `typeImportInfo()` 不能拿 `MachOImage` 读出的描述符来调：那种描述符的 `offset` 是镜像内偏移，`asPointer` 把它当地址会段错误（崩溃报告 `_platform_strlen` 于 `0x38460`）。这与既有的 `fieldDescriptor()` 用法一致，测试改为只走 machO 与 `ReadingContext` 两种读法。

**真机对比暴露的第三个问题，修在同一批**：SwiftUI 的 interface 里 C 导入类型的 `RawRepresentable` 扩展块变了形状——`NSScrollPocketEdge` 这种名字没变的 NS_ENUM，`typealias RawValue` 从与成员同块变成尾部独立的裸 `extension` 块；`NSAttributedStringKey` 这种 `swift_wrapper` typedef，`typealias RawValue = Swift.String` 的见证行直接消失（32 行降到 9 行）。追到 `TypeName` / `ExtensionName` 的 `==` 与 `hash` 都带 `kind`：conformance 描述符那侧用描述符种类（NS_ENUM 是 `enum`），`__swift5_assocty` 记录与符号那侧用 demangle 树遍历（改后是 `structure`），键不等，assocty 记录在 `SwiftDeclarationIndexer` 里配不到 conformance，退化成 `remainingTypeName` 的裸块；typedef 提升的类型树是 `typeAlias`，`Node.typeKind` 返回 nil，`AssociatedType.typeName` 直接返回 nil，记录被丢。修法是键只看节点结构，`Node.typeKind` 对 `typeAlias` 给 `.struct`，三处手写的种类推导统一走 `Node.typeKind`。先写 `CImportedTypeConformanceInterfaceTests`（bridging header 里的 NS_ENUM 与 `swift_wrapper` typedef，通过泛型函数逼出 importer 合成的 conformance 记录）看它红，再改代码看它绿。 改完发现 fixture 的 interface 快照也动了：末尾 175 行裸 `extension X { typealias … }` 块消失，同样的 typealias 出现在各自的 conformance 块里——`AssociatedTypeWitnessPatterns`、`AsyncSequenceTests` 这些嵌套在 enum 命名空间里的类型，树遍历先碰到外层 `enum`，与描述符的 `struct` 不等，见证从来没并进去过。提案 0007 记下的「已知外观残留」就是它，AGENTS.md 的那句说明已改。

## 验证

- **红/绿**：`CImportedTypeConformanceInterfaceTests` 在名字键修正前红（`__C.ProbeMode` 的 conformance 块 0 个匹配：块是空的 `{}` 加尾部裸 typealias 块；`__C.ProbeIdentifier` 的 typealias 整条缺失），修正后绿。
- **新套件**：`CImportedTypeIdentityRuleTests` 9 条纯规则测试、`CImportedTypeIdentityFixtureTests` 4 条（十个字段先断言都是指向描述符的 symbolic reference，再断言 remangle 结果逐字等于编译器 `_mangledTypeName` 的字面量、打印结果等于 `_typeName` 的拼法）、`TypeContextDescriptorProtocolTests.typeImportInfo`、覆盖不变量套件，连同改名相关套件定向运行 49 条 / 10 个 suite 全过。
- **快照**：dump 的 `enumsSnapshot` 一行 `case nsNumber(Decimal)` 变 `NSDecimal`；interface 快照一行 `__C.Decimal` 变 `__C.NSDecimal`，另有 175 行尾部裸 typealias 块归位到各自 conformance 块（见上）。逐行核对后重录，两套快照套件 65 条全过。
- **全量** `swift test --skip IntegrationTests`（退出码取自 `swift test` 本身）：三次运行。第一次 1675 条只有两处快照差异（即上面两行）；第二次在 795 条通过后测试进程 SIGBUS 崩溃，崩溃栈在 `ProtocolRecordTests.protocolDescriptor()` 经 `MachOImage.readWrapperElement` 读到非法地址，同一 suite 的 `offset()` 报出的镜像偏移恰是文件偏移减去共享缓存基址 `0x180000000`，说明那一刻 fixture 镜像被当成了 dyld cache 里的镜像——该 suite 不经过本批任何改动，第一、第三次运行都通过，判定为并行测试的环境抖动（崩溃报告 `swiftpm-testing-helper-2026-09-09-214700.ips`）；第三次 1676 条 / 313 个 suite 只剩 `SharedCacheTests` 那对用墙钟断言并行度的已知假失败，单独重跑通过。
- **真机前后对比**（当前系统 dyld cache 的 SwiftUI 与 Foundation，两侧 release CLI 各跑 `dump` 与 `interface`）：
  - SwiftUI dump 110919 行两侧等长，517 行变化全部是 `__C` 名字按编译器拼法改写（`__C.Subgraph` → `__C.AGSubgraphRef`、`__C.Style` → `__C.NSTableViewStyle`、`__C.Key` → `__C.NSAttributedStringKey`、`__C.CGPath` → `__C.CGPathRef`……），另有 29 行原来打成 `sub_` 地址占位的 protocol witness 拿到真名（`AGSubgraphRef` / `CGPathRef` / `CTFontRef` 的 `Hashable` 见证）；`Stripped Symbol` / `Symbol not found` 计数不变，stderr 无差异。
  - SwiftUI interface 106054 → 106819 行：`RawRepresentable` conformance 块「typealias 与成员同块」76 → 115，「只有成员」3 → 0，「只有 typealias」36 → 4（剩下 4 个是原生 `SwiftUI.SquareAzimuth.Set` 一类、成员本就不在镜像里的类型），尾部裸 `extension` 块 388 → 349。以前 `__C.Name`、`__C.Identifier`、`__C.Key` 这些用户可见名把多个不同类型压成同一个打印名，现在各归各名。
  - Foundation dump 36048 行等长，`sub_` 占位 2194 → 2060；interface 37329 → 38170 行，`RawRepresentable` 块「同块」122 → 140、「只有 typealias」18 → 0，裸块 289 → 237。

## 与提案的偏离

无实质偏离。提案写的「`CImportedTypeNameCategory(nodeKind:)` 对 `.typeAlias` 归 `.other`」是现状已满足，不需改代码。

## 环境备忘

- 期望值探针：`/tmp/claude/Probes/TypeImportInfo/` 与 `/tmp/claude/Probes/TypeImportInfoFixture/`，后者用 `-import-objc-header` 加一个只定义错误域符号的 `.m`，`_mangledTypeName` 打印上表的字面量。
- 真机对比用的基线检出：`.worktrees/MachOSwiftSection-RenderingBaseline`（detached，`next` 的 `f3463f50`），release CLI 构建在 `/tmp/claude/SwiftPM/MachOSwiftSection-RenderingBaseline`；候选侧 release 构建在 `/tmp/claude/SwiftPM/MachOSwiftSection-Release`。两侧都用远程 pin（未设 `USING_LOCAL_DEPENDENCIES`）。
