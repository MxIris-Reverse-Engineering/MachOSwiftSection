# Draft - Type / Protocol Definition 的导出标志：导出事实下沉到声明模型

- **状态**: Accepted
- **创建日期**: 2026-09-09
- **最后更新**: 2026-09-09
- **关联提案**: [0008](0008-interface-header-and-export-status-annotations.md)（导出状态标注，导出事实层的来源）、[0016](0016-exported-only-interface.md)（导出过滤，本提案复用它的类型 / 协议裁决）
- **实现分支**: `feature/exported-declaration-flag`

## 摘要

`TypeDefinition` 与 `ProtocolDefinition` 各加一个 `exportStatus: ExportStatus`（四态枚举），在索引期无条件填好，值就是提案 0016 已经在用的那条裁决——类型看自己的 nominal type descriptor 符号（`…Mn`）、协议看 protocol descriptor 符号（`…Mp`）在不在镜像的 export trie 里。

动机是宿主侧的消费形态：RuntimeViewer 在类型列表里要对**每一个**类型标注它是否导出，而今天这个事实只活在 `SwiftDeclarationPrinter` 的私有裁决里（`SwiftDeclarationPrinter+ExportFilter.swift`），宿主拿不到，只能自己重写一遍。同时打印器内部也有重复：`printRoot()` 打开 `--exported-only` 时，`installExportFilterScope(types:protocols:)` 会把全镜像的类型和协议再裁决一遍，而每个类型在打印时还会被裁决第二次。下沉之后全库只剩一份实现，打印器与 `ExportFilterScope` 都改成读模型上的标志。

## 方案

### 落点与形态

标志是一个四态枚举，不是 `Bool?`：

```swift
// SwiftDeclaration/Components/Definitions/ExportStatus.swift
public enum ExportStatus: Sendable, Hashable {
    /// 描述符符号在镜像的 export trie 里。
    case exported

    /// 镜像有导出信息，且这个描述符符号确定不在里面。
    case notExported

    /// 镜像本身没有导出信息（`.o` 目标文件、静态库产物一类没有 export trie 的 Mach-O）。
    /// 这是镜像级事实：该镜像里任何声明都无从判断，与声明本身无关。
    case imageHasNoExportInformation

    /// 镜像有导出信息，但这一条声明拿不到可信的描述符符号名，因此不裁决。
    /// 今天唯一的来源是 constrained extension 里的嵌套类型（见下）。
    case descriptorSymbolNameUnresolvable
}

extension ExportStatus {
    /// 与 `SymbolIndexStore.isExported(name:in:)` 同形的三态投影，
    /// 供既有调用点与「只在确定未导出时才动手」的规则直接使用。
    public var isExported: Bool? { ... }

    /// 「确定未导出」——过滤与标注唯一该认的条件。
    public var isDefinitelyNotExported: Bool { self == .notExported }
}
```

```swift
public final class TypeDefinition {
    public let exportStatus: ExportStatus
}

public final class ProtocolDefinition {
    public let exportStatus: ExportStatus
}
```

`let` 而非 `var`：值在构造时就定下来，不随索引进度变化。判定只需要 descriptor 的 offset 与名字节点，不需要 `index(in:)` 的产物，所以 `prepare()` 一结束整张表就都有值——这正是列表 UI 需要的时刻（那时各个类型都还没有 `index(in:)`）。

判定逻辑整体从 `SwiftPrinting` 搬到 `SwiftDeclaration`（同一个新文件），两条腿与 0016 完全一致，一行不改语义：

1. descriptor 自己地址上的符号（编译器自己的拼写）→ 查 trie，得到 `.exported` / `.notExported` / `.imageHasNoExportInformation`。
2. 只有第 1 步没有符号时，才把名字节点重整成 `_$s…Mn` / `_$s…Mp` 去查 trie；名字里含 `.extension` context 的一律拒绝裁决（`.descriptorSymbolNameUnresolvable`），因为 constrained extension 里的嵌套类型重整出来必然对不上，硬判会把导出类型说成未导出（`publicTypeNestedInConstrainedExtensionIsKept` 钉的就是这条）。

`SwiftDeclaration` 已经依赖 `MachOFoundation` 并 `@_spi(Internals) import MachOSymbols`，`Demangling` 也在依赖里，所以下沉不引入任何新依赖边。

### 为什么是枚举而不是 `Bool` / `Bool?`

`Bool` 不够，因为「不知道」是真实存在的一态：它**不是**「符号表里查不到」——查不到是确定的 `.notExported`。真正的不可判断有两个来源，而且性质完全不同——`.imageHasNoExportInformation` 是**镜像级**的（这个 Mach-O 压根没有 export trie，此时把每个类型都读成未导出就是整片谎报），`.descriptorSymbolNameUnresolvable` 是**声明级**的（镜像有导出表，只是这一条的名字重整不可信）。`Bool?` 能表达「不知道」，但把这两者压成同一个 `nil`，宿主既分不清也没法只对其中一种做补救；枚举把它们分开，同时给以后新增的裁决结局留了位置（`Bool?` 的三态是封死的）。

代价只是宿主写 `exportStatus == .notExported`（或 `isDefinitelyNotExported`）而不是 `!isExported`。实测覆盖的四个镜像上后两个 case 一次都没出现过。

### 填充点

