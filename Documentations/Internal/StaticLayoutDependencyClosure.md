# SwiftLayout 阶段 3：跨依赖闭包（Dependency Closure）

> 承接 [`StaticLayoutEngine.md`](StaticLayoutEngine.md)（单镜像引擎 + existential/actor 支持）。本文把静态 field-offset 引擎从「单镜像」扩展为「依赖闭包」，使字段类型 / 父类 / 协议位于**其他镜像**时也能解析。面向维护者。
>
> **状态：已落地。** 下文设计/步骤为原始计划，末尾「落地实测」记录与计划的差异；与实现冲突处以「落地实测」为准。

## 背景与目标

当前 `SwiftLayout` 单镜像：`ImageUniverse.singleImage(machO)` 只建一个 `ImageReference`，索引该镜像的 `__swift5_types`（类型）与 `__swift5_protos`（协议 class 约束）。一旦字段类型 / 父类 / 协议定义在别的镜像，求解器降级该字段（`resilientFieldUnresolved` / `typeDescriptorNotFound`）。

阶段 3 目标：定位每个依赖二进制（`LC_LOAD_DYLIB` + dyld shared cache），跨闭包建立**全局**「限定名 → (镜像, descriptor)」索引，让求解器递归进其他镜像——**求解器代码零改动**。

**架构前提已验证（求解器对宇宙是 hermetic 的）：** 求解器只通过两个 seam 查询类型：
- `ImageUniverse.resolveType(byQualifiedTypeName:)` — `StaticTypeLayoutResolver.swift:163, 236`（struct/enum 字段、父类），`:20`（enum）
- `ImageUniverse.resolveProtocolClassConstraint(byQualifiedTypeName:)` — `ExistentialLayoutBridge.swift:105`（existential class-bound 判定）

`ImageUniverse.swift:8-11` 的注释早已为此预留扩展点。因此阶段 3 = 新增 `ImageUniverse.dependencyClosure(...)` 工厂 + `ImageReference` 索引聚合，**不动 `StaticTypeLayoutResolver` / `BasicLayout` / `ExistentialLayoutBridge` / `EnumLayoutBridge`**。

## 范围：5 个残留 partial 的归属

| Fixture 类型 | 卡点 | 归属 | 阶段 3 后可验证？ |
|---|---|---|---|
| `DistributedActorTest` | 跨模块字段 `Distributed.LocalTestingActorID`（struct） | **阶段 3** | ✅ runtime vector 非空 `[16,112,128]`，经现有 harness 验证 |
| `ResilientChild` | 跨模块 resilient 父类 `ResilientBase`（SymbolTestsHelper） | **阶段 3** | ⚠️ runtime field-offset vector 为空 → 需改用 field-offset global 作真值（见下） |
| `ResilientObjCStubChild` | 跨模块 Swift 父类 `Object`（SymbolTestsHelper） | **阶段 3** | ⚠️ 同上（resilient，vector 为空） |
| `ObjCMembersTest` | ObjC 祖先 `NSObject`（无 Swift descriptor） | **阶段 4** | ✅（阶段 4 已做）经 ObjC `class_ro_t.instanceSize` 起算，runtime vector `[8]` 自动校验 |
| `ObjCBridge` | ObjC 祖先 | **阶段 4** | ✅（阶段 4 已做）同上，runtime vector `[8]` |

阶段 3 收掉 3 个；ObjC 祖先 2 个当时明确留阶段 4。**阶段 4 已落地**：`superclassStartLayout` 在 Swift `resolveType` 之前加 ObjC 兜底，经第三个 seam `resolveObjCClassInstanceSize` 从 ObjC `class_ro_t` 取 `instanceSize`（**非 `instanceStart`**，见下更正）作起点。详见 [StaticLayoutEngine.md](StaticLayoutEngine.md) 的「核心算法」「实测发现」。

## 关键正确性边界（必须先讲清）

