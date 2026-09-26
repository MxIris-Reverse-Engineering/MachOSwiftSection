# 2026-09-22 第三档「只按名字」接上开关：`NSGlassEffectView` 里没有 `override` 的那几个方法

## 起点

用户贴来 macOS 26.7 系统 cache 生成的 AppKit interface 里 `NSGlassEffectView` 的一段，问 `viewDidHide` / `viewDidUnhide` / `encode(with:)` 怎么没有 `override`，`_cornerConfiguration` 这个私有属性是不是也该是 `override`。

## 调研发现

**前三个是覆写，库知道，但联结不上。** dump 的 `@implementation` 段里这三条方法行都写着 `overrides NSView (no Swift member tied to this IMP)`。用 lldb 在一个链接 AppKit 的空进程里反汇编：`viewDidHide` 的 IMP 只有 3 条指令——装 selector 字串、跳到一个 outlined helper 去做 `objc_msgSendSuper2`，Swift 函数是并排的另一个 3 指令 stub，互不引用；`encodeWithCoder:` 的 IMP 是 Swift 函数体的整份拷贝（调 super、取 `contentView`、`encodeObject:forKey:`），没有 `bl` 到 Swift 函数。第一档要的 `To` 符号被 cache strip 了，第二档要的引用被内联掉了，只剩第三档「只按名字」——而它当时是 `ObjCMembers.infersOverridesFromSelectorNames` 这个进程级静态属性，默认关，CLI 与 `SwiftDeclarationIndexConfiguration` 都没接，RuntimeViewer 也只能全进程一起开。

**`_cornerConfiguration` 不是覆写。** 同一个进程里问运行时，`class_getInstanceMethod(NSView, _cornerConfiguration)` 返回 NULL；NSView 只有 category 里的类方法 `+default_cornerConfiguration`，实例 getter 是 NSButton、NSTextField、NSScrollView、NSBox、NSThemeFrame 各自声明的。库的输出不打 `override` 是对的；它缺的只是 `@objc`，原因与上面相同（getter 体被拷进 thunk），且 `@objc @implementation extension` 里成员本就隐含 `@objc`。

**第三档的推断方向是 ObjC → Swift。** 起点是类自己方法表里「前两档没联结上、且祖先链上有人实现同名 selector」的方法；候选是类里尚未标记的 Swift 成员，从 demangle 树取名字形状（基名、标签、参数个数、实例 / 类型级、getter / setter / init）——不含参数类型与返回类型；用 importer 的正向拼写规则 `isConsistent(withSelector:)` 过一遍，恰好一个候选才归属。非覆写的方法不参与，所以它能加 `override`、不可能添出 `@objc(name)`。

**`-O` 的 fixture 能稳定复现。** 把 fixture 的源码用 `-O` 编译再 `strip -x`，`SwiftDerivedWidget` 的每个覆写（`ping` / `pingCount` / `level` / `description` / `bump` / `noteValueForKeyPath:ofObject:`）都联结不上——与 AppKit 同一形状，可以做第三档的正例，不必依赖 macOS 26 门控的 AppKit 测试。

## 最终方案

用户定的：加一个开关，直接改（「加一个，直接改」）；默认仍关（既定裁决「只联结不猜」未变）。我定的、用户未反对的：开关按镜像而不是按进程（RuntimeViewer 同时开着多个镜像；与 `ObjCAncestorResolverStore` 同一模式），进程级静态属性去掉；dump 走同一档，不然 `dump` 上的 flag 是空的；flag 名 `--infer-objc-overrides`，放在 `dump` / `interface` 共用的 `ObjCMemberOptionGroup`，不放 `MachOOptionGroup`——`snapshot` 也用那个组却不记这些事实。

## 执行

