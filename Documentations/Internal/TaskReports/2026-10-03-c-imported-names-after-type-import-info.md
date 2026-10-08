# 2026-10-03 读 TypeImportInfo 之后 C 导入类型名字的变化，与依赖旧短名的地方

对应提案：无（[0023-type-import-info-identity](../../Evolutions/0023-type-import-info-identity.md) 的后续核查，豁免档）。前置：[2026-09-30-c-imported-typedef-types-uncolored-in-runtimeviewer](2026-09-30-c-imported-typedef-types-uncolored-in-runtimeviewer.md) 第五、六节准备好却没跑的那次对比。

## 问题

RuntimeViewer 的快照测试里 `__C.Decimal.FormatStyle` 变成了 `__C.NSDecimal.FormatStyle`。用户先要调查读 TypeImportInfo 之后 C 导入类型的名字到底怎么变了，再问二进制里有没有信息能还原真实的 Swift 名，最后定：先保持 ABI name（它是准确的），从二进制推断 Swift 名以后再做；检查有没有测试依赖之前被截短的 Swift 类型名，改掉；顺便查 RuntimeViewer 的测试。

## 调研

### 名字变了多少（2026-10-01）

改动前最后一个提交 `7071ac46` 与改动 `1c8d8588` 各编一个 release CLI，两侧共用同一份 `Package.resolved`，在本机 macOS 27.0 的系统 dyld cache 上跑 `dump` 与 `interface --show-c-imported-types`，逐行比对。CoreFoundation 没有 Swift section，不在其中。

| 框架 | `dump` 变化行 | 其中改名行 | 不同的改名 | `interface` 顶层声明 | C 类型 extension 目标 |
|---|---|---|---|---|---|
| AppKit | 633 | 633 | 81 | 768 → 773 | 404 → 406 |
| UIKitCore（Mac Catalyst） | 546 | 546 | 77 | 997 → 1003 | 646 → 644 |
| SwiftUI | 565 | 507 | 66 | 4400 → 4406 | 112 → 112 |
| SwiftUICore | 566 | 518 | 47 | 3058 → 3058 | 127 → 118 |
| Foundation | 510 | 375 | 33 | 406 → 406 | 205 → 200 |

`dump` 里不是改名的变化行都是 protocol witness：原来打成 `sub_…` 地址的拿到了真名（SwiftUI 35、SwiftUICore 48、Foundation 135），以及 SwiftUI 里 23 行原来挂着别的类型的 witness（见下）。

**旧名是什么**：描述符名字字段里的 user-facing name，也就是 Swift 名的最后一个成分。IRGen `computeIdentity`（`lib/IRGen/GenMeta.cpp`）取 `Type->getName()`，C 名作为 import info 的 `N` 分量跟在后面；`getAddrOfParentContextDescriptor`（`lib/IRGen/GenDecl.cpp`）把每个 Clang 导入类型的父级都设成 `__C` 模块，所以 `NSTableView.Style` 在二进制里只剩 `Style`，嵌套关系和所属模块都不记录。

**五个框架合计 244 组改名**：

| 类别 | 组数 | 例子 |
|---|---|---|
| 加回外层类型名或前缀 | 166 | `Style` → `NSTableViewStyle`、`Name` → `NSNotificationName`、`Decimal` → `NSDecimal` |
| CF class 加回 `Ref` | 38 | `CGColor` → `CGColorRef`、`Subgraph` → `AGSubgraphRef` |
| 完全换了名字 | 26 | `Event` → `UIControlEvents`、`BounceOptions` → `RBSymbolAnimationBounceFlags` |
| `swift_private` 去掉 `__` | 13 | `__UIButtonConfigurationSize` → `UIButtonConfigurationSize` |
| importer 合成的错误类型 | 1 | `__C_Synthesized.UISSceneConnectionValueError` → `__C_Synthesized.related decl 'e' for UISSceneConnectionValueError` |

**旧名造成的问题**（0023 之后都没有了）：

