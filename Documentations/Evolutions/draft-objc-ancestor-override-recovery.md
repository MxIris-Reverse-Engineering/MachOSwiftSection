# Draft - 从 ObjC 祖先链还原 `override`：ObjC 派生 Swift 类与 `@objc @implementation` 类的覆写成员

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-09-20
- **最后更新**: 2026-09-20
- **所属愿景**: 无
- **关联提案**: [draft-objc-implementation-class-recognition](draft-objc-implementation-class-recognition.md)（本提案叠在它之上：复用它的 ObjC 方法表读取与 `To` thunk 联结，并把 `@implementation` 类纳入同一套覆写判定）、[0006-final-keyword-and-lazy-accessor-type-recovery](0006-final-keyword-and-lazy-accessor-type-recovery.md)（`final` 还原用「没有 vtable 项」做证据，本提案的成员都有 ObjC 派发路径，两边判据互不干扰）、[0008-interface-header-and-export-status-annotations](0008-interface-header-and-export-status-annotations.md)（`override` 成员豁免 `// not exported` 标注，新识别出的 override 沿用同一豁免）
- **实现分支 / PR**: `feature/objc-ancestor-override-recovery`（worktree `.worktrees/MachOSwiftSection-ObjCImplementationClasses`，自 `feature/objc-implementation-class-recognition` 分出）
- **配套文档**: [ObjCMemberRecovery.md](../Internal/ObjCMemberRecovery.md)（实现说明；提案 `objc-member-selector-recovery` 落地时自 `ObjCAncestorOverrideRecovery.md` 改名扩写，两份提案共用）、[TaskReports/2026-09-20-objc-ancestor-override-recovery.md](../Internal/TaskReports/2026-09-20-objc-ancestor-override-recovery.md)（过程复盘）

## 摘要

interface 里 `override` 的唯一来源是 Swift vtable 的 override 表（`MethodOverrideDescriptor`）。但覆写一个从 ObjC 继承来的成员时，Swift 元数据里根本没有这条记录：编译器的 `NeedsNewVTableEntryRequest` 对「被覆写者来自 clang」的情况返回「需要一条**新的**普通 vtable 项」，所以普通 Swift 子类的 `override func layout()` 只有一条普通 method descriptor；`@objc @implementation` 类更是连 vtable 都没有。结果是 SwiftUI 里 165 个、AppKit 里 173 个 ObjC 派生的 Swift 类，它们覆写 NSView / NSResponder / NSObject 的成员全部打成裸 `func`，`NSGlassEffectView` 的 `layout()`、`viewDidMoveToWindow()`、`init?(coder:)`、`clipsToBounds` 等 15 个成员没有一个带 `override`，而 Apple 的源码里它们都写着。

证据在 ObjC 侧且足够：类自己的 ObjC 方法表里，每个 `@objc` 成员的 IMP 是它的 `To` thunk（符号名 = 成员符号 + `To`），祖先链 NSView → NSResponder → NSObject 的方法表给出被覆写的 selector 集合。Swift 的语义保证「子类里一个 `@objc` 成员的 selector 与祖先的 selector 相同」当且仅当它是 `override`（否则编译器报 selector 冲突），所以 selector 命中祖先就是确定性判据，不是推测。本提案把这份「类自己的方法表 + 祖先 selector」数据做成一个接缝：宿主已经跑着 ObjCSection 的索引器时直接递进来（RuntimeViewer 对每个镜像都先建 ObjC 索引），没有时 SwiftInspection 自己从 MachOObjCSection 读；再给 `TypeDefinition`（普通 ObjC 派生类）和 `ExtensionDefinition`（`@objc @implementation` 类）的成员补上这个事实，interface 打出 `override`（类方法同时由 `static` 改成 `class`），dump 在类和 `@implementation` 段里把「谁覆写了谁」打出来。

## 方案

### 判据与联结

