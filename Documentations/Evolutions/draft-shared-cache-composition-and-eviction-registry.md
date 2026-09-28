# Draft - 按镜像缓存整治：`SharedCache` 去继承、键去装箱、驱逐收口到注册表

- **状态**: In Progress
- **作者**: JH
- **创建日期**: 2026-09-28
- **最后更新**: 2026-09-28
- **所属愿景**: 无
- **关联提案**: [0019-large-stack-executor-and-cross-version-parallelism](0019-large-stack-executor-and-cross-version-parallelism.md)（已裁决不做 `SharedCache` / `SymbolIndexStore` 的 async 建表路径，本提案沿用；`NSCondition` 等待占住执行器线程是那里记录的契约）、[0001-symbol-name-offsetization](0001-symbol-name-offsetization.md) / [0003-symbol-row-bucket-flattening](0003-symbol-row-bucket-flattening.md)（本提案不碰各 `Storage` 的内容，那两份提案定下的存储模型原样保留）
- **实现分支 / PR**: 待定
- **配套文档**: 待定 —— 落地时新建 `Internal/Modules/MachOCaches.md`（模块文档，今天在模块索引里是「待写」），并在此登记

## 摘要

`SharedCache<Storage>` 是本包所有「按镜像缓存」的基类：键是镜像的 identifier（文件取 `LC_UUID` 加路径，进程内镜像取基址），值是那个镜像的某种一次性建好的索引（符号表、interned 名字池、ObjC 方法表……）。今天有 11 个子类单例、4 个裸实例，另有 3 个手写的同形 Store。它的并发核心（同一镜像的并发构建只建一次、构建在锁外跑）是 2026-05 修过的，是对的，本提案不动。要改的是它周围的四件事：每个实例各自监听内存压力并 `removeAll()`，绕过了「最后一个 indexer 才驱逐」的规则，而且清掉的存储被活引用钉着，回收不到内存；基类的 `buildStorage(for: some MachORepresentableWithCache)` 签名把读者类型擦成了最弱的协议，6 个子类只好在 override 里 `as? MachOFile / as? MachOImage` 再分派一遍，漏写 override 也不报错；每次查找都把 identifier 装箱成 `AnyHashable`（一次堆分配）并对整条路径字符串做哈希，而这个查找发生在按符号、按 mangled name 的循环里；同线程对同一个键重入构建会静默死锁，代码注释还以为它会 trap。

改法：`SharedCache` 改成不可继承的组合式原语，构建闭包在调用点给；键换成只哈希 UUID 或指针的具体类型；驱逐收口到一个下沉至 `MachOCaches` 的注册表，每个 cache 声明自己属于哪个 eviction group，indexer 的 deinit 从逐个点名 8 处 remove 变成一句话，内存压力监听整个去掉、改为暴露一个宿主显式调用的 API；promise 记下构建线程，重入变成带信息的崩溃。两个手写 Store 并入原语，第三个（弱引用注册）只换键类型。名字暂时都不改。

## 动机

### 内存压力驱逐绕过了所有权规则，且没有测试

`Sources/MachOCaches/SharedCache.swift:9-20`：每个 `SharedCache` 实例在 `init` 里创建一个 `MemoryPressureMonitor`（`Sources/Utilities/MemoryPressureMonitor.swift`，一个 `DispatchSourceMemoryPressure` 加一条队列，全库只有这一个用户），warning 与 critical 都直接 `storageByIdentifier.removeAll()`。15 个实例就是 15 个监听源，各自独立触发。它和 `PerImageCacheEvictionRegistry`（`Sources/SwiftIndexing/SwiftDeclarationIndexer.swift:1492` 起，private）是两套互不知情的驱逐：注册表的规则是「按镜像认领，最后一个活着的 indexer 走了才驱逐」，正是 PR #103 review 的 M6 修出来的，因为提前抽走 interned store 会让幸存 indexer 已建好的名字留在孤儿 store 里、新名字落进新 store，`store ===` 快速路径从此分裂；内存压力这条路完全不看认领，直接清空。

清了也回收不到多少：`Sources/MachOSymbols/InternedNodeReferenceCache.swift:40-43` 自己写明「Eviction reclaims nothing while external references survive」，声明模型里每个 `NodeReference` 都指着 store 的缓冲区，store 不会因为字典丢了引用就释放；`SymbolIndexStore.Storage` 同理被 `DemangledSymbol` 钉住。付出的代价倒是实打实的：符号表被清后，下一次 `demangledNodeReference` 重建十几万行。`Tests/` 下没有任何测试覆盖这条路径（`grep memoryWarningHandler Tests` 为空）。

### 继承式 `buildStorage` 是错的抽象层

