# SwiftLayout：静态 Field Offset 计算引擎实现说明

> 配套调研见 [`StaticFieldOffsetComputation.md`](StaticFieldOffsetComputation.md)。本文记录**实际落地的实现**、与调研的差异，以及首期覆盖范围与已知降级。面向维护者。

## 背景与目标

`feature/swift-diffing` 的静态 ABI 分析需要**不加载进程、不调用 runtime**，纯从 Mach-O 文件离线算出 Swift struct/class stored-property 的准确字节偏移。`SwiftLayout` module 实现这一能力。

## 关键设计决策

1. **重算，而非读 vector（路径 B，非路径 A）。** 实测确认两点颠覆了「直接读 metadata field-offset vector」的捷径：
   - **metadata 对象的 materialize 只有一条路：runtime accessor**（`descriptor.metadataAccessorFunction(in:)` → `accessor(request:)` **执行函数**），只能在已加载 MachOImage 下做。纯 MachOFile 不能执行 accessor，无法定位完整 metadata。
   - **ValueWitnessTable 在纯 MachOFile 静态上下文不可读**（runtime 对象，指针指向运行时分配内存）。

   因此引擎离线移植 runtime 的 `performBasicLayout`：从 `FieldDescriptor` 逐字段求 `(size, alignment)` 再累加。这套求解器统一处理 fixed + resilient + 嵌套，并能正确处理编译器写 0 占位的情况。

2. **独立 `SwiftLayout` module**，依赖 `MachOSwiftSection` + `SwiftInspection`，是 `SwiftInspection` 之上的独立 peer。不依赖 `SwiftDeclaration`，使 `SwiftDiffing` 后续可按需依赖而无环。

3. **逐字段降级。** 单个字段类型解析失败（existential、actor 默认存储、跨模块 resilient、未替换泛型参数）时，该字段及其后字段标 `FieldResolution.unknown`，而非整型失败；前序已算字段仍准确返回。`AggregateFieldLayout.computedFieldOffsets` 给出可信前缀，供 diffing 只比对已算字段。

## 模块结构

```
Sources/SwiftLayout/
├── TypeLayoutInfo.swift            # 输出值类型 (size/stride/alignmentMask/XI/isBitwiseTakable)
├── BasicLayout.swift               # runBasicLayout 内核（performBasicLayout 离线移植）
├── KnownLayoutTable.swift          # 硬编码 stdlib 固定布局表
├── BuiltinTypeLayoutIndex.swift    # __swift5_builtin 整体布局索引：C-imported 值类型 + multi-payload enum，按 demangle 还原的限定名建 key
├── NodeTypeNaming.swift            # 从 demangle Node 提取限定类型名 / 协议限定名（忽略泛型参数）；ObjC class 节点（__C.X）取裸名
├── GenericArgumentEnvironment.swift # 阶段 5：bound-generic 实例化的 (depth,index)→实参 Node 映射 + Node.Rewriter 语法替换（depth-0 类型参数，value/pack 降级）
├── StaticTypeLayoutResolver.swift  # 递归求解器：Node.Kind 分派 + memoization（含实例化 key 防环）+ 泛型环境线程化
├── EnumLayoutBridge.swift          # enum/Optional 布局（getEnumTagCounts 公式移植）
├── ExistentialLayoutBridge.swift   # existential 容器 + existential metatype（ExistentialTypeInfoBuilder 移植）
├── ObjCClassIndex.swift            # 阶段 4：从 __objc_classlist 读 ObjC 类 instanceSize（裸名→起点布局）；instance class_ro_t（realized 类经 class_rw_t 回退），按 MachOImage/MachOFile 拆两份
├── ImageReference.swift            # 单镜像：类型限定名 → descriptor 索引 + 协议 class 约束索引 + ObjC 类 instanceSize 索引 + builtin 索引（缺段容忍）
├── ImageUniverse.swift             # singleImage / dependencyClosure；类型/协议/ObjC-类三个解析 seam；依赖惰性索引
├── ImageUniverse+DependencyClosure.swift # 闭包便利工厂（MachOImage 经 dyld / MachOFile 经显式路径+cache）+ bare-name 归一 + BFS 闭包遍历
├── AggregateFieldLayout.swift      # 结果类型 + FieldLayoutEntry + FieldResolution
├── StaticLayoutCalculator.swift    # 顶层 API + 逐字段降级
└── LayoutResolutionError.swift     # 内部错误 + LayoutUnknownReason

Tests/SwiftLayoutTests/
├── BasicLayoutTests.swift          # runBasicLayout 纯数值单测
├── KnownLayoutTableTests.swift     # 固定表数值
├── ExistentialLayoutTests.swift    # existential / actor 字面值锁定（精确 field-offset 向量）
├── DependencyClosureLayoutTests.swift # 跨依赖闭包：DistributedActorTest 对 runtime vector 自动校验 + resilient 字面值锁定 + 单镜像 partial 回归守卫 + MachOFile 离线路径
├── ObjCAncestorLayoutTests.swift    # 阶段 4：ObjCMembersTest/ObjCBridge 闭包重算对 runtime vector 自动校验（均 [8]）+ 无字段 ObjCBridgeWithProto + 单镜像 partial 回归守卫
├── BuiltinTypeLayoutTests.swift     # builtin 整体布局回退：multi-payload enum + __C.Decimal 索引对 runtime VWT 自动对拍 + resolver 端到端
├── EdgeTypeKindLayoutTests.swift    # 边角函数 kind：cFunctionPointer / objCBlock / escapingObjCBlock = 单指针，对比 thick functionType
├── ObjCProtocolExistentialTests.swift # ObjC 协议 existential：objCProtocolBareName 单元 + 纯/多/混合(any NSCopying[& Swift]) class-bound 布局
├── MultiPayloadEnumStructuralTests.swift # multi-payload enum 结构化兜底：multiPayloadEnumLayout 直接算对 runtime VWT（spare-bits + indirect）
├── GenericInstantiationLayoutTests.swift # 阶段 5：9 个非泛型包裹类型（含具体 bound-generic 字段）完全解析且对 runtime offset 逐字段相等 + GenericArgumentEnvironment 语法替换/降级单测
├── Support/StaticLayoutTestSupport.swift # 闭包/ObjC/builtin 套件共用的 helper（fieldLayout / runtimeFieldOffsets / runtimeValueWitnessSizeStride / assertFullyComputed，单一真源）
└── StaticLayoutVsRuntimeTests.swift# 核心：遍历 fixture 真实类型 static == runtime 逐字段（单镜像）
```

