# Draft - interface 不打印编译器合成的成员：actor 默认存储与 property wrapper 的 `_x` / `$x`

- **状态**: In Progress
- **创建日期**: 2026-09-16
- **最后更新**: 2026-09-17
- **所属愿景**: 无
- **关联提案**: [draft-raw-layout-artificial-field-handling](draft-raw-layout-artificial-field-handling.md)（人造字段那批引出了本提案的第一条裁定）
- **实现分支 / PR**: `feature/swift-6.4-adaptation`
- **配套文档**: [Modules/SwiftDeclaration.md](../Internal/Modules/SwiftDeclaration.md)（`wrappedProperties` 一段）；规则写在 `TypeDefinition+WrappedProperties.swift` 与 `PropertyWrapperTypeCatalog.swift` 的文档注释里

## 摘要

interface 的契约是「像源码」。两类成员在源码里并不存在，是编译器替声明合成的：actor 的 `$defaultActor` 默认存储字段（`actor` 关键字或 `@globalActor` attribute 已经表达了它），以及 property wrapper 用法 `@Wrapper var x` 合成的 `_x` 存储字段与 `$x` 投影属性（源码只声明了 `x`）。本提案让 interface 不再打印它们；dump 的契约是「记录原样」，照常打印。

## 方案

**actor 默认存储**：`renderModelFields` 跳过所有 `isArtificial` 字段记录。人造记录目前只有两种——`$defaultActor` 与 Swift 6.4 的 `_rawLayout`——前者由 `actor` 关键字表达，后者打成 `@_rawLayout(like:)` attribute。

**property wrapper（第二版，索引产出、打印只读）**：第一版把「这个 nominal 类型是不是 property wrapper」做成打印器的一个槽位，由 `SwiftInterfaceBuilder` 构造时装一个索引器实现；用户裁定不能这样——有的下游（RuntimeViewer）不用这个类、自己驱动 `SwiftDeclarationPrinter` 打印，槽位永远是空的——而且这本来就该是索引的活：索引时顺手把这些东西做了，打印只读索引完成的类型定义里的特定内容。第二版因此改成：

- **模型**：`TypeDefinition.wrappedProperties: [WrappedPropertyDefinition]`，每条记属性名 `x`、存储字段名 `_x`、投影名 `$x`、attribute 类型节点、来源（`declaredMember` / `synthesized(declaredTypeNode:hasSetter:)`）。`fields` 与 `variables` 里的 `_x`、`$x` 原样保留，diff / snapshot 的记录不变。
- **索引**（`TypeDefinition.index(in:)` 末尾，成员建完之后）：对每个存储字段 `_x`，`_x` 的 nominal 类型按顺序判定是不是 wrapper：先查本镜像的符号索引有没有该类型的 `wrappedValue` 成员符号（`SymbolIndexStore.memberSymbols(of:for:node:in:)`，internal wrapper 也算；与 `TypeAttributeInferrer` 认 `@propertyWrapper` 是同一条证据）；没有再问 `PropertyWrapperTypeCatalog`——把 nominal 节点重整成 mangled 前缀，在本镜像和依赖闭包各镜像的导出 trie 里查 `<前缀>12wrappedValue` 开头的符号（MachOKit `search(byKeyPrefix:)`，不 demangle，命中才 demangle 那几个符号）。SwiftUICore 导出了 `EnvironmentObject.wrappedValue.getter`、`State.wrappedValue.modify` 等，跨镜像的公开 wrapper 都认得出；闭包解析不到的镜像诚实答「不知道」。是 wrapper 时，`variables` 里有 `x` 就是 `declaredMember`；没有（accessor 被 strip，系统框架与 app 里 internal 属性的常态）就从 wrapper 的 `wrappedValue` 符号类型代入 `_x` 的泛型实参得到声明类型（`EnvironmentObject<Model>.wrappedValue: A` → `Model`），`wrappedValue` 有 setter / modify 就可写，记 `synthesized`；代入不了（不是简单的泛型参数代换）就不记，`_x` 照旧当字段。
- **目录的生命周期**：`SwiftDeclarationIndexer.prepare()` 在索引类型之前用索引配置里新增的 `dependencySearchPaths`（默认系统 cache，CLI 的 `--dependency-search-path` 同时喂给它）建一个 `PropertyWrapperTypeCatalog` 登记到每镜像共享的 `PropertyWrapperTypeCatalogStore`（in-process 用已加载镜像的闭包，离线用搜索路径；闭包在第一次跨镜像查询时才建，结论按前缀记忆），随索引器一起释放（`PerImageCacheEvictionRegistry` 新增 `propertyWrapperCatalog` claim）；没登记过的镜像退化成查系统 cache。RuntimeViewer 用默认配置即可，不用改。
- **打印**只读 `wrappedProperties`：`declaredMember` 的 `_x` 不打、`x` 前面印 attribute；`synthesized` 的在字段原位置印 `@SwiftUI.EnvironmentObject var model: IDESettingsPanel.ThemesSettingsModel { get }`，保留字段的偏移 / 布局注释，上面一行注释 `synthesized from the backing storage \`_model\`; the property's own accessors are stripped`；`$x` 一律不打。dump 不动。