`SharedCache.swift:44-46` 的 `open func buildStorage(for machO: some MachORepresentableWithCache) -> Storage? { nil }`。`MachORepresentableWithCache` 没有 `swift` 段、也不是 `Readable`，而所有索引都要读描述符，所以 6 个子类在 override 里先 `as? MachOFile`、再 `as? MachOImage`、都不是就返回 nil（`ObjCClassMethodIndex.swift:114-121`、`SymbolicManglingIndex.swift:180-187`、`ObjCImplementationClassIndex.swift:65-71`、`AnonymousContextPrivateDiscriminatorIndex.swift:57-64`、`SwiftClassObjectIndex.swift:81-88`、`MultiPayloadEnumDescriptorCache.swift:41-42`，共 11 处 `as?`）。而它们各自的 `build(in:)` 本来就是泛型的：`some MachOSwiftSectionRepresentableWithCache` 或 `some ObjCImplementationClassReading`（`SwiftClassObjectIndex.swift:122`、`SymbolicManglingIndex.swift:258`、`AnonymousContextPrivateDiscriminatorIndex.swift:85`、`ObjCClassMethodIndex.swift:422`、`ObjCImplementationClassIndex.swift:186`）。这套分派存在的唯一原因是基类签名把调用点明明知道的类型擦掉了。默认实现返回 nil 还有个副作用：`nil` 不缓存（`resolve` 的注释写明是为了失败可重试），漏写 override 的子类不会报错，只会每次都静默重建。

### 三个手写 Store 重复了同一件事，其中两个把锁内构建又写了回来

`PropertyWrapperTypeCatalogStore`（`Sources/SwiftDeclarationRendering/PropertyWrapperTypeCatalog.swift:188-232`）、`ObjCAncestorResolverStore`（`Sources/SwiftInspection/ObjCAncestorResolver.swift:168-215`）、`ObjCClassHierarchyProviderStore`（`Sources/SwiftInspection/ObjCClassHierarchy.swift:180-215`）各自一把 `NSLock` 加一个 `[AnyHashable: …]`，键控、`contains`、`remove` 与 `SharedCache` 逐字相同，多出来的只是 `register(_:for:)` 覆盖安装。前两个的按需构建（`catalog(for:)`、`resolver(for:)`）在锁内调 `make(...)` / `ObjCAncestorResolver(root:searchPaths:)`，这会走依赖闭包去磁盘找文件。这正是 2026-04 `KNOWN_ISSUES.md`（commit `7b007bb4`）记录、2026-05 commit `aeed3735` 用 in-flight promise 从 `SharedCache` 里修掉的问题：一个镜像在建，所有镜像的查询都排在后面。

### 每次查找的键成本偏高，而查找发生在热循环里

一次 `storage(in:)`（`SharedCache.swift:69-75`）的路径：`machO.identifier`（`MachOFile` 走 `@AssociatedObject` 的 objc 关联对象查表，`../MachOKitExtensions/Sources/MachOKitExtensions/MachORepresentableWithCache.swift:52-76`）→ 装箱成 `AnyHashable`（`.uuidFile(path:uuid:)` 的载荷是一个 `String` 加一个 `UUID`，超过 existential 的 24 字节内联缓冲，每次一次堆分配）→ `Hasher` 吃整条路径字符串再吃 UUID → `os_unfair_lock` → 字典探测 → 命中时再比一次路径。全库有 15 处 `AnyHashable(machO.identifier)` 形态的装箱点。调用密度：`SymbolIndexStore.swift` 里 31 处 `storage(in:)`，其中 `demangledNodeReference`（`:1265-1266`）每查一个符号一次；`SymbolicDemangler.swift` 14 处，`SymbolicDemanglerCache.demangleType` 的未命中路径调两次（`:876-884`，一次查、一次写）。占比未测量，见「前期调研」的推测项。

### 同线程重入是静默死锁

`SharedCache.swift:156-200` 的 `resolve`：构建者装好 `.inFlight(promise)` 后在锁外跑 `build()`；若 `build()` 里同一线程再对同一个键调 `storage(in:)`，会拿到 `.wait(promise)`，在 `NSCondition` 上等一个只有自己返回后才会 fulfill 的 promise，永远不回来。`SymbolicDemangler.swift:134-140` 的注释描述的还是锁内构建时代的行为（「the re-entrant `storage()` lookup traps」），那时至少有崩溃日志，现在什么都没有。`Tests/MachOCachesTests/SharedCacheTests.swift` 的 `buildClosureMayResolveOtherKey` 只覆盖不同键的重入。

### 命名与文档失真

`CLAUDE.md:67` 把 `MachOCaches` 描述成「dyld shared cache support」，而该模块目录里只有 `SharedCache.swift` 与 `SharedCacheBuildPromise.swift`，dyld cache 的支持在 `MachOKitExtensions` 与 `MachODependencies`；`Documentations/Internal/Modules/README.md:37` 里它是「待写」。用户已决定本批不改名（类名 `SharedCache`、模块名 `MachOCaches` 保留，候选名另议），但文档失真要修。

## 前期调研

