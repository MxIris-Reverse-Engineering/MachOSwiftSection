# 2026-09-21 ObjC 祖先链走依赖闭包：独立文件上的 bind 按名字在依赖镜像里续链

## 起点

上一批（从 ObjC 方法表还原每个 `@objc` 成员）落地后，成员表在 cache 镜像与进程内都能跨镜像走到根，但独立的 Mach-O 文件——app 二进制、抽出来的框架、模拟器运行时的框架文件——父类是 bind，链在第一跳就断：UIKit / AppKit 的覆写一个都标不出，显式 selector 一律不判（fail closed），渲染 A/B 的四条模拟器腿没有一行 `override`。用户问「父类是 bind 这些能不能像 Layout 那样走闭包解析」，又问「`ImageUniverse` 需要抽出来么」。答：能，`dependencySearchPaths` 已通到 indexer、`PropertyWrapperTypeCatalog` 是同形状的先例；不抽 `ImageUniverse`——它的五个 resolver 全是布局问题，SwiftLayout 在 SwiftInspection 之上反向引用是环，祖先链只要「按名字找 class object」，`ObjCClassMethodIndex` 的名字表已有。提案先写、上下文压缩后按「把依赖闭包接一下」动工。

## 调研发现

**bind 的名字就是 `class_ro_t.name`。** chained fixups 由 MachOObjCSection 直接给出 `superClassName`；旧 `LC_DYLD_INFO` 格式由 MachOKitExtensions 的 `resolveBind(fileOffset:)` 给（上一批已补）。`_OBJC_CLASS_$_UIView` 去前缀是 `UIView`，Swift 父类的 `_OBJC_CLASS_$__TtC7SwiftUI9Something` 去前缀是 `_TtC…`，与 `class_ro_t.name` 一致，不需要二次转换。

**bind 只能落到导出符号，所以 export trie 是精确预检。** 对闭包里每个镜像先问 trie 有没有 `_OBJC_CLASS_$_<name>`，有才建那个镜像的名字表（一遍 classlist + catlist），umbrella 的 re-export 条目会通过预检但 classlist 落空，跟在闭包后面的真正定义者接住。app 二进制的几十个依赖里只有一两个会被真正扫描。

**宿主的 macOS cache 会把 Catalyst 镜像喂给 iOS 根。** iOS 二进制的 `/System/Library/Frameworks/UIKit.framework/UIKit` 在 macOS cache 里没有精确匹配，裸名排序落到 `/System/iOSSupport` 的 Catalyst UIKit——同名类、不同平台、祖先 selector 集合不同。守卫放在 `FileDependencyLocator` 一次性建索引时：`LC_BUILD_VERSION`（没有则 `LC_VERSION_MIN_*`）的平台集合与根不相交的 cache 镜像不入索引；显式文件与 system root 不过滤；被拒的 load name 落既有的 `unresolvedLoadNames`。布局引擎与 `__C` 归属走同一个定位器一并受益——也意味着 iOS 二进制在 macOS 宿主上不带搜索路径时它们不再拿到 Catalyst 镜像，诚实降级。

**环境漂移：兄弟仓库 `swift-capstone` 当天升到了 Capstone v6。** trait 从 `ARM64` 改名 `AARCH64`，本 worktree 的 Package.swift 还按旧 trait 声明，本地兄弟依赖一开就构建失败。本批全部用 `USING_LOCAL_DEPENDENCIES=0`（远程 pin：MachOKit 0.52.102、MachOObjCSection 0.8.105、swift-demangling 0.7.0、swift-capstone 5.0.0，即 CI 的配置）在新 scratch 里构建、测试与 A/B，两侧一致。

## 最终方案

提案已写（`draft-objc-ancestor-dependency-closure`），用户一句话批准。落地与提案的差异全部记在提案的「落地形状与方案的差异」与决策日志里，要点：解析器按镜像登记、无人登记的文件默认走系统 cache（与 catalog 同一契约）；hierarchy memo 的键带解析器身份；provider 交出的断链也续；闭包与 catalog 共用一次求值（`SharedDependencyClosure`）；`swift-section dump` 自己注册；A/B 模拟器腿对两侧都传 `--dependency-search-path <RuntimeRoot>`；SwiftLayout 的 `ObjCClassIndex` 不收拢。

## 执行

MachODependencies（`DependencyPlatforms`、`FileDependencyLocator(platforms:)`、`SharedDependencyClosure`）→ SwiftInspection（`ObjCAncestorResolver` / `ObjCAncestorResolverStore`；`ObjCClassMethodIndex` 的 `.unresolvable(name)` 续链、category 目标类的 bind 续链、memo 键、`completingAncestors(of:in:)`；`ObjCClassHierarchies.removeCache` 一并清）→ SwiftThunkAnalysis（provider 结果续链）→ SwiftDeclarationRendering（`PropertyWrapperTypeCatalog.make(root:dependencyImages:)`）→ SwiftIndexing（`registerDependencyClosureConsumers`、新 claim）→ swift-section（`dump` 注册、帮助文本）→ 脚本 → fixture 与测试 → 文档。

