# Draft - ObjC 祖先链走依赖闭包：独立文件上的父类与 category 目标类按名字在依赖镜像里解析

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-09-21
- **最后更新**: 2026-09-21
- **所属愿景**: 无
- **关联提案**: [draft-objc-member-selector-recovery](draft-objc-member-selector-recovery.md)（本提案补它留下的「磁盘二进制的跨镜像祖先」一项：祖先链在 bind 处断掉时，`override` 标不出、显式 selector 不判、链注释标断）、[0017-dependency-closure-unification](0017-dependency-closure-unification.md)（复用它的 `DependencyClosure` / `DependencySearchPath` / `FileDependencyLocator`，平台守卫加在那里）
- **实现分支 / PR**: `feature/objc-ancestor-dependency-closure`（叠在 `feature/objc-member-selector-recovery` 之上，两条分支按序合入 `next`）
- **配套文档**: [ObjCMemberRecovery.md](../Internal/ObjCMemberRecovery.md)「祖先链走依赖闭包」一节、[Modules/MachODependencies.md](../Internal/Modules/MachODependencies.md)（平台守卫、`SharedDependencyClosure`）、[任务报告](../Internal/TaskReports/2026-09-21-objc-ancestor-dependency-closure.md)

## 摘要

ObjC 成员表的祖先链在 cache 镜像和进程内都能跨镜像走到根，但在独立的 Mach-O 文件（app 二进制、抽出来的框架、模拟器运行时的框架文件）上，父类是 bind，链在第一跳就断：UIKit / AppKit 的覆写一个都标不出，显式 selector 一律不判（fail closed），链注释全是「断在 bind」。渲染 A/B 的四条模拟器腿今天没有一行 `override`，就是这个原因。

SwiftLayout 的 `ImageUniverse` 早就用 `DependencyClosure` 按名字在依赖镜像里找 ObjC 祖先的 instance size；`PropertyWrapperTypeCatalog` 用同一个闭包按镜像注册跨镜像事实给 `TypeDefinition.index(in:)` 读。本提案让祖先链照同一条路走：indexer 用 `SwiftDeclarationIndexConfiguration.dependencySearchPaths`（默认系统 cache，CLI `--dependency-search-path`）算出的闭包，按镜像注册一个祖先解析器；`superclassLocation` 返回 `.unresolvable(name)` 时，解析器按 BFS 顺序在依赖镜像里查 `ObjCClassMethodIndex` 的「运行时名 → class object」表，命中就把链续到那个镜像里。同时给 `FileDependencyLocator` 加平台守卫，防止 iOS 二进制在 macOS cache 里找到 Catalyst 的同名类。

**不抽 `ImageUniverse`**：它的五个 resolver 全是布局的问题，且 SwiftLayout 在 SwiftInspection 之上，反向引用是环；祖先链只要「按名字找 class object 并拿到那个镜像的 reader」，而这张按镜像的表 `ObjCClassMethodIndex.Storage.classObjectsByRuntimeName` 已经存在、已经惰性、已经是 `SharedCache`。要共享的是闭包，它本来就是共享的。

## 方案

### 解析器（SwiftInspection）

- `ObjCAncestorResolver`（值类型或 final class，`Sendable`）：持有闭包的依赖镜像列表 `[MachOFile]`（`DependencyClosure(root:searchPaths:traversal: .transitive).images`，BFS 顺序，根镜像不含）。`classObject(named:) -> (any ObjCImplementationClassReading, ObjCClass64)?`：按顺序对每个镜像取 `ObjCClassMethodIndex.shared.storage(in:)?.classObjectsByRuntimeName[name]`，第一个命中即返回；查过的镜像自然建了名字表，没查到的不建——与 `ImageUniverse` 同样的惰性。同名类出现在多个镜像时取第一个并 `#log(.info)`。
- bind 名到查表 key：`_OBJC_CLASS_$_UIView` 去前缀得 `UIView`；Swift 父类的 bind 名 `_OBJC_CLASS_$__TtC7SwiftUI9Something` 去前缀得运行时名 `_TtC…`，与 `class_ro_t.name` 一致，不需要二次转换。
- 按镜像注册：`ObjCAncestorResolverStore`（与 `ObjCClassHierarchyProviderStore` / `PropertyWrapperTypeCatalogStore` 同一模式，弱引用或与 indexer 生命周期绑定，`ObjCClassHierarchies.removeCache(for:)` 一并驱逐）。
- 接入点：`ObjCClassMethodIndex.ancestors(startingAt:className:)` 的 `.unresolvable(name)` 分支先问解析器，命中则改为 `.resolved(reader, classObject)` 继续走；找不到才断链。category 的目标类（`targetClass(of:)` 为 nil 时）同一个解析器。memo 落在命中镜像自己的 storage（已支持）。cache 镜像和进程内镜像不注册解析器，行为不变。

