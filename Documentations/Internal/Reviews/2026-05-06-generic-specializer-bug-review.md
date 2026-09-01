# GenericSpecializer 代码审查与修复总结

**审查日期：** 2026-05-06
**审查对象：** `Sources/SwiftInterface/GenericSpecializer/`、`Tests/SwiftInterfaceTests/GenericSpecializationTests.swift`、`Sources/SwiftDump/Extensions/GenericContext+Dump.swift`
**审查方法：** 对照 Swift 编译器源码（`/Volumes/SwiftProjects/swift-project/swift/lib/IRGen/GenMeta.cpp`、`lib/AST/GenericSignature.cpp`、`lib/AST/RequirementMachine/RequirementBuilder.cpp`、`lib/AST/Requirement.cpp`、`include/swift/AST/DiagnosticsSema.def`）逐项验证当前实现的正确性。
**约束：** generic type pack 与 value generics 已声明为暂不实现的功能，不在审查范围内。

---

## 一、最终落地的修复（4 项）

| 编号 | 主题 | 类型 | 复现测试 |
| ---- | ---- | ---- | -------- |
| P3 | TypePack/Value 参数早抛 | bug fix | `typePackParameterThrowsEarly` |
| P5 | SwiftDump 累积参数 dump | bug fix（潜伏） | `nestedThreeLevelDumpAllLevelsHasNoDuplicates` |
| P6 | `validate()` 运行时预检 | API 增强 + 错误时机修正 | `runtimePreflightCatches{ProtocolMismatch,LayoutMismatch}` |
| P8 | AssociatedTypeRequirement 按 (param, path) 聚合 | 语义修正 | `associatedTypeRequirementsAggregatedByPath` |

附加：

- P2：补 `nestedThreeLevelSpecializeEndToEnd` 端到端测试，关闭 commit `aa07d74` 留下的覆盖缺口（不是新 bug，是测试缺口）。
- P7：新增 `SpecializationRequest.CandidateOptions.excludeGenerics`，UX 增强（不是 bug）。

每条复现测试都在临时撤回相应修复后实测确认会失败：

| 修复 | 撤回后观察到的错误 |
| ---- | ----------------- |
| P3 | `Issue.record("makeRequest must reject…")` —— 旧实现静默跳过 TypePack |
| P5 | dumped 字符串等于 `A, A1, B1, A2`，phantom `B1` 被复现 |
| P6 | `specialize` 抛 `witnessTableNotFound`，而非 `specializationFailed` |
| P8 | `elementEntries.count == 3 ≠ 1`，每个 requirement 一条独立记录 |

---

## 二、撤回的修复（3 项，附原因）

### P1（已撤）：mergedRequirements 过滤 conditional 中的非-invertible

**最初的判断：** Conditional invertible 区段经由 `addGenericRequirements` 写入，理论上可以含 `Conformance` 类型记录（例如 `where T: Hashable`），合并后会污染 base 参数列表。

**对照源码后发现：** Swift 前端在 sema 阶段就会拒绝这种写法。

```
DiagnosticsSema.def:8200 inverse_cannot_be_conditional_on_requirement
"conditional conformance to suppressible <Copyable/Escapable> cannot depend on '<type><:|==|has same shape as><type>'"
```

实测尝试 `extension X: Copyable where A: Copyable, A: Equatable {}` 直接编译失败，所以条件区段在合法 Swift 二进制里**只可能**含 `.invertedProtocols`。

**当前代码的工作机理：** 即便 conditional 区段确实只含 `.invertedProtocols`，原本的代码：

- `collectInvertibleProtocols` 通过 `genericParamIndex == flatIndex` 过滤——条件区段里"正向 Copyable"形式的 `genericParamIndex == 0xFFFF`，永远不匹配真实参数 ordinal，自动跳过；
- `buildRequirement` 对 `.invertedProtocols` 返回 `nil`，不会进入 `parameter.requirements`；
- `resolveAssociatedTypeWitnesses` 仅看 `.protocol` kind。

所以即使源码层面允许该输入，下游也已正确过滤。**P1 是个幽灵 bug。**

**结论：** 撤回过滤代码，更新 `mergedRequirements` 注释解释这个不变量（Swift sema 强制 + 下游 kind 过滤双重保障）。

### P4（已撤）：specialize 单次 canonical 遍历

