# MachOSwiftSection Fixture-Based Test Coverage Design

**日期:** 2026-05-03
**状态:** 待实施
**分支:** `feature/machoswift-section-fixture-tests`(从 `feature/reading-context-api` 拉,因新测试要覆盖 ReadingContext API)

## 问题

`Sources/MachOSwiftSection/Models/` 下有 **287 个 public func**、**781 个 public 成员**、分布于 **24 个子目录、约 60 个文件**。这些方法构成了把 Mach-O 二进制中 Swift 元数据节(`__swift5_types`、`__swift5_proto` 等)解析成 Swift 模型的全部入口。

现状:

- **`Tests/MachOSwiftSectionTests/`** 只有 9 个测试文件,大多 ad-hoc 风格,基于系统 framework(SwiftUI、dyld shared cache)而非可控 fixture,且没有"哪些方法被覆盖、哪些没被覆盖"的客观标准。
- 最近刚加完的 ReadingContext API(每个 method 多了一个 `<Context: ReadingContext>(in: Context)` 重载)更需要回归保护——目前没有一个测试断言"三家 reader 在同一 fixture 上返回相同结果"。
- `SwiftDumpTests` 已经建立了 fixture-based 范式(`SymbolTestsCoreDumpSnapshotTests` + `SymbolTestsCoreCoverageInvariantTests`),但守的是更高层 SwiftDump 输出,无法替代对 MachOSwiftSection reader API 直接的 ABI 级断言。

本设计建立一套 fixture-based 测试体系,达成:

- 每一个 `Sources/MachOSwiftSection/Models/**` 下的 public func/var/init **被至少一个 `@Test` 覆盖**;
- 每个被覆盖方法做 **跨 reader 一致性断言**(MachOFile/MachOImage/InProcess + 三家对应 ReadingContext);
- 每个被覆盖方法做 **完整 ABI 数值层硬编码断言**(offset、size、flags、count、name 等);
- 新增 public method 不写测试 → `swift test` 红;
- baseline 数据通过 generator 一次性生成、人工 review 后冻结进 git。

## 目标

1. 为 `Sources/MachOSwiftSection/Models/` 下所有 public 入口建立 fixture-based `@Test`,镜像源码目录结构。
2. 引入 `MachOSwiftSectionFixtureTests` 基类,持有同一份 `SymbolTestsCore.framework` 的三种视图(`MachOFile`、`MachOImage`、`InProcessContext`)。
3. 每个 `@Test` 同时执行**跨 reader 一致性断言**(三家 reader + 三家 ReadingContext)与**ABI baseline 字面量断言**。
4. 提供 `baseline-generator` executable,从 fixture 自动生成 baseline 期望值,产出可读 Swift 代码,commit 进 git。
5. 提供 `MachOSwiftSectionCoverageInvariantTests` 守护测试,基于源码静态扫描确保覆盖完整。
6. 失败信息要 actionable,能直接告诉作者要新增/修改哪个 `@Test` 或 baseline。

## 非目标

- **扩展 fixture 内容**:`SymbolTestsCore.framework`(54 个 .swift 文件)已经覆盖大多数 Swift 语法元素,本期不增加新 fixture 文件。如某 model type 在 fixture 内找不到合适样本,先入 `CoverageAllowlist` 标 `needs fixture extension`,留 future work。
- **测试 MachOSwiftSection 之外的模块**:SwiftDump/SwiftInspection/SwiftInterface/TypeIndexing 都已有(或不在范围)各自的测试套件,本期仅聚焦 `MachOSwiftSection`。
- **性能 benchmark**:仅做正确性,不做性能基线。
- **fixture 自动构建**:沿用 `xcodebuild -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj -scheme SymbolTestsCore` 手动构建,DerivedData/ 已经 commit 在仓库内。
- **重写或合并现有测试**:`LayoutTests`、`AssociatedTypeTests`、`MetadataAccessorTests` 等保留,作为补充,不冲突。

## 设计

### 1. 整体架构

设计由四个支柱组成:

