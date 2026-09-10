# 0025 - Key path component header 与 property descriptor 的 ABI 模型

- **状态**: Implemented
- **创建日期**: 2026-09-10
- **最后更新**: 2026-09-10
- **关联提案**: [0018](0018-self-contained-abi-layer.md)（ABI 层自足，本提案的符号侧入口为什么不在这一批）

## 摘要

给 `MachOSwiftSection` 加一组 key path 的 ABI 模型：4 字节的 `KeyPathComponentHeader`，以及建立在它之上的 `PropertyDescriptor`。

property descriptor 是编译器为每个处在 ABI 边界上的属性发出的一小块常量数据，符号形如 `$s3Lib5PointV1xSdvpMV`（mangling 后缀 `MV`）。它是**跨模块 key path 的 resilience 间接层**：外部模块形成 `\Point.x` 时并不知道 `x` 是 stored（偏移多少）还是 computed（调哪个 getter），于是它发出的 key path pattern 里只放一个指向本 descriptor 的相对指针，运行时再把 descriptor 的内容拷进来。定义模块换了实现，client 不必重编译。

它不是一个 C++ 结构体，所以在 `include/swift/ABI/` 下找不到同名类型——它的内容就是**一个 key path component 的序列化字节**，格式定义在 `swift/shims/KeyPath.h` 的 `_SwiftKeyPathComponentHeader_*` 常量里，发出在 IRGen 的 `IRGenModule::emitSILProperty`，解析在 stdlib 的 `KeyPath.swift`。本提案把这套编码建成本库的 ABI 模型。

它也不在任何 `__swift5_*` section 里，因此没有 section 遍历入口；唯一的进入方式是拿到一个 offset 后 `PropertyDescriptor.resolve(from:in:)`。offset 从哪来（通常是 `…vpMV` 符号）由调用方决定，不在本提案范围内。

## 方案

### 落点

全部新增，位于新目录 `Sources/MachOSwiftSection/Models/KeyPath/`：

| 文件 | 内容 |
| --- | --- |
| `KeyPathComponentKind.swift` | `external` / `struct` / `computed` / `class` / `optional` 五个 discriminator |
| `KeyPathComponentHeader.swift` | 4 字节 header，`RawRepresentable` + 位访问器，写法对齐 `MethodDescriptorFlags` |
| `KeyPathComputedIdentifier.swift` | computed 的 identifier kind 与 resolution 两个枚举 |
| `KeyPathStoredFieldOffset.swift` | stored 偏移的四种形态 |
| `KeyPathComputedPropertyBody.swift` | computed body 的已解析结果 |
| `PropertyDescriptor.swift` | descriptor 本体，写法对齐 `FieldDescriptor`（固定 header + trailing 变长 body） |

不动任何既有模型、不动 section 扫描、不动 dump / interface 的输出。

### header 建成通用的，不是 property-descriptor 专用的

同一个 4 字节编码同时用在 key path pattern 的 component 和 property descriptor 上，两者共享全部位定义。因此 `KeyPathComponentHeader` 按完整语义建模，包含只在 pattern 里出现的 `external` / `optional` 两个 kind、`hasComputedArguments` 和 `isEndOfReferencePrefix`，并同时提供两个 body 长度：

```swift
public var propertyDescriptorBodySize: Int   // forPropertyDescriptor: true
public var patternComponentBodySize: Int     // forPropertyDescriptor: false
```

代价是几个当前用不到的枚举 case，好处是以后要解析 key path pattern 全局变量时，不必改动已发布的 API。

### 变长规则

body 长度取 `KeyPath.swift` 的 `_componentBodySize(forPropertyDescriptor:)`：

- trivial（整个 `UInt32 == 0`）：0
- `struct` / `class` 且偏移内联在 header 低 23 位：0
- `struct` / `class` 且 payload 是 `unresolvedFieldOffset` / `unresolvedIndirectOffset` / `outOfLine` 三个哨兵之一：4（body 里一个 `UInt32`）
- `computed`：identifier(4) + getter(4)，settable 再 +4 的 setter。**property descriptor 永远不带 arguments**，所以不加那 12 字节；pattern component 才加
- `optional`：0
- `external`：`4 * (1 + payload)`，只在 pattern 里出现

### API 形态

纯指针算术的做属性，需要读 body 的按本库惯例给三条 leg（`MachOFile` / in-process pointer / `ReadingContext`），与 `FieldDescriptor.records` 同构：

