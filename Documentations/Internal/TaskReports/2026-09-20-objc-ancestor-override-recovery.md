# 2026-09-20 从 ObjC 祖先链还原 `override`：一个「只联结不猜」的方案在 OS 框架上撞到 strip 之后

## 起点

上一批（`@objc @implementation` 识别）刚落地，用户贴出 `@objc @implementation extension __C.NSGlassEffectView` 的输出说：这里不会显示 `override`，有很多方法都是 NSView 的。

核实下来这不是识别漏了什么，而是库里 `override` 的唯一来源是 Swift vtable 的 override 表（`MethodOverrideDescriptor`），而覆写一个从 ObjC 继承来的成员时 Swift 元数据里根本没有这条记录：编译器的 `NeedsNewVTableEntryRequest` 对「被覆写者来自 clang（`hasClangNode`）」返回 true——需要一条**新的**普通 vtable 项。所以普通 Swift 子类也一样：SwiftUI 里 `CustomMarkedSliderCell: NSSliderCell` 的 `layout()` 同样是裸 `func`。`@implementation` 类更是连 vtable 都没有。SwiftUI 165 个、AppKit 173 个 ObjC 派生类全部受影响。

一轮澄清提问，用户定了范围：一并做所有 ObjC 派生的 Swift 类，另立轻量提案。提案落盘后用户补了一条要求：ObjCSection 那边经常也在做索引，加一个接收它索引内容的入口。补进提案后用户说 ok。

## 调研发现

**证据在 ObjC 侧且充分**：类自己的方法表里每个 `@objc` 成员的 IMP 是它的 `To` thunk；祖先链 NSView → NSResponder → NSObject 的方法表给出被覆写的 selector 集合；MachOObjCSection 的 `superClass(in:)` 对 cache 内文件和进程内镜像都能跨镜像走到 libobjc 的 NSObject，dyld cache 预挂的 category（Foundation 给 NSObject 的 `didChangeValueForKey:`）在 list-of-lists 里能读到。Swift 语义保证子类里一个 `@objc` 成员的 selector 与祖先相同当且仅当它是 `override`，所以判据是确定性的。

**ObjC 侧已经有现成的索引**：`ObjCIndexing.ObjCInterfaceIndexer` 和 RuntimeViewer 自己的 `RuntimeObjCInterfaceIndexer` 都按类存着 `[ObjCClassInfo]`——第 0 个是类自己，后面是跨镜像解析好的整条祖先链，每条方法带 selector、是否类方法、IMP 地址。RuntimeViewer 对每个镜像先建 ObjC section 再建 Swift section，Swift 侧再读一遍 NSView 的两千多个方法是重复劳动。于是数据来源做成接缝。

**落地时撞到的事实——OS 框架 strip 掉了 `To` thunk 的符号**。方案里写的联结是「成员符号名加 `To` 等于 IMP 处的符号名」，fixture 上全对，AppKit 门控测试上一个都对不上：`selectors → []`。回到 IDA（26.5.2 的 AppKit.i64）看 `-[NSGlassEffectView layout]` 的 IMP：一段没有符号的代码，`objc_retain; mov x20, x0; bl _$sSo17NSGlassEffectViewC6AppKitE6layoutyyF; …`。成员实现的符号还在，thunk 的符号没了。再看几个：`initWithCoder:` 是 `bl …fc`；`+defaultAnimationForKey:` 把 `$s…FZ` 的地址 `adrl` 进 x16、`pacia` 后交给一个 outlined helper 尾调；`setClipsToBounds:` 是 `bl …vs`；而 `clipsToBounds` getter 被内联成 `objc_msgSendSuper2`，`viewDidHide` 是 `adrl x2, selRef; b outlined`——thunk 里不剩任何 Swift 符号引用。

这条发现把联结改成了三档：`To` 符号在 IMP 处；反汇编 thunk 收它引用的成员实现（`bl` / 尾调 / 地址物化），配「所属类」与「importer 拼法」两道守卫；只按名字（默认关）。守卫的必要性：被内联的方法体会调用同类的别的成员，没有守卫会把 `self.update()` 认成覆写。「importer 拼法」是正向检查——给定 selector，成员名是不是它按 importer 规则会得到的样子——而不是把 Swift 名反推成 selector（那是有损的，`encode(with:)` 对 `encodeWithCoder:`）。

**一个归宿问题**：第二档要用 SwiftThunkAnalysis 的 Capstone 解码器，而 SwiftThunkAnalysis 依赖 SwiftInspection。hierarchy、接缝、库读取器、形状与一致性检查留在 SwiftInspection，联结表的构建器 `ObjCAncestorOverrides` 落到 SwiftThunkAnalysis，SwiftIndexing 因此新增了对它的依赖。

**两个小坑**：`@implementation` 里覆写导入成员必须 `public`（fixture 第一版没写，编译器报 "overriding instance method must be as accessible as the declaration it overrides"）；`OSAllocatedUnfairLock` 要 macOS 13，包的下限是 10.15，换 `NSLock`。

