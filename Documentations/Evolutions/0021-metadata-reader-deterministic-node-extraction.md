# 0021 - MetadataReader 符号引用解析去搜索化：ObjC protocol 引用与 extension 目标按 ABI 固定形状取节点

- **状态**: Implemented
- **创建日期**: 2026-09-09
- **最后更新**: 2026-09-09

## 摘要

`SwiftInspection/MetadataReader.swift` 的符号引用解析器里有两处靠深度优先搜索「找第一个像样的节点」的 helper：`.objectiveCProtocol` 分支用 `typeSymbol` 在整棵树里找第一个 `.type`（找不到就把第一个 nominal 包成 `.type`），`.extension` 分支用 `extensionSymbol` 找第一个 enum / struct / class / protocol 节点；另有一个全仓库无人调用的 `nodes(for:)`。这些 helper 写于不了解这两个字段 ABI 形状的时期，靠「样本里恰好都是这个形状」一直没出错。本提案把它们换成按 ABI 规定的固定形状逐层取节点：形状对得上就取，对不上返回 nil，绝不继续往下钻返回一个碰巧遇到的节点。现有样本的输出逐字节不变。

## 方案

**改动位置**（行号以 `next` 当前状态为准）：

1. `Sources/SwiftInspection/MetadataReader.swift:328-334`，resolver 的 `.objectiveCProtocol` 分支。IRGen 的 `getObjCProtocolRefSymRefDescriptor` 把协议的声明类型以 `FlatUnique` 角色 mangle 进 prefix 的第二个字段，即 `So9NSCopying_p` 这样的单协议存在类型，且保证不含符号引用。按 type demangle 的结果固定是四层，upstream `MetadataReader.h` 也是硬取这四层：

   ```
   Type
   └── ProtocolList
       └── TypeList
           └── Type
               └── Protocol(Module, Identifier)
   ```

   新实现改用项目自己的 `demangle(for:kind:.type,in:)` 解 prefix 里的 `MangledName`，然后逐层验 kind 取到第四层的 `Type(Protocol)` 返回；任何一层 kind 不符返回 nil。demangler 的 `popProtocol` 接受的正是 `Type(Protocol)`，与今天的输出一致。

2. `Sources/SwiftInspection/MetadataReader.swift:435-445`，`.extension` 分支。IRGen 的 `addExtendedContext` 写进去的是 `getSelfInterfaceType()`：非泛型类型是裸 nominal，泛型类型是带参数的 bound generic（`Array<A>`），protocol extension 是 `Self` 泛型参数。运行时 `stdlib/public/runtime/Demangle.cpp` 处理同一字段的做法是「去掉 `Type` 壳，若是 `BoundGenericEnum` / `BoundGenericStructure` / `BoundGenericClass` / `BoundGenericOtherNominalType` 就取 `child(0).child(0)`」。demangler 从符号解出 `Extension` 节点时第二个孩子必须满足 `Node.Kind.isAnyGeneric`。新实现照此逐层取：`Type` 的第一个孩子；若是上述四种 bound generic 再取其第一个孩子（`Type`）的第一个孩子；最后要求结果 `kind.isAnyGeneric`，否则 nil。

3. `Sources/SwiftInspection/MetadataReader.swift:589-652`，整个 `extension Node` 块删除（`typeSymbol` / `typeNonWrapperSymbol` / `extensionSymbol` / `nodes(for:)`）。

**行为变化**：

- 现有样本输出逐字节不变。两个 helper 在上述形状上恰好停在同一个节点。
- protocol extension 的 `Self` 目标：以前 nil，现在还是 nil。类型不能嵌套在 protocol extension 里（编译器诊断 `unsupported_type_nested_in_protocol_extension`），这种 descriptor 只经由函数内局部类型的匿名上下文到达，`adoptAnonymousContextName` 那条路用匿名上下文自带的完整名字绕过了它。
- extension 目标新增接受 `typeAlias` / `otherNominalType` / `typeSymbolicReference` / `protocolSymbolicReference` / `objectiveCProtocolSymbolicReference`（`isAnyGeneric` 集合）；以前 DFS 会跳过这些节点继续往里钻。
- 遇到没预料的形状时返回 nil 让上层降级，而不是返回树里第一个碰到的 nominal。