```
fixture.framework (SymbolTestsCore)
        │
        ├──[disk]──── MachOFile ──┐
        ├──[dlopen]── MachOImage ─┼──→ 3 个 ReadingContext (file/image/inprocess) ──→ Tests
        └──[ptr]───── InProcess ──┘
                                       │
                                       ├──→ ① cross-reader equality #expect (Suite 内自动)
                                       └──→ ② ABI baseline literal #expect (引用 baseline)
                                                       │
                                                       └── BaselineGenerator 自动生成
                                                                  ↑
                                       MachOSwiftSectionCoverageInvariantTests 守护
                                       ──→ 静态扫描 Sources/.../Models/ 找到 expected 名单
                                       ──→ 反射 Suite registeredTestMethodNames 找到 registered 名单
                                       ──→ missing/extra 必须为空
```

| 支柱 | 位置 | 职责 |
|---|---|---|
| Fixture 加载层 | `Sources/MachOTestingSupport/MachOSwiftSectionFixtureTests.swift` | 同时持有 fixture 的 MachOFile/MachOImage,以及三家 reader 与三家 ReadingContext |
| Suite 层 | `Tests/MachOSwiftSectionTests/Fixtures/`(镜像 Models/ 24 子目录) | 50 个左右 Suite 文件,每个 `@Test` 对应一个 public method,做"跨 reader 一致性 + baseline 断言" |
| Baseline Generator 层 | `Sources/MachOTestingSupport/Baseline/` + `Sources/baseline-generator/`(executable target) | 一次性运行,从 fixture 生成 `__Baseline__/<Suite>Baseline.swift` |
| Coverage 守护层 | `Sources/MachOTestingSupport/Coverage/` + `Tests/MachOSwiftSectionTests/Fixtures/MachOSwiftSectionCoverageInvariantTests.swift` | 静态扫描源码 + 反射 Suite,缺漏直接红 |

与现有测试的关系:

- `LayoutTests.swift`(纯 Layout offset 计算)→ 保留,继续管 Layout。
- `AssociatedTypeTests.swift` / `MetadataAccessorTests.swift` 等 ad-hoc 风格 → 保留,作为示例与补充。
- `SwiftDumpTests/Snapshots/SymbolTestsCoreDumpSnapshotTests` → 不冲突,守的是 SwiftDump 输出,本套件守 MachOSwiftSection reader API。

### 2. Test Infrastructure

#### 2.1 `MachOSwiftSectionFixtureTests` 基类

新文件 `Sources/MachOTestingSupport/MachOSwiftSectionFixtureTests.swift`:

```swift
@MainActor
package class MachOSwiftSectionFixtureTests: Sendable {
    package let machOFile: MachOFile
    package let machOImage: MachOImage

    package let fileContext: MachOContext<MachOFile>
    package let imageContext: MachOContext<MachOImage>
    package let inProcessContext: InProcessContext

    package class var fixtureFileName: MachOFileName  { .SymbolTestsCore }
    package class var fixtureImageName: MachOImageName { .SymbolTestsCore }

    package init() async throws {
        // 1. 磁盘加载(同 MachOFileTests)
        let file = try loadFromFile(named: Self.fixtureFileName)
        switch file {
        case .fat(let fatFile):
            self.machOFile = try required(
                fatFile.machOFiles().first(where: { $0.header.cpuType == .arm64 })
                    ?? fatFile.machOFiles().first
            )
        case .machO(let machO):
            self.machOFile = machO
        @unknown default:
            fatalError()
        }

        // 2. dlopen 加载到当前进程
        try Self.ensureFixtureLoaded()
        self.machOImage = try #require(MachOImage(named: Self.fixtureImageName))

        // 3. 三家 context
        self.fileContext = MachOContext(machO: machOFile)
        self.imageContext = MachOContext(machO: machOImage)
        self.inProcessContext = InProcessContext()
    }

    private static let dlopenOnce: Void = {
        // MachOImageName 的 raw value 是相对路径 "../../Tests/...",dlopen 需绝对路径。
        // 用 #filePath 作为 anchor 解析为绝对路径(同 SwiftDumpTests 已有的解析逻辑)。
        let path = resolveFixturePath(MachOImageName.SymbolTestsCore.rawValue)
        _ = dlopen(path, RTLD_LAZY)
    }()

    private static func ensureFixtureLoaded() throws {
        _ = dlopenOnce
        guard MachOImage(named: .SymbolTestsCore) != nil else {
            throw FixtureLoadError.imageNotFoundAfterDlopen(
                path: MachOImageName.SymbolTestsCore.rawValue,
                dlerror: String(cString: dlerror() ?? "")
            )
        }
    }
}

package enum FixtureLoadError: Error {
    case imageNotFoundAfterDlopen(path: String, dlerror: String)
}
```