第一版第一轮 A/B（对基线 `feature/objc-member-selector-recovery` 9149d899，`--jobs 6`）抓到四件事，每件都改了方案：

1. **「cache 内根镜像先查自己的 cache」撤回。** `cache-15.5` 腿的 SwiftUI interface 丢了 `@SwiftUI.IdentityLink` 的 property-wrapper 还原（退化成 `var _viewID: SwiftUI.IdentityLink`）。那个版本里 `IdentityLink` 是 SwiftUI 内部类型、accessor 被 strip，基线一直是靠宿主 26.6 cache 里 SwiftUICore 的导出（`@_originallyDefinedIn` 保留了 `SwiftUI` 模块名）判出来的；闭包按 bare name 去重，自己 cache 里的 SwiftUICore 一进来就挡住了宿主的。catalog 的跨版本取证不在本提案范围，撤回，闭包语义与基线完全一致。
2. **祖先的 category 来自别的文件时看不见。** 模拟器腿上四个显式 selector（`observeValueForKeyPath:ofObject:change:context:` ×2、`_accessibilityBoundsForRange:`、`_bridgedUpdateConfigurationUsingState:`）全是覆写——cache 里 dyld 把同一 cache 内其它镜像的 category 预挂进类的 list-of-lists（cache 腿上 `observeValueForKeyPath:` 一直判为 NSObject 的覆写，靠的就是 Foundation 的 KVO category 已挂在 libobjc 的 NSObject 上），文件世界里 category 只在加载时挂。现在祖先链每一跳都把根镜像自己与闭包里每个独立文件对该祖先的 category（实例 / 类方法 + category 采纳的协议）并进祖先的集合，按名字 memo。进程内同理：`dlopen` 进来的非 cache 镜像的 category 被运行时挂进 `class_rw_ext_t`，两个读取器只读 `class_ro_t`——`MachOImage` 根也有一个只做折入的解析器。fixture 为此加了第二个 dylib：头文件里声明 `NSObject (SeparatelyShipped)` 的 `noteValueForKeyPath:ofObject:`（与 Foundation 的 KVO 同形，编译器从 `noteValue(forKeyPath:of:)` 推不出这个 selector），实现放在 `libObjCImplementationFixtureCategories.dylib` 里、每个变体都链接它；`SwiftDerivedWidget` 覆写它。三种结果钉住：闭包含 category dylib → 文件腿判为 NSObject 的覆写；进程内 → 同；只给系统 cache → category dylib 报未解析、成员判成显式 selector（边界，钉成显式事实而不是期望）。
3. **category 目标类是旧格式 bind 时读不出名字。** category dylib 为了让 `.legacyBinds` 变体也能链接它以 `macosx11.0` 为部署目标，它对 NSObject 的 category 的类指针槽位在文件里是 0，MachOObjCSection 读不出名字，折入落空。`targetClassName(of:)` 与 `superclassLocation(of:)` 一样补 `resolveBind(fileOffset:)`。
4. **iOS 18.5 及之后的模拟器文件 classlist 读不出一部分。** 18.5 / 18.6 / 26.5 腿上 UIKit 根的链几乎全标 `(bound; chain not resolvable offline)`，15.5 腿大部分走完但 `UIView` / `CALayer` 仍缺。一度怀疑 MachOKit 的 trie `search(by:)` 对「键是别的导出的真前缀」失手（`UIView` / `UIViewController`），改成前缀查找再过滤；探针（一次性测试，用完即删）证明精确查找正常，真因是读取器：UIKitCore 18.5 的 `__objc_classlist` 5017 项里 791 个 `class_ro_t` 读不到、624 个被误读为元类、146 个名字为空，`UIView` / `UIResponder` / `UISplitViewController` 的 class object 都不在可读集合里（export trie 能查到符号，classlist 里没有对应偏移）；Foundation 18.5 同样（715 项里 101 个读不到，`NSExtensionContext` / `NSNumber` 缺）。兄弟仓库 MachOObjCSection 的 8 个未发布 commit 也未触及这里。前缀查找的改动撤回，这条记为已知边界。

另两处在测试里改的预期：链走完后编译器合成的 `init` 成了 `-[NSObject init]` 的覆写——与 cache 腿一直以来的行为一致；`SymbolTestsCore` 三份快照重录，diff 只有 `// ObjC ancestor chain: NSObject` 三处、`@objc init()` → `@objc override init()` 三处、`ExternalObjCSubclassTest.isKind(of:)` 从 `@objc func` 变为 `override func`——上一批任务报告里「断链错判的最小样本」，现在按事实标。