## 最终方案

用户定的：范围覆盖所有 ObjC 派生的 Swift 类；接收 ObjCSection 索引器的内容。我定的：判据放 ObjC 侧；provider 接缝按镜像弱引用注册，与 `PropertyWrapperTypeCatalogStore` 同一个模式（`TypeDefinition.index(in:)` 看不到 indexer 配置）；联结三档，第三档默认关（用户既定裁决「只联结不猜」，改默认要用户裁定）；覆写的类方法打 `class`；`init?(coder:)` 打 `override init?(coder:)`，`required` 不还原；泛型类、category、磁盘二进制的跨镜像祖先三项留待后续；事实不进 ABI 快照；dump 用行内注释而不是独立段，证据档位写在括号里。

## 执行

七个层次：SwiftInspection（hierarchy / 接缝 / 读取器索引 / 覆写事实与表 / 成员形状；`NodeTypeNaming` 下沉）→ SwiftThunkAnalysis（构建器 + thunk 引用解码）→ SwiftDeclaration（模型字段、`isOverride` / `isClassMember`、应用）→ SwiftIndexing（extension 接入、provider 注册、适配器、驱逐）→ SwiftDump（链注释、`overrides` 注释）→ fixture 与测试 → 文档。中途第一版（只有第一档）在 fixture 上全绿、在 AppKit 上全空，改成三档后 AppKit 门控测试通过。

## 验证

- 定向套件：`ObjCAncestorOverrideRecoveryTests`（10 例）、`AppKitObjCAncestorOverrideTests`（1 例，macOS 26 门控）、`ObjCAncestorOverrideDumpTests`（2 例）+ 受影响的既有套件，33 / 33。
- macOS 26.6 系统 cache 的 AppKit interface：`override` 行 2 → 52；`NSGlassEffectView` 15 个覆写成员标出 9 个（`init?(coder:)`、`clipsToBounds`、`tintColor`、`viewWillMove(toWindow:)`、`didChangeValue(forKey:)`、`viewDidMoveToWindow()`、`viewDidChangeEffectiveAppearance()`、`layout()`、`defaultAnimation(forKey:)` 打成 `override class func`），全部是第二档；剩下 6 个（`renewGState` / `viewDidHide` / `viewDidUnhide` / `_windowChangedKeyState` / `_viewDidChangeEffectiveCornerRadii` / `encode(with:)`）方法体被内联，只有第三档能标。与改动前输出的 diff 里，已有块内的每一行差异都是新增 `override` 或 `static` → `class`。
- 全量 `swift test --skip IntegrationTests`：1979 例 / 380 套件，3 个 issue 全是 `SharedCacheTests` 的三个墙钟并行度断言（跑的时候 A/B 基线在并行编译，16 s 对 0.8 s 预算），单独重跑 9 / 9 通过；无回归。
- 渲染 A/B（基线 = 上一提案分支头 af05e7b8，detached worktree `.worktrees/MachOSwiftSection-ABBaseline`；归档 cache 15.5、当前系统 cache、模拟器运行时 iOS 15.5 / 18.5 / 18.6 / 26.5、进程内 MachOImage 三条腿）：78 对里 39 对有差。逐行分类（脚本在 `/tmp`，不入库）：1358 行是新增的 `override` 关键字或 `// overrides …` 注释，9 行是 `static` → `class`，812 行是 `// ObjC ancestor chain: …` 注释及其后的空行分隔，未解释的差异行为**零**；dump 与 interface 两侧都在内，interface 侧只有前两类。第一轮 A/B 抓到一个自己引入的渲染缺陷：祖先链注释放在了成员段末尾且与 `}` 粘连（空类打成 `// … NSObject}`），改到类头下独占一行后第二轮才是上面的数字。iOS 27.0 模拟器运行时没有 SwiftUI / SwiftUICore，被脚本跳过。 第二轮之后又把注释里 Swift 祖先的 mangled 运行时名改成限定名显示，只动注释文本：用最终 release 二进制重渲染 iOS 26.5 模拟器的 WidgetKit（2 行变化）与 SwiftUI（88 行变化）dump，对照第二轮候选输出，变化的每一行都是祖先链或 `overrides` 注释。

## 与方案的偏离

- 联结从一档变三档（见调研发现）；提案决策日志已补。
- dump 的独立 `/* ObjC ancestor overrides */` 段改成行内注释。
- `ObjCAncestorOverrides` 从 SwiftInspection 移到 SwiftThunkAnalysis。

## 待用户裁定

第三档（只按名字）是否默认打开。NSGlassEffectView 剩下的 6 个、以及所有被优化器内联掉方法体的覆写，只有它能标；零参 selector 与 Swift 方法名的相等是编译器自己的规则（不写 `@objc(x)` 就一定相等），多参的一致性检查加上「唯一候选」也很强，但它终究不是符号级证据。
