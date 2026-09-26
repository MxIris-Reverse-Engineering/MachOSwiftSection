# 0027 - `@LocatableLayoutWrapping`：`LocatableLayoutWrapper` 三项要求的样板宏

- **状态**: Implemented
- **创建日期**: 2026-09-11
- **最后更新**: 2026-09-11
- **所属愿景**: 无
- **配套文档**: 无（改动自解释，不另写实现说明）

## 摘要

`ResolvableLocatableLayoutWrapper`（= `LocatableLayoutWrapper & Resolvable`）的三项存储级要求 —— `var layout: Layout`、`let offset: Int`、`init(layout:offset:)` —— 在 `Sources/MachOSwiftSection/Models/` 下被逐字手写了 **97 遍**，每处 7 行，无一处有自定义逻辑（97 个 init 体只有「两条赋值语句谁先谁后」这一种差异）。真正承载信息的只有嵌套的 `Layout` struct，样板把它埋在噪声里。本提案新增一个 attached member macro `@LocatableLayoutWrapping`，一次性替换全部 97 处，并同步调整覆盖率扫描器使其认识该宏。

## 方案

### 宏本身

`@LocatableLayoutWrapping` 贴在 wrapper struct 上，只生成三项要求，**不生成 conformance** —— 协议名继续写在声明处，这样源码里「谁是 `ResolvableLocatableLayoutWrapper`」仍然可搜、可读，`BuiltinTypeDescriptor: ResolvableLocatableLayoutWrapper, TopLevelDescriptor` 这类多重 conformance 也不必拆成一半写一半生成。

```swift
@LocatableLayoutWrapping
public struct MethodDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let flags: MethodDescriptorFlags
        public let implementation: RelativeDirectRawPointer
    }
}
```

展开为现有形状：`var layout: Layout` + `let offset: Int` + 两条赋值的 init。生成成员的访问级别**跟随宿主 struct 的修饰符**（现存 97 处全是 `public`，但泛型工具类型今后可能是 internal）。宿主若已手写同名成员，跳过该项并发一条 warning 诊断 —— 静默跳过会让「宏没生效」难以察觉。

落点：实现 `Sources/MachOMacros/LocatableLayoutWrappingMacro.swift`，注册进 `MachOMacroPlugin.swift`，声明 `Sources/Utilities/Macros/LocatableLayoutWrapping.swift`（与现有 `Layout.swift` 并列；`MachOSwiftSection/Exported.swift` 已 `@_exported import MachOBase`，而 `MachOBase` 再 `@_exported import Utilities`，故 97 个文件无需新增 import）。

### 迁移

97 处一次性全换。顺带统一三处偶然写成 `var offset` 的类型（`ProtocolDescriptor` / `ProtocolWitnessTable` / `AssociatedTypeRecord`）—— 全库没有任何地方给 `offset` 赋值，`let` 是正确形状。`Layout` 嵌套 struct、所有扩展方法、conformance 列表一概不动。

### 覆盖率契约

`PublicMemberScanner` 是纯源码扫描，看不到宏展开结果，而 `layout` / `offset` 是被覆盖率统计的 public 成员（170 个 baseline 文件中 96 个的 `registeredTestMethodNames` 含这两个名字）。样板移进宏后，`MachOSwiftSectionCoverageInvariantTests` 的「② extra」会大面积变红。

处理方式是**让扫描器认识宏**：`PublicMemberVisitor` 遇到带 `@LocatableLayoutWrapping` 的类型声明时，为其补上 `layout` / `offset` 两个 `MethodKey`，等价于现在手写时扫到的结果。`init(layout:offset:)` 早已被扫描器显式跳过，不受影响。于是 96 个 baseline 文件和 `CoverageAllowlistEntries.swift` 一个字都不用改，覆盖率契约的含义完全不变。

### 验证

1. `swift build` + `swift test --skip IntegrationTests`（全量本地跑，不只 CI 子集）。
2. `MachOSwiftSectionCoverageInvariantTests` 四条不变式必须保持绿，且 `git diff` 对 `__Baseline__/` 与 `CoverageAllowlistEntries.swift` 为空 —— baseline 有任何漂移都说明扫描器补偿写错了。
3. ABI 字面量基线套件（`MethodDescriptorTests` 等）保持绿，证明展开后的读取行为逐字节不变。
4. 抽查若干宏展开结果（`-Xfrontend -dump-macro-expansions` 或 Xcode 的 Expand Macro），确认生成文本与被删掉的手写代码逐字一致。

不跑渲染 A/B：本提案不触及 demangling / printing / indexing / reader 栈的任何逻辑，展开产物与手写代码逐字相同。若验证 4 发现任何不一致，则该前提失效，需补跑 A/B。

### 取用的假设

- 不为宏新建独立的展开测试 target（项目现无宏测试 target）。97 处真实用例加上 ABI 字面量基线，比一个合成展开测试更强的证据。
- 不把 `Layout` 嵌套 struct 也吸进宏：`offset(of: \.field)`、`MemoryLayout<Layout>`、`@Layout` 协议约束全都依赖 `Layout` 是显式类型，收进宏是另一个量级的改动。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-11 | Created as Draft | 用户："给 ResolvableLocatableLayoutWrapper 的要求写一个宏吧，现在太多这几行代码了" |
| 2026-09-11 | 宏只生成三项要求，不生成 conformance | 声明处保留协议名，源码可搜可读；多重 conformance 的类型不必一半手写一半生成 |
| 2026-09-11 | 97 处一次性全换，不试点、不只对新代码生效 | 机械替换，形状唯一；分批只会让手写与宏两种写法长期并存 |
| 2026-09-11 | 改 `PublicMemberScanner` 认宏，而非从 baseline 删掉 `layout` / `offset` | 前者约十行、96 个 baseline 零变动、覆盖率契约含义不变；后者把 diff 扩到 190+ 文件，且从此让宏生成的成员彻底脱离覆盖率视野 |
| 2026-09-11 | 命名 `@LocatableLayoutWrapping` 而非 `@LocatableLayout` | 与贴在 layout protocol 上的现有 `@Layout` 区分开：一个描述字段布局，一个让类型满足 `LocatableLayoutWrapper` |
| 2026-09-11 | 顺带把三处 `var offset` 统一为 `let offset` | 全库无赋值点，是历史偶然差异，宏只能生成一种形状 |
| 2026-09-11 | 状态 Draft → Accepted | 用户批准方案原样，三个决策点（只生成三项要求 / 97 处一次性全换 / 改扫描器认宏）均按推荐执行 |
| 2026-09-11 | 状态 Accepted → Implemented，落地取号 0027 | 97 处全部迁移，全量测试绿（除两处已知的 `SharedCacheTests` 墙钟 flaky，单独复跑 0.41 秒通过），覆盖率不变式四条绿且 baseline / allowlist 零漂移，`-dump-macro-expansions` 抽查确认展开与手写逐字一致。不另写配套实现说明（AGENTS.md 的 Key Patterns 已收录约定，提案 + 任务报告足够）；未引入新术语，术语表不动 |
