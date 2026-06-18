# 嵌套字段里的泛型实参替换：它解决什么问题，以及为什么要引入

这篇文档专门解释 `SwiftDeclarationRendering/FieldLayoutRenderer.swift` 里那套
**“手工静态泛型实参替换”**（`substitutingGenericParameters` / `staticallyBoundMetatype`
/ `boundGenericArgumentType` 这一族函数）：

- 它在渲染什么、为什么需要它；
- 当初为什么**不能**直接问运行期、而要手写一套从 metadata 裸读实参的逻辑（commit `0107c8a`）；
- 它依赖的泛型实参向量 ABI（以权威 Swift 源码为准）；
- 这套设计埋过的坑（`EXC_BAD_ACCESS @ 0x1`）与现在的形态（value / pack 支持）。

> 相关：渲染抽取的整体迁移见 [`FieldMetadataRenderingMigration.md`](FieldMetadataRenderingMigration.md)；
> 这里只聚焦“替换”这一件事。

---

## 1. 背景：嵌套字段偏移走查在干什么

开启 `printExpandedFieldOffsets` 时，dumper / interface 打印器会在每个存储字段前，
**递归展开**该字段类型内部的字段偏移树，渲染成这样的注释：

```
//     └── variable (SomeType): 0x10
//         ├── header (Header): 0x10
//         └── payload (Payload): 0x18
```

要画出这棵树，对每一层嵌套类型都需要两样东西：

1. **字段偏移**——来自运行期 metadata 的 field-offset 向量（`metadata.fieldOffsets`），不涉及本文主题；
2. **字段的类型名**——把字段记录里的 *mangled type name* demangle 成可读字符串。

问题就出在第 2 点：当父类型是**泛型**且我们手上是它的**特化（specialized）in-process metadata** 时，
字段记录里的 mangled name 引用的是**泛型参数**（`τ_0_0`、`τ_0_1`……，demangle 成
`dependentGenericParamType`），而不是具体类型。直接 demangle 只会得到占位符名字（`A`、`B`），
而我们想显示的是**这个特化实例里参数被绑定成的具体类型**——例如把字段类型
`Array<τ_0_0>` 显示成 `Array<Swift.Int>`，而不是 `Array<A>`。

**“替换”要解决的就是这件事**：把 demangle 出来的类型 node 里的 depth-0 泛型参数引用，
替换成该特化 metadata 实际绑定的具体实参，再打印。

> 注意：这条路径**只在 MachOImage（in-process）下触发**（`expandedFieldOffsets` 整体 gate 在
> `machO.asMachOImage`）。MachOFile 没有活的运行期 metadata，根本不发射这些注释，也就不需要替换。

---

## 2. 第一反应：直接问运行期——为什么不行

最自然的做法是把字段的 mangled name 连同父类型的泛型上下文一起交给 Swift 运行期，让它解析出具体类型：

```swift
RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName, specializedFrom: parentMetadata, in: machOImage)
```

这个 overload 会把 `metadataPointer + sizeof(Layout)`（实参向量基址）和 descriptor 一并丢给运行期的
`swift_getTypeByMangledNameInContext`，由运行期自己走查泛型环境、按需解析每个参数。**在普通进程里这完全可行。**

但本项目的核心使用场景是 **RuntimeViewer 把自己注入到目标进程**、对目标加载的第三方框架(SwiftUI 等)的
**MachOImage** 做接口导出。在这个场景下，上面的运行期解析会**硬崩**，有两种致命模式：

### 2.1 PAC-fault（不可捕获的硬件 trap）

`getTypeByMangledNameInContext(specializedFrom:)` 在走查 descriptor 的泛型环境时，会**认证
（authenticate）带签名的指针**（arm64e Pointer Authentication）。当 bound generic 的实参来自
**第三方框架、且跨越 ObjC 边界**（典型例子 `SwiftUI.ObservedObject<某 NSObject 子类>`）时，
指针签名上下文对不上，CPU 直接抛**硬件 trap**。

这种 trap 是**不可捕获**的：它不是 Swift error，`try?` / `do-catch` 拦不住，整个进程当场死亡。

### 2.2 无上下文 overload 的 `fatalError`

退一步用 context-free 的 `getTypeByMangledNameInContext(mangledTypeName)`（不传泛型上下文）也不行：
当 mangled name 里仍含**依赖类型**（泛型参数引用、关联类型）却没有上下文去绑定它时，运行期会在
`createDependentMemberType` 里直接 `fatalError`——同样**不可捕获**、同样进程死亡。

