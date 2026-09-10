# 2026-09-10 property descriptor 的 ABI 模型

对应提案：[0025-key-path-component-and-property-descriptor](../../Evolutions/0025-key-path-component-and-property-descriptor.md)

## 问题

用户在二进制里看到大量 `…vpMV` 符号，去 Swift 源码里找不到叫 property descriptor 的结构，问它是什么、能不能读。追问下来落到两个具体判断上：有这个符号能不能推出属性是 `public`，以及能不能推出这个库开没开 library evolution。最后决定把结构按本库其它 ABI 模型的写法定义出来，之后就能拿符号的 offset 直接读。

## 调研

**它不是结构体**。`include/swift/ABI/` 下没有同名类型，因为它的内容就是**一个 key path component 的序列化字节**：4 字节 header 加一段长度由 header 决定的 body。三处定义分散在

| 内容 | 位置 |
| --- | --- |
| 字节格式（全部位常量） | `swift/…/SwiftShims/swift/shims/KeyPath.h` 的 `_SwiftKeyPathComponentHeader_*` |
| 谁发出、发什么 | `swift/lib/IRGen/GenKeyPath.cpp` 的 `IRGenModule::emitSILProperty` |
| 谁读它 | `swift/stdlib/public/core/KeyPath.swift`（`visitExternalComponent` 一带，3641 行起） |

SIL 层它叫 `sil_property`，一行文本，不是类型。

**它干什么**：跨模块 key path 的 resilience 间接层。client 形成 `\Point.x` 时不知道 `x` 是 stored（偏移多少）还是 computed（调哪个 getter），只在自己的 pattern 里放一个 `external` component 指向定义模块的 descriptor，运行时构造 key path 时读**当时**那份 descriptor 把真正的访问方式拷进来。

**发出条件**（`swift/lib/SIL/IR/SIL.cpp:447` `getPropertyDescriptorGenericSignature`）：闸门是 getter 的 SIL linkage 属于 `Public` / `PublicNonABI` / `Package` / `PackageNonABI`。实测一个覆盖各访问级别的 fixture，发出 descriptor 的有 `public`、`open`、**`package`**、**`@usableFromInline internal`**、`@_spi public`、`@inlinable`、`@_alwaysEmitIntoClient`，全是 external 符号；不发的有 `internal` / `fileprivate` / `private`。所以**有这个符号推不出 source-level `public`**，只能推出「在 ABI 边界上」。反方向更弱：ABI 兼容的 `override`、协议要求、全局 `public var`、`~Copyable` 类型的属性、mutating getter 都不发。

**能判断 library evolution，但要看内容不是看符号**。同一 fixture 两种模式对照：不开时该模块所有 descriptor 都是 trivial（值 0）且 alias 到同一地址；开了之后 stored 属性带上真实 offset。硬证据是 discriminator 为 struct(1) 或 class(3)——非 resilient 模块的 stored 属性一律走 `canStorageUseTrivialDescriptor` 的 `return true`，永远不会带 offset 出来。反例已确认：非 resilient 模块里 setter 可见性收窄的 computed 属性也会发非 trivial descriptor（discriminator 2），所以只有 struct/class tag 能用。这个判据与项目已有的 dispatch thunk（`Tj`）判据互补——纯 struct 的库开了 library evolution 也一个 thunk 都没有，实测 `Tj=0` 而 struct-tag MV=2。

## 最终方案

轻量档提案，只做 ABI 结构 + fixture 测试，符号侧入口留给下一批（提案 0018 规定 ABI 层只依赖 `MachOBase`，从符号名查 offset 属于 `SwiftInspection`）。header 按**通用** key path component 建模而不是 property-descriptor 专用，两个 body 长度并存。

## 实际执行

新增 `Sources/MachOSwiftSection/Models/KeyPath/` 六个文件；`BaselineFixturePicker` 追加按符号取 descriptor 的入口和四个具名 picker；`Generators/KeyPath/` 四个 baseline generator 并注册进 `BaselineGenerator`；`Tests/MachOSwiftSectionTests/Fixtures/KeyPath/` 四个 Suite 共 43 个 `@Test`。

三处实现期发现的问题：

1. `resolve(at:in:)` / `resolve(from:in:)` 有 `-> Self` 和 `-> Self?` 两个重载，在三元表达式和嵌套参数里会歧义。改成显式类型标注 + `if` 语句。
2. `KeyPathComputedPropertyBody` 不能是 `Hashable`——`RelativeDirectRawPointer` 只有 `Equatable`。
3. **按符号名取 offset 有两个陷阱**，都写进了 picker 的注释：符号表用带前导下划线的拼法；且 Release 产物里有**同名的 stab 调试项**，`n_type` 为 0x20、`n_value` 为 0，先匹配到它会静默读到 Mach-O 文件头——第一版 baseline 四个条目的 header 全是 `0xfeedfacf`（Mach-O magic）就是这么来的。过滤条件是 `symbol.nlist.flags?.stab == nil`。

`KeyPathComputedPropertyBody.init` 定为 `package`：它是解析产物，不该由调用方拼装，顺带也就不进 `PublicMemberScanner` 的覆盖清单。

## 验证

- 四种形态先用独立的 Python 解码器从 fixture 二进制读了一遍，再与 baseline generator 的产物逐字段对照，全部一致（`0x3f400` header 0 trivial、`0x3dcd8` header `0x1800000` 偏移 0、`0x38b80` header `0x1fffffe` body `0x20`、`0x56020` header `0x2400000` bodySize 12 getter `0x784c`）。
- `swift test --filter "PropertyDescriptorTests|KeyPathComponentHeaderTests|KeyPathStoredFieldOffsetTests|KeyPathComputedPropertyBodyTests"`：43 tests / 4 suites 通过，原始退出码 0。
- `MachOSwiftSectionCoverageInvariantTests` 通过，原始退出码 0。
- 全量 `regen-baselines` 只改动 `AllFixtureSuites.swift`（+4 行），其余 baseline 字节不变——顺带证明本机重建的 fixture 与既有 baseline 的构建布局一致（用的是 CI 那套 `CODE_SIGN_IDENTITY=-` + `CODE_SIGNING_REQUIRED=NO`）。

## 偏差

与提案没有偏差。提案里写的 API 形态就是落地的形态；唯一未在提案中预告的是 `KeyPathComputedPropertyBody.init` 的可见性下调为 `package`。
