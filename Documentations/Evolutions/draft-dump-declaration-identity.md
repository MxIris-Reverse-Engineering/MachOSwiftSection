# Draft - SwiftSectionKit：dump 把每个声明的种类与名字一并交给输出端

- **状态**: In Progress
- **创建日期**: 2026-10-04
- **最后更新**: 2026-10-04
- **关联提案**: [0058](0058-swift-section-kit.md)（SwiftSectionKit 本身；本提案只给它的输出端加一条通道）
- **实现分支 / PR**: `feature/dump-declaration-identity`（worktree `.worktrees/MachOSwiftSection-DumpDeclarationIdentity`，基于 `next`），按本仓库惯例在本地合并进 `next`

## 摘要

`DumpRequest` 和 `ObjCDumpRequest` 把每个顶层声明当作一块 `.declarations` 产物交给输出端，却不说这块是什么、叫什么。宿主要按声明拆文件就做不到，只能自己再建一遍索引、重写一遍 dump 的编排——这正是 SwiftSectionKit 要消灭的重复。第一个撞上的宿主是 ReverseEngineeringToolbox：它的 dump 服务要改用 SwiftSectionKit，而它默认「每个类型一个文件」（`NSView.h`、`NSView+Animation.h`、`NSObject+Protocol.h`，Swift 的 conformance 并进它所扩展的类型的文件）。本提案让这两个请求交出声明时附上种类与名字：`SwiftSectionOutput` 新增一个带默认实现的方法来接收，默认实现转给 `write(_:)`，所以 `swift-section` 和只实现 `write(_:)` 的宿主，输出逐字节不变。

## 方案

**新类型**（`Sources/Commands/SwiftSectionKit/Output/`）：

```swift
/// What one top-level piece of a `dump` or `objc dump` product declares.
public enum DumpedDeclaration: Sendable, Hashable {
    /// A Swift declaration, from `section`. A conformance and an associated
    /// type are named after the type they extend. `name` is `nil` when the
    /// name could not be rendered although the declaration itself was.
    case swift(DumpSection, name: String?)
    /// An Objective-C declaration. A category is named
    /// `ClassName(CategoryName)`, as the index names it.
    case objc(ObjCDeclarationKind, name: String)
}
```

**输出端**：`SwiftSectionOutput` 加一条协议要求，扩展里给默认实现（转给 `write(_:)`）。做成协议要求而不是只放在扩展里，是为了经 `some SwiftSectionOutput` 调用时动态派发到宿主的实现。

```swift
/// One top-level declaration of a `dump` or `objc dump`, with what it
/// declares. The default hands `product` to `write(_:)`.
func write(_ product: SwiftSectionProduct, declaring declaration: DumpedDeclaration)
```

**两个请求怎么交**（只在 `destination: .output` 时；写文件时产物不经过输出端，照旧）：

- `DumpRequest`：每个 dump 成功的顶层声明改走 `write(.declarations(…), declaring: .swift(section, name:))`。名字就是 dump 打印的那个：type、protocol、`@objc @implementation` 类取 `dumpName`；conformance 取它 `extension` 那一行的完整拼法（`dumpedTypeName(isFull: true, …)`），associated type 取 `dumpTypeName`（与它的 `extension` 行同一个函数）；都用和 dump 同一份 `DumperConfiguration`。名字在 dump 成功之后才算；算名字失败只把 `name` 置 `nil`，不报诊断（否则 CLI 的 stdout 会多出错误行）。header 与「No @objc @implementation classes recognized」那行注释不是声明，照旧走 `write(_:)`。`.bySection` 与 `.binaryOrder` 都覆盖。
- `ObjCDumpRequest`：每个声明改走 `write(.declarations(interface), declaring: .objc(kind, name: name))`；后面那个 `.text("")` 空行照旧走 `write(_:)`。
- `InterfaceRequest`、`ObjCInterfaceRequest` 不动：产物只有一块。

**假设（未问）**：

- 名字一律算，不加开关。代价是每个 Swift 声明多解析一次名字（dumper 内部本来就解析一次），CLI 用不上也要付。落地前用 `swift-section dump` 跑一个大镜像（宿主 cache 里的 `SwiftUICore`）比较前后耗时，差别明显就改成请求上的开关，并记进决策日志。
- 名字用 `String` 而不是 `SemanticString`：它是给宿主认声明用的，不是用来显示的。
- 只覆盖 `dump` 与 `objc dump`。`snapshot` / `diff` / `evolution` 的产物不是按声明分块的，不在范围内。

