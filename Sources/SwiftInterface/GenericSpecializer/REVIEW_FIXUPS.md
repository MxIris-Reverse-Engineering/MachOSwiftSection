# GenericSpecializer — Review Follow-up Fixes

Tracks the work derived from the `feature/generic-specializer` review.
Item labels match the original review (`M1`–`M12`, `C1`–`C8`).

## Already fixed (earlier commits on this branch)

- **H1** — `resolveAssociatedTypeWitnesses` 的 `OrderedDictionary<Metadata, [PWT]>` 分组在不同链解析到同一 leaf metadata 时会破坏 binary PWT 顺序。改回 `[ProtocolWitnessTable]` 线性数组。
- **C1** — `mergedRequirements` 注释修正：原文断言 conditional invertible 段"只含 `.invertedProtocols`"，实际可同时含 marker `.protocol`，注释更新为说明每条过滤路径。
- **C2** — `SpecializationResult.fieldOffsets()` / `fieldOffsets(in:)` 删除（不是 `SpecializationResult` 的职责）。
- **C5** — `SpecializerError` 删 3 个未触发 case；`SpecializationValidation.Error` 删 6 个未发出 case；`Warning` 删 2 个未发出 case。

## In scope this round

### Group 1 — zero-cost quick fixes

- [x] **T1 (C7)** — `IndexerConformanceProvider` doc：必须先 `prepare()` 才能传给 `GenericSpecializer`
- [x] **T2 (C8)** — `GenericSpecializer` doc：`specialize` / `runtimePreflight` 仅在 `MachO == MachOImage` 时可用
- [x] **T3 (M10)** — 测试：`makeRequest` 在非 generic 类型上应抛 `notGenericType`
- [x] **T4 (M8)** — 测试：`validate` 对未声明的参数发 `.extraArgument` warning
- [x] **T5 (C4)** — 删除 `SpecializationSelection` 的 `init(_:variadic)` 与 `init(_:unlabeled-dict)` 两个重复重载

### Group 2 — coverage gaps

- [x] **T6 (M2a)** — 测试：`Argument.metadata(...)` 成功路径
- [x] **T7 (M2b)** — 测试：`Argument.candidate(...)` 成功路径（非 generic candidate）
- [x] **T8 (M2c)** — 测试：`Argument.specialized(...)` 递归 specialize（嵌套 generic 类型作为 GP）
- [x] **T9 (M3)** — 测试：三层嵌套 `~Copyable` `specialize` 端到端（fixture 已存在，仅缺 specialize 调用）
- [x] **T10 (M5)** — 新增 `~Escapable` 与 `~Copyable & ~Escapable` fixture + 测试（dual 用空 enum，由于工具链 bug 暂去掉条件扩展）

### Group 3 — enum / class coverage

- [x] **T11 (M1a)** — 新增 `TestGenericEnum` fixture + makeRequest / specialize 测试
- [x] **T12 (M1b)** — 新增 `TestGenericClass` fixture + makeRequest / specialize 测试

### Final

- [ ] **T13** — 跑 `swift test --filter GenericSpecializationTests` 确认全绿；跑 `swift build` 全包确认无外部回归

## Deferred (not fixed this round, recorded for record)

| 项 | 原因 |
|---|---|
| M4 (`where A == B` / sameType / baseClass non-AnyObject) | fixture 是否能 compile 本身需要验证；ROI 与风险不匹配 |
| M6 (`CompositeConformanceProvider` / `StandardLibraryConformanceProvider` 单测) | 简单 wrapper，价值有限 |
| M7 (`metadata()` / `valueWitnessTable()` / `argument(for:)` / `fullPath` 公开 API caller 测试) | 隐式被 M2 / M3 覆盖 |
| M9 (`Outer<A>.Inner<B, C>` 内层多 GP) | 路径已被 `perLevelNewParameterCounts` 覆盖；fixture 投入大 |
| M11 (marker / ObjC-only protocol silent skip) | 边角行为，目前没观察到 bug |
| M12 (`runtimePreflight` indexer 缺失协议时静默 skip) | 边角行为 |
| C3 (`StandardLibraryConformanceProvider` doc 警告) | 可在使用方加注释，非紧急 |
| C6 (`extractAssociatedPath` 防御日志) | 纯防御，未被触发 |
