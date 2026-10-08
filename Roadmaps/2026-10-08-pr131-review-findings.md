# PR #131 review findings（RuntimeViewer Find 配套 + 离线泛型特化，2026-10-08）

`/code-review max` 对 PR #131（`feature/runtime-viewer/find-navigator` → `next`，13 个 commit、90 个文件、+5540/−625）给出 15 条发现。这份记录逐条按四问（能否复现 / 基线有没有 / 值不值得修 / 以前修过没有）裁决，并为每条附上复现测试、修法 diff 和修前修后的示例。

**当前状态：已落地（2026-10-08）。** 用户审完这份记录后说「把发现的问题修一下吧」。有修法的 13 条（第 1–8、10、11、13–15 条，含原本建议「离线模式接入前修」的第 5、11 条）全部修掉，每条连同它的复现测试一个 commit；第 9、12 条登记不修。第 7 条横向排查查出的四处同类写法（落地清单第 6 项）也在这一批修掉，配新测试。登记项见 [ReviewAdjudications.md](../Documentations/Internal/ReviewAdjudications.md) A53–A59，其中包括 review 时被核验驳回的四条候选。提交与本机验证见文末「六、落地记录」。

下面几条是记录写成时（2026-10-08 凌晨，那时只落记录、代码未改）的状态：

- **复现测试**：10 个测试文件，另在共享 fixture `GenericSpecializationFixture` 里加了一个类型，写在 JHs-Mac-Studio-Ultra 的 `.worktrees/MachOSwiftSection-FindNavigator` 里，未提交。在 PR 头 `beae202d` 上 14 个测试全部失败（第 6 条带两组参数，共 15 个用例），失败原因与发现描述一致。
- **修法**：只在沙盒副本里改过、验证过。修后 14 个复现测试和第 13 条的 1 个守护测试全部通过；全量 2354 个测试、447 个套件全部通过（退出码 0，唯一一条 known issue 是 `next` 上本来就有的 `SymbolicManglingIndexTests`）。
- **第 13 条的修法改过一次**：第一版整个替换了旧逻辑，测试全绿，但实测把一个本来能用的形状弄坏了，现在的版本保留旧逻辑作为另一条路径。经过写在第 13 条里。
- **diff 怎么读**：下文每条的 diff 都摘自沙盒与 worktree 的逐文件比较。同一个文件里属于不同条目的改动，拆到了各自的条目下（比如 `ConformanceProvider.swift` 分在第 2、5 条），所以个别 hunk 头的行数是整个 hunk 的，与条目下显示的行数不一致。能直接打上的完整补丁是 `…/Logs/ReviewFixes/all-fixes.diff`（20 个文件，+449/−90），已用 `git apply --check` 确认能干净打到 worktree 上。只挑一部分修时，我再按条目切出对应的补丁。
- 对比基线：`git diff next...feature/runtime-viewer/find-navigator`（PR 头 `beae202d`）。已裁决清单（[ReviewAdjudications.md](../Documentations/Internal/ReviewAdjudications.md) A1–A52）里没有覆盖这 15 条的条目。

## 总表

| # | 问题 | 严重度 | 从哪来 | 复现测试 | 建议 |
|---|---|---|---|---|---|
| 1 | opaque 类型的实参按「第几张表」当层号 | 中 | 基线就有（2025-12 起） | `OpaqueTypeArgumentDepthTests` | 合并前修 |
| 2 | 离线检查把 Cocoa 子类判成违反基类约束 | 中 | PR 引入 | `OfflineObjectiveCBaseClassTests` | 合并前修 |
| 3 | 「参数 == 参数」的 same-type 约束补不出参数 | 低到中 | PR 引入 | `TiedParameterInstantiationTests` | 合并前修 |
| 4 | extension 里协议兜底补出的默认实现无处打印 | 低 | PR 引入 | `ProtocolInExtensionDefaultWitnessTests` | 合并前修 |
| 5 | 带条件的协议遵循被当成成立 | 低 | PR 引入 | `OfflineConditionalConformanceTests` | 离线模式接入前修 |
| 6 | 静态展开偏移把 opaque 类型印成占位符 | 低 | PR 引入 | `NestedFieldOffsetOpaqueWitnessTests` | 合并前修 |
| 7 | `specializedChildren` 无锁追加 | 低到中 | 机制旧，PR 扩大 | `ConcurrentSpecializationTests` | 合并前修 |
| 8 | opaque provider 少数一层 | 低到中 | 基线就有（2026-09-18 起） | `OpaqueParameterInMultiDepthExtensionTests` | 合并前修 |
| 9 | 等待索引时的优先级反转 | 低 | PR 引入 | 无（没有可测的行为） | 不修，登记 |
| 10 | 在线特化算类型名失败时静默退回 | 低 | PR 引入 | 由第 3 条的在线测试覆盖 | 合并前修（补日志） |
| 11 | 字段类型与布局注释读的是两套镜像 | 低 | 机制旧，PR 扩大 | `OfflineProjectionDependencyResolutionTests`（只在本机跑） | 离线模式接入前修 |
| 12 | 嵌套偏移缓存会记住「解析失败」 | 低 | PR 有意如此 | 无 | 本库不修，登记；转 RuntimeViewer |
| 13 | thunk 类型构造器认不出泛型 extension 里的泛型类型 | 低 | 基线就有（2026-09-12 起） | `AccessorThunkTypeInGenericExtensionTests` | 合并前修 |
| 14 | 关联类型投影没有提前返回 | 低（性能） | PR 引入 | 无 | 合并前修 |
| 15 | CI 覆盖 | 低 | PR 引入 | 无 | 合并前修 |

第 1、8、13 条与 PR 声称已整类修掉的「泛型参数层号数错」同属一类（PR 修了五处，漏了这三处）。按全库扫描，除这八处外没有别的地方用父链数层号。

## 验证环境

- **修后沙盒**：`/Volumes/DerivedData/Agents.noindex/claude/Sandboxes/FindNavigatorMerge/MachOSwiftSection`，是 `beae202d` 的副本加复现测试加全部修法。它只链了 swift-semantic-string 一个本地依赖（`DefinitionRegion` 只在它的 `next` 上），其余依赖按 `next` 要求的发布版解析（MachOKit 0.54.101、MachOKitExtensions 1.1.2、MachOObjCSection 0.8.109、swift-demangling 0.7.1、FrameworkToolbox 0.15.0）。构建目录 `/Volumes/DerivedData/Agents.noindex/claude/SwiftPM/MachOSwiftSection-FindNavigatorSandbox`。
- **基线沙盒**：`/Volumes/DerivedData/Agents.noindex/claude/Sandboxes/FindNavigatorReviewBaseline/MachOSwiftSection`，PR 头加复现测试，不带修法，用来确认复现测试失败。两个沙盒共用同一份 `Package.resolved`。
- 命令：在沙盒目录里 `USING_LOCAL_DEPENDENCIES=1 queued-build swift test --scratch-path <构建目录> --filter …`；工具链 Swift 6.4（Xcode 27），机器 JHs-Mac-Studio-Ultra。
- 日志（`…` = `/Volumes/DerivedData/Agents.noindex/claude/Sandboxes/FindNavigatorMerge`）：
  - 修前：`…/Logs/ReviewRepro/`（最初的复现与诊断），`…/Logs/ReviewBaselineFinal/repro-suites.log`（最终版测试在 PR 头上的结果）。
  - 修后：`…/Logs/ReviewFixes/`，其中 `full-suite-2.log` 是最终的全量，`examples-after.log` 是 10 个复现套件，`all-fixes.diff` 与 `PerFile/` 是补丁。带 `first-version` 字样的文件和 `full-suite.log` 对应第 13 条第一版修法，留作记录。
  - 第 13 条守护测试的对照：`…/Logs/ReviewBaselineFinal/guard-test-pr-head.log`、`guard-test-first-fix.log`。
  - CLI 示例：`…/Logs/ReviewFixes/Examples/`，同一个输入分别用三个 CLI 跑：
    - `release-0.21.0`：本机装的 0.21.0 release CLI，代表 `next` 的行为（这些代码路径上两者相同）；
    - `pr-head`：基线沙盒编出的 debug CLI；
    - `fixed`：修后沙盒编出的 debug CLI。
  - 实验二进制与源码：`/Volumes/DerivedData/Agents.noindex/claude/Sandboxes/FindNavigatorReviewRepro/experiments/`，与对应复现测试的 fixture 源码相同，只是单独编出来给 CLI 用，所以 opaque 描述符的偏移和测试里的不一样。

## 一、建议合并前修

### 1. opaque 类型的实参按「第几张表」当层号（中，基线就有）

`Sources/Output/SwiftDeclarationRendering/Extensions/Node+OpaqueType.swift:52`（`opaqueTypeGenericArgumentsByDepth`），调用点 `:415`。

opaque 类型（`some View` 这类不透明返回类型）的引用会带上泛型实参：每一层外围声明一张实参表。重写器解析它的底层类型时，把「第几张表」直接当成参数的层号用。

- **能复现吗**：能。
  - 真实二进制：0.21.0 对 `/Applications/Xcodes.app` 的 `interface -a arm64` 在非泛型的 `MainToolbarModifier` 里印出 `SwiftUI.TupleToolbarContent<A>`，共两处。
  - 原因已对照 Swift 6.4 源码确认。编译器 `ASTMangler::appendBoundGenericArgs` 给每一层外围声明都写一张表，不声明参数的层写空表。运行时 `resolveOpaqueType` 则先把所有表拍平，再按描述符自己的层结构重新分组（`_gatherGenericParameters`），从不把位置当层号。
  - 后果：外围只要有一层不声明参数（写了空表），它后面的每张表都被错当成往外一层的。最外的泛型层去空表里找实参，落空、留下裸 `A`；再往里的层拿到的是外一层的实参，印出「真实但错误」的类型（测试里 `makePair` 的 `Extra` 拿到了 `Boxed` 的 `Int`）。
- **基线有没有**：`next` 与 0.21.0 都有，这段代码从 2025-12-16 的 `5e7373fa` 起就按位置取层号。PR 在同一个文件里新加了 `ReadOpaqueType`，已经算出正确的层结构，但这个函数没用上。
- **值不值得修**：值得。普通 SwiftUI app 的 dump、interface 和 RuntimeViewer 都会走到（进程内路径用的是同一张表）。改动小。
- **以前修过吗**：没有。2026-09-11 的 `a85b172d` 修过同一个函数的另一个 bug（`for type in typeListNode` 按 preorder 遍历，取到了 typeList 节点本身）。那次验收只统计「depth ≥ 1 的裸参数残留」（178 → 10），层号 0 上因空表留下的裸 `A` 不在统计范围内。

**复现测试** `Tests/SwiftDeclarationRenderingTests/OpaqueTypeArgumentDepthTests.swift`（2 个测试）。fixture 里 `ProbeNamespace` 是不声明参数的 `enum`，按编译器的写法，`makeWrapper` 的实参表是 `[[], [Element]]`，`Box.makePair` 的是 `[[], [Boxed], [Extra]]`。测试照这个形状手工拼出 opaque 节点（做法同 `OpaqueTypeOrdinalTests`；编译器会把能看透的 opaque 类型直接代换进本模块的反射记录，fixture 造不出仍引用描述符的记录），再交给 `resolveOpaqueType(in:)`：

```swift
public enum ProbeNamespace {
    public static func makeWrapper<Element>(_ element: Element) -> some ProbeShape { ProbeWrapper(wrapped: element) }
    public struct Box<Boxed> {
        public func makePair<Extra>(_ extra: Extra) -> some ProbeShape { ProbePair(first: boxed, second: extra) }
    }
}
// 实参表 [[], [Int]]            → 期望 ProbeWrapper<Swift.Int>
// 实参表 [[], [Int], [String]]  → 期望 ProbePair<Swift.Int, Swift.String>
```

修前：

```
resolved → "OpaqueTypeArgumentDepthFixture.ProbeWrapper<A>"
resolved → "OpaqueTypeArgumentDepthFixture.ProbePair<A, Swift.Int>"     ← Extra 的位置拿到了 Boxed 的实参
```

**修法**：先把各层实参表按顺序拍平，再用 opaque 描述符的 `GenericParameterDepthLayout` 重新分组，这正是运行时的做法。`ReadOpaqueType` 已经算出了这个层结构，多存一份传进去即可。新参数默认 `nil`：不传时仍按位置分组，`OpaqueReferenceSpelling.swift:137`（只拍平使用）和现有单测不受影响。重写器本身、ordinal 的处理不动。

```diff
--- a/Sources/Output/SwiftDeclarationRendering/Extensions/Node+OpaqueType.swift
+++ b/Sources/Output/SwiftDeclarationRendering/Extensions/Node+OpaqueType.swift
@@ -38,7 +38,7 @@
 
 extension Node {
     /// The generic arguments an `opaqueType` node carries, keyed by the depth
-    /// each level substitutes.
+    /// of the parameter each one binds.
     ///
     /// Internal rather than private for the same reason the rewriter below is:
     /// reaching this through `resolveOpaqueType(in:)` needs a binary that
@@ -47,10 +47,26 @@
     /// leaves a parameter unsubstituted (printing `A` / `A1`) or substitutes a
     /// type belonging to a different parameter, and neither raises.
     ///
-    /// The walk mirrors `TypeDecoder.decodeMangledType`'s over the same child,
-    /// including its stop at the first level that is not a `typeList`.
-    static func opaqueTypeGenericArgumentsByDepth(of opaqueTypeNode: Node) -> OrderedDictionary<Int, [Node]> {
+    /// The node spells one argument list per declaration around the opaque
+    /// result, outermost first, and the mangler writes a list for EVERY such
+    /// declaration — an empty one for a level that declares no parameter
+    /// (`ASTMangler::appendBoundGenericArgs`). A list's position is therefore
+    /// not its depth: the runtime flattens the lists and regroups them by the
+    /// descriptor's own depths (`resolveOpaqueType` →
+    /// `_gatherGenericParameters`), and so does this, given the opaque type
+    /// descriptor's `depthLayout`. Keyed by position instead, the argument of
+    /// a generic function in a non-generic type was looked up in the type's
+    /// empty list and never substituted (Xcodes' `MainToolbarModifier.Body`
+    /// printed `SwiftUI.TupleToolbarContent<A>`). Without a layout the lists
+    /// stay keyed by position, which is right whenever no level around the
+    /// result is non-generic.
+    ///
+    /// The walk over the lists mirrors `TypeDecoder.decodeMangledType`'s over
+    /// the same child, including its stop at the first level that is not a
+    /// `typeList`.
+    static func opaqueTypeGenericArgumentsByDepth(of opaqueTypeNode: Node, depthLayout: GenericParameterDepthLayout? = nil) -> OrderedDictionary<Int, [Node]> {
         var argumentsByDepth: OrderedDictionary<Int, [Node]> = [:]
+        var flattenedArguments: [Node] = []
         guard let rootTypeListNode = opaqueTypeNode[safeChild: 2] else { return argumentsByDepth }
         for (depth, typeListNode) in rootTypeListNode.children.enumerated() {
             guard typeListNode.isKind(of: .typeList) else { break }
@@ -63,8 +79,17 @@
             // parameter read whatever preorder left at its index: the element
             // to its left, or a fragment of that element's subtree.
             argumentsByDepth[depth] = Array(typeListNode.children)
+            flattenedArguments.append(contentsOf: typeListNode.children)
         }
-        return argumentsByDepth
+        guard let depthLayout else { return argumentsByDepth }
+        var argumentsByParameterDepth: OrderedDictionary<Int, [Node]> = [:]
+        for (flatIndex, argument) in flattenedArguments.enumerated() {
+            // More arguments than the descriptor has parameters: a list this
+            // walk misread, so the positional reading is the one left.
+            guard let position = depthLayout.position(ofParameterAt: flatIndex) else { return argumentsByDepth }
+            argumentsByParameterDepth[position.depth, default: []].append(argument)
+        }
+        return argumentsByParameterDepth
     }
 
     /// Substitutes an opaque type's generic parameters with the concrete
@@ -412,7 +437,7 @@
             // carries ordinal 0, so this is correctness for a shape
             // those two do not have and a client binary may.
             let ordinal: Int = node[safeChild: 1]?.index?.cast() ?? 0
-            let allTypeList = Node.opaqueTypeGenericArgumentsByDepth(of: node)
+            let allTypeList = Node.opaqueTypeGenericArgumentsByDepth(of: node, depthLayout: readOpaqueType.depthLayout)
             guard let underlyingTypeArgumentMangledName = opaqueType.underlyingTypeArgumentMangledNames[safe: ordinal] else { return nil }
             let underlyingTypeArgumentNode: Node?
             if machO is MachOImage {
@@ -688,14 +713,20 @@
 fileprivate struct ReadOpaqueType {
     let opaqueType: OpaqueType
     let ownerLayout: AccessorThunkOwnerLayout
+    /// How the descriptor's parameters split into depths: what regroups the
+    /// argument lists of a reference to it (`opaqueTypeGenericArgumentsByDepth`).
+    /// `nil` for a descriptor with no generic context.
+    let depthLayout: GenericParameterDepthLayout?
 
     init(_ opaqueType: OpaqueType, in context: some ReadingContext) {
         self.opaqueType = opaqueType
         if let genericContext = opaqueType.genericContext {
             let depthLayout = GenericParameterDepthLayout.make(for: genericContext, ownedBy: .opaqueType(opaqueType.descriptor), in: context)
             self.ownerLayout = AccessorThunkOwnerLayout(genericContext: genericContext, depthLayout: depthLayout)
+            self.depthLayout = depthLayout
         } else {
             self.ownerLayout = AccessorThunkOwnerLayout(genericContext: nil as GenericContext?)
+            self.depthLayout = nil
         }
     }
 }
```

