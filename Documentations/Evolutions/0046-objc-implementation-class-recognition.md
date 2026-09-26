# 0046 - 识别 `@objc @implementation` 类：ObjC class 数据与 Swift 符号的联合归属

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-09-20
- **最后更新**: 2026-09-26
- **所属愿景**: 无
- **关联提案**: [0018-self-contained-abi-layer](0018-self-contained-abi-layer.md)（符号归属一律放 SwiftInspection，本提案的联合索引沿用这个归宿）、[0007-extension-container-dedup-and-default-impl-attribution](0007-extension-container-dedup-and-default-impl-attribution.md)（extension 容器合并，新加的事实必须在合并时保留）、[0016-exported-only-interface](0016-exported-only-interface.md)（`--exported-only` 对这类 extension 的裁决不动）
- **实现分支 / PR**: `feature/objc-implementation-class-recognition`（worktree `.worktrees/MachOSwiftSection-ObjCImplementationClasses`，自 `next` 分出）
- **配套文档**: [ObjCImplementationClassRecognition.md](../Internal/ObjCImplementationClassRecognition.md)（实现说明）、[TaskReports/2026-09-20-objc-implementation-class-recognition.md](../Internal/TaskReports/2026-09-20-objc-implementation-class-recognition.md)（过程复盘）

## 摘要

SE-0436 的 `@objc @implementation extension` 让一个在 ObjC 头文件里声明的类由 Swift 实现。编译器把这样的类编成一个**纯 ObjC class object**：`__swift5_types` 里没有它的 nominal type descriptor，`__swift5_fieldmd` 里没有 field descriptor，class data 指针上的 Swift bit 是 0。Swift 侧留下的只有三样东西：成员符号（mangle 成「模块 M 对 `__C.<类>` 的 extension」）、每个存储属性一个 `Wvd` 字段偏移全局变量、以及本镜像定义的 metadata accessor `$sSo<类>CMa`。Apple 已经大量采用：macOS 26.7 的 AppKit 里有 38 个这样的类（NSGlassEffectView 全家、NSScene 全家、NSScreen、NSGradient、NSBackgroundExtensionView 等），Catalyst 的 UIKitCore 里约 115 个（UIHoverStyle、UIShape、UICornerConfiguration、UIScrollEdgeEffect 等公开类都在内）。

今天 `swift-section interface` 把它们打成普通的 `extension __C.NSGlassEffectView { … }`：存储属性退化成 `{ get set }` 计算属性，`@objc` 和 `@implementation` 都不出现，ivar 的偏移与大小一个都没有；`dump` 只走 `__swift5_*` 段，完全看不到它们。本提案给两条路径都加上识别：在 SwiftInspection 建一个联合 ObjC classlist 与 Swift 符号表的 per-image 索引；interface 把这类 extension 标成 `@objc @implementation` 并把存储属性还原成带 `Field offset` 注释的 `var`；dump 新增一段 `objcImplementationClasses`，把 ObjC 侧与 Swift 侧能读到的全部事实打出来。

## 方案

### 二进制里到底有什么（fixture 与 AppKit 实测，编译器源码佐证）

fixture 是一个 `@objc @implementation extension Widget`（三个存储属性，其中一个 `final var` 是 Swift-only），加一个普通 Swift 类和一个普通 `extension NSNumber` 作对照，用 Swift 6.3.3 编成 dylib 后逐项核对：