## 核心算法

- **`BasicLayout.compute`**：照搬 `Metadata.cpp:2321-2360`。逐字段 `offset = roundUpToAlignMask(accumulator, fieldAlignMask)`，累加用 **size 不是 stride**，尾部 padding 只进 stride。struct 起点 0；class 起点 = 父类 instance size（= 父类 `size`，根类 16 = `HeapObject`），递归父类；tuple 起点 0。
- **`StaticTypeLayoutResolver`**：按 `Node.Kind` 分派。`builtinTypeName` → KnownLayoutTable / `builtinPrimitiveLayout`（含 `Builtin.DefaultActorStorage` 特判，见下）；`class`/`boundGenericClass` → 一个指针（**不递归字段，天然破环**）；`structure` → **BuiltinTypeLayoutIndex 回退**（C-imported 值类型，见下）或 known 表 / 递归 descriptor；`enum` → EnumLayoutBridge；`protocolList`·`protocolListWithAnyObject`·`protocolListWithClass`·`existentialMetatype` → ExistentialLayoutBridge；`tuple`/`functionType`(thick=2 words)/`cFunctionPointer`·`objCBlock`·`escapingObjCBlock`(单指针=1 word)/`weak`·`unowned`·`unmanaged`(1 word)/`metatype`(thin=0/thick=8) 各自处理；其余抛 `unknown` 降级。memoize 按限定名，`inProgressKeys` 防环兜底。
- **`EnumLayoutBridge`**：no-payload（最小 tag 字节）+ single-payload（含 `Optional`，用 payload 的 extra inhabitants 编码空 case，溢出才加 tag 字节）。`getEnumTagCounts` 公式从 runtime `EnumImpl` 移植。**multi-payload enum** 两条路解析：①首选 `BuiltinTypeLayoutIndex` 整体布局（编译器 emit 的精确值，见下）；②无 builtin descriptor 时**结构化兜底**——`multiPayloadEnumLayout` 复用 `SwiftInspection.EnumLayoutCalculator`（`GenEnum.cpp`/`TypeLowering.cpp` 的离线移植）：payload 区 = 最大 payload case 的尺寸，tag 编码在公共 spare bits（取自该 enum 的 `MultiPayloadEnumDescriptor`，`__swift5_mpenum` 段）或退而附加 extra tag bytes（`calculateTaggedMultiPayload`）。indirect case 的 payload 按单指针计。
- **`BuiltinTypeLayoutIndex`（整体布局回退）**：`__swift5_builtin` 段的 `BuiltinTypeDescriptor` 记录了「reflection 无法结构化推导布局」类型的**整体布局**（size/stride/align/XI/bitwiseTakable）——即**imported C 值类型**（`__C.CGRect`/`__C.Decimal`/…）与 **multi-payload enum**。编译器在**每个反射性引用该类型的镜像**（如把它当存储字段的类型所在镜像）里都 emit 一份，故「使用方镜像」必带。求解器在 `structureLayout`/`enumLayout` 里对**非泛型** `structure`/`enum` 节点先查 `originImage.builtinLayoutIndex`：命中（C 类型、multi-payload enum）即返回该整体布局；未命中（普通 struct/enum 不 emit builtin descriptor）落回结构化路径。对「作为字段」的场景只需整体 size/align/stride，故无需 C struct 内部偏移、也无需 multi-payload 的 spare-bit 分析。descriptor 的 `typeName` 是**符号引用**（裸串为空），故按 demangle 还原的限定名建 key（与求解器查找侧同一格式）。语义同 resilient：「针对这组具体二进制」。
- **`GenericArgumentEnvironment`（具体 bound-generic 实例化作字段，阶段 5）**：`MyBox<Int>` 作字段时，基础 generic descriptor 的字段记录存的是依赖参数（`A` = `dependentGenericParamType(depth,index)`）。做**纯语法 Node 替换**、不调任何 metadata accessor / PWT：从 `boundGeneric*` 节点自带的 `typeList` 按**位置**取具体实参（depth-0 下 index i ↔ typeList[i]），建 `(depth,index)→Node` 映射；解析字段/payload/超类类型前，先 demangle 再用一个 `Node.Rewriter`（Demangling）把节点里的 `dependentGenericParamType` 深度替换为具体实参节点，然后照常 `layout(forTypeNode:)`。深度替换意味着 `(A,B)`、`Pair<A,A>` 等也一并替换，递归再自然重建子环境；`structureLayout`/`enumLayout` 命中 `boundGeneric*` 时按节点建环境、并以**实例化 key**（remangle）memoize，使 `Foo<Int>`/`Foo<String>` 区分缓存与防环（`memoizedInstantiationLayout` 跳过 KnownLayoutTable 探测）。**仅限 depth-0 的类型参数**；任一实参是 value/pack（非纯类型节点）→ 环境整体降级为空（避免位置错配），depth>1 的参数也保持降级。`class Sub<T>: Base<T>` 经 `superclassStartLayout` 先把超类节点按子类环境替换、再据替换后的 `Base<Int>` 建超类环境递归。**纯语法的副带修复**：单 payload 泛型枚举 `enum E<First, Second>{case a(Second)}` 现按 payload 字段记录 + 环境替换取**正确参数**（旧逻辑无条件取 `typeList.first` 会取错第 0 个实参）。
- **`ExistentialLayoutBridge`**：从 runtime `ExistentialTypeInfoBuilder`（`TypeLowering.cpp`）移植。opaque `any P` / 协议组合 = 3-word inline buffer + 1 metadata word + 每协议 1 witness word（`32 + 8N`）；class-bound（`AnyObject` / class 约束协议 / 显式 superclass）= 1 object word + N witness（`8·(1+N)`）；`any Error` = 1 boxed word（8）；existential metatype = 1 metadata word + N witness（`8·(1+N)`，与 class-bound 无关）。是否 class-bound 由各协议 descriptor 的 class 约束决定（`protocolListWithAnyObject`/`WithClass` 结构上即 class-bound）。**marker 协议（`Sendable` 等）已被编译器从 mangled field 名剥离**，故每个列出的协议都计 1 个 witness，无需自行过滤 marker。跨模块协议的 class 约束现经依赖闭包解析（见下）。**imported ObjC 协议**（`any NSCopying` 等，由 `NodeTypeNaming.objCProtocolBareName` 识别 `__C.<Name>` 的 `.protocol` 节点）无 Swift descriptor：它**恒为 class-bound 且不贡献 Swift witness table**（`id<P>` 即单个 class 引用），故强制 existential class-bound 且不计入 witness 数——纯 ObjC existential = 8 字节，混合组合 = 1 object word + N(Swift 协议) witness。
- **ObjC 祖先起点（阶段 4）**：`superclassStartLayout` 中，超类 demangle 出的若是 `__C.<Name>`（ObjC 类，由 `NodeTypeNaming.objCClassBareName` 识别），则该类自身字段从 ObjC 父类的 `instanceSize` 起算（`NSObject` = 8，仅 isa），经第三个 seam `resolveObjCClassInstanceSize(byBareName:)` 取得；**先于** Swift 侧 `resolveType` 判断（ObjC 名在 Swift 类型索引里必然 miss，若先走 `resolveType` 会无谓地把整条依赖闭包索引一遍）。读法用 `ObjCClassIndex`：从 `__objc_classlist` 取 instance `class_ro_t`（in-process 的 realized 类经 `class_rw_t` 回退）的 `instanceSize`——与 `ObjCClass.info(in:).instanceSize` 同值但不解析 methods/ivars；**取 `instanceSize` 而非 `instanceStart`**（后者是 ObjC 类自身首 ivar 起点，cache 上常为 0）。alignmentMask 取 7（指针对齐）。ObjC 类无 Swift descriptor，故只能这样起算；其上的 Swift 字段照常累加。
- **`ImageUniverse` 依赖闭包（阶段 3）**：`singleImage` 之外新增 `dependencyClosure`。求解器始终只经 `resolveType` / `resolveProtocolClassConstraint` / `resolveObjCClassInstanceSize` 三个 seam 查类型，故闭包**不动求解器一行**。root 立即索引，依赖按 BFS 顺序**惰性索引**——仅当某次 resolve 在已索引镜像里全部 miss 时，才推进索引下一个依赖、命中即停（一次 OS 全闭包可达数百镜像，eager demangle 每个会耗数秒；真实查询只命中前几个 Swift 依赖）。便利工厂：`MachOImage` 经活动 dyld（`MachOImage(name: bareName)`）解析，`MachOFile` 经显式 on-disk 路径 + dyld shared cache（cache 一次性按 bare-name 建索引）。详见 [StaticLayoutDependencyClosure.md](StaticLayoutDependencyClosure.md)。