**最初的判断：** 现有 2 阶段写法（先按参数顺序收 direct PWT、再追加 associated PWT）依赖一个隐式的不变量"GP 优先于 nested type"，不直接对应二进制布局规则。

**对照源码后发现：** Swift `compareDependentTypesRec`（`GenericSignature.cpp:846`）对 (GP, nested-type) pair 总是返回 GP 在前；且 weight 在普通泛型场景下都是 0，不会 fall through 出非 GP-优先的顺序。也就是说，2 阶段写法的输出与 canonical 顺序**逐字节相等**，不是巧合，是 Swift 排序规则的直接推论。

**结论：** P4 不是 bug fix，是代码风格 refactor。撤回新写法，保留 2 阶段，但在注释里把不变量与对应 Swift 源码位置写清楚。

#### 我曾认为更稳健的方案（保留以备后续参考）

如果未来 Swift 改了 `compareDependentTypesRec`、或我们要支持 type pack / value generics 让 weight 出现非零情形，可以切换到下面的单次 canonical 遍历。它把"按 binary canonical 顺序遍历"做成显式逻辑，不依赖排序推论：

```swift
public func specialize(...) throws -> SpecializationResult {
    let typeDescriptor = request.typeDescriptor.asPointerWrapper(in: machO)

    let staticValidation = validate(selection: selection, for: request)
    guard staticValidation.isValid else { /* throw */ }
    let runtimeValidation = runtimePreflight(selection: selection, for: request)
    guard runtimeValidation.isValid else { /* throw */ }

    // Phase 1 — metadata in declaration order.
    var metadatas: [Metadata] = []
    var metadataByName: [String: Metadata] = [:]
    for parameter in request.parameters {
        let argument = selection[parameter.name]!  // validate 已保证存在
        let metadata = try resolveMetadata(for: argument, parameterName: parameter.name)
        metadatas.append(metadata)
        metadataByName[parameter.name] = metadata
    }

    // Phase 2 — 一次性按 binary canonical 顺序产 PWT。
    let genericContext = try requireGenericContextInProcess(for: request.typeDescriptor)
    let mergedReqs = Self.mergedRequirements(from: genericContext)
    var witnessTables: [ProtocolWitnessTable] = []
    var perParamPWTs: [String: [ProtocolWitnessTable]] = [:]

    for requirement in mergedReqs {
        guard requirement.flags.kind == .protocol,
              requirement.flags.contains(.hasKeyArgument) else { continue }

        let resolvedContent = try requirement.resolvedContent()
        guard case .protocol(let protocolRef) = resolvedContent,
              let resolved = protocolRef.resolved,
              let swiftDescriptor = resolved.swift else { continue }
        let proto = try MachOSwiftSection.Protocol(descriptor: swiftDescriptor)

        let paramNode = try MetadataReader.demangleType(for: requirement.paramMangledName())
        let targetMetadata: Metadata
        let directParamName: String?

        if let directName = Self.directGenericParamName(of: paramNode) {
            targetMetadata = metadataByName[directName]!
            directParamName = directName
        } else if let pathInfo = Self.extractAssociatedPath(of: paramNode), !pathInfo.steps.isEmpty {
            guard let indexer else { throw AssociatedTypeResolutionError.missingIndexer }
            var current = metadataByName[pathInfo.baseParamName]!
            for step in pathInfo.steps {
                current = try resolveAssociatedTypeStep(
                    currentMetadata: current,
                    step: step,
                    allProtocolDefinitions: indexer.allAllProtocolDefinitions
                )
            }
            targetMetadata = current
            directParamName = nil
        } else {
            continue
        }

        guard let pwt = try? RuntimeFunctions.conformsToProtocol(
            metadata: targetMetadata,
            protocolDescriptor: proto.descriptor
        ) else {
            throw SpecializerError.witnessTableNotFound(/* … */)
        }

        witnessTables.append(pwt)
        if let name = directParamName {
            perParamPWTs[name, default: []].append(pwt)
        }
    }

    var resolvedArguments: [SpecializationResult.ResolvedArgument] = []
    for parameter in request.parameters {
        resolvedArguments.append(.init(
            parameterName: parameter.name,
            metadata: metadataByName[parameter.name]!,
            witnessTables: perParamPWTs[parameter.name] ?? []
        ))
    }

    let response = try /* accessor */(request: metadataRequest, metadatas: metadatas, witnessTables: witnessTables)
    return SpecializationResult(metadataPointer: response.value, resolvedArguments: resolvedArguments)
}
```

