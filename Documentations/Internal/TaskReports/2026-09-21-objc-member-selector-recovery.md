# 2026-09-21 从 ObjC 方法表还原每个 `@objc` 成员：一个反方向的提议如何变成对既有盲区的修补

## 起点

上一批（从 ObjC 祖先链还原 `override`）合入 `next` 之后，用户接着问：Swift 这边知道 ObjC 的方法名吗，两个名字不一样时编译器怎么处理？答完（编译器同时存着两个名字，selector 从被覆写者继承，调用走 `objc_msgSend` 靠地址不靠名字，strip 只删符号不删代码）之后，用户提出：那 `SymbolIndexStore` 能不能顺手收集 ObjC 符号，到时候拿 `bl` 的地址去匹配 ObjC 方法？

核实下来方向反了：`bl` 的目标是 Swift 实现，ObjC 方法在链的起点（方法表 → IMP = thunk → `bl` → 实现），拿终点去匹配起点永远匹不上；而且系统 cache 里 ObjC 方法符号（`-[Class sel]`）和 `To` thunk 符号一样被 strip 掉了，IDA 里看到的标签是它自己从方法表合成的。成立的变体是：从方法表建一张「IMP → (类, selector)」表——而这正好补上一个比 selector 本身更要紧的既有盲区。

## 调研发现

**成员级 `@objc` 在 OS 框架上整体丢失。** interface 里成员的 `@objc` 唯一来源是 `To` thunk 符号 demangle 出来的 `.objCAttribute` 节点。OS 框架 strip 掉了 `To` 符号，于是 macOS 26.6 系统 cache 生成的 AppKit interface 一万行里成员级 `@objc` 是零——38 处 `@objc` 全是 `@objc @implementation extension` 的头。连带三处判定失灵：`final` 还原把「`@objc` 且没有 vtable descriptor」当 `@objc dynamic` 排除，看不见 `@objc` 就把这些 objc_msgSend 派发、随时可被覆写的成员打成 `final`；`--emit-export-status` 对 `@objc` 成员的豁免落空；dump 的同一豁免查 `To` 符号存在性，同样落空。

**方法表就是 `@objc` 成员清单。** 上一批已经会把方法表条目联结到 Swift 成员（`To` 符号在 IMP 处 / 反汇编无名 thunk 找它 `bl` 到的实现），只是只对「selector 被祖先实现」的条目做。推广到每一条就得到 per-class 的 ObjC 成员表，覆写表变成它的投影。

**编译器的 selector 推导是确定且无损的。** `lib/AST/Decl.cpp` 的 `AbstractFunctionDecl::getObjCSelector`：第一段 = 基名 +（`With`，除非第一个标签的首词或基名的末词是介词）+ 首字母大写的标签；`throws` 追加 `error:`（无参时 `AndReturnError:`）；`async` 追加 `completionHandler:`；setter 是 `set` + 大写属性名，**没有** `is` 处理。介词表在 `lib/Basic/PartsOfSpeech.def`，30 个词（提案初稿写 34，实数 30）。拿它正向推出默认 selector，与方法表里的实际 selector 比，不同就是源码写了 `@objc(name)`——与上一批有损的「importer 拼法一致性」是两套规则，一套判事实，一套做守卫。

**`@implementation` 体不是例外——被编译器纠正了一次。** 第一版在 AppKit 上报出 8 个显式 selector，7 个落在 `@implementation` 类（`NSGradient` 的 `drawInRect:angle:` 对 `draw(in:angle:)`），我以为那里 selector 来自头文件、Swift 名是 importer 给的、不该算显式，加了整表清标记的逻辑，并往 fixture 里加 `- (void)drawInRect:(NSRect)rect;` / `func draw(in rect: NSRect) {}` 想固定它。编译器报 `selector 'drawIn:' for instance method 'draw(in:)' not found in header; did you mean 'drawInRect:'?`——`@implementation` 体里 selector 同样从 Swift 名推导、必须在头文件里有，要用 importer 的名字就得写 `@objc(drawInRect:)`。那 7 处本就是 Apple 源码里写着的。撤回清标记，fixture 改成 `@objc(drawInRect:) func draw(in:)` 固定相反的事实。

**A/B 抓到第二个错判：断链处的显式 selector。** 第一轮渲染 A/B 的模拟器运行时腿（SwiftUI 作为独立 Mach-O 文件读，父类 UIView 是 bind、链在第一跳断）判出 35 个显式 selector，抽样几乎全是 `hitTest:withEvent:` / `drawRect:` / `touchesBegan:withEvent:` / `observeValueForKeyPath:…` 这类 UIKit 覆写：链断了不知道它是覆写，selector 又对不上推导，就打成了 `@objc(hitTest:withEvent:) func hitTest(_:with:)`——合法，但读者会以为是自定义命名，而这是 app 二进制这种最常见的逆向对象上的默认输出。改成 fail closed：祖先链没走完或某个协议读不到，就不下显式 selector 的判定；dump 注释照样写 selector。fixture 的文件腿因此不判（NSObject 是 bind），显式 selector 的断言全部搬到 `dlopen` 后的进程内腿。

