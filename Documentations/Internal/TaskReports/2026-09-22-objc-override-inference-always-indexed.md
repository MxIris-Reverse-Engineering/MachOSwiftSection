# 第三档「只按名字」改为始终索引，输出交给消费者（2026-09-22，当日第二次）

## 问题

同一天早些时候刚把第三档的开关从进程级静态属性改成按镜像的 `ObjCMemberRecoveryOptions`（见 [2026-09-22-objc-override-inference-switch.md](2026-09-22-objc-override-inference-switch.md)）。用户当天再次提出：

> `infersOverridesFromSelectorNames` 这个改成始终索引，实际输不输出又 printer 决定，printer 读 indexer 产生的数据（一般存在 Definitions 里面）。

按镜像的开关解决的是「谁能开」，不是「谁来裁决」。开关关着时索引**根本不跑**第三档，`Definition.objcMember` 上什么都没有——消费者就算想用也无从拿起，RuntimeViewer 想在一次索引的结果上同时提供「只看证据」与「连推断一起看」两种视图也做不到。

## 调研发现的那条硬约束

改动本身很直白：第三档无条件跑，printer 按配置决定打不打。但落地时发现一个必须同时处理的耦合，否则「输出由 printer 决定」只是口号：

`ObjCMemberApplication` 在第三档命中时会调 `addObjCAttribute(to:)`，往成员的 `attributes` 里塞一个 `.objc`。而 `TypeDefinition.index(in:)` 里 `applyObjCMembers` 的**下一句**就是 `recoverFinalMembers`，它把「有 `@objc` 且没有 method descriptor」读成 `@objc dynamic` 的证据从而不标 `final`；`--exported-only` 的过滤（`SwiftDeclarationPrinter+ExportFilter`）同样读 `attributes.contains(.objc)`。

也就是说，只要第三档在索引期写下那个属性，两个与它无关的判断就先于消费者的裁决落定，而且**收不回来**——`isFinal` 是存储属性，printer 再决定「不采信」也已经晚了。

所以第三档只能写 `objcMember`，四个关键字统一在渲染时派生。

## 方案（用户批准后实施）

**数据模型**
- `ObjCMemberApplication.apply` 去掉 `infersOverridesFromSelectorNames:` 参数，第三档无条件执行；`inferFromSelectorNames` 的写回循环删掉 `addObjCAttribute`，只设 `objcMember`。
- `ObjCMember` 加两个派生属性：`isInferredFromSelectorName`（`evidence == .selectorName`）与 `isJoinedOverride`（覆写且非第三档）。
- 三个 Definition 的 `isOverride` / `isClassMember` 改读 `isJoinedOverride`，只认前两档；`AccessorRepresentable` 同步，并把原先内联的 accessor 判断提成 `hasVTableOverrideAccessor`。
- 新增 `ResolvedObjCMemberFacts`（`Sources/SwiftDeclaration/Components/Definitions/`）：`resolve(...)` 按 `trustingSelectorNameEvidence` 一次性给出 `objcMember` / `attributes`（采信时末尾补 `@objc`，与原先 `addObjCAttribute` 的 append 位置一致）/ `isOverride` / `isClassMember` / `isFinal`（采信时强制 `false`——ObjC 运行时派发的方法是 `@objc dynamic`，不可能 final）。传 `false` 逐字复现定义自己的属性。

**printer**
- `SwiftDeclarationPrintConfiguration` 加 `infersObjCOverridesFromSelectorNames: Bool = false`，printer 内部经 `trustsSelectorNameEvidence` 读它。
- 三个 `printThrowing*`、`+ObjCImplementation` 的存储属性 printer、`renderMember` 的 export-status 腿、`+ExportFilter` 的成员腿，全部改成先取 facts 再读，`@objc` / `@objc(selector)` / `override` / `class` / `final` / export-status 豁免同进同退。

**dump**
- `ObjCMemberRendering.inferredOverrides` 去掉 store 查询与 `in machO:` 参数，始终算。dump 为每条联结标证据，第三档写作 `(selector name, no symbol evidence)`，读者分得清，所以不需要开关。