- **实例清单（2026-09-28 grep）**。子类 11 个：`SymbolIndexStore`（`Sources/MachOSymbols/SymbolIndexStore.swift:17`，public，`@_spi(ForSymbolViewer)`，另经 `DependencyKey` 注入，`liveValue` 与 `testValue` 都是 `.shared`，`:1363-1366`）、`InternedNodeReferenceCache`（`:46`，public，`@_spi(ForSymbolViewer)`，按镜像与按进程双入口）、`SymbolicDemanglerCache`（`Sources/SwiftInspection/SymbolicDemangler.swift:834`，private，双入口）、`AnonymousContextPrivateDiscriminatorIndex`（`:40`）、`ObjCImplementationClassIndex`（`:37`）、`SwiftClassObjectIndex`（`:49`）、`ObjCClassMethodIndex`（`:44`）、`SymbolicManglingIndex`（`:112`）（以上 package）、`MultiPayloadEnumDescriptorCache`（`Sources/SwiftDeclarationRendering/MultiPayloadEnumDescriptorCache.swift:29`，internal）。裸实例 4 个：`DependentMemberProjection.fileRegistries` / `imageEntries`（`DependentMemberProjection.swift:70-71`）、`MetadataAccessorIndex.cache`（`Sources/SwiftThunkAnalysis/Resolution/MetadataAccessorIndex.swift:36`）、`DependencyImageResolver.cache`（`DependencyImageResolver.swift:54`）。手写 Store 3 个，见动机。
- **谁在驱逐**。indexer 的 `deinit`（`SwiftDeclarationIndexer.swift:178-230`）按五个认领位逐个调用：`symbolStore` 位驱逐 `SymbolIndexStore`、`SymbolicManglingIndex`、`ObjCImplementationClasses.removeCache`（`ObjCImplementationClassIndex.swift:329`）、`ObjCClassHierarchies.removeCache`（`ObjCClassHierarchy.swift:224-229`，内含 `ObjCClassMethodIndex`、`SwiftClassObjectIndex`、`ObjCClassHierarchyProviderStore`、`ObjCAncestorResolverStore`）；`propertyWrapperCatalog`、`objcAncestorResolver`、`internedNames` 各驱逐自己那一个；`demangleMemo` 位调 `SymbolicDemangler.removeCache`（`SymbolicDemangler.swift:80-84`，内含 `SymbolicDemanglerCache` 与 `AnonymousContextPrivateDiscriminatorIndex`）。`Claims.normalized` 强制 `internedNames ⇒ demangleMemo`。认领在 `prepare()` 里按「当时缺席的就是我要建的」采样（`:369-382`）。`MultiPayloadEnumDescriptorCache`、`DependentMemberProjection` 的两个、`MetadataAccessorIndex`、`DependencyImageResolver` 这 5 个今天没有任何按镜像驱逐，只有内存压力那条路会清它们；其中 `DependencyImageResolver` 与 `DependentMemberProjection` 持有依赖镜像的 `MachOFile` 句柄和整个 `ImageUniverse`，不是小东西。
- **键的实际类型**。`MachORepresentableWithCache` 的 conformer 全世界只有 `MachOFile` 与 `MachOImage`（2026-09-28 grep 本仓库、`MachOKitExtensions`、`MachOObjCSection`、`RuntimeViewer`），`Identifier` 都是 `MachOTargetIdentifier`（`.image(UnsafeRawPointer)` / `.file(String)` / `.uuidFile(path:uuid:)` / `.versionedFile(path:platform:sdk:)`）。UUID 由链接器按构建唯一分配，`.uuidFile` 的 UUID 单独就足以区分镜像，路径只在等值比较时需要。
- **下游没有直接用它**。`RuntimeViewer` 全仓 grep 无 `SharedCache`、`.storage(in:`、`remove(for:`、`prepareWithProgress`、`removeCache(for:`；它经 `SwiftDeclarationIndexer` 与 `SymbolIndexStore` 的实例 API 间接使用。`SymbolIndexStore` 与 `InternedNodeReferenceCache` 带 `@_spi(ForSymbolViewer)`，实例 API 的形状要保住。
- **测试现状**。`Tests/MachOCachesTests/SharedCacheTests.swift` 覆盖单线程语义、同键去重、异键并行、异键重入、取消不污染缓存；其中 `differentKeysParallelViaTaskGroup` 与 `differentKeysParallelViaAsyncLet` 用墙钟断言并行度，全量并发跑时假失败，已多次记入任务报告（2026-08-14、2026-08-27）；同文件的 `concurrentCallsForDifferentKeysRunInParallel` 已改成信号量栅栏的确定性形态，是现成范例。`Tests/SwiftIndexingTests/PerImageCacheEvictionTests.swift` 是注册表规则的端到端 pin（最后一个 indexer 才驱逐、按 cache 单独认领、memo 随 store 走）。CI 的 filter（`.github/workflows/macOS.yml:120`）不含 `MachOCachesTests` 里的 `SharedCache` 套件。
- **前人裁决**。`KNOWN_ISSUES.md`（commit `7b007bb4`，2026-04-16）记录「build 在全局锁内」，commit `aeed3735`（2026-05-07）用 in-flight promise 修掉，`2fbd7d2e` 删除该文件；提案 0019 的「未来方向」明确写「`SharedCache` / `SymbolIndexStore` 的 async 建表路径（2026-09-03 评估收益小，不做）」；`Documentations/Internal/ReviewAdjudications.md` 有一条与 `SharedCache` 以镜像基址为键相关的裁决（镜像卸载后同址重载），结论是 Darwin 上含 Swift 内容的镜像永不卸载，本提案不改键的语义，那条裁决继续成立。
- **第三方库评估（2026-09-28）**。用户提出 [hyperoslo/Cache](https://github.com/hyperoslo/Cache)（7.4.0，2024-08；最后提交 2025-08；`swift-tools-version:5.5`，`swiftLanguageVersions: [.v5]`，无 Sendable）。读源码后否决：没有 get-or-build 也没有在途去重，promise 仍要自己写；内存层是 `NSCache`，会在注册表不知情时自行丢对象，旁边还维护一个不加锁的 `Set<Key>`；线程安全靠 `SyncStorage` 的 `serialQueue.sync`，每个读一次队列跳转，键包成 `WrappedKey: NSObject`、值包成 `MemoryCapsule`，分配比今天更多；带锁的 `Storage` 只能从 `DiskConfig` 加 `Transformer<Value>` 构造，而我们的 Storage 本质不可序列化。详见决策日志。
- **推测（未验证）**：键成本在整机时间里的占比。结构上每次查找在百纳秒量级、调用次数在十万到百万量级，估计总量在零点几秒以内，但没有 Instruments 数据。本提案把键做便宜是顺手的（改动小、正确性不变），是否值得进一步做「句柄」API 由落地后的测量决定，见「非目标」。

## 提议方案

1. **去继承**：`SharedCache<Storage>` 改为 `final class`，唯一的 get-or-build 是 `storage(in:buildUsing:)`，构建闭包在调用点给，调用点的 `MachO` 类型完整可用；删除 `open buildStorage(for:)`、`buildStorage()`、`storage()`、`contains()`、`remove()` 五个类型键变体。11 个子类改为持有 `private let cache = SharedCache<Storage>(evictionGroup: …)`，保留各自的 `static let shared` 与实例查询方法，调用点不动。两个进程作用域用户（`InternedNodeReferenceCache`、`SymbolicDemanglerCache`）改为各自一个 `private static let processScopedStorage = Storage()`。`PropertyWrapperTypeCatalogStore` 与 `ObjCAncestorResolverStore` 改为 `SharedCache` 的薄包装，`register(_:for:)` 由新增的 `SharedCache.register(_:for:)` 提供；`ObjCClassHierarchyProviderStore` 是弱引用注册，不并，只换键类型。
2. **键去装箱**：新增 `SharedCacheKey`，从 `MachORepresentableWithCache` 的 `identifier` 构造；对 `MachOTargetIdentifier` 只把 UUID（`.uuidFile`）或指针（`.image`）喂给 hasher，等值比较仍比完整值；非 `MachOTargetIdentifier` 的 identifier 走 `AnyHashable` 兜底（今天没有这样的 conformer）。`SharedCache`、三个 Store、注册表统一用它。
3. **驱逐收口**：`PerImageCacheEvictionRegistry` 从 `SwiftIndexing` 下沉到 `MachOCaches`，成为 `SharedCacheRegistry`；每个 `SharedCache` 在 `init` 时带一个 `SharedCacheEvictionGroup` 自动登记；五个认领位推广为 `Set<SharedCacheEvictionGroup>`，今天由 `deinit` 与三个 `removeCache` 助手拼出来的「认领一个位、连带清哪些」关系写成注册表里的一张 `dependents` 表；indexer 的 `deinit` 变成一句 `deregisterLiveOwner`。删除 `MemoryPressureMonitor` 与每实例监听；新增 `SharedCacheRegistry.shared.evictImagesWithoutLiveOwners()` 供宿主自行接内存压力。今天没有按镜像驱逐的 5 个 cache 各得一个 group，随镜像的最后一个 owner 一起走。
4. **重入保护与测试整改**：`SharedCacheBuildPromise` 记下构建线程；`resolve` 进入等待分支前若发现等的是自己线程正在建的 promise，`preconditionFailure` 带镜像键。两个墙钟测试改成信号量栅栏。注册表的规则测试搬到 `MachOCachesTests`，并把这些套件加进 CI filter。
5. **文档**：新建 `Internal/Modules/MachOCaches.md`；修 `CLAUDE.md:67` 与模块索引；术语表登记 eviction group、claim、live owner；`ProjectEvolutionLog` 加节。

### 非目标

- **不改名**：`SharedCache`、`SharedCacheBuildPromise`、模块 `MachOCaches` 与其测试 target 名保留。用户对已提的候选名不满意，改名另起讨论；文档里先把「它不是 dyld shared cache」说清。
- **不做「句柄」API**：把 `storage(in:)` 从 `SymbolIndexStore` 按符号的查询循环里提出去、改成先取一个绑定了 `Storage` 的句柄再逐个查，这会动 `SymbolIndexStore` 的公开面（`@_spi(ForSymbolViewer)`），本批不做，落地后用 Instruments 量 `dump` SwiftUI 里键查找的占比再决定是否另起提案。
- **不做 async 建表**：沿用 0019 的裁决，`SharedCacheBuildPromise` 仍是 `NSCondition` 同步等待。
- **不碰各 `Storage` 的内容**：`SymbolIndexStore.Storage`、`ObjCClassMethodIndex.Storage` 等的字段、内部锁、`NodeStore` 持有形态一律不动。
- **不改 `MachOKitExtensions`**：`identifier` 的 `@AssociatedObject` 记忆与 `associatedtype Identifier` 保留；把 `Identifier` 收窄为具体类型是 sibling 的后续事项（且 sibling 目前不能带本地依赖构建，见记忆）。
- **不做「hop 后的重入」检测**：`SymbolIndexStore` 的构建经 `StackSafeExecutor.withLargeStack` 跳到 8 MB 工作线程，那上面再对同键重入不会被线程比对抓到。这一层只能抓同线程重入，其余在注释里写明。

## 详细设计

### `SharedCacheKey`

```swift
public struct SharedCacheKey: Hashable, Sendable {
    private enum Representation: Hashable {
        case target(MachOTargetIdentifier)
        case other(AnyHashable)
    }

    private let representation: Representation

    public init(_ machO: some MachORepresentableWithCache) {
        if let targetIdentifier = machO.identifier as? MachOTargetIdentifier {
            representation = .target(targetIdentifier)
        } else {
            representation = .other(AnyHashable(machO.identifier))
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch representation {
        case .target(.uuidFile(_, let uuid)):
            hasher.combine(0 as UInt8)
            hasher.combine(uuid)
        case .target(.image(let pointer)):
            hasher.combine(1 as UInt8)
            hasher.combine(pointer)
        case .target(let identifier):
            hasher.combine(2 as UInt8)
            hasher.combine(identifier)
        case .other(let identifier):
            hasher.combine(3 as UInt8)
            hasher.combine(identifier)
        }
    }

    // `==` 用合成实现：比完整的 representation，路径参与比较，只是不参与哈希。
}
```

`as?` 到具体枚举是一次元数据比较，不分配。`.versionedFile` 与 `.file` 仍哈希路径，它们只出现在没有 `LC_UUID` 的二进制上。

### `SharedCache`

```swift
public final class SharedCache<Storage>: @unchecked Sendable {
    public init(evictionGroup: SharedCacheEvictionGroup)

    /// 原子的 get-or-build。命中直接返回；有人在建就等它；否则装上 in-flight 标记、在锁外跑 `build`。
    /// `build` 返回 `nil` 不缓存，下一次重试（沿用今天的语义）。
    public func storage<MachO: MachORepresentableWithCache>(
        in machO: MachO,
        buildUsing build: (MachO) -> Storage?
    ) -> Storage?

    /// 覆盖安装：替换已完成的条目；对在途构建不生效，构建者回来发现标记不是自己的就不写回。
    public func register(_ storage: Storage, for machO: some MachORepresentableWithCache)

    public func contains(in machO: some MachORepresentableWithCache) -> Bool
    public func remove(for machO: some MachORepresentableWithCache)
    public func removeAll()

    /// 测试入口，与今天相同。
    package func resolve(key: SharedCacheKey, build: () -> Storage?) -> Storage?
}
```

`Entry` / `Outcome` / `resolve` 的三段式（锁内查、锁外建、锁内写回且只在标记仍是自己时写回）原样保留。`register` 在锁内把 `.completed(storage)` 写进字典；若当前是 `.inFlight`，同样覆盖为 `.completed`，在途构建者回来时标记已不是它的 promise，不写回但照常 fulfill 等待者。这与今天 `remove` 遇到在途条目的处理一致。

子类迁移的固定形状（以 `ObjCClassMethodIndex` 为例，其余同形）：

```swift
package final class ObjCClassMethodIndex: @unchecked Sendable {
    package static let shared = ObjCClassMethodIndex()

    private let cache = SharedCache<Storage>(evictionGroup: .objcHierarchy)

    private func storage(in machO: some ObjCImplementationClassReading) -> Storage? {
        cache.storage(in: machO) { Self.build(in: $0) }
    }

    package func remove(for machO: some MachORepresentableWithCache) {
        cache.remove(for: machO)
    }
}
```

`SymbolIndexStore` 的 `prepareWithProgress` 今天已经用 `storage(in:buildUsing:)` 传 progress continuation，形状不变；`buildStorage(for:)` 变成 `storage(in:)` 的默认闭包。`InternedNodeReferenceCache.reference(interning:)`（进程作用域）改读 `static let processScopedStorage`，`SymbolicDemanglerCache` 的三个进程作用域字典同理。`DependentMemberProjection` 的两个裸实例、`MetadataAccessorIndex.cache`、`DependencyImageResolver.cache` 只加 `evictionGroup:` 参数。

`PropertyWrapperTypeCatalogStore` 迁移后：

```swift
public final class PropertyWrapperTypeCatalogStore: @unchecked Sendable {
    public static let shared = PropertyWrapperTypeCatalogStore()
    private let cache = SharedCache<PropertyWrapperTypeCatalog>(evictionGroup: .propertyWrapperCatalog)

    public func register(_ catalog: PropertyWrapperTypeCatalog, for machO: some MachORepresentableWithCache) {
        cache.register(catalog, for: machO)
    }

    public func catalog(for machO: some MachORepresentableWithCache) -> PropertyWrapperTypeCatalog {
        cache.storage(in: machO) { PropertyWrapperTypeCatalog.make(root: $0, searchPaths: [.systemDyldSharedCache]) }!
    }
}
```

默认构建从此在锁外跑；同一镜像的并发首次查询共用一次构建。`ObjCAncestorResolverStore` 同形，它的两个按读者类型的默认构建（文件走 `ObjCAncestorResolver(root:searchPaths:)`，进程内镜像走 `ObjCAncestorResolver(inProcessRoot:)`）保留为两个 `resolver(for:)` 重载里的闭包。

### `SharedCacheEvictionGroup` 与 `SharedCacheRegistry`

```swift
public enum SharedCacheEvictionGroup: Hashable, CaseIterable, Sendable {
    case symbolStore              // SymbolIndexStore
    case symbolicMangling         // SymbolicManglingIndex
    case objcImplementationClasses
    case objcHierarchy            // ObjCClassMethodIndex、SwiftClassObjectIndex、ObjCClassHierarchyProviderStore
    case objcAncestorResolver
    case internedNames            // InternedNodeReferenceCache
    case demangleMemo             // SymbolicDemanglerCache、AnonymousContextPrivateDiscriminatorIndex
    case propertyWrapperCatalog
    case multiPayloadEnumDescriptors
    case dependentMemberProjection
    case thunkResolution          // MetadataAccessorIndex、DependencyImageResolver

    /// 认领了 `self` 就连带驱逐的 group。今天散在 indexer deinit 与三个 removeCache 助手里的关系，原样搬进来：
    /// `.symbolStore` → `[.symbolicMangling, .objcImplementationClasses, .objcHierarchy, .objcAncestorResolver]`
    /// `.internedNames` → `[.demangleMemo]`（原 `Claims.normalized`）
    /// 其余 → `[]`
    var dependents: Set<SharedCacheEvictionGroup>
}

public final class SharedCacheRegistry: @unchecked Sendable {
    public static let shared = SharedCacheRegistry()

    /// `SharedCache.init` 调用；注册表持弱引用，cache 都是 static let，实际不会死。
    func register(_ cache: any SharedCacheEvicting, group: SharedCacheEvictionGroup)

    /// 首次登记时在锁内采样认领；重复登记不再采样（沿用今天的幂等规则）。
    public func registerLiveOwner(
        _ owner: ObjectIdentifier,
        for key: SharedCacheKey,
        samplingClaims: () -> Set<SharedCacheEvictionGroup>
    )

    /// 最后一个 owner 注销时，驱逐它们合并认领的 group 及其 dependents。
    public func deregisterLiveOwner(_ owner: ObjectIdentifier, for key: SharedCacheKey)

    public func evict(groups: Set<SharedCacheEvictionGroup>, for key: SharedCacheKey)
    public func hasLiveOwners(for key: SharedCacheKey) -> Bool

    /// 宿主接内存压力用：所有出现在任一 cache 里、且没有活 owner 的镜像，全部 group 一起驱逐。
    /// 只驱逐没人认领的，正在被索引的镜像不受影响；被非 indexer 消费者临时填充的镜像会被清，这是宿主显式调用的后果，文档写明。
    public func evictImagesWithoutLiveOwners()
}
```

`SwiftDeclarationIndexer.prepare()` 的认领采样改为对 `SharedCacheEvictionGroup.allCases` 逐个问 `contains(in:)`、缺席的即认领；`deinit` 改为一句 `SharedCacheRegistry.shared.deregisterLiveOwner(ObjectIdentifier(self), for: SharedCacheKey(machO))`。`ObjCClassHierarchies.removeCache`、`ObjCImplementationClasses.removeCache`、`SymbolicDemangler.removeCache` 三个公开助手保留为 `evict(groups:for:)` 的转发，测试与外部调用不需要改。

### 重入保护

```swift
public final class SharedCacheBuildPromise<Value>: @unchecked Sendable {
    private let builderThread: pthread_t = pthread_self()
    var isBuilderCurrentThread: Bool { pthread_equal(builderThread, pthread_self()) != 0 }
}
```

`resolve` 的 `.wait(promise)` 分支先 `precondition(!promise.isBuilderCurrentThread, "SharedCache: re-entrant build for \(key) on the builder's own thread; the build closure must not query the cache it is building")`。测试用 Swift Testing 的退出测试（`#expect(processExitsWith: .failure)`，Swift 6.2 起可用）pin 住。

### 测试

- `MachOCachesTests/SharedCacheKeyTests`：同 UUID 不同路径的两个键哈希相等、等值不等；`.image` 键按指针；`.file` 与 `.versionedFile` 按完整值。
- `MachOCachesTests/SharedCacheRegistryTests`：认领合并、`dependents` 展开、最后一个 owner 才驱逐、重复登记不重复采样、`evictImagesWithoutLiveOwners` 只清无 owner 的键、`register` 覆盖在途构建后构建者不写回。这些今天只能经 `PerImageCacheEvictionTests` 端到端测。
- `SharedCacheResolveTests`：加同键重入的退出测试；`differentKeysParallelViaTaskGroup` / `differentKeysParallelViaAsyncLet` 改成「每个 build 阻塞到全部 build 进入闭包」的栅栏形态，不再看墙钟。
- `PerImageCacheEvictionTests` 原样保留，作为端到端 pin；新增一条：`MultiPayloadEnumDescriptorCache` 与 `DependencyImageResolver` 这类原本不驱逐的 cache 现在随最后一个 indexer 走。
- 源码扫描：`Sources/` 下不再出现 `MemoryPressureMonitor` 与 `DispatchSource.makeMemoryPressureSource`。
- CI filter 加 `SharedCacheKeyTests|SharedCacheRegistryTests|SharedCacheResolveTests`。

## 替代方案考量

- **引入 hyperoslo/Cache**。见「前期调研」。它解决「Codable 值的内存加磁盘持久化与过期」，我们要的「一个镜像一份惰性建好、在途去重、按所有权驱逐、在锁外构建的对象」它一样都没有，其内存层还是会自行丢对象的 `NSCache`。否决。
- **只加一层「句柄」而不动其余**。键成本可以靠把查找提出循环解决，但内存压力绕过所有权、锁内构建的 Store、静默死锁三件事与键无关，句柄解决不了；而且句柄要动 `SymbolIndexStore` 的公开面，本批不做。
- **保留继承，只把 `buildStorage(for:)` 的参数改成 `some MachOSwiftSectionRepresentableWithCache`**。`MachOCaches` 在 `MachOSwiftSection` 之下，看不见那个协议；而且 `ObjCClassMethodIndex` 等要的是 `ObjCImplementationClassReading`，一个签名满足不了所有子类。把类型留给调用点是唯一不引入错误依赖方向的做法。
- **把 `MachORepresentableWithCache.Identifier` 收窄为 `MachOTargetIdentifier`，直接用它做键**。这是最干净的，但协议在 `MachOKitExtensions`，sibling 改动不在本批范围，且要给每个泛型签名加 `where MachO.Identifier == MachOTargetIdentifier`。`SharedCacheKey` 用一次 `as?` 得到同样的效果，代价是每次查找多一次元数据比较，可忽略。
- **内存压力改为注册表级自动响应，只清没有活 owner 的镜像**。用户已选「彻底去掉、暴露显式 API」：库不替宿主做生命周期决定；非 indexer 消费者填充的镜像没有 owner 概念，自动清仍有抽走存储的窗口，由宿主决定何时可以清更诚实。`evictImagesWithoutLiveOwners()` 保留了这条路的能力。
- **process 作用域也保留在 `SharedCache` 里**。只有两个用户，键是 `ObjectIdentifier(Self.self)` 这种凑数的常量；`static let` 已经是惰性且线程安全的单例，不需要经过按镜像的字典。代价是这两个进程作用域存储从此不可驱逐（今天只有内存压力会清它们），它们的大小由进程实际碰到的唯一名字数决定，可接受。

## 影响

### 源码兼容性（source compatibility）

**有破坏**，全部在 `@_spi(Internals)` 面上，仓库内迁移，已知下游无调用点（2026-09-28 grep `RuntimeViewer`）：

- `SharedCache` 不再 `open`，删除 `buildStorage(for:)`、`buildStorage()`、`storage()`、`contains()`、`remove()`；`init()` 改为 `init(evictionGroup:)`。改前 `final class Foo: SharedCache<Foo.Storage> { override func buildStorage(for:) }`，改后 `final class Foo { private let cache = SharedCache<Storage>(evictionGroup: …) }`。
- `SymbolIndexStore`、`InternedNodeReferenceCache`（`@_spi(ForSymbolViewer)`）不再是 `SharedCache` 的子类，但 `storage(in:)`、`contains(in:)`、`remove(for:)`、`prepare(in:)`、`prepareWithProgress(in:)`、`reference(interning:in:)`、`reference(interning:)` 签名不变；以 `SharedCache<…>` 拼写它们类型的调用方会断，已知没有。
- `PropertyWrapperTypeCatalogStore`、`ObjCAncestorResolverStore`、`ObjCClassHierarchyProviderStore` 的 public API 不变。
- `MemoryPressureMonitor`（package，`Utilities`）删除。
- **行为变化**：库不再在内存压力下自动清缓存。宿主要这个行为就调用 `SharedCacheRegistry.shared.evictImagesWithoutLiveOwners()`。RuntimeViewer 没有显式依赖它，但落地后要在其 release note 里提一句。

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

仓库内：`MachOCaches`、`Utilities`、`MachOSymbols`、`SwiftInspection`、`SwiftDeclarationRendering`、`SwiftThunkAnalysis`、`SwiftIndexing`，以及 `MachOCachesTests`、`SwiftIndexingTests`、CI 的 filter。

仓库外：`RuntimeViewer` 只有上述行为变化；`SymbolViewer` 经 `@_spi(ForSymbolViewer)` 用 `SymbolIndexStore`，实例 API 保住即不受影响，落地前用它的仓库再 grep 一次确认。

### 文档与示例

- 新建 `Documentations/Internal/Modules/MachOCaches.md`：它是什么、不是什么（不是 dyld shared cache）、键的哈希规则、eviction group 与 dependents 表、认领与 live owner、宿主接内存压力的方式、同线程重入的限制。
- `CLAUDE.md:67` 改写模块描述；`Documentations/Internal/Modules/README.md:37` 改为已写；`Documentations/README.md` 登记模块文档。
- `Documentations/Glossary.md` 登记 eviction group、claim（认领）、live owner。
- `Documentations/Internal/ProjectEvolutionLog.md` 加节。
- 本提案落地时状态改 `Implemented`、登记配套文档。

## API 演进与废弃策略

- 删除的成员全在 `@_spi(Internals)` 面上，不设废弃期，直接删除；`SharedCache.init()` 无参形式同样直接删除。
- 保留的公开助手（`ObjCClassHierarchies.removeCache` 等）改为注册表转发，不废弃。
- 不需要 semver major 跃迁：公开面无破坏，SPI 面按仓库惯例随版本变动。

## 落地步骤

1. **重入保护与测试整改**（只动 `MachOCaches` 与 `MachOCachesTests`）：promise 记线程、`resolve` 加 precondition、退出测试、两个墙钟测试改栅栏。单独可构建、可验证。
2. **`SharedCacheKey`**：替换 `SharedCache`、三个 Store、`PerImageCacheEvictionRegistry` 里的 `AnyHashable` 键，加 `SharedCacheKeyTests`。行为不变，全量测试应零变化。
3. **去继承**：`SharedCache` 改 `final`、加 `register`、删五个类型键变体；11 个子类与 4 个裸实例迁移；两个进程作用域改 `static let`；两个 Store 并入。此步改了 `MachOSymbols` 的公开类型形状，按 AGENTS.md 先 `swift package clean`。
4. **注册表下沉**：`SharedCacheEvictionGroup`、`SharedCacheRegistry` 落到 `MachOCaches`，indexer 的采样与 `deinit` 改一句，三个 `removeCache` 助手改转发，删 `MemoryPressureMonitor`，加 `SharedCacheRegistryTests`，CI filter 加套件。`PerImageCacheEvictionTests` 必须原样通过。
5. **文档**：模块文档、`CLAUDE.md`、模块索引、术语表、演进账本、本提案状态与配套文档登记。
6. **验证**：全量 `swift test --skip IntegrationTests`；渲染 A/B（改了索引与 reader stack 之下的键控，按 AGENTS.md 必跑）；顺手用 Instruments 量一次 `dump` SwiftUI 里 `SharedCache.storage(in:)` 的占比，作为句柄 API 是否立项的输入，数字记进任务报告。

收尾判断：配套文档要写（模块文档，判据是「eviction group 的 dependents 关系与 live owner 规则从签名看不出来、违反了会静默泄漏或分裂 store」）；新术语三个（eviction group、claim、live owner），同批登记。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-09-28 | Created as Draft | 用户要求「看看 SharedCache 怎么优化，包括 API 设计和性能」。读码结论：并发核心不动，改内存压力驱逐、继承签名、键装箱、重入检测四件事。 |
| 2026-09-28 | 内存压力驱逐：彻底去掉，改显式 API | 用户裁决。理由：库不替宿主做生命周期决定；今天的自动清空绕过认领规则且回收不到被钉住的存储。注册表暴露 `evictImagesWithoutLiveOwners()`。 |
| 2026-09-28 | 句柄 API 不进本批 | 用户裁决。键做便宜后先测量占比，显著再另起提案；避免没有数字就动 `SymbolIndexStore` 的 `@_spi(ForSymbolViewer)` 公开面。 |
| 2026-09-28 | 暂不改名 | 用户对候选名（`ImageKeyedCache` / `PerImageCache` / `MachOImageCaching` 等）不满意，类名与模块名本批保留，另议。 |
| 2026-09-28 | 否决引入 hyperoslo/Cache | 用户提出、读源码后否决：无 get-or-build 与在途去重、内存层是自行丢对象的 `NSCache`、每次访问一次串行队列跳转、带锁入口必须带磁盘配置与 `Transformer`、Swift 5 模式无 Sendable。换掉的只是最简单的锁加字典，promise、注册表、认领照写。 |
| 2026-09-28 | 沿用 0019：不做 async 建表 | 已有裁决（2026-09-03 评估收益小），不重开。 |
| 2026-09-28 | Draft → Accepted → In Progress | 用户「开工」批准；按落地步骤 1 起实现。 |