- **候选类**：`__objc_classlist` 里本镜像定义的 class object——Swift 类（`isSwift` 为 1，`class_ro_t.name` 是 `_TtC…` / `$s…` 运行时名，demangle 回限定名做 key）与 `@objc @implementation` 类（沿用上一提案的识别结果）。
- **自己的成员**：类（与元类）`class_ro_t` 的方法表，含 dyld cache 的 list-of-lists 形态；每个方法记 selector 与 IMP 处的 Swift 符号名。
- **祖先的 selector**：沿 `superClass(in:)` 逐级向上，收每一级实例方法表与元类方法表的 selector；MachOObjCSection 对 cache 内文件与进程内镜像都能跨镜像走到 libobjc 的 `NSObject`，dyld cache 预挂的 category（Foundation 给 `NSObject` 加的 `didChangeValueForKey:`）在 list-of-lists 里一并读到。Swift 祖先也照走：`@objc dynamic` 成员没有 vtable 项，子类覆写它同样只能从这里判。
- **联结**（三档证据，前两档都是确定性的，第三档默认关）：
  1. **`To` 符号在 IMP 处**：成员符号名加 `To`（属性按 getter / setter 各自的 accessor 符号，`init` 用 initializing 入口 `…fc`）等于 IMP 处的 Swift 符号名。只对没 strip 的二进制成立——落地时发现 **OS 框架把 `To` thunk 的符号全部 strip 掉了**（dyld cache 里 `-[NSGlassEffectView layout]` 的 IMP 是一段无名代码，而成员实现 `$sSo17NSGlassEffectViewC6AppKitE6layoutyyF` 的符号还在），这一档在系统缓存上一个都对不上。
  2. **thunk 引用成员实现**：IMP 处没有符号时，用 SwiftThunkAnalysis 的 Capstone 解码器把那段 thunk 反汇编，收它 `bl` / 尾调 `b` 的目标和 `adrp` / `add` 物化出来的地址（类方法的 thunk 把实现地址装进 x16 交给一个 outlined helper），落在本类某个 Swift 成员符号上即联结。两道守卫：那个符号 demangle 出来的所属类型必须就是这个类；成员名必须是 importer 对该 selector 的拼法（`viewWillMove(toWindow:)` ↔ `viewWillMoveToWindow:`，`encode(with:)` ↔ `encodeWithCoder:`，`init(coder:)` ↔ `initWithCoder:`，getter 同名、setter `set` + 首字母大写，`is` 前缀可省）——因为被内联的方法体会调用同类的别的成员，没有这道守卫会把 `self.update()` 认成覆写。
  3. **只按名字**（`ObjCAncestorOverrides.infersOverridesFromSelectorNames`，默认 `false`）：IMP 的代码不引用任何 Swift 符号时（方法体被内联成 `objc_msgSendSuper` 或一个 outlined helper，NSGlassEffectView 的 `clipsToBounds` getter 与 `viewDidHide` 就是），把它归给本类**唯一**一个名字与 selector 一致的成员；两个候选就一个都不标。这一档在 dump 里以 `(selector name, no symbol evidence)` 标出，interface 只打 `override`。
- **不按 Swift 名字反推 selector**：反向映射有损；第 2、3 档用的是正向检查（给定 selector，成员名是不是它的 importer 拼法），失败只会漏标，不会错标。

### 数据来源：一个接缝，两个提供者

覆写判定需要的输入只有一种形状——「一个类自己的 ObjC 方法表（selector + IMP 地址）加上它祖先链上每一级的 selector 集合」。这份数据 MachOObjCSection 那边的索引器早就算过了：库里的 `ObjCIndexing.ObjCInterfaceIndexer` 和 RuntimeViewer 自己的 `RuntimeObjCInterfaceIndexer` 都按类存着 `[ObjCClassInfo]`（`info[0]` 是类自己，后面是跨镜像解析好的整条祖先链，每条 `ObjCMethodInfo` 带 `name` / `isClassMethod` / `imp`）。RuntimeViewer 对每个镜像先建 ObjC section 再建 Swift section（`RuntimeEngine` 里两个 factory 的调用顺序），Swift 侧再读一遍 NSView 的两千多个方法是纯粹的重复劳动。所以数据来源做成接缝，而不是写死自己读：