调研确认了 resilient 的静态可计算性，这是本阶段最容易出错的地方：

1. **resilient 不等于「无法静态计算」。** `ResilientChild` 的 runtime field-offset vector 为空，是因为父类 `ResilientBase` 以 `BUILD_LIBRARY_FOR_DISTRIBUTION=YES` 编译（`hasResilientSuperclass`，`ClassDescriptor.swift:81-82`），其 metadata bounds **延迟到运行时**算（`Metadata.cpp:273-285` `computeMetadataBoundsFromSuperclass`），子类用 field-offset **全局变量**而非 vector 存偏移。
   - 但子类**自身**字段偏移仍可静态算：读父类**实际二进制**的布局，用 `performBasicLayout` 从父类 `instanceSize` 起累加（`Metadata.cpp:3774` `super->getInstanceSize()`）。`computeClassLayout`（`StaticTypeLayoutResolver.swift:207-214`）已经是这套逻辑——父类一旦被闭包解析，递归即端到端打通。
   - **语义界定**：这算出的是「针对闭包里这组具体二进制版本」的偏移。这正是 ABI 分析想要的（分析特定部署），而非「客户端编译期可假设的偏移」（resilient 类型客户端不可假设）。文档须显式声明此语义。

2. **resilient 类的 runtime vector 为空 → 现有验证 harness 不能直接验证它们。** `StaticLayoutVsRuntimeTests` 以 `metadata.fieldOffsets(in:)` 为真值，对 `ResilientChild` 返回 `[]`。验证策略须扩展（见「验证」）。

3. **ObjC 祖先（`NSObject`）根本无 Swift descriptor**。阶段 3 **不碰**，留阶段 4 接 MachOObjCSection。
   - **阶段 4 更正**：当时此处写「偏移在 `class_ro_t.InstanceStart`」是**错的**。Swift 子类字段起点是 ObjC 父类的 **`instanceSize`**（`Metadata.cpp:3774` `super->getInstanceSize()`，`NSObject` = 8）；`instanceStart` 是 ObjC 类自身首 ivar 起点、cache 上常为 0。且 in-process 的 `NSObject` 是 realized 类，须经 `class_rw_t` 回退才能读到 instance `class_ro_t`。详见 StaticLayoutEngine.md「实测发现」。

## 设计

### 1. 镜像同构（typing 决策——避免类型擦除）

`ImageReference<MachO>` / `ImageUniverse<MachO>` 是单态的：所有镜像须同一具体 `MachO` 类型（`ImageReference.swift:12`）。直觉上闭包要混 `MachOFile`（磁盘依赖）与 dyld cache 镜像（不同具体类型），似乎要类型擦除。

**结论：不需要类型擦除——按 root 类型保持同构即可。**
- `MachOFile` root → 依赖也解析为 `MachOFile`：`FullDyldCache.host?.machOFile(by:)` 返回 `MachOFile`（`DyldCache+.swift:19`），磁盘依赖经 `File.loadFromFile`。
- `MachOImage`（在进程）root → 依赖经 `MachOImage(name:)` 返回 `MachOImage`。

两条路各自同构，`ImageReference<MachO>` / `ImageUniverse<MachO>` 泛型签名不变。这复用了 `SwiftInterfaceBuilderDependencies`（`SwiftInterfaceBuilderDependencies.swift:19/60` 两条平行路径）的现成模式。

> 备选（已否决）：把约束抬成 `any MachOSwiftSectionRepresentableWithCache` 存异构镜像。否决理由：同构方案更简单、零泛型擦除开销，且与现有依赖解析基建天然对齐。

### 2. `ImageUniverse.dependencyClosure` 工厂

```swift
extension ImageUniverse {
    /// 由调用方已解析好的依赖镜像直接构建（最底层、可测试、与解析策略解耦）。
    static func dependencyClosure(root: MachO, dependencyImages: [MachO]) throws -> ImageUniverse<MachO>
}
```

