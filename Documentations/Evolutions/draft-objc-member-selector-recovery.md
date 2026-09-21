# Draft - 从 ObjC 方法表还原每个 `@objc` 成员：strip 后的 `@objc`、显式 selector 与 category 成员

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-09-21
- **最后更新**: 2026-09-21
- **所属愿景**: 无
- **关联提案**: [draft-objc-ancestor-override-recovery](draft-objc-ancestor-override-recovery.md)（本提案把它的「方法表 → Swift 成员」联结从「只看被覆写的 selector」推广到类的每一条 ObjC 方法，覆写表成为成员表的一个投影）、[0006-final-keyword-and-lazy-accessor-type-recovery](0006-final-keyword-and-lazy-accessor-type-recovery.md)（`final` 还原用 `@objc` 排除 `@objc dynamic` 成员，本提案让这道排除在 strip 后的二进制上重新生效）、[0008-interface-header-and-export-status-annotations](0008-interface-header-and-export-status-annotations.md)（`@objc` 成员豁免 `// not exported`，同理）
- **实现分支 / PR**: `feature/objc-member-selector-recovery`（worktree `.worktrees/MachOSwiftSection-ObjCImplementationClasses`，自 `next` 分出）
- **配套文档**: [ObjCMemberRecovery.md](../Internal/ObjCMemberRecovery.md)（实现说明，自 `ObjCAncestorOverrideRecovery.md` 改名扩写，两份 @objc 提案共用）、[TaskReports/2026-09-21-objc-member-selector-recovery.md](../Internal/TaskReports/2026-09-21-objc-member-selector-recovery.md)（过程复盘）

## 摘要

interface 里成员级 `@objc` 的唯一来源是 `To` thunk 符号 demangle 出来的 `.objCAttribute` 节点（`SymbolIndexStore.thunkAttributeMembers` → `MemberAttributeApplication`）。OS 框架把 `To` 符号全部 strip 掉了（上一提案落地时在 IDA 里核实），于是从 macOS 26.6 系统 cache 生成的 AppKit interface 一万行里**成员级 `@objc` 一个都没有**——仅有的 38 处 `@objc` 全是 `@objc @implementation extension` 的头。连带三处判定跟着失灵：`final` 还原把「`@objc` 且没有 vtable descriptor」当作 `@objc dynamic` 予以排除，strip 后看不见 `@objc`，这些 objc_msgSend 派发、随时可被覆写的成员被打成 `final`；`--emit-export-status` 对 `@objc` 成员的豁免落空；dump 的同一豁免直接查 `To` 符号存在性，同样落空。

而类的 ObjC 方法表就是它的 `@objc` 成员清单——每条一个 selector 加一个 IMP——运行时靠它派发，strip 不会碰。上一提案已经会把方法表条目联结到 Swift 成员（IMP 处的 `To` 符号，或反汇编无名 thunk 找它 `bl` 到的成员实现），只是只对「selector 在祖先链上有人实现」的条目做。本提案把联结推广到类自己的**每一条**方法（实例方法表、元类方法表、本镜像 `__objc_catlist` 里指向它的 category），得到一张 per-class 的 **ObjC 成员表**：成员符号名 → selector、是否类方法、证据档位、被覆写的祖先（可空）。覆写表成为它的投影。表喂给四个消费者：`@objc` 属性（strip 后也有）、selector 与编译器默认推导不一致时 interface 打 `@objc(selector)`、dump 每条联结上的成员打 `// @objc -[Class selector] (证据)`、`final` 与 export-status 的既有 `@objc` 排除自动恢复。

## 方案

### 判据与联结

