# Evolution Proposals

- **项目类型**: 库（源码分发）—— SPM library product，下游仓库（RuntimeViewer、MachOKitUI、SymbolViewer 等）从源码重编译，无 ABI 约束，但每次公开 API 变更必须评估源码兼容性。`swift-section` 可执行产物是配套 CLI，不是对外契约。（完整声明见 [`Documentations/README.md`](../README.md) 头部。）

所有非平凡变更以提案形式落盘，一次改动 = 一份提案文件，从调研到落地全生命周期原地更新。状态机：`Draft` → `In Review` → `Accepted` → `In Progress` → `Implemented`，另有 `Rejected` / `Deferred` / `Withdrawn`；被否的提案保留不删。

**编号在落地时分配**（2026-08-24 起，成因：多线并行下创建期取号必撞——0008→0009、0009→0010 各让位一次，opaque 归属提案 0005→0006→0011 两次改号）：创建期文件名用 `draft-<slug>.md` 不占号、状态表编号列写 `draft`；合入长寿命共享分支（main / next）的落地 commit 里 fetch 全部远程共享分支、取 `Evolutions/` 编号全局最大值 +1，改名与互链同批完成。残余撞号以先推上共享分支者为准。in-flight 提案用 slug 引用；**代码与 fixture 注释引用提案只用 slug，不写编号**。演进账本 ProjectEvolutionLog 的节号同规则落地时取。存量 0001–0011 不动。

| # | 标题 | 状态 |
|---|------|------|
| [0001](0001-symbol-name-offsetization.md) | SymbolIndexStore 符号名 offset 化：驻留字符串换字符串表引用 | Implemented |
| [0002](0002-declaration-model-descriptor-slimming.md) | 声明模型 descriptor 化：TypeDefinition / ExtensionDefinition / ProtocolDefinition 不再驻留急切解析的胖 wrapper | Implemented |
| [0003](0003-symbol-row-bucket-flattening.md) | SymbolIndexStore `[UInt32]` 行号桶扁平化：单元素桶内联化 | Implemented |
| [0004](0004-arm64e-signed-vwt-pointer-hardening.md) | arm64e 签名 VWT 指针加固：进程内裸读 strip + 真 PAC 环境的回归验证形态 | Implemented |
| [0005](0005-event-based-degradation-reporting.md) | 降级上报统一走事件：库侧不再自选落点，Dispatcher 兜底零 handler | Implemented |
| [0006](0006-final-keyword-and-lazy-accessor-type-recovery.md) | `final` 成员关键字还原与 lazy var 访问器类型修正（issue #106 §1/§4） | Implemented |
| [0007](0007-extension-container-dedup-and-default-impl-attribution.md) | Extension 容器索引期去重与协议默认实现归属标注（issue #106 §5） | Implemented |
| [0008](0008-interface-header-and-export-status-annotations.md) | Interface 文件头部与导出状态标注（issue #106 §2/§3/§8） | Implemented |
| [0009](0009-type-indexing-revival.md) | TypeIndexing 重启：`__C` 类型模块归属解析的索引管线修复与重构（两线合并时由 0008 重排至 0009，见提案「编号说明」） | Implemented |
| [0010](0010-community-type-mapping-bundles.md) | 补充类型映射：私有框架 `__C` 类型的用户自备 APINotes 加载（AttributeGraph 等；合并时由 0009 重排） | Implemented |
| [0011](0011-opaque-primary-associated-type-attribution.md) | opaque 返回类型的 primary associated type 归属：anchor 协议裁决 + 协议事实解析链（main 直落线并入 next 时由 0006 重排） | Implemented |
| [0012](0012-in-process-metadata-type-builder.md) | RuntimeMetadataTypeBuilder：TypeBuilder 的首个生产 conformer，node → 进程内活 metadata | Implemented |
| [0013](0013-swift-evolution-interface-builder.md) | SwiftEvolutionInterfaceBuilder：ABI 演进的并集注解接口渲染（`evolution --interface`） | Implemented |
| [0014](0014-unify-interface-renderers.md) | 统一 diff / evolution 接口渲染器的结构遍历核心（顺带修 diff accessor 双重缩进） | Implemented |
| [0015](0015-type-name-resolver-role-split.md) | TypeNameResolvable 角色化拆分：printer 查询解析器按能力分协议 | Implemented |
| [0017](0017-macho-dependencies-module.md) | 依赖闭包下沉为 MachODependencies 模块：两套依赖加载合一 | Implemented |
| [0016](0016-exported-only-interface.md) | Interface 只打印导出声明（`--exported-only`）：提案 0008 标注的过滤形态，打印期按描述符 / 派生符号 / 扩展目标裁决 | Implemented |
| [draft](draft-self-contained-abi-layer.md) | ABI 层自包含：MachOSwiftSection 不再依赖符号索引——描述符只暴露实现地址，符号查询上移 SwiftInspection，值类型下沉 MachOResolving | In Progress |
| [draft](draft-large-stack-executor-and-cross-version-parallelism.md) | 大栈任务执行器接入与跨版本并行准备：打印路径零线程跳转（执行器本体在 swift-demangling 0014），diff / evolution 多版本并行 | Draft |
