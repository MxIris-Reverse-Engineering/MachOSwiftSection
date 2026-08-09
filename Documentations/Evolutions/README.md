# Evolution Proposals

- **项目类型**: 库（源码分发）—— SPM library product，下游仓库（RuntimeViewer、MachOKitUI、SymbolViewer 等）从源码重编译，无 ABI 约束，但每次公开 API 变更必须评估源码兼容性。`swift-section` 可执行产物是配套 CLI，不是对外契约。（完整声明见 [`Documentations/README.md`](../README.md) 头部。）

所有非平凡变更以提案形式落盘，一次改动 = 一份提案文件，从调研到落地全生命周期原地更新。状态机：`Draft` → `In Review` → `Accepted` → `In Progress` → `Implemented`，另有 `Rejected` / `Deferred` / `Withdrawn`；被否的提案保留不删。

编号全项目连续。0001–0003 属于内存优化线，其提案文件与实现都在 `feature/node-store-migration` 分支上，尚未并入 main——它们的文件链接在该分支并入后恢复。0004 因为修的是 main 上就有的基线 bug，直接在 main 立项与实施。

| # | 标题 | 状态 |
|---|------|------|
| 0001 | SymbolIndexStore 符号名 offset 化：驻留字符串换字符串表引用 | Implemented（`feature/node-store-migration`，待并入） |
| 0002 | 声明模型 descriptor 化：TypeDefinition / ExtensionDefinition / ProtocolDefinition 不再驻留急切解析的胖 wrapper | Implemented（`feature/node-store-migration`，待并入） |
| 0003 | SymbolIndexStore `[UInt32]` 行号桶扁平化：单元素桶内联化 | Implemented（`feature/node-store-migration`，待并入） |
| [0004](0004-arm64e-signed-vwt-pointer-hardening.md) | arm64e 签名 VWT 指针加固：进程内裸读 strip + 真 PAC 环境的回归验证形态 | Implemented |