加两个**便利工厂**承担实际定位（解析策略与索引构建解耦）：
- `MachOFile` 版：`dependencyClosure(root: MachOFile, searchPaths: [DependencyPath])` —— 复用 `FullDyldCache.host` + 显式路径（`DependencyPath` 枚举，`DependencyPath.swift`），递归遍历 `machO.dependencies.map(\.dylib.name)`。
- `MachOImage` 版：`dependencyClosure(root: MachOImage)` —— 经 `MachOImage(name:)` 用活动 dyld 解析（系统框架天然走 dyld cache）。

### 3. 全局索引聚合

`ImageUniverse` 持 `rootImage` + `dependencyImages: [ImageReference<MachO>]`，构建时合并成两张全局表：
- `typeIndex: [String: (image: ImageReference<MachO>, descriptor: TypeContextDescriptorWrapper)]`
- `protocolIndex: [String: (image: ImageReference<MachO>, constraint: ProtocolClassConstraint)]`

`resolveType` / `resolveProtocolClassConstraint` 改为查全局表（root 优先，再依赖按 link 顺序，**首写者胜**）。`ImageReference.init` 的逐镜像索引逻辑（`ImageReference.swift:18-50`）原样复用，每个依赖镜像各建一份再合并。

### 4. 依赖闭包遍历 + 防环

- **递归 / 传递闭包**：`SwiftInterfaceBuilderDependencies` 只做一层；阶段 3 须递归遍历每个依赖的依赖。
- **install-name 去重 / 防环**：以 install-name 集合作 visited-set，避免框架互相依赖时无限递归。
- **@rpath / @loader_path / @executable_path**：代码库**无**现成展开器。MVP 策略：
  - dyld cache 按 **bare name** 匹配（`DyldCache+.swift:52-59` 去路径去扩展名）——覆盖 stdlib / Distributed / Foundation 等系统框架（正好是 fixture 的 `DistributedActorTest` 场景）；
  - 非 cache 依赖（如本地 `SymbolTestsHelper`）经显式 `searchPaths` 或在进程内经 `MachOImage(name:)`；
  - 完整 `@rpath` 展开（读 `LC_RPATH` + 相对 root 位置）**列为后续增强**，MVP 文档化「调用方可预先展开为绝对路径」。
- **求解器层防环**：`inProgressKeys` 用 `qualifiedTypeName`（`StaticTypeLayoutResolver.swift:168`）。限定名是模块限定的（如 `Distributed.LocalTestingActorID`），跨镜像撞名概率极低；**保持现状**，仅记风险。

### 5. 降级语义保持

定位不到的依赖**不**让整个宇宙构建失败——按现有逐字段降级（`FieldResolution.unknown`）。`LayoutUnknownReason.missingDependencyImage(installName:)`（`LayoutResolutionError.swift:11`，已存在但未用）此时启用，给出更精确的降级原因。

## 实现步骤（建议提交粒度）

1. **`ImageReference` 索引可复用化**：把「从一个 machO 建 type/protocol 索引」抽成可被多镜像聚合调用的形式（当前 `init` 已是单镜像版，加一个把多个 `ImageReference` 合并的入口）。
2. **`ImageUniverse` 多镜像化**：`rootImage` + `dependencyImages`，全局表合并，`resolveType` / `resolveProtocolClassConstraint` 改查全局表（root 优先）。加 `dependencyClosure(root:dependencyImages:)` 底层工厂。单测：手工塞两个镜像，验证跨镜像解析。
3. **`MachOImage` 便利工厂**：`dependencyClosure(root: MachOImage)` 经 `MachOImage(name:)` 递归 + 防环。用 fixture（`machOImage`）验证 `DistributedActorTest` 经 vector 完全解析、`ResilientChild` 字段偏移可算。
4. **`MachOFile` 便利工厂**：`dependencyClosure(root: MachOFile, searchPaths:)` 经 `FullDyldCache.host` + 显式路径。
5. **resilient 验证扩展**（见下）。
6. **文档**：更新 `StaticLayoutEngine.md`（移除阶段 3 残留项）、本文「实测」回填、`Documentations/README.md`。

