# 2026-09-20 识别 `@objc @implementation` 类：从「能识别吗」到两条输出路径都接上

## 起点

用户问：SE-0436 这种（`@objc @implementation extension`）能识别出来吗？答复给出结论「现在识别不出来，二进制里线索够」之后，用户补充 Apple 已大量采用，NSGlassEffectView 就是。核实后确认：macOS 26.7 的 AppKit 有 38 个这样的类，Catalyst UIKitCore 约 115 个；当时的 `interface` 把它们打成普通 `extension __C.X`，存储属性退化成 `{ get set }`，`dump` 完全看不到。用户说「写提案」，提案落盘后说「开工」。

## 调研发现

**编译器往二进制里写了什么**（Swift 6.3.3 即时编译 fixture + `swift-project` 源码核对）：

- 类对象是纯 ObjC 形态。`ClassMetadataVisitor::layout()` 的 `isPureObjC()` 分支只放 isa / superclass / cache / data；`getClassDataPointerHasSwiftMetadataBits()` 断言它不会为这种类运行，所以 Swift bit 永远是 0。
- 没有 nominal type descriptor 与 field descriptor：`emitExtension` 对主 `@implementation` 块调 `emitClassDecl`，但 `GenReflection.cpp` 对 `getObjCImplementationDecl()` 非空的 class 关掉 field descriptor。fixture 的 `__swift5_types` 只有对照类那 4 字节。
- Swift 侧剩三样：extension 形态的成员符号（`$sSo6WidgetC11ImplFixtureE…`）与 `To` thunk、每个存储属性一个 `Wvd` 字段偏移全局变量、本镜像定义的 `$sSo<类>CMa`（普通 imported 类走 `swift_getInitializedObjCClass` 内联，`MetadataRequest.cpp` 的注释明说只有 `@implementation` 会发 accessor）。
- ObjC 侧：ivar 的 type encoding 由 `GenClass.cpp buildIvar` 写，非 ObjC 可表示类型写 `?`，非 `@objc` 的存储属性写空串，clang 不会这样写；方法表的 IMP 全是 `To` thunk；`.cxx_destruct` 是 `$sSo6WidgetCfETo`。
- category 形式的 `@implementation` 被链接器合并进主类方法表，mangling 也不带 category 名，分不开。

**普查方法**：`dyld_info -exports` 里找本镜像定义的 `$sSo<类>CMa`，剥符号后仍成立（系统框架不 strip 导出表）。AppKit 38 个、UIKitCore 约 115 个；六个 A/B 框架里为零（SwiftUI 唯一一个命中是嵌套类型 `NSWindow.HostingSheetRepresentation` 的 accessor，判据要求 class node 只有 module 与 identifier 两个孩子，不会误判）。

**一个改掉方案形状的发现**：方案初稿把「IMP 处的 Swift 符号」列为第三种确定性证据，落地时发现要判定它得先读每个 clang 类的方法表，镜像里绝大多数类是 clang 类，索引的代价会变成一次 class-dump。改为只对 accessor / `Wvd` / ivar encoding 命中的类读方法表，IMP 处的符号只写进证据说明。

**一个把 join 键改掉的发现**：fixture 里头文件声明的 `title` 属性其 ivar name 字段是空指针，按名字 join 会漏；ivar_t 的 offset 指针指向的正是 `Wvd` 符号命名的那个全局变量，但 ObjC reader 解析该指针的 fixup 接口被 `#if false` 掉了，最终按「`Wvd` 全局变量的值 == ivar 偏移」join，名字只作兜底。

**一个让 inferred 档有处落脚的发现**：全 strip 的镜像没有成员符号就没有 extension，索引认出来的类在 interface 里会整个消失。给这种类合成一个空 `ExtensionDefinition` 承载事实。

## 最终方案

三个用户决定：interface 与 dump 都做、dump 信息最大化；保留 inferred 档并标注；存储属性不进 ABI 快照。我定的：索引放 SwiftInspection；不做 selector 反推 `@objc`；dump 新段默认开启；join 按偏移值；thunk 归属抽成共享实现让 extension 成员也拿到 `@objc`；facts 做成不可变 final class（第一版 struct 让 `ExtensionDefinition` 涨到 360 B，撞了实例大小上限测试）。

## 执行

按提案的改动清单落地，位置见实现说明 [ObjCImplementationClassRecognition.md](../ObjCImplementationClassRecognition.md)。代码分五个 commit（inspection / declaration+indexing / printing / dump / test），文档一个。

## 验证

