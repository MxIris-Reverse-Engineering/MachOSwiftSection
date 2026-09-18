# Draft - 只用一次的泛型参数改写为 opaque parameter（`some`）

- **状态**: In Progress
- **创建日期**: 2026-09-17
- **最后更新**: 2026-09-17
- **所属愿景**: 无
- **关联提案**: 无
- **实现分支 / PR**: `next`
- **配套文档**: 无（纯签名书写形式的统一，不改变任何模块的职责）

## 摘要

仓库里绝大多数「读某个镜像」的函数都写成显式泛型：

```swift
public func parent<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> SymbolOrElement<ContextDescriptorWrapper>?
```

其中的泛型参数 `MachO` 只被用了一次——就是它自己那个形参的类型。它既没出现在返回类型里，也没出现在 `where` 子句里，函数体里更没有以 `MachO.self`、`[MachO]`、`Array<MachO>` 之类的形式被提到。这种情况下，泛型参数列表纯属噪音：它给一个只出现一次的类型起了个名字，读者却要先扫一遍 `<…>` 才知道形参的约束是什么。SE-0341 的 opaque parameter 就是为这个场景准备的语法糖：

```swift
public func parent(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> SymbolOrElement<ContextDescriptorWrapper>?
```

两种写法生成的泛型签名完全相同，mangling 相同，ABI 相同——这是纯粹的书写形式变更，不是行为变更。

本批把仓库里满足判据的 522 处泛型参数改成 opaque parameter，覆盖 `Sources/` 与 `Tests/`（不含 fixture 源码，见下）。

## 方案

### 判据

一个泛型参数被改写，当且仅当**同时**满足：

1. **带内联约束**。`<MachO: MachOSwiftSectionRepresentableWithCache>` 可以改；裸的 `<Element>`（约束写在 `where` 子句里，或压根没有约束）不改——前者会落到第 3 条，后者无处安放 `some`。
2. **在形参列表里恰好出现一次，且出现在某个形参类型的顶层**。`machO: MachO` 与 `machO: inout MachO` 都算顶层；`values: [T]`、`keyPath: KeyPath<Layout, [Pointer]>` 这类嵌套位置虽然语法上写得出 `[some P]`，但可读性反而下降，本批一律跳过（12 处）。
3. **在别处一次都不出现**：返回类型、`where` 子句、函数体、以及兄弟泛型参数的约束里，都不能提到它。

第 3 条里的前两项不是保守，是语法上根本写不出来——`func f<Element: P>(x: Element) -> Element` 里的返回类型没有东西可以指代那个 `some P`；`where Element.Index == Int` 同理。第三项（函数体）才是这次真正要判断的东西，也是编译器能替我们兜底的那一项：改错了，编译立刻报 `cannot find type 'MachO' in scope`。

### 三个前提，用 typecheck 探针实测过，不凭记忆

1. **opaque parameter 可以直接写在 protocol requirement 里**。`protocol P { func f(x: some Q) }` 通过类型检查。因此 `PointerProtocol`、`Resolvable`、`ContextDescriptorProtocol`、`Dumpable`、`Definition` 等协议的**要求声明本身**也在本批改写范围内（32 处），不需要在协议里保留泛型写法、只在实现里用 `some`。
2. **要求侧与实现侧的写法可以不一致，conformance 照样成立**。泛型形式的实现能满足 opaque 形式的要求，反过来也能。这条是安全网：某个实现因为函数体里用到了类型名而必须保留泛型写法时，它对应的协议要求仍然可以改成 `some`，不会破坏 conformance。
3. **`some` 不能出现在函数类型的形参位置**：`func f(handler: (some P) -> Void)` 报 `'some' cannot appear in parameter position in parameter type`。本批 522 处全部是 `label: Name` 的顶层形式，不触碰这条限制。

另外全仓没有任何 `@_specialize` 属性（只在注释里被提到），也没有显式泛型特化调用点（`f<Foo>(…)`），所以不存在调用点被这次改写打断的可能。

### 明确不动的