## 验证

`StaticLayoutVsRuntimeTests` 遍历 fixture 二进制（`SymbolTestsCore`）里**每个非泛型 struct/class**，以 runtime metadata accessor 读出的 field-offset vector 为 ground truth，断言静态引擎重算**逐字段相等**（引擎自身从不调用 accessor）。降级类型则断言**已算前缀**与 runtime 前缀一致。`ExistentialLayoutTests` 另以**字面值**锁定 existential / actor 类型的完整 field-offset 向量（如 `ExistentialFieldTest = [0, 40, 80, 120, 128, 136]`），独立于宽泛前缀套件，精确钉住容器尺寸公式。

单镜像当前结果：**147 个类型参与比较，142 个完全算对，0 个 mismatch**；其余 5 个为单镜像下的合理降级（ObjC 祖先 2 个 + 跨模块 resilient/字段 3 个）——其中 ObjC 祖先 2 个与跨模块 3 个均由依赖闭包（阶段 3/4）解析掉，见下。覆盖率下限断言（`comparedCount > 100`、`fullyComputedCount > 140`）防止「全降级静默通过」并锁定 existential + actor + 具体 bound-generic 实例化收敛带来的提升。具体 bound-generic 实例化作字段另由 `GenericInstantiationLayoutTests` 专门验证：9 个非泛型包裹类型（字段含 `GenericStructNonRequirement<Int>`/`<String>`、`Pair<Box<Int>, Int>`、`Box<Int>?`、元组、单/多 payload 泛型枚举、具体泛型超类的子类等）全部**完全解析**且逐字段等于 runtime offset；`GenericArgumentEnvironmentTests` 以手搓 Node 树单测替换与 value 实参降级守卫。**顶层**具体实例化另由 `TopLevelGenericInstantiationLayoutTests` 验证：`fieldLayout(of:genericArguments:)` 对 `GenericStructNonRequirement<Int>`/`<String>` 与 `GenericClassNonRequirement<Int>`、`fieldLayout(forInstantiationMangledName:)` 对一条**二进制里真实的 `GenericStructNonRequirement<Int>` 字段引用**，均**完全解析**且逐字段等于 runtime **特化** metadata 向量（经 accessor 传具体实参 metatype 取真值），并守卫 value 实参降级（裸 `field2: A` 后续字段转 `unknown`，前序 `field1: Double` 仍算对）。

