# MachOCaches 模块

> 模块参考文档（module reference），随代码维护。读者：维护者。
> 提案：[0053-shared-cache-composition-and-eviction-registry](../../Evolutions/0053-shared-cache-composition-and-eviction-registry.md)。

## 模块定位

先说它不是什么：MachOCaches **不是 dyld shared cache 的支持层**。dyld cache 的读取在 `MachOKitExtensions`（`DyldCache` 的镜像查找、进程内镜像是否在 cache 里），按 cache 找依赖镜像在 `MachODependencies`。这个模块名字里的 cache 是「缓存」，撞名是历史遗留，本批未改（提案决策日志有记录）。

它回答一个问题：**一个镜像的某种一次性建好的索引放在哪、谁建、谁清。** 符号表（`SymbolIndexStore`）、interned 名字池（`InternedNodeReferenceCache`）、ObjC 方法表（`ObjCClassMethodIndex`）、`_symbolic` 符号索引（`SymbolicManglingIndex`）……每一种都是「按镜像算一次、之后人人共享」的东西，它们的持有者各在自己的模块里，共用的机制在这里：

- `SharedCache<Storage>`：按镜像的 get-or-build。同一镜像的并发首次访问只建一次，构建在锁外跑。
- `SharedCacheKey`：镜像的键，只哈希 UUID（从 dyld cache 读出的镜像再加上所在 cache 的 UUID）或基址。
- `SharedCacheRegistry` + `SharedCacheEvictionGroup`：谁认领了哪个镜像的哪些缓存、最后一个持有者走了清什么、宿主想在内存压力下清什么。
- `SharedCacheBuildPromise`：在途构建的会合点，等待者在 `NSCondition` 上睡。

依赖只有 `MachOKit` / `MachOKitExtensions`（为了 `MachORepresentableWithCache` 与 `MachOTargetIdentifier`）和 `Utilities`。整个模块以 `@_spi(Internals)` 暴露，下游仓库（RuntimeViewer）不直接用它，经 `SwiftDeclarationIndexer` 与 `SymbolIndexStore` 的实例 API 间接使用。

## 文件 → 子系统对照

| 子系统 | 文件 |
|---|---|
| 1. get-or-build | `SharedCache`、`SharedCacheBuildPromise` |
| 2. 键 | `SharedCacheKey` |
| 3. 驱逐 | `SharedCacheRegistry`（含 `SharedCacheEvicting` 协议）、`SharedCacheEvictionGroup` |

## 1. get-or-build（`SharedCache`）

`storage(in:buildUsing:)` 是唯一的取值入口，三段式：锁内查字典，命中直接返回；有人在建就拿到它的 promise、出锁等；都没有就装一个 in-flight 标记、出锁跑构建闭包、回来在锁内写回并 fulfill 等待者。写回只在「标记还是自己的」时发生：`register(_:for:)` 或 `removeAll()` 可能在构建期间换掉了条目，那时构建者不写回，但仍把自己的结果交给已经在等它的人。构建返回 `nil` 不缓存，下一次重试（`MultiPayloadEnumDescriptorCache` 对非 Swift 读者就返回 `nil`）。

**构建闭包在调用点给，不在缓存里。** 缓存位于 `MachOSwiftSection` 之下，看不见 `MachOSwiftSectionRepresentableWithCache`，更看不见 `SwiftInspection` 的 `ObjCImplementationClassReading`；而每个索引的构建都要读描述符或 ObjC 类数据。以前基类的 `open func buildStorage(for: some MachORepresentableWithCache)` 把类型擦到最弱的协议，六个子类只好各自 `as? MachOFile / as? MachOImage` 再分派。现在持有者在自己的 `storage(in:)` 里把读者改一次类型（`SwiftInspection/Extensions/MachORepresentableWithCache+ReaderKinds.swift` 的 `swiftSectionReader` / `objcImplementationClassReader`，把 `some MachORepresentableWithCache` 转成对应协议的 existential，再交给 `some P` 参数的泛型 `build(in:)` 隐式打开），分派只写一次。查询 API 仍以 `MachORepresentableWithCache` 为参数类型，因为每个消费者手里拿的就是它。