- **接缝**（SwiftInspection）：`protocol ObjCClassHierarchyProviding: AnyObject, Sendable { func objcClassHierarchy(forClassNamed: String) -> ObjCClassHierarchy? }`，值类型 `ObjCClassHierarchy` 记类名、自己的方法（selector、是否类方法、IMP 地址）、祖先列表（最近的在前，每个带名字与实例 / 类 selector 集合）、祖先链是否走完。查询用 ObjC 运行时名（Swift 类是 `_TtC…` / `$s…`，`@implementation` 类是裸名）。
- **注册**：`ObjCClassHierarchyProviderStore.shared.register(provider, for: machO)` / `unregister(for:)`，按镜像 identifier 弱引用持有——与 `PropertyWrapperTypeCatalogStore` 同一个模式，`TypeDefinition.index(in:)` 在 SwiftDeclaration 里看不到 indexer 的配置，只能走 per-image 注册表。`SwiftDeclarationIndexer` 上加一个便利入口把 provider 注册到自己的镜像。类的索引本来就是惰性的（首次打印 / 浏览时才 `index(in:)`），所以 RuntimeViewer 在建完 ObjC section 后注册即可，不存在「Swift 先索引完、ObjC 后到」的窗口。
- **提供者一：库自己的读取器**（SwiftInspection `ObjCClassMethodIndex`，兜底）：`SharedCache<Storage>` 子类按镜像缓存。`Storage` 急切地建「ObjC 运行时名 / Swift 限定名 → class object」表（只读 classlist 与 `class_ro_t.name`，不读方法表），方法表与祖先 selector 集合按 class object 惰性求值并在 `Storage` 内用锁保护的 memo 保存——NSView 的 selector 在 AppKit 的 173 个子类之间只读一次；祖先在别的镜像时 memo 落在那个镜像自己的 `Storage` 里，AppKit 与 SwiftUI 共用 libobjc 的那份。父类是 bind 而非 rebase 时 MachOObjCSection 返回 nil，链就在这里断，断链前收到的 selector 照用。没有注册 provider、或 provider 对某个类答 nil 时走这条。这张「限定名 → 运行时名」表在两种提供者下都要建：Swift 侧拿到的是 `TypeDefinition` 的限定名，问 ObjC 侧必须用运行时名。上一提案的 `ObjCImplementationClassIndex` 改为从这里取方法表，不再自己读。
- **提供者二：ObjCSection 索引器的适配器**（SwiftIndexing，新增 `ObjCIndexing` 与 `ObjCMetadataSource` 两个 product 依赖）：`ObjCInterfaceIndexerClassHierarchyProvider<MachO>` 包一个 `ObjCInterfaceIndexer<MachO>`，`classGroup(forName:)` 的 `info` 数组直接映射成 `ObjCClassHierarchy`；同文件提供 `ObjCClassHierarchy.init(classInfoChain: [ObjCClassInfo])`，RuntimeViewer 让自己的 `RuntimeObjCInterfaceIndexer` 遵循协议时只需一行转换。IMP 是地址，Swift 侧用 `resolveOffset(at:)` 换成偏移再查 `To` 符号，两个读取器在这一步汇合。
- **等价性固定成测试**：同一个 fixture 分别用两个提供者跑，覆写判定必须逐成员一致。
- **联结的归宿**：第 2 档要用 Capstone 解码器，而 SwiftThunkAnalysis 依赖 SwiftInspection，所以 hierarchy / provider / 读取器索引留在 SwiftInspection，联结表的构建器 `ObjCAncestorOverrides` 落在 SwiftThunkAnalysis（`ObjCOverride/`），SwiftDeclaration、SwiftDump、SwiftIndexing 都已经或从此依赖它。`ObjCMemberShape`（成员的 selector 形状与一致性检查）是纯字符串逻辑，放 SwiftInspection 供两边共用。

