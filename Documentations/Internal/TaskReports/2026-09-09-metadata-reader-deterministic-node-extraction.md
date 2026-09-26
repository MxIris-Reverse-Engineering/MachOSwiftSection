# 2026-09-09 MetadataReader 符号引用解析去搜索化

对应提案：[0021-metadata-reader-deterministic-node-extraction](../../Evolutions/0021-metadata-reader-deterministic-node-extraction.md)

## 问题

用户问上游 `swift/include/swift/Remote/MetadataReader.h` 的 demangle 部分是不是过时了：项目里的实现是当年魔改出来的，试过完全照上游写却跑不通。对比过程中顺带看到 `Sources/SwiftInspection/MetadataReader.swift` 末尾一组早年写的 `Node` 扩展（`typeSymbol` / `typeNonWrapperSymbol` / `extensionSymbol` / `nodes(for:)`），都是「在整棵树里深度优先找第一个像样的节点」，写的时候并不清楚对应字段的 ABI 形状，靠样本里恰好都是那个形状一直没出错。用户要求把它们去掉。

## 调研

**上游是否过时**：不过时。checkout 是 swift-6.3.2-RELEASE，demangle 相关代码最近一次改动是 2025 年 12 月（LLDB 用的「descriptor 有符号就先用符号」快捷路径）。照抄行不通的根因是目标不同：上游的树喂给 `TypeDecoder` 和 `TypeBuilder`，后者拿到树还会继续读内存，所以它故意把地址留在节点里、形状也不对齐 `Demangler` 从字符串解出来的树；我们的树要直接进 `NodePrinter` / `Remangler` / 符号索引的结构比较，形状必须与 demangler 一致。具体差异分三类：上游确实落后的两处（extension 泛型签名的 `SameShape` / `InvertedProtocols` 是 `llvm_unreachable`；`AccessorFunctionReference` 直接返回空让整条 mangled name 失败），上游故意与 demangler 形状不一致的五处（Extension 第二个孩子带 `Type` 壳、匿名上下文用 `$<地址>` 做标识符、extended existential shape 只存地址、opaque 引用默认直接构造 `OpaqueReturnTypeOf`、resolver 签名是 `(kind, directness, offset, base)`），以及上游有而我们没有的（`TypeImportInfo` 的 ABI 名覆盖与 C 导入类型的种类改写；全种类的 descriptor 符号快捷路径）。另发现 `buildContextDescriptorMangling` 的 `.symbol` 分支未剥 `Type` 壳、剥壳逻辑在永远不返回 `Type` 的 `.element` 分支上，疑似抄错位置，另案处理。

**两个字段的 ABI 形状**：

- ObjC protocol 符号引用（`\x0C`）：IRGen `getObjCProtocolRefSymRefDescriptor` 把 `protocol->getDeclaredType()` 以 `FlatUnique` 角色 mangle 进记录的第二个字段，即 `So9NSCopying_p` 这样的单协议存在类型，不含符号引用。按 type 解出来固定是 `Type → ProtocolList → TypeList → Type(Protocol)` 四层，上游 `MetadataReader.h` 就是硬取四层；demangler `popProtocol` 接受的正是 `Type(Protocol)`。发射门槛是 feature availability `ObjCSymbolicReferences` = 6.0（macOS 15），IRGen 选项 `EnableObjectiveCProtocolSymbolicReferences` 默认开。
- extension 的 `ExtendedContext`：IRGen `addExtendedContext` 写的是 `getSelfInterfaceType()`，`lib/AST/Decl.cpp` 里该函数对 protocol 返回第一个泛型参数（`Self`），其余返回声明类型，泛型类型即 `Array<A>` 的 bound generic。运行时 `stdlib/public/runtime/Demangle.cpp` 处理同一字段：去 `Type` 壳，四种 `BoundGeneric*` 取 `child(0).child(0)`。demangler 从符号解 `Extension` 时第二个孩子必须满足 `Node.Kind.isAnyGeneric`。类型不能嵌套在 protocol extension 里（诊断 `unsupported_type_nested_in_protocol_extension`），所以 protocol extension 的 descriptor 只经函数内局部类型的匿名上下文到达。

**覆盖现状**：extension 分支由 `SymbolTestsCore` 快照覆盖（`extension Generics.GenericRequirementTest.RawRepresentableNestedStruct { struct NestedStruct {} }` 走 bound generic 形状）；`\x0C` 引用零覆盖，fixture 里 `GenericStructObjCProtocolRequirement<A: NSCopying>` 走的是 generic requirement 的 protocol 指针路径。

