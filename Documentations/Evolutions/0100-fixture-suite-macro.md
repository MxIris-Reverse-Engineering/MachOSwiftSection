# 0100 - `@FixtureSuite` 宏：夹具测试套件开头的固定写法由宏生成

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-11-20
- **最后更新**: 2026-11-20
- **所属愿景**: 无
- **关联提案**: [0104-shared-macho-testing-support](0104-shared-macho-testing-support.md)（同一次「减少测试样板」的讨论里拆出来；那份统一跨包的测试支持，这份只管本包的 Swift 夹具覆盖率体系，两份互不依赖）
- **实现分支 / PR**: `feature/fixture-suite-macro`，从 `next` 切出，快进合入 `next`
- **配套文档**: 无单独文档；用法写在 `AGENTS.md`「添加夹具测试」与 [FixtureTestingAndContinuousIntegration.md](../Internal/FixtureTestingAndContinuousIntegration.md)「套件头由 `@FixtureSuite` 生成」一节；演进账本第 145 节
- **网页版**: 同目录同名的 `.html`

## 摘要

新增 attached 宏 `@FixtureSuite`，挂在夹具测试套件类上，生成 `static let testedTypeName`、`static var registeredTestMethodNames`，并补上对 `FixtureSuite` 协议的遵循。被测类型名默认取类名去掉 `Tests` 后缀，baseline 默认取「类名去掉 `Tests` 加 `Baseline`」；少数例外用参数写明。`SuiteBehaviorScanner` 改为也认宏的写法。`MachOSwiftSectionTests` 里按固定写法写的 170 个夹具套件改用宏，每处省 3 行（`CoroFunctionPointerTests` 没有 baseline，保持手写）。宏的实现放在新的宏 target `SwiftSectionTestingMacros`，声明放在 `SwiftSectionTestingSupport`，只有测试链接它。

## 动机

- **同样的 5 行写了 170 遍。** `MachOSwiftSectionTests` 里每个夹具套件的开头都是：

  ```swift
  @Suite
  final class StructDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
      static let testedTypeName = "StructDescriptor"
      static var registeredTestMethodNames: Set<String> {
          StructDescriptorBaseline.registeredTestMethodNames
      }
  ```

  （`Tests/MachOSwiftSectionTests/Fixtures/Type/Struct/StructDescriptorTests.swift:16-21`）171 个夹具套件遵循 `FixtureSuite`；按完整写法匹配的 170 个里，165 个的被测类型名就是类名去掉 `Tests`，只有 5 个例外。
- **手抄容易抄错。** `testedTypeName` 决定覆盖率不变式按哪个类型检查成员（`FixtureSuite.swift` 的文档注释），抄错一个字母，这个套件就静默地对不上源码里的类型。
- **起因**：用户问能否给测试加便捷的宏减少样板。调研后，跨读取器写法 `acrossAllReaders` 不适合做宏（改用普通函数重载，归 `0104-shared-macho-testing-support`），套件开头这一处适合，另写本提案。

## 前期调研

- **协议**：`package protocol FixtureSuite`（`Sources/TestSupport/SwiftSectionFixtureSupport/Coverage/FixtureSuite.swift`），`@MainActor`，两个要求：`static var testedTypeName: String`、`static var registeredTestMethodNames: Set<String>`。
- **谁读这两个值**：
  - 覆盖率不变式测试 `Tests/MachOSwiftSectionTests/Fixtures/MachOSwiftSectionCoverageInvariantTests.swift:53-55` 在运行时读 `suite.testedTypeName` 与 `registeredTestMethodNames`——宏生成的成员照样读得到。
  - `SuiteBehaviorScanner`（`Coverage/SuiteBehaviorScanner.swift:118-133`）**按源码语法**读 `testedTypeName`：在类的成员里找 `static` 且初始值是字符串字面量的 `testedTypeName`。宏生成的成员不在源码里，所以扫描器要改，认 `@FixtureSuite` 的参数或类名。它的样例源码在 `Tests/SwiftSectionTestingSupportTests/Coverage/Fixtures/SuiteSampleSource.swift.txt`。
  - `BaselineGenerator.writeAllFixtureSuitesIndex`（`Baseline/BaselineGenerator.swift:693-710`）用手维护的类名清单生成 `__Baseline__/AllFixtureSuites.swift`，不读 `testedTypeName`，不受影响。
