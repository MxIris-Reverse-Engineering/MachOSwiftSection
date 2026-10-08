# 2026-09-30 - C-imported typedef types uncolored and unsearchable in RuntimeViewer

- **日期**: 2026-09-30
- **任务**: C-imported typedef types uncolored and unsearchable in RuntimeViewer
- **作者**: Mx-Iris
- **仓库**: https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection

## 1. 问题 / 任务

用户在 RuntimeViewer 里看 AppKit 的 `NSSliderAquaduckVisualProvider`，发现 stored property `var state: __C.NSSliderDrawingState` 的类型名没有着色、点不了，在侧边栏也搜不到。用户还有一个疑问：如果它是 ObjC 类，Type Layout 为什么是 `size: 232`，而不是一个指针的大小。解释清楚之后，用户要求评估提案 0023 对 AppKit、UIKitCore、SwiftUI、SwiftUICore、Foundation、CoreFoundation 这六个库的影响。0023 就是 `type-import-info-identity`：读取 C 导入类型 descriptor 上的 import info，按运行时的规则定名字和种类。A/B 对比准备到一半时，用户叫停，要求先把调查结果写下来。

## 2. 探索与调研

### 调研内容

- **本仓库**（`next` @ `32feff36`）：
  - 代码：`Sources/Analysis/SwiftInspection/SymbolicDemangler.swift`、`Sources/Output/SwiftPrinting/NodePrintables/TypeNodePrintable.swift`、`Sources/Output/SwiftPrinting/NodePrintables/NodePrintable.swift`、`Sources/Output/SwiftDeclarationRendering/Extensions/Node+.swift`、`Sources/Declaration/SwiftIndexing/SwiftDeclarationIndexer.swift`。
  - CLI 着色：`Sources/Executables/swift-section/Models/SemanticColorScheme.swift`、`Sources/Executables/swift-section/Utilities/Extensions.swift`。
  - 文档：提案 [0023](../../Evolutions/0023-type-import-info-identity.md)，以及三份相关任务报告 [2026-09-09-type-import-info-identity](2026-09-09-type-import-info-identity.md)、[2026-09-10-remove-primitive-type-mapping](2026-09-10-remove-primitive-type-mapping.md)、[2026-09-10-c-imported-extension-kind-from-descriptor](2026-09-10-c-imported-extension-kind-from-descriptor.md)。
- **RuntimeViewer**（`.worktrees/RuntimeViewer`，`next` @ `92bff04a`）：
  - `RuntimeViewerCore/Sources/RuntimeViewerCore/` 下的 `Common/RuntimeObjectKind.swift`、`Core/RuntimeObjCSection.swift`、`Core/RuntimeSwiftSection.swift`、`Indexing/RuntimeSwiftInterfaceIndexer.swift`。
  - `RuntimeViewerPackages/Sources/RuntimeViewerApplication/Theme/` 下的 `SemanticString+ThemeProfile.swift`、`ThemePreset+ThemeProfile.swift`。
- **兄弟仓库**：MachOObjCSection 的 `Sources/ObjCIndexing/ObjCInterfaceIndexer.swift`，swift-semantic-string 的 `Sources/Semantic/SemanticType.swift`，swift-demangling 的 `Sources/Demangling/Node/Printer/NodePrintContext.swift`。
- **Swift 编译器源码**（`/Volumes/SwiftProjects/swift-project/swift`，`swift-6.4-RELEASE`）：`lib/AST/ASTMangler.cpp`、`stdlib/public/runtime/Demangle.cpp`、`include/swift/ABI/TypeIdentity.h`。
- **本机逆向资料**：
  - `/Volumes/DyldSharedCaches/macOS/26.5.2/AppKit/ObjCHeaders/` 下的 `NSSliderCell.h`、`NSSliderTrack.h`、`NSSliderDial.h`、`NSSliderKnob.h`、`NSSliderVisualProvider-Protocol.h`。
  - `26.5.2/AppKit/SwiftInterfaces/AppKit.NSSliderAquaduckVisualProvider.swiftinterface` 和 `26.6.2/AppKit/SwiftInterfaces/AppKit-types-layout-host-dependencies-unverified.txt`。
  - 内部 SDK `MacOSX15.5.Internal.sdk` 里没有这个 struct（它是 macOS 26 才有的）。
- **本机 dyld shared cache**（macOS 26.7，`/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/`）：做了字节级搜索。
- **Rainbow**（CLI 用来上色的库；当前 scratch 解析到的是 4.2.2）：`Sources/Rainbow.swift`、`Sources/OutputTarget.swift`。