#### 2.2 `MachOImageName.SymbolTestsCore` 枚举条目

需要新增,镜像 `MachOFileName.SymbolTestsCore` 的相对路径:

```swift
extension MachOImageName {
    case SymbolTestsCore = "../../Tests/Projects/SymbolTests/DerivedData/SymbolTests/Build/Products/Release/SymbolTestsCore.framework/Versions/A/SymbolTestsCore"
    case SymbolTests = "../../Tests/Projects/SymbolTests/DerivedData/SymbolTests/Build/Products/Release/SymbolTests.framework/Versions/A/SymbolTests"
}
```

#### 2.3 `acrossAllReaders` helper

为减少 `@Test` 内重复,提供:

```swift
extension MachOSwiftSectionFixtureTests {
    /// 在 (machOFile, machOImage, inProcess) 三家上分别求值,断言相等,返回唯一值。
    package func acrossAllReaders<T: Equatable>(
        file: () throws -> T,
        image: () throws -> T,
        inProcess: () throws -> T
    ) throws -> T { ... }

    /// 在 (fileContext, imageContext, inProcessContext) 三家 ReadingContext 上分别求值,断言相等。
    package func acrossAllContexts<T: Equatable>(
        file: () throws -> T,
        image: () throws -> T,
        inProcess: () throws -> T
    ) throws -> T { ... }
}
```

dlopen 失败采取**抛错**而非 fatalError,让 `@Test` 显示 actionable 信息;`dlerror` 输出到错误。

### 3. Suite 结构

#### 3.1 文件组织

镜像 `Sources/MachOSwiftSection/Models/`:

```
Tests/MachOSwiftSectionTests/Fixtures/
├── Anonymous/
│   ├── AnonymousContextDescriptorTests.swift
│   └── AnonymousContextTests.swift
├── AssociatedType/...
├── BuiltinType/...
├── ContextDescriptor/...
├── ExistentialType/...
├── Extension/...
├── FieldDescriptor/...
├── FieldRecord/...
├── ForeignType/...
├── Generic/...
├── Metadata/...
├── Module/...
├── OpaqueType/...
├── Protocol/...
├── ProtocolConformance/...
├── TupleType/...
└── Type/
    ├── TypeContextDescriptorTests.swift
    ├── TypeContextWrapperTests.swift
    ├── TypeReferenceTests.swift
    ├── TypeContextDescriptorProtocolTests.swift
    ├── ValueMetadataProtocolTests.swift
    ├── Class/
    │   ├── ClassTests.swift
    │   ├── ClassDescriptorTests.swift
    │   ├── AnyClassMetadataProtocolTests.swift
    │   ├── ...
    │   └── Method/...
    ├── Enum/
    │   ├── EnumTests.swift
    │   ├── EnumMetadataProtocolTests.swift
    │   └── MultiPayloadEnumDescriptorTests.swift
    └── Struct/
        ├── StructTests.swift
        └── StructMetadataProtocolTests.swift
```

约 50 个 Suite 文件。

#### 3.2 Suite 模板

