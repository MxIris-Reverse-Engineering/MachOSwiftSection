# 0038 - FieldLayoutRenderable 不再继承 MachOSwiftSectionRepresentableWithCache

- **状态**: Implemented
- **创建日期**: 2026-09-14
- **最后更新**: 2026-09-26
- **所属愿景**: 无
- **关联提案**: [FieldLayoutRenderer 按 reader 特化](../Internal/FieldLayoutRendererReaderSpecialization.md)（该协议的来历）
- **实现分支 / PR**: 待定
- **配套文档**: [FieldLayoutRendererReaderSpecialization.md](../Internal/FieldLayoutRendererReaderSpecialization.md)（同批更新）

## 摘要

`SwiftDeclarationRendering.FieldLayoutRenderable` 声明的是六个「怎么渲染这个类型的字段布局注释」的 static witness，与「这个类型身上有 `__swift5_*` section、并且带读取缓存」是两件彼此独立的事——只是恰好同为 `MachOFile` 与 `MachOImage` 持有。它却 refine 了 `MachOSwiftSectionRepresentableWithCache`，把一个能力协议写成了 reader 协议的子类型：任何只想提供渲染 witness 的类型都被迫先成为一个 Mach-O reader，协议自己的语义边界也糊掉了。本提案去掉这条继承，改用一个 protocol composition typealias 表达上层真正需要的「两样都要」。

## 方案

**协议本身**（`Sources/SwiftDeclarationRendering/FieldLayoutRenderer.swift`）：`public protocol FieldLayoutRenderable` 不再带父协议，六个 witness 要求原样不动。两处 conformance（`extension MachOFile: FieldLayoutRenderable` / `extension MachOImage: FieldLayoutRenderable`）都长在具体类型上，`Self` 天然仍是 reader，实现体一行不改。

**组合别名**：同文件新增（名字带 `MachO` 前缀，与 `MachORepresentableWithCache` / `MachOSwiftSectionRepresentableWithCache` 一致——约束点上的泛型参数就叫 `MachO`，约束名必须让人看出这是一个 Mach-O reader）

```swift
public typealias MachOFieldLayoutRenderable = MachOSwiftSectionRepresentableWithCache & FieldLayoutRenderable
```

**约束点**：83 处泛型约束位置（`<MachO: …>`、`some …`、`each Reader: …`、`associatedtype MachO: …`）从 `FieldLayoutRenderable` 改为 `MachOFieldLayoutRenderable`，分布在 SwiftDump、SwiftInterface、SwiftPrinting、SwiftDeclarationRendering、MachOFixtureSupport 与 IntegrationTests。这些位置的方法体本来就在调 `descriptor.xxx(in: machO)` 这类需要 section 读取能力的 API——包括 `FieldLayoutRenderer` 自己的 `resolveAccessorMetadata`，它调的 `metadataAccessorFunction(in:)` 签名上就写着 `<MachO: MachOSwiftSectionRepresentableWithCache>`——所以这不是「补一个原本不需要的约束」，而是把此前靠继承偷偷带进来的那一半显式写出来。

**取舍**：另外两种写法都被否掉。83 处各自展开 `MachOSwiftSectionRepresentableWithCache & FieldLayoutRenderable` 最显式，但多参数场景（`Old` / `New`、`each Reader`）行宽翻倍；引入一个同时继承两者的空协议则要给每个 reader 补一条 conformance，新增 reader 类型容易漏，且又多出一层继承关系——正是这次要去掉的那种东西。typealias 零 conformance 负担，且在类型系统里就是组合而非名义类型。

**兼容性**：这是源码层面的公开 API 变更（`Dumpable` / `NamedDumpable` / `ConformedDumpable` / `Dumper` 的协议要求签名跟着变）。对调用方零影响——传进去的永远是 `MachOFile` / `MachOImage`，两者都满足组合。只有「在包外自己实现 `Dumpable`」这种用法需要跟着改约束名，仓库内外均无已知此类实现（RuntimeViewer 侧是调用方，不是 conformer）。

**验证**：`swift build --build-tests` 全绿即等价——纯类型层改动，不触碰任何运行期逻辑，渲染输出与快照基线按定义不变。跑定向套件（SwiftDumpTests / SwiftInterfaceTests / MachOSwiftSectionTests）确认无行为漂移；不需要跑系统框架 A/B 渲染验证，因为没有一行实现代码被改动。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-14 | 创建为 Draft，同日 Accepted | 用户指出「FieldLayoutRenderable 应该跟 MachOSwiftSectionRepresentableWithCache 分开，他俩没任何关系」 |
| 2026-09-14 | 约束点用组合 typealias，不逐处展开、也不新建空协议 | 用户在三个选项中选定 typealias：协议彻底解耦、组合关系只写在一处、对调用方零影响、不需要额外 conformance 声明 |
| 2026-09-14 | 实现完成并验证通过，状态置 In Progress（落地 commit 时再改 Implemented 并分配编号） | `swift build --build-tests` 退出码 0、零 error；SwiftDumpTests / SwiftInterfaceTests / MachOSwiftSectionTests 共 1088 测试 / 215 套件全绿（原始退出码 0），无行为漂移 |
| 2026-09-14 | 别名定名 `MachOFieldLayoutRenderable`，不叫 `FieldLayoutRenderingReader` | 用户指出 `<MachO: FieldLayoutRenderingReader>` 这个约束看不出 reader 是 Mach-O——泛型参数叫 `MachO`，约束名里却一个 `MachO` 都没有；`MachO` 前缀也正是 `MachORepresentableWithCache` / `MachOSwiftSectionRepresentableWithCache` 的既有惯例。协议本身仍叫 `FieldLayoutRenderable` 不加前缀，它确实不要求 conformer 是 Mach-O reader |
| 2026-09-14 | 不入术语表 | `MachOFieldLayoutRenderable` 是一个 API 标识符（两个既有协议的组合别名），不是新概念，[Glossary.md](../Glossary.md) 收的是项目自造术语；配套文档为同批更新的 FieldLayoutRendererReaderSpecialization.md，已登记在头部 |
| 2026-09-26 | In Progress → Implemented，落地编号 0038 | 代码已于 2026-09-14 随 `52b827e4` 合入 `next`，当时状态停在 In Progress、没有取号；0.20.0 发版收尾时按合入顺序补取。配套文档见头部，已随代码更新；没有新的项目术语 |