**删除**
- `Sources/SwiftInspection/ObjCMemberRecoveryOptions.swift` 整个文件（`ObjCMemberRecoveryOptions` + `ObjCMemberRecoveryOptionsStore`）。
- `SwiftDeclarationIndexConfiguration.infersObjCOverridesFromSelectorNames`；indexer 的 `registerObjCMemberRecoveryOptions()`、`Claims.objcMemberRecoveryOptions` 字段与 `formUnion` 分支、`deinit` 的驱逐分支、`updateConfiguration` 的重注册分支、claim 采样；`ObjCClassHierarchies.removeCache(for:)` 里的那一行。
- `DumpCommand` 的 `--infer-objc-overrides`（`ObjCMemberOptionGroup` 只留在 `InterfaceCommand`，`recoveryOptions` 计算属性一并删）。

## 决策

用户定的：改成始终索引、输出由 printer 决定、printer 读 Definitions（原话见上）。三个提问一轮问完，全部选推荐项：dump 始终打并删掉它的 flag；interface 默认关、`--infer-objc-overrides` 打开；索引期那套开关整个删掉（RuntimeViewer 尚未引用，用户答「RV 那边还没读，直接改」）。

我定的、用户未反对的：
- 第三档不写 `attributes`（上面那条硬约束的直接后果）。
- `ResolvedObjCMemberFacts` 作为唯一裁决点，而不是给每个 Definition 加五个带参属性——后者是 15 个方法，且没法保证四个关键字被同一个裁决覆盖。
- 无参的 `isOverride` / `isClassMember` 保留但收窄到前两档，而不是让它们带参数。它们有大量既有读者（export filter 的 field 腿、`SwiftInterfaceBuilder`、诊断），收窄的语义正是「默认不猜」。

## 验证

- `swift build` 绿。
- `InferObjCOverridesFlagTests` / `ObjCMemberDumpTests` / `ObjCMemberRecoveryTests` 三个 suite 共 37 个测试全过。
- 新增 `indexRecordsTheNameOnlyTieWhicheverWayTheConsumerRules`（SwiftInterfaceTests）：在没有任何开关的默认配置下索引 `.optimizedStripped` fixture，断言 `ping.objcMember` 存在且 `evidence == .selectorName`、`overriddenAncestorClassName == "ClangWidget"`，同时 `isOverride == false`、`attributes` 不含 `.objc`；`resolvedObjCMemberFacts(trustingSelectorNameEvidence: true)` 给出 `isOverride` / `isObjC` / `!isFinal`，传 `false` 则 `objcMember == nil` 且 `isFinal` 与定义自己的取值相同。这条是「关掉时输出不变」与「打开时 `final` 被压制」唯一的复现点——`final` 压制在这个 fixture 上走不到端到端（fixture 的覆写都有 vtable descriptor，`final` 还原本来就不标它们），所以只能在这一层钉住。
- `ObjCMemberDumpTests.inlinedOverridesAreTiedByNameOnly`：原测试的「默认不标」一段删除（dump 不再有开关），改为默认就写 `(selector name, no symbol evidence)`。
- `InferObjCOverridesFlagTests.dumpRejectsTheFlag`：`dump` 传这个 flag 直接报错，而不是静默 no-op。
- 全量 `swift test --skip IntegrationTests`（fixture 重建后）：2005 个测试 / 381 个 suite，4 个 issue，无一与本改动有关：
  - `SharedCacheTests` 的三个并行度断言（`differentKeysParallelViaTaskGroup` / `…ViaAsyncLet` / `concurrentCallsForDifferentKeysRunInParallel`）——用墙钟断言并行度，全量跑必假失败，单独跑全过。已知 flake。
  - `GenericSpecializationTests.argumentCandidatePathSpecializesNonGenericCandidate`——单独跑仍红。**在未改动的 baseline（`55a01ce4`）上跑同一测试，失败形态完全相同**（candidate 路径与 metatype 路径拿到相差约 4.7 KB 的两个泛型元数据槽位），是基线既有失败，与本改动无关。

