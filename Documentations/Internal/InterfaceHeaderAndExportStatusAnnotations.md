# Interface 文件头部与导出状态标注的实现说明

> 对应提案：[0008](../Evolutions/0008-interface-header-and-export-status-annotations.md)（issue #106 §2/§3/§8）。
> 本文面向维护者，记录代码看不出来的决策与降级；提案保持决策历史原貌，与实现不一致处见「与提案的差异」。

## 全景

三件事，一个共同契约（两个 flag 默认关，默认输出字节不变）：

1. **导出集**（`MachOSymbols`）：`SymbolIndexStore.Storage` 在构建扫描的 export trie 循环里旁路收集导出事实，公开 `isExported(name:in:)` 与 `isExportedIncludingDerivedSymbols(name:in:)`。
2. **头部组件**（`SwiftPrinting`）：`InterfaceHeaderInfo`（纯值）+ `InterfaceHeaderBlock`（public 组件）+ 从 `MachORepresentableWithCache` 读事实的工厂。CLI 经 `--emit-header` 接线（interface 走 `SwiftInterfaceBuilderConfiguration.interfaceHeaderInfo`，dump 在首个声明前打一次）；RuntimeViewer 的 per-type 导出可独立调用组件。
3. **`// not exported` 标注**：interface 的 `renderMember` 与 dump 三个 Dumper 的 member-symbol 循环，`--emit-export-status` 门控。

## 为什么导出集必须显式收集

`buildStorageSweep` 的两条 symtab 收集腿都过滤 `!nlist.isExternal`（只收本地符号），导出符号的行全部由 export trie 循环补建——但那个循环带两个筛（`existingRow == nil`、`offset != nil`），且「这一行来自 trie 腿」这个事实事后不可恢复：

- 一个名字 symtab 已有行时 trie 循环什么都不做（导出事实丢失）；
- offset-less 的 re-export 条目从不建行（连行都没有）。

所以导出事实在同一遍循环里旁路收集：有行记行号（freeze 后折进 `(rowCount+63)/64` 字的 bitmap，185k 行 ≈ 23 KB），无行记名字（`exportedSwiftNamesWithoutRows`，预期空或极小）。**表本身的建行为完全不变**——`SymbolTableEquivalenceTests` 与全量快照钉住。

`isExported` 是三态：`nil` = 镜像没有任何导出信息（`hasExportInformation == false`，trie 枚举零条目）——此时「not exported」不构成有意义区分，发射侧不打标注。注意 `nil` 侧目前没有 fixture 能构造（所有 fixture 都带 trie），`ExportedSymbolFactsTests.imageWithExportTrieNeverAnswersNil` 只钉了非 nil 侧。

## 派生符号形态：裸查名字是错的

第一版按成员实现符号裸查导出集，SymbolTestsCore（library-evolution Release 构建）当场全军覆没：**public 成员的实现符号照例不在 trie 里**——外部调用方经导出的 `Tj` dispatch thunk 派发，实现符号保持 local。裸查会把整个 resilient 库标满。

issue #106 作者的验证法是「该成员的**任何**符号在导出表零命中」，对应实现 `isExportedIncludingDerivedSymbols(name:)`：查 `name` 本身 + `Tj` / `Tq` / `Tu` / `TjTu` 四个追加后缀形态（Swift mangling 的派生符号恰好是原名追加后缀）。每查一次是一次 permutation 二分，O(5·log n)。

## 发射侧的两个豁免（interface 路径）

即便带派生形态，两类成员的「自有符号零导出」仍是编译器常态而非不可达：

- **`override`**：外部经**父类**的 dispatch thunk 链接调用，子类不发射任何导出符号（fixture 实证：`public override func instanceMethod()` 全形态 trie 缺席）。跨类查父类符号超出诚实范围，直接豁免。
- **`@objc`**：`@objc dynamic` 经 objc_msgSend 派发，Swift 符号合法缺席（fixture 实证：`@objc public dynamic func objcDynamicMethod()`）。豁免整个 `@objc` 类别是保守安全的——非 dynamic 的 `@objc public` 成员本来就有导出符号，不会被标。