| 事实 | fixture / AppKit 观测 | 编译器源码依据 |
|---|---|---|
| class object 是 5 个 word 的纯 ObjC 形态，Swift bit 为 0 | `otool -ov` 对普通 Swift 类打印 `Swift class`，对 Widget 不打印；RuntimeViewer 导出的 AppKit 头文件里 NSGlassEffectView 的 11 个 ivar 全是 `Unknown` | `ClassMetadataVisitor::layout()` 的 `isPureObjC()` 分支只放 isa / superclass / cache / data 四个字段；`getClassDataPointerHasSwiftMetadataBits()` 断言 `!isPureObjC()`，即 Swift bit 永远不会被置上 |
| 没有 nominal type descriptor，没有 field descriptor | fixture 的 `__swift5_types` 只有 4 字节（对照类那一条）；AppKit 的 `dump --sections types` 里 grep 不到 `__C.NSGlassEffectView` 本身，只有它的嵌套类型 | `emitExtension` 对主 `@implementation` 块调 `emitClassDecl`，而 `GenReflection.cpp` 对 `getObjCImplementationDecl()` 非空的 class 把 `needsFieldDescriptor` 置为 false |
| 成员符号 mangle 成 extension | `$sSo6WidgetC11ImplFixtureE7refreshyyF`，每个 `@objc` 成员另有 `To` thunk（非导出，OS 框架里被 strip） | 成员的 DeclContext 就是那个 extension |
| 存储属性同时留在两边 | ObjC ivar list 有 name / offset / size / alignment / type encoding；Swift 侧有 `…vpWvd` 字段偏移全局变量，demangle 后带属性名与 Swift 类型。AppKit 导出了 55 个这样的符号（15 个类） | `GenClass.cpp buildIvar`：类型不能 trivially represent 到 ObjC 的写 `?`，非 `@objc` 的存储属性写空串；clang 从不会写这两种 |
| 本镜像定义 metadata accessor | `$sSo6WidgetCMa` 在 fixture 里是外部符号，`strip -x` 后仍在；AppKit 导出表里有 `$sSo17NSGlassEffectViewCMa`；对照的 `extension NSNumber` 没有任何 `So8NSNumberCMa` | `MetadataRequest.cpp` 的注释明说 `@implementation` 类会被发出 accessor，普通 imported 类走 `swift_getInitializedObjCClass` 内联 |
| category 形式的 `@implementation` 分不出来 | `@objc(Extras) @implementation` 的方法被链接器合并进主类方法表，mangling 也不带 category 名 | 链接器的 category 合并优化，编译器侧无标记 |
| `.cxx_destruct` 是 Swift 的 ivar destroyer | 方法表最后一项 IMP 是 `$sSo6WidgetCfETo` | `addIVarDestroyer()` |

普查方法是「导出表里有本镜像定义的 `$sSo<类>CMa`」，属于符号级证据，剥符号后仍成立（系统框架不 strip 导出表）：

| 镜像（macOS 26.7 系统 cache） | `So…CMa` 命中的 `__C` 类 | 其中带 `…vpWvd` 存储属性导出的类 |
|---|---|---|
| AppKit | 38 | 15（55 个存储属性） |
| UIKitCore（Catalyst） | 约 115 | 4（8 个存储属性） |

今天 interface 对 NSGlassEffectView 的实际输出（节选）：

```swift
extension __C.NSGlassEffectView {
    class ContentHolderView: __C.NSView { … }
    enum Legibility { … }
    init?(coder: __C.NSCoder)
    var _scrimState: __C._NSGlassEffectViewScrimState {
        get
        set
    }
    var contentView: __C.NSView? {
        get
        set
    }
    func viewWillMove(toWindow: __C.NSWindow?)
}
```

四个问题：声明性质说错了（它是类的主体，不是 extension）；存储属性打成了计算属性；没有 `@objc`，因为 `@objc` 推断只在 `TypeDefinition.index` 里做，extension 路径没接；ivar 的偏移和大小明明在 ObjC 侧和 `Wvd` 全局变量里，却一个没渲染。

### 判据与证据分级

前置条件：类 C 由本镜像的 `__objc_classlist` 定义，且 class data 指针的 Swift bit 为 0（`ObjCClassProtocol.isSwiftStable == false`）。满足前置条件后分三档：

- **definitive**：以下任一成立即判定。(a) 导出表里有 `$sSo<C>CMa`——只有实现该类的主模块会发出 public unique accessor；imported 类的 formal linkage 是 `PublicNonUnique`，任何用到它 metadata 的镜像都会发一个 hidden 的 non-unique accessor，dyld cache 的本地符号表里也留着，所以符号表里「有」不算数，必须是导出的；(b) 存在 `…vpWvd` 符号，demangle 出的 variable 的 context 是 `(extension in M):__C.C`。C 自身方法表的 IMP 地址上的 Swift 符号只作佐证（见决策日志）。
- **inferred**：没有任何上述符号，但 C 的 ivar 列表里至少一个 type encoding 是 `?` 或空串。同镜像里的普通 Swift 类也会有这种 encoding，但它们 Swift bit 为 1，已被前置条件排除。渲染时在头部加注释 `// inferred from ObjC class data: N ivar(s) carry Swift-style type encodings`。
- **否则不判定**：视作 clang 编的类。即使本镜像有它的 Swift extension 成员，也维持今天的 `extension` 形态，因为那是 category，不是类主体。