### 关键发现

**一、232 字节是对的：`NSSliderDrawingState` 是 C struct，不是 ObjC 类**

- **`__C` 不等于 ObjC 类。** `__C` 是 Swift 给所有从 C / ObjC 头文件导入的东西用的伪模块，ObjC class、C struct、C enum、typedef 都在里面。只有 ObjC class 是一个指针，比如同一个类里的 `weak var sliderCell: __C.NSSliderCell?` 就是 `size: 8`。
- **整个 struct 直接存在对象里。** `state` 从 `0x20` 开始；最后一个字段 `hidesKnob` 在 `0x100`，按 8 字节对齐补到 `0x108`，正好是下一个属性 `_hostingView` 的偏移，`0x108 - 0x20 = 0xE8 = 232`。C 的 size 本来就包含 tail padding，所以 size 和 stride 都是 232。
- **声明形状是推断出来的，头文件原文没见到。** 它在 AppKit 私有头文件里应该是 anonymous struct 加 typedef name。下面的字段取自 Swift 侧的 field record：

  ```c
  typedef struct {
      NSSliderType sliderType;
      NSControlSize controlSize;
      // …
  } NSSliderDrawingState;
  ```

  依据有两条：
  - ObjC type encoding 里它是匿名的。导出的头文件只写成 `struct { NSUInteger x0; … }`，出现在 `NSSliderCell.h` 的 `-_currentDrawingState` 和 `+_visualProviderClassForDrawingState:`、`NSSliderTrack` / `NSSliderDial` / `NSSliderKnob` 的 `drawingState`，以及 `NSSliderVisualProvider-Protocol.h`。
  - Swift 侧的 descriptor 带着 C typedef 标记（见下一节第 2 步）。

**二、为什么不着色、点不了：从编译器到 RuntimeViewer 的一条链**

1. **编译器按 typedef 拼 mangled name。** 对 anonymous tag，`ASTMangler::getClangDeclForMangling`（`lib/AST/ASTMangler.cpp:2915`）改用它的 typedef name；`tryAppendClangName` 碰到 `TypedefNameDecl` 就追加 `a`（`:3237`）。所以它的 mangled name 是 `So20NSSliderDrawingStatea`，结尾的 `a` 表示 typealias，而不是 struct 用的 `V`。
2. **二进制里的 descriptor 带着 C typedef 标记。** 在本机 26.7 cache 的 `dyld_shared_cache_arm64e.01` 里能直接搜到 `NSSliderDrawingState\0St\0`：descriptor 名字后面跟着 import info 分量 `S`（symbol namespace），值是 `t`，也就是 C typedef（`include/swift/ABI/TypeIdentity.h:54`）。在 `.01`、`.05`、`.09` 三个 subcache 里都搜不到字面的 `So20NSSliderDrawingState`，说明 field record 是用 symbolic reference 指向这个 descriptor 的。这和 0023 任务报告对 IRGen `CanSymbolicReference` 的分析一致。
3. **本库从 0023 起把它还原成 `typeAlias` node。** 0023（`1c8d8588`，2026-09-09）之后，`SymbolicDemangler.cImportedTypeIdentity`（`Sources/Analysis/SwiftInspection/SymbolicDemangler.swift:736-737`）对带 C typedef 标记的 descriptor 产出 `typeAlias` node，和运行时 `stdlib/public/runtime/Demangle.cpp:168-169` 一致。0023 之前这里用 descriptor 自己的种类，产出的是 `structure` node；提案 0023 对照表里 `Decimal` 那一行就是这个形态。
4. **打印器给 `typeAlias` 名字打的是 `.standard`。** `TypeNodePrintable.swift:30-40` 把 `.typeAlias` 和 `.enum`、`.structure`、`.class`、`.protocol` 一起交给 `printType`，后者用 `parentKind: name.kind` 打印 identifier（`:202`）。`SemanticString` 的 `write(_:context:)`（`Sources/Output/SwiftDeclarationRendering/Extensions/Node+.swift:36-52`）按 `parentKind` 选 semantic type，但没有 `.typeAlias` 分支，于是落到 `default: .standard`。swift-semantic-string 的 `SemanticType.TypeKind` 本身也只有 `enum`、`struct`、`class`、`protocol`、`other` 这几种。
5. **RuntimeViewer 只给 `.type` token 上色和加链接。** 颜色只看 semantic type：`.type(_, .name)` 用类型名颜色，其余用正文颜色（`ThemePreset+ThemeProfile.swift:103`）。跳转链接也只挂在含 `.type` token 的片段上（`SemanticString+ThemeProfile.swift:162-166` 的 `resolveTargetKind`）；`resolveSwiftLinkTargets` 的注释写明，typealias 引用是有意不给链接的。