**conformance witness 故意不豁免**：一个 witness 成员零导出符号时，外部确实无法静态直接调用它（只能经协议派发）——「not exported」是准确的符号事实。合成 conformance（`==`、`hash(into:)`、Codable 的 init/encode）因此构成标注的大头，这是正确行为。

判定语义（`exportVerdict(forSymbolNames:)`）：成员**所有**符号（变量/下标为全部 accessor）都明确 false 才标；任一 exported → 不标；任一 `nil`（无导出信息）或成员无符号证据 → 不标。标注永不建立在猜测上。

## dump 路径的豁免（PR #111 review 修正）

初版实现说明在这里写过「dump 循环里拿不到模型级 override/@objc 事实……fixture 目前未触发」——**这个结论是错的**，且错在验证方法：当时用 `grep "override"` 检查 dump 输出，但成员符号区的 demangled 文本根本不含 override 字样，匹配到的只有 vtable override 段。复检（按符号名查）证实 fixture 当天就触发了两类假阳性：`public override` 的实现符号（`SubclassTest.instanceMethod`）与 `@objc public dynamic`（`ObjCAttributeClass.objcDynamicMethod`）都在成员符号区被标。

修正后的 dump 侧豁免（`ClassDumper` 专属——struct/enum 成员无 override 无 `@objc`）不依赖模型，从符号层面直接判定：

- **override**：`methodOverrideDescriptors` + `methodDefaultOverrideDescriptors` 的 implementation 符号名集合（`collectOverrideImplementationSymbolNames()`，仅 flag 开启时收集），成员区同名符号跳过标注。
- **`@objc`**：`@objc` 成员的 ObjC 入口是实现符号名追加 `To` 后缀，查 `SymbolIndexStore.containsSymbol(named: name + "To")`（一次 permutation 二分）即可识别，无需 demangle。

`methodDescriptorMemberSymbols`（`[Method]` 区）的行是 `Tq` 数据符号，查询前**剥掉 `Tq` 后缀**再走派生形态扩展——对 `…Tq` 名字追加 `Tj`/`Tu` 得到的 `…TqTj` 等从不存在，等于退化回本提案自己否掉的裸名查询。实证注：SourceEditor 与 fixture 上「`Tq` local 而成员任何形态导出」的组合均为空集（`Tq` 的导出跟随成员的 public-ness），所以修复前无假阳性实证——但该伴随性质无任何规范保证（`-exported_symbols_list` 手工导出清单即可打破），修复以正确性为准。「修复前失败」形态的复现测试因此不可构造（需要非常规导出清单的 fixture，不值得为此扩展 fixture 矩阵），守护测试钉的是修复后的行为不变性。

`ProtocolConformanceDumper` 的 witness 地址行不发射（那些行没有符号名在手）。

`method descriptor for …__allocating_init` 行被标是 true positive 的一个易误读形态：`Classes.ClassTest` 没写 init，隐式 `init()` 是 internal（Swift 从不合成 public 默认 init），`fC`/`fCTj`/`fCTq` 全不导出。注意这个 init **连实现符号都没发射**（未被引用），所以 interface 路径根本渲染不出它——测试用 `GenericAsyncSequenceTest.AsyncIterator` 的隐式 init 作 true-positive 标本（实现符号以 local `t` 在 symtab）。

## 覆盖面（PR #111 review 补齐）

`--emit-export-status` 的覆盖：四种 `OrderedMember`（`renderMember`）+ **存储 `var` 的 accessor 组**（`renderModelFields`，0006 折回的 accessor 有符号可查；同两豁免，`@objc` 用 `To` 存在性口径）+ **两个顶层 globals 块**（`printRoot` 经 `globalExportStatusComment`；顶层无 override/@objc，无需豁免）。没有 accessor 符号的存储属性是「无从标」而非「漏标」（符号驱动的模型构造决定的），头部 digest 里的「stored properties carry no symbol and are not checked」一句把「没检查」与「已确认导出」区分开。

另一处连带修复：`FunctionDefinition.isOverride` 的历史 `??` 链（`a ?? b ?? false` 右结合短路，`.methodDefaultOverride` wrapper 恒 false，引入时就没生效过）改为 `||` 形式——它是 override 豁免的承重判定；`FieldDefinition` 顺势 conform `AccessorRepresentable` 取得正确的 `isOverride`。

## 头部组件的边界