第二轮 A/B 同一腿**仍然**判出 33 个——链注释显示 `_UIInheritedView` 的链在 `SwiftUI._UIGraphicsView` 处「走完」而不是断掉。`otool -l` 证实 iOS 15.5 模拟器的 SwiftUI 用旧的 `LC_DYLD_INFO` bind 格式：bind 槽位在文件里是 0，MachOObjCSection 的 `superClassName(in:)` 先 `guard value > 0` 再谈 bind，于是读成「没有父类」= 根类。读取器补了一道 MachOKitExtensions 的 `resolveBind(fileOffset:)`（两种 bind 格式都认，`LegacyDyldInfoBindTests` 就靠它）取 bind 符号名，再兜一道「Swift 类不可能是 ObjC 根类」；fixture 加 `.legacyBinds` 变体（`-target arm64-apple-macosx11.0`，与 `LegacyDyldInfoBindTests` 同法）固定「链断在 NSObject、不判显式 selector、同镜像覆写照常」。这也顺手修正了上一批在这类文件上的链注释：之前打成走完，现在诚实标 `(bound; chain not resolvable offline)`。

第三轮 A/B 的 macOS 15.5 归档 cache 腿还剩一处：WidgetKit 的 `WidgetRelevanceFetchResult.encode(with:)` 被判显式 selector。用一个一次性探针测试打印它的 hierarchy：链走完（NSObject），协议集合 `isComplete == true`，但实例 selector 集合是 `[""]`——类采纳的 Foundation `NSSecureCoding` 在归档 cache 里跨镜像读方法表，名字串读成空串，`encodeWithCoder:` 因此不在集合里、witness 判定失效。跨镜像协议方法名的读取问题在 MachOObjCSection 那边（macOS 26.6 的当前 cache 上同样的读取是好的，`NSGradient` 的 `encodeWithCoder:` 正确判为 witness），这里的对策是把空 selector 一律当读失败、集合标不完整，不据此下判。探针测试用完即删。

第四轮 A/B 的进程内腿还剩一处：`SwiftUI.SwiftUIOutlineTableView.draggingSession(_:movedTo:)` 对 `draggingSession:movedToPoint:`。它是 `NSDraggingSource` 协议的可选要求，而 conformance 声明在祖先 `NSTableView` 上——子类实现它时编译器照样给要求的 selector（`inferObjCName` 查的是类的全部 conformance，继承的也在内），我的 witness 判定只看了类自己和它 category 的协议表。`Ancestor` 加上各自采纳协议的 selector 集合，`adoptedProtocolDeclares` 与完整性判定连整条链一起算；fixture 给 `WidgetObserving` 加一个自定义 selector 的可选要求、只由孙类实现，固定「继承的 conformance 不算显式」。

## 最终方案

用户定的：做（「可以，加一下」「开工吧」）。我定的、用户未反对的五条：显式 selector 用编译器正向推导判；覆写与协议 witness 不打括号（落地时改为：祖先链或协议没读完就不判）；dump 行内注释 `// @objc -[Class selector][, explicit selector] (证据)`；类型按新范围改名（`ObjCAncestorOverride*` → `ObjCMember*`，只在 `next` 上、未发布）；纳入 `__objc_catlist` 的 category（顺带解决上一批留下的「extension 里的 `@objc override`」）。归宿不进 `MachOSymbols`——那一层不依赖 MachOObjCSection——留在 SwiftInspection / SwiftThunkAnalysis。

## 执行

SwiftInspection（`ObjCMember` / `ObjCMemberTable`；`ObjCMemberShape` 加 subscript 形状、`throws` / `async`、`defaultSelector` 与介词表、驼峰分词，`To` 符号的 attribute 子节点跳过；`ObjCClassHierarchy.adoptedProtocolSelectors`；`ObjCClassMethodIndex` 扫 category、读协议 selector、给外部类的 category 另立 hierarchy；读取器协议加 category / 协议读取）→ SwiftThunkAnalysis（`ObjCMembers` 全表联结，第一档对 identical code folding 叠在一个 IMP 的多个符号只取形状一致的）→ SwiftDeclaration（`objcMember` 字段；`ObjCMemberApplication` 补 `.objc`、属性 getter 优先、只经 setter 联结的清显式标记；`TypeDefinition.index` 的调用顺序注释改写：它现在**必须**先于 `final` 还原）→ SwiftIndexing（Swift 类的 extension 也过表；适配器归组 category、递归收协议 selector）→ SwiftPrinting（`@objc(selector)`）→ SwiftDump（`ObjCMemberRendering`、export-status 豁免查表、`@implementation` 的 ObjC 方法行对非覆写也标 `no Swift member tied to this IMP`）→ fixture 与测试 → 文档。