- **5 个例外**（类名 → `testedTypeName`、baseline）：
  - `OpaqueTypeFixtureTests` → `"OpaqueType"`、`OpaqueTypeBaseline`（类名加了 `Fixture` 避开同 target 里的快照套件 `OpaqueTypeTests`，见 `BaselineGenerator.swift:701-704`）
  - `EnumFunctionsTests` → `"EnumTagCounts"`、`EnumFunctionsBaseline`
  - `TupleTypeMetadataElementTests` → `"Element"`、`TupleTypeMetadataElementBaseline`
  - `GenericContextTests` → `"TargetGenericContext"`、`GenericContextBaseline`
  - `GenericRequirementContentTests` → `"InvertedProtocols"`、`GenericRequirementContentBaseline`

  baseline 名除 `OpaqueTypeFixtureTests` 外都是「类名去掉 `Tests` 加 `Baseline`」。
- **现有的宏**：宏 target `SwiftSectionMacros`（`Package.swift:1007-1016`，`Sources/Support/SwiftSectionMacros`，`@Layout` 等），供 `Utilities`、`MachOSwiftSection` 两个生产 target 用；本包没有宏的展开测试。swift-syntax 依赖是 `602.0.0..<605.0.0`（`Package.swift:93`）。
- **同名先例**：Observation 里协议 `Observable` 与宏 `@Observable` 同名，`@Observable` 解析到宏；本提案的宏与协议同名同理。
- **宏的硬规则**（`swift-macro-patterns` skill）：`conformances:` 只列一定会添加的协议——本宏总是添加 `FixtureSuite`，满足；生成代码里的类型写全名（`Swift.Set<Swift.String>`）。

## 提议方案

1. **宏声明**放在 `SwiftSectionTestingSupport`（夹具套件都 import 它），`package` 可见：member 角色生成两个静态成员，extension 角色添加 `FixtureSuite`。
2. **宏实现**放在新的宏 target `SwiftSectionTestingMacros`（`Sources/TestSupport/SwiftSectionTestingMacros`），只给 `SwiftSectionTestingSupport` 依赖，生产的 `SwiftSectionMacros` 插件不带测试代码。
3. **默认值**：`testedTypeName` 取类名去掉 `Tests` 后缀；baseline 取同一个词干加 `Baseline`。类名不以 `Tests` 结尾时报错并给 Fix-It（写明 `testedTypeName:`）。
4. **参数**：`@FixtureSuite(testedTypeName: "EnumTagCounts")`、`@FixtureSuite(testedTypeName: "OpaqueType", baseline: OpaqueTypeBaseline.self)`。两个参数都只收字面量（字符串字面量、`类型.self`），给变量就报错，不静默退回默认值。
5. **扫描器**：`SuiteBehaviorScanner` 先看类上有没有 `@FixtureSuite`：有就取 `testedTypeName:` 参数的字面量，没有参数就取类名去掉 `Tests`；没有宏的类照旧读静态成员。
6. **迁移**：按完整写法写的 170 个夹具套件改用宏——类声明里去掉 `FixtureSuite` 遵循和两个静态成员，挂上 `@FixtureSuite`；5 个例外带参数。`CoroFunctionPointerTests` 没有 baseline、注册名单是字面量，保持手写。
7. 本包 `AGENTS.md`「添加夹具测试」那几条（`:186` 一带）改成用宏的写法。

### 非目标

