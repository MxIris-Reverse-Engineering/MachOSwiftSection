# Draft - `Builtin.Borrow` 支持：Swift 6.4 新元数据种类的读取、进程内构建与静态布局

- **状态**: In Progress
- **创建日期**: 2026-09-16
- **最后更新**: 2026-09-16
- **所属愿景**: 无
- **关联提案**: [0012 RuntimeMetadataTypeBuilder](0012-in-process-metadata-type-builder.md)（本提案给它补第二个 builtin 分支）；swift-demangling 侧的 evolution 0015（`BW` 解码与 `TypeBuilder.createBuiltinBorrowType` 协议要求）
- **实现分支 / PR**: `feature/swift-6.4-adaptation`
- **配套文档**: [Modules/SwiftLayout.md](../Internal/Modules/SwiftLayout.md)（同批补 Borrow 规则一段）

## 摘要

Swift 6.4 给运行时加了一种新的元数据种类 `MetadataKind::Borrow`（0x309，`TargetBorrowTypeMetadata`，只有一个 `Referent` 指针），配套 mangling `BW`，标准库的 `Swift.Ref` / `MutableRef` 用它做唯一的存储字段——macOS 27.0 cache 的 libswiftCore 里 `Ref` 已经是 `let builtin: Builtin.Borrow<A>`。本库此前不认识这个种类：`MetadataKind` 会把 0x309 落到 `lastEnumerated`，`RuntimeMetadataTypeBuilder` 缺 swift-demangling 0.7.0 新增的协议要求 `createBuiltinBorrowType(referent:)`，`SwiftLayout` 对 `.builtinBorrow` 节点只能报「不支持」。本提案把三处补齐，并顺带把布局引擎缺的两个 value witness 事实（bitwise-borrowable、addressable-for-dependencies）接进来，因为 Borrow 的布局规则正好取决于它们。

## 方案

**ABI 模型（MachOSwiftSection）**：`MetadataKind` 新增 `borrow = 0x309`；新增 `BorrowTypeMetadata`（`@LocatableLayoutWrapping`，Layout = kind + `referent: ConstMetadataPointer<Metadata>`）与 `BorrowTypeMetadataLayout`；`MetadataWrapper` 新增 `.borrow` case 并在全部八个 switch 里接线，照 `FixedArrayTypeMetadata` 的形态。`ValueWitnessFlags` 新增 `isAddressableForDependencies`（0x0200_0000）——6.4 运行时开始给 `Builtin.FixedArray` 打这一位，多 payload enum 也会透传它。覆盖不变量：`BorrowTypeMetadata` 走与 FixedArray 相同的 sentinel（`runtimeOnly`）+ 合成实例 Suite 形态，因为这种元数据永远不进二进制 section，fixture 里到不了活实例。

**进程内构建（SwiftInspection）**：`RuntimeMetadataTypeBuilder.createBuiltinBorrowType(referent:)` 调 `swift_getBorrowTypeMetadata(request, referent)`。入口用 `dlsym` 按名字取而不是 `weak_import` 声明：符号只在 6.4 运行时（macOS 27）存在，用 26.x SDK 编译时 TBD 里没有它，弱导入也链接不过。运行时缺入口时返回带名字的 `TypeLookupError`，不造假值。公开 `supportsBuiltinBorrowMetadata` 让调用方与测试能判断分支。

**静态布局（SwiftLayout）**：`StaticTypeLayout` 新增 `isBitwiseBorrowable`、`isAddressableForDependencies` 两个事实，init 给默认值（前者由 `isBitwiseTakable` 推出，后者 false），三十余处既有构造点不动；`BasicLayout` / 字段累加器 / enum 桥接按运行时规则折叠（borrowable 取 AND，addressable 取 OR）；`Builtin.FixedArray` 标 addressable-for-dependencies。`.builtinBorrow` 的规则移植 `stdlib/public/runtime/Borrow.cpp` 的 `swift_getBorrowRepresentation`：referent 超过 4 个指针宽、或 addressable-for-dependencies、或不可按位借用 → 一个 `Builtin.RawPointer`（8 字节，1 个 extra inhabitant）；否则与 referent 同 size / stride / alignment / extra inhabitants。Borrow 自身恒为可按位 take 与 borrow、不 addressable（RemoteInspection `BorrowTypeInfo` 同）。

**假设（未问，写在这里）**：本机没有 6.4 运行时，Borrow 的布局测试只能用运行时源码推出的字面值断言，不能做运行时对账；`RuntimeMetadataTypeBuilder` 的测试两个分支都断言（有入口 → kind 与 referent；无入口 → 错误信息点名符号），不会静默变绿。`@_rawLayout` 类型的「不可按位借用」事实要等人造字段那批（同分支下一提案）才能识别，此前对这类 referent 会答成 inline——与 RemoteInspection 移植版的边界一致。

**依赖**：swift-demangling pin 从 `0.6.3 ..< 0.7.0` 抬到 `0.7.0 ..< 0.8.0`（0.7.0 = evolution 0015，`TypeBuilder` 新增该协议要求，无默认实现）。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-16 | 创建为 Draft，用户以「开工」批准整批 Swift 6.4 适配，直接进入 In Progress | 调研报告已列出改动清单与分批；本提案是其中「Builtin.Borrow」一批 |
| 2026-09-16 | `swift_getBorrowTypeMetadata` 用 `dlsym` 而不是 `weak_import` | 26.x SDK 的 libswiftCore TBD 没有该符号，弱导入声明也链接不过；`swift_getExtendedFunctionTypeMetadata` 能用 weak_import 是因为它在 SDK 里存在 |
| 2026-09-16 | 两个新 flag 以带默认值的 init 参数加入 `StaticTypeLayout`，不改既有构造点 | 34 处构造点里只有 FixedArray、enum、struct 累加三处的真值与默认不同；其余类型 borrowable 恒等于 takable、addressable 恒为 false |
| 2026-09-16 | `BorrowTypeMetadata` 的覆盖形态照抄 FixedArray：sentinel `runtimeOnly` + 合成实例 Suite | 这种元数据不进 section，fixture 到不了；活路径由 SwiftInspectionTests 在 6.4 运行时上覆盖 |
| 2026-09-16 | 实现完成并验证通过，状态保持 In Progress（落地 commit 时改 Implemented 并分配编号） | Xcode 26.6 + 本地 sibling（swift-demangling next @ 6def38a = 0.7.0）：`MachOSwiftSectionTests \| SwiftLayoutTests \| SwiftInspectionTests \| SwiftDumpTests` 1130 测试 / 225 套件，唯一失败是覆盖不变量要求把 `isAddressableForDependencies` 登记为 pure-data sentinel，补登记后 21 测试复跑全绿（原始退出码 0）；`BorrowLayoutTests` 七条、`RuntimeMetadataTypeBuilderTests.builtinBorrowFollowsTheRuntimeEntryPoint`（本机走「缺入口」分支）全过；regen-baselines 只产生套件索引 +1、VWT flag 基线新增一位、新 Borrow 基线三处变化 |