**`@Wrapper` attribute**：证据齐全时，`x` 前面补上 wrapper 作为 attribute，与编译器自己的 swiftinterface 同形（`@SwiftUICore.Binding public var isOn: Swift.Bool { … }`，wrapper 在其它 attribute 之前，类型按 interface 惯例全限定）。泛型实参的写法二进制里没有记录，只有 `_x` 的完整类型；规则取「读者会怎么写」：wrapper 恰有一个泛型实参且等于被包装属性自己的类型时，编译器能推断，省略不写（`@State var x: Int`）；否则原样带上（`@Tagged<String, Int> var count: Int`），两种都是合法源码。编译器 swiftinterface 里的 `@_projectedValueProperty($x)` 是编译器内部 attribute，不印。机制：`SynthesizedPropertyWrapperMembers` 多记一张「属性名 → attribute 类型节点」的表，`renderMember` 经 `printVariable(_:level:propertyWrapperAttributeTypeNode:)` 传给变量打印；diff / evolution 的 interface 走另一条成员渲染路径，不受影响。

**不再有槽位、不再依赖 `SwiftInterfaceBuilder`**：`PropertyWrapperTypeResolving` 协议、`setPropertyWrapperTypeResolver` 与 `IndexedPropertyWrapperTypeResolver` 全部删除（都是本分支上新加的、未合入的 API）。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-16 | interface 隐藏全部 `isArtificial` 字段 | 用户裁定：`$defaultActor` 不该出现在 interface，`actor` / `@globalActor` 已足够；dump 可以标 |
| 2026-09-16 | property wrapper 合成的 `_x` / `$x` 在推断认出 wrapper 时隐藏，dump 不动 | 用户裁定：「如果 attribute 推断已经能够知道是 propertyWrapper 了，把编译器生成的那个也去掉」 |
| 2026-09-16 | 三条证据缺一不隐藏；跨镜像 wrapper 不识别 | 手写 `_x` / `x` 模式常见，只看命名会误删；跨镜像的推断没有事实来源 |
| 2026-09-16 | 第一版不补 `@Wrapper` attribute | 泛型实参写法无记录，先不猜 |
| 2026-09-16 | 补上 `@Wrapper` attribute；泛型实参「能推断就省略，否则原样带上」；不印 `@_projectedValueProperty` | 用户要求把这个语法加上；三种候选（能推断就省略 / 始终印完整类型 / 始终裸名）中用户选了第一种，它最接近常见源码写法且两种输出都是合法源码 |
| 2026-09-16 | 实现完成并验证通过，状态保持 In Progress | Swift 6.4 工具链：`SwiftInterfaceTests \| SwiftPrintingTests \| SwiftLayoutTests` 全绿（原始退出码 0），现场编译 fixture 补了泛型 wrapper（`@Boxed var title: String`）与双参数 wrapper（`@Tagged<String, Int> var count: Int`）两例；fixture 快照不受影响（`SymbolTestsCore` 定义了三个 wrapper 但没有用法） |
| 2026-09-17 | 去掉槽位与 `SwiftInterfaceBuilder` 的安装点；跨镜像 wrapper 查 wrapper 所在镜像的导出表；accessor 被 strip 时从 `_x` 合成 `@Wrapper var x` | 用户裁定：「这个功能不要挂在 SwiftInterfaceBuilder 里面，有些下游不使用这个类会自定义打印」；三个候选里用户选了导出表识别、从 `_x` 合成 |
| 2026-09-17 | 识别与合成放到索引（`TypeDefinition.index(in:)`）产出 `wrappedProperties`，打印只读模型 | 用户裁定：「这个活应该是索引那边干，打印只读取索引完成的类型定义里面的特定内容就可以打印出来」「索引的时候就能顺手把这些东西做了」 |
