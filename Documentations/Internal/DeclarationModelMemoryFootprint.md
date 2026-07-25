# 声明模型内存足迹量测与剩余优化空间

- **日期**: 2026-07-25
- **背景**: NodeStore 迁移（见 [NodeStoreMigrationPlan.md](NodeStoreMigrationPlan.md)）落地后，RuntimeViewer 实测内存腰斩。本文记录「还剩多少空间」这一问题的量测结果与结论，避免日后重新盘查。
- **结论先行**: 剩余可回收量约 35–45 MB，占当时 434 MB 的 8–10%，需要动 `MachOSwiftSection` 核心模型，**当前不建议实施**。

## 一、迁移收益（RuntimeViewer 实测，相同负载）

| 指标 | 迁移前 | 迁移后 |
|---|---|---|
| `Node` 实例数 | 1,101,318 | 183,994 |
| 进程内存 | 842.3 MB | 434.2 MB |
| `NodeCache` 实例 | 1 | 1（且不再随浏览增长，Stage 5c 生效） |

同时可见 `NodeStore` 67,056 个、`TypeDefinition` 10,524 个。

**这一轮真正解决的是无界增长**：全局 `NodeCache` 不再随浏览累积。绝对值的进一步压缩属于收尾，性质不同。

## 二、量测方法

用 `class_getInstanceSize`（类实例真实大小）+ `MemoryLayout<T>.size/stride`（值类型内联足迹）对声明模型逐项量测。探针是一个独立可执行包，依赖 `MachOSwiftSection` + `SwiftDeclaration` 两个 product，release 构建，本文末附完整源码。

malloc 分桶用独立的 C 程序实测，不依赖记忆。

## 三、`TypeDefinition` 实例构成

`class_getInstanceSize(TypeDefinition.self)` = **1272 字节**。

| 存储属性 | 字节 |
|---|---|
| `type: TypeContextWrapper` | **472** |
| `parentContext: ParentContext?` | **472** |
| `metadata: MetadataWrapper?` | 96（size 89） |
| 14 个数组/集合引用 × 8 | 112 |
| `deallocatorSymbol` / `destructorSymbol`（两个 `DemangledSymbol?`） | ~80 |
| 对象头 | 16 |
| `typeName: TypeName` | 16（size 13） |
| 其余（`weak parent`、两个 `Bool`） | ~18 |

**两份 `TypeContextWrapper` 合计 944 字节，占 74%。**

同批量测的兄弟类型：`ProtocolDefinition` 440 字节、`ExtensionDefinition` 520 字节。单个镜像的 extension 定义数可达上万（conformance 每条一个），值得一并纳入后续评估。

成员定义（数组元素，按值存储）：`FieldDefinition` 40、`VariableDefinition` 56、`FunctionDefinition` 144。

## 四、`TypeContextWrapper` 为何是 472 字节

它是枚举，大小按最大 case 取：

| Case | 字节 |
|---|---|
| `Class` | **472** |
| `Struct` | 304（size 297） |
| `Enum` | 304（size 297） |

**即便是 struct / enum 的定义，也照样按 class 的 472 字节付费。**

`Class` 之所以 472，是因为有 12 个**内联的可选描述符**（Swift 的 `Optional` 对结构体不装箱，直接占位）+ 5 个数组引用：

| 成员 | 字节 |
|---|---|
| `TypeGenericContext?` | **160** |
| `ClassDescriptor` | 52 |
| `SingletonMetadataInitialization?` | 21 |
| `ResilientSuperclass?` / `VTableDescriptorHeader?` / `OverrideTableHeader?` / `ObjCResilientClassStubInfo?` / `SingletonMetadataPointer?` / `MethodDefaultOverrideTableHeader?` | 各 17 |
| `ForeignMetadataInitialization?` | 13 |
| `InvertibleProtocolSet?` | 3 |
| 5 个数组引用 | 各 8 |

其中 `TypeGenericContext?` 一项就 160 字节，而绝大多数类型是非泛型的——这 160 字节存的是 nil。

## 五、三处可回收项

### 1. `parentContext` 是被当成永久字段的临时值（性质上是卫生问题）

全代码库读写点追踪结果：

- **写**：仅在 `SwiftIndexing/SwiftDeclarationIndexer.swift` 索引过程中赋值（356–380 行）
- **读**：仅在**同一个函数**紧接着的循环里读一次（390–421 行），用于构造 extension 定义
- 此后**再无任何消费者**

且 `.type` 分支对这 472 字节的唯一用途是取名字：

```swift
case .type(let parentType):
    let parentTypeName = try parentType.typeName(in: machO)
```

即：为了在索引期传递一次「父类型叫什么」，每个 `TypeDefinition` 永久扛着一份完整描述符包装。

**改法**（二选一，都不动公开语义）：
- 索引期改用局部字典 `[ObjectIdentifier: ParentContext]` 承载，函数返回即释放；或
- 把 `.type` 的载荷从 `TypeContextWrapper` 换成 `TypeContextDescriptorWrapper`（仅描述符引用）

**收益**：实例 1272 → 约 800 字节，10,524 个实例约 **7.6 MB**。

### 2. `TypeContextWrapper` 载荷装箱

把 `Class` / `Struct` / `Enum` 改为 `indirect case`（或引用类型），枚举本身 472 → 8 字节。