**结论：这是 0023 的副作用。** 提案和它的三份任务报告都只比了纯文本，没看 semantic type，所以当时没发现。

**波及面是按代码推断的，没有实测。** 受影响的是所有以 C typedef 为身份的类型：
- CF class，比如 `__C.CGColorRef`；
- `swift_wrapper` typedef，比如 `NSAttributedStringKey`、`NSNotificationName`；
- typedef anonymous struct，比如 `NSDecimal`、`CMTime`、`NSSliderDrawingState`。

这些类型出现在从符号 demangle 出来的位置时（名字里本来就是 `…a`），0023 之前就已经是 `typeAlias` node、不着色。0023 让 field type 这类从 descriptor 推出来的位置也和它们一致了，只不过是一致地不着色。

**三、为什么搜不到：两个独立原因，都在 RuntimeViewer**

- **Swift 侧被过滤了。** 这个 descriptor 就在 AppKit 的 `__swift5_types` 里：26.6.2 的 dump 导出第 270 行是 `struct __C.NSSliderDrawingState {`，后面带着全部字段。但 RuntimeViewer 建 Swift 索引时把 `SwiftDeclarationIndexConfiguration(showCImportedTypes: false)` 写死在了 `RuntimeViewerCore/Sources/RuntimeViewerCore/Core/RuntimeSwiftSection.swift:1208` 和 `RuntimeViewerCore/Sources/RuntimeViewerCore/Indexing/RuntimeSwiftInterfaceIndexer.swift:153`。索引器按这个开关跳过所有 C 导入的 descriptor（本仓库 `Sources/Declaration/SwiftIndexing/SwiftDeclarationIndexer.swift:495`）。按 `git log -S` 看，这个写法至少从 `9b48c942`（2026-01-05）起就在了。
- **ObjC 侧根本没有这个名字。** 侧边栏的「C Struct」来自 `objcIndexer.structNames`（`RuntimeObjCSection.swift:105-106`），是从 ObjC type encoding 里收集的，而且只收有名字的 struct（MachOObjCSection `Sources/ObjCIndexing/ObjCInterfaceIndexer.swift:218-219` 的 `if let name`）。`NSSliderDrawingState` 在 encoding 里是 `{?=…}`，这个名字在 ObjC 元数据里根本不存在。

所以二进制里唯一同时带着这个名字和字段定义的，是 Swift 侧这个 C 导入类型的 descriptor，而它恰好被过滤掉了。

**四、顺带看到、没深究的两点**

- **字段偏移的两处说法不一样。** 26.6.2 的 dump 里，`__C.NSSliderDrawingState` 自己的条目每个字段都写着 `Field offset: unknown (C-imported type; field offsets not derivable from reflection)`；可在 `NSSliderAquaduckVisualProvider` 的 expanded field tree 里，同一批字段都有具体偏移。
- **旧导出的类型名和现在不同。** 本机旧导出（26.5.2 的 `AppKit.NSSliderAquaduckVisualProvider.swiftinterface`，以及 26.6.2 那份由 swift-section 0.19.0 生成的 dump）把同一批字段写作 `__C.SliderType` / `__C.ControlSize`；用户截图（当前 `next`）里是 `__C.NSSliderType` / `__C.NSControlSize`。这和 0023 的 ABI name 规则一致，同类例子是 `__C.Style` → `__C.NSTableViewStyle`。不过两份旧导出的生成版本是否早于 0023，没有核实。

**五、0023 影响评估：已有什么、还缺什么**

- **已有：**
  - [2026-09-09-type-import-info-identity](2026-09-09-type-import-info-identity.md) 做过 SwiftUI 和 Foundation 的纯文本前后对比。
  - [2026-09-10-c-imported-extension-kind-from-descriptor](2026-09-10-c-imported-extension-kind-from-descriptor.md) 用 `runtime-viewer-cli` 对比过 SwiftUICore 侧边栏的对象清单，并修掉了 `__C.AGSubgraphRef` 从 Class Extension 掉到 Struct Extension 的退化。
  - [2026-09-10-remove-primitive-type-mapping](2026-09-10-remove-primitive-type-mapping.md) 删的是死代码，不改输出。