```swift
@Suite
final class StructDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "StructDescriptor"
    static let registeredTestMethodNames: Set<String> = [
        "name",
        "fields",
        "genericContext",
        "numberOfFields",
        "fieldOffsetVectorOffset",
        // ... generator 同步生成
    ]

    private func pickedStruct(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> StructDescriptor {
        try #require(
            machO.swift.typeContextDescriptors.lazy
                .compactMap(\.struct)
                .first(where: { try $0.name(in: machO) == "Structs.StructTest" })
        )
    }

    @Test func name() async throws {
        let fileSubject = try pickedStruct(in: machOFile)
        let imageSubject = try pickedStruct(in: machOImage)

        let fromFile      = try fileSubject.name(in: machOFile)
        let fromImage     = try imageSubject.name(in: machOImage)
        let fromInProcess = try imageSubject.asPointerWrapper(in: machOImage).name()
        let fromFileCtx   = try fileSubject.name(in: fileContext)
        let fromImageCtx  = try imageSubject.name(in: imageContext)

        // ① cross-reader 一致性
        #expect(fromFile == fromImage)
        #expect(fromFile == fromInProcess)
        #expect(fromFile == fromFileCtx)
        #expect(fromFile == fromImageCtx)

        // ② ABI baseline literal
        #expect(fromFile == StructDescriptorBaseline.structTest.name)
    }

    // ... 每个 public func/var/init 一个 @Test
}
```

约定:

- `@Suite final class XxxTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable`,文件名 = `<被测类型>Tests.swift`。
- 每个 `@Test func` 名 = 被测 member 名。
- 每个 `@Test` 同时做 ① cross-reader equality(包括 fileContext/imageContext/inProcessContext)和 ② baseline literal。
- 跨 reader 比对 wrapper 类型时,投影到"语义可比较"字段(string、numeric、array of string),避免 wrapper 内部不可比较的 offset/pointer。
- **InProcess 重载缺失**:并非每个 method 都有 `()` 形式的 InProcess 重载(部分 model 类型未提供 `asPointerWrapper`,或 InProcess 形式与 MachO 形式不对称)。Suite 模板对没有 InProcess 重载的 method 跳过 `fromInProcess` 一致性断言;对没有 ReadingContext 重载的 method(极少数)同理跳过 context 断言。每个 `@Test` 实际验证哪些 reader 由该 method 在源码中存在的重载决定,plan 阶段会逐 method 列出。

#### 3.3 fixture 主测目标策略

每个 Suite 选 **1 主 + 2~3 个反差变体**(由 `BaselineFixturePicker` 统一规划):

- struct:Structs.StructTest(主) + GenericFieldLayout.GenericStructNonRequirement(generic)。
- class:Classes.ClassTest(主) + DiamondInheritance.DiamondLeaf(继承链) + Classes.ObjCDerivedTest(ObjC interop)。
- enum:Enums.EnumTest(主) + (single payload) + (multi-payload)。
- protocol:Protocols.ProtocolTest(主) + AssociatedTypeWitnessPatterns 选 1 关联类型 protocol。
- 等等。

#### 3.4 Baseline 引用形态

每个 Suite 配 `Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/<Suite>Baseline.swift`:

```swift
// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: swift run baseline-generator --suite StructDescriptor
// Source fixture: SymbolTestsCore.framework
// Toolchain: Swift 6.2 (swiftlang-6.2.x)
// Generated: 2026-05-03

enum StructDescriptorBaseline {
    static let registeredTestMethodNames: Set<String> = [
        "name", "fields", "genericContext",
        "numberOfFields", "fieldOffsetVectorOffset",
    ]

    struct Entry {
        let name: String
        let numberOfFields: Int
        let fieldNames: [String]
        let fieldOffsets: [Int]
        let isGeneric: Bool
        let flagsRawValue: UInt32
    }

    static let structTest = Entry(
        name: "SymbolTestsCore.Structs.StructTest",
        numberOfFields: 1,
        fieldNames: ["body"],
        fieldOffsets: [0x10],
        isGeneric: false,
        flagsRawValue: 0x40000051
    )

    static let genericStructNonRequirement = Entry(
        name: "SymbolTestsCore.GenericFieldLayout.GenericStructNonRequirement",
        numberOfFields: 3,
        fieldNames: ["field1", "field2", "field3"],
        fieldOffsets: [0x10, 0x18, 0x28],
        isGeneric: true,
        flagsRawValue: 0x40000091
    )
}
```

### 4. Baseline Generator

#### 4.1 形态

独立 executable target `baseline-generator`,通过 `swift run baseline-generator [--suite <name>] [--output <dir>]` 触发。
不混入 `swift test`(不属于"测试")。

#### 4.2 模块组织

