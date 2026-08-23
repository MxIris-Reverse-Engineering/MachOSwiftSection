# 0009 - 社区类型映射包：私有框架 `__C` 类型的补充 APINotes 加载

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-08-22
- **最后更新**: 2026-08-22
- **所属愿景**: 无
- **关联提案**: [0008](0008-type-indexing-revival.md)（TypeIndexing 重启，本案是它的直接增量：0008 的三层归属/改名管线对「SDK 里没有模块」的私有框架三层全 miss）
- **实现分支 / PR**: `feature/type-indexing-revival`（基于 `next`，与 0008 同 worktree 续作）
- **配套文档**: 落地时并入 `Documentations/Internal/TypeIndexingPipeline.md`（补充包一节），社区贡献指引另立公开文档（英文，见「详细设计」）
- **编号说明**: 取立案时 git 全历史未占用的最小号 0009。注意 `main` 并行会话的提案线已与本线两次撞号（其重编号后的 0008「interface header 标注」与本线已 Implemented 的 0008 撞，双方 0005 亦互撞）；本案不再避让——本线 0008 已被实现提交历史引用、改动代价最高，对方同号提案仍为 Draft。冲突留待两线合并时统一裁决。

## 摘要

AttributeGraph 这类私有框架在 SDK 里没有任何模块存在（无头文件、无 swiftmodule、无 apinotes），0008 的三层归属管线（SDK interface / SDK APINotes / ObjC 元数据懒索引）对它的 CF-bridged 类型全部 miss，`__C.AGGraphRef` 只能原样保留；而 `AG_SWIFT_NAME(Graph)` 的改名信息只存在于头文件 attribute 里、二进制零残留，任何工具都无法自行恢复 `AttributeGraph.Graph` 这个拼写。与此同时，社区已把这批框架的类型映射逆向得相当完整。本案（用户裁定方向）给 `TypeDatabase` 增加**社区类型映射包**的加载接口：映射以**标准 `.apinotes` 格式**表达（零新格式、零新解析器，直接进既有 `APINotesIndex` 管线），库内置一份随库分发的映射资源（社区经 PR 贡献），宿主与 CLI 可追加自定义路径；查询命中即直接替换——`__C.AGGraphRef` 渲染为 `AttributeGraph.Graph`。

## 动机

- **问题域已在 0008 的实现说明里记档**：私有框架无 SDK 模块 → interface 层无从生成；无 apinotes → APINotes 层 miss；CF-bridged 类型不是 ObjC class → 懒索引层看不见。三层全 miss 是「诚实降级」，但对 SwiftUI 逆向这类高频场景，满屏 `__C.AGGraphRef` 的可读性损失是真实痛点。
- **改名信息原理上不可恢复**：`AG_SWIFT_NAME` / `swift_name` attribute 只活在头文件里。要拿回 `Graph` 拼写，唯一的路是外部知识——而社区（OpenGraph 等重建项目）已经把这份知识挖出来了，缺的只是一个进入 `TypeDatabase` 的入口。
- **归属信息虽可通过启发式推断（前缀表、导出符号聚类），但既然要为改名引入外部知识入口，归属顺带解决**，无需再造启发式。

## 提议方案

### A. 映射格式：直接复用 `.apinotes`

社区映射就是一个手写的 `.apinotes` 文件：

```yaml
Name: AttributeGraph
Typedefs:
- Name: AGGraphRef
  SwiftName: Graph
- Name: AGSubgraphRef
  SwiftName: Subgraph
- Name: AGGraphContextRef
  SwiftName: GraphContext
Tags:
- Name: AGGraphStorage
  SwiftName: Graph
- Name: AGSubgraphStorage
  SwiftName: Subgraph
```

选它的理由：Apple 官方 spec、社区熟悉、`swift_name` 语义一一对应（`AG_SWIFT_NAME(Graph)` ≡ `SwiftName: Graph`）；本库已有完整解析管线（swift-apinotes → `APINotesFile` → `APINotesIndex`），类别隔离（0008 的 `NSObject` 教训）由 Classes / Protocols / Tags / Typedefs 分节天然携带；不带 `SwiftName` 的条目正好是纯归属注册（既有语义）。**贡献指引要求 CF-bridged 类型同时登记两个名字**：`XxxRef`（Typedefs，覆盖符号签名的 mangling 形态）与 pointee struct 名（Tags，覆盖字段元数据的 `__C.AGGraphStorage` 形态）——0008 实测两种形态在同一二进制里并存。

### B. 两层来源

1. **库内置包**（开箱即用）：`Sources/TypeIndexing/Resources/SupplementaryAPINotes/*.apinotes`，SPM resource 随库分发，`Bundle.module` 加载。首发内置 AttributeGraph；后续社区通过 PR 贡献新框架/新条目——这就是「接受社区贡献的接口」的落点，review 门槛即 PR review。
2. **宿主追加路径**：`TypeDatabase` / provider 接受 `supplementaryAPINotesURLs: [URL]`（文件或目录）；CLI 加 `--supplementary-apinotes <path>`（可重复）。RuntimeViewer 将来把它接到设置项即可。

### C. 合并优先级：显式提供者最高

写入顺序 interface 名 → SDK APINotes → 内置包 → 宿主追加包，后写覆盖同名——用户显式提供的映射「碰到直接替换」，可以覆盖 SDK 条目（修正官方数据错误的通道），宿主追加又可覆盖内置。补充包不参与依赖过滤（体量小，全量加载）；解析失败逐文件降级记日志，与 SDK apinotes 同一契约。

### 非目标