- **候选类与方法**：沿用 `ObjCClassMethodIndex` 的 class object 表；一个类的「自己的方法」= 实例方法表 + 元类方法表 + 本镜像 `__objc_catlist` 里目标是它的 category 的实例 / 类方法表（Swift `extension Foo { @objc func bar() }` 编成 category；category 的目标类不在本镜像时——SwiftUI 给 `NSView` 加的 `@objc` 成员——按目标类名另立一张表，供 `__C.NSView` 的 `ExtensionDefinition` 查）。同一 IMP 出现两次（dyld cache 预挂 category 后 list-of-lists 与 `__objc_catlist` 重叠）按 IMP 偏移去重。
- **联结**：与上一提案完全相同的两档确定性证据（IMP 处的 `To` 符号；反汇编 thunk 收 `bl` / 尾调 / 地址物化的目标，守卫「所属类就是这个类」与「成员名是 importer 对该 selector 的拼法」），第三档只按名字仍默认关，开关不动。差别只在**不再先用祖先 selector 过滤**：每条方法都联结，联结上的成员记 `overriddenAncestorClassName`（祖先链上有人实现该 selector 时）或 nil。
- **subscript 补进形状检查**：`ObjCMemberShape` 目前对 subscript 的 getter / setter 返回 nil；补 `.subscriptGetter` / `.subscriptSetter`，一致性检查接受 `objectAtIndexedSubscript:` / `objectForKeyedSubscript:` / `setObject:atIndexedSubscript:` / `setObject:forKeyedSubscript:` 四个固定 selector。

### 默认 selector 的推导（编译器规则的移植）

「显式 selector」的判据是：方法表里的实际 selector ≠ 编译器从 Swift 名**正向**推出来的默认值。这条推导是确定性的、无损的（`lib/AST/Decl.cpp` `AbstractFunctionDecl::getObjCSelector` / `VarDecl::getDefaultObjCSetterSelector`），与上一提案里有损的「importer 拼法一致性」是两回事，放 `ObjCMemberShape.defaultSelector` 里，规则逐条移植：

- 无参方法：selector = 基名。单个无标签参数：`基名:`。
- 有标签的多参方法：第一段 = 基名 +（`With`，除非第一个标签的首词是介词、或基名的末词是介词）+ 首字母大写的第一个标签；后续每段 = 标签原文，无标签为空段。`viewWillMove(toWindow:)` → `viewWillMoveToWindow:`；`perform(after:)` → `performAfter:`；`replace(_:with:)` → `replace:with:`。
- `throws` 追加 `error:` 段（无参时变 `基名AndReturnError:`）；`async` 追加 `completionHandler:` 段（无参时变 `基名WithCompletionHandler:`）；`async throws` 只追加 `completionHandler:`。
- 初始化器：基名 `init`，同一条第一段规则：`init(coder:)` → `initWithCoder:`，`init(from:)` → `initFrom:`，`init(_:)` → `init:`，`init()` → `init`。
- 属性：getter = 属性名；setter = `set` + 首字母大写的属性名。**没有 `is` 前缀处理**——`var isEnabled` 的 Swift 默认 setter 是 `setIsEnabled:`；`is` 可省是 importer 从 ObjC 往 Swift 的规则，上一提案的一致性检查里保留，这里不适用。
- 介词表：`lib/Basic/PartsOfSpeech.def` 的 30 个词（above / after / along / … / with / within），作为固定常量移植，测试固定其内容。
- 驼峰分词按编译器 `camel_case::Words` 的规则（大写字母起新词，连续大写视为缩写词）。

判定 `hasExplicitSelector` 时两类成员**不算**：被还原为覆写的成员（selector 从被覆写者继承，编译器禁止写不同的名字，`@objc(…)` 至多是冗余）；`@objc` 协议要求的 witness（selector 从要求继承）——后者要读类采纳的协议：库读取器从 `class_ro_t.baseProtocols` 与 category 的协议表收协议（含协议继承链）的要求 selector，宿主适配器从 `ObjCClassInfo.protocols` 收；祖先链没走完（磁盘上独立二进制的父类是 bind）或某个协议读不到时，selector 可能就是从没读到的那一级继承的，**不下判定**：不打 `@objc(sel)`，dump 注释里照样写出 selector，只是不加 `explicit selector`。落地时 A/B 抓到的反例：模拟器运行时的 SwiftUI 文件上，`hitTest:withEvent:` / `drawRect:` / `touchesBegan:withEvent:` 这些 UIKit 覆写全被判成显式 selector（UIView 是 bind，链在第一跳断）——合法但误导，与「只联结不猜」相悖。

