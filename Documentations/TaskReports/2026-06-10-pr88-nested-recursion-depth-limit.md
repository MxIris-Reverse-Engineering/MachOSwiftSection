# 2026-06-10 - PR #88 嵌套递归 depth limit:抽常量 + 警告 + 合同测试

- **日期**: 2026-06-10
- **关联 PR**: https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/pull/88
- **关联文档**: `2026-06-10-pr88-nested-generic-specialization-followups.md` 中 **E** 段
- **分支**: `codex/fix-specialization-recursive-description`
- **作者**: Mx-Iris

## 背景

PR #88 review 期间 Copilot + 我自己都指出:`Sources/SwiftInterface/Components/Definitions/TypeDefinition.swift` 与 `Sources/SwiftDump/Protocols/TypedDumper.swift` 各自硬编码了 `depth < 16` 上限,**且超过上限时静默返回空**。三个问题:

1. 同一个 magic number 跨文件重复。
2. 触达上限的调用方完全分辨不出「真的没有更深嵌套」还是「被上限掐了」。
3. 没有任何回归测试 pin 死这个值,后续修改容易引入 silent regression。

PR review 时把这条记为 E,延后处理。本 commit 系列收尾 E。

## 改动概览

### 1. 抽常量

**`Sources/SwiftInterface/Components/Definitions/TypeDefinition.swift`**

加 `@_spi(Support) public static let nestedSpecializationDepthLimit = 16`。`@_spi(Support)` 让回归测试用 `@_spi(Support) import SwiftInterface` 即可读到,不需要 `@testable`。

将 `deriveNestedSpecializedTypeChildren` 中 `guard depth < 16 else { return [] }` 改为 `guard depth < Self.nestedSpecializationDepthLimit else { ... }`。

**`Sources/SwiftDump/Protocols/TypedDumper.swift`**

加 `package let nestedFieldOffsetExpansionDepthLimit = 16`,**file-level** 常量。原因:`TypedDumper` 是 protocol,Swift protocol 不支持 stored static let。`package` 可见性让 `SwiftDumpTests` 用 `@testable import SwiftDump` 直接读到,且不污染外部 API surface。

将 `walkNestedExpandedFieldOffsets` 中 `if depth < 16, let wrapper = ...` 拆成「first-guard、then 处理」,头部命中上限走告警 helper。

### 2. 触达上限时打 `os_log` 警告

两处都加了对应的 `OSLog`(`subsystem` 命名隔离:`com.machoswiftsection.swift-interface` 与 `com.machoswiftsection.swift-dump`)。

**选 `OSLog` + `os_log()` 而不是 `Logger.warning(...)`**:Package.swift 设的最低 `platforms` 是 macOS 10.15,而 `os.Logger` 类型要 macOS 11+。`OSLog(subsystem:category:)` 与 `os_log()` 函数 macOS 10.12+ 可用,无需提升整包最低版本。

警告 level 选 `.info`:这个状况非崩溃、非严重错误,但调试时希望默认看得见。

警告消息举例:

```
deriveNestedSpecializedTypeChildren reached nested specialization depth limit 16 — truncating subtree at MyOuter<Int>
walkNestedExpandedFieldOffsets reached nested field-offset depth limit 16 — truncating expansion of MyDeeplyNested.Type
```

**SwiftDump 一侧的 `os_log` 必须从 result-builder body 中抽到普通函数** — `walkNestedExpandedFieldOffsets` 标了 `@SemanticStringBuilder`,直接在 builder body 调用返回 `Void` 的 `os_log` 不是非法,但读起来奇怪、容易踩 builder 元素求值次序。新增 `emitNestedFieldOffsetDepthLimitWarning(for:)` 普通函数把 log 调用包起来,builder body 只看见一个 `Void` 调用。

### 3. 合同测试(contract pin)

**`Tests/SwiftInterfaceTests/NestedSpecializationDepthLimitTests.swift`**

```swift
@Test("nestedSpecializationDepthLimit pins to 16")
func limitIsSixteen() {
    #expect(TypeDefinition.nestedSpecializationDepthLimit == 16)
}

@Test("nestedSpecializationDepthLimit is strictly positive")
func limitIsStrictlyPositive() {
    #expect(TypeDefinition.nestedSpecializationDepthLimit > 0)
}
```

**`Tests/SwiftDumpTests/NestedFieldOffsetExpansionDepthLimitTests.swift`**

同样两条,断言 `nestedFieldOffsetExpansionDepthLimit`。

「严格正」是防御性断言:若有人把上限改成 0 或负数,会**立刻**短路掉整个 walker / derivation,而 `pins to 16` 那条无法覆盖这种降为 0 的情况。

#### 为什么没有「16+ 层人造嵌套」行为测试

PR 原 review 评论建议「人造 16+ 层嵌套类型,断言截断真的发生但不崩」。这种 fixture 要在 `Tests/Projects/SymbolTests/` 里手写 16+ 层嵌套 struct/enum 并重新 build。工作量 vs 收益:

- 16 层用户源码层嵌套属于人造极端情况,实际很难遇到。
- contract pin 测试已经能挡住绝大多数 silent regression(任何人改常量值会被两条测试卡住)。
- `os_log` 警告意味着即使触发也不会真的「静默」,有可观察信号。

如果未来线上真的遇到上限触发且需要更高的值,届时再回头补 fixture-driven 行为测试不迟。

## 验证

```bash
swift build 2>&1 | xcsift --quiet
# → status: success, 0 errors, 2 pre-existing warnings

swift test --skip IntegrationTests --filter \
  "NestedSpecializationDepthLimitTests|NestedFieldOffsetExpansionDepthLimitTests" 2>&1 | xcsift
# → 4 passed, 0 failed
```

## 处置说明

E 段闭环。原 PR #88 review 上的 4 条公开评论(Copilot 3 + gemini 1)与 2 条延后 follow-up (C、D)全部有结果:C、D 经代码实证假设不成立,E 已实现。详见 `2026-06-10-pr88-nested-generic-specialization-followups.md`「终态」段。