- 新增测试：`ObjCImplementationClassRecognitionTests`（fixture 三档 + 反例 + hidden accessor 反例 + 事件，9 例）、`AppKitObjCImplementationClassTests`（系统 cache，macOS 26 门控，1 例）、`ObjCImplementationClassDumpTests`（3 例）、`DumpSectionsOptionTests`（1 例），全部通过。
- 全量 `swift test --skip IntegrationTests`：最终一轮 1966 例 / 377 套件，剩 3 个问题，全是已知的并行环境假失败——`SharedCacheTests` 三例用墙钟断言并行度，单独跑通过。此前一轮还出现过 `ProtocolRecordTests` 三例的 in-process fixture 偏移抖动（`fromImage → -6442124264`，即文件偏移减 0x180000000），同样单独跑通过。第一轮的 1103 个问题几乎全是 fixture 二进制缺失：`/tmp/claude/DerivedData` 里没有 `SymbolTests`，按 CI 的 ad-hoc 签名设置重建后消失。
- 实测输出：fixture 三个变体的 dump / interface 形态与提案预期一致；AppKit dump 段命中 38 个类，与普查逐一吻合；interface 里 NSGlassEffectView 打成 `@objc @implementation extension __C.NSGlassEffectView`，9 个有 `Wvd` 的存储属性打成 `var`，11 个没有的打成诚实注释。
- 渲染 A/B：见下节。

## 渲染 A/B

基线是分支起点 commit（`next` 的 f6120d80）的 detached 检出 `.worktrees/MachOSwiftSection-ABBaseline`（照 0035 的经验，不用 `next` worktree 本身，它的 `Package.resolved` 会被构建改写），候选是本分支，两侧各自独立的 scratch 目录、同一份 `Package.resolved`。跑了两轮。

**第一轮抓到一个误报。** 78 对里 65 对逐字节一致，13 对不同，全在 interface 侧；dump 侧六框架全部一致。逐行分类：11 对的差异全部是 extension 成员新增的 `@objc` / `@nonobjc`（预期内的副作用），但 `machoimage-current` 的 SwiftUICore 两对多出一个 `@objc @implementation extension __C.DateFormattingContext` 块。查证：这个类的 ivar 名是 `_referenceDate` 这种 clang 合成风格、property attribute 带 `V_referenceDate`、type encoding 完整、本地符号表里没有任何 extension 成员的访问器符号——是 clang 编的类加一个 Swift 扩展的 `init`。它被认出来的证据是本地符号表里的 `$sSo21DateFormattingContextCMa`。回到 `MetadataRequest.cpp`：imported 类的 formal linkage 是 `PublicNonUnique`，走 `NonUniqueAccessor`，任何需要它 metadata 的镜像都会发一个 hidden 的 linkonce accessor，而 dyld cache 保留本地符号。方案里「普通 imported 类不会被定义出 accessor」这句话只在 fixture 里成立（那里没人需要 NSNumber 的 metadata），对系统 cache 不成立。修法：accessor 证据只认导出表里的那个（实现该类的主模块发出的 public unique accessor）。fixture 的 clang 反例补了一句 `String(describing: ClangWidget.self)` 让它也带上这种 hidden accessor，并把 fixture 改为 `-Onone`——`-O` 下优化器把这个 accessor 内联进唯一的调用点，只剩 lazy cache 变量，反例就失去了它要考的那个符号。

**第二轮**：78 对，65 对一致、13 对不同，仍全在 interface 侧且集中在 SwiftUI / SwiftUICore；dump 侧六框架全部一致。逐行分类脚本：13 对共 34 处新增 attribute（`@objc` 29、`@nonobjc` 5），每一行都能与基线的同一行对上，未解释的差异行为零。DateFormattingContext 不再出现。

场景：归档 cache macOS 15.5、模拟器 iOS 15.5 / 18.5 / 18.6 / 26.5、进程内 MachOImage（当前系统 cache，file 与 image 两路）。归档 cache 26.6 这一腿没跑：脚本找的是 `/Volumes/DyldSharedCaches/macOS/26.6`，卷上现在的目录名是 `26.6.2`，脚本静默跳过——目录常量要随卷改名再更新一次（0035 时刚为 26.6 改过）。

## 留下的东西

- `SwiftInspection.ObjCImplementationClassIndex` 与门面 `ObjCImplementationClasses`；`ExtensionDefinition.objcImplementation`；`MemberAttributeApplication`；`SwiftSection.objcImplementationClasses`；`MachOTestingSupport.ObjCImplementationFixture`（含 clang 编译步骤的即时 fixture，后续 ObjC 相关测试可复用）。
- 术语表新增「ObjC implementation class」。

## 遗留

- diff / evolution 渲染器走自己的成员打印，存储属性在那两条路径里仍是 `{ get set }` 形态；头部的 `@objc @implementation` 因共用 `printExtensionHeader` 已带上。
- 一个存储属性类型全部 ObjC 可表示、且导出表被 strip 的 app 二进制识别不到（没有任何证据可用）。
- category 形式的 `@implementation` 块与主块合并显示。
