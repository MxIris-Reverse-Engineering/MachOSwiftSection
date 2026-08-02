# Accessor-Function Symbolic Reference 的渲染与解析阶梯

## 背景：kind-9 引用是什么、怎么触发

Swift 的 field record 里存的类型名通常是可 demangle 的 mangled name，但有一类例外：当 payload 类型的 mangling 用到了「部署目标的 runtime demangler 不认识」的语言特性时，编译器不再嵌入类型名，而是嵌入一个字节 `0x09` + 指向 metadata accessor thunk 的相对指针——运行时解析这种引用不做 demangle，直接调用该函数拿 metadata。这是为向后部署新类型系统特性设计的逃生门（swiftlang/swift `lib/IRGen/GenReflection.cpp`：`getRuntimeVersionThatSupportsDemanglingType` 逐特性判最低 runtime 版本，`mangledNameIsUnknownToDeployTarget` 命中则走 `getTypeRefByFunction`）。

实测触发案例（Xcode 26.5 的 Testing.framework，即 swift-testing，部署目标低于 macOS 15）：

- `Event.Kind.valueAttached(_ attachment: Attachment<AnyAttachable>)`——`Attachment<AttachableValue: Attachable & ~Copyable>` 的泛型签名带 inverse requirement，mangling 需要 Swift 6.0 runtime；
- `TypeInfo._Kind.type(_ type: any (~Copyable & ~Escapable).Type)`——带 inverse 的 protocol composition，同样需要 6.0。

随着各框架采用 noncopyable/nonescapable 泛型并保持向后部署，这类引用会越来越常见。

离线（`MachOFile`）读取器不能执行目标二进制的代码，所以这种引用**构造上不可解析**：`MetadataReader` 把 thunk 的文件偏移存进 node 的 index（`MetadataReader.swift` 的 `.accessorFunctionReference` 分支），Demangling 包的 `NodePrinter` 打出兜底文案 `accessor function at <offset>`。

## 症状与历史

`SwiftPrinting` 自己的节点渲染器家族（`NodePrintable` 及四个分类 printer）不认识 `.accessorFunctionReference` 这个 kind，`dispatchPrintName` 全部 miss 后静默返回——节点渲染为空串。叠加枚举 case 的「mangled name 非空就加括号」gating，interface 输出出现 `case type()` / `indirect case valueAttached()`，`swiftc -parse` 拒绝（"enum element with associated values must have at least one associated value"）。

这个 bug 早于 leaf 迁移：迁移前（`aa233bc^`）的 interface 对同一二进制输出逐字节相同的空括号。迁移后的 main 改按「渲染文本」gating，意外遮住了它，但代价是 Void payload 回归（`case a(Void)` 塌成裸 `case a`）；PR #98 恢复 mangled-name gating 后空括号重新暴露。dump CLI 一直显示 `case type(accessor function at 750396)`，因为 `swift-section dump` 配的 resolver 走 Demangling 包的 `NodePrinter`（有兜底文案），而 interface 配的是 `SwiftPrinting` 的渲染器（没有）。

## 解析阶梯（能真解析就真解析，不能就诚实占位）

### 层 0：占位渲染补齐（已实现，2026-08-02，随 PR #98）

- `SwiftPrinting/NodePrintables/NodePrintable.swift` 的 `printNameInBase` 补 `.accessorFunctionReference` case，文案与 Demangling `NodePrinter` 逐字一致（`accessor function at <index>`），保证 dump/interface 两路拼写一致。
- `FieldFlags.hasMangledTypeName`（`SwiftDeclaration`）：index 时从 field record 捕获「mangled type name 非空」，`renderModelFields` 的 payload gating 改读模型 flag，不再按下标读 record（消除位置对齐的隐式依赖）。
- 双防护网：`printThrowingEnumCase`（interface 路径）与 `EnumDumper.fields`（dump 路径）在 payload 渲染结果为空串时退回裸 case——括号绝不包空。防将来再出现未覆盖 kind 时复发非法 `case name()`。

明确的限制：`case type(accessor function at 750396)` 依然不是合法 Swift——离线本就还原不出类型名，这是诚实标注（与 dump 的历史行为一致），不是可编译输出。要真类型名需要下面两层。

### 层 1：进程内真解析（待做）

kind-9 的设计意图就是「调函数拿 metadata」，进程内完全可以照做。库里已有同类先例：layout 注释路径的 `resolveFieldMetatype` 对每个非泛型字段都在调 `getTypeByMangledNameInContext`，特化替换路径（`SpecializedMetadataNodeSubstitution`）也在用 `_mangledTypeName` + `demangleAsNode` 回读节点，所以不引入新的风险类别。

- 助手放 `MachOSwiftSection/Runtime/RuntimeFunctions.swift` 旁：`demangledNodeByResolvingAccessorFunction(for: MangledName, in: MachOImage) -> Node?`——整条 mangled name 交给 `swift_getTypeByMangledNameInContext`（runtime 会执行 thunk），成功后 `_mangledTypeName(metatype)` → `demangleAsNode` 得到真实节点。
- 两个挂接点（kind-9 只在 Reflection/FieldMetadata 两个 role 下发出，即 field record，所以这两处覆盖全部实际出现）：`FieldRecord.demangledTypeNode(in:)`（`SwiftDeclaration/Extensions.swift`，interface/模型索引路径）与 `TypedDumper.fieldDemangledTypeNode(for:)`（`SwiftDump`，dump 路径）。mangled name 含 `0x09` 控制字节且 reader 是进程内 `MachOImage` 时先走助手，失败（泛型上下文缺实参等）回落层 0 占位。
- 边界：`MetadataReader` 本体保持纯读取——「执行目标代码」是策略决定，留在字段入口层，不下沉进底层 reader。
- 效果：RuntimeViewer 与进程内 dump/interface 直接显示 `case valueAttached(Testing.Attachment<Testing.AnyAttachable>)`。

### 层 2：离线符号表还原（待验证可行性）

编译器给 thunk 起的符号名内嵌完整类型 mangling：`IRGenMangler.cpp` 的 `mangleSymbolNameForMangledMetadataAccessorString` 产出 `get_type_metadata <generic-signature><type-mangling>`，noncopyable 类型再追加 ` noncopyable` 后缀，private linkage 本地符号。离线拿 node 里存的文件偏移查 `SymbolIndexStore`，命中这种符号就剥前缀 demangle 出真类型——纯符号表读取，不执行代码，可以放进 `MetadataReader` 的离线分支。

限制与前置：strip 过的 OS 框架查不到（Testing.framework 实测已 strip，nm 只能看到偏移前 16 字节处相邻的枚举自身 metadata accessor）；只对未 strip 的用户二进制生效。立项前先在一个未 strip 的向后部署二进制上验证符号确实保留、且带泛型签名的符号后缀能被 demangler 接受。

## 验证

- 单测：`NodePrinterTests.typeNodePrinterAccessorFunctionReference`（合成 kind-9 节点，钉兜底文案）；`EnumCaseRenderingParityTests`（Void payload 括号与两路拼写一致，不受影响）。
- A/B：Testing.framework（arm64e）整文件 interface diff——层 0 前后仅三行变化，全部是修复本身：`indirect case valueAttached()` → `indirect case valueAttached(accessor function at 428216)`、`case type()` → `case type(accessor function at 750396)`，以及一处此前没被发现的**存储字段**同源问题 `var _storage: `（悬空冒号，同样非法）→ `var _storage: accessor function at 283740`（`Attachment` 的 `Allocated<AttachableValue>` 字段）。三行均与 dump 路径拼写逐字一致。
