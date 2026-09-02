# 0016 - Interface 只打印导出声明（`--exported-only`）

- **状态**: Implemented
- **创建日期**: 2026-09-02
- **最后更新**: 2026-09-02
- **关联提案**: [0008](0008-interface-header-and-export-status-annotations.md)（导出状态标注——本提案复用它的导出事实层与成员判定）
- **实现分支**: `feature/exported-only-interface`
- **配套文档**: [ExportedOnlyInterfaceFiltering.md](../Internal/ExportedOnlyInterfaceFiltering.md)（实现说明）

## 摘要

给 `SwiftInterfaceBuilder` / `SwiftDeclarationPrinter` 加一个打印期过滤开关
`SwiftDeclarationPrintConfiguration.printExportedDeclarationsOnly`（CLI：`swift-section interface --exported-only`），
打开后 interface 只输出**镜像导出**的声明：类型 / 协议按各自描述符符号（`…Mn` / `…Mp`）是否在 export trie 里裁决，
成员沿用提案 0008 的成员判定（本体或 `Tj`/`Tq`/`Tu`/`TjTu` 派生符号任一导出即算导出），
扩展按「被扩展类型 / 遵循协议是否为本镜像内未导出声明」裁决。提案 0008 只做**标注**（`// not exported`），
本提案是它的**过滤**形态；默认关闭，默认输出字节不变。

## 方案

**语义仍是符号表事实，不是访问级别猜测**（与 0008 一致）：只在裁决为「确定未导出」（`false`）时删；
镜像没有导出信息、成员没有符号证据、重整名失败等一切拿不到证据的情形（`nil`）一律保留——过滤绝不靠猜。
因此 `-enable-testing` 构建里的 `internal` 声明、`@usableFromInline` 类型会被保留，这是导出表的真实状态。

裁决规则：

| 对象 | 判据 | 备注 |
|------|------|------|
| 类型 | `_$s<type>Mn`（nominal type descriptor）在 export trie | 从 `TypeName.node` 重整（剥 `.type` 壳与 bound-generic 壳）；C 导入类型的外来描述符不导出，`--show-c-imported-types` 下会被过滤 |
| 协议 | `_$s<protocol>Mp`（protocol descriptor）在 export trie | 同上 |
| 成员（函数 / 计算属性 / 下标 / 协议 requirement） | 0008 的 `exportVerdict(forSymbolNames:)`：任一符号（含派生形态）导出即保留 | `override` / `@objc` 成员豁免（保留）；协议 requirement 经 `Tq` 派生形态命中 |
| 存储属性 | accessor 组的同一判定 | 没有 accessor 符号的字段「不可检」→ 保留；`override` / 有 `To` ObjC 入口的保留 |
| 枚举 case | 不判 | 没有符号；枚举被保留则 case 全保留 |
| 全局变量 / 函数 | 成员判定 | |
| 扩展 | 被扩展类型或遵循协议是**本镜像内**未导出声明 ⇒ 整个删除 | 目标在其它镜像的一律保留；fixture 上 44 个未导出 `Mc` 全涉及私有类型，无需再查 conformance 描述符 |
| 空扩展 | 普通扩展过滤后没有任何成员 / 嵌套声明 ⇒ 删除 | conformance 扩展即使空体也保留（它本身就是声明） |
| 嵌套类型 / 协议、特化子类型、协议默认实现扩展块 | 各按自身判据；父级被删则整块消失 | |

**落点在打印期**（用户选定）：索引出的模型保持完整，RuntimeViewer 浏览、ABI diff / snapshot / evolution 不受影响。
三个打印入口（`printTypeDefinition` / `printProtocolDefinition` / `printExtensionDefinition`）拆成「过滤壳 + builder 体」，
成员循环、字段循环、`printRoot` 的全局块各加一处 `where` 过滤。扩展的「本镜像内」判定需要索引器的类型 / 协议表，
打印器不持有索引器，所以引入 `ExportFilterScope`（本镜像内未导出的 `TypeName` / `ProtocolName` 集合），
由 `SwiftInterfaceBuilder.printRoot()` 在开关打开时从索引器构建并装到打印器上；绕过 `printRoot` 的宿主自行调用
`installExportFilterScope(types:protocols:)`，不装则扩展过滤退化为「保留」（fail-open）。

**已知限制**：过滤按声明进行，不改写引用——导出成员的签名里仍可能引用被过滤掉的类型
（fixture 里 `typealias Body = Structs.PrivateProtocolTest` 就是一例），与真实二进制里 `some P` 解析到私有类型的情形同构。
`dump` 路径不在本提案范围（用户选定）。

**验证**：`SymbolTestsCore`（library-evolution Release，`ENABLE_TESTABILITY` 打开，故只有 `private` 声明未导出）上的端到端测试
钉住类型 / 协议 / 协议默认实现扩展 / conformance 扩展 / 嵌套私有类型 / 成员 / 全局各一例的删除，以及 `Tj` 导出、`@objc`、`override`
三类保留；另用即时编译的 library-evolution fixture（无 `-enable-testing`）钉住 `internal` 类型 / 成员 / 存储属性 / 空扩展规则。
CLI flag 解析测试与默认关闭。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-02 | Created；一轮澄清（三题） | 用户原话「SwiftInterface实现只打印exported的方法和类型」 |
| 2026-09-02 | 过滤放打印期，不放索引期 | 用户选定；模型完整、diff / RuntimeViewer 不受影响，改动集中在打印器 |
| 2026-09-02 | 存储属性按 accessor 判定过滤，无证据者保留 | 用户选定；与 0008 标注一致，接近 `.swiftinterface` 对 resilient 类型的做法 |
| 2026-09-02 | 只做 `interface`，`dump` 不动 | 用户选定 |
| 2026-09-02 | 类型级判据用 `Mn` / `Mp` 描述符符号，而非 `Ma` 或 offset→符号反查 | fixture 上导出 `Mn` 集合与 `Ma` 完全一致；按名字查 trie 在 strip 过的镜像上依然给出确定的 `false`，offset 反查在 strip 后只能答 `nil` |
| 2026-09-02 | 三题均选推荐项，视为批准，直接进入 In Progress | 轻量档流程：一轮提问、点头即动手 |
| 2026-09-02 | 类型级判据改为「先反查描述符 offset 处的符号，重整名只兜底且拒绝 `.extension` 上下文」 | fixture 交叉验证发现带约束扩展里的公开嵌套类型被纯重整名判据误删——编译器只 mangle 扩展自身的 requirement，模型节点带完整签名；上一行「按名字查优于 offset 反查」的理由仍成立，故 offset 反查为第一腿、名字查询降为兜底。详见实现说明「与提案的差异」 |
| 2026-09-02 | Implemented；落地编号 0016（远端 `next` 最大 0015）。配套实现说明 [ExportedOnlyInterfaceFiltering.md](../Internal/ExportedOnlyInterfaceFiltering.md) 已登记；新术语「exported-only 过滤」已入 Glossary | 三套 22 测试 + 回归 290 测试全绿，fixture 全量交叉验证零残留 |