依赖闭包另由 `DependencyClosureLayoutTests` 验证那 3 个跨模块 partial：
- **`DistributedActorTest`**（字段 `Distributed.LocalTestingActorID`）：runtime vector `[16, 112, 128]` 非空，闭包重算与之**自动逐字段相等**——同时覆盖跨模块 struct 字段解析。
- **`ResilientChild` / `ResilientObjCStubChild`**（跨模块 resilient 父类）：runtime vector 为空且**无 `…Wvd` field-offset global**（偏移纯运行时计算），故按从跨模块父类静态 instanceSize 推导的**字面值**锁定——`ResilientChild.extraField = 24`（父 `ResilientBase` = HeapObject 16 + `Int` 8）、`ResilientObjCStubChild.stubField = 16`（父 `Object` 空根类）。
- 另有「单镜像下这 3 类型仍 partial」的**回归守卫**，证明确是闭包把它们解析掉的；以及 **MachOFile 离线路径**（显式 helper 路径 + host cache）解析同样三者。

`ObjCAncestorLayoutTests`（阶段 4）验证直继 ObjC 根类的 Swift 类：
- **`Classes.ObjCMembersTest`（`property: Int`）/ `ObjCClassWrapperFixtures.ObjCBridge`（`label: String`）**：runtime field-offset vector 非空（均 `[8]`，首字段紧接 `NSObject.instanceSize = 8`），闭包重算与之**自动逐字段相等**——同时交叉验证 ObjC `instanceSize` 起点正确。
- **`ObjCBridgeWithProto`（无 stored property）**：runtime vector `[]`，闭包重算同为 `[]` 且无 unknown 字段（ObjC 父类成功解析）。
- **单镜像回归守卫**：单镜像引擎下带字段的两类必为 partial（ObjC 父类 `class_ro_t` 不可达），证明是闭包定位到 libobjc 才解析掉的（无字段的那类因无字段天然「全算对」，不纳入守卫）。