- 成员级改名（selector → Swift 方法名）——仍属另立提案的渲染替换全集。
- 「重建头文件 → apinotes」的自动转换工具（sourcekitd 的 `editor.open.interface.header` 可做，留作未来方向；本案手写 apinotes 已够用）。
- 映射内容的正确性背书——包是社区知识，条目错了输出跟着错，PR review 是唯一防线（文档写明）。

## 详细设计

- `APINotesIndex` 不动——补充包就是多几个 `APINotesFile` 输入。`TypeDatabase` 的注册序列在 `register(apiNotesIndex:)` 之后增加 `register(supplementaryAPINotesFiles:)`（或合并为带序参数的一次注册），保证覆盖顺序。
- 内置资源枚举 + 外部路径枚举（目录展开 `*.apinotes`）→ `APINotesFile(path:)` 逐个解析，失败 `#log` 跳过。
- 贡献指引文档（英文，公开面）：格式样例、两名字规则（`Ref` + storage struct）、类别选择（CF-bridged 用 Typedefs + Tags；真 ObjC 类用 Classes；ObjC protocol 用 Protocols）、验证方法（`swift-section interface --resolve-c-module-names` 前后对比）。
- 测试：内置包加载与覆盖顺序单测（临时目录 + 罐装 apinotes）；AttributeGraph 样例的三层数据流单测（`__C.AGGraphRef` → 归属 AttributeGraph + swiftName Graph，两种形态都断言）；e2e 用 dyld cache 的 SwiftUI 人工核对（维护者路径）。

## 影响

- **源码兼容性**：`TypeDatabase.index` / provider init 增加带默认值的参数（或新增重载），既有调用零变化；CLI 纯增 flag。
- **ABI**：不适用（源码分发）。
- **下游影响**：RuntimeViewer 接入补充路径是它自己的设置项变更；内置资源使 TypeIndexing target 增加 SPM resource 处理，其余 product 不受影响。

## 落地步骤

1. 资源与加载：内置 bundle 目录 + `Bundle.module` 枚举 + 外部路径入口；注册序列扩展。
2. 首发 AttributeGraph 内置包（Graph / Subgraph / GraphContext / Attribute 等社区已确认的核心条目，两名字规则）。
3. CLI flag + 单测全套。
4. 贡献指引公开文档 + `TypeIndexingPipeline.md` 补节 + 提案状态推进，与代码同批提交。

## 决策日志

- 2026-08-22：用户裁定方向——「提供一个接口，接受社区的贡献；像 AttributeGraph 这种已被大量挖出的，Database 预先加载，碰到直接替换」。立案（In Review），格式选定复用 `.apinotes`。
- 2026-08-22：用户批准（「开工」），状态 In Review → Accepted → In Progress，同 worktree 实施。
- 2026-08-22：首发内置包只收录用户亲自给出头文件证据的三个类型（Graph / Subgraph / GraphContext，双名字规则各两条）。`AGAttribute` 等其余条目的 `SwiftName` 拼写缺乏一手证据，按本案「条目错了输出跟着错」的立场宁缺毋滥，留给社区 PR 补齐。
- 2026-08-22：实施中发现提案的「两形态」模型不完整，实为**三形态**（AG probe 实测：手造 clang module 复刻 `objc_bridge` + `swift_name` 声明做端到端）——(1) typedef 名 `__C.AGGraphRef`（typealias node，Typedefs 表命中）；(2) storage tag 名 `__C.AGGraphStorage`（字段元数据的 foreign **class** descriptor → `.objcClass` 类别，而 Tags 条目在值类型表，类别隔离挡住了它——落地为 `.objcClass` 查询 miss 后回退值类型表，protocol 表照旧绝不回退）；(3) **导入名直出** `__C.Graph`（消费方 emit 的 foreign descriptor 记录 swift_name 之后的拼写，改名无从谈起、缺的是归属——落地为归属同步把 `cNamesBySwiftName` 的 SwiftName 拼写也登进归属表，带点嵌套名跳过；SDK 的 `NSDecimal → Decimal` 同理受益）。贡献者仍只需登记两个 C 拼写，第三形态由 SwiftName 自动派生。
- 2026-08-22：落地完成置 Implemented。验证：单测 6 项新增全绿（全套 1466/276 退出码 0）；AG probe 5 处引用全解析为 `AttributeGraph.Graph`/`.Subgraph`；CGCVProbe 输出与 0008 基线字节一致（SwiftName 归属登记无回归）。
- 2026-08-23：PR #110 code review（并行 review 会话 15 条发现，四问裁决）后用户裁定**移除内置资源层**（「不要内置资源，让用户自己提供」）：SwiftPM resource bundle 的 `Bundle.module` accessor 在 bundle 缺失时直接 fatalError，而 `build-executable-product.sh` 只分发裸二进制——分发出去的 CLI 一用就崩（review 发现 2）。本节「提议方案 B.1（库内置包）」作废，补充映射改为**纯用户自备**（宿主 `supplementaryAPINotesURLs:` / CLI `--supplementary-apinotes`），AttributeGraph 样例移入公开指引文档；merge 优先级简化为 SDK APINotes → 用户文件按传入序。同批修复 review 发现 3（依赖解析为空的 stderr 警告）/ 4（submodule 失败不写缓存，防残缺条目固化）/ 5（`moduleName(forImagePath:)` 前导点名字死循环，加不动点守卫）/ 6（`--supplementary-apinotes` 坏路径/坏 YAML 的 stderr 预检）/ 7（task group 完成序注册改为按 SDK 发现序重排，`entriesInDiscoveryOrder`），各带回归测试（`ModuleInterfaceIndexer` 为此增加 `InterfaceGenerator` 注入缝）。