一个容易担心的点：命名声明本身是泛型时，opaque 描述符的「自有」层会把函数参数和 opaque 参数并成一层，看起来像是层数算错了。但实参表只覆盖命名声明的签名，opaque 参数总在最后、不在表里，所以按扁平下标取位置仍然正确：`Box<Boxed>.makePair<Extra>` 的 `[Boxed, Extra]` 落到 `(0,0)`、`(1,0)`。

**修后**：两个测试通过；`OpaqueTypeGenericParameterSubstitutionTests`、`OpaqueTypeOrdinalTests` 等现有 opaque 套件不变。

```
resolved → "OpaqueTypeArgumentDepthFixture.ProbeWrapper<Swift.Int>"
resolved → "OpaqueTypeArgumentDepthFixture.ProbePair<Swift.Int, Swift.String>"
```

真实二进制：`interface -a arm64 /Applications/Xcodes.app/Contents/MacOS/Xcodes`，第 4311 行。0.21.0 与 PR 头相同：

```swift
extension Xcodes.MainToolbarModifier: SwiftUI.ViewModifier {
    typealias Body = SwiftUI.ModifiedContent<SwiftUI._ViewModifier_Content<Xcodes.MainToolbarModifier>, SwiftUI.ToolbarModifier<(), SwiftUI.TupleToolbarContent<A>>>
```

修后（原文是一整行，这里按层级拆开，`…` 是省略的部分）：

```swift
typealias Body = SwiftUI.ModifiedContent<
    SwiftUI._ViewModifier_Content<Xcodes.MainToolbarModifier>,
    SwiftUI.ToolbarModifier<(), SwiftUI.TupleToolbarContent<
        SwiftUI.ToolbarItemGroup<SwiftUI.TupleView<(
            SwiftUI.HelpView<…Xcodes.ProgressButton<SwiftUI.Label<SwiftUI.Text, SwiftUI.Image>>…>,
            SwiftUI.Spacer,
            SwiftUI.ModifiedContent<…SwiftUI.Menu<SwiftUI.Label<SwiftUI.Text, SwiftUI.Image>, …>…>
        )>>
    >>
>
```

整份 interface（11603 行）修后只变了两行：第 4311 行和第 4898 行，修前都含 `TupleToolbarContent<A>`。0.21.0 与 PR 头的输出完全相同。

解开后的类型里有 `accessor function at 8328`。这是另一个既有的限制：同一份输出里，修前就已有 6 行、13 处这个占位符（kind-9 accessor thunk 没解出来），以前这一处藏在 `A` 后面看不到。与本条无关，不在这次修。

**落地时**：这条会改变普通 SwiftUI app 的 interface 输出，渲染 A/B 必跑。`Internal/OpaqueReturnTypeResolution.md` 补一句「实参表按描述符的层结构重新分组」。

### 2. 离线检查把 Cocoa 子类判成违反基类约束（中，PR 引入）

`Sources/Declaration/SwiftSpecialization/GenericSpecializer+StaticSpecialization.swift:443`（`checkBaseClass`）。

- **能复现吗**：能。`<Subject: NSObject>` 选 `FixtureOperation: Operation` 时，离线 `staticPreflight` 报错，`specialize` 抛错，在线（运行时）路径却接受同样的选择。原因有两层：
  - `ConformanceProvider.subclasses(of:)` 的类层级图只连得起**已索引的 Swift 类**。`FixtureOperation → NSOperation → NSObject` 断在中间的 ObjC 类上，于是 `FixtureOperation` 不在 `NSObject` 的子树里。检查又因为它「已被索引」，就判成确定违反。
  - `subclasses(of:)` 的结果总以基类自己开头，所以「索引里没有这个类层级」那条警告分支永远走不到。
- **基线有没有**：离线检查是 PR 新代码；在线路径由运行时判断，不受影响。
- **值不值得修**：值得。`<V: NSView>`、`<T: NSObject>`、`<VC: UIViewController>` 是最常见的基类约束，离线模式一接上宿主就会误拒合法特化，违背 PR 自己定的「证明不了只给警告」原则。
- **以前修过吗**：没有。`subclasses(of:)` 是 2026-05-10 的 `a209e2b3` 为缩小候选列表写的，空结果的含义是「不缩小」，以前从没被当成证据用过。

**复现测试** `Tests/SwiftSpecializationTests/OfflineObjectiveCBaseClassTests.swift`（2 个测试，自带一个 `import Foundation` 的小 fixture）：

```swift
public final class FixtureOperation: Operation {}
public final class FixtureObject: NSObject {}
public struct ObjectBound<Subject: NSObject> { public var subject: Subject }
```

候选是从索引器的定义手工构造的：请求里的候选列表同样被那张类层级图缩小过，所以 `FixtureOperation` 根本不在列表里。这个「候选列表缺类」是基线既有的问题，在线路径也一样，这里不修。修前：

```
staticPreflight → isValid == false
specialize      → specializationFailed("Type 'ObjectiveCBaseClassFixture.FixtureOperation' for parameter 'A' does not inherit from required base class 'NSObject'")
```

**修法**：沿实际类的父类链往上走。走到基类就通过；走到根类还没碰到基类才报错；链走出已索引的类（ObjC 类，或索引器没收录的镜像里的类）就给警告。为此给 `ConformanceProvider` 加一个带默认实现的 `superclassLink(of:)`，库外的遵循者不用改。`IndexerConformanceProvider` 在建子类图的同一遍循环里顺手记下反向链接，名字一律去掉实参后再比较，否则 `BaseBox<A>` 和 `BaseBox` 对不上。死分支随之删掉。

```diff
--- a/Sources/Declaration/SwiftSpecialization/GenericSpecializer+StaticSpecialization.swift
+++ b/Sources/Declaration/SwiftSpecialization/GenericSpecializer+StaticSpecialization.swift
@@ -463,17 +474,33 @@
             builder.addError(.baseClassRequirementNotSatisfied(parameterName: subject.path, expectedBaseClass: expectedDisplay, actualType: subject.display))
             return
         }
-        let subtree = conformanceProvider.subclasses(of: expectedClassName)
-        guard !subtree.isEmpty else {
-            builder.addWarning(.baseClassRequirementResolutionFailed(parameterName: subject.path, reason: "offline: the indexed images describe no class hierarchy under \(expectedDisplay)"))
-            return
+        // Up the superclass chain the indexed images describe, class names
+        // compared unbound. Reaching the base proves the requirement; a root
+        // class reached without it proves the violation. A link no indexed
+        // image describes proves nothing either way: an Objective-C class —
+        // `NSOperation` between a Swift class and an `NSObject` bound — or a
+        // class of an image the indexer does not hold. Taking that for a
+        // violation rejected every Swift class below a Cocoa class, which the
+        // runtime accepts.
+        var currentClassName = actualTypeName
+        var visitedClassNames: Set<String> = []
+        while visitedClassNames.insert(currentClassName.name).inserted {
+            if currentClassName.name == expectedClassName.name { return }
+            switch conformanceProvider.superclassLink(of: currentClassName) {
+            case .inherits(let superclassName):
+                currentClassName = unboundNominalTypeName(of: superclassName.node.materialize(), kind: .class) ?? superclassName
+            case .root:
+                builder.addError(.baseClassRequirementNotSatisfied(parameterName: subject.path, expectedBaseClass: expectedDisplay, actualType: subject.display))
+                return
+            case .unknown:
+                let reason = currentClassName.name == actualTypeName.name
+                    ? "offline: \(subject.display) is in no indexed image, so its superclass chain cannot be read"
+                    : "offline: the superclass chain of \(subject.display) leaves the indexed images at \(currentClassName.name), so whether it reaches \(expectedDisplay) cannot be read"
+                builder.addWarning(.baseClassRequirementResolutionFailed(parameterName: subject.path, reason: reason))
+                return
+            }
         }
-        if subtree.contains(where: { $0.name == actualTypeName.name }) { return }
-        if conformanceProvider.typeDefinition(for: actualTypeName) != nil {
-            builder.addError(.baseClassRequirementNotSatisfied(parameterName: subject.path, expectedBaseClass: expectedDisplay, actualType: subject.display))
-        } else {
-            builder.addWarning(.baseClassRequirementResolutionFailed(parameterName: subject.path, reason: "offline: \(subject.display) is in no indexed image, so its superclass chain cannot be read"))
-        }
+        builder.addWarning(.baseClassRequirementResolutionFailed(parameterName: subject.path, reason: "offline: the superclass chain of \(subject.display) loops back on itself"))
     }
```

`ConformanceProvider.swift` 里的配套改动（与第 5 条的 `isConditionalConformance` 写在同一处，第 5 条另列）：

```diff
--- a/Sources/Declaration/SwiftSpecialization/ConformanceProvider.swift
+++ b/Sources/Declaration/SwiftSpecialization/ConformanceProvider.swift
@@ -49,8 +49,34 @@
     /// no class-hierarchy knowledge degrade to "show every candidate"
     /// without breaking the contract.
     func subclasses(of baseClassName: TypeName) -> [TypeName]
+
+    /// What the provider knows of the class `className` inherits from
+    /// directly — the link the offline base-class check walks up (evolution
+    /// proposal `offline-generic-specialization`). Default `.unknown`: a
+    /// provider without class-hierarchy knowledge proves nothing either way.
+    func superclassLink(of className: TypeName) -> SuperclassLink
 }
 
+/// A class's direct superclass, as a `ConformanceProvider` knows it.
+public enum SuperclassLink: Sendable, Equatable {
+    /// The provider describes the class, and it inherits from this class.
+    case inherits(from: TypeName)
+    /// The provider describes the class, and it has no superclass.
+    case root
+    /// The provider holds no description of the class: an Objective-C
+    /// class, or a class of an image it does not index.
+    case unknown
+}
+
 // MARK: - Default Implementations
 
 extension ConformanceProvider {
@@ -78,6 +104,14 @@
     public func subclasses(of baseClassName: TypeName) -> [TypeName] {
         []
     }
+
+    public func superclassLink(of className: TypeName) -> SuperclassLink {
+        .unknown
+    }
 }
 
 // MARK: - IndexerConformanceProvider
@@ -111,6 +145,9 @@
     /// (`TypeName.name`, "Module.Type") is stable across both paths.
     private final class SubclassCache: @unchecked Sendable {
         var directChildrenByParentName: [String: [TypeName]]?
+        /// Every indexed class's direct superclass by the class's name: the
+        /// same links, read the other way, built in the same walk.
+        var superclassLinkByClassName: [String: SuperclassLink]?
         let lock = NSLock()
     }
 
@@ -152,7 +189,7 @@
         // return empty so callers can fall back to "do not narrow".
         guard baseClassName.kind == .class else { return [] }
 
-        let directChildren = directChildrenMap()
+        let directChildren = classHierarchy().directChildrenByParentName
 
         // BFS over the parent → direct-subclasses graph, keyed by
         // canonical name string. Result list still uses `TypeName`s
@@ -171,18 +208,37 @@
             }
         }
         return result
+    }
+
+    public func superclassLink(of className: TypeName) -> SuperclassLink {
+        guard className.kind == .class else { return .unknown }
+        return classHierarchy().superclassLinkByClassName[className.name] ?? .unknown
     }
 
     /// Build (or fetch from cache) the parent-name → direct-subclasses
-    /// map by walking every indexed `.class` definition's
+    /// map, and the class-name → superclass map that reads the same links
+    /// the other way, by walking every indexed `.class` definition's
     /// `superclassType` link. Lock-protected so concurrent first-callers
     /// don't both pay the O(n) build cost.
-    private func directChildrenMap() -> [String: [TypeName]] {
+    private func classHierarchy() -> (directChildrenByParentName: [String: [TypeName]], superclassLinkByClassName: [String: SuperclassLink]) {
         subclassCache.lock.lock()
         defer { subclassCache.lock.unlock() }
-        if let cached = subclassCache.directChildrenByParentName { return cached }
+        if let cachedChildren = subclassCache.directChildrenByParentName, let cachedLinks = subclassCache.superclassLinkByClassName {
+            return (cachedChildren, cachedLinks)
+        }
 
         var map: [String: [TypeName]] = [:]
+        var links: [String: SuperclassLink] = [:]
         for (childTypeName, entry) in indexer.allAllTypeDefinitions {
             guard childTypeName.kind == .class else { continue }
             guard case .class(let classDescriptor) = entry.value.typeContextDescriptorWrapper else { continue }
@@ -212,14 +268,18 @@
             }
 
             // A missing / unreadable superclass link is the ordinary "this class
-            // has no usable parent" case and stays silent.
+            // has no usable parent" case and stays silent. Missing is a root
+            // class; unreadable stays unknown, proving nothing.
             var superNode: Node?
             do {
                 superNode = try classWrapper.superclassNode(in: entry.machO.context)
             } catch {
                 continue
             }
-            guard let superNode else { continue }
+            guard let superNode else {
+                links[childTypeName.name] = .root
+                continue
+            }
 
             // `SymbolicDemangler.demangleType` may wrap the result in a
             // `.type` node or return a deeper tree depending on the
@@ -240,10 +300,12 @@
             }
             let superTypeName = TypeName(node: InternedNodeReferenceCache.shared.reference(interning: superNode, in: entry.machO), kind: .class)
             map[superTypeName.name, default: []].append(childTypeName)
+            links[childTypeName.name] = .inherits(from: superTypeName)
         }
 
         subclassCache.directChildrenByParentName = map
-        return map
+        subclassCache.superclassLinkByClassName = links
+        return (map, links)
     }
 }
 
@@ -333,6 +395,20 @@
         }
         return result
     }
+
+    /// The first provider that describes the class answers: a class lives in
+    /// one image, so at most one sub-indexer knows its superclass link.
+    public func superclassLink(of className: TypeName) -> SuperclassLink {
+        for provider in providers {
+            let link = provider.superclassLink(of: className)
+            if link != .unknown { return link }
+        }
+        return .unknown
+    }
 }
```