- 给 `MachOFileTests` 等其他基类的子类（`override class var fileName` 之类）做宏：属于基类配置，宏省不了几行。
- 把 `acrossAllReaders` 做成宏：归 `0104-shared-macho-testing-support`，用普通函数重载。
- 自动维护 `BaselineGenerator` 里手写的套件清单（`AllFixtureSuites` 的来源）。
- `@Suite` 与 `ExclusiveImageAccess` 等 trait 的组合：已经只有一行。

## 改动地图

| 文件 / 类型 | 动作 | 改什么 | 为什么 | 步骤 |
|---|---|---|---|---|
| `Package.swift` | 修改 | 新增宏 target `SwiftSectionTestingMacros`（SwiftSyntax、SwiftSyntaxMacros、SwiftCompilerPlugin、SwiftSyntaxBuilder）与测试 target `SwiftSectionTestingMacrosTests`（加 `SwiftSyntaxMacrosGenericTestSupport`）；`SwiftSectionTestingSupport` 依赖新宏 target；Tuist 适配块留在文件末尾 | 宏的实现与测试 | 1 |
| `Sources/TestSupport/SwiftSectionTestingMacros/FixtureSuiteMacro.swift`、`TestingMacroPlugin.swift` | 新增 | `FixtureSuiteMacro`（`MemberMacro`、`ExtensionMacro`）：推出类名词干、读两个字面量参数、生成成员与遵循、诊断与 Fix-It | 宏实现 | 1 |
| `Sources/TestSupport/SwiftSectionTestingSupport/FixtureSuiteMacro.swift` | 新增 | `package macro FixtureSuite(testedTypeName:baseline:)` 声明 | 宏声明 | 1 |
| `Tests/SwiftSectionTestingMacrosTests/FixtureSuiteMacroTests.swift` | 新增 | 展开测试：默认、只给 `testedTypeName`、两个都给、类名不以 `Tests` 结尾、参数不是字面量 | 宏的行为 | 1 |
| `Sources/TestSupport/SwiftSectionFixtureSupport/Coverage/SuiteBehaviorScanner.swift` | 修改 | 认 `@FixtureSuite`：取参数或类名词干 | 扫描器按源码读被测类型名 | 2 |
| `Tests/SwiftSectionTestingSupportTests/Coverage/SuiteBehaviorScannerTests.swift`、`Fixtures/SuiteSampleSource.swift.txt` | 修改 | 加宏写法的样例与测试 | 扫描器的行为 | 2 |
| `Tests/MachOSwiftSectionTests/Fixtures/**/*Tests.swift`（170 个夹具套件） | 修改 | 改用 `@FixtureSuite` | 去掉样板 | 3 |
| `AGENTS.md`、`Documentations/Internal/FixtureTestingAndContinuousIntegration.md` | 修改 | 添加夹具测试的写法 | 文档同步 | 4 |

## 架构图

```text
Package (MachOSwiftSection)
  SwiftSectionMacros (macro)                 @Layout, ...            (unchanged, production)
+ SwiftSectionTestingMacros (macro)          FixtureSuiteMacro: member + extension
  SwiftSectionFixtureSupport
    Coverage/FixtureSuite (protocol)                                  (unchanged)
~   Coverage/SuiteBehaviorScanner            reads @FixtureSuite too
~ SwiftSectionTestingSupport  -> + SwiftSectionTestingMacros
+   macro FixtureSuite(testedTypeName:baseline:)
~ MachOSwiftSectionTests                     170 suites: @FixtureSuite
+ SwiftSectionTestingMacrosTests             expansion tests
```

展开前后：

```text
@Suite @FixtureSuite
final class StructDescriptorTests: MachOSwiftSectionFixtureTests, @unchecked Sendable { ... }

 ↓ member
    static let testedTypeName: Swift.String = "StructDescriptor"
    static var registeredTestMethodNames: Swift.Set<Swift.String> { StructDescriptorBaseline.registeredTestMethodNames }
 ↓ extension
extension StructDescriptorTests: SwiftSectionFixtureSupport.FixtureSuite {}
```