- **`Tests/Projects/SymbolTests/` 下的 fixture 源码。** 这是被编译成 `SymbolTestsCore` 二进制、供 ABI 基线比对的源码。改它会改变 fixture 的 ABI，进而让所有版本化的基线失效。首轮 dry-run 曾把 `OverloadedMembers.swift`、`ProtocolComposition.swift`、`StringInterpolation.swift`、`Subscripts.swift` 四个文件算进计划，已在改写脚本里加了显式排除。
- **146 处泛型参数在别处仍被引用**（返回类型带着它、`where` 子句约束它的关联类型、或函数体里用到类型名本身）。
- **105 处没有内联约束**。
- **12 处那一次出现嵌套在类型内部**（`[T]`、`[[MachO]]`、`TargetGenericContext<[H]>`、`KeyPath<Layout, [Pointer]>`）。

### 改写规模

| 约束 | 处数 |
| --- | --- |
| `MachOSwiftSectionRepresentableWithCache` | 179 |
| `ReadingContext` | 157 |
| `MachORepresentableWithCache & Readable` | 66 |
| `MachORepresentableWithCache` | 41 |
| `MachOFieldLayoutRenderable` | 41 |
| 其余零星（`ValueMetadataProtocol`、`Readable`、`FixedWidthInteger`、`Definition` 等） | 38 |

共 522 处，分布在 135 个文件。同一个函数带多个泛型参数时按参数逐个判断：`func resolveAny<T: Resolvable, MachO: MachORepresentableWithCache & Readable>(in machO: MachO) throws -> T` 里 `T` 出现在返回类型（不改）、`MachO` 只在形参出现一次（改），结果是 `func resolveAny<T: Resolvable>(in machO: some MachORepresentableWithCache & Readable) throws -> T`。

## 决策日志

- **为什么连 protocol requirement 一起改，而不是只改实现**：探针证明协议要求里写 `some` 合法，两侧写法又可以不一致。若只改实现侧，同一个方法在声明处和实现处长得不一样，读者要在两种形式之间来回翻译，反而比全不改更差。
- **为什么跳过嵌套位置的 12 处**：`func hexArray(values: [[some BinaryInteger & Sendable]])` 这类写法语法合法，但 `some` 埋在两层方括号里，读者需要停下来想它绑定到哪一层。泛型参数名在这里反而是有信息量的。
- **为什么不碰没有内联约束的 105 处**：把 `where` 子句里的约束搬进 `some` 需要逐条判断约束是否只涉及这一个参数，属于另一类改写；本批只做机械可判定的部分。
- **验证靠编译器，不靠人工复核**：判据第 3 条的「函数体里没用到」是由脚本按标识符出现次数判定的，正则解析 Swift 必然有边界情况。但这里的误判是**单向安全**的——漏改只是少改一处，误改一定编译不过（泛型参数被删掉之后，函数体里对它的引用会变成 `cannot find type in scope`）。因此验收标准就是全量构建加全量测试通过。

## 验证

- `swift build`：通过，0 error。
- `swift test --skip IntegrationTests`：全部 target 编译通过，0 编译错误；测试进程退出码 1，两个套件红：
  - `HostCacheSwiftUICoreMergedAccessorTests.theMergedAccessorFieldsAreReadOnTheHostCache()`（2 个 issue）
  - `MultiPayloadEnumDescriptorCacheTests.noncopyableMultiPayloadEnumDegradesToNoLayout()`（1 个 issue）
- **这两个套件与本批无关，已二分确认**：把 135 个文件还原到改写前状态（此时工作区逐字节等于 `a3ff2c45`）、在同一个 scratch 里跑同样两个 filter，得到**完全相同的三个 issue、相同的断言、相同的行号**。随后恢复改写后状态并逐字节校验一致，重新构建通过。

判据第 3 条依赖脚本对函数体的标识符扫描，而正则解析 Swift 有边界情况——这里的安全性来自误判方向单一：漏改只是少改一处，误改一定编译不过。全量测试 target 零编译错误，就是这条判据在 522 处上全部成立的证据。