每个持有者的固定形状：

```swift
package final class ObjCClassMethodIndex: @unchecked Sendable {
    package static let shared = ObjCClassMethodIndex()

    private let cache = SharedCache<Storage>(evictionGroup: .objcHierarchy)

    private init() {}

    package func storage(in machO: some MachORepresentableWithCache) -> Storage? {
        cache.storage(in: machO) { machO in
            machO.objcImplementationClassReader.map { Self.build(in: $0) }
        }
    }

    package func contains(in machO: some MachORepresentableWithCache) -> Bool {
        cache.contains(in: machO)
    }

    package func remove(for machO: some MachORepresentableWithCache) {
        cache.remove(for: machO)
    }
}
```

`register(_:for:)` 是「覆盖安装」：`PropertyWrapperTypeCatalogStore` 与 `ObjCAncestorResolverStore` 用它让 indexer 按自己的搜索路径建好的对象顶掉早先某次查询建的默认对象。`contains(in:)` 对在途构建回答 `false`，这是注册表认领规则要的语义：一个 `prepare()` 看到「没有」然后去建，哪怕最后和别人共享了一次构建，也算它建的。

**重入**：构建闭包里再对同一个键调 `storage(in:)`，会等一个只有自己返回才 fulfill 的 promise，永远不回来。promise 记下构建线程，`resolve` 在进入等待分支前发现等的是自己线程在建的 promise，直接 `precondition` 崩溃并报出键。只能抓同线程：`SymbolIndexStore` 的 sweep 经 `StackSafeExecutor.withLargeStack` 跳到 8 MB 工作线程，在那上面再重入抓不到。退出测试 `reentrantBuildForTheSameKeyTrapsInsteadOfHanging` 钉住这条。

## 2. 键（`SharedCacheKey`）

`MachORepresentableWithCache` 的两个 conformer（`MachOFile`、`MachOImage`）的 identifier 都是 `MachOTargetIdentifier`：从 dyld cache 读出的镜像按路径、`LC_UUID` 加所在主 cache 的 UUID（`.dyldCacheImage`），其余文件按 `LC_UUID` 加路径（`.uuidFile`），没有 UUID 的文件按 `LC_BUILD_VERSION` 或裸路径，进程内镜像按基址（`.image`）。cache 镜像必须带上 cache：同一次构建可以原样出现在两个 cache 里——macOS 13.5 和 13.6 的 SwiftUI 连 `LC_UUID` 都一样——但两个 cache 把它放在不同地址，经它读出的每个偏移都属于读它的那个 cache。只按 `.uuidFile` 时两份共用一切按镜像的缓存，后读的那份拿着前一份的类对象偏移去读自己的 cache，读到的不是指针，MachOKit 解 rebase 时 trap（MachOKitExtensions 1.1.0 修，`DyldCacheTwinImageTests` 钉住）。用主 cache 的 UUID，同一个镜像无论 cache 是只开主文件还是连子 cache 一起开，都是同一个身份。以前键是 `AnyHashable(machO.identifier)`：`.uuidFile` 的载荷超过 existential 的 24 字节内联缓冲，每次查找一次堆分配，再把整条路径喂给 SipHash——而查找发生在按符号、按 mangled name 的循环里。

`SharedCacheKey` 包住 identifier：`.uuidFile` 只哈希 UUID（链接器按构建唯一分配，单独就能区分镜像），`.dyldCacheImage` 只哈希镜像与 cache 的两个 UUID，`.image` 只哈希指针，`.file` / `.versionedFile` 才哈希路径；**等值比较仍比完整值**，路径不同的两个键相等测试不通过，只是哈希相同。identifier 不是 `MachOTargetIdentifier` 的读者（今天没有）走 `.opaque(AnyHashable)` 兜底。`SharedCacheKey(opaque:)` 同时是测试造键的入口。

没有直接把协议的 `associatedtype Identifier` 收窄成具体类型，因为协议在 sibling 仓库 `MachOKitExtensions` 里，且要给每个泛型签名加 `where MachO.Identifier == MachOTargetIdentifier`；这里用一次 `as?` 得到同样效果。