仍有的局限（基线就有，不在这次修）：比较的是**去掉实参的类名**，`<S: BaseBox<Int>>` 选 `DerivedBox<String>` 时会被放行。要比到实参，得沿父类链做实参代换，留作以后。可选增强：用现成的 `ObjCAncestorResolver` 顺着依赖闭包把 ObjC 祖先也读出来，这样 `NSOperation → NSObject` 能直接证明，连警告都不用给。

**修后**：2 个测试通过，`OfflineSpecializationTests` 里原有的三条基类测试（不相关的类报错、子类通过、宿主类报错）不变。同一个选择现在是零个错误、一条警告：

```
Could not resolve required base class for parameter 'A'; preflight skipped the inheritance check: offline: the superclass chain of ObjectiveCBaseClassFixture.FixtureOperation leaves the indexed images at __C.NSOperation, so whether it reaches NSObject cannot be read
```

**落地时**：`ConformanceProvider` 多了一个带默认实现的 requirement 和一个公开枚举 `SuperclassLink`，进 0.22.0 发版说明；`Internal/OfflineGenericSpecialization.md` 的「离线约束检查」一节改写基类那一条。

### 3. 「参数 == 参数」的 same-type 约束补不出参数（低到中，PR 引入；含第 10 条可测的一侧）

`Sources/Declaration/SwiftSpecialization/GenericInstantiation.swift:82`（`fillFixedParameters`）。

- **能复现吗**：能，SymbolTestsCore 里现成的 `SameTypeRequirementTest<First, Second> where First == Second` 就是这个形状。编译器把仍带 key argument 的参数写在约束**左边**（`First == Second`），不带 key argument 的 `Second` 在右边。`fillFixedParameters` 只按左边记约束，于是 `Second` 永远补不上。
  - 离线：`GenericInstantiation` 抛 `unresolvedFixedParameter`，`specialize` 把它包成 `specializationFailed` 抛出。
  - 在线：`try?` 静默退回扁平名 `<Swift.Int>`（见第 10 条），而类型头印的是运行时的 `<Swift.Int, Swift.Int>`。
  - 运行时 `_gatherWrittenGenericParameters`（Swift 6.4 源码 `stdlib/public/runtime/MetadataLookup.cpp`，函数从 3575 行起）在 3686 行前后有「左边已有实参、右边也是参数，就抄给右边」的分支，PR 移植时漏了。
- **基线有没有**：`GenericInstantiation` 是 PR 新代码；在线类型名的形状也是 PR 改的。
- **值不值得修**：值得。用户无法绕开。这个写法放在类型声明上，Swift 6 语言模式会报错（Swift 5 只是警告）；但放在 extension 上一直合法（`extension Pair where First == Second { struct Nested<C> }`，已用 `-swift-version 6` 编过），所以新代码里同样会出现。extension 这个形状走的是同一段补参数的逻辑，没有单独测。改动小。
- **以前修过吗**：没有。

**复现测试** `Tests/SwiftSpecializationTests/TiedParameterInstantiationTests.swift`（2 个测试）。为了离线、在线两条路都能测，并能拿运行时的名字作对照，形状加在共享 fixture `GenericSpecializationFixture` 里（它用 Swift 5 模式编译，这个写法只是警告）：

```diff
--- a/Sources/TestSupport/MachOTestingSupport/GenericSpecializationFixture.swift
+++ b/Sources/TestSupport/MachOTestingSupport/GenericSpecializationFixture.swift
@@
+    // `Second` is tied to `First`, so it takes no key argument: the compiler
+    // writes the requirement as `First == Second`, the parameter that keeps
+    // its key argument on the left, and the instantiation binds `Second` to
+    // `First`'s argument. A warning in the fixture's Swift 5 mode.
+    public struct TiedParameterPair<First, Second> where First == Second {
+        public var first: First
+        public var second: Second
+    }
```

用到这个共享 fixture 的 9 个现有套件（`OfflineSpecializationTests`、`OfflineSpecializationParityTests`、`InstantiatedTypeNameTests`、`CanonicalParameterDepthTests`、`BoundInstantiationLayoutTests`、`ExtensionContextInstantiationLayoutTests`、`AccessorThunkOwnerLayoutDepthTests`、`GenericParameterDepthNamingTests`、`GenericParameterDepthDumpTests`）加了这个类型后全部仍然通过。修前：

```
离线：specializationFailed(reason: "could not bind the type's parameters: the argument of B, which a same-type requirement fixes, could not be determined from that requirement")
在线：specialized GenericSpecializationFixture.TiedParameterPair<Swift.Int>   runtime GenericSpecializationFixture.TiedParameterPair<Swift.Int, Swift.Int>
```

**修法**：收集 same-type 约束时，右边也是参数的另记一份；补参数时先按原逻辑用右边的类型补，补不上就看自己是不是某条约束的右边、左边已有实参，有就抄过来。迭代到不动点的逻辑不变。

```diff
--- a/Sources/Declaration/SwiftSpecialization/GenericInstantiation.swift
+++ b/Sources/Declaration/SwiftSpecialization/GenericInstantiation.swift
@@ -79,6 +79,11 @@
     /// requirement that fixes it. A right-hand side can name another fixed
     /// parameter (`C == B`, `B == Int`), so the requirements are applied until
     /// no further one resolves.
+    ///
+    /// A requirement between two parameters (`First == Second`) is read both
+    /// ways, as the runtime's `_gatherWrittenGenericParameters` reads it: the
+    /// compiler writes the parameter that keeps its key argument on the LEFT,
+    /// so it is the right-hand parameter that takes the left one's argument.
     private static func fillFixedParameters<MachO: MachOSwiftSectionRepresentableWithCache>(
         _ argumentsByFlatIndex: inout [Node?],
         depthLayout: GenericParameterDepthLayout,
@@ -89,16 +94,26 @@
         guard !unresolvedFlatIndices.isEmpty else { return }
 
         // The same-type requirements whose subject is a parameter itself, by
-        // that parameter's position in the cumulative list.
+        // that parameter's position in the cumulative list; and, for those
+        // whose right-hand side is a parameter too, the left-hand parameter
+        // by the right-hand one's position.
         var fixingRequirementByFlatIndex: [Int: MangledName] = [:]
+        var leftHandFlatIndexByRightHandFlatIndex: [Int: Int] = [:]
         for requirement in requirements where requirement.layout.flags.kind == .sameType {
             guard let subjectNode = try? SymbolicDemangler.demangleType(for: requirement.paramMangledName(in: machO.context), in: machO.context),
                   let position = genericParameterPosition(of: subjectNode),
                   let flatIndex = depthLayout.flatIndex(depth: position.depth, index: position.index),
-                  fixingRequirementByFlatIndex[flatIndex] == nil,
                   let rightHandSide = try? requirement.type(in: machO.context)
             else { continue }
-            fixingRequirementByFlatIndex[flatIndex] = rightHandSide
+            if fixingRequirementByFlatIndex[flatIndex] == nil {
+                fixingRequirementByFlatIndex[flatIndex] = rightHandSide
+            }
+            if let rightHandSideNode = try? SymbolicDemangler.demangleType(for: rightHandSide, in: machO.context),
+               let rightHandPosition = genericParameterPosition(of: rightHandSideNode),
+               let rightHandFlatIndex = depthLayout.flatIndex(depth: rightHandPosition.depth, index: rightHandPosition.index),
+               leftHandFlatIndexByRightHandFlatIndex[rightHandFlatIndex] == nil {
+                leftHandFlatIndexByRightHandFlatIndex[rightHandFlatIndex] = flatIndex
+            }
         }
 
         var didResolveParameter = true
@@ -106,13 +121,20 @@
             didResolveParameter = false
             let partialBinding = Self.partialBinding(argumentsByFlatIndex, depthLayout: depthLayout)
             for flatIndex in unresolvedFlatIndices {
-                guard let rightHandSide = fixingRequirementByFlatIndex[flatIndex],
-                      let rightHandSideNode = try? SymbolicDemangler.demangleType(for: rightHandSide, in: machO.context)
-                else { continue }
-                let argument = DependentMemberProjection.projectingConcreteMembers(in: partialBinding.substituting(in: rightHandSideNode), in: machO)
-                guard !containsGenericParameter(argument) else { continue }
-                argumentsByFlatIndex[flatIndex] = typeWrapped(argument)
-                didResolveParameter = true
+                if let rightHandSide = fixingRequirementByFlatIndex[flatIndex],
+                   let rightHandSideNode = try? SymbolicDemangler.demangleType(for: rightHandSide, in: machO.context) {
+                    let argument = DependentMemberProjection.projectingConcreteMembers(in: partialBinding.substituting(in: rightHandSideNode), in: machO)
+                    if !containsGenericParameter(argument) {
+                        argumentsByFlatIndex[flatIndex] = typeWrapped(argument)
+                        didResolveParameter = true
+                        continue
+                    }
+                }
+                if let leftHandFlatIndex = leftHandFlatIndexByRightHandFlatIndex[flatIndex],
+                   let leftHandArgument = argumentsByFlatIndex[leftHandFlatIndex] {
+                    argumentsByFlatIndex[flatIndex] = leftHandArgument
+                    didResolveParameter = true
+                }
             }
             unresolvedFlatIndices.removeAll { argumentsByFlatIndex[$0] != nil }
         }
```

**修后**：2 个测试通过，在线名与运行时名结构相等。

```
离线：GenericSpecializationFixture.TiedParameterPair<Swift.Int, Swift.Int>   （绑定 [["Swift.Int", "Swift.Int"]]）
在线：specialized GenericSpecializationFixture.TiedParameterPair<Swift.Int, Swift.Int>   runtime GenericSpecializationFixture.TiedParameterPair<Swift.Int, Swift.Int>
```

### 4. extension 里协议兜底补出的默认实现无处打印（低，PR 引入）

`Sources/Output/SwiftInterface/SwiftInterfaceBuilder.swift:248`。

interface 的打印顺序是：顶层类型 → 特化子类型 → 顶层协议 → 嵌套协议的默认实现 extension → 所有 extension。PR 的 `bca9594d` 把「声明在 extension 里的协议」的默认实现挪到了第四块；而这类协议自己要到第五块才被打印、被索引。

- **能复现吗**：能，已造出触发条件。library evolution 下，若协议需求的默认实现来自**父协议**的 extension（`Labeled: Base`，`describe()` 的默认实现写在 `extension Base` 里），编译器会生成一个挂在 `Labeled` 需求名下的默认 witness。模块索引器 `prepare()` 只扫协议 extension 块的符号，扫不到它；要等协议自己的索引过程兜底补出这个 extension。第四块读列表时协议还没索引，列表是空的；而打印器又不再在协议后面打印它，于是哪里都不打印。
- **基线有没有**：改前打印在 `extension Swift.Int { … }` 的大括号里（位置不合法，但打印了）：

  ```swift
  extension Swift.Int {
      protocol Labeled: ProbeDefaultWitness.Base {
          func describe() -> Swift.String
      }
  extension Swift.Int.Labeled {
      func describe() -> Swift.String
  }
  }
  ```

  PR 的修复把它挪走之后，这种情况就彻底消失了。属于 PR 引入的回退，只在这个窄形状上出现。
- **值不值得修**：值得，改动小。
- **以前修过吗**：没有。兜底逻辑来自 2026-08-22 的 `85b88b43`（提案 0007，统一 extension 容器），本意是「没有模块索引器时」才用；第四块的条件是 0007 修活的，PR 扩大了条件，但没考虑索引时机。

**复现测试** `Tests/SwiftInterfaceTests/ProtocolInExtensionDefaultWitnessTests.swift`（2 个测试，fixture 用 `-enable-library-evolution` 编）：

```swift
public protocol Base {}
extension Base { public func describe() -> String { "base" } }
extension Int {
    public protocol Labeled: Base { func describe() -> String }
}
```

修前：顶层没有 `extension Swift.Int.Labeled`；同一个 builder 打印两次，结果不一样。第一次打印到第五块时协议才被索引，第二次打印时列表已经完整，第四块就把它印出来了。

**修法**：第四块读列表之前，先对协议调用 `index(in:)`（PR 已经让它同步、可重复调用、只跑一次），区块顺序不动。`printRootContents` 整个函数体是 `@SemanticStringBuilder`，直接写 `try? …` 会被当成要拼进输出的组件，所以包成一个小辅助函数。

```diff
--- a/Sources/Output/SwiftInterface/SwiftInterfaceBuilder.swift
+++ b/Sources/Output/SwiftInterface/SwiftInterfaceBuilder.swift
@@ -246,7 +246,7 @@
             // of a parent; its blocks used to print inside that extension's
             // braces (evolution proposal `nested-definition-regions`).
             for protocolDefinition in indexer.allProtocolDefinitions.values where protocolDefinition.parent != nil || protocolDefinition.extensionContext != nil {
-                for extensionDefinition in protocolDefinition.defaultImplementationExtensions {
+                for extensionDefinition in indexedDefaultImplementationExtensions(of: protocolDefinition) {
                     await printCatchedThrowing(
                         dispatchingTo: eventDispatcher,
                         context: .init(name: extensionDefinition.extensionName.name, kind: .extension)
@@ -267,6 +267,20 @@
                 }
             }
         }
+    }
+
+    /// `protocolDefinition`'s default-implementation extensions, read once
+    /// it is indexed. The list is complete only then: the protocol's own pass
+    /// synthesizes the extension of a default the module indexer's symbol scan
+    /// misses — under library evolution, a default witness named after the
+    /// requirement itself. A protocol nested in a type is indexed by the time
+    /// the nested protocols' block prints, its type printed before it; one
+    /// declared in an extension prints, and indexes, only in the extensions
+    /// block after it, so its synthesized extension printed nowhere. A pass
+    /// that fails is reported when the protocol prints.
+    private func indexedDefaultImplementationExtensions(of protocolDefinition: ProtocolDefinition) -> [ExtensionDefinition] {
+        try? protocolDefinition.index(in: machO)
+        return protocolDefinition.defaultImplementationExtensions
     }
 
     private func collectModules() async throws {
```

横向排查：库里读 `defaultImplementationExtensions` 的只有这里和打印器（`SwiftDeclarationPrinter.swift:393`，读之前已经 `index(in:)`），没有别的遗漏。**RuntimeViewer 有同样的顺序问题**：`RuntimeSwiftSection.defaultImplementationExtensionsLeftToPrint(of:)` 也是直接读这个列表，需要在读之前确保协议已索引（那边改）。

**修后**：2 个测试通过；`ProtocolInExtensionTests` 不变。

CLI 对同一个 fixture 的 `interface`（只摘最后一段）。PR 头：

```swift
extension Swift.Int {
    protocol Labeled: ProbeDefaultWitness.Base {
        func describe() -> Swift.String
    }
}
```

修后：

```swift
extension Swift.Int.Labeled {
    func describe() -> Swift.String
}

extension Swift.Int {
    protocol Labeled: ProbeDefaultWitness.Base {
        func describe() -> Swift.String
    }
}
```

默认实现块出现在协议声明之前，这是 PR 定下的区块顺序（嵌套协议的默认实现 extension 块在所有 extension 之前），不是这次修法带来的。

**根因的另一种修法（未做）**：让 `prepare()` 的符号扫描也认出「挂在需求名下的默认 witness」，列表在 `prepare()` 之后就完整。改动大得多，眼下这处读取顺序的修法已经够用。

### 6. 静态展开偏移把 opaque 类型印成占位符（低，PR 引入）