```
Sources/MachOTestingSupport/Baseline/
├── BaselineGenerator.swift      // 主入口:遍历 fixture、调度子 generator
├── BaselineEmitter.swift        // 数值 → Swift 字面量(offset/flags hex,count 十进制)
├── BaselineFixturePicker.swift  // 在 fixture 中找"主测目标 + 关键变体"
└── Generators/
    ├── StructDescriptorBaselineGenerator.swift
    ├── ClassDescriptorBaselineGenerator.swift
    └── ... (每个被测 type 一个 generator)

Sources/baseline-generator/
└── main.swift                    // ArgumentParser + 调 BaselineGenerator
```

#### 4.3 生成流程

```
1. 加载 fixture(同 MachOSwiftSectionFixtureTests:磁盘 + dlopen)
2. 对每个被测 model type
   ├── BaselineFixturePicker 选出 (主测目标 + 关键变体)
   ├── 对每个挑中的 fixture entity,Generator 调用 entity 上每个 public 入口
   │   └── BaselineEmitter 序列化为 Swift 字面量
   └── 输出 <Suite>Baseline.swift 到 Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/
3. 同时输出每个 Suite 的 registeredTestMethodNames(嵌入对应 `<Suite>Baseline.swift`)+ 一个汇总文件 `Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/AllFixtureSuites.swift`,内含 `allFixtureSuites` 数组(供 Coverage 守护测试使用)
4. 文件头写元数据:fixture commit hash + Swift toolchain version + 生成日期
```

#### 4.4 Emitter 数值进制约定

- **offset / size** 用 hex(`0x10`),便于和 `otool`/Hopper 对照。
- **flags rawValue** 用 hex(`0x40000051`),与 Swift 源码内 flag 定义一致。
- **count / index** 用十进制。
- **name / mangled name** 用字符串字面量,转义 backslash/quote。
- **enum 值**(如 `ContextDescriptorKind`)输出全限定名:`.class`。

#### 4.5 重生成流程(operator-facing)

fixture 重编后(toolchain 升级 / 源文件改动):

```
1. xcodebuild -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj \
              -scheme SymbolTestsCore -configuration Release build
2. swift run baseline-generator --output Tests/MachOSwiftSectionTests/Fixtures/__Baseline__
3. git diff Tests/MachOSwiftSectionTests/Fixtures/__Baseline__
   ── 漂移符合预期:commit
   ── 漂移不符合预期:定位 reader bug
4. swift test --filter MachOSwiftSectionTests
```

支持 `--suite <Name>` 局部重生,降低 review 范围。

#### 4.6 Generator 自身正确性保证

- generator 只用 **MachOFile** 路径生成 baseline(单一路径,易审)。
- 测试 Suite 通过三家 reader 一致性独立验证 MachOImage/InProcess,**不依赖** baseline。
- 关键 emitter(数值进制、字符串转义)有专门的 emitter unit test。

### 5. Coverage Invariant

#### 5.1 数据源

- **expected**:SwiftSyntax 静态扫描 `Sources/MachOSwiftSection/Models/**/*.swift`,提取每个 `public func`/`public var`/`public init`。
- **registered**:反射所有 `FixtureSuite`-conforming Suite 类型的 `static var registeredTestMethodNames` + `testedTypeName`。

#### 5.2 MethodKey

```swift
struct MethodKey: Hashable, Comparable {
    let typeName: String        // e.g. "StructDescriptor"
    let memberName: String      // e.g. "fields"
}
```

**重载合并**:三家重载(`(in: MachO)` / `(in: Context)` / `()` InProcess)共享一个 `memberName`,在单个 `@Test` 内验证一致性。Coverage 守护按 `(typeName, memberName)` 比对,不区分重载。

#### 5.3 Scanner 实现

`Sources/MachOTestingSupport/Coverage/PublicMemberScanner.swift`:

- 用 SwiftSyntax 解析 `Sources/MachOSwiftSection/Models/**/*.swift`。
- 跳过 `@_spi(Internals)` 标注的方法。
- 跳过 `internal`/`private`/`fileprivate`(必须 `public` 或 `open`)。
- 跳过 `Layout` 内字段(已被 `LayoutTests` 覆盖)。
- 跳过 `@MemberwiseInit` 宏生成的 `init(layout:offset:)`(识别 attribute 或签名)。
- 接受 `Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlist.swift` 配置,允许 (a) 已知不可测方法的明确豁免,(b) 暂未支持的 fixture 场景。每个 allowlist 项必须有 reason 注释。