**好处：**

- "PWT 顺序 = mergedRequirements 顺序" 写在循环里而非靠不变量推导。
- 不再需要 `resolveAssociatedTypeWitnesses` 这条单独路径（虽然它对外仍是 `@_spi(Support)` 保留 API，给 `main()` 测试用）。
- 与 `swift/lib/IRGen/GenMeta.cpp:7351` `addGenericRequirements` 的发射顺序一一对应。

**触发切换的信号：**

- 新增 type pack / value generics 支持，weight 不再恒等；
- Swift 改 `Requirement::compare` 或 `compareDependentTypesRec` 的排序规则；
- 想统一处理 same-type / base-class 的 PWT-less 校验路径。

不触发上述任一条之前，2 阶段实现工作正确且更短。

### P7（保留）：CandidateOptions.excludeGenerics

严格说不是 bug，是 UX 改进。原始候选列表会包含 `Array`、`Dictionary` 等带 `isGeneric: true` 的条目，调用方选了再调 `specialize` 才会拿到 `candidateRequiresNestedSpecialization`。新增的 `.excludeGenerics` 让调用方在 `makeRequest` 阶段就把这类剔除掉。

保留是因为它不破坏任何契约（默认值是 `.default` 即旧行为），追加的字段是 `OptionSet` 形式可向前扩展。

---

## 三、各项 bug 及修复细节

### P3：TypePack / Value 参数静默跳过

**问题：** `buildParameters` 用 `guard param.hasKeyArgument, param.kind == .type else { continue }` 跳过 typePack/value 参数。结果：

1. `request.parameters.count` 少于 `genericContext.header.numKeyArguments` 暗含的真实参数数；
2. `specialize` 循环迭代 `request.parameters` 把 metadata pointer 数组做齐，但少塞；
3. metadata accessor 拿到不齐的数组，最终在运行时崩溃或返回错值。

**修复：** `makeRequest` 入口检查 `genericContext.parameters` 里是否有 `.typePack` 或 `.value`，若有立即抛 `SpecializerError.unsupportedGenericParameter(parameterKind:)`。

**复现测试：** `typePackParameterThrowsEarly`，fixture 是 `struct TestTypePackStruct<each T> { let value: (repeat each T) }`。撤回修复后测试落到 `Issue.record("makeRequest must reject…")`。

### P5：SwiftDump 累积参数 dump（≥ 3 层嵌套时输出错位）

**问题：** `dumpGenericParameters(isDumpCurrentLevel: false)` 遍历 `allParameters`，但 `parentParameters` 每一层是**累积存储**（每层都包含父级的所有参数）。原代码：

```swift
for (offsetAndDepth, depthParameters) in allParameters.offsetEnumerated() {
    for (offset, parameter) in depthParameters.offsetEnumerated() {
        try Standard(genericParameterName(depth: offsetAndDepth.index, index: offset.index))
        ...
    }
}
```

对三层嵌套 `Outer<A>.Middle<B>.Inner<C>`，`allParameters = [[A], [A, B], [C]]`，输出 `<A, A1, B1, A2>`：

- depth 0 输出 `A` —— 正确；
- depth 1 输出 `A1, B1` —— `A1` 实际是 Outer 的 A 在 cumulative 形式下被重命名，`B1` 是 phantom 槽；
- depth 2 输出 `A2` —— Inner 的 C，正确。

正确输出应是 demangler-canonical 名 `<A, A1, A2>`。

**修复：** 切换到 per-level "新增"切片走法，与 `GenericSpecializer.perLevelNewParameterCounts` 同源：

```swift
let perLevelCounts = Self.dumpPerLevelNewParameterCounts(
    parentParameters: parentParameters,
    currentCount: currentParameters.count
)
var paramOffset = 0
for (depthIndex, newCount) in perLevelCounts.enumerated() {
    for indexInLevel in 0..<newCount {
        let parameter = parameters[paramOffset + indexInLevel]
        try Standard(genericParameterName(depth: depthIndex, index: indexInLevel))
        ...
    }
    paramOffset += newCount
}
```

**潜伏性：** 当前代码库里 `dumpGenericSignature` 的所有调用者都用默认 `isDumpCurrentLevelParams: true`，即"只 dump 当前层"路径。`isDumpCurrentLevel: false` 路径只在测试中通过 `dumpGenericParameters(in:isDumpCurrentLevel: false)` 被触发到。修复后即便外部 caller 切到 false 也得到正确输出。