`BuiltinTypeLayoutTests` 验证 builtin 整体布局回退（multi-payload enum + imported C 值类型）：
- **multi-payload enum**（`MultiPayloadEnumTests`/`MultiPayloadEnumTests2`/`FunctionReferenceCaseTest`/`AssociatedValueErrorTest`/`CodableEnumTest`）：`BuiltinTypeLayoutIndex` 按限定名解析出的 size/stride 与 **runtime value-witness table 自动相等**。
- **`__C.Decimal`**（imported C 值类型，无 Swift descriptor）：经 builtin 索引解析出 `size/stride=20、align=4`。
- **resolver 端到端**：之前降级为 unknown 的 `MultiPayloadEnumTests`，现经 resolver 走 builtin 回退算出整体布局，与 runtime VWT 一致。

> 单镜像 `StaticLayoutVsRuntimeTests` 基线仍只遍历 `SymbolTests*` 模块自己定义的**非泛型 struct/class**（且只比对有 field-offset vector 的类型）；C-imported 值类型与 multi-payload enum 作为**字段**时已能解析（见 `BuiltinTypeLayoutTests`），但它们本身不作为该基线的顶层遍历目标。

## 实测发现（与调研的差异）

- **建「限定名 → descriptor」索引必须用 `MetadataReader.demangleContext(for: ContextDescriptorWrapper)`**，而非 `demangleType(descriptor.mangledName)`——后者对 descriptor 自身的 mangledName 解析失败（它不是可 demangle 的类型引用）。
- **`EnumLayoutCalculator.LayoutResult` 不含 enum 整体 `(size, align, stride, XI)`**，故 enum 整体布局由 `EnumLayoutBridge` 自行移植 runtime 公式得出，未复用 `calculateSinglePayload` 的返回值。
- **metatype 区分 thin/thick**：具体 value 类型的 metatype（`Int.Type`）是 thin（0 字节），class 的 metatype（`AnyObject.Type`）是 thick（8 字节）。
- **`Optional<T>` 特判**：其 descriptor 在 stdlib 不在本 image，直接从 payload 类型按 single-payload（1 空 case）计算。
- **marker 协议在 mangled field 名里已被剥离**：`any (P & Sendable)` 的 field 类型 demangle 后只剩 `P`（`sendableComposition` 实测），故 witness 计数直接数协议个数即可，无需识别/排除 marker。
- **existential class-bound 不能只看 Node 形态**：`any ClassBoundProtocolTest` 的 Node 是普通 `ProtocolList`（非 `WithAnyObject`），但结果是 16 字节 class existential。必须解析协议 descriptor 的 class 约束（`ProtocolContextDescriptorFlags.classConstraint`）。为此 `ImageReference` 额外建「协议限定名 → class 约束」索引；协议在 `__swift5_protos`（经 `protocolDescriptors`），与类型的 `__swift5_types`（`contextDescriptors`）是**不同 section**，须分别遍历。
- **`Builtin.DefaultActorStorage` = 96 字节、对齐 16**：`NumWords_DefaultActor`(12) × pointer size，对齐为 pointer 对齐的 2 倍。本 fixture 未 emit 其 builtin descriptor，故在 `builtinPrimitiveLayout` 按常量给出，移植自 runtime reflection lowering 的 `getDefaultActorStorageTypeInfo()`。actor 类型（如 `ActorTest = [16, 112]`）由此完全解析。
- **`TypeLowering.cpp`（RemoteInspection）是官方离线 lowering，是本引擎的权威对照**：existential 与 default-actor 公式均以它为准，并经 runtime accessor 真值交叉验证。
- **`MachOFile.imagePath` 返回的是 install name（LC_ID_DYLIB），不是磁盘路径**：框架的 install name 是 `@rpath/Foo.framework/.../Foo`。故 `MachOFile` 闭包的显式 search path 不能由已加载 root 的 `imagePath` 字符串替换得出，须另给真实磁盘路径；依赖名匹配统一归一到 **bare name**（末段去扩展名，即 `MachOImage(name:)` 的语义）。
- **闭包须容忍缺段**：纯 ObjC/C dylib（libobjc、libsystem_*）无 `__swift5_types`/`__swift5_protos`，许多镜像无 `__swift5_builtin`。`ImageReference`/`BuiltinTypeLayoutIndex` 把 `sectionNotFound` 视作「该镜像无此类内容」返回空，而非让整个闭包构建失败。
- **依赖闭包须惰性索引**：`SymbolTestsCore` 的传递闭包实测达 **551 个镜像**；若 eager 索引（逐镜像 demangle 全部 descriptor）约 **13 秒**。改为 root 立即索引、依赖按 BFS 顺序仅在 resolve miss 时逐个增量索引、命中即停后，闭包构建（收集 551 镜像）约 0.8 秒，整套闭包测试数秒内完成。一次「真 miss」（名字哪都没有）会触发把整列表索引一遍，之后全 O(1)。
- **resilient 子类无 field-offset global**：`ResilientChild`/`ResilientObjCStubChild` 既无 runtime field-offset vector（`fieldOffsets(in:)` 返回 `[]`），也**不 emit `…Wvd` field-offset global**（偏移完全运行时计算）。故其验证只能走「从跨模块父类静态 instanceSize 推导的字面值」，且语义是「针对闭包里这组具体二进制」。
- **ObjC 起点取 `instanceSize` 而非 `instanceStart`，且 realized 类不可读 `classROData`（阶段 4 的关键坑）**：调研单点 finding 主推「读 `class_ro_t.instanceStart`」，实测**否决**——(1) `instanceStart` 是 ObjC 类自身首 ivar 起点（= 其父类大小），dyld cache 上常写 0；Swift 子类字段起点应是父类 **`instanceSize`**（`NSObject` = 8）。(2) **in-process 的 `NSObject` 是 realized 类**，`classROData(in: MachOImage)` 返回 `nil`（`data` 指向 `class_rw_t`），须经 `classRWData → classROData`（或 `ext.classROData`）回退取 instance ro；offline 的 cache `MachOFile` 则 `classROData` 直接可读。唯一在 in-process 与 cache 两条 reader 上都正确且一致的值是 instance `class_ro_t.instanceSize`（= `ObjCClass.info(in:).instanceSize`，但 `ObjCClassIndex` 直接读 ro、不解析 methods/ivars/metaclass，故更轻）。
- **ObjC 索引随 Swift 索引同步惰性折入，无额外扫描**：`resolveObjCClassInstanceSize` 复用 `resolveType` 的 `indexNextDependency` 折入机制（ObjC 索引在 `ImageReference.init` 里一并构建、`mergeIndexes` 一并合并）。又因 ObjC 父类在 `superclassStartLayout` 里**先于** Swift `resolveType` 判断，ObjC 名不会触发「Swift 全 miss → 折满 551 镜像」；折到 libobjc 命中 `NSObject` 即停，比旧路径（ObjC 名走 `resolveType` 折满全闭包再抛错）更快。
- **`objc.classes64` / `info(in:)` 是 `MachOFile`/`MachOImage` 具体重载（非协议泛型）**：故 `ObjCClassIndex` 与 `ImageReference` 的 ObjC 索引构建须按 `as? MachOImage` / `as? MachOFile` 向下转型分派，复刻 `ImageUniverse+DependencyClosure` 的 `where MachO == …` 拆分写法。
- **`BuiltinTypeDescriptor.typeName` 是符号引用，裸串为空——必须 demangle 才有 key**：`__swift5_builtin` 段实测**不含** `Builtin.*` 条目，全是 imported C 值类型（`__C.Decimal`/`__C.CGRect`/…）与 multi-payload enum；其 `typeName` 指向 context descriptor（相对指针），`typeString` 为空字符串。旧 `BuiltinTypeLayoutIndex` 按 `typeString` 建 key，把全部条目塞进 key `""`（互相覆盖）→ 索引等于失效、且只在 `builtinTypeName` 分支被查（而该段无 `Builtin.*`），实为死代码。修复：用 `MetadataReader.demangleType` 还原成限定名（`__C.Decimal` / `SymbolTestsCore.Enums.MultiPayloadEnumTests`）建 key。
- **builtin descriptor 由「使用方」镜像 emit，故查 `originImage`**：编译器在每个**反射性引用**该类型的镜像里都 emit 一份 builtin descriptor（实测 fixture 自己就带 `__C.Decimal`、Foundation 也带一份）。所以解析某字段类型时查**字段所属镜像**（`originImage`，求解器已线程化）的 builtin 索引正中靶心，无需跨镜像合并。
- **builtin 回退限非泛型节点**：builtin key 是 generic-argument-free 的限定名（`nominalQualifiedName` 会剥泛型实参），故只对 `node.kind == .structure`/`.enum`（非 `boundGeneric*`）查 builtin，避免 `Foo<Int>` 与 `Foo<String>` 撞到同一 key；`Optional<T>` 等泛型枚举继续走结构化/payload 路径。
- **泛型替换：`MetadataReader.demangleType` 返回的是 `.type`-包裹节点，但求解器分派会先解包**：求解器 `layout(forTypeNode:)` 先 `unwrappedType` 再分派，故 `structureLayout` 收到的是裸 `boundGenericStructure`；而 `superclassStartLayout` 拿到的超类节点是**刚 demangle 的 `.type`-包裹**节点。`GenericArgumentEnvironment.make` 若不容忍 `.type` 包裹，对超类节点会 `kind == .type` → 误判非泛型 → 返回空环境 → 超类字段 `A` 不替换而降级（具体泛型超类子类用例实测踩到）。修复：`make` 先解一层 `.type` 再判 `boundGeneric*`，使「已解包」与「刚 demangle」两侧建出同一环境。
- **泛型实例化的 memoize/防环 key 必须含实参，且要绕开冻结表**：原 `memoizedNominalLayout` 按裸限定名做 key 且首步查 `KnownLayoutTable`——对 `Foo<Int>`/`Foo<String>` 会撞同 key（裸名相同）。故 `boundGeneric*` 改用 `memoizedInstantiationLayout`（key = remangle 后的实例化名，**跳过**冻结表探测）。同时 `structureLayout`/`enumLayout` 仍在建环境前**先按裸名查冻结表**：`Array<Int>`/`UnsafePointer<Double>` 等 stdlib 泛型布局与实参无关、靠裸名命中冻结表（指针大小）；若直接走实例化 key 会漏表并尝试结构化展开 stdlib 内部存储而失败（单镜像下其 descriptor 也不可达）。`Range<Int>` 不在冻结表，单镜像下降级、依赖闭包下方可结构化解析。
- **multi-payload 结构化：`EnumLayoutCalculator.LayoutResult` 无 size/stride，须自行推导**：`calculateMultiPayload`/`calculateTaggedMultiPayload` 返回的是逐 case 投影 + `tagRegion`/`payloadRegion`/`numTags`，**没有**整体 size/stride。推导：extra tag bytes = `tagRegion` 中**起点 ≥ payloadSize** 的那段长度（spare-bits 策略下 tagRegion 落在 payload 内部 → 0；tagged/混合策略下落在 payload 之后）；`size = payloadSize + extraTagBytes`，`stride = roundUp(size, maxPayloadAlignMask)`，`align = maxPayloadAlignMask`。payloadSize/align 由遍历所有 payload case、解析各 payload 类型取 max 得出。实测对 6 个 fixture multi-payload enum（含 spare-bits 17/24、21/24、25/32 与 indirect 8/8、9/16）与 runtime VWT 逐一精确吻合。