三处顺手修正的测试预期：`init`（编译器合成）与 `.cxx_destruct`（指向 ivar destroyer）也是方法表条目；显式 selector 过不了第二档的 importer 拼法守卫，strip 后诚实缺席；`ExportStatusDumpAnnotationTests` 的行匹配从 `hasSuffix` 改 `contains`（成员行尾多了注释）。三份快照（`attributesSnapshot` / `classesSnapshot` / `interfaceSnapshot`）重录，diff 只有新增的 `// @objc -[…]` 注释。第一版重录时曾多出一处 `@objc(isKindOfClass:)`——`ExternalObjCSubclassTest.isKind(of:)` 覆写 NSObject 的方法，文件上 NSObject 是 bind、链断、不被认作覆写——正是断链错判的最小样本，fail closed 之后消失。

## 验证

- 定向套件：`ObjCMemberRecoveryTests`（16 例）、`AppKitObjCMemberTests`（2 例，macOS 26 门控）、`ObjCMemberDumpTests`（5 例）+ 受影响的既有套件（`@implementation` 识别与 dump、export-status、三份 fixture 快照），107 / 107；`LegacyDyldInfoBindTests` 一并跑过。
- macOS 26.6 系统 cache 的 AppKit interface（与 `next` 头的输出逐行分类）：成员级 `@objc` 0 → 97，其中 `@objc(sel)` 8 处（7 处在 `@implementation` 类，是编译器逼着源码写的；1 处在 `extension NSView` 的 category），`final` 误标去掉 1 处，未解释差异 **0**。`NSGlassEffectView` 的 `init?(coder:)` 现在打成 `@objc override init?(coder:)`。
- 全量 `swift test --skip IntegrationTests`（最终代码）：1991 例 / 380 套件，4 个 issue——3 个是 `SharedCacheTests` 的墙钟并行度断言（A/B 在并行跑；单独重跑 9 / 9），1 个是 `GenericSpecializationTests.argumentCandidatePathSpecializesNonGenericCandidate`——**在 `next` 头 74c4eb24 的干净 checkout 上单独跑同样失败**（两条特化路径拿到不同的 metadata 指针），与本次改动无关，未深究，留给用户。
- 渲染 A/B（基线 = `next` 头 74c4eb24，detached worktree `.worktrees/MachOSwiftSection-ABBaseline`；归档 macOS 15.5 cache、模拟器运行时 iOS 15.5 / 18.5 / 18.6 / 26.5、进程内 MachOImage，iOS 27.0 运行时无 SwiftUI 被跳过）：78 对里 42 对有差。逐行分类（脚本在 `/tmp`，不入库）：dump 成员行新增 `// @objc -[…]` / `// overrides -[…]` 注释 1768 行，interface 新增 `@objc` 115 行，新增 `override` 19 行（extension 里的覆写，来自 category），去掉 `final` 24 行（`@objc dynamic` 等无 descriptor 的 `@objc` 成员），链注释改写 13 行（旧 bind 格式的文件上链从「走完」改为「断在 bind」）、新增 14 行（有了 category 方法的类）及 1 个空行分隔，`@objc(sel)` **0** 处，未解释差异 **0**。前四轮分别抓到：注释放错位置之外的三个判定错误——`@implementation` 豁免（撤回）、断链处的显式 selector（fail closed）、旧 bind 格式的父类被当根类（补 bind 名解析）——以及跨镜像协议方法名读空、祖先的 conformance 未计入两处 witness 漏判；每一处都在最终一轮消失。

## 与方案的偏离

- 祖先链没走完或协议读不到时，显式 selector 从「不排除、照事实打」改为「不下判定」（见调研发现的 A/B 一节）。
- `@implementation` 体一度想豁免显式 selector 判定，被编译器纠正（见调研发现），最终与提案一致：不豁免。
- strip 后的显式 selector 不还原（提案没写死这一点，落地时明确为边界并固定成测试）。
- 介词 30 个不是 34 个。

## 留给后续

- 第三档「只按名字」是否默认开（上一批遗留，未变）。
- 泛型 ObjC 派生类、磁盘二进制的跨镜像祖先（上一批遗留，未变）。
- `GenericSpecializationTests.argumentCandidatePathSpecializesNonGenericCandidate` 在 `next` 上的失败。
- A/B 脚本找归档 cache 目录 `26.6` 与卷上 `26.6.2` 不一致，那一腿被静默跳过（上一批遗留）。