**复现测试：** `nestedThreeLevelDumpAllLevelsHasNoDuplicates`，对照 `NestedGenericThreeLevelInner` 三层嵌套 fixture，断言：

- 输出含 `A`、`A1`、`A2`；
- 不含 phantom `B1`；
- 按逗号分割后裸 `A` token 只出现一次。

撤回修复后测试拿到 `A, A1, B1, A2`，phantom-B1 与重复 A 检查同时失败。

### P6：`validate()` 运行时预检

**问题：** 原 `validate(selection:for:)` 只做 missing/extra 参数检查。任何对所选 metadata 类型的实际匹配（协议、类约束）都要等到 `specialize` 跑到 `RuntimeFunctions.conformsToProtocol` 才报错，错误形式是 `witnessTableNotFound(typeName:protocolName:)`，定位不直观。

**修复：**

1. `validate` 签名保留，仅做静态检查（轻量、`MachO` 任意）。
2. 新增 `runtimePreflight(selection:for:)`，仅在 `MachO == MachOImage` 上可用，针对 `.metatype` / `.metadata` 类型的 selection 做：
   - 协议要求：`RuntimeFunctions.conformsToProtocol(metadata, protocolDescriptor)` 拿不到 PWT 时报 `protocolRequirementNotSatisfied`；
   - layout(.class) 要求：检查 metadata 的 kind 不在 `.class / .objcClassWrapper / .foreignClass` 报 `layoutRequirementNotSatisfied`；
   - `.candidate` / `.specialized` 跳过（需要先调 accessor 才能拿 metadata，由 specialize 主流程兜底）。
3. `specialize` 先 `validate`，再 `runtimePreflight`，两者都通过才进入 metadata 解析阶段。任一失败都包成 `SpecializerError.specializationFailed(reason:)` 抛出。

**契约保护：** 因为 `runtimePreflight` 不预检 generic candidate（避开 `requiresFurtherSpecialization` 拦截），原有的 `candidateRequiresNestedSpecialization` 错误路径继续走 `resolveCandidate`，不破坏 `genericCandidateFailFast` / `candidateErrorMessageMentionsSpecialized` 测试。

**复现测试：**

- `runtimePreflightCatchesProtocolMismatch`：`TestSingleProtocolStruct<A: Hashable>` 选 `() -> Void`（不 Hashable），断言 `runtimePreflight().errors` 含 Hashable 错误，且 `specialize` 抛 `specializationFailed` 而非 `witnessTableNotFound`。撤回修复后测试拿到 `witnessTableNotFound`，不匹配 `specializationFailed` 分支。
- `runtimePreflightCatchesLayoutMismatch`：`TestClassConstraintStruct<A: AnyObject>` 选 `Int`，断言 `runtimePreflight` 报 `layoutRequirementNotSatisfied`。

### P8：AssociatedTypeRequirement 按 (param, path) 聚合

**问题：** 原 `buildAssociatedTypeRequirements` 为每个 requirement 单独生成一条 `AssociatedTypeRequirement`。`TestGenericStruct<A: Collection, B, C> where A.Element: Hashable, A.Element: Decodable, A.Element: Encodable` 会产生三条 `path == ["Element"]` 的记录，每条 `requirements` 里只有一项。但字段类型是 `requirements: [Requirement]`（复数），暗示应聚合，调用方却必须自己再 group by。

**修复：** 用 `(parameterName, path)` 作为聚合 key 收集 requirement 列表，按首次出现顺序产出，所以同一 path 多个约束按 binary canonical 顺序进入同一个 `requirements` 数组：

```swift
private func buildAssociatedTypeRequirements(...) throws -> [...] {
    var entriesByKey: [AssociatedTypeRequirementKey: [SpecializationRequest.Requirement]] = [:]
    var orderedKeys: [AssociatedTypeRequirementKey] = []
    for genericRequirement in genericRequirements {
        guard let pathInfo = Self.extractAssociatedPath(of: paramNode), !pathInfo.steps.isEmpty else { continue }
        guard let requirement = try buildRequirement(from: genericRequirement) else { continue }
        let key = AssociatedTypeRequirementKey(
            parameterName: pathInfo.baseParamName,
            path: pathInfo.steps.map(\.name)
        )
        if entriesByKey[key] == nil { orderedKeys.append(key) }
        entriesByKey[key, default: []].append(requirement)
    }
    return orderedKeys.map { ... }
}

private struct AssociatedTypeRequirementKey: Hashable {
    let parameterName: String
    let path: [String]
}
```