## 已知降级（当前范围外）

| 形态 | 原因 | 归属阶段 |
|---|---|---|
| 泛型类型**自身**作顶层且**未提供实参**（裸 `T`） | 无具体实参时字段里的 `T` 依赖实例化；**提供具体实参后已可算**（见「后续工作」的「顶层具体实例化」） | 裸泛型不可静态定（本质如此） |
| value/pack 泛型实参（`Foo<3, Int>` / `each T`） | 环境只建 depth-0 纯类型实参映射，value/pack 整体降级以防位置错配 | 范围外，按字段降级 |
| depth > 0 的嵌套泛型上下文参数 | 当前环境只映射 depth-0 | 范围外，按字段降级 |
| 无 builtin descriptor 的 multi-payload enum / C 类型 | 编译器未对该类型 emit builtin（如反射裁剪、未被反射性引用） | 罕见，按字段降级 |
| 少数 kind：`dependentMemberType`(关联类型)、`opaqueType`(`some P` 存储)、`silBoxType` | 需 witness/实例化信息或编译器内部类型 | 边角，按字段降级 |

> **已落地（原降级，现已解析）**：existential（`any P` / 协议组合 / `AnyObject` / `any Error` / `existentialMetatype` / **imported ObjC 协议 `any NSCopying`**）、actor 默认存储（`Builtin.DefaultActorStorage`）、边角函数 kind（C 函数指针 / ObjC block）、**跨模块字段 / 父类 / 协议（阶段 3 依赖闭包）**——含跨模块 resilient 父类（按「具体二进制」语义静态重算）、**ObjC 祖先类（阶段 4）**——Swift 类直继 `NSObject` 等 ObjC 根类时自身字段从 ObjC 父类 `instanceSize` 起算（经依赖闭包内的 libobjc 定位）、**multi-payload enum 与 imported C 值类型（builtin 整体布局）**——经 `BuiltinTypeLayoutIndex` 取编译器 emit 的整体布局，以及 **具体 bound-generic 实例化作字段（阶段 5）**——经 `GenericArgumentEnvironment` 纯语法 Node 替换（depth-0 类型参数）。详见上文「核心算法」「验证」「实测发现」。