`Sources/Analysis/SwiftLayout/ImageUniverse+AssociatedTypeWitnessProjection.swift:102`（`projectingConcreteMembers`）。

PR 让静态展开偏移树的每一行都经过「关联类型投影」：`[Swift.Int].Element` 按 `Array` 遵循 `Collection` 时记录的实际类型（witness）读成 `Swift.Int`。但实际类型记录里可能是一个 opaque 类型引用，投影把它原样拼进了这一行。

- **能复现吗**：能，但要用对写法。编译器只要知道 opaque 结果的底层类型，就会把它直接写进本模块的记录，**开了 library evolution 也一样**（普通写法实测得到 `() -> Swift.Int`，测试通过）。会留下 opaque 引用的写法有三种：`dynamic` 的命名声明、按系统版本返回不同类型（SE-0360，`if #available`），以及另一个 resilient 模块里不可内联的 `some`。前两种已实测复现，第三种未实测。
- **基线有没有**：改前（0.21.0）这一行印的是成员名：

  ```
  // └── make (() -> NestedFieldOffsetOpaqueWitnessFixture.DynamicConcrete.NestedFieldOffsetOpaqueWitnessFixture.Shape.Body): 0x0
  ```

  PR 头变成占位符，属于 PR 引入的回退。
- **值不值得修**：值得，改动小。只影响读文件（`MachOFile`）并打开展开字段偏移、而且关联类型的实际类型是 opaque 的字段。离线特化代换字段类型走的是同一个函数，一并受益。
- **以前修过吗**：没有，新代码。

**复现测试** `Tests/SwiftLayoutTests/NestedFieldOffsetOpaqueWitnessTests.swift`（1 个测试 × 2 组参数）：

```swift
public struct DynamicConcrete: Shape { public dynamic var body: some Equatable { 1 } }
public struct ConditionalConcrete: Shape {
    public var body: some Equatable { if #available(macOS 26, *) { return 1 } else { return "one" } }
}
public struct Wrapper<Value: Shape> { public var make: () -> Value.Body }
public struct DynamicHolder { public var wrapper: Wrapper<DynamicConcrete> }
public struct ConditionalHolder { public var wrapper: Wrapper<ConditionalConcrete> }
```

修前：

```
make.typeName → "() -> opaque type symbolic reference 0x1A38.0"   (DynamicHolder)
make.typeName → "() -> opaque type symbolic reference 0x1A60.0"   (ConditionalHolder)
```

**修法**：投影出来的实际类型里含 opaque 引用（或 kind-9 accessor 引用）时不替换，保留成员名，也就是改前的输出。`[Int].Element → Int` 这类能正常投影的不受影响。另一种做法是走 opaque 重写器把它解开，但重写器在 `SwiftDeclarationRendering` 里，`SwiftLayout` 够不到；而且条件可用的 opaque 没有唯一的底层类型。

```diff
--- a/Sources/Analysis/SwiftLayout/ImageUniverse+AssociatedTypeWitnessProjection.swift
+++ b/Sources/Analysis/SwiftLayout/ImageUniverse+AssociatedTypeWitnessProjection.swift
@@ -119,7 +122,8 @@
            let baseTypeNode = rewrittenNode.children.first,
            let associatedTypeReference = rewrittenNode.children.at(1),
            !Self.containsGenericParameter(baseTypeNode),
-           let projection = projectedAssociatedTypeWitness(base: baseTypeNode, associatedTypeReference: associatedTypeReference) {
+           let projection = projectedAssociatedTypeWitness(base: baseTypeNode, associatedTypeReference: associatedTypeReference),
+           !Self.containsUnspellableReference(projection.witnessNode) {
             var nestedRewrittenNodes: [ObjectIdentifier: Node] = [:]
             let projectedWitness = projectingConcreteMembers(in: projection.witnessNode, remainingHops: remainingHops - 1, rewrittenNodes: &nestedRewrittenNodes)
             // The member sits inside a `.type` wrapper already; the witness's
@@ -133,4 +137,20 @@
     private static func containsGenericParameter(_ node: Node) -> Bool {
         node.kind == .dependentGenericParamType || node.children.contains(where: containsGenericParameter)
     }
+
+    /// Whether `node` holds a reference that prints as a placeholder rather
+    /// than a type: an opaque type — the record keeps one for the result of a
+    /// `dynamic` declaration, an availability-conditional `some` (SE-0360) and
+    /// a non-inlinable `some` of another resilient module, whose underlying
+    /// type it cannot fix — or a kind-9 accessor function. Spliced into a
+    /// field's type it read `opaque type symbolic reference 0x….0`; the member
+    /// it would replace, `Concrete.Body`, names the type better.
+    private static func containsUnspellableReference(_ node: Node) -> Bool {
+        switch node.kind {
+        case .opaqueType, .opaqueReturnType, .opaqueReturnTypeOf, .opaqueTypeDescriptorSymbolicReference, .accessorFunctionReference:
+            return true
+        default:
+            return node.children.contains(where: containsUnspellableReference)
+        }
+    }
 }
```

（同一文件开头那处 `guard node.contains(.dependentMemberType)` 属于第 14 条。）

**修后**：两组参数都通过；`SwiftLayoutTests` 全部 33 个套件不变。

```
make.typeName → "() -> NestedFieldOffsetOpaqueWitnessFixture.DynamicConcrete.NestedFieldOffsetOpaqueWitnessFixture.Shape.Body"
make.typeName → "() -> NestedFieldOffsetOpaqueWitnessFixture.ConditionalConcrete.NestedFieldOffsetOpaqueWitnessFixture.Shape.Body"
```

CLI `dump --emit-expanded-field-offsets`，`DynamicHolder` 的展开行（`ConditionalHolder` 同理）：

```
0.21.0：// └── make (() -> NestedFieldOffsetOpaqueWitnessFixture.DynamicConcrete.NestedFieldOffsetOpaqueWitnessFixture.Shape.Body): 0x0
PR 头：  // └── make (() -> opaque type symbolic reference 0x1A28.0): 0x0
修后：  // └── make (() -> NestedFieldOffsetOpaqueWitnessFixture.DynamicConcrete.NestedFieldOffsetOpaqueWitnessFixture.Shape.Body): 0x0
```

### 7. `specializedChildren` 无锁追加（低到中，机制旧，PR 扩大）

`Sources/Declaration/SwiftSpecialization/TypeDefinition+Specialization.swift:24`（关联对象），追加点 `:130`、`:190`、`:462`、`:492`。

`specializedChildren` 存在一个 nonatomic 的关联对象里（ObjC 运行时挂在对象上的附加存储；`TypeDefinition` 在另一个模块，跨模块的 extension 加不了存储属性）。追加是「读出数组 → 追加 → 写回」三步，没有锁。

- **能复现吗**：能，而且是确定性的：512 个任务同时特化同一个定义，每次只留下 445 到 467 个（直接跑 5 次、挂 lldb 跑 6 次，11 次全部丢）。RuntimeViewer 侧也核实了（它的 find-navigator 工作树 `942524f4`，`RuntimeViewerCore/Sources/RuntimeViewerCore/Core/RuntimeSwiftSection.swift`）：`actor RuntimeSwiftSection` 在第 905 行 `await baseTypeDefinition.specialize(...)`，这个方法是 nonisolated async，本库没开 `NonisolatedNonsendingByDefault`，所以它离开 actor 执行；与此同时 actor 可能在第 295/393/630 行读这个数组。最坏情况是读到写入方刚释放的数组（use-after-free），这个没实际跑出来。
- **基线有没有**：机制是 2026-06-15 拆模块（`47b5961f`）时引入的。PR 又加了两处追加，还把 `TypeDefinition` 标成 `@unchecked Sendable`，并发打印提案里「RuntimeViewer 的读写都在 section actor 上」这个前提不成立。
- **值不值得修**：值得，改动小。
- **以前修过吗**：没有。

**复现测试** `Tests/SwiftSpecializationTests/ConcurrentSpecializationTests.swift`（1 个测试，在子进程里跑：丢更新的那种重叠，也可能释放一个仍在被读的数组，那会把整个测试进程带走）。用自己的索引器，不污染共享定义：

```swift
try await withThrowingTaskGroup(of: Void.self) { group in
    for _ in 0 ..< 512 {
        group.addTask {
            try await definition.specialize(with: result, typeArgumentNodes: typeArgumentNodes, in: machOImage)
            _ = definition.specializedChildren.count   // RuntimeViewer 的 actor 同时在读
        }
    }
    try await group.waitForAll()
}
// 留下的个数 != 512 → 子进程以 EXIT_FAILURE 退出
```

修前：`expected exit status ".success", but ".exitCode(EXIT_FAILURE)" was reported`。

注意：exit test 的测试体一旦抛错，子进程是以 SIGTRAP 结束的，看起来像崩溃。所以测试体里自己 catch 后 `exit(EXIT_FAILURE)`，让 SIGTRAP 只剩「被测代码 trap」这一种含义。

**修法**：关联对象保留，读和四处追加都经过同一把所有定义共用的锁（库里 `@Mutex` 宏的惯用写法，同 `DefinitionIndexing`）。特化很少、追加很快，一把锁足够。没有把存储挪进 `TypeDefinition`：那会改变它的实例大小，而 `DeclarationModelInstanceSizeTests` 专门钉住了这个大小。

```diff
--- a/Sources/Declaration/SwiftSpecialization/TypeDefinition+Specialization.swift
+++ b/Sources/Declaration/SwiftSpecialization/TypeDefinition+Specialization.swift
@@ -20,10 +20,29 @@
 /// instance properties to a type it does not own.
 extension TypeDefinition {
     /// Associated-object backing for `specializedChildren`. Mutated only
-    /// within this file (the `specialize(...)` family appends to it).
+    /// within this file (the `specialize(...)` family appends to it), and
+    /// read and written only under `specializedChildrenAccess`.
     @AssociatedObject(.retain(.nonatomic))
     private var _specializedChildren: [TypeDefinition] = []
 
+    /// The lock every read and write of `_specializedChildren` holds — one
+    /// for all definitions, as a specialization is rare and its append quick.
+    /// A host reads the list while it specializes from another task:
+    /// RuntimeViewer's section actor awaits `specialize(...)`, a nonisolated
+    /// async method that runs off the actor while the actor goes on reading.
+    /// Unlocked, two appends at once lost one of them, and a read overlapping
+    /// a write could retain the array the write had just released (the
+    /// associated object is retained non-atomically, and its getter even
+    /// writes on a first read).
+    @Mutex
+    private static var specializedChildrenAccess: Void = ()
+
+    private func appendSpecializedChild(_ specialized: TypeDefinition) {
+        Self._specializedChildrenAccess.withLockUnchecked { _ in
+            _specializedChildren.append(specialized)
+        }
+    }
+
     /// Specialized children produced by **directly** calling
     /// `specialize(with:in:)` (or the `derivingNestedSpecializationsWith`
     /// overload) on this generic definition. Each entry is a sibling-shaped
@@ -67,7 +86,9 @@
     /// independent subtrees in `outerSpecialized.typeChildren`). Equality
     /// of `metadata` does not imply identity of the wrapping
     /// `TypeDefinition`.
-    public var specializedChildren: [TypeDefinition] { _specializedChildren }
+    public var specializedChildren: [TypeDefinition] {
+        Self._specializedChildrenAccess.withLockUnchecked { _ in _specializedChildren }
+    }
 
     /// Maximum recursion depth that `deriveNestedSpecializedTypeChildren`
     /// will descend before bailing out. Swift's source-level nesting rarely
@@ -127,7 +148,7 @@
             typeArgumentNodes: typeArgumentNodes,
             in: machO
         )
-        _specializedChildren.append(specialized)
+        appendSpecializedChild(specialized)
         return specialized
     }
 
@@ -187,7 +208,7 @@
         for child in specialized.typeChildren {
             child.parent = specialized
         }
-        _specializedChildren.append(specialized)
+        appendSpecializedChild(specialized)
         return specialized
     }
 
@@ -459,7 +486,7 @@
         in machO: MachOFile
     ) async throws -> TypeDefinition {
         let specialized = try makeStaticallySpecializedDefinition(with: specializationResult, in: machO)
-        _specializedChildren.append(specialized)
+        appendSpecializedChild(specialized)
         return specialized
     }
 
@@ -489,7 +516,7 @@
         for child in specialized.typeChildren {
             child.parent = specialized
         }
-        _specializedChildren.append(specialized)
+        appendSpecializedChild(specialized)
         return specialized
     }
```

两处说明随之改写：

```diff
--- a/Sources/Declaration/SwiftDeclaration/Components/Definitions/TypeDefinition.swift
+++ b/Sources/Declaration/SwiftDeclaration/Components/Definitions/TypeDefinition.swift
@@ -10,8 +10,9 @@
 /// publishes what it wrote (`DefinitionIndexing`, evolution proposal
 /// `concurrent-definition-printing`). Printing writes nothing to it, so one
 /// definition may be printed from several tasks at once. The one write
-/// outside that promise is `specialize(...)` appending to a generic
-/// definition's `specializedChildren`.
+/// outside that promise, `specialize(...)` appending to a generic
+/// definition's `specializedChildren`, holds a lock of its own
+/// (`SwiftSpecialization`).
 public final class TypeDefinition: Definition, @unchecked Sendable {
--- a/AGENTS.md
+++ b/AGENTS.md
@@ -271,7 +271,7 @@
-… The `MachOFile` reader is still not safe — MachOKit's `MachOFile` reads share one `FileHandle` (seek + read) — and `specialize(...)` appends to the generic definition unlocked. [draft-concurrent-definition-printing](…).
+… The `MachOFile` reader is still not safe — MachOKit's `MachOFile` reads share one `FileHandle` (seek + read). `specialize(...)` may run beside reads of the same definition's `specializedChildren`: the list is held under a lock of its own. [draft-concurrent-definition-printing](…).
```

**修后**：测试通过（512 个全部留下）。

**横向排查**：库里另有四处同样「懒创建、无锁、nonatomic」的关联对象：`MachOFile` 与 `DyldCache` 的 `_fileHandle`、`_fileIO`（`Sources/MachO/MachOReading/Extensions/MachOFile+.swift`、`DyldCache+.swift`）。`MachOFile` 本来就声明不支持同一版本内并发；但宿主的 dyld cache 对象会被多个版本共享（`FullDyldCache.cachedHost`），跨版本并行时这四处会不会真被并发首次访问，还没查。它们不在本 PR 范围内，建议另开一项。

**落地时**：`draft-concurrent-definition-printing` 的决策日志补一条（前提更正 + 加锁）。

### 8. opaque provider 少数一层（低到中，基线就有）

`Sources/Output/SwiftInterface/SwiftInterfaceBuilderOpaqueTypeProvider.swift:230`。

provider 负责给 `some P` 印出约束（`interface --parse-opaque-return-type` 和 RuntimeViewer 都会挂它）。它按父链里「参数个数增长的层」来数 opaque 参数所在的层号。

- **能复现吗**：能。
  - `extension Outer.SecondMiddle where A: Hashable { var body: some Sequence }` 这个 extension 一次带来两层（`Outer` 的 `A` 和 `SecondMiddle` 的 `C`），被数成一层。约束落在 `τ_2_0` 上，超出了算出的层号 1。
  - debug 构建（`swift test`、debug CLI、debug RuntimeViewer）在这里崩溃，崩溃信息：`SwiftInterfaceBuilderOpaqueTypeProvider.swift:253: Fatal error: opaque type descriptor of (extension in ProbeOpaqueExtensionDepth):ProbeOpaqueExtensionDepth.Outer.SecondMiddle< where A: Swift.Hashable>.body : some constrains parameter τ_2_0, beyond the opaque parameters' depth 1`。
  - release（0.21.0）没有断言，打印出裸 `var body: some`，同一个 extension 里的泛型方法也是裸 `some`。
  - Swift 运行时 `_gatherGenericParameterCounts` 遇到 extension 会改用被扩展的类型来数层，所以不会少数。