### 模型（SwiftDeclaration）

- `FunctionDefinition` / `VariableDefinition` / `SubscriptDefinition` 各加一个存储属性 `objcAncestorOverride: ObjCAncestorOverride?`（selector + 最近祖先名，供 dump 与注释使用）；`isOverride` 改为「descriptor 判定 **或** 这个字段非空」，`isClassMember` 对类型级成员改为「有 vtable descriptor **或** 这个字段非空」——`override static` 不是合法 Swift，覆写的类方法必须打 `class`。
- `TypeDefinition.index(in:)` 在 `applyThunkAttributes` 之后、`recoverFinalMembers` 之前挂一步 `applyObjCAncestorOverrides`（`final` 还原看的是「没有 descriptor」，ObjC 派生类的这些成员都有新 descriptor，不会被误标 `final`；顺序只是为了让后续步骤看到完整的成员事实）。`SwiftDeclarationIndexer.indexExtensions()` 在 `attachObjCImplementation` 后对 `@implementation` 的 extension 走同一步。
- **不进 ABI 快照**：与上一提案一致，`MemberRecord` 不含 override 事实，`formatVersion` 不动，diff / evolution 输出不变。

### 渲染

- **interface**：三个成员 printer 已经按 `isOverride` / `isClassMember` 打关键字，模型改完自动生效。`init?(coder:)` 打成 `override init?(coder:)`——库本来就不还原 `required`，这是既有限制，不在本提案范围。
- **dump**：`ClassDumper` 在类头之后加一行 `// ObjC ancestor chain: NSView → NSResponder → NSObject`（断链时标 `→ NSObject (bound; chain not resolvable offline)`），成员符号行尾追加 `// overrides -[NSView layout] (the IMP's code references the implementation)`——括号里是证据档位；`ObjCImplementationClassDumper` 同样加链注释，ObjC 方法行追加 `overrides NSView`（联结不上的写 `overrides NSView (no Swift member tied to this IMP)`），Swift 成员行同 `ClassDumper`。落地时把方案里的独立 `/* ObjC ancestor overrides */` 段改成了行内注释：事实挂在它所属的那一行上，读者不用两处对照。

### 范围外与降级

- **泛型 ObjC 派生类**（SwiftUI 26 个，`NSHostingView<A>` 等）不在 `__objc_classlist` 里，它们的 `class_ro_t` 藏在泛型 metadata pattern 的 extra-data 块中（`classReadOnlyDataOffsetInWords`），本提案不读，留待后续；它们的成员维持现状。
- **磁盘上的 app 二进制**：父类在别的镜像时是 bind，链在第一跳就断，同镜像内的祖先照常判；又因 app 通常 strip 掉本地符号，`To` 联结也断。本提案不接 dependency closure，`#log(.debug)` 记一条，输出与今天相同。
- **Swift extension 里的 `@objc override` 成员**（编成 `__objc_catlist` 里的 category，ld 未合并进类时）不在类自己的方法表里，本提案不读 category，留待后续。

### 验证