三个反例是判据的边界：普通 Swift extension of imported class 只产生 category，类不由本镜像定义，前置条件不满足；clang 类加同镜像的 Swift extension，前置条件满足，但没有 accessor、没有 `Wvd`、自身方法表的 IMP 都是 `-[C sel]`、ivar encoding 完整，三档都不命中；普通 Swift 类有 ObjC 祖先，Swift bit 为 1，前置条件不满足。

### 改动清单（位置优先）

1. **新增 `Sources/SwiftInspection/ObjCImplementationClassIndex.swift`**。reader-split，照 `Sources/SwiftLayout/ObjCClassIndex.swift:33` 与 `:51` 遍历 `machO.objc.classes64` 的写法。产出 per-image 的 `bare class name → ObjCImplementationClassFacts`，每条含：证据档位与理由列表；superclass 名；`class_ro_t` flags / instanceStart / instanceSize；ivar 列表（name、offset、size、alignment、encoding，以及按 offset 对上的 `Wvd` 符号与其 Swift 类型节点）；方法表（selector、type encoding、IMP 地址、IMP 地址上的 Swift 符号）；属性表（name、attributes）；ObjC protocol 列表；metadata accessor 符号。符号侧用 `SymbolIndexStore.containsSymbol(named:in:)` 查 accessor，用 `symbols(of: .fieldOffset, in:)` 取 `Wvd`；若 sweep 今天没把 `fieldOffset` 收进 `symbolsByKind`，就在 sweep 里补这一类。每镜像只建一次，惰性，缓存与清理沿用 `MultiPayloadEnumDescriptorCache` 的 per-image 模式。方法表的 list-of-lists 形态用 `ObjCClassRODataProtocol.methodRelativeListList(in:)` 读。
2. **`Sources/SwiftDeclaration/Components/Definitions/ExtensionDefinition.swift:11`** 加 `public package(set) var objcImplementation: ObjCImplementationFacts?`，以及一个由 ivar 与 `Wvd` join 出来的存储属性列表（名、Swift 类型节点或 nil、offset、size、encoding）。`absorbMembers(of:)`（同文件约 161 行）合并时 OR 保留这个事实，因为 0007 的容器合并会把嵌套类型发现线与成员符号线的两个定义合成一个。
3. **`Sources/SwiftIndexing/SwiftDeclarationIndexer.swift:787 indexExtensions()`**：对目标是 `__C` class 的 extension，按 bare name 查第 1 步的索引，命中就挂上事实；同时把 `applyThunkAttributes` 的 `@objc` / `@nonobjc` 推断（今天只在 `TypeDefinition.index` 里对类型做）用 `inExtension` 的 member kind 对 extension 成员也做一遍，有 `To` 符号的成员就能得到 `@objc`。派发新事件 `objcImplementationClassRecognized(context:)`（信息类），class 数据读不出来时派发失败事件并在 `Payload.unhandledFailureDescription` 里显式登记。
4. **`Sources/SwiftPrinting/SwiftDeclarationPrinter.swift:417 printExtensionHeader`**：事实非空时在 `extension` 前打 `@objc @implementation `，inferred 档在头部行尾加上面那条注释。**`:366 printIncludedExtensionDefinition`**：在成员之前渲染存储属性。有 `Wvd` 的打 `var name: Type`；只有 ivar 没有 `Wvd` 的打一行诚实注释 `// stored property <name>: Swift type not recoverable (ObjC ivar, size N, encoding "?")`，不编类型。`--emit-offset-comments` 打开时每条带 `// Field offset: 0x…`，走 `SwiftFieldOffset` transformer 模板，模板选项照常生效。存储属性一律不再作为 `{ get set }` 计算属性重复出现：按 offset 对上的 `Wvd` 名字在 variables 里的同名项改为存储属性形态，accessor 信息保留在 `FieldDefinition.accessors` 一样的位置。
5. **dump 新段**。`Sources/swift-section/Models/SwiftSection.swift:3` 加 `case objcImplementationClasses`，进 `allCases` 默认开启；`Sources/swift-section/Commands/DumpCommand.swift:15 TopLevelContext` 加一个 case，offset 取 class object 在 `__objc_data` 里的偏移，让 `--preferred-binary-order` 也能排它。新增 `Sources/SwiftDump/Dumpable/ObjCImplementationClass+Dumpable.swift` 与 `Dumper/ObjCImplementationClassDumper.swift`，体例照 `ClassDumper`：头部一行 `@objc @implementation extension Widget`，后跟注释 `/* ObjC class Widget: NSObject, class_ro_t flags 0x184, instanceStart 8, instanceSize 40, evidence: … */`；然后四段，每段都来自索引里已经读好的数据：