- **还缺：** 所有库的 semantic 维度（着色和链接）都没看过；AppKit、UIKitCore、CoreFoundation 三个库完全没比过。
- **对比哪两个提交：**
  - 0023 前的最后一个提交是 `7071ac46`，0023 本身是 `1c8d8588`，两者之间 `Package.swift` 没变。
  - `e4783365`（删 `PrimitiveTypeMapping`）和 `296f192c`（extension 的 kind 改按 descriptor 定；按报告，它不改 dump / interface 文本）是 0023 的延续。
  - 中间还夹着三批与 0023 无关的提交：0024（给类型和协议定义带上导出状态）、0025（property descriptor 建模）、0026（补五种缺失的 ABI 结构）。
  - 所以拿 `7071ac46` 对比 `1c8d8588`，量出来的就是 0023 对输出的直接影响。

**六、A/B 的技术准备（已查明，未执行）**

- **着色可以直接用 CLI 量。** `interface` 和 `dump` 都有 `--color-scheme`。在当前 `next` 的 `withColorHex(for:colorScheme:)`（`Sources/Executables/swift-section/Utilities/Extensions.swift`）里，`.type(_, .name)` 统一用一种颜色（dark 下是 `#D0A8FF`），`.standard` 不上色，所以「掉色」能从 ANSI 输出里直接看出来。但 NS_ENUM 从 `enum` 改成 `structure` 这类变化只改链接目标的 kind、不改颜色，这样看不出来。`1c8d8588` 时两个命令都有 `--color-scheme`，颜色映射没有逐行核对。
- **录彩色输出要套伪终端。** Rainbow 只在 stdout 是终端、且设了 `TERM` 时才输出颜色（`OutputTarget.current` 会检查 `isatty`）。`FORCE_COLOR` 只影响 `Rainbow.enabled`，对非终端目标，`generateString` 照样返回纯文本。所以要用 `script -q <file> <command>` 之类的办法套伪终端，再用去掉 ANSI 的版本做文本 diff。
- **`1c8d8588` 时的 CLI 选项：**
  - `interface`：`--emit-offset-comments`、`--emit-expanded-field-offsets`、`--emit-type-layout`、`--emit-enum-layout`、`--show-c-imported-types`、`--resolve-c-module-names`。
  - `dump`：`--emit-field-offsets`、`--emit-type-layout`、`--emit-expanded-field-offsets`、`--emit-enum-layout`。
  - 读本机 cache：`--uses-system-dyld-shared-cache --cache-image-path <path>`。
- **依赖必须两侧对齐。** `Package.resolved` 被 gitignore 了，依赖又是按范围写的。`7071ac46` 时的范围是：MachOKit `0.52.101..<0.53.0`、MachOObjCSection `0.8.105..<0.9.0`、swift-demangling `0.6.3..<0.7.0`、MachOKitExtensions `from: "0.1.1"`、swift-semantic-string `from: "0.3.0"`。9 月 9 日之后，这些范围里又发了 MachOKit 0.52.103、MachOObjCSection 0.8.106 / 0.8.107、MachOKitExtensions 0.1.2 / 0.1.3、swift-semantic-string 0.4.0。两侧必须共用同一份 `Package.resolved`；旧代码能不能在这些今天的最新版本上编译通过，还没验证。
- **构建要排队。** 这台是 `JHs-Mac-Studio`（10 核），`queued-build` 全机串行。当时队列被另一个会话的 release `swift test`（`RenderingVerificationTests`）占着。

### 候选方案

没有做取舍，只列出可以改的地方：

| 方案 | 位置 | 优点 | 缺点 |
|------|------|------|------|
| A. 打印器按 descriptor 的真实种类，给 `__C` 下的 `typeAlias` 打 `.type(.struct / .class, .name)` | `Sources/Output/SwiftDeclarationRendering/Extensions/Node+.swift:36-52`，另外需要一条在打印时拿到 descriptor 种类的途径 | 恢复着色，不动 0023 的身份规则 | 打印时手里只有 node，`typeAlias` 树分不出 CF class 和 typedef struct（`296f192c` 修的就是同一个问题），要额外去查 descriptor |
| B. `typeAlias` 一律打 `.type(.other, .name)` | 同上 | 改动最小，能恢复着色 | RuntimeViewer 对 Swift 侧的 `.other` 不给链接；还要确认会不会波及原生 Swift typealias 引用（RuntimeViewer 的注释说它们是有意不给链接的） |
| C. RuntimeViewer 把 C 导入类型收进索引 | RuntimeViewer `RuntimeViewerCore/Sources/RuntimeViewerCore/Core/RuntimeSwiftSection.swift:1208`、`RuntimeViewerCore/Sources/RuntimeViewerCore/Indexing/RuntimeSwiftInterfaceIndexer.swift:153` | 能搜到，也能跳过去 | 直接放开会让侧边栏多出大量 `CGRect`、NS_ENUM 之类的条目；可以考虑只进搜索和跳转，不进默认列表 |