- **基线有没有**：有。这段是 2026-09-18 的 `044f69dc` 修 PhotosUIFoundation 崩溃时写的；PR 修那五处同类错误时漏了这里。
- **值不值得修**：值得。合法但不常见的形状，会让 debug 构建崩溃。
- **以前修过吗**：没有。`044f69dc` 当时有意按「父层是否增加参数」来数，没考虑跨层的 extension。

**复现测试** `Tests/SwiftInterfaceTests/OpaqueParameterInMultiDepthExtensionTests.swift`（1 个测试，在子进程里跑，因为修前会崩）。除了属性，还加了一个同在这个 extension 里的泛型方法，覆盖下面说的匿名上下文那条路径：

```swift
extension Outer.SecondMiddle where A: Hashable {
    public var body: some Sequence { [1] }
    public func elements<Element>(_ element: Element) -> some Sequence { [element] }
}
// 期望：var body: some Swift.Sequence {   以及   func elements<A2>(_: A2) -> some Swift.Sequence
```

修前：`expected exit status ".success", but ".signal(SIGTRAP)" was reported`。测试体里自己的检查失败会以 `EXIT_FAILURE` 退出，所以这里的 SIGTRAP 就是 provider 自己崩溃。PR 头的 debug CLI 对同一个 fixture 跑 `interface --parse-opaque-return-type` 也以 133（SIGTRAP）退出，stderr 就是上面那条崩溃信息。

**修法**：改用 opaque 描述符所在的类型或 extension 的 `GenericParameterDepthLayout` 层数，再加上声明自己是否泛型的那一层（`declaresOwnGenericParameters` 保留不变）。

一个踩过的坑：第一版直接拿描述符的**直接**父上下文来算，结果 `OpaqueParameterWithoutProtocolRequirementTests` 里 `Outer<Element>.generic<Argument>() -> some Equatable` 退化成裸 `some`。原因是泛型方法的 opaque 描述符，父上下文是一个带着方法自己签名的**匿名上下文**，旧代码（`validParentGenericContextDescriptor` 只认类型和 extension）会跳过它，直接拿它算就把方法那一层数了两次。所以要沿父链找到最近的类型或 extension。

```diff
--- a/Sources/Output/SwiftInterface/SwiftInterfaceBuilderOpaqueTypeProvider.swift
+++ b/Sources/Output/SwiftInterface/SwiftInterfaceBuilderOpaqueTypeProvider.swift
@@ -208,12 +208,17 @@
     /// The depth comes from the descriptor, not from the declaration's mangled
     /// signature: a member's signature spells only the depths it adds
     /// (`ASTMangler::appendGenericSignatureParts` skips the context's). It is
-    /// the number of enclosing depths — one per parent level that grows the
-    /// parameter count, as the runtime's `_gatherGenericParameterCounts`
-    /// counts them, so a non-generic nested type adds none — plus one when the
-    /// declaration is generic itself, which its type node says (a
-    /// `dependentGenericType` wrapper; a constrained extension's signature
-    /// sits in the context and does not count).
+    /// the number of enclosing depths — the depths of the context the
+    /// declaration sits in, the descriptor's parent, as
+    /// `GenericParameterDepthLayout` counts them: a non-generic nested type
+    /// adds none, and an extension of a nested generic type adds every level
+    /// of the type it extends, which the runtime's
+    /// `_gatherGenericParameterCounts` reaches by switching to the extended
+    /// type — plus one when the declaration is generic itself, which its type
+    /// node says (a `dependentGenericType` wrapper; a constrained extension's
+    /// signature sits in the context and does not count). Counting the parent
+    /// chain's growing levels instead took `extension Outer.SecondMiddle
+    /// where A: Hashable` for one depth and trapped below on its `τ_2_0`.
     ///
     /// A requirement on a parameter beyond that depth cannot exist for a
     /// well-formed image: that is reported as a fault and asserted in debug
@@ -227,13 +232,7 @@
             return nil
         }
 
-        var enclosingDepthCount = 0
-        var inheritedParameterCount = 0
-        for parameters in genericContext.parentParameters where parameters.count > inheritedParameterCount {
-            enclosingDepthCount += 1
-            inheritedParameterCount = parameters.count
-        }
-        let opaqueParameterDepth = enclosingDepthCount + (Self.declaresOwnGenericParameters(node) ? 1 : 0)
+        let opaqueParameterDepth = enclosingDepthCount(of: opaqueType) + (Self.declaresOwnGenericParameters(node) ? 1 : 0)
 
         var constraintsByParameter: [GenericParameterCoordinate: OpaqueParameterConstraints] = [:]
         for requirement in requirements {
@@ -269,6 +268,26 @@
         return parameterConstraints
     }
 
+    /// The depths of the type or extension the declaration naming `opaqueType`
+    /// sits in, as `GenericParameterDepthLayout` counts them — the nearest one
+    /// up the descriptor's parent chain. An anonymous context in between is
+    /// where a generic declaration's own signature lives; its depth is the one
+    /// `declaresOwnGenericParameters` adds, so it is passed over here, as the
+    /// parent chain's own `parentParameters` passes over it. No type or
+    /// extension above (a top-level declaration) is no enclosing depth.
+    private func enclosingDepthCount(of opaqueType: OpaqueType) -> Int {
+        var parent = (try? opaqueType.descriptor.parent(in: machO.context))?.flatMap(\.resolved)
+        while let currentParent = parent {
+            switch currentParent {
+            case .type, .extension:
+                return (try? GenericParameterDepthLayout.make(for: currentParent, in: machO.context))?.depthCount ?? 0
+            default:
+                parent = (try? currentParent.parent(in: machO.context))?.flatMap(\.resolved)
+            }
+        }
+        return 0
+    }
+
     /// Whether the declaration introduces generic parameters of its own: its
     /// type is wrapped in a `dependentGenericType`. The entity is unwrapped
     /// first so a `static` or accessor wrapper does not hide it; a constrained
