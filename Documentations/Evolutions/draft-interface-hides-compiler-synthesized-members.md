# Draft - interface 不打印编译器合成的成员：actor 默认存储与 property wrapper 的 `_x` / `$x`

- **状态**: In Progress
- **创建日期**: 2026-09-16
- **最后更新**: 2026-09-16
- **所属愿景**: 无
- **关联提案**: [draft-raw-layout-artificial-field-handling](draft-raw-layout-artificial-field-handling.md)（人造字段那批引出了本提案的第一条裁定）
- **实现分支 / PR**: `feature/swift-6.4-adaptation`
- **配套文档**: 无（规则写在 `SwiftDeclarationPrinter+PropertyWrapperSynthesis.swift` 的文档注释里）

## 摘要

interface 的契约是「像源码」。两类成员在源码里并不存在，是编译器替声明合成的：actor 的 `$defaultActor` 默认存储字段（`actor` 关键字或 `@globalActor` attribute 已经表达了它），以及 property wrapper 用法 `@Wrapper var x` 合成的 `_x` 存储字段与 `$x` 投影属性（源码只声明了 `x`）。本提案让 interface 不再打印它们；dump 的契约是「记录原样」，照常打印。

## 方案

**actor 默认存储**：`renderModelFields` 跳过所有 `isArtificial` 字段记录。人造记录目前只有两种——`$defaultActor` 与 Swift 6.4 的 `_rawLayout`——前者由 `actor` 关键字表达，后者打成 `@_rawLayout(like:)` attribute。

**property wrapper**：打印器新增一个独立的解析器槽位 `PropertyWrapperTypeResolving`（「这个 nominal 类型是不是 property wrapper」），`SwiftInterfaceBuilder` 在构造时装一个由索引器的 `allTypeDefinitions` 加 `TypeAttributeInferrer` 回答的实现。对每个名字以 `_` 开头的存储字段 `_x`，三条证据齐全才隐藏：同一类型有成员变量 `x`；`_x` 的类型（剥掉泛型实参）能在本镜像的类型定义里找到；该定义被推断为 `@propertyWrapper`。齐全时同时隐藏 `_x` 与 `$x`。证据不全时照常打印——手写的 `_manual` / `manual` 一对不受影响；wrapper 定义在别的镜像里（SwiftUI 的 `@State` 用在 app 里）也不受影响，因为推断看不见它，这是诚实的「不知道」。

**`@Wrapper` attribute**：证据齐全时，`x` 前面补上 wrapper 作为 attribute，与编译器自己的 swiftinterface 同形（`@SwiftUICore.Binding public var isOn: Swift.Bool { … }`，wrapper 在其它 attribute 之前，类型按 interface 惯例全限定）。泛型实参的写法二进制里没有记录，只有 `_x` 的完整类型；规则取「读者会怎么写」：wrapper 恰有一个泛型实参且等于被包装属性自己的类型时，编译器能推断，省略不写（`@State var x: Int`）；否则原样带上（`@Tagged<String, Int> var count: Int`），两种都是合法源码。编译器 swiftinterface 里的 `@_projectedValueProperty($x)` 是编译器内部 attribute，不印。机制：`SynthesizedPropertyWrapperMembers` 多记一张「属性名 → attribute 类型节点」的表，`renderMember` 经 `printVariable(_:level:propertyWrapperAttributeTypeNode:)` 传给变量打印；diff / evolution 的 interface 走另一条成员渲染路径，不受影响。

**槽位不走 `TypeNameResolving` 角色**：它不解析名字，且必须在 `removeAllTypeNameResolvers()` 之后仍然生效（RuntimeViewer 切换 extra data provider 时会调它）。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-16 | interface 隐藏全部 `isArtificial` 字段 | 用户裁定：`$defaultActor` 不该出现在 interface，`actor` / `@globalActor` 已足够；dump 可以标 |
| 2026-09-16 | property wrapper 合成的 `_x` / `$x` 在推断认出 wrapper 时隐藏，dump 不动 | 用户裁定：「如果 attribute 推断已经能够知道是 propertyWrapper 了，把编译器生成的那个也去掉」 |
| 2026-09-16 | 三条证据缺一不隐藏；跨镜像 wrapper 不识别 | 手写 `_x` / `x` 模式常见，只看命名会误删；跨镜像的推断没有事实来源 |
| 2026-09-16 | 第一版不补 `@Wrapper` attribute | 泛型实参写法无记录，先不猜 |
| 2026-09-16 | 补上 `@Wrapper` attribute；泛型实参「能推断就省略，否则原样带上」；不印 `@_projectedValueProperty` | 用户要求把这个语法加上；三种候选（能推断就省略 / 始终印完整类型 / 始终裸名）中用户选了第一种，它最接近常见源码写法且两种输出都是合法源码 |
| 2026-09-16 | 实现完成并验证通过，状态保持 In Progress | Swift 6.4 工具链：`SwiftInterfaceTests \| SwiftPrintingTests \| SwiftLayoutTests` 全绿（原始退出码 0），现场编译 fixture 补了泛型 wrapper（`@Boxed var title: String`）与双参数 wrapper（`@Tagged<String, Int> var count: Int`）两例；fixture 快照不受影响（`SymbolTestsCore` 定义了三个 wrapper 但没有用法） |
