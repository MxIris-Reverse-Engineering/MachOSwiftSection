# PR #135 review findings（协议约束可选写在各自的关联类型上，2026-10-21）

`/code-review high` 对 PR #135（`feature/protocol-requirement-placement` → `next`，PR 头 `07016c07`，基线 `7d181357`；提案 [0073-protocol-requirement-placement](../Documentations/Evolutions/0073-protocol-requirement-placement.md)）给出 8 条发现。这份记录逐条按四问（能否复现 / 基线有没有 / 值不值得修 / 以前修过没有）裁决。

**结论**：没有会把输出印错的问题。只有第 1 条要改，而且只改文档措辞，另往 fixture 加了一个协议，用测试把文档说的规则固定下来；第 2–8 条是误报、有意设计或成本可以忽略，登记在 [ReviewAdjudications.md](../Documentations/Internal/ReviewAdjudications.md) A69–A75。已裁决清单 A1–A68 里没有覆盖这 8 条的条目，第 4、5、6 条各有同类先例（A26、A3、A45）。

**当前状态**：已落地（2026-10-21）。用户批准按这份结论修完后直接合并：第 1 条的修正是 `5c3da04b`，与这份记录、提案落地一起随 PR #135 合入 `next`。

## 总表

| # | 问题 | 从哪来 | 裁决 |
|---|---|---|---|
| 1 | 公开文档把约束归位的规则说宽了 | PR 引入 | 修（只改措辞，加测试） |
| 2 | 两个新套件进了 CI 名单，却只在 Xcode 27 上跑过 | PR 引入 | 误报（CI 的工具链上实跑通过），A69 |
| 3 | `SwiftDumpConformance` 被当普通文字印出 | 基线既有 | 误报（走不到），A70 |
| 4 | 默认写法下每个协议多读一次关联类型名 | PR 引入 | 不修（可以忽略），A71 |
| 5 | 开关打开时每条约束的主语 demangle 两次 | PR 引入 | 部分误报，不修，A72 |
| 6 | 现场编译 fixture 的辅助代码又复制了一份 | 基线既有 | 本 PR 不修，另做重构，A73 |
| 7 | 继承子句的拼写循环有三份 | 基线既有，PR 加一份 | 有意设计，不修，A74 |
| 8 | diff / evolution 的协议头手工传入「约束全留在协议上」 | PR 引入 | 有意设计，不修，A75 |

## 1. 公开文档把约束归位的规则说宽了（修）

`Sources/Output/SwiftPrinting/SwiftDeclarationPrintConfiguration.swift:45-48`，`ProtocolRequirementPlacement.associatedTypes` 的文档注释。

- **能复现吗**：能，但只是文档与实现对不上，输出没错。原文说「any other requirement mentioning `Self.Item` goes into its `where` clause」，实现对 conformance、superclass、layout 约束只看主语（`ProtocolRequirementPartition.location(of:among:in:)`）。例如：

  ```swift
  protocol SubjectOnlyRequirements: Sequence where Element: GenericBase<First> {
      associatedtype First
  }
  ```

  `Self.Element: GenericBase<Self.First>` 提到了 `Self.First`，却留在协议的 `where` 子句，不挪到 `First` 上。
- **基线有没有**：新代码，`next` 上没有。
- **值不值得修**：修，只改措辞。实现本身是对的：提案的规则就是「只看主语，same-type 约束两边都看」，编译器自己也这么摆（`swift/lib/AST/ASTPrinter.cpp` 的 `bestRequirementPrintLocation`：conformance、superclass、layout 只看 `req.getFirstType()`，same-type 两边都看）。同样宽泛的说法还在 ProjectEvolutionLog 本节的「关键决策 ①」和 PR 描述里，三处一起改。CLI 的 `--help`、agent 插件的 skill、提案正文的说法没有问题。
- **以前修过吗**：本 PR 新写，没有。
- **横向排查**：说同一条规则的地方逐个看过：提案「摆放规则」、`ProtocolRequirementPartition` 的文档注释、fixture 与测试的注释、CLI 的 `--help`、agent 插件的 skill 都写的是「只看主语」或没有细到这一层，不用改。

**修法**：