- 20 个短名各指多个类型：`Style` 8 个、`Identifier` 5 个、`Name` 4 个。
- `interface --show-c-imported-types` 只留下同名 C 类型中的一个：AppKit 少 5 个声明，UIKitCore、SwiftUI 各少 6 个。
- SwiftUI 里 `NSTouchBarItem.Identifier` 的 conformance 下面列的是 `NSToolbarItemIdentifier` 的 witness，`NSAppearance.Name`、`NSButton.BezelStyle` 同理，共 23 行。
- 同一类型拆成两个名字：描述符给短名，符号给 C 名。SwiftUICore 里 `CGColor` 的 extension 分成 `__C.CGColor` 5 块与 `__C.CGColorRef` 1 块；Foundation 的 `interface` 里 `__C.Decimal` 106 行、`__C.NSDecimal` 67 行并存。
- `--resolve-c-module-names` 按短名查模块会认错：AppKit 的 `controlSize` 字段被写成 `SwiftUICore.ControlSize`，`__C.Mode` 被写成 `QuartzCore.Mode`。用当前代码，同一字段写成 `AppKit.NSControl.ControlSize`。

**仍然存在、本批没动的**：默认输出没有 Swift spelling；`interface` 里 C 类型自己的声明头仍是描述符的短名（AppKit 的 `NSAppearanceName`、`NSFontCollectionName`、`NSNotificationName` 都打成 `struct Name {`，`dump` 的声明头却是全名），RuntimeViewer 自 `d300bafd` 起把 C 类型列进侧边栏后会看到这一点；开了 `--resolve-c-module-names` 时 extension 头仍是 `extension __C.NSControlSize`，只有引用处被改写。

### 二进制能还原多少 Swift 名

拿 SDK 当标准答案：所有 `.apinotes` 的顶层条目（4530 条，含 Mac Catalyst 的 UIKit）、头文件里的 `NS_SWIFT_NAME` 等标注（405 条）、importer 的固定规则（CF `Ref` 剥除、`swift_private` 的 `__`、合成错误类型）。244 组里 188 组有答案。

- 不嵌套的 64 组：二进制里的最后一截就是完整 Swift 名（`Decimal`、`CGColor`、`StringTransform`）。
- 嵌套的 124 组：二进制只有最后一截。按「C 名去掉最后一截，剩下的前缀若是 ObjC class 就当外层类型」去猜，89 组的 C 名正好是外层类名加最后一截，用 AppKit、Foundation、UIKitCore、UIFoundation、CoreData 的 ObjC class 名单猜对 79 组；另外 35 组的 C 名对不上，必错（`NSControlSize` 实为 `NSControl.ControlSize`，`UIControlEvents` 实为 `UIControl.Event`，`NSRunLoopMode` 实为 `RunLoop.Mode`）。
- 合计猜对 143 组，错的 45 组看起来和对的一样。
- 56 组 SDK 里没有答案，几乎都是私有框架（AttributeGraph、RenderBox、UIKit 的 `_UI…`）。对它们来说二进制里的最后一截是唯一来源，而 0023 之后开不开 `--resolve-c-module-names` 都打印 C 名（SwiftUICore 的 `__C.AGSubgraphRef` 140 行，开了之后仍是 140 行）。

改名过的 ObjC class 与 protocol（`NSFileManager` → `FileManager`、`NSObject` protocol → `NSObjectProtocol`）没有 Swift 描述符，二进制里没有它们的 Swift 名。

### 依赖旧短名的地方

用只出现在旧侧的 212 个拼写搜索：

- **MachOSwiftSection 的测试**：没有断言依赖旧短名，0023 当时已改过 `__C.Decimal` 的期望和两份快照。唯一相关的是 `SupplementaryAPINotesTests.userSuppliedMappingsResolveInAllManglingShapes`，它的说明把描述符直出的 `__C.Graph` 列为第三种 mangling 形态；0023 之后这种形态不再出现，SwiftUICore 的 `dump` 里 `__C.Graph` / `__C.Subgraph` 从 107 行变成 0。
- **MachOSwiftSection 的注释与文档**：`StaticLayoutCalculator` 的注释与 `StaticLayoutEngine.md` 里的 `__C.Decimal`；`TypeIndexingPipeline.md`、公开指引 `SupplementaryTypeMappings.md` 与术语表对第三种形态的描述和「二进制零残留」的说法；A15 裁决对「剥后名」形态的引用；`TypeDatabase.registerAttribution` 的注释。任务报告、提案和账本的旧节是历史记录，不改。
- **其它分支**：`next` 之外三个未合并分支的测试都没有旧短名。
- **RuntimeViewer**：12 个 worktree 的测试与快照里，C 导入类型名都已是 ABI name。唯一依赖旧名的 `relationships-swift-baseline.txt` 已在 RuntimeViewer `next` 的 `81a79054` 更新；仍带旧基线的五个分支都已并入 `next`。RuntimeViewer 没有改动。