每步 `swift build 2>&1 | xcsift` + 跑对应 `SwiftLayoutTests`。**遵循 CLAUDE.md：动手前先取得批准。**

## 验证

- **`DistributedActorTest`**：runtime vector `[16,112,128]` 非空，直接进现有 `StaticLayoutVsRuntimeTests`（闭包解析 `Distributed` 后应完全算对）。
- **resilient 类（`ResilientChild` / `ResilientObjCStubChild`）**：runtime `fieldOffsets(in:)` 返回 `[]`，**不能**用 vector 作真值。两条路：
  1. **field-offset global 作真值（推荐，原则正确）**：resilient 类的每个存储属性 emit 一个 field-offset 全局变量（mangled `…Wvd`）。读该符号的值作 ground truth，与静态重算逐字段对比。需 MachOSymbols 读符号 + 取数据。
  2. **字面值锁定（更快、可作过渡）**：仿 `ExistentialLayoutTests`，对小 fixture 手工推导期望偏移（`ResilientChild.extraField` = `ResilientBase.instanceSize`，后者从 helper 二进制读出）并 `#expect` 字面值。
- **覆盖率下限**：闭包模式下 `fullyComputedCount` 应再升（含跨模块类型）；更新 `StaticLayoutVsRuntimeTests` 阈值锁定收益。

## 风险与取舍

| 风险 | 缓解 |
|---|---|
| 异构镜像类型壁垒 | 按 root 类型保持同构（见设计 1），不引类型擦除 |
| `@rpath` 等未展开 → 部分依赖定位失败 | MVP 靠 dyld cache bare-name + 显式路径覆盖 fixture 场景；完整展开列后续；定位失败按字段降级，不 panic |
| 跨镜像限定名撞名 | 模块限定名天然区分；首写者胜；记录为已知小风险 |
| dyld cache 子缓存遗漏 | 枚举**全部** subcache（`DyldCache+.swift` 现仅取 `.first`，需扩展） |
| resilient 版本错配 | 闭包语义＝「针对这组具体二进制」；文档显式声明，不做跨版本假设 |
| 误入 ObjC 祖先 | `superclassStartLayout` 的 ObjC 降级分支保持不动；ObjC 留阶段 4 |

## 后续（阶段 4，超出本计划）

ObjC 祖先（`ObjCMembersTest` / `ObjCBridge`）：接 MachOObjCSection 读 `class_ro_t.InstanceStart/InstanceSize`（`Metadata.cpp:3778-3785`）作 class 起点。届时跨二进制 ObjC 父类经阶段 3 的闭包递归定位。

## 关键文件

- 复用：`Sources/SwiftInterface/SwiftInterfaceBuilderDependencies.swift`（依赖解析两条路径）、`Sources/SwiftInterface/DependencyPath.swift`
- 复用：`Sources/MachOExtensions/DyldCache+.swift`（`machOFile(by:)`、bare-name 匹配）、`MachORepresentableWithCache.swift`（`imagePath` / `cache`）
- 改动：`Sources/SwiftLayout/ImageUniverse.swift`、`Sources/SwiftLayout/ImageReference.swift`（**仅这两个** + 新增便利工厂文件）
- 不动：`StaticTypeLayoutResolver.swift`、`BasicLayout.swift`、`ExistentialLayoutBridge.swift`、`EnumLayoutBridge.swift`
- runtime 参照：`/Volumes/SwiftProjects/swift-project/swift/stdlib/public/runtime/Metadata.cpp:3767-3830`（class 字段布局 + Swift/ObjC 父类分派）

## 落地实测（与计划的差异）

