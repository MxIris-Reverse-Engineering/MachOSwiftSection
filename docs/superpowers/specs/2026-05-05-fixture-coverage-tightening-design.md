# Fixture-Based Test Coverage 收紧 Design

**日期:** 2026-05-05
**状态:** 待实施
**分支:** `feature/machoswift-section-fixture-tests`
**关联 PR:** #85
**前置 spec:** `2026-05-03-machoswift-section-fixture-tests-design.md` (PR #85 原始设计)

## 问题

PR #85 (`Fixture-based test coverage for MachOSwiftSection Models/`) 的 review 暴露出 fixture 测试覆盖系统性失真。具体度量:

| 维度 | 数字 |
|---|---|
| Fixture suites 总数 | 157 |
| 从不调用 `acrossAllReaders`/`acrossAllContexts` 的 sentinel-only suites | 88 (56%) |
| 通过 `registeredTestMethodNames` 声明已覆盖的 public method 总数 | 687 |
| 实际只挂在 baseline 字符串集合里、从未真正跨 reader 验证的 method | 277 (40%) |

`MachOSwiftSectionCoverageInvariantTests` 的 "missing == [] && extra == []" 断言在过半 suite 上是空挡: 它只比对"源码声明的 public 名字"和"baseline 字符串集合里登记的名字"——后者是手动维护的 `registeredTestMethodNames` 而非 `@Test` 实际执行的 behavior。一个

```swift
@Test func registrationOnly() {
    #expect(Baseline.registeredTestMethodNames.contains("foo"))
}
```

形如上面的"sentinel 测试"永远 pass,跟方法 `foo` 是否被实际跨 reader 验证完全无关。

PR #85 的原始设计 spec 明确写过 "找不到合适样本就入 `CoverageAllowlist` 标 `needs fixture extension`,留 future work"。但实施时被偷换成 sentinel suite —— 绕过了 allowlist 必须填 `reason: String` 的强制约束,导致 fixture 缺口不可见。

本设计修复信任问题,沿三条路径并行:

- **A — Sentinel 机制就位**: 让 sentinel 成为 first-class 概念,每个 sentinel method 必须显式登记类型化 reason
- **B — Fixture 扩展**: 给 `SymbolTestsCore` 加 12-15 种新 metadata 形态,把"应能但没做"的 sentinel 转成真测
- **C — InProcess 真测**: runtime-only metadata 用 InProcess single-reader 路径 + baseline literal 真测,把"运行时分配类型"sentinel 转成真测

## 目标

1. **类型化 sentinel reason**: 引入 `SentinelReason` enum (`runtimeOnly` / `needsFixtureExtension` / `pureDataUtility`),写进 `CoverageAllowlistEntries`
2. **CoverageInvariant 新增双约束**:
   - **③ liarSentinel**: 标记 sentinel 但 suite 实际调过 `acrossAllReaders`/`inProcessContext` → fail (标签不同步)
   - **④ unmarkedSentinel**: suite 行为是 sentinel 但未登记 → fail (核心新约束,堵住"silent sentinel")
3. **88 个现有 sentinel suites (共 277 个 method) 一次性 categorize**: 启发式归类 + 人工补 unknown。Allowlist 是 per-method 粒度,但同 suite 内 method 共享同一 `SentinelReason` (用 `sentinelGroup(typeName:members:reason:)` helper 减少重复)
4. **~15 个 type 扩 fixture**: PR merge 时 `needsFixtureExtension` 类目清零 (覆盖约 15 个 suite,对应 ~50-70 个 method)
5. **~30 个 runtime-only type 转真测**: PR merge 时 `runtimeOnly` 类目清减至 ~3-5 个无法稳定构造的 type (heap 内部 metadata)
6. **可消化的 sentinel 全部消化**: PR merge 时残留 sentinel suite 仅:
   - `pureDataUtility`: ~25 个 type (合理永久 sentinel,纯 raw-value enum / flags / kind protocol;允许后续 follow-up 做 rawValue pinning 增强)
   - `runtimeOnly`: ~3-5 个 type (无法在测试进程稳定构造的 heap 内部 metadata,documented)

   _精确数字按 A2 commit 落地为准,以上为 brainstorm 阶段预估上限。_

## 非目标

- **不重构 `PublicMemberScanner` 与现有 `BaselineFixturePicker`** 已落地代码。新 picker 加在它们旁边,不动旧代码。
- **不修改 `__Baseline__/AllFixtureSuites.swift` 索引的 hand-maintained 机制** (review 提过的双源问题留独立 follow-up)
- **不动 PR #85 已经 push 的 commit 历史** (前 30+ commits 不 amend / rebase / squash)
- **不引入 Swift runtime backdeploy hack**, 走 macOS 12 + 标准 API
- **不解决 `pureDataUtility` 的 rawValue pinning 增强** (sentinel 标签就位后是 follow-up 优化项,不在本 spec 范围)

## 设计

### 1. 整体架构

```
┌─ Sources/MachOSwiftSection/Models/                    (源代码事实)
│       │
│       │  PublicMemberScanner (SwiftSyntax,保持现状)
│       ▼
│   expected: Set<MethodKey>
│
├─ Tests/MachOSwiftSectionTests/Fixtures/**/*Tests.swift  (suite 文件事实)
│       │
│       │  SuiteBehaviorScanner (SwiftSyntax,新增)         ← A 核心
│       ▼
│   suiteBehavior: [MethodKey: MethodBehavior]
│        MethodBehavior = .acrossAllReaders | .inProcessOnly | .sentinel
│
├─ Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/AllFixtureSuites.swift
│       │
│       │  反射 (保持现状)
│       ▼
│   registered: Set<MethodKey>
│
└─ Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift  (人工事实)
        │
        ▼
    allowlist: [CoverageAllowlistEntry]
        kind: AllowlistKind = .legacyExempt(reason)            ← 现有
                            | .sentinel(SentinelReason)        ← 新增

CoverageInvariant 四段断言:
  ① missing  = expected − registered − allowlist.keys                         必须为空
  ② extra    = registered − expected − allowlist.keys                         必须为空
  ③ liarSentinel  = sentinel-tagged keys whose actual behavior is non-sentinel   必须为空
  ④ unmarkedSentinel = behavior=.sentinel keys missing from sentinel-tagged set  必须为空
```

`SuiteBehaviorScanner` 在 method 粒度判定行为,聚合到 `(typeName, memberName)` key。Mixed suite (一部分 method 真测、一部分 sentinel) 自然成立 —— behavior map 是 per-key 的。

### 2. A — Sentinel 机制就位

#### 2.1 `CoverageAllowlistEntries.swift` 新 schema

```swift
package enum SentinelReason: Hashable {
    /// 类型由 Swift runtime 现场分配,不在 fixture binary 里序列化。
    /// 由 C 通过 InProcess single-reader + baseline literal pinning 覆盖。
    /// 例: MetatypeMetadata, TupleTypeMetadata, FunctionTypeMetadata,
    /// OpaqueMetadata, FixedArrayTypeMetadata, *MetadataHeader, *MetadataBounds.
    case runtimeOnly(detail: String)

    /// fixture 内缺合适样本,理论上能扩 SymbolTestsCore 后转真测。
    /// 由 B 通过新增 fixture 文件 + 转真测消化。
    /// 本 PR 内此类目最终应清零。
    /// 例: MethodDefaultOverrideDescriptor, ObjCClassWrapperMetadata,
    /// CanonicalSpecializedMetadatas* family, ResilientSuperclass.
    case needsFixtureExtension(detail: String)

    /// 纯 raw-value enum / 标记 protocol / pure-data utility,
    /// 永久 sentinel 也合理。仍要求后续 follow-up 做 rawValue pinning。
    /// 例: ContextDescriptorKind, MetadataKind, ProtocolDescriptorFlags 等。
    case pureDataUtility(detail: String)
}

package enum AllowlistKind: Hashable {
    /// 现有用法: 源码扫描误判 / @MemberwiseInit 合成 init / @testable 才可见的合成 init 等。
    case legacyExempt(reason: String)

    /// 新增: 标 sentinel 类目 + reason。
    case sentinel(SentinelReason)
}

package struct CoverageAllowlistEntry: Hashable {
    package let key: MethodKey
    package let kind: AllowlistKind

    /// 兼容现有 `legacyExempt` 调用点的 convenience init。
    package init(typeName: String, memberName: String, reason: String) {
        self.key = MethodKey(typeName: typeName, memberName: memberName)
        self.kind = .legacyExempt(reason: reason)
    }

    package init(typeName: String, memberName: String, sentinel: SentinelReason) {
        self.key = MethodKey(typeName: typeName, memberName: memberName)
        self.kind = .sentinel(sentinel)
    }
}
```

`CoverageAllowlistEntries.entries` 数组里现有的 1 项 (`ProtocolDescriptorRef.init(storage:)`) 走 `legacyExempt` 路径不变。新增 277 项 sentinel 走 `.sentinel(...)` 路径。

`CoverageAllowlistEntries.keys: Set<MethodKey>` 保持不变,仍返回所有项的 key 集合。新增便利 accessor:

```swift
extension CoverageAllowlistEntries {
    static var sentinelKeys: Set<MethodKey> {
        Set(entries.compactMap { entry in
            if case .sentinel = entry.kind { return entry.key } else { return nil }
        })
    }

    static func sentinelReason(for key: MethodKey) -> SentinelReason? {
        for entry in entries {
            if entry.key == key, case .sentinel(let reason) = entry.kind {
                return reason
            }
        }
        return nil
    }

    /// Construct a flat array of `[CoverageAllowlistEntry]` sharing the same
    /// `SentinelReason` for all `members` of `typeName`. Use this in
    /// `entries` initialization to avoid repeating the reason on every method:
    ///
    ///     static let entries: [CoverageAllowlistEntry] = [
    ///         .init(typeName: "ProtocolDescriptorRef", memberName: "init(storage:)",
    ///               reason: "synthesized memberwise init"),
    ///     ] + sentinelGroup(
    ///         typeName: "MethodDefaultOverrideDescriptor",
    ///         members: ["originalMethodDescriptor", "replacementMethodDescriptor",
    ///                   "implementationSymbols", "layout", "offset"],
    ///         reason: .needsFixtureExtension(detail: "no class with default-override table in SymbolTestsCore")
    ///     ) + sentinelGroup(...)
    static func sentinelGroup(
        typeName: String,
        members: [String],
        reason: SentinelReason
    ) -> [CoverageAllowlistEntry] {
        members.map { memberName in
            CoverageAllowlistEntry(
                typeName: typeName,
                memberName: memberName,
                sentinel: reason
            )
        }
    }
}
```

#### 2.2 `SuiteBehaviorScanner` (新增)

文件: `Sources/MachOFixtureSupport/Coverage/SuiteBehaviorScanner.swift`

```swift
package struct SuiteBehaviorScanner {
    package enum MethodBehavior: Equatable {
        case acrossAllReaders     // 调用过 acrossAllReaders / acrossAllContexts
        case inProcessOnly        // 只调过 usingInProcessOnly / inProcessContext (不接 acrossAllReaders)
        case sentinel             // 既没跨 reader 也没 InProcess single-reader
    }

    package let suiteRoot: URL

    package init(suiteRoot: URL) { self.suiteRoot = suiteRoot }

    /// 扫描 suiteRoot 下所有 *Tests.swift,对每个 `@Test` 函数判定行为,
    /// 聚合到 `(testedTypeName, methodName)` key。
    package func scan() throws -> [MethodKey: MethodBehavior]
}
```

实现:
- 用 `SwiftSyntax.Parser` 解析每个 `*Tests.swift`
- 找带 `@Test` attribute 的 `FunctionDeclSyntax`
- 函数 body 里 `IdentifierExprSyntax` / `MemberAccessExprSyntax` 含 `acrossAllReaders` 或 `acrossAllContexts` → `.acrossAllReaders`
- 否则若含 `usingInProcessOnly` 或 `inProcessContext` → `.inProcessOnly`
- 否则 → `.sentinel`
- key 用 `<EnclosingClass>.testedTypeName` (从 class body 里找 `static let testedTypeName = "..."`) + 函数名

边界处理:
- 函数名直接取 `FunctionDeclSyntax.name.text`
- 若 suite 类不 conform `FixtureSuite` (例如 `MachOSwiftSectionCoverageInvariantTests` 自身) → 跳过
- testedTypeName 从 `static let testedTypeName = "Foo"` 字面量提取;无法提取 → 抛错

#### 2.3 `MachOSwiftSectionCoverageInvariantTests` 新断言

```swift
@Test func everyPublicMemberHasATest() throws {
    let scanner = PublicMemberScanner(sourceRoot: modelsRoot)
    let allowlistAllKeys = CoverageAllowlistEntries.keys
    let sentinelKeys = CoverageAllowlistEntries.sentinelKeys

    let expected = try scanner.scan(applyingAllowlist: [])
    let registered: Set<MethodKey> = Set(...)  // 同现状
    let behaviorMap = try SuiteBehaviorScanner(suiteRoot: ...).scan()

    // ① + ② 同现状,允许 allowlist 兜底
    let missing = expected.subtracting(registered).subtracting(allowlistAllKeys)
    let extra = registered.subtracting(expected).subtracting(allowlistAllKeys)
    #expect(missing.isEmpty, ...)
    #expect(extra.isEmpty, ...)

    // ③ liar sentinel
    let liarSentinels = sentinelKeys.filter { key in
        if let behavior = behaviorMap[key], behavior != .sentinel {
            return true
        }
        return false
    }
    #expect(
        liarSentinels.isEmpty,
        """
        These methods are tagged sentinel in CoverageAllowlistEntries but the
        Suite actually calls acrossAllReaders / inProcessContext — the sentinel
        tag is stale. Either remove the sentinel entry or revert the test to
        registration-only.
        \(liarSentinels.sorted().map { "  \($0)" }.joined(separator: "\n"))
        """
    )

    // ④ unmarked sentinel
    let actualSentinelKeys = Set(behaviorMap.compactMap { $0.value == .sentinel ? $0.key : nil })
    let unmarked = actualSentinelKeys.subtracting(sentinelKeys).subtracting(allowlistAllKeys)
    #expect(
        unmarked.isEmpty,
        """
        These methods are sentinel-only (the Suite never calls
        acrossAllReaders / inProcessContext) but are not declared in
        CoverageAllowlistEntries. Either implement a real test, or add a
        SentinelReason entry explaining why this is the right level of coverage.
        \(unmarked.sorted().map { "  \($0)" }.joined(separator: "\n"))
        """
    )
}
```

#### 2.4 88 个现有 sentinel 的初步归类

预归类清单见 Appendix A。A2 commit 实施时按实际 suite 内容精调。

### 3. B — SymbolTestsCore Fixture 扩展

#### 3.1 新增 fixture 文件

按"一种 metadata 形态 → 一个 .swift 文件"组织,drop 进 `Tests/Projects/SymbolTests/SymbolTestsCore/`。`PBXFileSystemSynchronizedRootGroup` 自动 pick up。

| 文件 | 引入的 metadata 形态 | 消化的 sentinel suites |
|---|---|---|
| `DefaultOverrideTable.swift` | class with dynamic replacement → method default-override table | `MethodDefaultOverrideDescriptor`, `MethodDefaultOverrideTableHeader`, `OverrideTableHeader` |
| `ResilientClasses.swift` | resilient class + resilient superclass reference | `ResilientSuperclass`, `StoredClassMetadataBounds` |
| `ObjCClassWrappers.swift` | Swift class inheriting `NSObject` → ObjC class wrapper metadata | `ObjCClassWrapperMetadata`, `ClassMetadataObjCInterop`, `AnyClassMetadataObjCInterop`, `RelativeObjCProtocolPrefix` |
| `ObjCResilientStubs.swift` | Swift class inheriting resilient ObjC class | `ObjCResilientClassStubInfo` |
| `CanonicalSpecializedMetadata.swift` | generic types with `@_specialize(exported: true)` → canonical specialized metadata | `CanonicalSpecializedMetadataAccessorsListEntry`, `CanonicalSpecializedMetadatasCachingOnceToken`, `CanonicalSpecializedMetadatasListCount`, `CanonicalSpecializedMetadatasListEntry` |
| `ForeignTypes.swift` | foreign class import + foreign reference type | `ForeignClassMetadata`, `ForeignReferenceTypeMetadata`, `ForeignMetadataInitialization` |
| `GenericValueParameters.swift` | type with `<let N: Int>` value generic parameters | `GenericValueDescriptor`, `GenericValueHeader` |

预估 15 个 sentinel suites 通过 B 转真测。剩余少数 fixture 技术上做不出的 (例如 `@_specialize(exported:)` 在 framework 不触发 canonical-specialized-metadata 的情况下) 保留 `runtimeOnly` 标签或新增 `unbuildable` case 处理,在 spec 末尾登记。

#### 3.2 工程流程 (每个 fixture 文件一个 commit)

1. 写新 `.swift` 文件到 `Tests/Projects/SymbolTests/SymbolTestsCore/`
2. 在 `SymbolTestsCore` Xcode 项目中 build:
   ```bash
   xcodebuild -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj \
              -scheme SymbolTestsCore -configuration Release build
   ```
3. 在 `Sources/MachOFixtureSupport/Baseline/BaselineFixturePicker.swift` 加新 picker 函数:
   ```swift
   package static func class_DefaultOverrideTest(
       in machO: some MachOSwiftSectionRepresentableWithCache
   ) throws -> ClassDescriptor { ... }
   ```
4. 在对应 `Sources/MachOFixtureSupport/Baseline/Generators/<Sub>/<Type>BaselineGenerator.swift` 把 `static let registeredTestMethodNames` 改完整字面量列表,发出 `Entry` ABI literal
5. 重写对应 suite: 删 `registrationOnly` 函数,加入真 `acrossAllReaders` 测试函数
6. `swift package --allow-writing-to-package-directory regen-baselines --suite <Name>`
7. `swift test --filter <Name>Tests` 验证
8. 同步移除 `CoverageAllowlistEntries` 中对应 `needsFixtureExtension` 项

#### 3.3 风险与缓解

| 风险 | 缓解 |
|---|---|
| 某 metadata 形态需要内部 `@_` attribute 才能触发,编译/链接失败 | 优先尝试不带 `@_` 的最小路径;不行则保留 `runtimeOnly`/新建 `unbuildable` case 在 spec 登记 |
| `xcodebuild` rebuild 后 `DerivedData/` 二进制变动触发整片 baseline drift | B0 阶段先做一次 baseline 全量对齐 commit;后续每个 B-commit 标 `[fixture rebuild]` 并 git diff 全量 review |
| ObjC interop fixture 需要 ObjC runtime 加载 | 现有 `dlopen(SymbolTestsCore)` 走 dyld,ObjC runtime 自动加载,无需配置 |
| `@_specialize(exported:)` 在 framework 里能否触发 canonical-specialized 不确定 | spec 标记此 fixture 为"实验",B5 commit 失败则保留 `needsFixtureExtension` |
| `<let N: Int>` value-generic 在 Swift 6.2 仍是 experimental | `@available(...)` 守卫;旧 OS 跳过 |

### 4. C — InProcess Runtime Metadata 真测

#### 4.1 来源分流

| 来源 | 适用 suite | 取得方式 |
|---|---|---|
| **stdlib metatype** | `MetatypeMetadata` | `unsafeBitCast(Int.self.self, to: UnsafeRawPointer.self)` |
| **stdlib tuple** | `TupleTypeMetadata`, `TupleTypeMetadataElement` | `unsafeBitCast((Int, String).self, to: UnsafeRawPointer.self)` |
| **stdlib function** | `FunctionTypeMetadata`, `FunctionTypeFlags` | `unsafeBitCast(((Int) -> Void).self, to: UnsafeRawPointer.self)` |
| **stdlib existential** | `ExistentialTypeMetadata`, `ExistentialMetatypeMetadata`, `ExistentialTypeFlags`, `ExtendedExistentialTypeMetadata`, `ExtendedExistentialTypeShape`, `ExtendedExistentialTypeShapeFlags`, `NonUniqueExtendedExistentialTypeShape` | `Any.self`, `(any Equatable).self`, `(any Equatable & Sendable).self` |
| **stdlib opaque** | `OpaqueMetadata` | `unsafeBitCast(Builtin.Int8.self, to: UnsafeRawPointer.self)` (或 `Int8.self` fallback) |
| **stdlib fixed array** | `FixedArrayTypeMetadata` | `InlineArray<3, Int>.self` (macOS 26+ guard) |
| **fixture nominal** | `StructMetadata`, `EnumMetadata`, `ClassMetadata`, `DispatchClassMetadata`, `ValueMetadata`, `AnyClassMetadata`, `AnyClassMetadataObjCInterop`, `FinalClassMetadataProtocol`, `ClassMetadataBounds`, `StoredClassMetadataBounds` | `unsafeBitCast(SymbolTestsCore.<Type>.self, to: UnsafeRawPointer.self)` |
| **header offset on existing metadata** | `HeapMetadataHeader`, `HeapMetadataHeaderPrefix`, `TypeMetadataHeader`, `TypeMetadataHeaderBase`, `TypeMetadataLayoutPrefix`, `MetadataBounds`, `MetadataBoundsProtocol`, `Metadata`, `FullMetadata`, `MetadataWrapper`, `MetadataProtocol`, `MetadataResponse`, `MetadataRequest`, `MetadataAccessorFunction`, `SingletonMetadataPointer` | 复用上面 metadata pointer,从 layout prefix 偏移读取 |
| **保留 sentinel** (无法稳定构造) | `GenericBoxHeapMetadata`, `HeapLocalVariableMetadata` | 保留 `runtimeOnly` 标签,spec 解释 |

总计预计 ~30 个 sentinel suites 通过 C 转出真测。

#### 4.2 新增 helper — `InProcessMetadataPicker`

文件: `Sources/MachOFixtureSupport/InProcess/InProcessMetadataPicker.swift`

```swift
package enum InProcessMetadataPicker {
    /// stdlib `Int` 的 metatype metadata,用于 MetatypeMetadataTests。
    package static let stdlibIntMetatype: UnsafeRawPointer = {
        unsafeBitCast(Int.self.self, to: UnsafeRawPointer.self)
    }()

    /// `(Int, String)` 的 tuple metadata。
    package static let stdlibTupleIntString: UnsafeRawPointer = {
        unsafeBitCast((Int, String).self, to: UnsafeRawPointer.self)
    }()

    /// `((Int) -> Void)` 的 function metadata。
    package static let stdlibFunctionIntToVoid: UnsafeRawPointer = {
        unsafeBitCast(((Int) -> Void).self, to: UnsafeRawPointer.self)
    }()

    /// `Any` 的 existential metadata。
    package static let stdlibAnyExistential: UnsafeRawPointer = {
        unsafeBitCast(Any.self, to: UnsafeRawPointer.self)
    }()

    /// `(any Equatable)` 的 extended existential metadata (with shape)。
    package static let stdlibAnyEquatable: UnsafeRawPointer = {
        unsafeBitCast((any Equatable).self, to: UnsafeRawPointer.self)
    }()

    // ... 其余按 4.1 表逐一暴露
}
```

#### 4.3 一致性策略调整

`MachOSwiftSectionFixtureTests` 加 helper:

```swift
package func usingInProcessOnly<T: Equatable>(
    _ work: (InProcessContext) throws -> T,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> T {
    try work(inProcessContext)
}
```

Suite 模板:
```swift
@Test func kind() async throws {
    let metadataPointer = InProcessMetadataPicker.stdlibIntMetatype
    let result = try usingInProcessOnly { context in
        try MetatypeMetadata(at: metadataPointer, in: context).kind
    }
    #expect(result == MetatypeMetadataBaseline.stdlibIntMetatype.kind)
}
```

`SuiteBehaviorScanner` 把 `usingInProcessOnly` / `inProcessContext` 也认作非 sentinel。

#### 4.4 边界处理

- `Builtin.Int8` 不在普通 module 可见 → 用 `Int8.self` fallback
- `InlineArray<3, Int>` 需 macOS 26+ → `@available` 守卫,旧 OS 跳过该 suite 的 InProcess 测,baseline 标 OS-conditional
- `swift_allocBox` 等 runtime API 不在 public surface → `GenericBoxHeapMetadata` / `HeapLocalVariableMetadata` 保留 `runtimeOnly` 不消化

### 5. Migration / Commit / 验证

#### 5.1 Commit 顺序

```
Phase A — 机制就位 (3 commits, ~1 day)
├── A0. docs: add fixture-coverage tightening design (本 spec 文档)
├── A1. feat(MachOFixtureSupport): introduce SuiteBehaviorScanner + AllowlistKind/SentinelReason schema
│       新增 scanner、扩 schema、CoverageInvariant 暂保留旧断言不启用新约束
├── A2. test: seed sentinel reasons for existing 88 suites (277 methods)
│       一次性 categorize,allowlist 277 个 entries 填好。用 `sentinelGroup(typeName:members:reason:)`
│       helper 缩短 (88 个 suite × 平均 3-5 行 = ~300-400 行 schema 数据)
└── A3. test: enable liarSentinel + unmarkedSentinel invariant assertions
        点亮新断言 ③ ④,跑通

Phase C — runtime-only 转 InProcess (5-6 commits, ~2 days)
├── C1. feat(MachOFixtureSupport): add InProcessMetadataPicker + usingInProcessOnly helper + BaselineGenerator InProcess Entry 支持
├── C2. test: convert MetatypeMetadata/TupleType*/FunctionType* (~5 suites)
├── C3. test: convert ExistentialType* family (~7 suites)
├── C4. test: convert *Metadata/*Header/*Bounds fixture-nominal (~10 suites)
├── C5. test: convert Metadata/MetadataResponse/SingletonMetadataPointer layer (~6 suites)
└── (C6 视情况合入,每 commit 同步删 allowlist 中对应 runtimeOnly 项)

Phase B — 扩 SymbolTestsCore 消化 needsFixtureExtension (7-8 commits, ~2 days)
├── B0. test(fixture): rebuild SymbolTestsCore baseline DerivedData snapshot
│       (若 phase A/C 期间 DerivedData 漂移,先 baseline 对齐)
├── B1. test(fixture): add DefaultOverrideTable.swift, convert 3 suites
├── B2. test(fixture): add ResilientClasses.swift, convert 2 suites
├── B3. test(fixture): add ObjCClassWrappers.swift, convert 4 suites
├── B4. test(fixture): add ObjCResilientStubs.swift, convert 1 suite
├── B5. test(fixture): add CanonicalSpecializedMetadata.swift, convert 4 suites
├── B6. test(fixture): add ForeignTypes.swift, convert 3 suites
└── B7. test(fixture): add GenericValueParameters.swift, convert 2 suites

Phase D — cleanup (1 commit)
└── D1. docs: update CLAUDE.md fixture-coverage section + PR description
```

总 16-18 个 commit,~5 工作日。

#### 5.2 每个 commit 的硬性 gate

```bash
swift build                                                       # 编译
swift test --filter MachOSwiftSectionTests                        # 该 phase fixture suites 全绿
swift test --filter MachOSwiftSectionCoverageInvariantTests       # invariant 绿
```

A3 之后 invariant 是 PR tripwire。任何 commit 后若 invariant 红 → 该 commit 必须 fix-forward,**不允许 skip**。

#### 5.3 Push 节奏

不每个 commit push,按 phase 边界 push,共 6 次:
1. A 完成 (3 commits)
2. C 中段 (~3 commits)
3. C 完成 (~3 commits)
4. B 中段 (~4 commits)
5. B 完成 (~3 commits)
6. D (1 commit)

#### 5.4 风险登记

| 风险 | 触发位置 | 处置 |
|---|---|---|
| `SuiteBehaviorScanner` 误判 mixed-suite 中某 method 行为 | A1-A3 | scanner 遇分歧时 fallback per-suite 粒度;allowlist 项相应放宽,spec 备注精度损失 |
| B 期间 `xcodebuild` 重建 SymbolTestsCore 触发整片 baseline ABI drift | B 任意 commit | B0 先做 baseline 全量对齐;漂移大时该 commit 标 `[fixture rebuild]`,git diff 全量人工 review |
| 某 fixture metadata 形态在当前 Swift 6.2 不触发预期 ABI | B5/B6/B7 | 该项保留 `needsFixtureExtension`,spec doc 更新解释,不 block 其他 phase |
| `InlineArray<3, Int>` 在 macOS 12 不可用 | C-fixedarray | `@available(macOS 26.0, *)` 守卫;旧 OS 跳过该 suite InProcess 测,baseline 标 OS-conditional |
| `swift_allocBox` 等 runtime API 无 public surface | C5 | `GenericBoxHeapMetadata` / `HeapLocalVariableMetadata` 保留 `runtimeOnly`,spec 标"未消化" |

## Appendix A: 88 个现有 sentinel 的初步归类

基于命名规则与 Swift runtime 知识的预归类。A2 commit 实施时按实际 suite 内容精调。

### A.1 `runtimeOnly` (~50 项)

由 Swift runtime 现场分配、不在 fixture binary 序列化的类型:

- **Metadata core**: `Metadata`, `FullMetadata`, `MetadataProtocol`, `MetadataWrapper`, `MetadataRequest`, `MetadataResponse`, `MetadataAccessorFunction`, `SingletonMetadataPointer`
- **Metadata bounds**: `MetadataBounds`, `MetadataBoundsProtocol`, `ClassMetadataBounds`, `ClassMetadataBoundsProtocol`, `StoredClassMetadataBounds`
- **Metadata headers**: `HeapMetadataHeader`, `HeapMetadataHeaderPrefix`, `TypeMetadataHeader`, `TypeMetadataHeaderBase`, `TypeMetadataLayoutPrefix`
- **Type-flavored metadata**: `StructMetadata`, `StructMetadataProtocol`, `EnumMetadata`, `EnumMetadataProtocol`, `ClassMetadata`, `ClassMetadataObjCInterop`, `AnyClassMetadata`, `AnyClassMetadataObjCInterop`, `AnyClassMetadataProtocol`, `AnyClassMetadataObjCInteropProtocol`, `FinalClassMetadataProtocol`, `DispatchClassMetadata`, `ValueMetadata`, `ValueMetadataProtocol`
- **Existentials**: `ExistentialTypeMetadata`, `ExistentialMetatypeMetadata`, `ExtendedExistentialTypeMetadata`, `ExtendedExistentialTypeShape`, `NonUniqueExtendedExistentialTypeShape`
- **Tuple/function/metatype/opaque/fixed-array**: `TupleTypeMetadata`, `TupleTypeMetadataElement`, `FunctionTypeMetadata`, `MetatypeMetadata`, `OpaqueMetadata`, `FixedArrayTypeMetadata`
- **Heap (保留 sentinel)**: `GenericBoxHeapMetadata`, `HeapLocalVariableMetadata`
- **Generic*runtime layer***: `GenericEnvironment`, `GenericWitnessTable`
- **Value witness table**: `ValueWitnessTable`, `TypeLayout`
- **Foreign metadata initialization**: `ForeignMetadataInitialization`

### A.2 `needsFixtureExtension` (~15 项)

应能扩 fixture 后转真测:

- `MethodDefaultOverrideDescriptor`, `MethodDefaultOverrideTableHeader`, `OverrideTableHeader`
- `ResilientSuperclass`
- `ObjCClassWrapperMetadata`, `RelativeObjCProtocolPrefix`, `ObjCProtocolPrefix`
- `ObjCResilientClassStubInfo`
- `CanonicalSpecializedMetadataAccessorsListEntry`, `CanonicalSpecializedMetadatasCachingOnceToken`, `CanonicalSpecializedMetadatasListCount`, `CanonicalSpecializedMetadatasListEntry`
- `ForeignClassMetadata`, `ForeignReferenceTypeMetadata`
- `GenericValueDescriptor`, `GenericValueHeader`

### A.3 `pureDataUtility` (~25 项)

纯 raw-value enum / 标记 protocol / pure-data utility,合理永久 sentinel:

- **Flags**: `ContextDescriptorFlags`, `ContextDescriptorKindSpecificFlags`, `AnonymousContextDescriptorFlags`, `TypeContextDescriptorFlags`, `ClassFlags`, `ExtraClassDescriptorFlags`, `MethodDescriptorFlags`, `ProtocolDescriptorFlags`, `ProtocolContextDescriptorFlags`, `ProtocolRequirementFlags`, `GenericContextDescriptorFlags`, `GenericRequirementFlags`, `GenericEnvironmentFlags`, `FieldRecordFlags`, `ProtocolConformanceFlags`, `ExistentialTypeFlags`, `ExtendedExistentialTypeShapeFlags`, `FunctionTypeFlags`, `ValueWitnessFlags`
- **Kinds**: `ContextDescriptorKind`, `MethodDescriptorKind`, `ProtocolRequirementKind`
- **Other utilities**: `EnumFunctions`, `InvertibleProtocolSet`, `InvertibleProtocolsRequirementCount`, `TypeReference`

### A.4 备注

- 上面三类列举的是**type 名 (即 sentinel suite 对应的 testedTypeName)**,不是 method 数。Allowlist schema 是 per-method,实际 entry 数 = 各 type 对应 suite 内的 method 总和 (约 277)。
- 三类 type 总和 ≈ 88,具体每类精确数量 A2 commit 实施时按 suite 内容精调。
- A.1 中 `GenericBoxHeapMetadata`, `HeapLocalVariableMetadata` 不进 C 真测,保持 `runtimeOnly` 永久 sentinel。
- A.3 数量预估 25 type,实际可能略多 (某些 *Header / *Bounds 在 method 粒度看更接近 pure-data,需 A2 实施时确认)。
- A2 commit 会用 `sentinelGroup` helper 把同一 type 下所有 method 共享同一 `SentinelReason`,避免重复:
  ```swift
  CoverageAllowlistEntries.sentinelGroup(
      typeName: "MethodDefaultOverrideDescriptor",
      members: ["originalMethodDescriptor", "replacementMethodDescriptor",
                "implementationSymbols", "layout", "offset"],
      reason: .needsFixtureExtension(detail: "no class with default-override table in SymbolTestsCore — covered after B1")
  )
  ```

## Appendix B: SuiteBehaviorScanner 实现要点

```swift
import SwiftSyntax
import SwiftParser

private final class SuiteBehaviorVisitor: SyntaxVisitor {
    private(set) var collected: [(testedTypeName: String, methodName: String, behavior: SuiteBehaviorScanner.MethodBehavior)] = []
    private var currentTestedTypeName: String?
    private var currentClassName: String?

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        currentClassName = node.name.text
        currentTestedTypeName = extractTestedTypeName(from: node)
        return .visitChildren
    }
    override func visitPost(_ node: ClassDeclSyntax) {
        currentClassName = nil
        currentTestedTypeName = nil
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard hasTestAttribute(node.attributes),
              let testedTypeName = currentTestedTypeName,
              let body = node.body else {
            return .skipChildren
        }
        let behavior = inferBehavior(from: body)
        collected.append((testedTypeName, node.name.text, behavior))
        return .skipChildren
    }

    private func extractTestedTypeName(from classDecl: ClassDeclSyntax) -> String? {
        // 找 `static let testedTypeName = "Foo"` 字面量
        for member in classDecl.memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self),
               varDecl.modifiers.contains(where: { $0.name.text == "static" }) {
                for binding in varDecl.bindings {
                    if let ident = binding.pattern.as(IdentifierPatternSyntax.self),
                       ident.identifier.text == "testedTypeName",
                       let initializer = binding.initializer,
                       let stringLit = initializer.value.as(StringLiteralExprSyntax.self) {
                        return stringLit.segments.compactMap {
                            $0.as(StringSegmentSyntax.self)?.content.text
                        }.joined()
                    }
                }
            }
        }
        return nil
    }

    private func hasTestAttribute(_ attributes: AttributeListSyntax) -> Bool {
        for attr in attributes {
            if let attribute = attr.as(AttributeSyntax.self),
               attribute.attributeName.trimmedDescription == "Test" {
                return true
            }
        }
        return false
    }

    private func inferBehavior(from body: CodeBlockSyntax) -> SuiteBehaviorScanner.MethodBehavior {
        let bodyText = body.description
        if bodyText.contains("acrossAllReaders") || bodyText.contains("acrossAllContexts") {
            return .acrossAllReaders
        }
        if bodyText.contains("usingInProcessOnly") || bodyText.contains("inProcessContext") {
            return .inProcessOnly
        }
        return .sentinel
    }
}
```

字符串 `contains` 检测足够 — `acrossAllReaders` 等 identifier 在 fixture suite 里没有 false-positive 同名变量约束 (本项目命名规则保证)。如果未来出现冲突,升级到 `MemberAccessExprSyntax` / `IdentifierExprSyntax` 走 SwiftSyntax 树。

## Appendix C: 决策记录

本 spec 在 brainstorming 阶段做出的关键决策:

| 决策 | 选项 | 选择 | 理由 |
|---|---|---|---|
| 总体路径 | α 一次大 PR / β 分 PR / γ 先 A 增量 / δ 当前 PR 分批 | δ | PR 内闭环,review 一次看完 |
| Sentinel 检测机制 | 1 全自动 / 2 半显式 marker / 3 per-method baseline 拆分 | 1 | 现有 88 suite 不动源码;88 suite 全 sentinel 无 mixed,per-suite 粒度够用;行为事实最难撒谎 |
| Reason 存储 | a baseline 内 / b 独立文件 / c 扩 CoverageAllowlistEntries | c | 已存在的 reason 集中点,baseline 保持 100% auto-generated |
| Reason 类型 | free-text / typed enum | typed enum | B/C 各自能 iter `.needsFixtureExtension` / `.runtimeOnly` 子集 |
| 88 sentinel seed 策略 | i 全手工 / ii 启发式 + needsCategorization placeholder / iii 启发式 + 立刻补 | iii | spec 落地即完整分类,无 needsCategorization 残留 |
| B 范围 | a 全部消化 / b top-N / c 不做 | a | δ 路径目标是 PR 内闭环 |
| C 实现方式 | 1 stdlib / 2 fixture helper / 3 按 metadata 性质分流 | 3 | 不同 metadata 类型来源不同,分流是技术上更对 |
| C 一致性策略 | 仍要求 acrossAllReaders / 仅 InProcess single-reader | 仅 InProcess | runtime-allocated 在其他 reader 拿不到数据,强求 cross-reader 是另一种 sentinel |
