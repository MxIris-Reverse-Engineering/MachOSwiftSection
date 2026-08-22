# Evolution Proposals

- **项目类型**: 库（源码分发）—— SPM library product，下游仓库（RuntimeViewer、MachOKitUI、SymbolViewer 等）从源码重编译，无 ABI 约束，但每次公开 API 变更必须评估源码兼容性。`swift-section` 可执行产物是配套 CLI，不是对外契约。（完整声明见 [`Documentations/README.md`](../README.md) 头部。）

所有非平凡变更以提案形式落盘，一次改动 = 一份提案文件，从调研到落地全生命周期原地更新。状态机：`Draft` → `In Review` → `Accepted` → `In Progress` → `Implemented`，另有 `Rejected` / `Deferred` / `Withdrawn`；被否的提案保留不删。

| # | 标题 | 状态 |
|---|------|------|
| [0001](0001-symbol-name-offsetization.md) | SymbolIndexStore 符号名 offset 化：驻留字符串换字符串表引用 | Implemented |
| [0002](0002-declaration-model-descriptor-slimming.md) | 声明模型 descriptor 化：TypeDefinition / ExtensionDefinition / ProtocolDefinition 不再驻留急切解析的胖 wrapper | Implemented |
| [0003](0003-symbol-row-bucket-flattening.md) | SymbolIndexStore `[UInt32]` 行号桶扁平化：单元素桶内联化 | Implemented |
| [0004](0004-arm64e-signed-vwt-pointer-hardening.md) | arm64e 签名 VWT 指针加固：进程内裸读 strip + 真 PAC 环境的回归验证形态 | Implemented |
| [0005](0005-event-based-degradation-reporting.md) | 降级上报统一走事件：库侧不再自选落点，Dispatcher 兜底零 handler | Implemented |
| [0006](0006-final-keyword-and-lazy-accessor-type-recovery.md) | `final` 成员关键字还原与 lazy var 访问器类型修正（issue #106 §1/§4） | Implemented（`feature/0006-final-and-lazy-recovery`，待并入） |
| [0007](0007-extension-container-dedup-and-default-impl-attribution.md) | Extension 容器索引期去重与协议默认实现归属标注（issue #106 §5） | Accepted |
| [0008](0008-interface-header-and-export-status-annotations.md) | Interface 文件头部与导出状态标注（issue #106 §2/§3/§8；待 §6 重构落地后开工） | Accepted |