实现完成后，与计划相比的关键调整与发现：

1. **全局索引改为惰性，而非 eager 合并。** 计划设想构建时把 root + 所有依赖合并成一张全局表。实测 `SymbolTestsCore` 传递闭包达 **551 个镜像**，eager 索引（逐镜像 demangle 全部 descriptor）约 **13 秒**。改为：root 立即索引，依赖按 BFS 顺序仅在某次 `resolveType`/`resolveProtocolClassConstraint` 全 miss 时增量索引下一个、命中即停。闭包构建（仅收集 551 镜像，不索引）降到约 0.8 秒。「真 miss」会触发整列表索引一遍，之后全 O(1)。`ImageUniverse` 因此持 `dependencyMachOs: [MachO]`（原始镜像）+ 惰性 `typeIndex`/`protocolIndex`，而非计划里的 `dependencyImages: [ImageReference]`。

2. **依赖收集用 BFS，不用 DFS。** 惰性索引下顺序至关重要：DFS 会在抵达 `libswiftDistributed` 前先把 Foundation 整棵子树排前面。BFS 让 root 的直接 Swift 依赖（多数字段类型所在）最先被索引。

3. **`MachOImage(name:)` 按 bare name 匹配；`MachOFile.imagePath` 是 install name。** 依赖 load name（`@rpath/Foo.framework/.../Foo`、`/usr/lib/swift/libswiftX.dylib`）须先归一到 bare name 再查。尤其 `MachOFile.imagePath` 返回 LC_ID_DYLIB（install name，`@rpath/...`）而非磁盘路径——`MachOFile` 闭包的显式 search path 不能由 root 的 `imagePath` 字符串替换得出，须另给真实磁盘路径（测试里由 `#filePath` 推导）。

4. **缺段容忍是必需的。** 纯 ObjC/C dylib 无 `__swift5_types`/`__swift5_protos`，多数镜像无 `__swift5_builtin`。`ImageReference`/`BuiltinTypeLayoutIndex` 把 `sectionNotFound` 视作空内容返回，否则闭包构建在第一个无 builtin 段的依赖处就抛错。

5. **`MachOFile` cache 解析须一次性建索引。** 逐次 `FullDyldCache.machOFile(by: .name(...))` 是 `O(依赖数 × cache 大小)` 的全扫描（实测拖到 21 秒）。改为首次 cache 查询时一次性遍历 `cache.machOFiles()` 建 bare-name → MachOFile 索引，之后 O(1)。

6. **resilient 验证只能走字面值。** 计划首选「读 `…Wvd` field-offset global」。实测 `ResilientChild`/`ResilientObjCStubChild` 这类 resilient 子类**根本不 emit `…Wvd`**（偏移纯运行时计算），runtime vector 也为空。故采用计划的 option 2（字面值锁定），但字面值由跨模块父类的静态 instanceSize 推导（`ResilientChild.extraField = 24`、`ResilientObjCStubChild.stubField = 16`），并辅以 `DistributedActorTest` 对非空 runtime vector `[16, 112, 128]` 的**自动**逐字段校验。

7. **`DependencyPath` 未复用，改本地 `LayoutDependencySearchPath`。** `DependencyPath` 在 `SwiftInterface`（上层 orchestrator），`SwiftLayout` 依赖它会造成层级倒置。新增的 `LayoutDependencySearchPath`（`.machOFile` / `.dyldSharedCache` / `.systemDyldSharedCache`）是 SwiftLayout 本地等价物。`SwiftLayout` 仅新增对 `MachOExtensions` 的依赖（复用 `File.loadFromFile` / `machOFile(by:)`）。

8. **典型决策保持。** 镜像同构（按 root 类型 `MachOImage`/`MachOFile` 各自闭包，无类型擦除）、求解器零改动（只经两个 seam）、降级语义保持（定位不到的依赖按字段降级不 panic）均如计划落地。