```swift
/* Stored properties (ObjC ivars) */
var title: Swift.String // offset 0x8, size 16, encoding "?"
var count: Swift.Int // offset 0x18, size 8, encoding "q"
final var swiftOnlyCache: [Swift.Int] // offset 0x20, size 8, encoding ""

/* ObjC methods */
-[Widget describe] // types "@16@0:8", imp 0x13cc, $sSo6WidgetC11ImplFixtureE8describeSSyFTo
-[Widget .cxx_destruct] // types "v16@0:8", imp 0x12ec, $sSo6WidgetCfETo

/* ObjC properties */
title // T@"NSString",N,C
count // Tq,N,Vcount

/* Swift members */
(extension in ImplFixture):__C.Widget.refresh() -> ()
…
```

   Swift members 段沿用 `ClassDumper` 的成员段做法，用 `symbolIndexStore.memberSymbols(of:for:node:in:)` 取 `inExtension` 各 kind。`--emit-member-addresses` / `--emit-export-status` 等现有开关对这一段同样生效。IMP 地址上没有符号就只打地址，不猜名字。

6. **事件与 handler**：`Sources/SwiftDeclaration/Events/SwiftIndexEvents.swift` 加两个 case，`ConsoleEventHandler` / `OSLogEventHandler` / `SwiftIndexEventReporter` 补对应分支。
7. **测试**：新增一个即时编译的 fixture（ObjC header 加 `-import-objc-header`，至少保留一个类以避开 MachOKit 无 `__DATA` 段的已知崩溃），三个变体各测一档：原样（definitive，三种符号都在）、`strip -x`（definitive，只剩导出的 accessor）、以 `-Xlinker -exported_symbols_list /dev/null` 编译再 `strip -x`（inferred，只剩 ivar encoding）。反例测试：同 fixture 里的 `extension NSNumber` 和普通 Swift 类都不得命中。系统 cache 门控测试（照 `GraphHostVTableAttributionTests` 的门控方式）：AppKit 的 NSGlassEffectView 判定为 definitive 且还原出至少 9 个存储属性，NSScreen 与 NSGradient 命中，NSView 作为 clang 类加同镜像 Swift extension 的反例不得命中。interface 与 dump 的快照测试各加一份。
8. **文档**：落地时写 `Documentations/Internal/ObjCImplementationClassRecognition.md`，AGENTS.md 的 SwiftInspection / SwiftIndexing / SwiftDump 条目各加一段，`ProjectEvolutionLog.md` 加节，术语表条目本批已登记。

### 明确不动的地方

- `MachOSwiftSection` ABI 层不读任何 ObjC 数据，0018 的自包含边界不变。
- `ABIDiffer` 的容器 key 与 `MemberRecord` 投影不变，`ABISnapshot.formatVersion` 停在 4：存储属性只渲染，不进快照。一个类从 clang 实现改成 `@implementation` 不是 Swift ABI 变化，所以这个事实也不进容器 key。
- `--exported-only`（0016）的 extension 裁决不变：`ExportFilterScope` 建自 Swift 类型表，这类 ObjC 类不在表里，extension 按既有规则保留。
- 不做 selector 反推 `@objc`：ObjC selector 到 Swift 名字的 importer 规则反过来推有歧义（`viewWillMoveToWindow:` 对应 `viewWillMove(toWindow:)`，而不是任何机械拼接），而 `@implementation` 头部本身已经表示成员默认 `@objc`。有 `To` 符号时沿用现有的 thunk 归属。
- category 形式的 `@implementation` 块与主块合并显示，二进制上分不开。
- RuntimeViewer 不需要改 UI，它消费同一个声明模型。

### 验证