额外红利：Swift 的 indirect box **复制时共享**，因此 `parentContext = .type(父的 wrapper)` 会与父对象的 `type` 共用同一个 box，不再复制。

**收益**：单独实施即可让实例降到约 344 字节，约 **12.6 MB**（与第 1 项收益重叠）。
**代价**：`TypeContextWrapper` 在全库按值传递，装箱引入引用计数开销，须先跑吞吐对比。

### 3. `NodeStore` mini-store 增殖 + `MetadataReaderCache` 仍持 `Node`

- `NodeReference(interning:)` 的语义是**每次调用新建一个私有 store**（其文档注释已明示，并指出批量场景应直接驱动 `NodeStoreBuilder` 共享 arena）。28 处调用点中，热点是按类型/协议/conformance 逐个派生名字的地方——这是 67,056 个 `NodeStore` 的来源。单个小名字树的开销约 270 字节（对象 48 + nodes 缓冲 160 + text 缓冲 64），而真正载荷仅约 150 字节；更大的损失是**跨名字的 hash-consing 去重被切断**（同模块几万个名字里 `Module("SwiftUI")` 这类叶子各存一份）。估算约 **18 MB**。
  - 修法建议**分块 arena**：每 N 个名字共用一个 builder，写满即冻结换新。不破坏「冻结后不可变 ⇒ `Sendable` 免锁」这一性质。`TypeDefinition.index` 已有同类范例（一个类型的所有字段树共享一个 store）。
- `MetadataReaderCache.Storage` 仍以三个字典缓存 **`Node` 类树**（`nodeForMangledNameBox` / `nodeForContextOffset` / `nodeForSymbolName`）——这是残留 183,994 个 `Node` 的来源。Stage 5c 只把**构造**改为 transient（阻止 `NodeCache` 增长），并未改变**持有**形态。改持 `NodeReference` 即可清零，估算约 **8 MB**。它继承自 `SharedCache`，走内存压力清理与按镜像驱逐，属稳态占用而非泄漏。

## 六、结论：当前不建议实施

| 项 | 收益 | 改动面 |
|---|---|---|
| `parentContext` 常驻 | ~7.6 MB | 小 |
| `TypeContextWrapper` 装箱 | ~12.6 MB（与上项重叠） | 大，有 ARC 吞吐风险 |
| NodeStore mini-store 合并 | ~18 MB | 中 |
| `MetadataReaderCache` 改持 `NodeReference` | ~8 MB | 中 |

全部实施约 **35–45 MB / 434 MB ≈ 8–10%**，代价是改动核心模型。投入产出不成比例。

**须知量测边界**：上述四项之外的约 90% 内存构成**未曾量测**。本轮只沿 Node / NodeStore / 声明模型这条线量到底，而这条线已不再是大头。若日后要继续压缩，**第一步应是用 Instruments Allocations 按分配大小剖析 434 MB 的真实构成**，而不是继续在这 10% 里做优化。

**更该先回答的问题**：434 MB 是稳态还是仍在增长？

- 稳态 → 本轮目标（阻止无界增长 + 砍半）已达成，收工。
- 仍单调上涨 → 增长源比任何静态优化都重要，应单独立项。

唯一建议顺手做的是第 1 项（`parentContext`），且不必为它单独开一轮——下次改到 `SwiftDeclarationIndexer` 时捎带修掉即可。

## 七、待澄清

内存图对某个 `TypeDefinition` 实例显示 **Size 1536 bytes**，而本文量测的实例大小是 1272 字节。实测 macOS 分桶为：

```
request   440 -> malloc_size   448      request  1000 -> malloc_size  1024
request   520 -> malloc_size   640      request  1024 -> malloc_size  1024
request   800 -> malloc_size   896      request  1272 -> malloc_size  1280
request   816 -> malloc_size   896      request  1536 -> malloc_size  1536
```

且实测一个 `class_getInstanceSize == 1272` 的 Swift 类，其 `malloc_size` 为 **1280**。因此 1272 **不会**被舍入到 1536——两者相差的 264 字节尚无解释。候选原因：

1. RV 运行的二进制早于当前分支 HEAD，彼时 `TypeDefinition` 字段更多；
2. RV 的 workspace 本地引用实际解析到了另一份 `MachOSwiftSection` 检出。

下次在 RV 里复量时应先确认所链接的检出与提交。**本文的属性构成表不受此影响**——1272 由各属性尺寸独立累加自洽。

## 八、复现方法

```swift
// Package.swift 依赖 MachOSwiftSection 的 MachOSwiftSection + SwiftDeclaration 两个 product
import ObjectiveC
import MachOSwiftSection
import SwiftDeclaration

print(class_getInstanceSize(TypeDefinition.self))          // 1272
print(MemoryLayout<TypeContextWrapper>.size)               // 472
print(MemoryLayout<TypeDefinition.ParentContext?>.size)    // 472
print(MemoryLayout<Class>.size, MemoryLayout<Struct>.size) // 472, 297
print(MemoryLayout<TypeGenericContext?>.size)              // 160
```

malloc 分桶用 `malloc_size()`（`<malloc/malloc.h>`）实测，Swift 对象用
`malloc_size(Unmanaged.passUnretained(object).toOpaque())`。