**源码兼容性**：纯新增。协议新要求带默认实现，现有 conformer（`StandardStreamOutput`、测试里的 `RecordingOutput`、下游宿主）不改照样编译；`SwiftSectionProduct` 不加 case，`switch` 它的宿主不受影响。`DumpedDeclaration` 是宿主消费的 enum，以后加 case 对穷举 `switch` 它的宿主是源码破坏——使用指南里写明不承诺可穷举，与 `DumpSection` 等一致。

**测试**（`SwiftSectionKitTests`，SymbolTestsCore fixture）：

- `RecordingOutput` 记下每块产物附带的声明。
- `DumpRequest`：每块 `.declarations` 都带声明，且与只实现 `write(_:)` 的输出端收到的那些块逐一相同；类型与它的 conformance 同名（一个枚举、一个泛型结构体、一个文件级 private 结构体）；protocol 按声明命名；associated type 以见证它的类型命名；`.binaryOrder` 下声明集合与 `.bySection` 相同；header 那块不带声明。
- `ObjCDumpRequest`：桥接类以 `.objc(.classes, name: "SymbolTestsCoreObjCBridgeClass")` 交出；声明顺序与产物顺序一致。
- 默认实现：一个只实现 `write(_:)` 的输出端收到的 `printedProduct` 与改动前相同（现有的 dump / objc 测试原样保留并通过即证明）。
- `SwiftSectionCommandTests` 全绿，CLI 输出不变。
- 先写测试、确认在改动前编译失败或断言失败，再实现。

**文档**：使用指南 `SwiftSectionKit.md` / `SwiftSectionKit_zh.md` 的「输出端契约」加一条；模块文档 `Internal/Modules/SwiftSectionKit.md` 的「1. 输出端」与「6. 测试锚点」；`Evolutions/README.md` 状态表；落地时演进账本。

**不做**：给 `swift-section` 加按声明拆文件的 flag；`Architecture` 补 `arm64e.x1`（本仓库要求的 MachOKit 0.52.x 不认这个子类型）。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-04 | Created as Draft | ReverseEngineeringToolbox 改用 SwiftSectionKit 时，用户：「不要自己重写dump逻辑」；被问到按类型拆文件怎么办时，用户选「先补 SwiftSectionKit」 |
| 2026-10-04 | 走轻量档 | 公开 API 纯新增，不改现有行为 |
| 2026-10-04 | 新增带默认实现的输出端方法，不给 `SwiftSectionProduct` 加 case | 加 case 会让每个穷举 `switch` 它的宿主编不过（CLI 的 `StandardStreamOutput`、测试的 `RecordingOutput` 都是）；默认实现转给 `write(_:)`，不关心声明的宿主一行不改 |
| 2026-10-04 | Draft → Accepted | 用户批准：「开工」 |
| 2026-10-04 | Accepted → In Progress | 开始实现 |
| 2026-10-04 | conformance 的名字取 `extension` 行的完整拼法，不用公开的 `dumpTypeName` | 实测：文件级 private 类型 `AlphaProtocolWitness` 的类型名是 `SymbolTestsCore.(AlphaProtocolWitness in _82F1…)`，`dumpTypeName` 按 interface-type 选项打印、去掉了判别符，得到 `SymbolTestsCore.AlphaProtocolWitness`，宿主会把类型和它的 conformance 分进两个文件。`filePrivateTypeAndConformanceShareName` 钉住；换回 `dumpTypeName` 的单点变异实测变红 |
| 2026-10-04 | 名字一律算，不加开关 | 实测（release，JHs-Mac-Studio-Ultra，macOS 27.0 宿主 cache 的 SwiftUICore，输出 8.5 MB，两侧交替各跑三次）：改动前 53.02 / 53.43 / 52.83 秒，改动后 55.48 / 53.49 / 54.50 秒，中位数慢 2.8%（约 1.5 秒）。为这点差别再加一个必须和 `write(_:declaring:)` 配对打开的开关不值得；三次的 stdout 两侧逐字节相同 |
| 2026-10-04 | 验证 | `SwiftSectionKitTests` 60 个（新增 8 个）、`SwiftSectionCommandTests` 99 个、`PrintFailureEventTests` / `ContinuousIntegrationTestFilterTests` / `CommandLineStreamWriteScanTests` 全部通过，原始退出码 0。新增的 Swift 测试先在只加了类型与默认实现时运行，7 个全红、原有测试全绿，实现后转绿；ObjC 那条同样先红后绿。命令行逐字节对照（`git archive` 导出的 `next` 与本分支，各自 release 编译）：`dump` libswiftObservation、SwiftUICore，`objc dump` AppKit（5.9 MB），stdout 与 stderr 全部一致 |