注意 `Key` 不能嵌在泛型方法里（Swift 限制），所以提到 extension 里。

**复现测试：** `associatedTypeRequirementsAggregatedByPath`：

- 期望 `path == ["Element"]` 的条目数为 1；
- 期望该唯一条目的 `requirements.count == 3`；
- 期望 requirements 按字母序保留 canonical（Decodable < Encodable < Hashable）。

撤回修复后测试报 `count → 3 ≠ 1` 和 `requirements.count → 1 ≠ 3`。

---

## 四、新增的覆盖测试（非 bug fix）

### P2：nested generic specialize 端到端

之前 commit `aa07d74` 修了三层嵌套泛型在 `makeRequest` / `currentRequirements` / `invertibleProtocols` 这几个点的 bug，但加的测试都只断言到 `request` 这个层面。`specialize` 调用 metadata accessor 这条完整链路对 ≥ 2 层嵌套从来没跑过。

补 `nestedThreeLevelSpecializeEndToEnd`：用 `NestedGenericThreeLevelInner<Int, Double, String>`（满足 Hashable / Equatable / Comparable）跑完 `specialize`，断言：

- `resolvedArguments` 顺序 `["A", "A1", "A2"]`；
- 每个直接 GP 约束贡献一个 PWT；
- `fieldOffsets() == [0, 8, 16]`（Int + Double + String 布局）。

这条测试在 aa07d74 之前会失败（参数名错位导致 metadata accessor 调用失败），现在通过；之后就是抗回归保险。

---

## 五、不在本次审查范围内的 follow-up

留给后续 PR：

1. `mergedRequirements` 现在是 `genericContext.requirements + conditionalInvertibleProtocolsRequirements`，依赖 sema 保证 conditional 区段只含 `.invertedProtocols`。如果将来要保护 against 手工伪造的二进制（非 swiftc 产出），可以加 `kind == .invertedProtocols` 过滤，把当前的隐式信任写成显式。
2. P4 列出的"单次 canonical 遍历"方案在引入 type pack / value generics 时切换。同一 PR 顺手把 `resolveAssociatedTypeWitnesses` 标 deprecated 或合并掉。
3. SwiftDump 端如果将来要支持完整的 `<all-levels>` dump（目前所有调用者都是 `current`），P5 修过的 false 分支路径就可以正式走起来——届时应同步把现有 fixtures 跑一遍 baseline 重生。

---

## 六、本次提交 surface

**修改文件：**

- `Sources/SwiftInterface/GenericSpecializer/GenericSpecializer.swift`（P3 makeRequest 入口检查、P6 runtimePreflight + specialize 联动、P7 candidateOptions、P8 聚合 key、`SpecializerError.unsupportedGenericParameter`）
- `Sources/SwiftInterface/GenericSpecializer/Models/SpecializationRequest.swift`（P7 `CandidateOptions`）
- `Sources/SwiftDump/Extensions/GenericContext+Dump.swift`（P5 per-level walker + 两个 helper）
- `Tests/SwiftInterfaceTests/GenericSpecializationTests.swift`（P2 + P3 + P5 + P6 ×2 + P7 + P8 共 7 条测试 + 1 个 fixture）

**API 增加：**

- `SpecializerError.unsupportedGenericParameter(parameterKind: GenericParamKind)`
- `GenericSpecializer.makeRequest(for:candidateOptions:)`（兼容旧无参形式，默认值 `.default`）
- `SpecializationRequest.CandidateOptions`（OptionSet：`.default` / `.excludeGenerics`）
- `GenericSpecializer.runtimePreflight(selection:for:)`（仅 `MachO == MachOImage`）

**API 行为变化：**

- `validate(selection:for:)` 文档更新（强调静态检查，不再误导调用方"specialize 会替你跑深度校验"）。
- `specialize` 现在会先静态校验、再运行时预检，最后才进 metadata 阶段；预检失败抛 `specializationFailed`。
- `request.associatedTypeRequirements` 同 path 多约束聚合到一条记录（行为改变，调用方需重新 group 的代码可以删掉）。