- **generator 身份由调用方传入**（`generatorName` + `generatorVersion`）：`BundledVersion` 是 CLI 目标私有，RuntimeViewer 也不是 swift-section——库侧不猜。
- **日期可选且默认缺席**：有日期行则快照/基线不可复现。测试 `absentDateLeavesNoDateLine` 钉住两侧。
- **evolution 行措辞是 detected / not detected**，不断言：`Tj == 0` 不严格等于未开 evolution（无可派发 public 成员的 resilient 模块也可为 0）。计数经 `symbols(of: .dispatchThunk)`——sweep 对所有 global 符号无条件按首孩子 kind 分桶，零新增管线。注意 `Tj` 符号本身是导出符号、经 trie 腿建行，所以 **strip 掉 export 信息的镜像 Tj 计数会塌到 0**——与「无导出信息则不标注」同根同源，头部行的措辞余地也覆盖它。
- **cpu / fileType 的人话映射**：MachOKit 的 description 是宏名风格（`MH_DYLIB`、`arm64(arm64e)`），组件工厂内联了三分支常见架构映射（对齐 CLI `Architecture`）+ `MH_` 前缀剥除，罕见值回退 MachOKit 原样。
- **头部对 `ImportsBlock` 零侵入**：`printRoot` 只在 imports 前多一个独立的 if 块——为 §6 的 import 重构（另一 agent，动同一带）把未来合并冲突面压到最小。
- 不可恢复项短清单是 roadmap「Known limitations」（L-1/L-8/L-13…L-16）的读者摘要，全文以 roadmap 承载。

## 与提案的差异

| 提案 | 实现 | 原因 |
|------|------|------|
| `isExported(name:in:)` 单一查询 | 追加 `isExportedIncludingDerivedSymbols(name:in:)`，发射侧一律用后者 | 裸查在 resilient 库上全量假阳性（见上） |
| 导出集「`Set<String>` 或字符串表引用」 | 行号 bitmap + 无行名字 fallback set | 对齐 0001 的 offset 化形态，185k 行 ≈ 23 KB |
| 头部字段含单一 `generatorVersion` | 拆成 `generatorName` + `generatorVersion` | RuntimeViewer 用同一组件时不应冒充 swift-section |
| 未提及豁免 | `override` / `@objc` 两个发射豁免 | fixture 实证的两类假阳性 |
| 前置等待 §6 落地 | 用户指示提前开工，接线做成零侵入 | 决策日志 2026-08-22 条 |

## 测试地图

- `ExportedSymbolFactsTests`（MachOSymbolsTests）：全量 trie 名 sweeping、本地符号阴性、thunk-only public 成员经派生查询转阳、internal 合成 init 全形态阴性、非 nil 契约。
- `InterfaceHeaderTests`（SwiftInterfaceTests）：逐行渲染、字段省略、`not detected` 措辞、日期缺席字节稳定、工厂读 Mach-O 事实、`printRoot` 接线 + 默认无头部。
- `ExportStatusAnnotationTests`（SwiftInterfaceTests）：三类假阳性各一钉（thunk-only public / `@objc` / `override`），每条负向断言配 store 层正向前提（先证成员确实全形态 trie-miss / thunk-only，「未标注」才必然是豁免的功劳而非 fixture 偶然）；true positive 限定在 `AsyncIterator` 块内按精确 trim 行匹配；默认输出零标注。
- `ExportStatusDumpAnnotationTests`（SwiftDumpTests）：dump 侧两类假阳性的复现钉（override 实现符号 / `@objc dynamic`，修复前的标注输出留档在任务报告）、`Tq` 行 true positive 保持、默认零标注。
- `OverrideRecoveryPredicateTests`（SwiftIndexingTests）：`FunctionDefinition.isOverride` 三 case 钉——`.methodDefaultOverride`（历史 `??` 链下恒 false 的复现）、`.methodOverride`、nil。
- `HeaderAndExportStatusFlagTests`（SwiftSectionCommandTests）：两命令 × 两 flag 的解析与默认关。
- 真实二进制复核（手动，见任务报告）：SourceEditor 上 issue §3 的 `updateLineNumberDisplay()` 被准确标注（3487 处全库标注），public API（`CachingManagedSourceEditorRange.init`）经 `fCTj` 不被标。