**结论**：在注入进程里对第三方泛型类型，“把活干给运行期”这条路两头都是雷，而且都绕不过 `try?`。
这就是引入手工替换的根本原因。

---

## 3. 解法：手工静态替换（commit `0107c8a`）

`0107c8a fix(SwiftDump): statically substitute nested generics to avoid trap` 的思路：

> **自己复现 depth-0 的 `(depth, index) → 实参` 映射**：直接从父类型特化 in-process metadata 的
> header 之后那段**内联实参数组**里读出具体实参 metadata，**只把全具体的名字交给运行期**。

也就是说，我们**不让运行期去解析依赖类型**——而是自己把 `τ_0_i` 换成它在这个特化实例里实际绑定的
具体类型，换完后整棵 node 树里再没有 `dependentGenericParamType`，要么直接打印（不经过运行期），
要么交给运行期的也只是**全具体**的名字（不触发签名认证 / 依赖解析，从而绕开 §2 两种 trap）。

为什么安全：

- **不认证签名指针**——我们只是从 metadata 的实参槽里 `load` 一个字、判空判对齐后当指针用，
  不调用任何会做 PAC 认证的运行期入口。
- **不解析依赖上下文**——替换发生在 node 层，依赖参数被换成具体类型后才（可能）交给运行期。
- **偏移不受影响**——字段偏移始终来自 `metadata.fieldOffsets`，与本替换正交；替换只影响**类型名**。

附带：`0107c8a` 还加了 `MetadataReader.demangleTypeUncached`，让递归 dump 路径对那个加锁的共享 node 缓存
保持可重入安全。

---

## 4. 实参向量 ABI（以权威 Swift 源码为准）

手工读槽位的前提是精确知道实参向量的排布。下列事实**全部对照** `/Volumes/SwiftProjects/swift-project`
权威源码核实，而非凭记忆：

特化 metadata 头（value metadata 为 `{kind, descriptor}` = 16 字节）之后，紧跟**内联泛型实参向量**：

```
[ numShapeClasses 个 pack 长度字 ]
[ 每个 hasKeyArgument 参数一字，按声明序，三种 kind 交错：
      .type     → const Metadata*        （类型 metadata 指针）
      .value    → 原始整数值本身          （SE-0452 值泛型，目前仅 Int）
      .typePack → MetadataPackPointer     （metadata 包指针，低位是 on-heap 标记）]
[ 见证表（每个 hasKeyArgument 的 requirement 一字）]
```

**关键事实与出处：**

- **槽位公式**：depth-0 参数 `index` 的槽位 =
  `numShapeClasses + (其前 hasKeyArgument 参数计数，不分 kind)`。
  以运行期**真正的读取器** `SubstGenericParametersFromMetadata::getMetadata`
  （`swift/stdlib/public/runtime/MetadataLookup.cpp`）为准——它对 type/value/typePack 一视同仁，
  都从 `genericArgs[flatIndex]` 取，`flatIndex` 对每个 hasKeyArgument 参数 +1（不分 kind）。
  > 坑：`GenericContext.h` 的 `NumKeyArguments` 文档注释把 value“排在见证表之后”，那描述的是另一种布局；
  > **实测读取器以交错为准**，不要按头注释去“改正”槽位数学。
- **shape class 在最前**：`MetadataLookup.cpp` 里 `nonShapeClassGenericArgs = getGenericArgs() + NumShapeClasses`，
  且 `GenericPackShapeDescriptor.Index` 的注释明说“counts the shape classes at the beginning”。
- **越界上界**：`header.numKeyArguments` 是整个 key 区大小（**含** shape class，见 `GenericContext.h` L59-83），
  可作任意槽位读取的安全上界。
- **pack 定位**（`swift/include/swift/ABI/GenericContext.h`）：metadata-kind 的 `GenericPackShapeDescriptor`
  全排在 witnessTable-kind 之前、各自按 `Index` 排序；第 k 个 metadata-kind descriptor 对应第 k 个
  `.typePack` key 参数。pack 指针槽 = `descriptor.Index`（绝对，已含 shape class 偏移）；
  pack 长度 = `genericArgs[descriptor.ShapeClass]`（前导 shape-class 槽存的就是长度）。
- **pack 指针**（`swift/include/swift/ABI/Metadata.h` `TargetPackPointer`）：最低位是 on-heap 生命周期标记，
  `getElements() = Ptr & ~1`；元素是 `count` 个连续的 `const Metadata*`。
  （长度宁可读 shape-class 槽，也不调 `getNumElements()`——后者读 `elements[-1]`，对 on-stack pack 会 `fatalError`。）