- fixture 扩展：clang 实现的 `ClangWidget` 加一个可覆写的实例方法、类方法与属性；新增普通 Swift 子类（覆写这三样，外加一个不覆写的 `@objc` 成员与一个 `@objc dynamic` 成员再被孙类覆写）与一个 `@objc @implementation` 子类（同样三样覆写）；on-disk 读取只能判同镜像祖先，`NSObject` 的 `description` 覆写在 dylib 文件上不标、`dlopen` 后以 `MachOImage` 读取则标——两种结果都固定成测试。
- AppKit（macOS 26 门控）：`NSGlassEffectView` 的祖先链 NSView → NSResponder → NSObject 走完；`layout` / `initWithCoder:` / `setClipsToBounds:` / `viewWillMoveToWindow:` / `didChangeValueForKey:` / `defaultAnimationForKey:` 全由第二档给出（OS 构建 strip 了 `To` 符号），`clipsToBounds` getter 与 `viewDidHide` 在未联结列表里。interface 上 `init?(coder:)` / `clipsToBounds` / `layout()` 等 9 个成员带 `override`，`defaultAnimation(forKey:)` 打成 `override class func`；剩下 6 个被内联的成员维持裸 `func`，直到第三档打开。
- 渲染 A/B：所有差异行必须是「新增 `override`」或「`static` → `class`」，其余任何差异都是回归。dump 差异同理只允许新段与新注释。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-20 | Created as Draft | 用户看到 `@objc @implementation extension __C.NSGlassEffectView` 里 NSView 的方法都没有 `override`；调研确认这是 `override` 只来自 vtable override 表的既有盲区，普通 ObjC 派生类同样受影响 |
| 2026-09-20 | 范围一并覆盖所有 ObjC 派生的 Swift 类，不只 `@implementation` 类 | 用户决定；判据与代码完全相同，分两次做只会重摸同一段代码 |
| 2026-09-20 | 只按 `To` 符号联结，不按 Swift 名字反推 selector | 名字到 selector 的映射有损（`encode(with:)` ↔ `encodeWithCoder:`），猜错会把非 override 标成 override；strip 后诚实降级 |
| 2026-09-20 | 覆写的类方法打 `class`，不打 `static` | `override static` 不是合法 Swift；这是对「descriptor-less 一律打 `static`」规则的一个有证据的例外 |
| 2026-09-20 | 泛型 ObjC 派生类、`__objc_catlist` category、磁盘二进制的跨镜像祖先三项留待后续 | 三者各需一套新的读取路径（metadata pattern extra-data、category 表、dependency closure），与本提案的主干无关，先把有证据的主路径落地 |
| 2026-09-20 | 事实不进 ABI 快照 | 与 `@implementation` 识别的决定一致：这是渲染事实，不是 ABI 变化 |
| 2026-09-20 | 数据来源做成接缝：库自己的读取器只是兜底提供者，另给 ObjCSection 的 `ObjCInterfaceIndexer` 一个适配器，注册表按镜像弱引用 | 用户指出 RuntimeViewer 等宿主本来就跑着 ObjCSection 的索引器，那边已经按类存好了整条祖先链的方法表，Swift 侧再读一遍是重复劳动；接缝让宿主把现成的索引递进来 |
| 2026-09-20 | Draft → Accepted → In Progress | 用户确认方案（含 ObjC 侧索引器接缝）后开始实现 |
| 2026-09-20 | 联结加第 2 档（反汇编 thunk 找它引用的成员实现），第 3 档（只按名字）实现但默认关 | 落地时 IDA 核实 OS 框架 strip 掉了全部 `To` 符号，只靠符号在系统缓存上一个覆写都标不出来；thunk 的 `bl` / 地址物化是硬事实，配所属类与 importer 拼法两道守卫后不会错标。第 3 档是否默认开待用户裁定 |
| 2026-09-20 | dump 的祖先链注释放类头下独占一行，Swift 祖先按限定名显示 | 第一轮 A/B 抓到注释放在成员段末尾且与 `}` 粘连；`class_ro_t.name` 对 Swift 类是 mangled 运行时名，注释里照抄读不懂 |
| 2026-09-20 | In Progress → Implemented | 实现连同文档合入 `next`；配套文档（实现说明、任务报告）已登记在头部，术语已入术语表；编号按仓库惯例在发布合入 `main` 时分配 |
| 2026-09-21 | 旧 `LC_DYLD_INFO` bind 格式的父类槽位不再当根类（随提案 `objc-member-selector-recovery` 落地） | 那种文件（iOS 15.5 模拟器运行时）的 bind 槽位是 0，链曾被打成走完、注释不带 `(bound; chain not resolvable offline)`；读取器补 MachOKitExtensions 的 `resolveBind(fileOffset:)` 取 bind 名并以 `isSwift` 兜底，链注释从此诚实 |