- 文档注释改成逐类说清：conformance、superclass、layout 约束只看主语，主语恰好是 `Self.Item` 进继承子句，主语是从 `Item` 起头的成员链进 `Item` 的 `where` 子句，主语与本协议的关联类型无关就留在协议上，即使父类提到了它；same-type 约束进任一边所关于的关联类型的 `where` 子句，恰好是 `Self.Item` 的那一边优先；inverse 与 same-shape 留在协议上。
- ProjectEvolutionLog 本节「关键决策 ①」同样改写；PR 描述的「Where a requirement prints」一段同样改写。
- `ProtocolRequirementPlacementFixture` 加 `SubjectOnlyRequirements`（就是上面的例子），`ProtocolRequirementPlacementInterfaceTests` 的 `placementCases` 加一条期望：`.associatedTypes` 写法下这条约束仍在协议头。参数化在 `protocolNames` 上的三个测试（默认写法不带约束、往返编译、diff 协议头）也自动覆盖了它。

这条修的是文档，不是代码，所以新测试在修前也是绿的。为证明它确实钉住了「只看主语」，在沙盒副本里临时把 superclass 约束改成也看右侧（文档原先的说法），新测试按预期变红，见文末「验证」。

## 2. 两个新套件进了 CI 名单，却只在 Xcode 27 上跑过（误报，A69）

`.github/workflows/macOS.yml:123`。

- **能复现吗**：不能。PR 自己的验证只用了 Xcode 27.0（Swift 6.4）：当天 github.com 连不上，依赖是拷来的一份只有 Swift 6.4 认的解析。这次在 `git archive` 出来的 PR 头副本里，用 `/Applications/Xcode.app`（Xcode 26.6，Swift 6.3.3，与 CI 相同）从远端重新解析依赖，跑两个新套件和 PR 改过的 `DumpAndInterfaceRequestTests`、`CommandRequestMappingTests`：4 个套件 45 个测试全部通过，原始退出码 0。只跑了 debug，CI 还会跑 release。
- **基线有没有**：新加的套件。
- **影响**：合进 `next` 的 PR 不跑 CI，真有问题也要到下次发版合进 `main` 时才暴露，所以值得在本机先用 CI 的工具链跑一遍。
- **以前修过吗**：出过同类问题：`a2725835` 修的是换了工具链后一个现场编译 fixture 的测试全红，修法是固定语言模式。本 PR 的 fixture 从一开始就带 `-swift-version 5`。

## 3. `SwiftDumpConformance` 被当普通文字印出（误报，A70）

`Sources/Output/SwiftDeclarationRendering/Extensions/GenericContext+Dump.swift:364`。

- **能复现吗**：构造不出来。这类内容只来自 SameConformance 约束（「两个 conformance 必须相同」），编译器的 IRGen 从不发出它，运行时遇到它也只是标着 `FIXME` 跳过（`ProtocolConformance.cpp:1906`、`:2062`）。就算出现，划分也把它留在协议的 `where` 子句，进不了 `associatedtype` 的继承子句，所以「这个 PR 让它变得可达」不成立。
- **基线有没有**：有。协议的 `where` 子句一直经过这个函数，`next` 第 363 行就是这样。
- **值不值得修**：不修。走不到的分支，不值得为它手工造一个二进制来写测试。
- **以前修过吗**：`f223b210` 把旁边 `dumpContent` 的同一处改成了 `Error`，漏了这一处，只改了一半。

## 4. 默认写法下每个协议多读一次关联类型名（不修，A71）

`Sources/Output/SwiftPrinting/SwiftDeclarationPrinter.swift:377`。

- **能复现吗**：属实。默认写法用不到这份名单，打印 `associatedtype` 行时又读了一遍。
- **基线有没有**：本 PR 新引入。
- **值不值得修**：不修。多读的只是一个短字符串，比起打印整个协议可以忽略，也写不出修前会失败的测试。
- **以前修过吗**：没有。同类先例 A26。

## 5. 开关打开时每条约束的主语 demangle 两次（部分误报，不修，A72）

`Sources/Output/SwiftPrinting/ProtocolRequirementPartition.swift:74`。

- **能复现吗**：调用确实重复，但「两倍工作量」不对：第二次命中按镜像的记忆化缓存，只是从已驻留的 `NodeReference` 重建一棵很小的树。
- **基线有没有**：本 PR 新引入，只在打开开关时发生。
- **值不值得修**：不修，影响很小。
- **以前修过吗**：没有。同类先例 A3：这类重建实测只占打印时间约 1%。

## 6. 现场编译 fixture 的辅助代码又复制了一份（本 PR 不修，A73）