---

## 5. 替换是怎么跑的

入口 `nestedTypeName(for:parentMetadata:)`：

1. `MetadataReader.demangleTypeUncached(for: mangledTypeName)` 把字段 mangled name demangle 成 node 树；
2. `topLevelGenericLayout(of: parentMetadata)` 取出 depth-0 参数、`keyArgumentFlags`、`numShapeClasses`、
   `totalKeyArguments`、metadata-kind pack descriptors；
3. `substitutingGenericParameters(in:parentMetadata:layout:)` **递归**走 node 树，
   命中 depth-0 `dependentGenericParamType` 就按其 kind 替换；
4. 把替换后的 node `printSemantic(using: .default)` 成字符串。

替换出的节点**接替**被命中的那个裸 `dependentGenericParamType`，其外层 `.type` wrapper 由递归保留——
所以 `.value` 得到规范的 `type(integer)`、`.type` 得到 `type(<nominal>)`，与 demangler 自身产出一致。
结果**仅用于打印**（从不 remangle），故 pack 直接用裸 `pack` 子节点（打成 `Pack{…}`）即可。

递归侧另有 `staticallyBoundMetatype`：当**整个字段类型就是**某个 depth-0 参数时，用来取出要继续下钻的
具体 metatype——它**只对 `.type`** 生效（`.value`/`.typePack` 没有可静态走查的嵌套字段布局）。

---

## 6. 三种参数 kind 的处理

| kind | 槽里是什么 | 怎么渲染 |
|---|---|---|
| `.type` | `const Metadata*` | `_mangledTypeName(指针)` → demangle → 拼入节点（原始路径） |
| `.value` | 原始整数（SE-0452 值泛型） | 建 `.integer` / `.negativeInteger` 字面量节点，如 `InlineArray<3, UInt8>` |
| `.typePack` | `MetadataPackPointer` | 读 pack（`& ~1` 去标记、count 取自 `ShapeClass` 槽）→ 逐元素 `_mangledTypeName` → 建 `.pack` 节点（`Pack{…}`） |

槽位一律用 §4 的统一公式 `numShapeClasses + flatIndex`（pack 也可直接用 `descriptor.Index`，二者一致）。

---

## 7. 埋过的坑：忽略 `GenericParamKind` 的 `EXC_BAD_ACCESS @ 0x1`

`0107c8a` 引入这套替换时，`boundGenericArgumentType` 把**每个 key argument 都当成 type-metadata 指针**
裸读再 `unsafeBitCast` 成 `Any.Type`，**完全忽略了参数 kind**。这在当时只跑 `.type` 为主的场景下没暴露，
但它是个**潜在缺陷**：

- **`.value` 槽里是整数本身**（不是指针）。当某 SwiftUI 类型的 depth-0 参数是 `.value`、值为 `1` 时，
  把 `1` `unsafeBitCast` 成 `Any.Type` 交给 `_mangledTypeName` → `swift_getMangledTypeName`
  → `_swift_buildDemanglingForMetadata` 解引用地址 `0x1` → **`EXC_BAD_ACCESS code=1 address=0x1`**
  （崩溃地址恰好等于那个值 `1`，是决定性证据）。
- `.typePack` 槽里是带低位 tag 的 pack 指针，同样不是裸 metadata 指针。

为什么直到最近才炸：model 驱动的打印器（`SwiftDeclarationPrinter`）一度在 MachOImage 上**根本不发射
expanded offsets**（一个独立的 metadata 回归）；修掉那个回归后，printer 路径才首次真正在 SwiftUI MachOImage
上跑这套替换，于是潜伏的 value-generic 缺陷立刻暴露。

> 历史误判已澄清：曾把这个崩溃记成“`substitutingGenericParameters` 无界递归栈溢出”。其实崩溃栈里 ~30 帧
> 的 `substitutingGenericParameters` 看似深递归，实为叶子处把整数当指针解引用——并非栈耗尽。修复后
> `RenderingVerificationTests`（SwiftUI × MachOImage × 全 options）跑通无崩溃，该问题不复现。

### 修复

1. **kind 门控**（止崩 + 正确渲染）：替换按 `GenericParamKind` 分派——`.type` 走指针解析，`.value` / `.typePack`
   走各自的整数 / 包渲染（见 §6）。flat-index 仍按**全部** key argument 计数（每种参数恰好占一个槽），
   后续 `.type` 槽位定位不变。