#### 5.4 Coverage Test

```swift
@Suite
struct MachOSwiftSectionCoverageInvariantTests {
    @Test func everyPublicMemberHasATest() async throws {
        let scanner = PublicMemberScanner(sourceRoot: ... /* Sources/MachOSwiftSection/Models */)
        let expected = try scanner.scan(applyingAllowlist: CoverageAllowlist.entries)

        let registered = Set(
            allFixtureSuites.flatMap { suite -> [MethodKey] in
                suite.registeredTestMethodNames.map { name in
                    MethodKey(typeName: suite.testedTypeName, memberName: name)
                }
            }
        )

        let missing = expected.subtracting(registered)
        let extra = registered.subtracting(expected)

        #expect(missing.isEmpty, "Missing tests for: \(missing.sorted())")
        #expect(extra.isEmpty, "Tests registered for non-existent members: \(extra.sorted())")
    }
}
```

`allFixtureSuites` 由 generator 同步生成:

```swift
let allFixtureSuites: [any FixtureSuite.Type] = [
    StructDescriptorTests.self,
    ClassDescriptorTests.self,
    ProtocolDescriptorTests.self,
    // ...
]
```

#### 5.5 失败信息

```
Missing tests for these public members of MachOSwiftSection/Models:
  StructDescriptor.classGenericContext
  ClassDescriptor.objCRuntimeName
  ProtocolDescriptor.numAssociatedTypes

Tip: add these names to the registeredTestMethodNames of the corresponding Suite,
add a @Test per name, and run `swift run baseline-generator --suite <Name>`
to populate baseline expected values.
```

#### 5.6 Coverage / Generator 协作矩阵

| 触发场景 | 谁动了什么 | Coverage 守护行为 |
|---|---|---|
| 给 Models/ 加 public method | scanner expected 多一项 | 失败,提示新增 @Test |
| 给 Suite 加 @Test + registeredTestMethodNames | registered 多一项 | 通过(前提是 expected 也有) |
| 删 public method 但忘删 @Test | scanner expected 少一项 | 失败 with "extra" |
| 改 method 名 | expected/registered 都变 | 失败 with both,作者跟着改 |
| 重新生成 baseline | generator 自动同步 registered | 通过 |

### 6. 测试范围与 Allowlist

#### 6.1 入测范围

- `Sources/MachOSwiftSection/Models/**/*.swift` 中所有 `public`/`open` 标注的 `func` / `var` / `init`(open 主要出现在 class 上)。
- 三家重载(`(in: MachO)` / `(in: Context)` / `()` InProcess)在单个 `@Test` 内一并验证;实际存在的重载由源码决定,缺失的跳过(见 §3.2)。

#### 6.2 显式 Exclusions(`CoverageAllowlist`)

每项必须带 reason:

1. `@MemberwiseInit` 宏生成的 `init(layout:offset:)` —— 自动产物,无业务逻辑。
2. `Layout` 类型的 `static func offset(of:)` —— 已在 `LayoutTests` 覆盖。
3. MachO-only 调试 helper(如 `ResilientWitness.implementationAddress(in: MachO) -> String`)—— 已在源码 doc comment 标注非数据读取。
4. `@_spi(Internals)` 标注的 public —— SPI 不属于稳定 API。
5. `Capture/` 等高度专用 wrapper(实施阶段 case-by-case 决定),fixture 不触发的暂入 allowlist with reason `needs fixture extension`。

### 7. Risks & Mitigations