一个自己挖的坑：`ObjCAncestorResolverStore` 里同标签的泛型重载 `resolver(for: some MachORepresentableWithCache)` 从 `as? MachOFile` 分支里调 `resolver(for: machOFile)` 时解析到了自己，无限递归 SIGBUS；改名 `resolver(forImage:)`。

## 验证

- 定向套件（远程 pin，新 scratch）：`ObjCMemberRecoveryTests`（含新增的解析器 / 注册表 / 空解析器 / category dylib 正例与边界 / provider 续链 / `.legacyBinds` 两种解析器）、`ObjCMemberDumpTests`、`ObjCImplementationClassRecognitionTests`、`ObjCImplementationClassDumpTests`、`AppKitObjCMemberTests`、`AppKitObjCImplementationClassTests`、`FileDependencyLocatorTests`（平台守卫）、`DependencyClosureTests`、`SwiftInterfaceBuilderDependenciesTests`、`LegacyDyldInfoBindTests`：66 / 66；`SymbolTestsCoreInterfaceSnapshotTests`、`SymbolTestsCoreDumpSnapshotTests`（重录后）、`ExportStatusDumpAnnotationTests`、`PerImageCacheEvictionTests`、`SwiftSectionCommandTests`、`DependencyClosureLayoutTests`、`VTableSlotAttributionTests`、`FinalKeywordICFRegressionTests`：82 / 82。碰 fixture 的四个 suite 挂了 `ExclusiveImageAccess(ObjCImplementationFixture.moduleName)`。
- harness 自己的单元测试 9 / 9（模拟器腿多传一个参数）。
- **渲染 A/B**（基线 `feature/objc-member-selector-recovery` 9149d899，两侧远程 pin、`--jobs 6`，基线侧第二轮 54 对全部命中缓存）：最终一轮 78 对，**27 对有差，全部在模拟器腿**；归档 cache 腿（macOS 15.5）12 对与进程内腿 24 对逐字节一致（macOS 26.6 腿本轮没跑：归档目录已从 `26.6` 改名 `26.6.2`，脚本常量没跟——这是此前就挂着的一项，本批未动）；一次性分类脚本逐行归类，**未解释差异 0**。模拟器腿的差异全是本提案要的那几类：

  | 腿 | interface `+override` | dump `overrides` 注释 | dump 链注释（新增 / 改写） | 显式 selector | 仍断的链 |
  |---|---|---|---|---|---|
  | sim-iOS-15.5（SwiftUI / SwiftData / WidgetKit） | 87 | 185 | 60 / 9 | 1 | 6 / 65 |
  | sim-iOS-18.5（六框架） | 18 | 32 | 84 / 14 | 0 | 20 / 104 |
  | sim-iOS-18.6 | 18 | 32 | 84 / 14 | 0 | 同 18.5 |
  | sim-iOS-26.5 | 19 | 36 | 98 / 16 | 0 | 24 / 122 |

  仍断的链就是「执行」第 4 条那批（`_UIGraphicsView → UIView`、`RBLayer → CALayer`，18.5+ 上 UIKit 根几乎全部）。唯一剩下的显式 selector 是 15.5 上 `SwiftUI.AccessibilityNode._accessibilityBounds(for:)` 对 `_accessibilityBoundsForRange:`：链走完（`UIResponder → NSObject`）、闭包里可读文件的 category 里没有这个 selector；它要么真是源码写的 `@objc(_accessibilityBoundsForRange:)`，要么覆写的是某个不在闭包里（或读不出）的私有 accessibility category——无法离线核实，按规则照判。第一轮（改动前）同一腿是 51 个 `+override`、3 个显式 selector，其中 `observeValueForKeyPath:…` 两处是假的，category 折入后成了 `overrides -[NSObject observeValueForKeyPath:ofObject:change:context:]`。
- **全量测试**（`--skip IntegrationTests`，远程 pin）：1998 例、380 个 suite，4 处 issue，均与本批无关——`SharedCacheTests` 的三个墙钟并行度断言在全量负载下假失败，单独重跑 9 / 9；`GenericSpecializationTests.argumentCandidatePathSpecializesNonGenericCandidate` 在基线 `next` 上同样失败（上一批已记录，留给用户）。

## 遗留

- iOS 18.5+ 模拟器文件的 classlist 读取（上面第 4 条）——底层读取器的活，修好后模拟器腿的 UIKit 根链会自然走完，本提案不需要再改。
- category 所在镜像不在闭包里（闭包解析不到的依赖）仍看不见，覆写它的成员会被判成显式 selector；要更保守可以在闭包有未解析依赖时不下显式判定，没做——OS 框架的闭包总有几个弱链接的缺席依赖，会把模拟器腿的判定全关掉。
- `PropertyWrapperTypeCatalog` 对归档 cache 根镜像的取证靠宿主 cache 的导出（上面第 1 条），是否该改成「先自己的 cache、再宿主 cache、不按 bare name 互斥」另议。
- 本批用远程 pin 构建；`swift-capstone` v6 的适配（trait 改名 + API）是另一条线。