### 数据来源

接缝不变：`ObjCClassHierarchyProviding` / `ObjCClassHierarchyProviderStore` 原样，`ObjCClassHierarchy.methods` 本来就是「类自己的全部方法」，只是过去只被覆写判定消费。两处补充：

- `ObjCClassHierarchy` 加 `adoptedProtocolSelectors: Set<String>?`（nil = 提供者读不到），实例 / 类各一份。
- 库读取器 `ObjCClassMethodIndex` 建表时多扫一遍 `__objc_catlist`，按目标类名归组；`ObjCImplementationClassReading` 加 category 与协议表的读取要求。宿主适配器 `ObjCInterfaceIndexerClassHierarchyProvider` 把 indexer 里同名的 category group 并进 `methods`（`ObjCInterfaceIndexer` 目前按名字另存 category，不折进 class info）。
- 等价性测试延伸：同一 fixture 两个提供者跑出的成员表逐条一致。

### 模型（SwiftDeclaration）

- 类型改名反映新范围（这些类型只在 `next` 上、未随任何版本发布）：`ObjCAncestorOverride` → `ObjCMember`（`selector` / `isClassMethod` / `evidence` / `overriddenAncestorClassName: String?` / `hasExplicitSelector: Bool`），`ObjCAncestorOverrideTable` → `ObjCMemberTable`，构建器 `ObjCAncestorOverrides` → `ObjCMembers`（`infersOverridesFromSelectorNames` 开关随之搬家），`ObjCAncestorOverrideApplication` → `ObjCMemberApplication`，定义上的 `objcAncestorOverride` → `objcMember`。RuntimeViewer 若已引用旧名，留 deprecated typealias 一个版本。
- `isOverride` / `isClassMember` 改读 `objcMember?.overriddenAncestorClassName != nil`，语义不变。
- `ObjCMemberApplication.apply` 在设置 `objcMember` 的同时给缺 `.objc` 的成员补上 `.objc` 属性（functions / variables / subscripts 及其 static 形态、allocators），放在 `applyThunkAttributes` 之后、`recoverFinalMembers` 之前——顺序就是让 `final` 还原看到 `@objc`。
- `SwiftDeclarationIndexer.indexExtensions()`：`@implementation` extension 的路径已有；加上本镜像 Swift 类的 extension（category 成员）与 `__C.X` 的普通 extension（对外部类的 category），都用同一张表按符号名应用。
- **不进 ABI 快照**，`MemberRecord` 不含这些事实，`formatVersion` 不动。

### 渲染

- **interface**：`.objc` 属性打印处（`SwiftDeclarationPrinter` 三个成员 printer 的属性循环）遇到 `.objc` 且 `objcMember?.hasExplicitSelector == true` 时打 `@objc(selector)`，属性用 getter 的 selector（`@objc(name)` 给属性改名时 setter 随之变成 `setName:`，只打一处）；其余情形维持 `@objc`。`final` 还原、export-status 豁免不改代码，靠 `.objc` 重新出现自动恢复。
- **dump**：`ClassDumper` 成员行尾对联结上的非覆写成员追加 `// @objc -[Class selector] (证据)`，覆写成员维持既有 `// overrides -[Ancestor selector] (证据)`（selector 已在其中）；export-status 的 `To` 符号存在性检查改查成员表。`ObjCImplementationClassDumper` 的 ObjC 方法段已经按 selector 列出，只把 Swift 成员行的注释换成同一套渲染。
- 注释里 Swift 祖先 / 类名沿用上一提案的限定名显示。

### 范围外与降级

- **泛型 ObjC 派生类**（没有静态 class object）与**磁盘 app 二进制的跨镜像祖先**（bind 断链）维持上一提案的降级；后者让 `override func encode(with:)` 因祖先链不完整而不被认作覆写，也因此不判显式 selector——打成裸 `@objc func encode(with:)`，缺 `override`、不多 `@objc(…)`，两个方向都是「不知道就不说」。
- **第三档默认关**不在本提案内讨论。
- **性能**：thunk 反汇编从「被覆写的方法」扩大到「全部 `@objc` 方法」，每条 thunk 最多解码 96 条指令；A/B 时记 SwiftUI / AppKit 的 interface 耗时，与基线比差异应在噪声内，超过 5% 要回头看。