## 详细设计

```swift
// SwiftSectionTestingSupport
@attached(member, names: named(testedTypeName), named(registeredTestMethodNames))
@attached(extension, conformances: FixtureSuite)
package macro FixtureSuite(testedTypeName: String? = nil, baseline: Any.Type? = nil) =
    #externalMacro(module: "SwiftSectionTestingMacros", type: "FixtureSuiteMacro")
```

- **词干**：类名去掉末尾的 `Tests`。类名不以 `Tests` 结尾且没给 `testedTypeName:` → 诊断「类名不以 Tests 结尾，写明 testedTypeName:」并给 Fix-It。
- **baseline**：参数写 `X.self` 时取 `X`，否则取「词干 + `Baseline`」。
- **只收字面量**：`testedTypeName:` 不是字符串字面量（含插值）、`baseline:` 不是 `类型.self` → 诊断落在参数上。
- **挂错地方**：挂在非 class 声明上 → 诊断。
- **全名**：生成代码写 `Swift.String`、`Swift.Set<Swift.String>`、`SwiftSectionFixtureSupport.FixtureSuite`。
- **隔离**：套件类继承 `@MainActor` 的 `MachOSwiftSectionFixtureTests`，协议也是 `@MainActor`，生成成员不另加隔离标注。
- **扫描器**：`SuiteBehaviorVisitor.visit(_ node: ClassDeclSyntax)` 先查 `node.attributes` 里名字最后一段是 `FixtureSuite` 的属性；有 `testedTypeName:` 字符串字面量就用它，否则用类名词干；没有该属性才走现有的静态成员读取。

## 替代方案考量

- **把宏实现放进现有的 `SwiftSectionMacros`**：少一个 target，但生产代码链接的插件会带上测试用的宏。否决。
- **只用基类或协议扩展给默认值**：协议扩展能给 `testedTypeName` 一个按类型名推的默认实现（运行时 `String(describing: Self.self)` 去掉 `Tests`），但 `registeredTestMethodNames` 要引用 baseline 类型，运行时拿不到，且扫描器按源码读不到运行时默认值。否决。
- **做成宏后不改扫描器、保留手写的 `testedTypeName`**：省一行都不到。否决。

## 影响

### 源码兼容性（source compatibility）

只改测试支持与测试，对外 product 不变。

### ABI 兼容性（条件项）

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

无：新宏 target 与测试支持都不是 product。`0104-shared-macho-testing-support` 落地时，`MachOSwiftSectionFixtureTests` 变成共享基类的子类，`@FixtureSuite` 不受影响；两份提案改到同一批测试文件（这份改类声明，那份改 `acrossAllReaders` 调用），先落地的一份之后，另一份在合并时解冲突。

### 文档与示例

`AGENTS.md` 的「添加夹具测试」步骤与 `FixtureTestingAndContinuousIntegration.md`。

## API 演进与废弃策略

- `package` 级别的宏，只给本包测试用，没有对外承诺。
- 不保留旧写法的兼容：迁移在同一批完成，扫描器两种写法都认，所以中途也不会坏。

## 落地步骤

1. **宏与展开测试**（完成）—— `Package.swift`、`SwiftSectionTestingMacros`、宏声明、`FixtureSuiteMacroTests`
   - 行为：`defaultsTakeTheTestedTypeAndBaselineFromTheClassName`
   - 行为：`anExplicitTestedTypeNameKeepsTheBaselineFromTheClassName`
   - 行为：`anExplicitBaselineIsUsedAsWritten`
   - 行为：`aClassNameWithoutTestsAsksForTheTestedTypeName`（诊断加 Fix-It）
   - 行为：`aNonLiteralArgumentIsRejected`
   - 行为：`theMacroAddsTheFixtureSuiteConformance`