### 渲染 A/B

归档 cache 15.5，6 个默认框架 × dump + interface：**12 对全部逐字节一致**（这些框架上第三档无命中，所以这一腿证明的是「不命中时输出完全不变」）。

第三档真正有命中的是 macOS 26 的 AppKit，而 harness 的 `ARCHIVED_CACHE_DIRECTORIES` 写的是 `/Volumes/DyldSharedCaches/macOS/26.6`、磁盘上实际是 `26.6.2`，那条腿一直在静默跳过（脚本本身不假绿，会报 `zero pairs compared`）。所以对 26.6.2 的 AppKit 手工做了三组，全部用两侧的 release 二进制：

| 对比 | 结果 |
|---|---|
| `interface`，两侧都不带 flag | **逐字节一致**（10092 行） |
| `interface --infer-objc-overrides`，两侧 | **逐字节一致** |
| baseline `dump --infer-objc-overrides` vs candidate `dump`（无 flag） | **逐字节一致**（21464 行） |
| baseline `dump`（无 flag） vs candidate `dump` | 124 行差异，即 62 处；候选侧新增的 62 行**全部**带 `(selector name, no symbol evidence)`，零例外 |

第二、三行是这次改动的核心证据：开关打开后，候选方由 printer 现场派生的 `@objc` / `override` / `class` / 压制 `final`，与基线在索引期写死的结果**完全相同**。开关本身确有效果——AppKit 的 `override` 行数 59 → 123，64 处声明变化（`init()` → `@objc override init()` 这类）。

最后一行的 62 处差异全是同一形态：`@implementation` 的 ObjC 方法行由 `overrides NSView (no Swift member tied to this IMP)` 变成 `overrides NSView (selector name, no symbol evidence)`，以及对应 Swift 成员行新增同样标注的注释。正是「dump 始终渲染第三档」的预期结果。

## 环境备忘

这个 worktree 的 `../swift-capstone` 符号链接指向已升级到 Capstone v6 的本地 sibling（trait 改名 `ARM64` → `AARCH64`），而本仓库 pin 的是 exact 5.0.0。带 `USING_LOCAL_DEPENDENCIES=1` 构建会直接失败在 trait 解析：

```
error: Trait 'ARM64' enabled by package 'machoswiftsection' is not declared by package 'swift-capstone'.
The available traits declared by this package are: AARCH64, …
```

在 swift-capstone 的 v6 迁移落地前，本仓库的构建**不能**带那个环境变量，走远程 pin。

fixture 二进制在新 worktree 里是缺的（`DerivedData` 是 gitignore 的 per-machine 产物，这里是指向 `/tmp/claude/DerivedData` 的符号链接）。重建命令按 CI 的签名方式：

```bash
mkdir -p /tmp/claude/DerivedData   # 见下
xcodebuild -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj \
  -scheme SymbolTestsCore -configuration Release \
  -derivedDataPath Tests/Projects/SymbolTests/DerivedData/SymbolTests \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO build
```

两个把人带偏的坑，这次各踩了一次：

1. **符号链接的目标目录不存在时，xcodebuild 的报错不指向根因**。`/tmp` 会被清理，`Tests/Projects/SymbolTests/DerivedData → /tmp/claude/DerivedData` 就成了断链，xcodebuild 报的是 `Couldn't create workspace arena folder …: The file "SymbolTests" couldn't be saved in the folder "Projects"`——听上去像仓库目录权限问题。先 `mkdir -p` 目标目录。
2. **`xcsift` 把构建失败也报成成功**。已知它的退出码恒为 0（见 `CLAUDE.md`），但那条写的是「构建诊断不受影响」，指的是错误信息能被正确解析——加上 `--quiet` 之后，失败的构建输出为空、管道退出码为 0，看起来与成功完全一样。这次因此误以为 fixture 已就绪，跑了一轮全量测试，1102 个 issue 全是 `The file "SymbolTestsCore" doesn't exist.`。**构建也要用 `${pipestatus[1]}` 或先落文件再判退出码**，不只是测试。