### 注册（SwiftIndexing）

- `SwiftDeclarationIndexer.prepare()` 在注册 `PropertyWrapperTypeCatalog` 的同一处算一次 `DependencyClosure`，两者共用（`PropertyWrapperTypeCatalog.make(root:searchPaths:)` 改为接收已算好的闭包，或反过来解析器从它拿）。
- 闭包的 `searchPathLoadFailures` / `unresolvedLoadNames` 照既有做法作为事件派发，不在这里另起日志。

### 平台守卫（MachODependencies）

- `FileDependencyLocator.locate(loadName:)` 按精确装载路径命中优先、裸名排序其次；iOS 二进制的 `/System/Library/Frameworks/UIKit.framework/UIKit` 在 macOS cache 里没有精确匹配，裸名排序会落到 `/System/iOSSupport` 的 Catalyst 版——同名类、不同平台、祖先 selector 集合不同，`override` 会错标。
- 守卫：比对根镜像与候选镜像的 `LC_BUILD_VERSION` 平台（zippered 镜像有两个，任一相同即算匹配；没有 `LC_BUILD_VERSION` 的老镜像按 `LC_VERSION_MIN_*` 推），不匹配就跳过该候选、记进 `searchPathLoadFailures` 一类的可观测结果而不是静默。布局引擎跨镜像查 instance size 走同一个 locator，一并受益。

### 可选收拢（SwiftLayout，不作为本提案的验收条件）

- `SwiftLayout.ObjCClassIndex` 自己也扫 `__objc_classlist` 建名字表；可改为从 `ObjCClassMethodIndex` 取 class object，只保留 instanceSize / instanceStart 与进程内 rw 解析那部分自己的读取。做不做看落地时的顺手程度，做了记决策日志。**落地时没做**（见决策日志）。

### 落地形状与方案的差异（2026-09-21 落地）