手里只有 `ReadingContext`、没有读者的 memo（`SymbolicDemangler` 的反混淆缓存、`InternedNodeReferenceCache`）从 context 的缓存范围（`cacheScope`）拿身份：`MachOContext` 答 `.image(identifier:)`，带的就是读者的 `MachOTargetIdentifier`，memo 用 `SharedCacheKey(identifier:)` 建键，与 `SharedCacheKey(machO)` 是同一个键，所以经读者和经 context 存进去的条目是同一条，驱逐也一起走。这个载荷故意是具体类型而不是 `AnyHashable`，理由同上：每次 memo 查找都要问一次范围。详见 [ReadingContextAbstraction.md](../ReadingContextAbstraction.md)「缓存范围」一节。

## 3. 驱逐（`SharedCacheRegistry` / `SharedCacheEvictionGroup`）

每个 `SharedCache` 在创建时声明自己的 eviction group，并向进程级 `SharedCacheRegistry.shared` 登记（弱引用）。**`MachOCaches` 自己不定义任何 group**：`SharedCacheEvictionGroup` 是一个只有名字的结构体，各模块在自己的扩展文件（`SharedCacheEvictionGroup+<模块>.swift`）里声明自己的常量，注册表处理的是「登记过的 group 的集合」，加一个 cache 不需要回来改这个模块。持有别的 group 存储引用的 cache 在创建时用 `follows:` 说明它跟谁走（`SharedCache(evictionGroup: .symbolicMangling, follows: [.symbolStore])`），注册表据此反向建表，同一 group 下多个 cache 的声明取并集。今天的对照：

| group（声明所在模块） | cache | follows |
|---|---|---|
| `symbolStore`（MachOSymbols） | `SymbolIndexStore` | — |
| `internedNames`（MachOSymbols） | `InternedNodeReferenceCache` | — |
| `symbolicMangling`（SwiftInspection） | `SymbolicManglingIndex`（持有符号表的 `_symbolic` 表） | `symbolStore` |
| `objcImplementationClasses`（SwiftInspection） | `ObjCImplementationClassIndex`（持有指向符号表 arena 的 `NodeReference`） | `symbolStore` |
| `objcHierarchy`（SwiftInspection） | `ObjCClassMethodIndex`、`SwiftClassObjectIndex`、`ObjCClassHierarchyProviderStore`（宿主的弱引用注册，手工遵循 `SharedCacheEvicting`） | `symbolStore` |
| `objcAncestorResolver`（SwiftInspection） | `ObjCAncestorResolverStore` | `symbolStore` |
| `demangleMemo`（SwiftInspection） | `SymbolicDemanglerCache`、`AnonymousContextPrivateDiscriminatorIndex` | `internedNames` |
| `propertyWrapperCatalog`（SwiftDeclarationRendering） | `PropertyWrapperTypeCatalogStore` | — |
| `multiPayloadEnumDescriptors`（SwiftDeclarationRendering） | `MultiPayloadEnumDescriptorCache` | — |
| `dependentMemberProjection`（SwiftDeclarationRendering） | `DependentMemberProjection` 的两个实例 | — |
| `thunkResolution`（SwiftThunkAnalysis） | `MetadataAccessorIndex`、`DependencyImageResolver` | — |

**认领与驱逐的规则**（PR #103 review 的 M6，原来是 `SwiftDeclarationIndexer.swift` 里的私有注册表，现在下沉到这里并推广到全部 group）：

