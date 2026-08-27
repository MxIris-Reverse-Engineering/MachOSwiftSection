# 2026-08-22：社区类型映射包（提案 0010）

> 编号说明：本报告写作时提案编号为 0009（重启案为 0008），2026-08-23 两线合并时分别重排为 0010 / 0009；下文历史提法保留原号。另注：本报告记录的「内置 SPM resource 包」在次日的 PR #110 review 后按用户裁定移除，见 [2026-08-23-pr110-review-fixes.md](2026-08-23-pr110-review-fixes.md)。

## 问题

0008 重启后的 TypeIndexing 三源管线对 **SDK 里没有模块的私有框架**三层全 miss：AttributeGraph 无头文件、无 swiftmodule、无 apinotes，interface 层无从生成、APINotes 层无文件、CF-bridged 类型不是 ObjC class 所以懒索引层也看不见。`__C.AGGraphRef` 只能原样保留；而 `AG_SWIFT_NAME(Graph)` 的改名信息只活在头文件 attribute 里、二进制零残留，`AttributeGraph.Graph` 这个拼写**原理上不可恢复**，必须引入外部知识。用户裁定方向：「提供一个接口，接受社区的贡献；像 AttributeGraph 这种已被大量挖出的，Database 预先加载，碰到直接替换」。

## 调研

- **格式选型**：社区要贡献的信息（C 名 → Swift 名 + 归属模块）与 Apple 官方 APINotes 的表达能力一一对应（`AG_SWIFT_NAME(Graph)` ≡ `SwiftName: Graph`），且本库已有完整解析管线（swift-apinotes → `APINotesFile` → `APINotesIndex`）与类别隔离表——直接复用 `.apinotes`，零新格式零新解析器。swift-apinotes 用 Yams 解析，标准 YAML `#` 注释可用（内置包文件带注释头）。
- **mangling 形态摸底（实施中推翻了提案的「两形态」模型，实为三形态）**：
  1. 0008 遗留的 CGCVProbe 实测：本地编译的二进制里符号签名与字段 symbolic reference 全是 `So…Refa`（typedef 名，typealias node → `.other` 类别）。
  2. 系统 dyld cache 二进制搜索：`So[0-9]+AG…` 文本 mangling 零命中，但存在孤立的 `AGGraphStorage` 字符串——SwiftUI 对 AG 类型的引用走 symbolic reference，指向消费方自行 emit 的 **foreign class descriptor**（name = C tag 名，kind = class → `.objcClass` 类别）。这暴露了类别隔离的缺口：Tags 条目在值类型表，`.objcClass` 查询摸不到。
  3. AG probe（见下）实测出第三形态：本地编译场景下 foreign descriptor 记录的是 **swift_name 之后的导入名**（`__C.Graph`）——identifier 已是最终拼写、无需改名，缺的只是归属。
- **`.objcClass` 回退值类型表的安全论证**：C 的 tag namespace 与 ObjC class 的 ordinary namespace 理论上可同名共存，但 class 表先查先赢；「改名只在 tag 侧、同名 ObjC class 又真被引用」无已知真实实例。protocol 表照旧绝不回退（`NSObject` 隔离是它存在的理由）。

## 最终方案

提案 [0010](../../Evolutions/0010-community-type-mapping-bundles.md)（用户批准后实施）：

- 补充映射包 = 标准 `.apinotes` 文件；两层来源——库内置 SPM resource（`Sources/TypeIndexing/Resources/SupplementaryAPINotes/*.apinotes`，社区经 PR 贡献）+ 宿主/CLI 追加路径（`--supplementary-apinotes`，可重复，文件或目录）。
- 覆盖顺序 SDK APINotes → 内置包 → 宿主追加包；`APINotesIndex.register(files:)`（init 主体提炼为可追加方法）的后写覆盖即优先级实现。
- 三形态各自的覆盖机制：Typedefs 条目（typedef 名）、Tags 条目 + `.objcClass` 值类型表回退（tag 名 foreign class）、SwiftName 拼写登进归属表（导入名直出；带点嵌套名跳过）。贡献者只需登记两个 C 拼写，第三形态自动派生。
- 首发内置包宁缺毋滥：只收用户亲自给出头文件证据的 Graph / Subgraph / GraphContext（双拼写各一条）；`AGAttribute` 等缺一手证据的条目留给社区 PR。

## 实际执行

1. `APINotesIndex`：`register(files:)` 提炼 + `.objcClass` 回退（含安全论证注释）。
2. `SupplementaryAPINotesLoader`（新文件）：内置 `Bundle.module` 枚举（文件名排序保证覆盖顺序确定）+ 宿主路径枚举（目录取浅层 `.apinotes`）；解析失败逐文件 `#log` 跳过；protocol 形态 `@Loggable`。
3. `TypeDatabase`：init 增 `supplementaryAPINotesURLs`（默认空）；新增 `register(supplementaryAPINotesFiles:)` 步骤；归属同步提炼为 `registerAttribution(fromAPINotesIndex:)` 并把 `cNamesBySwiftName` 的 SwiftName 拼写也登进归属表（`register(apiNotesIndex:)` 同样受益——SDK 的 `NSDecimal → Decimal` 场景下 `__C.Decimal` 引用同理）。
4. Provider init 透传（带默认值，源码兼容）；CLI `--supplementary-apinotes`（无 `--resolve-c-module-names` 时警告一句）；`Package.swift` 加 `.copy` resource。
5. 内置包 `AttributeGraph.apinotes`（6 条目 + 注释头引贡献指引）。
6. 测试 6 项新增（`SupplementaryAPINotesTests`）：内置包加载、AG 三形态数据流、`.objcClass` 回退（含 class 表优先与 protocol 不回退）、SDK 覆盖、包间覆盖、宿主路径枚举与坏文件降级。
7. 文档：公开贡献指引 `Documentations/SupplementaryTypeMappings.md`（英文，顶层）、`TypeIndexingPipeline.md` 补充映射包一节、AGENTS.md、`Documentations/README.md` 索引、ProjectEvolutionLog 42 节补记、Glossary 登记、提案状态推进 Implemented。

## 验证

- 全套测试两轮（回退落地后、归属修复后）均退出码 0：1466 tests / 276 suites（0008 批次为 1460 / 275）。
- **AG probe 端到端**：手造 clang module（`objc_bridge(id)` + `swift_name` 的 typedef 声明 + modulemap）复刻 SwiftUI 引用 AG 类型的编译形态，`swiftc -emit-library` 出 dylib 后跑 `swift-section interface --resolve-c-module-names`：首轮暴露第三形态（`var graph: __C.Graph?`——符号签名侧已对，字段元数据侧 module 未解析）；SwiftName 归属登记落地后 5 处引用（函数签名、字段、enum payload）全部解析为 `AttributeGraph.Graph` / `AttributeGraph.Subgraph`。
- **回归**：CGCVProbe 输出与 0008 基线**字节一致**（SwiftName 归属登记未扰动既有场景）。

## 与方案的差异

- 提案写的「两形态」双名字规则不完整——实为三形态（见调研 2/3）。贡献指引仍只要求登记两个 C 拼写（第三形态由 SwiftName 自动派生），但查询侧多了 `.objcClass` 回退与归属表的 SwiftName 登记两处机制性修正，均已回写提案决策日志。
- 提案落地步骤里的「Attribute 等社区已确认条目」收窄为三个有一手证据的类型（决策日志已记）。