2. **扫描器认宏**（完成）—— `SuiteBehaviorScanner`、样例源码与测试
   - 行为：`scannerReadsTheTestedTypeNameFromTheMacroArgument`
   - 行为：`scannerTakesTheClassNameStemWhenTheMacroHasNoArgument`
   - 行为：`scannerStillReadsAStaticTestedTypeName`
3. **迁移 170 个套件**（完成）—— `Tests/MachOSwiftSectionTests/Fixtures/**`
   - 行为：覆盖率不变式测试照常通过，迁移前后 `allFixtureSuites` 各套件的 `testedTypeName` 与 `registeredTestMethodNames` 逐个相等
   - 行为：`SuiteBehaviorScanner` 认出的「被测类型 → 测试方法 → 行为」与迁移前逐条相同
4. **文档**（完成）—— `AGENTS.md`、`FixtureTestingAndContinuousIntegration.md`
   - 收尾判断：实现说明不必单写，`AGENTS.md` 的步骤与宏的文档注释够用；没有新术语。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-11-20 | Created as Draft | 用户问能否给测试代码加便捷的宏减少样板。只读调研统计了两个包测试里的重复写法：值得做成宏的是 176 个夹具套件开头的固定 5 行；`acrossAllReaders` 改用普通函数重载（归 `0104-shared-macho-testing-support`）。用户选择把这个宏另写一份本包提案。 |
| 2026-11-20 | 宏实现放新 target `SwiftSectionTestingMacros` | 生产代码链接的 `SwiftSectionMacros` 插件不带测试用的宏。 |
| 2026-11-20 | 宏与协议同名 `FixtureSuite` | 照 Observation 的 `Observable` 先例，`@FixtureSuite` 读起来就是「这是一个夹具套件」。 |
| 2026-11-20 | 状态 → Accepted | 用户批准，开始实现。 |
| 2026-11-20 | 第 1、2 步完成 | 宏的 6 个展开测试与扫描器的 9 个测试在 MacBook 上通过（Ultra 负载过高，按规则分流）。 |
| 2026-11-20 | 套件数更正：171 个，迁 170 个 | 提案里的 176 是 grep 把扫描器样例文本里的几个类也数进去了。`CoroFunctionPointerTests` 自己编夹具、没有 baseline，注册名单是字面量，套不上宏，保持手写。 |
| 2026-11-20 | 实现完成，待用户看过后收尾 | 在 MacBook 上按 CI 的 ad-hoc 签名编出 `SymbolTestsCore`，跑 `swift test --skip IntegrationTests`：`MachOSwiftSectionCoverageInvariantTests`、宏与扫描器的测试全部通过。另有 150 组失败——夹具套件的 `offset()`、`layout()` 等与 baseline 写死的偏移不符，以及 `SymbolicDemanglerTests` 找不到 iOS 26.5 模拟器运行时——在同一台机器、同一份夹具上切到 `next` 跑同一批，失败逐条相同，是 MacBook 的环境（夹具与 baseline 的产物不一致、没装该运行时），不是本次引入的。Ultra 负载过高（1 分钟负载约 90–107），没在 Ultra 上跑。文档：`AGENTS.md` 与 `FixtureTestingAndContinuousIntegration.md` 已写明用法；不另写实现说明；没有新术语。 |
| 2026-11-20 | 与 Swift 6 迁移一起落地 | 用户看过分支后决定与 [0101-swift6-mode-and-upcoming-features](0101-swift6-mode-and-upcoming-features.md) 同批落地：本分支先快进合入 `next`，Swift 6 那一支合在它之上；合并后的构建与全量测试在两者合并的结果上统一跑，过了再一起推送。 |
| 2026-11-20 | 状态 → Implemented，编号 0100 | 落地时取号：远端共享分支上最大编号是 0099。收尾判断：不另写实现说明或使用指南，`AGENTS.md` 的步骤、`FixtureTestingAndContinuousIntegration.md` 的一节与宏的文档注释已经够用；没有新术语，术语表不动。演进账本记第 145 节。没有后续项。 |