- **解析器**是 `final class`（`ObjCAncestorResolver`），持有一个惰性求值的 `[MachOFile]`；查名字先问镜像的 export trie（bind 只能解析到导出符号，`_OBJC_CLASS_$_<name>` 不在 trie 里就不必建那个镜像的名字表；umbrella 的 re-export 条目会通过 trie 预检但在 classlist 上落空，闭包里跟着的真正定义者接住），再查 `ObjCClassMethodIndex` 的名字表；命中与未命中都按名字 memo。
- **注册表 `ObjCAncestorResolverStore`** 与 `PropertyWrapperTypeCatalogStore` 同形：indexer 在 `index()` 里注册、按独立的 claim 随最后一个活着的 indexer 驱逐，`ObjCClassHierarchies.removeCache(for:)` 也一并清；`swift-section dump`（没有 indexer）自己按 `--dependency-search-path` 注册；**无人注册的文件在首次查询时得到系统 cache 上的默认解析器**——与 catalog 一致，RuntimeViewer 这类直接走 dump 路径的宿主因此不需要改动。进程内镜像永远没有解析器（每个指针都是真的）。
- **cache 内的根镜像不先查自己的 cache（试过，撤回）**：落地时曾给 cache 内的根（归档 cache 的 A/B 腿）在配置路径前插入它自己所在的 cache，A/B 立刻抓到 `cache-15.5` 腿的 SwiftUI interface 丢了 `@SwiftUI.IdentityLink` 的 property-wrapper 还原——那个版本里 `IdentityLink` 是 SwiftUI 内部类型、accessor 被 strip，基线一直是靠宿主 26.6 cache 里 SwiftUICore 的导出（`@_originallyDefinedIn` 保留了 `SwiftUI` 模块名）判出来的；闭包按 bare name 去重，自己 cache 里的 SwiftUICore 一进来就挡住了宿主的。catalog 的跨版本取证不在本提案范围，撤回，闭包语义与基线完全一致。
- **祖先的 category 来自别的文件时折进祖先的 selector 集合**：cache 里的类，dyld 把同一 cache 内其它镜像的 category 预挂进它自己的 list-of-lists（cache 腿上 `observeValueForKeyPath:ofObject:change:context:` 一直判为 NSObject 的覆写，靠的就是 Foundation 的 KVO category 已挂在 libobjc 的 NSObject 上）；文件世界里 category 只在加载时挂，离线读祖先的方法表看不到——第一轮 A/B 的模拟器腿把四个这种覆写全判成了显式 selector（`observeValueForKeyPath:…`、`_accessibilityBoundsForRange:`、`_bridgedUpdateConfigurationUsingState:`）。现在祖先链的每一跳都把**根镜像自己**与**闭包里每个独立文件**对该祖先的 category（实例 / 类方法 + category 采纳的协议）并进祖先的集合（`ObjCAncestorResolver.fileCategorySelectors(onClassNamed:)`，按名字 memo；首次会给闭包里每个文件建名字表）。cache 镜像的 category 不折（已预挂）。边界：category 所在的镜像不在闭包里（闭包解析不到的依赖）就看不见，那条成员会被判成显式 selector——fixture 的 `categoryInAnUnreachableImageIsInvisible` 把这条边界钉成显式事实。
- **进程内也折 category**：`dlopen` 进来的非 cache 镜像，运行时把它们的 category 挂进 `class_rw_ext_t`，两个读取器都只读 `class_ro_t`，看不见；`MachOImage` 根现在也有一个解析器（`ObjCAncestorResolver(inProcessRoot:)`，只用于 category 折入、从不跟 bind），把进程里每个非 cache 镜像的 category 折进祖先——fixture 的进程内腿因此与文件腿一致。
- **category 目标类是旧格式 bind 时按 bind 流取名**：`targetClassName(of:)` 与 `superclassLocation(of:)` 一样补 `resolveBind(fileOffset:)`——fixture 的 category dylib 以 `macosx11.0` 为部署目标（好让 `.legacyBinds` 变体也能链接它），它对 NSObject 的 category 的类指针槽位在文件里是 0，MachOObjCSection 读不出名字，折入就落空。
- **已知边界（本提案不处理）**：iOS 18.5 / 18.6 / 26.5 模拟器运行时的 UIKitCore / Foundation 文件，`__objc_classlist` 有约六分之一读不出——探针实测 UIKitCore 5017 项里 791 个 `class_ro_t` 读不到、624 个被误读为元类、146 个名字为空，`UIView` / `UIResponder` / `UISplitViewController` 的 class object 都不在可读集合里（export trie 能查到符号，classlist 里没有对应偏移——一度怀疑是 MachOKit `search(by:)` 对真前缀键失手，探针证明精确查找正常）；iOS 15.5（旧 rebase 格式）大部分能读、`UIView` / `CALayer` 仍缺。这是 MachOKit / MachOObjCSection 对这批 chained-fixup 文件的读取问题（兄弟仓库的未发布 commit 也未触及），本提案的解析器在读得出的类上工作正常；A/B 模拟器腿上仍标 `(bound; chain not resolvable offline)` 的链就是这批。
- **hierarchy memo 的键带解析器身份**（`Storage.HierarchyMemoKey`）：同一个 class object 在不同解析器下的链不同，测试里「先空解析器、后默认解析器」不能读回断链；祖先 selector 集合不走链，memo 不变。
- **provider 交出的断链也续**：宿主的 ObjC 索引器在 bind 处停下的位置与库读取器相同，`ObjCMembers.hierarchy(forClassNamed:in:)` 对 provider 的结果调 `ObjCClassMethodIndex.completingAncestors(of:in:)`，用同一个解析器从 `unresolvedAncestorName` 续，两条接缝在独立文件上得到同一条链（`registeredProviderIsConsultedAndAgreesWithTheReader` 锁定）。
- **闭包与 catalog 共用**：indexer 用 `SharedDependencyClosure`（MachODependencies 新增，一次求值、多方共享）同时喂 `PropertyWrapperTypeCatalog.make(root:dependencyImages:)`（新重载）与解析器；闭包首次求值时把 `searchPathLoadFailures` 按 `SwiftInterfaceBuilderDependencies` 的既有做法派发为 `renderingDegraded(.dependencyLoad)` 事件，`unresolvedLoadNames` 仍是数据。
- **平台守卫**在 `FileDependencyLocator` 一次性建 cache 索引时过滤：`DependencyPlatforms.platforms(of:)` 收全部 `LC_BUILD_VERSION` 的平台（zippered 镜像两个），没有就按 `LC_VERSION_MIN_*` 推；与根镜像的集合不相交的 cache 镜像不入索引（精确路径与裸名两步一起受约束），显式文件与 system root 是用户自己给的、不过滤；一个 load name 的候选全被拒时它落进闭包既有的 `unresolvedLoadNames`，没有另起一条可观测通道。`DependencyClosure(root: MachOFile, …)` 自动传根的平台。**副作用**：iOS 二进制在 macOS 宿主上不带 `--dependency-search-path` 时，布局引擎与 `__C` 归属过去会拿到 Catalyst 的 UIKit，现在拿不到——诚实降级；A/B 脚本的模拟器腿因此对两侧都传 `--dependency-search-path <RuntimeRoot>`。
- **SwiftLayout 收拢没做**：`ObjCClassIndex` 除名字表外还读 instanceSize / instanceStart 与进程内 `class_rw_t`，与 `ObjCClassMethodIndex` 的 storage 形状不同，合并的收益（一次 classlist 扫描）小于改动面。
- **测试**：fixture 的文件腿现在经宿主 cache 走到 libobjc 的 `NSObject`，`override var description` 与 `@objc(pokeUsingForce:)` 在文件上也标；断链行为用 `dependencySearchPaths: []`（indexer）与 `ObjCAncestorResolver.empty`（直接查表）固定；碰 fixture 的四个 suite 一起挂 `ExclusiveImageAccess`（注册表按镜像全局，不排他会互相踩）。链走完后编译器合成的 `init` 成了 `-[NSObject init]` 的覆写——与 cache 腿一直以来的行为一致，测试预期随之改。`SymbolTestsCore` 的三份快照重录：`ExternalObjCSubclassTest.isKind(of:)` 从 `@objc func` 变为 `override func`（正是上一提案任务报告里「断链错判的最小样本」），类的链注释不再标 bound。