```swift
public struct PropertyDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let header: KeyPathComponentHeader
    }
    public var layout: Layout
    public let offset: Int
}

extension PropertyDescriptor {
    public var header: KeyPathComponentHeader { layout.header }
    public var isTrivial: Bool
    public var bodySize: Int
    public var size: Int                                  // 4 + bodySize
    public var inlineStoredFieldOffset: KeyPathStoredFieldOffset?   // 无需读 body 的那一路

    public func storedFieldOffset<MachO>(in machO: MachO) throws -> KeyPathStoredFieldOffset?
    public func computedPropertyBody<MachO>(in machO: MachO) throws -> KeyPathComputedPropertyBody?
}
```

`KeyPathComputedPropertyBody` 的构造函数是 `package` 而非 `public`——它是解析产物，只由 `PropertyDescriptor` 产出，不该由调用方拼装。里面的 getter / setter 暴露为**已解析的文件偏移**（`Int?`，null 相对指针给 `nil`），语义与 `MethodDescriptor.implementationOffset` 完全一致：纯相对指针算术，把符号归属留给上一层。identifier 只在它确实是相对指针时（`identifierKind == .pointer`）解析出偏移，按 stored-property / vtable-offset 编码时保留原始字。

### 覆盖

fixture `SymbolTestsCore` 是 `BUILD_LIBRARY_FOR_DISTRIBUTION = YES`，含 487 个 `MV` 符号，四种形态齐全。picker 按符号名各取一个（`PropertyDescriptorFixtureSymbol`），实测：

| 符号 | offset | header | 形态 |
| --- | --- | --- | --- |
| `StaticMemberStructTest.storedConstant` | `0x3f400` | `0x00000000` | trivial（模块共享，多个符号 alias 到同一地址） |
| `MarkerConformingStructTest.value` | `0x3dcd8` | `0x01800000` | struct，偏移 0 内联在 header |
| `PropertyWrapperStruct.wrappedValue` | `0x38b80` | `0x01fffffe` | struct，`unresolvedFieldOffset`，body = `0x20` |
| `CodableClassTest.identifier` | `0x56020` | `0x02400000` | computed settable，body 12 字节，getter 落 `0x784c` |

新增四个 Suite（`PropertyDescriptorTests` / `KeyPathComponentHeaderTests` / `KeyPathStoredFieldOffsetTests` / `KeyPathComputedPropertyBodyTests`，共 43 个 `@Test`）落在 `Tests/MachOSwiftSectionTests/Fixtures/KeyPath/`，按 AGENTS.md 的覆盖契约注册 `registeredTestMethodNames` 并生成 baseline。property descriptor 无法承载的两种 kind（`external` / `optional`）和 `isEndOfReferencePrefix` 由构造出的 header 字覆盖，所以 pattern 侧的访问器不是死代码。

**按符号取 offset 的两个陷阱**（写进了 picker 的注释）：符号表用带前导下划线的拼法；且 Release 产物里有**同名的 stab 调试项**（`n_type` 0x20、`n_value` 0），先匹配到它会静默读到 Mach-O 文件头。过滤条件是 `symbol.nlist.flags?.stab == nil`。

## 决策日志

**符号侧入口不在这一批。** 从 `…vpMV` 符号名查 offset 需要符号索引，而提案 0018 规定 `MachOSwiftSection` 只依赖 `MachOBase`，够不到 `MachOSymbols`。按既有分工（`MethodDescriptor.implementationOffset` 与 `SwiftInspection.implementationSymbols(in:)` 的关系），符号那一步应当落在 `SwiftInspection`，作为独立一批。本批的读取入口是现成的 `Resolvable.resolve(from:in:)`。

**没有 section 入口不是缺陷。** property descriptor 落在 `__TEXT,__const`（含相对指针的落 `__DATA_CONST,__const`），没有任何 `__swift5_*` 记录指向它，运行时也只经由 key path pattern 的相对指针到达。本库不为它编造一个"全镜像扫描"入口。

**identifier 不解释语义。** 它的含义由 header 的 kind 与 resolution 决定（stored-property 偏移 / vtable 偏移 / 相对指针，后者还分 resolved、absolute、indirect pointer、function call 四种解析方式）。本层只诚实地给出原始字与"它是不是指针、指向哪个偏移"，怎么用是上层的事。

**`kind` 返回 optional。** discriminator 有 7 位而只有 0–4 有效，读的是任意二进制，无效值必须能表达出来，不能像 `MethodDescriptorFlags.kind` 那样强解。