| 风险 | 触发 | 缓解 |
|---|---|---|
| Fixture 路径在 CI 上找不到 | DerivedData 相对路径 / CI working dir 不同 | (a) 沿用 SwiftDumpTests 已跑通的相对路径;(b) `init` 失败给 actionable 信息(指出 `xcodebuild` 命令) |
| dlopen fixture framework 失败 | framework 未编译 / iOS Simulator 路径不匹配 / sandbox | 抛 `FixtureLoadError.imageNotFoundAfterDlopen(path:dlerror:)`,所有子类的 `@Test` init 阶段就 fail |
| Fixture 重编 → ABI 漂移 | toolchain 升级 / 源文件改动 / Xcode 升级 | (a) `git diff __Baseline__` 一目了然;(b) baseline 头记录 toolchain version + 日期;(c) `--suite <name>` 局部重生 |
| Generator 自身 bug 把错值固化进 baseline | generator 调用 reader 错或 emitter 转义错 | (a) generator 只用 MachOFile 单一路径,易审;(b) 三家 reader 一致性独立验证 MachOImage/InProcess;(c) emitter unit test |
| 跨 reader 一致性"假阳性通过":三家都错同一个 bug | 共享底层 helper 出 bug | baseline 数值断言独立兜底 |
| `@MemberwiseInit` 签名变化 → scanner 误判 | 宏更新 | scanner 基于 `@MemberwiseInit` attribute 是否存在,而非签名形状;allowlist 兜底 |
| Coverage 守护数据漂移成本 | 改方法名同时改两处 | 失败信息明确 missing/extra;正常工作流是 `改源码 → 跑 generator → commit`,registered 自动同步 |
| InProcess 路径在 fixture 上不存在的 method | 部分 model 类型未提供 `asPointerWrapper` 桥接,InProcess 与 MachO 重载不完全对称 | Suite 模板对没有 InProcess 重载的 method 跳过 `fromInProcess` 一致性断言;每个 `@Test` 实际验证的 reader 集合由 method 在源码中存在的重载决定(详见 §3.2) |
| 测试规模膨胀拖慢 swift test | 几百 `@Test`,每个 init 加载 fixture | (a) `dlopen` 用 `static let` 只跑一次;(b) MachOFile/MachOImage 单 init 成本不高(SwiftDumpTests 已验证);(c) 必要时 future work 引入 fixture cache |

## Validation

实施完成的验收 checklist:

- [ ] `swift test --filter MachOSwiftSectionTests` 全绿。
- [ ] `swift test --filter MachOSwiftSectionCoverageInvariantTests` 绿(missing/extra 均空)。
- [ ] `swift run baseline-generator --suite <任一>` 应该幂等(刚生成完跑不修改任何 baseline 文件)。
- [ ] 在 `Sources/MachOSwiftSection/Models/Type/Struct/StructDescriptor.swift` 临时加空 `public func dummyForCoverageProbe() {}`,coverage test 必须报 missing 含 `StructDescriptor.dummyForCoverageProbe`。回滚后重新绿。
- [ ] 在某个 Suite 临时改一个 baseline 数值断言,运行该 Suite 必须报 #expect 失败,信息能定位到具体 method 名。
- [ ] CI 上无需新增配置即可通过(fixture 已编译并 commit 在 DerivedData/)。

## 实施分批(初步)

详细 plan 由 writing-plans 阶段产出,初步切分参考:

1. **基础设施**:`MachOImageName.SymbolTestsCore` + `MachOSwiftSectionFixtureTests` + `acrossAllReaders` helper + `FixtureLoadError`。
2. **BaselineEmitter**:数值/字符串/数组/Optional/enum 字面量序列化 + emitter unit test。
3. **PublicMemberScanner + CoverageAllowlist 框架**:scanner 实现 + 一个故意制造的 sample 验证 missing/extra 报错。
4. **第一个 Suite(StructDescriptorTests + StructDescriptorBaselineGenerator)** 跑通端到端流程,锁定模板。
5. 后续按 Models/ 子目录批量迁移,每批一个 commit:Anonymous/Module/Extension → ContextDescriptor → Type/Class → Type/Enum → Type/Struct → Type 根 → Protocol/ProtocolConformance → Generic → FieldDescriptor/FieldRecord/AssociatedType → Metadata → ExistentialType/TupleType/OpaqueType/BuiltinType/ForeignType → Capture(若需)。
6. **`MachOSwiftSectionCoverageInvariantTests`** 上线,把所有上面批次串起来守护。
7. **`baseline-generator` executable target** 收尾(整合所有 sub generator + ArgumentParser)。

每批一个 commit 且必须 `swift build` + `swift test --filter MachOSwiftSectionTests` 全绿。