```

**修后**：测试通过；`OpaqueParameterWithoutProtocolRequirementTests`、`OpaqueConstraintRenderingTests`、`ProjectedOpaqueMemberWitnessTests`、`CrossImageOpaqueReferenceTests` 不变。

CLI `interface --parse-opaque-return-type`。0.21.0（release，没有断言）：

```swift
extension ProbeOpaqueExtensionDepth.Outer.SecondMiddle where A: Swift.Hashable {
    var body: some {
…
extension ProbeOpaqueExtensionDepth.Outer.SecondMiddle {
    func elements<A2>(_: A2) -> some where A: Swift.Hashable
```

PR 头（debug）：崩溃，没有输出。修后：

```swift
extension ProbeOpaqueExtensionDepth.Outer.SecondMiddle where A: Swift.Hashable {
    var body: some Swift.Sequence {
…
extension ProbeOpaqueExtensionDepth.Outer.SecondMiddle {
    func elements<A2>(_: A2) -> some Swift.Sequence where A: Swift.Hashable
```

（泛型方法单独印在一个不带 `where` 的 extension 里、把约束挂在方法上，是打印器原本就有的写法，与本条无关。）

**落地时**：`Internal/OpaqueReturnTypeResolution.md` 里描述层号算法的那段同步改写。

### 10. 在线特化算类型名失败时静默退回（低，PR 引入）

`Sources/Declaration/SwiftSpecialization/TypeDefinition+Specialization.swift:225`。

- **能复现吗**：能，主要落点就是第 3 条的形状。`try?` 失败后退回旧的扁平名，没有日志也没有事件；类型头仍印运行时的名字，于是同一个定义有两个名字。另一处名字不一致（嵌套泛型类型的约束 extension 里，`DeepConstrainedInner` 的 `typeName` 按层绑定，而类型头是运行时那种把实参全塞进最内层的名字）是提案写明的**有意差异**，不改。
- **基线有没有**：PR 新代码。
- **值不值得修**：值得，补一条日志即可；修完第 3 条后基本走不到。
- **以前修过吗**：没有。

**复现测试**：可测的症状已由第 3 条的在线测试覆盖（修前在线名 `<Swift.Int>`，运行时 `<Swift.Int, Swift.Int>`）。日志本身没有可断言的行为。

**修法**：`try?` 换成 `do/catch`，退回之前先打一条 `#log(.error, …)`。文件里已有 `NestedSpecializationLogging` 这个日志通道，subsystem 与 category 不变。

```diff
--- a/Sources/Declaration/SwiftSpecialization/TypeDefinition+Specialization.swift
+++ b/Sources/Declaration/SwiftSpecialization/TypeDefinition+Specialization.swift
@@ -222,12 +243,18 @@
         let unboundTypeName = try materializedTypeContext.typeName(in: machO.context)
         let finalTypeName: TypeName
         if let typeArgumentNodes, !typeArgumentNodes.isEmpty {
-            if let instantiation = try? GenericInstantiation(of: typeContextDescriptorWrapper, keyArguments: typeArgumentNodes, in: machO) {
+            do {
+                let instantiation = try GenericInstantiation(of: typeContextDescriptorWrapper, keyArguments: typeArgumentNodes, in: machO)
                 finalTypeName = TypeName(
                     node: InternedNodeReferenceCache.shared.reference(interning: instantiation.typeNode, in: machO),
                     kind: unboundTypeName.kind
                 )
-            } else {
+            } catch {
+                // The flat name is the name of no instantiation, so falling
+                // back to it is a degradation worth a trace: the header still
+                // prints the runtime's name, and the two now disagree.
+                let reason = (error as? LocalizedError)?.errorDescription ?? "\(error)"
+                #log(.error, "could not name the instantiation of \(unboundTypeName.name, privacy: .public) (\(reason, privacy: .public)); naming it with every argument on its innermost level")
                 finalTypeName = Self.boundGenericTypeName(
                     unboundTypeName: unboundTypeName,
                     typeArgumentNodes: typeArgumentNodes
```

### 13. thunk 类型构造器认不出泛型 extension 里的泛型类型（低，基线就有）

`Sources/Analysis/SwiftThunkAnalysis/Resolution/ThunkTypeNodeBuilder.swift:94`（`boundTypeNode`，以及它用的 `keyParameterCountsByNominalLevel`、`bound`）。

kind-9 accessor thunk 是编译器为某些字段生成的「取类型的小函数」，比如 `~Copyable` 的泛型类型，在不确定运行时支持的系统上就要先查询再实例化。本库会对它做符号执行，读出它调用了哪个类型的 accessor、传了哪些实参，再拼回类型名。

- **能复现吗**：能。`extension Outer where A: Hashable { struct Inner<B>: ~Copyable }` 的 accessor 收 `A` 和 `B` 两个实参，而构造器只数父链上的「类型层」各自声明了几个参数。extension 描述符的父上下文是模块，不是被扩展的 `Outer`，所以这条链上只有 `Inner` 一层、只数出 1 个，对不上就放弃。dump 打印 `var inner: accessor function at 2488`（0.21.0 实测，测试里是 `accessor function at 2608`）。没在真实框架里找到实例。
- **基线有没有**：有，2026-09-12 的 `1b1b60aa` 首版就是这样。它是 PR 在 `GenericArgumentEnvironment` 修掉的那个「extension 走不过去」在构造一侧的对应。
- **值不值得修**：值得。PR 新加的 `GenericParameterDepthLayout` 和 `SymbolicDemangler.instantiatedTypeNode` 正好能拼这种名字。但**不能整个替换掉旧逻辑**，见下面的修法。
- **以前修过吗**：没有。

**复现测试** `Tests/SwiftThunkAnalysisTests/AccessorThunkTypeInGenericExtensionTests.swift`（1 个测试），走的是索引器解析 kind-9 字段时用的同一个入口：

```swift
public struct Outer<A> {}
extension Outer where A: Hashable {
    public struct Inner<B>: ~Copyable { public var value: Int }
}
public struct Holder<T: Hashable, U>: ~Copyable {
    public var inner: Outer<T>.Inner<U>
}
```

修前：`fieldType → "accessor function at 2608"`。

**修法**：分两条路。

- 类型的**整个**泛型上下文里每个参数都带 key argument 时，thunk 传进来的实参正好一个参数一个：用 `GenericParameterDepthLayout` 分层，再用 `SymbolicDemangler.instantiatedTypeNode` 照运行时的规则拼名字，extension 上下文和被扩展的类型都能处理好。第 13 条的形状走这条路。
- 否则（有参数被 same-type 约束固定、运行时自己推出来而不是接收）照旧走原来的逻辑，一行不改。

**为什么不能整个替换**：这一版之前，我先试过直接删掉旧逻辑、遇到不带 key argument 的参数就放弃。复现测试和全量都过了，但实测发现它把一个本来能用的形状弄坏了：same-type 约束的 extension 里的类型（`extension SameTypeOuter where A == Int { struct Inner<B> }`）。thunk 只传 `B` 的实参；旧逻辑因为 extension 不算一层，正好对上个数，拼出的名字信息是完整的。三个 CLI 对同一个 fixture（`experiments/finding13b`）的 dump：

```
0.21.0：            var inner: (extension in ProbeThunkSameType):ProbeThunkSameType.Outer< where A == Swift.Int>.Inner<A>
PR 头：             var inner: (extension in ProbeThunkSameType):ProbeThunkSameType.Outer< where A == Swift.Int>.Inner<A>
整个替换的那一版：  var inner: accessor function at 2592
```

所以现在的修法只在新路径确实能处理时才用它，其余情况与 PR 头逐字相同；另加一条守护测试钉住这个形状（见下面的测试 diff）。旧逻辑在「extension 固定了一部分参数、另一部分仍要接收」的混合形状上本来就对不上个数、会放弃，这一点不变。

```diff
--- a/Sources/Analysis/SwiftThunkAnalysis/Resolution/ThunkTypeNodeBuilder.swift
+++ b/Sources/Analysis/SwiftThunkAnalysis/Resolution/ThunkTypeNodeBuilder.swift
@@ -19,9 +19,12 @@
 /// the existing substitution rewrites it into the concrete argument. A
 /// mangled name is demangled. A specialized accessor's symbol is demangled
 /// and the type it is the accessor *for* taken. And an accessor applied to
-/// arguments becomes the accessor's nominal type with a `boundGeneric*`
-/// wrapper per generic level of its declaration chain, the way the demangler
-/// itself spells `Outer<Int>.Inner<String>`.
+/// arguments becomes the accessor's type bound to them: named the way the
+/// runtime names the instantiation when they are one per parameter of the
+/// type's whole context — `Outer<Int>.Inner<String>`, an extension context
+/// and the type it extends included — and otherwise wrapped in a
+/// `boundGeneric*` node per generic level of its declaration chain, the way
+/// the demangler itself spells it.
 package struct ThunkTypeNodeBuilder: ThunkTypeNodeBuildingLogging {
     package let machO: MachOFile
     package let environment: MachOThunkEnvironment
@@ -91,17 +94,44 @@
         }
     }
 
+    /// The accessor's type bound to the arguments the thunk passed it.
+    ///
+    /// When every parameter of the type's whole generic context takes a key
+    /// argument, the arguments are one per parameter: grouped by
+    /// `GenericParameterDepthLayout`, they name the instantiation the way the
+    /// runtime does (`SymbolicDemangler.instantiatedTypeNode`). Both count
+    /// what the walk of the type contexts below misses — the parameters an
+    /// extension context brings (`extension Outer where A: Hashable { struct
+    /// Inner<B> }` takes `A` and `B`), which left such a type unnamed, its
+    /// field `accessor function at …`.
+    ///
+    /// Otherwise the walk of the type contexts binds each level's own key
+    /// parameters. It is what names a type in a same-type-constrained
+    /// extension — `extension Outer where A == Int { struct Inner<B> }`
+    /// receives the argument of `B` alone and reads
+    /// `Outer< where A == Swift.Int>.Inner<…>` — since an extension's
+    /// parameters are no type level of the walk.
     private func boundTypeNode(accessorAddress: UInt64, typeArguments: [ThunkTypeExpression]) -> Node? {
         guard let origin = environment.accessorOriginsByAddress[accessorAddress] else { return nil }
         do {
             let descriptor: ContextDescriptorWrapper = try ContextDescriptorWrapper.resolve(at: origin.descriptorOffset, in: origin.machO.context)
-            let unboundNode = try SymbolicDemangler.demangleContext(for: descriptor, in: origin.machO.context)
-            guard let keyParameterCountsByLevel = try keyParameterCountsByNominalLevel(of: descriptor, in: origin.machO) else { return nil }
             var argumentNodes: [Node] = []
             for typeArgument in typeArguments {
                 guard let argumentNode = typeNode(for: typeArgument) else { return nil }
                 argumentNodes.append(argumentNode)
             }
+            if let typeDescriptor = descriptor.typeContextDescriptorWrapper,
+               let genericContext = try typeDescriptor.genericContext(in: origin.machO.context),
+               genericContext.parameters.allSatisfy(\.hasKeyArgument) {
+                let depthLayout = GenericParameterDepthLayout.make(for: genericContext, ownedBy: descriptor, in: origin.machO.context)
+                guard let argumentsByDepth = depthLayout.grouped(argumentNodes) else {
+                    #log(.info, "accessor at 0x\(String(accessorAddress, radix: 16), privacy: .public) takes \(depthLayout.parameterCount, privacy: .public) type arguments, \(argumentNodes.count, privacy: .public) were named")
+                    return nil
+                }
+                return enveloped(try SymbolicDemangler.instantiatedTypeNode(for: typeDescriptor, binding: GenericArgumentBinding(argumentsByDepth: argumentsByDepth), in: origin.machO.context))
+            }
+            let unboundNode = try SymbolicDemangler.demangleContext(for: descriptor, in: origin.machO.context)
+            guard let keyParameterCountsByLevel = try keyParameterCountsByNominalLevel(of: descriptor, in: origin.machO) else { return nil }
             guard keyParameterCountsByLevel.reduce(0, +) == argumentNodes.count else {
                 #log(.info, "accessor at 0x\(String(accessorAddress, radix: 16), privacy: .public) takes \(keyParameterCountsByLevel.reduce(0, +), privacy: .public) type arguments, \(argumentNodes.count, privacy: .public) were named")
                 return nil
```

守护测试（加在同一个复现测试文件里，属于修法的一部分，所以只在沙盒里、不在 worktree 的复现测试里）：

```diff
--- a/Tests/SwiftThunkAnalysisTests/AccessorThunkTypeInGenericExtensionTests.swift
+++ b/Tests/SwiftThunkAnalysisTests/AccessorThunkTypeInGenericExtensionTests.swift
@@ -55,6 +55,18 @@
     public struct Holder<T: Hashable, U>: ~Copyable {
         public var inner: Outer<T>.Inner<U>
     }
+
+    public struct SameTypeOuter<A> {}
+
+    extension SameTypeOuter where A == Int {
+        public struct Inner<B>: ~Copyable {
+            public var value: Int
+        }
+    }
+
+    public struct SameTypeHolder<U>: ~Copyable {
+        public var inner: SameTypeOuter<Int>.Inner<U>
+    }
     """
 
     private static let fixtureCompilationResult: Result<URL, Error> = {
@@ -99,12 +111,13 @@
         }
     }
 
-    /// `Holder.inner`'s type, read through the entry the indexer uses for a
-    /// kind-9 field: the thunk's arguments named as `Holder`'s parameters.
-    private func resolvedInnerFieldType() throws -> String {
+    /// The `inner` field's type of the holder named `holderName`, read
+    /// through the entry the indexer uses for a kind-9 field: the thunk's
+    /// arguments named as the holder's parameters.
+    private func resolvedInnerFieldType(ofHolderNamed holderName: String) throws -> String {
         let machOFile = try loadFixture()
         let holder = try #require(
-            try machOFile.swift.typeContextDescriptors.first { try $0.namedContextDescriptor.name(in: machOFile.context) == "Holder" }
+            try machOFile.swift.typeContextDescriptors.first { try $0.namedContextDescriptor.name(in: machOFile.context) == holderName }
         )
         let genericContext = try #require(try holder.typeContextDescriptor.genericContext(in: machOFile.context))
         let ownerLayout = AccessorThunkOwnerLayout(
@@ -121,9 +134,22 @@
 
     @Test("a thunk instantiating a generic type declared in a generic extension is named")
     func thunkInstantiatingATypeInAGenericExtensionIsNamed() throws {
-        let fieldType = try resolvedInnerFieldType()
+        let fieldType = try resolvedInnerFieldType(ofHolderNamed: "Holder")
 
         #expect(!fieldType.contains("accessor function"), "\(fieldType)")
         #expect(fieldType.contains("Outer<A>") && fieldType.contains("Inner<B>"), "\(fieldType)")
     }
+
+    /// A type in a same-type-constrained extension receives the arguments of
+    /// its own parameters alone — the parameter the extension fixes takes no
+    /// key argument — and the walk of the type contexts names it. Naming the
+    /// instantiation from the whole context cannot, so it must not take over
+    /// there: doing so turned this field into `accessor function at …`.
+    @Test("a thunk instantiating a generic type declared in a same-type-constrained extension stays named")
+    func thunkInstantiatingATypeInASameTypeConstrainedExtensionStaysNamed() throws {
+        let fieldType = try resolvedInnerFieldType(ofHolderNamed: "SameTypeHolder")
+
+        #expect(!fieldType.contains("accessor function"), "\(fieldType)")
+        #expect(fieldType.contains("SameTypeOuter< where A == Swift.Int>.Inner<A>"), "\(fieldType)")
+    }
 }
```

两条测试在三个版本上的结果（证明守护测试确实能挡住那种改法，而不是怎么改都过）：

| 代码版本 | 第 13 条的复现测试 | 守护测试 |
|---|---|---|
| PR 头 | 失败（`accessor function at …`） | 通过 |
| 整个替换的那一版 | 通过 | 失败（`fieldType → "accessor function at 2712"`） |
| 现在的修法 | 通过 | 通过 |

**修后**：两条都通过：

```
fieldType → "(extension in ProbeThunkExtension):ProbeThunkExtension.Outer<A>.Inner<B>"
fieldType → "(extension in ProbeThunkExtension):ProbeThunkExtension.SameTypeOuter< where A == Swift.Int>.Inner<A>"
```

换成现在这版修法后重跑了全量（2354 个测试全过，见开头）；Xcodes 的 interface 与整个替换那一版逐字相同。

CLI dump，第 13 条的 fixture（`experiments/finding13`）：

```
0.21.0：  var inner: accessor function at 2488
PR 头：   var inner: accessor function at 2488
修后：    var inner: (extension in ProbeThunkExtension):ProbeThunkExtension.Outer<A>.Inner<B>
```

same-type 那个 fixture（`experiments/finding13b`）修后与 0.21.0、PR 头逐字相同：

```
var inner: (extension in ProbeThunkSameType):ProbeThunkSameType.Outer< where A == Swift.Int>.Inner<A>
```

**这一条给的教训**：整个替换的那一版，复现测试和全量（2353 个测试）都是绿的，回退是用 CLI 拿旧逻辑本来能处理的形状做对比才发现的。替换一段旧逻辑时，要专门找旧逻辑能处理、新逻辑放弃的输入去比，不能只看测试。

**落地时**：会改变 thunk 字段的输出，渲染 A/B 必跑。`Internal/Modules/SwiftThunkAnalysis.md` 里讲类型名拼法的地方同步。

### 14. 关联类型投影没有提前返回（低，性能，PR 引入）

`Sources/Output/SwiftDeclarationRendering/DependentMemberProjection.swift:131`，`Sources/Analysis/SwiftLayout/ImageUniverse+AssociatedTypeWitnessProjection.swift:92`。

- **能复现吗**：属实（读码）。每次调用都重新推断搜索路径（要列目录）、拿两把锁；第一次调用还要建整个依赖闭包，哪怕节点里根本没有关联类型成员。PR 无条件调用它：离线特化的每个字段、离线检查的每条约束、在线特化补固定参数时各一到三次。旧的 opaque 重写器调用前有 `isConcreteNominal` 前置检查，这里没有。
- **基线有没有**：PR 新代码。
- **值不值得修**：值得，一行。纯性能，没有可断言的行为，没写测试。
- **以前修过吗**：没有。

**修法**：两个入口开头各加一行，节点里没有 `dependentMemberType` 就原样返回（`contains(_:)` 是按种类做的整树搜索，正是这里要的语义）。

```diff
--- a/Sources/Output/SwiftDeclarationRendering/DependentMemberProjection.swift
+++ b/Sources/Output/SwiftDeclarationRendering/DependentMemberProjection.swift
@@ -129,6 +129,10 @@
     /// the reader is neither a file nor an in-process image, or the universe
     /// cannot be built.
     package static func projectingConcreteMembers<MachO: MachOSwiftSectionRepresentableWithCache>(in node: Node, in machO: MachO) -> Node {
+        // Nothing to project, so nothing to look up: no search-path inference
+        // (it lists directories), no lock, no dependency closure built — the
+        // first call used to build one even for a plain `Swift.Int`.
+        guard node.contains(.dependentMemberType) else { return node }
         if let machOFile = machO as? MachOFile {
             let registry = fileRegistries.storage(in: machOFile) { FileRegistry(root: $0) } ?? FileRegistry(root: machOFile)
             guard let entry = registry.entry(for: searchPaths(for: machOFile)) else { return node }
--- a/Sources/Analysis/SwiftLayout/ImageUniverse+AssociatedTypeWitnessProjection.swift
+++ b/Sources/Analysis/SwiftLayout/ImageUniverse+AssociatedTypeWitnessProjection.swift
@@ -90,6 +90,9 @@
     /// (`IndexingIterator`'s `Element` is `Elements.Element`), so a projection
     /// is projected again, a bounded number of hops deep.
     public func projectingConcreteMembers(in node: Node) -> Node {
+        // Most nodes name no member at all; they come back as they are,
+        // without a rebuilt copy of every node on the way.
+        guard node.contains(.dependentMemberType) else { return node }
         var rewrittenNodes: [ObjectIdentifier: Node] = [:]
         return projectingConcreteMembers(in: node, remainingHops: Self.maximumProjectionHops, rewrittenNodes: &rewrittenNodes)
     }
```

### 15. CI 覆盖（低，PR 引入）

`.github/workflows/macOS.yml:123`（主过滤列表）与 `:135`–`:149`（单线程协作线程池那一步，PR 加的说明从 `:135` 开始）。

- **属实**：
  - PR 把 `ConcurrentDefinitionPrintingTests` 加进「只给一个线程的协作线程池」那一步，想证明索引过程从不需要池线程。但 CI 上每次打印都跑在 `LargeStackTaskExecution.run` 里、用的是 swift-demangling 自己的线程，`LIBDISPATCH_COOPERATIVE_POOL_STRICT` 缩不到它们，所以这一步测不出它要防的问题。提案本地验证时关了执行器（`MACHO_SWIFT_SECTION_LARGE_STACK_EXECUTOR=0`），CI 没有。
  - 离线特化和层号相关的新套件一个都没进 CI 的过滤列表。
- **值不值得修**：值得。注意：这些套件**从没在 CI（Xcode 26.6）上跑过**，加进去可能暴露只在 CI 上出现的问题，那正是加的意义。
- **以前修过吗**：没有。仓库的 CI 一直只跑子集（有意为之），新套件通常会补进列表。

**修法**：主过滤列表补上 PR 和这批新加的套件（第 11 条那个依赖本机 cache 的除外）；另加一步，在单线程池且关掉大栈执行器的条件下单独跑并发打印测试。`ContinuousIntegrationTestFilterTests` 只要求列表里的名字都是真实存在的套件，满足。

```diff
--- a/.github/workflows/macOS.yml
+++ b/.github/workflows/macOS.yml
@@ -120,7 +120,7 @@
-            --filter '\.(…|ConcurrentDefinitionPrintingTests|NestedFieldOffsetMemoizationTests|NestedDefinitionRegionContractTests|ProtocolInExtensionTests)(/|$)'
+            --filter '\.(…|ConcurrentDefinitionPrintingTests|NestedFieldOffsetMemoizationTests|NestedDefinitionRegionContractTests|ProtocolInExtensionTests|OfflineSpecializationTests|OfflineSpecializationParityTests|InstantiatedTypeNameTests|CanonicalParameterDepthTests|GenericParameterDepthNamingTests|GenericParameterDepthDumpTests|BoundInstantiationLayoutTests|ExtensionContextInstantiationLayoutTests|AccessorThunkOwnerLayoutDepthTests|OpaqueTypeArgumentDepthTests|OfflineObjectiveCBaseClassTests|TiedParameterInstantiationTests|ProtocolInExtensionDefaultWitnessTests|OfflineConditionalConformanceTests|NestedFieldOffsetOpaqueWitnessTests|ConcurrentSpecializationTests|OpaqueParameterInMultiDepthExtensionTests|AccessorThunkTypeInGenericExtensionTests)(/|$)'
@@ -147,3 +147,22 @@
             --build-path .build-test-${{ matrix.configuration }} \
             --filter '\.(SharedCacheResolveTests|SharedCacheResolveSwiftConcurrencyTests|ConcurrentDefinitionPrintingTests)/' \
             --skip 'differentKeysParallelVia'
+
+      - name: Run the concurrent printing suite on a one-thread pool without the large-stack executor (${{ matrix.configuration }})
+        # The step above cannot catch an indexing pass that needs a pool
+        # thread: on this runner every print runs inside
+        # `LargeStackTaskExecution.run`, on the demangler's own threads, which
+        # the strict pool does not shrink. With the executor off, prints run
+        # on the cooperative pool itself — as they do below macOS 15 / iOS 18
+        # — and a pass that waited on pool work would hang here.
+        timeout-minutes: 5
+        env:
+          LIBDISPATCH_COOPERATIVE_POOL_STRICT: 1
+          MACHO_SWIFT_SECTION_LARGE_STACK_EXECUTOR: 0
+        run: |
+          swift test \
+            -c ${{ matrix.configuration }} \
+            --skip-build \
+            --enable-experimental-prebuilts \
+            --build-path .build-test-${{ matrix.configuration }} \
+            --filter '\.ConcurrentDefinitionPrintingTests/'
```

（过滤列表前半段没变，用 `…` 省略。）本地按新加这一步的条件（`LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`、`MACHO_SWIFT_SECTION_LARGE_STACK_EXECUTOR=0`）在修后沙盒里跑 `ConcurrentDefinitionPrintingTests`：3 个测试全部通过，用时约 13 秒（日志 `…/Logs/ReviewFixes/ci-step-strict-pool.log`）。CI 用的 Xcode 26.6 上没跑过。

## 二、建议离线模式接入前修

这两条只有离线特化才会走到，而 RuntimeViewer 目前还没有调用离线特化。修法已写好、已验证，可以和上一组一起合，也可以等离线模式接入时再合。

### 5. 带条件的协议遵循被当成成立（低，PR 引入）

`Sources/Declaration/SwiftSpecialization/GenericSpecializer+StaticSpecialization.swift:403`（`checkConformance`）。

- **能复现吗**：能。`doesType(_:conformTo:)` 只查按未绑定类型名记录的遵循表，条件被丢掉了。于是 `Inner<InnerElement: Hashable>` 的 `A1` 选「元素是 `FixtureUnmarked` 的 `Array`」时，`Hashable` 约束一个警告都没有，`specialize` 会拼出一个不可能存在的实例化；运行时路径会拒绝同样的选择。`staticPreflight` 的文档承诺这种情况给警告。
- **基线有没有**：丢条件是 2026-01-26 的 `25d3a8bb`（`ConformanceProvider` 第一版）以来的既有语义，在线的候选列表也因此会列出 `Array`；但在线最后由运行时核验，不会放行。离线检查把这条记录当成了证明，是 PR 引入的。
- **值不值得修**：值得，不急。
- **以前修过吗**：没有。

**复现测试** `Tests/SwiftSpecializationTests/OfflineConditionalConformanceTests.swift`（1 个测试，用 PR 的共享 fixture，不用改）。断言只要求「这个选择被标记出来」，给警告或报错都算，不预先限定修法。修前：零个警告、零个错误。

**修法**：索引器给每个协议遵循建的 conformance extension 都留着遵循描述符，`flags.numConditionalRequirements` 就是条件约束的个数，不用加新存储。给 `ConformanceProvider` 加一个默认返回 `false` 的 `isConditionalConformance(of:to:)`；离线检查遇到记录在案、但带条件的遵循时给警告。用绑定逐条检查这些条件，留作以后的增强。候选列表不动（它只是提示）。

`ConformanceProvider.swift` 的这几处改动与第 2 条落在同几个 hunk 里，这里只摘第 5 条的行；`@@` 后面括号里写的是它们在文件里的位置，真正的 hunk 头见第 2 条。

```diff
--- a/Sources/Declaration/SwiftSpecialization/ConformanceProvider.swift
+++ b/Sources/Declaration/SwiftSpecialization/ConformanceProvider.swift
@@ （协议 requirement，接在第 2 条的 superclassLink(of:) 之后）
+
+    /// Whether the conformance of `typeName` to `protocolName` that the
+    /// provider records holds only under conditions — `Array: Hashable where
+    /// Element: Hashable`. Such a record, kept under the type's unbound name,
+    /// proves nothing for one instantiation, so the offline check does not
+    /// take it for proof (evolution proposal `offline-generic-specialization`).
+    /// Default `false`: the record stands for the conformance, as
+    /// `doesType(_:conformTo:)` has always read it.
+    func isConditionalConformance(of typeName: TypeName, to protocolName: ProtocolName) -> Bool
 }
@@ （默认实现）
+
+    public func isConditionalConformance(of typeName: TypeName, to protocolName: ProtocolName) -> Bool {
+        false
+    }
 }
@@ （IndexerConformanceProvider）
+
+    /// Read off the conformance's own descriptor, which the conformance
+    /// extension the indexer built for it keeps: its conditional requirements
+    /// are counted in the flags.
+    public func isConditionalConformance(of typeName: TypeName, to protocolName: ProtocolName) -> Bool {
+        (indexer.allConformanceExtensionDefinitions[typeName.extensionName] ?? []).contains { entry in
+            entry.value.conformingProtocolName == protocolName
+                && (entry.value.protocolConformanceDescriptor?.flags.numConditionalRequirements ?? 0) > 0
+        }
+    }
@@ （CompositeConformanceProvider）
+
+    public func isConditionalConformance(of typeName: TypeName, to protocolName: ProtocolName) -> Bool {
+        providers.contains { $0.isConditionalConformance(of: typeName, to: protocolName) }
+    }
 }
--- a/Sources/Declaration/SwiftSpecialization/GenericSpecializer+StaticSpecialization.swift
+++ b/Sources/Declaration/SwiftSpecialization/GenericSpecializer+StaticSpecialization.swift
@@ -411,11 +411,22 @@
             ))
             return
         }
-        guard !conformanceProvider.doesType(typeName, conformTo: protocolName) else { return }
+        guard conformanceProvider.doesType(typeName, conformTo: protocolName) else {
+            builder.addWarning(.conformanceCheckFailed(
+                parameterName: subject.path,
+                protocolName: protocolName.name,
+                reason: "offline: the indexed images record no conformance of \(subject.display) to \(protocolName.name); a conformance in an image the indexer does not hold, a conditional one, or one the runtime synthesizes cannot be checked without the runtime"
+            ))
+            return
+        }
+        // The record is kept under the type's unbound name, so a conditional
+        // one says nothing about this instantiation: `[FixtureUnmarked]`
+        // passed `Hashable` on `Array`'s record, conditions and all.
+        guard conformanceProvider.isConditionalConformance(of: typeName, to: protocolName) else { return }
         builder.addWarning(.conformanceCheckFailed(
             parameterName: subject.path,
             protocolName: protocolName.name,
-            reason: "offline: the indexed images record no conformance of \(subject.display) to \(protocolName.name); a conformance in an image the indexer does not hold, a conditional one, or one the runtime synthesizes cannot be checked without the runtime"
+            reason: "offline: \(typeName.name) conforms to \(protocolName.name) only under conditions, which \(subject.display) may not meet; they cannot be checked without the runtime"
         ))
     }
```

**修后**：测试通过；`OfflineSpecializationTests` 里「记录在案的遵循不给警告」「投影后的成员遵循」等测试不变（`Array: Sequence`、`Int: Hashable` 都不带条件）。

同一个选择现在给一条警告：

```
Conformance check for parameter 'A1' against protocol 'Swift.Hashable' failed to run: offline: Swift.Array conforms to Swift.Hashable only under conditions, which [GenericSpecializationFixture.FixtureUnmarked] may not meet; they cannot be checked without the runtime
```

### 11. 字段类型与布局注释读的是两套镜像（低，机制旧，PR 扩大）

`Sources/Output/SwiftDeclarationRendering/StaticSpecializationNodeSubstitution.swift`、`DependentMemberProjection.swift:75`（`searchPaths(for:)`）、`SwiftDeclarationPrinter+Headers.swift:459`。

- **能复现吗**：能，只在有归档 iOS 模拟器 cache 的机器上。离线特化一个 iOS 模拟器二进制、打印时配置 iOS 模拟器 cache：

  ```
  // Type Layout: (size: 9, stride: 16, alignment: 8, extraInhabitantCount: 0)
  var first: [Int].Element?
  ```

  布局注释是按 `Int?` 算的（`size: 9`），字段类型却还是 `[Int].Element?`。原因是关联类型投影用的搜索路径来自 thunk 解析器或「文件所在位置推断 + 宿主 cache」，不看打印配置的 `staticLayoutDependencyResolution`；而宿主的 macOS 镜像对 iOS 二进制从来不是候选。离线约束检查也用同一套路径，所以一条被违反的 `where A.Element == B` 会被降成警告。
- **基线有没有**：这套路径是 2026-09-18 的 `72b5c5f6` 给 opaque 成员投影写的；PR 把它用到了字段类型和约束检查上。
- **值不值得修**：值得，不急，只影响跨平台的离线特化。
- **以前修过吗**：没有。

**复现测试** `Tests/SwiftSpecializationTests/OfflineProjectionDependencyResolutionTests.swift`（1 个测试）：编一个 `-target arm64-apple-ios17.0-simulator` 的 fixture（`ElementsHolder<Elements: Collection>`），离线特化成 `ElementsHolder<[Int]>`，打印时 `staticLayoutDependencyResolution = .dependencyClosure(searchPaths: [.dyldSharedCache(path: "/Volumes/DyldSharedCaches/iOS-Simulator/27.0/dyld_sim_shared_cache_arm64")])`。套件带 `.enabled(if:)`，没有这个 cache 的机器（包括 CI）会跳过。

**修法**：给 `StaticFieldLayoutProvider` 加一个默认返回 `nil` 的投影方法；`MachOFileStaticFieldLayoutProvider` 用自己那份按打印配置建好的依赖闭包来投影（为此 `StaticLayoutCalculator` 开一个公开的 `projectingConcreteMembers(in:)`，它的镜像集合原本是模块内可见）。打印字段时优先用它，没有 provider（没开布局注释）才退回原来的路径。特化器的 `staticPreflight` 没有打印配置，保持现状，写进文档。

```diff
--- a/Sources/Analysis/SwiftLayout/StaticLayoutCalculator.swift
+++ b/Sources/Analysis/SwiftLayout/StaticLayoutCalculator.swift
@@ -145,6 +145,14 @@
     }
 
     // MARK: - Instantiations bound by a binding (evolution proposal `offline-generic-specialization`)
+
+    /// `node` with every member of a concrete type projected through the
+    /// witness records of this calculator's images — the images its layouts
+    /// are computed over, so a field type projected here and the layout
+    /// printed beside it read the same records.
+    public func projectingConcreteMembers(in node: Node) -> Node {
+        imageUniverse.projectingConcreteMembers(in: node)
+    }
 
     /// The per-field layout of the instantiation `binding` makes of
     /// `typeDescriptor` — every depth of its generic signature bound, so a
--- a/Sources/Output/SwiftDeclarationRendering/StaticFieldLayoutProvider.swift
+++ b/Sources/Output/SwiftDeclarationRendering/StaticFieldLayoutProvider.swift
@@ -4,6 +4,7 @@
 import MachOSwiftSection
 import MachOFoundation
 import SwiftLayout
+import Demangling
 @_spi(Internals) import SwiftInspection
 
 /// How the static (MachOFile) field-layout path resolves field / superclass /
@@ -85,9 +86,21 @@
     /// The expanded nested-field-offset tree for a field type of the
     /// instantiation `binding` describes.
     func nestedFieldOffsetTree(forMangledTypeName mangledTypeName: MangledName, baseOffset: Int, depthLimit: Int, genericArgumentBinding binding: GenericArgumentBinding) -> [NestedFieldOffset]
+
+    /// `node` with every member of a concrete type projected through the
+    /// witness records of the images the layouts above are computed over —
+    /// `[Swift.Int].Element` read as `Swift.Int` — so a field's printed type
+    /// and the layout printed beside it come from the same images. `nil`
+    /// when the provider has no images of its own: the caller projects
+    /// through its own.
+    func projectingConcreteMembers(in node: Node) -> Node?
 }
 
 extension StaticFieldLayoutProvider {
+    public func projectingConcreteMembers(in node: Node) -> Node? {
+        nil
+    }
+
     public func aggregateFieldLayout(forDescriptor descriptor: TypeContextDescriptorWrapper, genericArgumentBinding binding: GenericArgumentBinding) -> AggregateFieldLayout? {
         nil
     }
@@ -190,4 +203,10 @@
         defer { lock.unlock() }
         return calculator.nestedFieldOffsetTree(forMangledTypeName: mangledTypeName, baseOffset: baseOffset, depthLimit: depthLimit, genericArgumentBinding: binding)
     }
+
+    public func projectingConcreteMembers(in node: Node) -> Node? {
+        lock.lock()
+        defer { lock.unlock() }
+        return calculator.projectingConcreteMembers(in: node)
+    }
 }
--- a/Sources/Output/SwiftDeclarationRendering/StaticSpecializationNodeSubstitution.swift
+++ b/Sources/Output/SwiftDeclarationRendering/StaticSpecializationNodeSubstitution.swift
@@ -14,12 +14,23 @@
 /// from. A member no record answers keeps its spelling.
 package enum StaticSpecializationNodeSubstitution {
     /// `typeNode` — a field's or an enum payload's declared type — with
-    /// `binding`'s arguments substituted and concrete members projected.
+    /// `binding`'s arguments substituted and concrete members projected:
+    /// through the images `staticFieldLayoutProvider` computes the layout
+    /// comments over, when the print has one, so the type and its layout agree
+    /// — an iOS binary printed against an iOS cache used to have its layout
+    /// computed while its field kept `[Swift.Int].Element?`, the host's macOS
+    /// images being no candidates for an iOS root. Without a provider (no
+    /// layout comment printed) through the images the opaque rewriter uses.
     package static func substitutedTypeNode<MachO: MachOSwiftSectionRepresentableWithCache>(
         of typeNode: Node,
         binding: GenericArgumentBinding,
+        staticFieldLayoutProvider: (any StaticFieldLayoutProvider)?,
         in machO: MachO
     ) -> Node {
-        DependentMemberProjection.projectingConcreteMembers(in: binding.substituting(in: typeNode), in: machO)
+        let substitutedNode = binding.substituting(in: typeNode)
+        if let projectedNode = staticFieldLayoutProvider?.projectingConcreteMembers(in: substitutedNode) {
+            return projectedNode
+        }
+        return DependentMemberProjection.projectingConcreteMembers(in: substitutedNode, in: machO)
     }
 }
--- a/Sources/Output/SwiftPrinting/SwiftDeclarationPrinter+Headers.swift
+++ b/Sources/Output/SwiftPrinting/SwiftDeclarationPrinter+Headers.swift
@@ -456,7 +456,12 @@
             }
             let substitutedTypeNode: Node? = {
                 if let staticSpecialization {
-                    return StaticSpecializationNodeSubstitution.substitutedTypeNode(of: field.typeNode.materialize(), binding: staticSpecialization, in: machO)
+                    return StaticSpecializationNodeSubstitution.substitutedTypeNode(
+                        of: field.typeNode.materialize(),
+                        binding: staticSpecialization,
+                        staticFieldLayoutProvider: renderConfiguration.staticFieldLayoutProvider,
+                        in: machO
+                    )
                 }
                 guard let specializedMetadata, let specializedMachOImage, let mangledTypeName else { return nil }
                 return SpecializedMetadataNodeSubstitution.substitutedFieldTypeNode(for: mangledTypeName, metadata: specializedMetadata, in: specializedMachOImage)
```

**修后**：测试通过。字段类型与布局注释现在出自同一套镜像：

```swift
struct SimulatorProjectionFixture.ElementsHolder<[Swift.Int]> {
    // Type Layout: (size: 8, stride: 8, alignment: 8, extraInhabitantCount: 2147483647)
    var elements: [Swift.Int]
    // Type Layout: (size: 9, stride: 16, alignment: 8, extraInhabitantCount: 0)
    var first: Swift.Int?
}
```

**落地时**：`StaticFieldLayoutProvider` 多了一个带默认实现的 requirement，`StaticLayoutCalculator` 多了一个公开方法，进发版说明；`Internal/OfflineGenericSpecialization.md` 写明「打印时投影走打印配置的依赖闭包，`staticPreflight` 仍走默认路径」。

## 三、不修，登记

拟写入 [ReviewAdjudications.md](../Documentations/Internal/ReviewAdjudications.md)（从 A53 起编号），落地批次一起写。

### 9. 等待索引时的优先级反转（低）

`Sources/Declaration/SwiftDeclaration/Components/Definitions/DefinitionIndexing.swift:84`。

- **属实**（机制）：等待用的是 `SharedCacheBuildPromise.wait()`，底层是 NSCondition；前台打印等后台 utility 线程跑完某个定义的索引时，不会把自己的 QoS（线程调度优先级）借给它。RuntimeViewer 的语料在 `.utility` 优先级上建，用户恰好点开语料正在索引的类型时就会等。通常只差毫秒级，没实测。
- **基线**：PR 新引入（以前各自索引各自的，但那是数据竞争）。`SharedCache` 的并发构建用的是同一个 promise，一直是同样的取舍。
- **裁决**：不修。复审条件：RuntimeViewer 出现能感觉到的点开延迟。
- **真要修**：在 `SharedCacheBuildPromise` 里记下构建线程，等待前用 `pthread_override_qos_class_start_np` 把等待者的优先级借给它，等完 `_end_np`。要处理构建线程在等待开始前已经结束的情况（`pthread_t` 失效），这是没现在就做的另一个原因。`SharedCache` 会一起受益。没写 diff。

### 12. 嵌套偏移缓存会记住「解析失败」（低，PR 有意如此）

- **属实**（设计如此）：进程级的嵌套偏移缓存按 metatype 记录每一层，「这个字段类型解析不出」也会被记住；宿主之后加载了定义那个类型的镜像，缓存仍说解析不出。提案里已写明「近乎理论」，review 也没在 AppKit、SwiftUI、WebKit、Xcode IDE 框架里找到实例。本库提供了 `RuntimeFieldLayoutMemo.removeAll()`，由宿主在加载镜像后调用。
- **裁决**：本库不修。
- **转 RuntimeViewer**：它的 find-navigator 分支只在自己 `dlopen` 之后（`DyldUtilities.loadImage(at:)`）调用 `removeAll()`；被检查的进程自己加载的镜像不会触发。`DyldUtilities.observeDyldRegisterEvents()` 写了 dyld 加载镜像的回调，但从没被调用。那边要注册这个回调，并在回调里调用 `removeAll()`。

## 四、顺带项（review 因条数上限砍掉的）

| 项 | 结论 | 处置 |
|---|---|---|
| swift-semantic-string 构建阻塞 | `DefinitionRegion` 只在它的 `next` 上，`Package.swift` 下限仍是 `from: "0.4.0"`；`next` 分支没有 CI 门禁，现在合并不会被拦，但合完后按远程版本解析的 `next` 编不过 | PR 描述里已列为合并前的阻碍：先给 swift-semantic-string 发版、再抬下限 |
| 缩写命名 | PR 重写过的几行里有 `param`、`paramName`、`protocolRef`、`swiftProto`、`proto`，新文件里有 `info`；大多是旧代码挪行带过来的 | 只改这几行，diff 见下；`GenericSpecializer.swift` 其余旧代码里的缩写（含公开错误类型的关联值标签）不在本次范围 |
| `ProtocolInExtensionTests` 编 fixture 没写语言模式 | 它不输出 module interface，Swift 6.4 不会报错，只是稳健性 | 补 `-swift-version 5`，diff 见下 |
| 嵌套 `.boundGeneric` 实参链的请求次数随深度平方增长 | 属实，深度 d 时约 d(d+3)/2 次；实际嵌套很浅 | 不修，登记 |
| 测试 fixture 的共享索引器在并行套件下会重复构建 | 只影响测试耗时 | 不修，登记 |
| 离线 `specialize(with:in:)` 只比较描述符偏移 | 拿另一个文件里偏移恰好相同的结果也会被接受；只有误用 API 才会碰到 | 不修，登记；以后可让结果带上镜像身份 |

缩写改名的 diff（只动 PR 重写过的行）：

```diff
--- a/Sources/Declaration/SwiftSpecialization/GenericSpecializer.swift
+++ b/Sources/Declaration/SwiftSpecialization/GenericSpecializer.swift
@@ -205,25 +205,25 @@
-        for (flatIndex, param) in cumulativeParameters.enumerated() {
+        for (flatIndex, parameter) in cumulativeParameters.enumerated() {
             // Skip non-key parameters (type packs, values, etc.)
-            guard param.hasKeyArgument, param.kind == .type else { continue }
+            guard parameter.hasKeyArgument, parameter.kind == .type else { continue }
             guard let position = depthLayout.position(ofParameterAt: flatIndex) else { continue }
 
             // Get parameter name based on depth and per-level index
             // (e.g., A, B, A1, B1, A2...).
-            let paramName = genericParameterName(depth: position.depth.cast(), index: position.index.cast())
+            let parameterName = genericParameterName(depth: position.depth.cast(), index: position.index.cast())
 
             // Collect requirements for this parameter (ordered for PWT passing)
             let requirements = try collectRequirements(
-                for: paramName,
+                for: parameterName,
                 from: mergedRequirements
             )
 
             // Find candidate types that satisfy all protocol requirements
             let protocolRequirements = requirements.compactMap { requirement -> ProtocolName? in
-                if case .protocol(let info) = requirement {
-                    return info.protocolName
+                if case .protocol(let protocolRequirement) = requirement {
+                    return protocolRequirement.protocolName
                 }
                 return nil
             }
@@ -250,7 +250,7 @@
             parameters.append(SpecializationRequest.Parameter(
-                name: paramName,
+                name: parameterName,
                 index: position.index,
@@ -385,17 +385,17 @@
-            guard case .protocol(let protocolRef) = resolvedContent else {
+            guard case .protocol(let protocolReference) = resolvedContent else {
                 return nil
             }
 
             // Try to get protocol name
             let protocolName: ProtocolName
-            switch protocolRef {
+            switch protocolReference {
             case .element(let resolved):
-                guard let swiftProto = resolved.swift else { return nil }
-                let proto = try MachOSwiftSection.`Protocol`(descriptor: swiftProto, in: machO.context)
-                protocolName = try proto.protocolName(in: machO.context)
+                guard let swiftProtocolDescriptor = resolved.swift else { return nil }
+                let protocolWrapper = try MachOSwiftSection.`Protocol`(descriptor: swiftProtocolDescriptor, in: machO.context)
+                protocolName = try protocolWrapper.protocolName(in: machO.context)
--- a/Sources/Declaration/SwiftSpecialization/GenericSpecializer+StaticSpecialization.swift
+++ b/Sources/Declaration/SwiftSpecialization/GenericSpecializer+StaticSpecialization.swift
@@ -401,8 +401,8 @@
     private func checkConformance(of subject: StaticRequirementSubject, to requirement: GenericRequirementDescriptor, into builder: SpecializationValidation.Builder) {
-        guard let builtRequirement = try? buildRequirement(from: requirement), case .protocol(let info) = builtRequirement else { return }
-        let protocolName = info.protocolName
+        guard let builtRequirement = try? buildRequirement(from: requirement), case .protocol(let protocolRequirement) = builtRequirement else { return }
+        let protocolName = protocolRequirement.protocolName
--- a/Tests/SwiftInterfaceTests/ProtocolInExtensionTests.swift
+++ b/Tests/SwiftInterfaceTests/ProtocolInExtensionTests.swift
@@ -50,7 +50,7 @@
             try run(swiftcArguments: [
-                "-O", "-emit-library", "-module-name", "ProbeProtocolInExtension",
+                "-swift-version", "5", "-O", "-emit-library", "-module-name", "ProbeProtocolInExtension",
```

## 五、落地清单

决定修哪几条之后：

1. **每条修复连同它的复现测试同一批提交**；不修的条目把对应测试删掉（或留作 `withKnownIssue`，由用户定），并写进已裁决清单。第 3 条的测试依赖共享 fixture 里新加的 `TiedParameterPair`，两者一起进或一起退。第 13 条的守护测试是修法的一部分，随修法一起进。
2. **渲染 A/B 必跑**（AGENTS.md 对动到打印和索引的改动的要求）。会改变既有输出的是第 1 条（普通 SwiftUI app 的 opaque 类型实参）、第 4 条（extension 里协议的默认实现块）、第 6 条（静态展开偏移里 opaque 实际类型那一行）、第 8 条（带 provider 的 interface）、第 13 条（kind-9 字段名）。PR 本身在 rebase 和合并 `next` 后也还没重跑 A/B。
3. **文档同批**：
   - 演进账本补一节。
   - `draft-concurrent-definition-printing` 决策日志：第 7 条（前提更正、加锁）、第 9 条（登记）。
   - `draft-offline-generic-specialization` 决策日志与 `Internal/OfflineGenericSpecialization.md`：第 2、3、5、10、11 条。
   - `draft-nested-definition-regions` 决策日志：第 4 条。
   - `Internal/OpaqueReturnTypeResolution.md`：第 1、8 条。
   - `Internal/Modules/SwiftThunkAnalysis.md`：第 13 条。
   - AGENTS.md 的 `specialize(...)` 那句（diff 见第 7 条）。
   - AGENTS.md「Work in progress」那段的「Five readers once counted ancestors」改成八处。
4. **发版说明（0.22.0）**：
   - 新增：`ConformanceProvider` 的两个带默认实现的 requirement（`superclassLink(of:)`、`isConditionalConformance(of:to:)`）和公开枚举 `SuperclassLink`；`StaticFieldLayoutProvider.projectingConcreteMembers(in:)`；`StaticLayoutCalculator.projectingConcreteMembers(in:)`。
   - 行为变化：opaque 类型实参按描述符的层结构分组；离线基类检查对 ObjC 中间类给警告；带条件的遵循给警告。
5. **转告 RuntimeViewer**：第 4 条（读默认实现列表前先索引协议）、第 7 条（库修后，`specialize` 可以照常在 actor 外跑）、第 12 条（加载镜像后清缓存）。
6. **另开一项**：`MachOFile` 与 `DyldCache` 懒创建文件句柄的那四处无锁关联对象（见第 7 条的横向排查）。

## 六、落地记录（2026-10-08）

落地在 JHs-Mac-Studio 上做：复现测试、review 记录和完整补丁都只在 Ultra 上、没有推送，经 ssh 只读地取回，在同一个基线 `beae202d` 上打上补丁（`git apply --check` 干净）。

**提交**（每条修复连同它的复现测试一个 commit，按顺序）：

| commit | 条目 |
|---|---|
| `4661eb42` | 第 1 条：opaque 类型的实参按描述符的层结构分组 |
| `c8cf653d` | 第 8 条：opaque provider 从所在类型或 extension 取层数 |
| `7d7ffd41` | 第 13 条：泛型 extension 里的类型由 thunk 拼出名字（含守护测试） |
| `ad4f33b3` | 第 2 条：离线父类检查沿父类链往上走 |
| `6c35e8c4` | 第 3、10 条：「参数 == 参数」的约束补参数；退回扁平名时记日志 |
| `d1a47dfb` | 第 4 条：读默认实现列表前先索引协议 |
| `d2f8d586` | 第 5 条：带条件的遵循给警告 |
| `2d58a451` | 第 6 条：投影出的实际类型是 opaque 时保留成员名 |
| `f5266e30` | 第 7 条：`specializedChildren` 加锁 |
| `5308fa1a` | 第 11 条：字段类型经打印配置的依赖闭包投影 |
| `de14e727` | 第 14 条：没有关联类型成员的节点不做投影 |
| `4e8f4a7f` | 第四节的两个顺带项：缩写改名、`ProtocolInExtensionTests` 补 `-swift-version 5` |
| `07993a5f` | 落地清单第 6 项：`MachOFile` / `DyldCache` 的文件映射和句柄持锁创建、只存一次 |
| `f108d5e6` | 第 15 条：CI 过滤列表与单线程池、关大栈执行器的一步 |

文档（本记录、已裁决清单 A53–A59、四份提案的决策日志、实现说明、演进账本）在随后的文档提交里。

**落地清单第 6 项改为本批就修**：全局规则要求确认为真的问题连同类一起修。查到它可达——`FullDyldCache` 把同一批子 cache 实例交给所有镜像，`FullDyldCache.cachedHost` 是进程级单例，`diff` 与 `evolution` 并行准备几个输入、各自经依赖查找读宿主 cache 时，会同时第一次读同一个子 cache。新测试 `ConcurrentFileMappingTests`（`MachOSwiftSectionTests`）每轮新建一个实例，让 32 个线程同时做第一次读取，每个 getter 跑 20 轮：修前四个 getter 都失败，20 轮里有 12 到 19 轮，32 个读者拿到 2 到 7 个不同的对象；修后每轮都只有一个。`MachOFile` 那两处只在同一个文件被并发读时才会撞上（`MachOFile` 读者本来就不承诺并发），修法一样、热路径不变，一并改了。

**本机验证**（Xcode 26.6、Swift 6.3.3，也就是 CI 的工具链；Ultra 上用的是 Swift 6.4）。沙盒 `/Volumes/DerivedData/Agents.noindex/claude/Sandboxes/FindNavigatorReviewFixes/MachOSwiftSection` 只链 swift-semantic-string，其余依赖钉到与 Ultra 相同的版本（MachOKit 0.54.101、MachOKitExtensions 1.1.2、MachOObjCSection 0.8.109、swift-demangling 0.7.1）；fixture 按 CI 的做法 ad-hoc 签名重编。日志在 `/Volumes/DerivedData/Agents.noindex/claude/Sandboxes/FindNavigatorReviewFixes/Logs/`。

- 修前（PR 头的源码 + 全部测试）：10 个复现套件（含 `ConcurrentFileMappingTests`）全部失败，`OfflineProjectionDependencyResolutionTests` 跳过（见下），原始退出码 1；第 13 条的守护测试照常通过。`repro-suites-baseline.log`。
- 修后：同样这些套件的 19 个测试里 18 个通过、第 11 条那个跳过，原始退出码 0。`repro-suites-final.log`。
- `OfflineProjectionDependencyResolutionTests` 在上面两轮里都跳过：本机没有 `/Volumes/DyldSharedCaches/iOS-Simulator/27.0`。另在沙盒副本里把它的路径临时改指本机装的 iOS 27.0 模拟器 runtime（`/Library/Developer/CoreSimulator/Volumes/iOS_24A434/…/dyld_sim_shared_cache_arm64`），PR 头上失败（字段仍是 `[Int].Element?`）、修后通过。`environment-check-baseline.log`、`environment-check-final.log`。
- 全量 `swift test --skip IntegrationTests`：2358 个测试、448 个套件（Ultra 上的 2354 / 447 加上新的 `ConcurrentFileMappingTests`），原始退出码 1。失败的只有 `MultiPayloadEnumDescriptorCacheTests` 的 `everyFixtureMultiPayloadEnumRendersALayout` 与 `noncopyableMultiPayloadEnumLaysOutFromItsResolvedPayloads`：换回 PR 头的源码，在同一个沙盒、同一份 fixture 上同样两条在同样位置（`:101`、`:130`）失败，是这台机器上早就有的环境问题，`next` 上也是这样（进程内 enum 布局，这批改动不碰）。另有早已登记的 known issue（`SymbolicManglingIndexTests`）。`full-suite-final.log`。
- 渲染 A/B：基线 `beae202d`，候选 `f108d5e6`（这批代码提交的末尾），两侧都是 `git archive` 出来的沙盒、只链 swift-semantic-string、共用同一份 `Package.resolved`，经构建队列预构建 release 后带 `--skip-build --no-baseline-cache --jobs 3` 跑。**90 对全部逐字节一致**：归档 cache 15.5 与 26.6.2 各 12 对，iOS 15.5 / 18.5 / 18.6 / 26.5 模拟器 42 对，MachOImage 腿 24 对；iOS 27.0 模拟器的框架在 cache 里、不是文件，按设计跳过。输出在 `/Volumes/DerivedData/Agents.noindex/claude/Sandboxes/FindNavigatorReviewAB/Output/`，日志 `…/FindNavigatorReviewAB/Logs/ab-run.log`。落地清单第 2 项列出的会改变输出的几条，在这些框架与选项组合里都没有触发；第 1 条另用两侧 CLI 对本机 `/Applications/Xcodes.app` 复核：11599 行的 interface 只有两行不同（第 4308、4895 行），都是 `TupleToolbarContent<A>` 补上了实参，与第 1 条「修后」一节在 Ultra 上看到的一致（那边是 11603 行，宿主不同）；补出来的类型里露出的 5 处 `accessor function at` 就是那一节说的既有限制。

**还没做的**：RuntimeViewer 那边的三件事（落地清单第 5 项）还没转告；PR #131 的描述里的发版说明还没按上面第 4 项更新；推送等用户确认。另外 PR 现在与 `next` 冲突：`next` 在 `433f1421` 之后合进了两个修复，并要求 MachOObjCSection 0.8.110，要再把 `next` 合进分支一次。