- 一个持有者（`SwiftDeclarationIndexer`）在 `prepare()` 开头调 `registerLiveOwner(_:for:)`，注册表在自己的锁内采样：这个镜像在哪些登记过的 group 里还没有完成的条目，那些就是它要建的，全部认领。锁内采样是为了关掉一个窗口：采样在锁外做，兄弟 indexer 的注销恰好落在中间，会让它看到缓存都在、什么都不认领、随后重建一切又没有认领可驱逐，符号表就泄漏到进程结束。
- 只有第一次注册采样。同一持有者再注册（`prepare()` 重跑）看到的是自己刚建的缓存，再采样会反着读。
- `deregisterLiveOwner(_:for:)` 只在它是这个镜像**最后一个**活着的持有者时驱逐；提早走的兄弟什么都不清，否则幸存者已建好的名字留在孤儿 store 里、新名字落进新 store，`store ===` 快速路径从此分裂。驱逐在注册表锁内做，理由同上。
- 驱逐认领的 group 时连带跟着它走的 group（`follows` 的反向，传递闭包）：按上表，`symbolStore` 带走 `symbolicMangling`、`objcImplementationClasses`、`objcHierarchy`、`objcAncestorResolver`，`internedNames` 带走 `demangleMemo`（memo 的值是指向 interned arena 的引用，留着它 arena 释放不了）。单向：扔 memo 不要求扔 arena。
- 非持有者（`SwiftLayout`、渲染器、`SwiftSpecialization`）在 `prepare()` 之前填的条目不会被认领，也就不会被 indexer 驱逐；在 indexer 生命周期内填的会随它走（误认领的代价只是事后多建一次）。
- `evict(groups:for:)` 是显式驱逐，**不展开 followers**：调用方点名要清什么。`ObjCClassHierarchies.removeCache`、`ObjCImplementationClasses.removeCache`、`SymbolicDemangler.removeCache` 三个公开助手都是它的转发。

**内存压力**：库不再监听。以前每个 `SharedCache` 实例各挂一个 `MemoryPressureMonitor`，warning 就 `removeAll()`，绕过认领规则，而且清掉的存储被活着的 `NodeReference` 钉着、回收不到内存。现在宿主想清就调 `SharedCacheRegistry.shared.evictImagesWithoutLiveOwners()`：清所有出现在任一 cache 里、且没有活持有者的镜像的全部 group。非持有者临时填的镜像也会被清，这是宿主显式调用的后果。

**不受驱逐的**：两个进程作用域的 memo（`InternedNodeReferenceCache` 与 `SymbolicDemanglerCache` 给没有 Mach-O 句柄的进程内读取路径用的）是 `static let`，不经过按镜像的字典，大小由进程实际碰到的唯一名字数决定。

## 4. 契约与坑

- **新加一个按镜像的 cache**：在自己模块的 `SharedCacheEvictionGroup+<模块>.swift` 里选或加一个 group 常量；持有者按第 1 节的形状写，条目引用了别的 group 的存储就加 `follows:`；在这份文档的对照表登记。`MachOCaches` 不用动。不要再手写 `NSLock` 加字典。
- **构建闭包里不要查自己的 cache**：同线程会崩，跨线程会挂。需要别的 cache 可以（`buildClosureMayResolveOtherKey` 钉住）。
- **`MachOSymbols` 里的公开类型布局变了要 `swift package clean`**（AGENTS.md 的既有契约）：`SymbolIndexStore` 不再是 `SharedCache` 的子类就是这样一次变化。
- **测试怎么写**：`SharedCache(evictionGroup:registry:)` 与 `SharedCacheRegistry()` 都是 `package` 可见，测试自建注册表、用 `SharedCacheKey(opaque:)` 造键、用 `resolve(key:)` 驱动，不需要真镜像；端到端规则由 `SwiftIndexingTests/PerImageCacheEvictionTests` 在 fixture 上钉。
- **CI 跑的套件**：`SharedCacheResolveTests`、`SharedCacheResolveSwiftConcurrencyTests`、`SharedCacheKeyTests`、`SharedCacheRegistryTests`（`macOS.yml` 的 filter）。

## 验证

- `MachOCachesTests` 四个套件：get-or-build 契约（同键去重、异键并行、异键重入、取消不污染、同键重入崩溃、`register` 覆盖在途构建）、键的哈希与等值、注册表规则。异键并行用两个构建的会合点证明，不看墙钟。
- `SwiftIndexingTests/PerImageCacheEvictionTests`：indexer 与注册表的端到端。
- 渲染 A/B：见提案「验证」。