`swift test --skip IntegrationTests` 全绿；上面第 7 条的 fixture 三档与系统 cache 门控测试全部通过；`Scripts/run-rendering-ab-verification.py` 的 dump 侧预期出现差异，差异必须**仅由新增块构成**（新段默认开启），interface 侧只在含 `@implementation` 类的镜像上出现差异且仅限那些 extension 块。实施时先用 `So…CMa` 普查确认六个 A/B 框架里哪些含这类类，把预期差异写进 A/B 记录。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-20 | Created as Draft | 用户先问「SE-0436 这种能够识别的出来吗？」，随后指出 Apple 已大量采用（NSGlassEffectView），最后说「写提案」。fixture 与 AppKit 实测、编译器源码核对见方案第一节 |
| 2026-09-20 | interface 与 dump 两条路径都做，dump 以信息最大化为目标 | 用户决定 |
| 2026-09-20 | 保留结构性的 inferred 档并显式标注 | 用户决定。覆盖导出表也被 strip 的 app 可执行文件；误报需要 clang 类带 `?` 或空 encoding 的 ivar，罕见 |
| 2026-09-20 | 还原出的存储属性不进 ABI 快照 | 用户决定。ivar 布局属于 ObjC ABI，Swift ABI differ 本来也不比字段偏移；formatVersion 不变，旧基线继续可比 |
| 2026-09-20 | 联合索引放 SwiftInspection | 它已经依赖 MachOObjCSection 与 MachOFoundation，位于 SwiftDump 与 SwiftDeclaration 之下，两条路径共用；0018 已把符号归属放在这一层。SwiftLayout 是布局引擎，语义不对 |
| 2026-09-20 | 不做 selector 反推 `@objc` | 见「明确不动的地方」 |
| 2026-09-20 | dump 新段默认开启 | 信息最大化；A/B 预期差异只应是新增块，实施时逐一核对 |
| 2026-09-20 | 存储属性与 ivar 的 join 键用 offset，名字只作次要校验 | fixture 里 header 声明的 `title` 属性其 ivar name 字段是空指针，`Wvd` 全局变量的值就是 ivar offset，按 offset 对最稳 |
| 2026-09-20 | Draft → Accepted | 用户看过提案后说「开工」，视为批准 |
| 2026-09-20 | Accepted → In Progress | 建 worktree 开始实现；提案里的 `文件:行号` 以 `next` 分支为准重新核对 |
| 2026-09-20 | IMP 处的 Swift 符号从「确定性证据 (c)」降为佐证 | 实现时发现要判定它得先读每个 clang 类的方法表，索引的代价会变成一次 class-dump；改为只对 accessor / `Wvd` / ivar encoding 命中的类读方法表，符号只写进证据说明 |
| 2026-09-20 | ivar 与 `Wvd` 的 join 改按「`Wvd` 全局变量的值 == ivar 偏移」 | ObjC reader 里解析 ivar offset 指针的 fixup 接口被 `#if false` 掉了；读 `Wvd` 的值等价且只用公开 API |
| 2026-09-20 | 没有任何成员符号的命中类合成一个空 `ExtensionDefinition` | 否则 inferred 档在 interface 里无处落脚：全 strip 的镜像没有成员符号就没有 extension，类会整个消失 |
| 2026-09-20 | thunk 归属抽成 `MemberAttributeApplication`，对所有 extension 成员生效 | 方案第 3 条的落地形态；副作用是含 `@objc` extension 成员的 interface 输出多出 attribute，A/B 时逐条核对 |
| 2026-09-20 | 头部 attribute 与 inferred 标注都留在 header 同一行 | diff / evolution 渲染器锚定容器的最后一行 header，多一行会挪锚点 |
| 2026-09-20 | `ObjCImplementationClassFacts` 与 `InstanceVariable` 做成不可变 final class | 第一版是 struct，`ExtensionDefinition` 实例从 ≤ 320 B 涨到 360 B，`DeclarationModelInstanceSizeTests` 红；每个 `VariableDefinition` 也会内联一份约百字节的 ivar 事实。改成引用后各占 8 B |
| 2026-09-20 | accessor 证据只认导出表里的那个 | 渲染 A/B 抓到误报：SwiftUICore 里 clang 编的 `DateFormattingContext` 被认成 `@implementation`，因为 cache 的本地符号表里有一个 hidden 的 non-unique `$sSo21DateFormattingContextCMa`（`MetadataRequest.cpp`：imported 类的 `PublicNonUnique` linkage 走 `NonUniqueAccessor`，谁用谁发）。改为 `isExported == true` 才算；fixture 的 clang 反例补了一句 `String(describing: ClangWidget.self)` 让它也带上这种 accessor（一个空数组字面量不够，优化后不实例化 metadata） |
| 2026-09-20 | In Progress → Implemented | 实现连同文档合入 `next`；配套文档（实现说明、任务报告）已登记在头部，术语已入术语表；编号按仓库惯例在发布合入 `main` 时分配 |
| 2026-09-26 | 落地编号 0046 | 已于 2026-09-20 随 `584f1ff7` 起的一组提交 合入 `next` 并标为 Implemented，但当时没有取号；0.20.0 发版收尾时按合入顺序补取 |