## 后续工作（扩展点已预留）

- **~~阶段 5 具体 bound-generic 实例化作字段~~（已完成）**：经 `GenericArgumentEnvironment` 纯语法 Node 替换实现，见上文「核心算法」。落地时确认**无需** `SwiftGenericSupport` 共享层——替换只需从 `boundGeneric*` 节点直接读 `(depth,index)` 与节点自带的 `typeList`（按位置映射），用不到 `GenericSpecializer` 的描述符泛型签名/需求枚举/key-argument 向量；故未引入跨模块重构。后续若 SwiftLayout 需要运行期驱动的特化再议。剩余不可静态定：顶层泛型类型自身未实例化的 `T`、value/pack 实参、depth>0 嵌套泛型上下文（见「已知降级」）。
- **~~顶层具体泛型实例化的逐字段 offset~~（已完成）**：把阶段 5 的 `GenericArgumentEnvironment` 替换从「字段场景」**对称扩展**到「顶层请求场景」。新增两个公开入口：`StaticLayoutCalculator.fieldLayout(of:genericArguments:)`（descriptor + 具体实参 `Node`，按 depth-0 位置建环境）与 `fieldLayout(forInstantiationMangledName:)`（二进制里的 `Foo<Int>` 引用：demangle → 按限定名解析 descriptor → 经 `make(forBoundGenericNode:)` 建环境，故跨模块实例化在其**定义镜像**上展开）。实现上把富信息逐字段路径（`accumulateFieldLayout` → `AggregateFieldLayout`，**带逐字段降级**）线程化 `environment`（默认 `.empty` ⇒ 非泛型行为逐字节不变），并把私有 `fieldLayout(ofStruct:/ofClass:)` 抽出 `in image:` 以支持跨镜像；新增 `GenericArgumentEnvironment.make(forDepthZeroTypeArguments:)` 直接从实参 Node 列表建环境。仅 depth-0 **类型**参数；value/pack、depth>0、裸泛型仍按字段降级。**未**引入对 `SwiftSpecialization` 的依赖——runtime 真值在测试侧用底层 accessor 传具体实参 metatype 取得（无约束泛型无需 PWT）。
- **multi-payload enum 的 payload 内部偏移（可选，未做）**：当前结构化路径只给整体 size/stride/align（已满足「作为字段」需求，且对全部 fixture multi-payload enum 与 runtime VWT 逐一吻合）。若需逐 case 的 payload 投影/tag 编码细节，`EnumLayoutCalculator.LayoutResult.cases` 已含，可后续暴露。multi-payload enum 的精确 extra inhabitants 当前结构化路径记 0（builtin 路径给精确值）。
- **`@rpath` 完整展开**：`MachOFile` 闭包 MVP 靠 dyld cache bare-name + 显式路径覆盖；完整 `@rpath`/`@loader_path`/`@executable_path` 展开（读 `LC_RPATH` + 相对 root 定位）未做，调用方可预先展开为绝对路径。
- **路径 A（读 vector）未实现**：runtime accessor 已是更强的 ground truth，`FieldOffsetVectorReader` 未单独建。如需纯 MachOFile 的交叉校验可后补。