- `TypeDefinition.init(type:in:)` / `ProtocolDefinition` 的同类构造入口带着 machO，直接算。
- 行为变化一处（已在属性文档里写明）：裁决要查符号索引，而 `SymbolIndexStore.storage(in:)` 是 get-or-build，所以**绕过索引器**直接构造一个定义（`TypeDefinition(type:in:)` 是 public）会触发该镜像的符号索引构建。走 `SwiftDeclarationIndexer.prepare()` 的正常路径不受影响：符号索引在类型定义构造**之前**就已建好（`prepareIndexes()` 里符号索引段在类型段之前），这也是实测总耗时只有毫秒级的原因。
- 不带 machO 的 `package` designated init（测试用的错误契约构造、`specialize(with:in:)` 的绑定构造）增加一个 `exportStatus` 参数：特化定义与它的泛型原型共用同一个 descriptor，事实相同，直接继承原型的值，不重算。

### 打印器改为转发

`exportVerdict(forTypeDefinition:)` / `exportVerdict(forProtocolDefinition:)` 签名不变（是 public API，返回 `Bool?`），实现改成读 `definition.exportStatus.isExported`——不制造破坏性变更；`installExportFilterScope(types:protocols:)` 同样只是筛 `isDefinitelyNotExported`，`printRoot()` 那趟全镜像重算随之消失。成员级、字段级、扩展级的裁决**完全不动**——成员没有自己的 descriptor 符号，扩展没有描述符，规则不同，本提案不碰。

### 明确不做的

- 成员（函数 / 属性 / 下标 / 字段）与 `ExtensionDefinition` 不加标志（用户选定的范围）。
- `ABISnapshot` 不记录导出状态：导出与否是 symbolication / 构建配置状态，不是 ABI 事实，写进快照会让同一份二进制在 strip 前后 diff 出假变更。
- 默认输出不变：这是模型上多一个字段，不改任何渲染。

### 成本

索引期无条件填充，实测占 `prepare()` 的 0.15% 以内（最大样本 3992 个类型 28 毫秒 vs 18.16 秒），因此不设配置开关——一个默认关闭的开关会让宿主必须记得打开，而收益是毫秒。

## 验证

一次性探针（跑完即删）在四个镜像上测了裁决的分布与耗时：

| 镜像 | 类型数 | 第 1 条腿命中率 | 走重整名 | 导出 / 未导出 / 不可判断 | 裁决总耗时 | `prepare()` |
|---|---|---|---|---|---|---|
| SwiftUICore（当前 dyld shared cache） | 3992 | 100% | 0 | 2113 / 1879 / 0 | 28 ms | 18.16 s |
| SwiftUICore（iOS 18.5 模拟器 runtime） | 2991 | 100% | 0 | 1588 / 1403 / 0 | 20 ms | 22.17 s |
| libswiftCore（进程内 `MachOImage`） | 463 | 100% | 0 | 387 / 76 / 0 | 2.4 ms | 2.80 s |
| SymbolTestsCore（fixture） | 394 | 100% | 0 | 378 / 16 / 0 | 2.8 ms | 2.28 s |

协议侧同形（400 / 325 / 105 / 56 个，同样 100% 命中、0 个不可判断）。关键事实有两条：Swift 的 descriptor 符号在 strip 过的模拟器框架和 dyld shared cache 里**都还在**，所以那条贵的「重整名 + 查 trie」路径实际上从不触发；以及两个不可判断的 case 在真实框架上不出现——它们是为正确性保留的分支，不是常态。

回归测试：

1. 模型标志与打印器既有裁决在 `SymbolTestsCore` 全表上逐个相等（保证下沉零行为漂移）。
2. 已知符号的具体取值：`ExportedOnlyInterfaceTests` 已经钉住的那批 `…Mn` / `…Mp` 符号，对应定义的 `exportStatus` 必须与 `SymbolIndexStore.isExported(name:in:)` 一致。
3. 特化定义继承泛型原型的取值。
4. `--exported-only` 与 `--emit-export-status` 的既有端到端测试保持全绿（它们现在走的是同一份事实）。

文档：提案本身即设计说明；另更新 [ExportedOnlyInterfaceFiltering.md](../Internal/ExportedOnlyInterfaceFiltering.md) 的裁决来源一节、`AGENTS.md` 的 SwiftDeclaration 段落，并按惯例补 ProjectEvolutionLog 与任务报告。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-09 | Created as Draft；一轮澄清（三题） | 用户原话「给 Type/Protocol Definition 加一个是否是导出类型的 Flag」 |
| 2026-09-09 | 索引期无条件填充，不设配置开关 | 用户要求「每个类型都要消费」，先测性能；实测裁决占 `prepare()` 的 0.15% 以内，且贵路径从不触发 |
| 2026-09-09 | 不折叠成 `Bool` | 用户认为「导出符号表找不到肯定不是导出类型」——实测支持这半句（查不到确实是「未导出」），但真正的不可判断另有来源：镜像没有导出表，折叠后 `.o` / 静态库里每个类型都会被谎报 |
| 2026-09-09 | 三态 `Bool?` 改为四态 `ExportStatus` 枚举 | 用户「还是用一个枚举吧，Bool 就写死这 3 种情况了」；顺带把 `nil` 压在一起的两个原因（镜像级无导出信息 / 声明级名字不可重整）分开，并为以后新增结局留位 |
| 2026-09-09 | 只做 Type / Protocol，成员与扩展不动 | 用户选定；成员与扩展的判据不同（派生符号 / 目标归属），混进来会把改动面放大 |
| 2026-09-09 | Accepted，开始实现 | 用户「开工」 |
