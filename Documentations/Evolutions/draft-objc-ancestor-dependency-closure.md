# Draft - ObjC 祖先链走依赖闭包：独立文件上的父类与 category 目标类按名字在依赖镜像里解析

- **状态**: Draft
- **作者**: JH
- **创建日期**: 2026-09-21
- **最后更新**: 2026-09-21
- **所属愿景**: 无
- **关联提案**: [draft-objc-member-selector-recovery](draft-objc-member-selector-recovery.md)（本提案补它留下的「磁盘二进制的跨镜像祖先」一项：祖先链在 bind 处断掉时，`override` 标不出、显式 selector 不判、链注释标断）、[0017-dependency-closure-unification](0017-dependency-closure-unification.md)（复用它的 `DependencyClosure` / `DependencySearchPath` / `FileDependencyLocator`，平台守卫加在那里）
- **实现分支 / PR**: 待定（自 `next` 分出，须在 `feature/objc-member-selector-recovery` 合入之后）
- **配套文档**: 待落地时登记（预计在 [ObjCMemberRecovery.md](../Internal/ObjCMemberRecovery.md) 加一节）

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

- `SwiftLayout.ObjCClassIndex` 自己也扫 `__objc_classlist` 建名字表；可改为从 `ObjCClassMethodIndex` 取 class object，只保留 instanceSize / instanceStart 与进程内 rw 解析那部分自己的读取。做不做看落地时的顺手程度，做了记决策日志。

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