2. **`.type` 路径补 `numShapeClasses` 偏移**：原实现漏了它，对**变长类型**会算错槽位（非变长 `numShapeClasses=0`、
   逐字节不变；变长是纯修正）。
3. **`boundGenericArgumentType` 兜底**：null + 8 字节对齐 + 槽位越界检查；任何读取可疑都回退占位符，绝不解引用坏字。
4. **`GenericParamDescriptor.kind` 强解包硬化**：原为 `GenericParamKind(rawValue: raw & 0x3F)!`，对未建模的
   reserved kind 字节（`3...0x3E`）会 trap。门控新增的 `.kind` 急切求值会触发它，故改成 `?? .max`
   （runtime 用 `Max=0x3F` 作哨兵；任何 `== .type` 判断都正确视其为“非 type”）。此改动同时盖掉
   `GenericSpecializer` 既有的同类暴露。

---

## 8. 当前设计的不变式

- **仅 MachOImage / in-process**：整条路径 gate 在 `machO.asMachOImage`；`parentMetadata` 始终是已完整实例化的
  in-process 特化 metadata（其 key-arg 槽由运行期保证填了真实 metadata / 包指针 / 值）。
- **仅 depth-0**：只替换最外层泛型参数。这正是 `descriptor.Index` 绝对槽位、以及 `allParameters.first` +
  累积 pack descriptor 映射成立的前提；若放开到 depth>0，pack 序号计数会失配（见代码注释）。
- **仅用于打印**：替换结果只 `printSemantic`，从不 remangle。
- **永不崩**：bounds / 对齐 / count 上限（256）全程兜底；任一守卫失败即回退到未绑定占位符——退化为“显示参数名”
  而非崩溃或乱码。
- **仅限 value metadata**：`boundGenericArgumentType` 等约束在 `ValueMetadataProtocol`（struct/enum），
  只对 `.struct`/`.enum`/`.optional` 触发；class metadata 的实参偏移不是定值，从不走这条裸读路径。

---

## 9. 已知局限

- **pack 在 `repeat` 下渲染成 `repeat …<Pack{…}>`**，而非惯用的展平写法 `(A, B)`。作为
  expanded-field-offset **诊断注释**，显示具体包内容已达目的；完整的 `packExpansion` 展平是后续可做的增强。
- **node 递归理论上仍无界**：`substitutingGenericParameters` 沿 demangled node 树递归没有深度上限。
  实测框架（SwiftUI / SwiftUICore 全开）未观察到溢出；若未来遇到真正病态的深度，在该处加深度上限即可
  （单点同时惠及 dumper 与 model printer）。
- **残留的固有风险**：`.type` / pack 元素最终仍会把一个“看起来合法、对齐、非空”的字交给 `_mangledTypeName`。
  null/对齐/越界守卫能挡住明显垃圾，但一个恰好对齐却非 metadata 的陈旧字仍可能在运行期内部触雷。
  此风险**自始存在、非本设计新增**，且因 `parentMetadata` 必为已实例化 in-process metadata 而被严格收敛。

---

## 10. 涉及的文件 / commit

- 实现：`Sources/SwiftDeclarationRendering/FieldLayoutRenderer.swift`
  （`substitutingGenericParameters` / `staticallyBoundMetatype` / `boundGenericArgumentType` /
  `substitutedValueNode` / `substitutedPackNode` / `genericArgumentWord` / `topLevelGenericLayout`）。
- 模型：`Sources/MachOSwiftSection/Models/Generic/`（`GenericParamDescriptor` / `GenericParamKind` /
  `GenericPackShapeDescriptor` / `GenericPackShapeHeader` / `GenericValueDescriptor` / `GenericContext`）。
- 运行期入口：`Sources/MachOSwiftSection/Runtime/RuntimeFunctions.swift`
  （`getTypeByMangledNameInContext(specializedFrom:)`——即 §2 那条“会 trap”的路径）。
- 关键 commit：`0107c8a`（引入静态替换止 trap）、value-generic 止崩与 `kind` 硬化、value/pack 渲染支持。
- 权威 ABI 出处：`swift/include/swift/ABI/{GenericContext.h, Metadata.h, MetadataValues.h}`、
  `swift/stdlib/public/runtime/MetadataLookup.cpp`（`SubstGenericParametersFromMetadata::getMetadata`、
  `_gatherGenericParameters`）。