A 或 B 最好和 C 一起做。只改着色的话，会出现有颜色但点不过去的链接。

## 3. 最终方案

还没有定方案。用户先要解释，再要 0023 的影响评估；评估在准备 A/B 时被用户叫停，改为先把这份报告写下来。修不修、按哪个方案修、A/B 要不要继续，都等用户决定。

## 4. 实际执行与改动

### 改动清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `Documentations/Internal/TaskReports/2026-09-30-c-imported-typedef-types-uncolored-in-runtimeviewer.md` | 新建 | 本报告 |
| `/Volumes/DerivedData/Agents.noindex/claude/SourceExports/MachOSwiftSection-7071ac46` 和 `…/MachOSwiftSection-1c8d8588` | 新建（在仓库外） | A/B 用的 `git archive` 源码导出，各约 12 MB，还没构建；不用了可以删 |

没有改动任何源代码。

### 关键命令

在本机 cache 里搜 descriptor 名字后面的 import info，以及字面的 mangled name：

```bash
cd /System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/
LC_ALL=C grep -a -o -b -E 'NSSliderDrawingState\x00[A-Za-z][A-Za-z0-9_]*\x00' dyld_shared_cache_arm64e.01
LC_ALL=C grep -a -c 'So20NSSliderDrawingState' dyld_shared_cache_arm64e.01
```

第二条命令对 `.05` 和 `.09` 也各跑了一次，三个 subcache 的结果都是 0。

A/B 用的源码导出：

```bash
git archive 7071ac46 | tar -x -C /Volumes/DerivedData/Agents.noindex/claude/SourceExports/MachOSwiftSection-7071ac46
git archive 1c8d8588 | tar -x -C /Volumes/DerivedData/Agents.noindex/claude/SourceExports/MachOSwiftSection-1c8d8588
```

被用户拒绝、没有执行的一步：在 `7071ac46` 的导出上跑 `swift package resolve`，scratch path 是 `/Volumes/DerivedData/Agents.noindex/claude/SwiftPM/MachOSwiftSection-Pre0023`。

### 验证

只有只读的证据：没有构建、没有跑测试，也没有跑 RuntimeViewer。
- **直接看到的：** import info 里的 `St` 是字节级搜出来的。
- **读代码得出的：** 着色失效的那条链。
- **推断、未实测的：** 「波及所有以 C typedef 为身份的类型」和「符号位置在 0023 之前就不着色」。

### 与原方案的差异

- **差异点**：计划中的 0023 A/B 没有执行。原计划是 `7071ac46` 对比 `1c8d8588`，六个库都跑 `interface` 和 `dump`，同时比纯文本和 ANSI 着色。
- **原因**：解析依赖那一步被用户叫停，改为先写报告。
- **影响**：六个库还没有量化数字。现有的数字只有旧报告里 SwiftUI、Foundation（文本）和 SwiftUICore（侧边栏）那几组。

### 恢复 A/B 时的步骤

1. 在 `7071ac46` 的导出上解析一次依赖，把得到的 `Package.resolved` 复制到 `1c8d8588` 的导出，两侧共用。
2. 两侧各跑一次 `queued-build swift build -c release --product swift-section`，放后台。scratch path 分别用 `/Volumes/DerivedData/Agents.noindex/claude/SwiftPM/MachOSwiftSection-Pre0023` 和 `…-Post0023`。
3. 对六个库各跑 `interface`（带上布局注释选项）和 `dump`，都加 `--color-scheme dark`，用 `script -q` 套伪终端录下 ANSI 输出。两个待确认的点：
   - macOS cache 里的 UIKitCore 是 Mac Catalyst 版，路径还没确认；
   - CoreFoundation 先确认有没有 `__swift5_*` section。
4. 去掉 ANSI 后做文本 diff，看改名和 conformance 块重排。再按 `__C.<名字>` 统计同一个名字在两侧着色和不着色的次数，得出掉色清单。

下一次会话可以用的 skill：
- `xcode-build-and-test`：排队构建和 scratch path；
- `swift-section:swift-section-cli`：CLI 选项；
- 决定修复时用 `evolution` 写轻量提案，用 `write-tests` 先写一条能变红的着色回归测试。