### 验证

- fixture 扩展：`SwiftDerivedWidget` 加 `@objc(pokeWithForce:) func poke(force:)`、`@objc(customLevel) var alias`、`@objc func fetch() throws`、`@objc func load() async`、`@objc dynamic` 成员（已有 `dynamicHook`）；一个 Swift extension 提供 `@objc func fromExtension()` 与 `@objc override func ping()`（category 里的覆写，上一提案留待后续的一项）；一个 `@objc protocol` 及其 witness（selector 与默认推导不同，验证协议排除）。interface 断言：显式 selector 的两个成员打 `@objc(...)`，其余 `@objc` 成员不打括号，witness 不打括号，category 成员带 `@objc`、覆写者带 `override`；dump 断言 `// @objc -[...]` 注释与证据档位。
- 默认推导的单元测试：一张「Swift 名 → 默认 selector」对照表固定编译器规则（含介词、`throws` / `async`、初始化器、setter 无 `is` 处理、subscript 四个固定 selector）。
- AppKit（macOS 26 门控）：`NSGlassEffectView` 的全部 `@objc` 成员在 interface 上带 `@objc`；整份 AppKit interface 的成员级 `@objc` 数从 0 变为正数；`@objc dynamic` 且无 descriptor 的成员不再带 `final`。
- 渲染 A/B（基线 = `next` 头 74c4eb24）：允许的差异只有五类——成员行新增 `@objc` / `@objc(sel)`、成员行去掉 `final`、去掉 `// not exported`、dump 新增 `// @objc -[…]` 注释、`@implementation` 段 Swift 成员行注释改写；其余任何差异都是回归。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-21 | Created as Draft | 用户在追问「selector 与 Swift 名不一致编译器怎么处理」时提出让符号索引顺手收 ObjC 符号、拿 `bl` 地址匹配 ObjC 方法；调研确认方向相反（`bl` 目标是 Swift 实现）且 ObjC 方法符号在系统 cache 里同样被 strip，成立的变体是从方法表建成员表；同时发现 strip 后成员级 `@objc` 整体丢失（AppKit interface 0 处） |
| 2026-09-21 | 归宿在 SwiftInspection / SwiftThunkAnalysis，不进 `MachOSymbols` 的 `SymbolIndexStore` | `MachOSymbols` 只依赖 MachOKit、Demangling 与读取层，把 ObjC 方法表解析塞进去会把 MachOObjCSection 拉到模块图底层；成员表与已有的 `ObjCClassMethodIndex` 同层同模式 |
| 2026-09-21 | 显式 selector 用编译器的正向默认推导判定，不用 importer 的一致性检查 | 前者确定且无损（`Decl.cpp getObjCSelector` 可逐条移植），后者有损只能做守卫；两者分工不同，各留各的 |
| 2026-09-21 | 覆写成员与可读到的协议 witness 不打 `@objc(sel)`；协议读不到时不排除 | 覆写与 witness 的 selector 是继承的，源码不会写；读不到协议时按事实打是合法且真实的，宁多勿错 |
| 2026-09-21 | 类型按新范围改名，不留旧名 | 上一提案的类型只在 `next` 上、未发布；名字继续叫 override 会误导后来者 |
| 2026-09-21 | Draft → Accepted → In Progress | 用户确认方案（含五条自定假设：编译器正向推导判显式 selector、覆写与 witness 不打括号、dump 行内注释、类型改名、纳入 category）后开始实现 |
| 2026-09-21 | `@objc @implementation` 类的成员**照常**判显式 selector | 第一版在系统 cache 的 AppKit 上报出 8 个显式 selector，7 个落在 `@implementation` 类（`NSGradient` 的 `drawInRect:angle:` 对 `draw(in:angle:)`），一度以为那里 selector 继承自头文件、不该算显式；给 fixture 加 `- (void)drawInRect:` / `func draw(in:)` 时编译器报 `selector 'drawIn:' for instance method 'draw(in:)' not found in header`，证明 `@implementation` 体里 selector 同样从 Swift 名推导、要对上头文件必须写 `@objc(drawInRect:)`——那 7 处本就是源码里写着的。撤回清标记的改动，fixture 固定 `@objc(drawInRect:) func draw(in:)` |
| 2026-09-21 | strip 后的显式 selector 不还原，诚实漏标 | 第二档的 importer 拼法守卫天然拒绝改过名的 selector（`pokeUsingForce:` 不是任何拼法下的 `poke(force:)`），放宽守卫会把内联方法体里对同类别的成员的调用错认成 `@objc`，违背「只联结不猜」；fixture 的 `.strippedLocals` 变体把这一点固定成测试 |
| 2026-09-21 | `init` 与 `.cxx_destruct` 留在表里 | 编译器给每个 ObjC 派生的 Swift 类合成的 `init` 与指向 ivar destroyer 的 `-.cxx_destruct` 都是真实的方法表条目；前者联结到 allocator 定义（默认 selector `init`，不算显式），后者没有成员定义，只在 dump 符号行留注释 |
| 2026-09-21 | 介词表 30 个词，不是提案初稿写的 34 | `PartsOfSpeech.def` 实数；测试固定 `prepositions.count == 30` |
| 2026-09-21 | In Progress → Implemented | 实现连同文档合入 `next`；配套文档（实现说明改名扩写、任务报告）已登记在头部，术语「ObjC member table」已入术语表；编号按仓库惯例在发布合入 `main` 时分配 |
| 2026-09-21 | 祖先链没走完或协议读不到时不判显式 selector（fail closed） | 第一轮 A/B 在模拟器运行时的 SwiftUI 文件（父类 UIView 是 bind）上判出 35 个显式 selector，几乎全是 `hitTest:withEvent:` / `drawRect:` / `touchesBegan:withEvent:` 这类 UIKit 覆写：合法但误导，读者会以为是自定义命名。提案初稿的「读不到不排除」改成「读不到不判」；fixture 文件腿固定不判、进程内腿固定判出 |
| 2026-09-21 | 旧 bind 格式的父类槽位按 bind 处理，Swift 类永不当根类 | fail closed 之后 A/B 的 iOS 15.5 模拟器腿仍判出显式 selector：那些框架用 `LC_DYLD_INFO`，bind 槽位在文件里是 0，MachOObjCSection 读成「没有父类」，链被当作走完。读取器补 MachOKitExtensions 的 `resolveBind(fileOffset:)`（认两种格式）取名，再以 `isSwift` 兜底；fixture 加 `.legacyBinds` 变体（`-target arm64-apple-macosx11.0`）固定 |
| 2026-09-21 | 读成空字符串的协议 selector 视为读失败，集合标不完整 | 第三轮 A/B 的 macOS 15.5 cache 腿仍有一处：WidgetKit 的 `encode(with:)` 被判显式，探针显示它采纳的 Foundation `NSSecureCoding` 跨镜像读出的方法名全是空串——集合「完整」却缺 `encodeWithCoder:`。跨镜像协议方法名的读取问题在 MachOObjCSection，这里只保证不据此下错判 |
| 2026-09-21 | witness 判定连祖先采纳的协议一起算 | 第四轮 A/B 的进程内腿判出 `SwiftUIOutlineTableView.draggingSession(_:movedTo:)` 为显式 selector——`draggingSession:movedToPoint:` 是 `NSDraggingSource` 的可选要求，conformance 在祖先 `NSTableView` 上，子类的实现继承它的 selector（编译器 `inferObjCName` 查的是全部 conformance）。`Ancestor` 加协议 selector 集合，完整性要求整条链都读完；fixture 给 `WidgetObserving` 加 `@objc(widgetWillPingSoon) optional func widgetWillPing()`、孙类实现，固定「继承的 conformance 不算显式」 |