## 实际执行

**先删后撤**：一开始判断 `TypeDatabase.registerAttribution` 里把 APINotes 的 SwiftName spelling 登进归属表的那段循环只为第三种形态存在，删掉了它，并把测试里 `Graph` / `Subgraph` 的归属期望改成 `nil`。单元测试全过，但改动前后两版 release CLI 在系统框架上对比 `interface --resolve-c-module-names --show-c-imported-types` 时输出不同，差异全是 `NSObject` 的模块归属：

| 框架 | 变化行 | `ObjectiveC.NSObject` → `Foundation.NSObject` | `ObjectiveC.NSObjectProtocol` → `Foundation.NSObjectProtocol` |
|---|---|---|---|
| AppKit | 129 | 108 | 22 |
| UIKitCore | 136 | 130 | 6 |
| SwiftUI | 260 | 263 | 4 |

原因：Foundation 与 AppKit 的 APINotes 为了标注 category 方法也列了 `NSObject`，`APINotesIndex` 的 C 名登记是后加载的文件说了算；ObjectiveC 的条目把 `NSObject` 改名为它自己，那段循环在 C 名之后登记这个 SwiftName spelling，`NSObject` 才回到 ObjectiveC。也就是说它早就不服务第三种形态，却在替「多个模块列出同一个 C 名」的情况定归属。现有测试没有覆盖这一点，所以删掉后全绿。

于是撤回删除，改成：

- `TypeDatabase.registerAttribution`：保留循环，注释改写成它现在实际起的作用。源码只有注释变化，行为不变。
- 新增 `TypeDatabaseMergePriorityTests.renamingEntryKeepsItsModuleAgainstLaterListings`：两个模块的 APINotes 都列出 `TSTBase`，改名条目所在的模块先加载、只做标注的后加载，断言归属仍是改名条目的模块。
- `SupplementaryAPINotesTests`：断言不变，说明改为两种 mangling 形态，并指明 Swift spelling 为什么仍被登记。
- 文档：`SupplementaryTypeMappings.md`（二进制只留最后一截、typedef 名也出现在字段元数据里、`__C.Graph` 不必登记）、术语表「supplementary APINotes」、`TypeIndexingPipeline.md`（第三种形态标为不再出现，记下那段登记为什么要留）、A15 加补记、`StaticLayoutEngine.md` 与 `StaticLayoutCalculator` 注释里的 `__C.Decimal` 改成 `__C.NSDecimal`。

## 验证

- `swift test --filter TypeIndexingTests`（退出码取自 `swift test` 本身）：38 条 / 7 个 suite 全过。
- 红/绿：把那段循环临时去掉再跑 `TypeDatabaseMergePriorityTests` 与 `SupplementaryAPINotesTests`，3 处失败（`TSTBase` 归到 `AnnotatingModule`，`Graph` / `Subgraph` 归属为 nil）；恢复后全过。
- 源码改动只有注释（`git diff -- Sources` 里除注释外没有增删行），所以没有再对系统框架做输出对比；上面那次对比就是删掉循环时做的。

## 环境备忘

- 对比产物与派生表：`/Volumes/DerivedData/Agents.noindex/claude/Logs/TypeImportInfoNames/`。`all-renames.tsv` 是 244 组改名，`all-renames-truth.tsv` 是 SDK 答案与分类，`sdk-apinotes-swift-names.tsv` / `sdk-header-swift-names.tsv` 是从 SDK 抽出的 C name → Swift name，`spelling-ab/` 是删循环那次的输出对比。
- CLI：`/Volumes/DerivedData/Agents.noindex/claude/SwiftPM/MachOSwiftSection-{Pre0023,Post0023}/release/swift-section`（名字调查），`…/MachOSwiftSection-SwiftSpellingBaseline-Release` 与 `…/MachOSwiftSection-DropSwiftSpellingAttribution-Release`（删循环那次的对比，后者是删掉循环的版本）。
- 本批构建时 GitHub 连不上（`SSL_ERROR_SYSCALL`）。依赖用 FindNavigator worktree 的 `Package.resolved` 加 `--skip-update --only-use-versions-from-resolved-file` 从本机缓存离线解析，两侧共用同一份。