`Sources/TestSupport/MachOTestingSupport/ProtocolRequirementPlacementFixture.swift:153`。

- **能复现吗**：属实，而且比审查说的严重：`next` 上已有 41 份副本（审查说 6 份），这是第 42 份。
- **基线有没有**：早就存在。
- **值不值得修**：值得，但不在这个 PR 里：合并成一个共享函数要改 41 个测试文件。副本的代价有据可查：`d2cacc50`（先读完 stderr 再等进程退出，防死锁）和 `a2725835`（固定语言模式）当年都只修了一份，现在 41 份里还有 25 份没固定语言模式，只是因为它们都不生成 `.swiftinterface` 这类随语言模式变化的产物，暂时没出事。
- **以前修过吗**：没人合并过。相关条目 A45。

## 7. 继承子句的拼写循环有三份（有意设计，不修，A74）

`Sources/Output/SwiftPrinting/SwiftDeclarationPrinter+Headers.swift:238`。

- **能复现吗**：部分属实。新加的循环与协议头的循环形状相同，但两者调用不同的打印函数，后面还要接 `~Copyable`。PR 同时把 `where` 子句抽成了一个函数，打印器内部的重复其实变少了。
- **基线有没有**：dump 与 interface 各有一份协议头，基线就有，而且是有意的。
- **以前修过吗**：没有。分成两份是 `aa233bc0`（让 SwiftDump 成为叶子模块）有意做的，提交说明写着「the two paths intentionally diverge」。

## 8. diff / evolution 的协议头手工传入「约束全留在协议上」（有意设计，不修，A75）

`Sources/Output/SwiftInterface/SwiftDeclarationPrinter+DiffRendering.swift:76`。

- **能复现吗**：审查担心以后有人改成按配置走，约束会悄悄丢掉。不会悄悄发生：`diffHeaderKeepsEveryRequirement` 在开关打开时打印 diff 的协议头，与默认写法比较，那样改就会变红。
- **基线有没有**：新代码。
- **以前修过吗**：没有。提案的决策日志专门记了这个选择。

## 验证

- **环境**：PR 头的 `git archive` 副本 `/Volumes/DerivedData/Agents.noindex/claude/Scratch/MachOSwiftSection-PR135-CIToolchain`（SymbolTestsCore fixture 链接自主 checkout），构建目录 `/Volumes/DerivedData/Agents.noindex/claude/SwiftPM/MachOSwiftSection-Xcode26.6`，`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`（Xcode 26.6，Swift 6.3.3），依赖从远端解析，不用本地兄弟仓库；机器 JHs-Mac-Studio（macOS 26.7）。日志在 `/Volumes/DerivedData/Agents.noindex/claude/Logs/`。
- **第 2 条**：PR 头上，两个新套件加 `DumpAndInterfaceRequestTests`、`CommandRequestMappingTests` 共 4 个套件 45 个测试通过，退出码 0（`MachOSwiftSection-PR135-Xcode26.6.log`）。
- **第 1 条修正之后**：同样 4 个套件 45 个测试通过，退出码 0；`SubjectOnlyRequirements` 在四个参数化测试里都通过，包括往返编译（`MachOSwiftSection-PR135-Xcode26.6-final.log`）。
- **变异检查**：在沙盒里临时让 superclass 约束也看右侧（旧措辞的说法），`ProtocolRequirementPlacementInterfaceTests` 退出码 1，只有 `SubjectOnlyRequirements` 这一条放置用例失败：约束被挪进了 `associatedtype First where Self.Element: ProtocolRequirementPlacementFixture.GenericBase<Self.First>`。往返编译测试照样通过，因为这种摆法语义不变，所以「只看主语」只有这条用例在守。临时改动已撤回（`MachOSwiftSection-PR135-Xcode26.6-mutation.log`）。
- **编译器对照**：Swift 6.3.3 对同一源码 `-emit-module-interface`，印出 `public protocol SubjectOnlyRequirements : Swift.Sequence where Self.Element : ProtocolRequirementPlacementFixture.GenericBase<Self.First>`，`associatedtype First` 不带约束，与测试的期望一致（`/Volumes/DerivedData/Agents.noindex/claude/Scratch/PR135-CompilerPlacementProbe/`）。
- **没跑的**：release 配置；Xcode 27.0；全量测试。修正只动了测试和一段文档注释，全量测试在 PR 头 `07016c07` 上跑过，结果记在 ProjectEvolutionLog 本节。