- SwiftInspection：`ObjCMemberRecoveryOptions`（一项 `infersOverridesFromSelectorNames`）与 `ObjCMemberRecoveryOptionsStore`；`ObjCClassHierarchies.removeCache(for:)` 一并清。
- SwiftThunkAnalysis：`ObjCMembers` 去掉静态开关与锁。
- SwiftDeclaration：`ObjCMemberApplication.apply` 收 `infersOverridesFromSelectorNames:` 参数；`TypeDefinition.applyObjCMembers(in:)` 从注册表读；`ExtensionDefinition.applyObjCMembers(_:infersOverridesFromSelectorNames:)`。
- SwiftIndexing：配置字段 `infersObjCOverridesFromSelectorNames`；indexer 在类型索引前注册（`registerObjCMemberRecoveryOptions`），新 claim `objcMemberRecoveryOptions` 随最后一个活着的 indexer 驱逐，`updateConfiguration` 改了就重注册；extension 两处从注册表读。
- SwiftDump：`ObjCMemberRendering.inferredOverrides(for:memberSymbols:in:)`（键是符号名，跳过已在表里的），`ClassDumper` 与 `ObjCImplementationClassDumper` 先收齐全部成员符号再渲染，成员行查表落空时查推断结果，export-status 豁免同样算上；`@implementation` 的方法行三态：`overrides NSView` / `overrides NSView (selector name, no symbol evidence)` / `overrides NSView (no Swift member tied to this IMP)`。
- swift-section：`ObjCMemberOptionGroup`（`--infer-objc-overrides`），`dump` 注册进注册表，`interface` 写进索引配置。
- fixture：`.optimizedStripped` 变体（`-O` + `strip -x`）。
- 测试：`ObjCMemberRecoveryTests` 三例（默认不标且表里全在未联结列表；开了之后普通类 / extension / 孙类 / `@implementation` 体的覆写都标、`notAnOverride` 与显式 selector 不被碰；注册表按镜像）、`ObjCMemberDumpTests` 一例（两个 dumper 开关前后）、`InferObjCOverridesFlagTests` 四例。

## 验证

- 定向套件（新增三个位置 + 碰 fixture 的四个 suite + `AppKitObjCMemberTests` + 驱逐与既有 flag 测试）：64 / 64；`SwiftInterfaceTests` / `SwiftDumpTests` / `SwiftSectionCommandTests` / `SwiftIndexingTests` / `MachOTestingSupportTests` 五个 target 整跑 447 / 447（73 个 suite）。全量套件未重跑——改动全在开关之后，默认路径的输出下面逐字节核过。
- macOS 26.7 系统 cache 的 AppKit，`dump -s objcImplementationClasses --infer-objc-overrides`：`NSGlassEffectView` 的 `viewDidHide` / `viewDidUnhide` / `encodeWithCoder:` / `renewGState` / `_windowChangedKeyState` / `_viewDidChangeEffectiveCornerRadii` / `clipsToBounds` getter 全部标为 `overrides NSView (selector name, no symbol evidence)`，`_cornerConfiguration` 照旧不标；38 个 `@implementation` 类里联结不上的覆写 96 → 65。不开 flag 的输出与之前逐字节一致（默认路径不变）。
- 同一 cache 的 AppKit interface（release 构建，10 秒）：不带 flag 与之前一致，`override` 行 52；`--infer-objc-overrides` 下 116，`NSGlassEffectView` 的 `viewDidHide` / `viewDidUnhide` / `encode(with:)` / `renewGState` / `_windowChangedKeyState` / `_viewDidChangeEffectiveCornerRadii` / `clipsToBounds` 全打成 `@objc override`，`_cornerConfiguration` 仍是 `var`。两份输出把行首的 `@objc` / `override` / `final` 归一后逐行 diff 为空——flag 只改关键字，不动别的。

## 偏差与遗留

- `_cornerConfiguration` 不按用户的直觉标 `override`，事实如上；它在 interface 里没有 `@objc` 是同一原因造成的诚实漏标，且 `@implementation` 体里成员隐含 `@objc`，未改。
- 第三档仍没比对方法的 `types` 编码与 Swift 参数类型（参数个数比了，类型没比）；要更稳可以加这一道。
- 全局 skill `swift-section-cli` 未更新（不在本仓库）。