## 方案

见提案。要点：两个分支改成逐层验 kind 取节点，对不上返回 nil；删掉整个 `extension Node` 块；`\x0C` 路径用 on-the-fly `swiftc` fixture 补覆盖。

## 实际执行

- 代码按提案落地。两个 helper 做成 `MetadataReader` 的 internal static 函数（提案写的是 fileprivate），便于用手搭的树做纯形状单测。
- 新增 `Tests/SwiftInspectionTests/MetadataReaderFixedShapeExtractionTests.swift`，7 条测试：5 条手搭树的纯形状测试（四层正确形状取到内层 `Type(Protocol)`；裸 nominal / 协议位置放 struct / 缺顶层 `Type` 三种错误形状返回 nil；非泛型 extension 目标、bound generic 目标、protocol extension 的 `Self` 与缺 `Type` 壳）+ 2 条 on-the-fly fixture 测试（`-target arm64-apple-macosx15.0`，字段 `any NSCopying` 与 `any NSObjectProtocol & NSCopying`；先用 `MangledName.lookupElements` 断言字段确实带 `\x0C` 引用作为前提，再断言打印结果与节点形状）。
- 写测试时纠正两处自己的假设：`NSObjectProtocol` 在 mangling 里是 ObjC 运行时名 `NSObject`（`So8NSObject_p`），Swift 侧的改名是 APINotes / TypeIndexing 的事，期望值改为 `__C.NSCopying & __C.NSObject`；钉住的 swift-demangling 0.6.0 里 `createTransient` 是 `@_spi(Internals)`，`Node.children` 是 `Node.Children` 而非数组。

## 验证

- 新套件：`swift test --filter MetadataReaderFixedShapeExtractionTests` 7/7 通过，退出码 0（取自 `swift test` 本身）。
- 全量：`swift test --skip IntegrationTests`，1661 条测试 / 310 个套件，417 秒，仅 2 条失败且都是 `SharedCacheTests` 里用墙钟断言并行度的 `differentKeysParallelViaTaskGroup` / `differentKeysParallelViaAsyncLet`（已知的全量跑假失败，单独重跑 2/2 通过、退出码 0）。其余全部通过，包括 `SwiftDumpTests` / `SwiftInterfaceTests` 的 `SymbolTestsCore` 快照套件与 `MachOSwiftSectionTests` 的 fixture 基线套件，即 extension 分支的 bound generic 形状在快照上逐字节不变。退出码取自 `swift test` 本身。
- 红/绿说明：这是行为保持的重构。两条 fixture 测试在旧代码上也会通过（旧 DFS 恰好停在同一个节点），它们是回归钉；旧实现与新实现的差别在 5 条纯形状测试覆盖的「错误形状」分支——旧 DFS 会继续往下钻返回碰到的第一个 nominal，新实现返回 nil。

## 与提案的偏离

- helper 可见性从 fileprivate 放宽到 internal，为了纯形状单测。其余无偏离。

## 环境备忘

- 主检出的 `Tests/Projects/SymbolTests/DerivedData` 目录为空，全盘也没有其它 `SymbolTestsCore` Release 构建。按 CI 的方式（`CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO`）把 fixture 构建到隔离目录 `/tmp/claude/DerivedData/SymbolTests`，`__text` 在 `0x13e8`，与基线生成时的签名布局一致。经用户选择，把 worktree 里的 `Tests/Projects/SymbolTests/DerivedData` 符号链接改指向 `/tmp/claude/DerivedData`；原目标是主检出的同名目录，改回用 `ln -sfn /Volumes/Repositories/Private/Org/MxIris-Reverse-Engineering/MachOSwiftSection/Tests/Projects/SymbolTests/DerivedData Tests/Projects/SymbolTests/DerivedData`。`/tmp` 重启后清空，届时需重建。
- 未执行 `swift package update`：它会改写 `Package.resolved`，而仓库刻意把 swift-demangling 钉在 0.6.0（0.6.1 的执行器改动让 dump 慢 3–4 倍，见 2026-09-02 任务报告）。
- XcodeBuildMCP CLI 的 `swift-package test` 没有 scratch path 参数，无法隔离构建产物，降到 `swift test --scratch-path`。