### 对测试与输出的影响

- fixture 的文件腿会经系统 cache 走到 libobjc 的 `NSObject`，链变完整：`override var description` 在文件上也标，显式 selector 在文件上也判。现有「文件上不标、进程内才标」的用例改成显式传空搜索路径（`dependencySearchPaths: []`）来保留断链行为，另加一组默认路径下链完整的断言。
- `.legacyBinds` 变体：bind 名解析出 `NSObject` 后也能续链，同样分「有 / 无搜索路径」两组。
- 渲染 A/B：模拟器腿把运行时自己的 dyld cache 作为搜索路径（`--dependency-search-path <runtime>/.../dyld_shared_cache_arm64`）后应与 cache 腿对齐：新增 `override`、`@objc(sel)`、链注释走完；差异只允许这几类。脚本要给模拟器腿加这个参数（按腿筛选 `--scenarios`、并发 `--jobs`、基线缓存已于 2026-09-21 先行落地，见 [SystemFrameworkRenderingVerification.md](../Internal/SystemFrameworkRenderingVerification.md)）。
- 性能：每个依赖镜像首次被问到时建一次名字表（只读 classlist 与类名），方法表按类惰性；对 app 二进制常见的几十个依赖可忽略。

### 范围外

- 泛型 ObjC 派生类（无静态 class object）维持不标。
- 归档 cache 里跨镜像读协议方法名读成空串的问题在 MachOObjCSection，本提案不碰；空串守卫继续生效。
- 第三档「只按名字」默认关不动。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-21 | Created as Draft | 用户问「父类是 bind 这些能不能像 Layout 那样走闭包解析」；能，且 `dependencySearchPaths` 已通到 indexer，`PropertyWrapperTypeCatalog` 是同形状的先例 |
| 2026-09-21 | 不抽 `ImageUniverse`，共享的是 `DependencyClosure` | `ImageUniverse` 的五个 resolver 全是布局问题，SwiftLayout 在 SwiftInspection 之上反向引用是环；祖先链只需按名字查 class object，这张表 `ObjCClassMethodIndex` 已有且是 `SharedCache` |
| 2026-09-21 | 平台守卫放 `FileDependencyLocator`，不放解析器 | 错平台的同名类是 locator 裸名排序的问题，布局引擎同样会踩；修在下面一层两边都好 |
| 2026-09-21 | 断链用例改为显式空搜索路径保留 | 默认系统 cache 会让 fixture 文件腿的 NSObject 变得可达；「链断时不猜」这条行为仍要有测试钉住 |
| 2026-09-21 | 用户「把依赖闭包接一下」→ Accepted → In Progress | 轻量档，一句话批准；叠在未合入的成员表分支上做，两条按序合 |
| 2026-09-21 | 注册表给无人注册的文件一个系统 cache 上的默认解析器，而不是「没注册就断链」 | 与 `PropertyWrapperTypeCatalogStore` 同一契约；直接走 dump 路径的宿主与测试的直接查表不必各自注册；要断链的测试显式装 `.empty` |
| 2026-09-21 | hierarchy memo 键带解析器身份，而不是注册时驱逐 storage | 驱逐在并行 suite 下有窗口；带身份的键让「先空后默认」顺序确定、无需清缓存 |
| 2026-09-21 | provider 交出的断链也经解析器续 | 否则 `registeredProviderIsConsultedAndAgreesWithTheReader` 的「两接缝等价」在独立文件上不再成立；续链只依赖 `unresolvedAncestorName`，provider 协议不变 |
| 2026-09-21 | 闭包与 catalog 共用一次求值 | 各自建闭包 = 各自把搜索路径里的 cache 整扫一遍 |
| 2026-09-21 | cache 内根镜像先查自己的 cache——**撤回** | 归档 cache 的依赖按定义在同一个 cache 里，看似更对；但 A/B 显示 property-wrapper catalog 在 `cache-15.5` 腿上因此丢掉 `@IdentityLink`（基线靠宿主 26.6 cache 的导出判出），改 catalog 的取证策略不在本提案范围 |
| 2026-09-21 | 平台不匹配的候选只落 `unresolvedLoadNames`，不加新的可观测通道 | 定位器已有的「答不上就报未解析」正是这种情况的语义；加字段要穿过 `DependencyClosure` 的泛型定位器接缝，收益小 |
| 2026-09-21 | A/B 脚本模拟器腿对两侧都传 `--dependency-search-path <RuntimeRoot>` | 平台守卫让宿主 cache 对 iOS 根一律拒绝，不传则两侧都断链、本提案在模拟器腿上看不到效果；两侧同传，catalog 与布局的输入也一致，差异只剩解析器本身 |
| 2026-09-21 | SwiftLayout `ObjCClassIndex` 不收拢 | 它还读 instanceSize / instanceStart 与进程内 rw，形状不同；一次 classlist 扫描的节省不值改动面 |
| 2026-09-21 | 祖先的 category 从根镜像与闭包里的独立文件折入；进程内从已加载的非 cache 镜像折入 | 文件世界里 category 不预挂，Foundation 的 KVO 覆写在模拟器腿被判成显式 selector；进程内运行时挂进 `class_rw_ext_t`、读取器看不见；fixture 加单独的 category dylib（对 NSObject 的 category，与 Foundation 的 KVO 同形）钉住两条腿的正例与「镜像不在闭包里就看不见」的边界 |
| 2026-09-21 | iOS 18.5+ 模拟器文件的 classlist 部分读不出，记为已知边界不处理 | 底层读取器问题（探针：UIKitCore 5017 项 791 个 ro 读不到、624 个误读为元类），与本提案无关；解析器在读得出的类上工作正常 |
| 2026-09-21 | Implemented | 代码、测试、脚本、文档同批；A/B 见任务报告 |