**不动的地方**：`readProtocol` 里处理 `_TtP` 名字的 while 循环（照抄 upstream 的另一条路径）；`.anonymous` 分支的 `first(of: .privateDeclName)`；resolver 其它分支；`MetadataReaderCache`；`buildContextDescriptorMangling` 的 `.symbol` 分支未剥 `Type` 壳的问题（另案）。

**测试**：

- `.extension` 分支已有覆盖：`SymbolTestsCore` 里 `extension Generics.GenericRequirementTest.RawRepresentableNestedStruct { struct NestedStruct {} }` 走的是「嵌套在泛型父类型里的 nominal」的 bound generic 形状，`SwiftInterfaceTests` 的 interface 快照钉着它。改完跑 `SwiftInterfaceTests` / `SwiftDumpTests` 快照套件。
- `.objectiveCProtocol` 分支当前零覆盖：`SymbolTestsCore` 里没有任何以 ObjC 协议做存在类型的字段，`GenericStructObjCProtocolRequirement<A: NSCopying>` 走的是 generic requirement 的 protocol 指针路径，不是 mangled name 里的 `\x0C` 符号引用。新增 `Tests/SwiftInspectionTests/ObjCProtocolSymbolicReferenceTests.swift`：沿用 `VTableSlotAttributionTests` 的 on-the-fly `swiftc` fixture 模式，`-target arm64-apple-macosx15.0`（ObjC 协议符号引用的运行时门槛是 feature availability 6.0，即 macOS 15），fixture 含一个 class 保证有 `__DATA` 段，字段 `var copyable: any NSCopying` 与 `var both: any NSObjectProtocol & NSCopying`；断言 `MetadataReader.demangleType` 对这两个字段的打印结果为 `__C.NSCopying` 与 `__C.NSObjectProtocol & __C.NSCopying`，并断言 resolver 返回节点的形状是 `Type(Protocol)`。

**未问即定的假设**：

- protocol extension 的 `Self` 不做「从 requirement `Self: P` 恢复协议」的补强，保持与运行时一致的 nil。
- bound generic 只认运行时列出的四种；`boundGenericProtocol` / `boundGenericTypeAlias` 不可能出现在 canonical 的 self type 里。
- ObjC 协议引用的覆盖用 on-the-fly fixture，不改 `SymbolTestsCore`：改后者要重建 fixture 并重生成 baseline，而这条路径只需一个能编译的小 dylib。
- 不需要新的设计文档；落地时补一份 task report，并在 `ProjectEvolutionLog.md` 追加一节。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-09 | Created as Draft | 用户原话：「看看怎么把这些扩展去掉，这是我很久之前写的，当时并不理解这些内部机制，不过运行这么久没碰到问题，可能是样本量不够」 |
| 2026-09-09 | 走轻量档，先写精简提案再动手 | 用户在档位提问中选择。改动约几十行、行为保持，但要进 `next`。 |
| 2026-09-09 | protocol extension 的 `Self` 目标不做恢复，保持 nil | 与运行时 `Demangle.cpp` 一致；该 descriptor 只经匿名上下文到达，那条路已有完整名字。 |
| 2026-09-09 | `\x0C` 引用的覆盖用 on-the-fly `swiftc` fixture | `SymbolTestsCore` 无此形状；加进去要重建 fixture 与重生成 baseline。 |
| 2026-09-09 | Accepted → In Progress | 用户回复「ok」批准提案；同日开始实现。 |
| 2026-09-09 | helper 可见性 fileprivate → internal | 用手搭的树做纯形状单测（错误形状必须返回 nil 的分支，fixture 覆盖不到）。 |
| 2026-09-09 | 组合存在类型测试期望改为 `__C.NSCopying & __C.NSObject` | `NSObjectProtocol` 在 mangling 里是 ObjC 运行时名 `NSObject`（`So8NSObject_p`），Swift 侧改名归 APINotes / TypeIndexing，demangler 不做。 |
| 2026-09-09 | In Progress → Implemented | 代码、7 条测试、task report 与演进账本同批落地；全量套件仅已知的两条墙钟 flaky 测试假失败，单独重跑通过。不需要配套 guide / implementation note（helper 的依据已写在代码文档注释与 task report 里）；未引入新术语，术语表不动。编号待落地 `next` 的 commit 分配。 |
