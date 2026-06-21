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
├── BuiltinTypeLayoutIndex.swift    # __swift5_builtin 按类型名索引（数值真值）
├── NodeTypeNaming.swift            # 从 demangle Node 提取限定类型名 / 协议限定名（忽略泛型参数）
├── StaticTypeLayoutResolver.swift  # 递归求解器：Node.Kind 分派 + memoization + 防环
├── EnumLayoutBridge.swift          # enum/Optional 布局（getEnumTagCounts 公式移植）
├── ExistentialLayoutBridge.swift   # existential 容器 + existential metatype（ExistentialTypeInfoBuilder 移植）
├── ImageReference.swift            # 单镜像：类型限定名 → descriptor 索引 + 协议 class 约束索引 + builtin 索引
├── ImageUniverse.swift             # singleImage 工厂；类型/协议解析 seam；多镜像扩展点
├── AggregateFieldLayout.swift      # 结果类型 + FieldLayoutEntry + FieldResolution
├── StaticLayoutCalculator.swift    # 顶层 API + 逐字段降级
└── LayoutResolutionError.swift     # 内部错误 + LayoutUnknownReason

Tests/SwiftLayoutTests/
├── BasicLayoutTests.swift          # runBasicLayout 纯数值单测
├── KnownLayoutTableTests.swift     # 固定表数值
├── ExistentialLayoutTests.swift    # existential / actor 字面值锁定（精确 field-offset 向量）
└── StaticLayoutVsRuntimeTests.swift# 核心：遍历 fixture 真实类型 static == runtime 逐字段
```

## 核心算法

- **`BasicLayout.compute`**：照搬 `Metadata.cpp:2321-2360`。逐字段 `offset = roundUpToAlignMask(accumulator, fieldAlignMask)`，累加用 **size 不是 stride**，尾部 padding 只进 stride。struct 起点 0；class 起点 = 父类 instance size（= 父类 `size`，根类 16 = `HeapObject`），递归父类；tuple 起点 0。
- **`StaticTypeLayoutResolver`**：按 `Node.Kind` 分派。`builtinTypeName` → KnownLayoutTable / BuiltinTypeLayoutIndex（含 `Builtin.DefaultActorStorage` 特判，见下）；`class`/`boundGenericClass` → 一个指针（**不递归字段，天然破环**）；`structure` → known 表或递归 descriptor；`enum` → EnumLayoutBridge；`protocolList`·`protocolListWithAnyObject`·`protocolListWithClass`·`existentialMetatype` → ExistentialLayoutBridge；`tuple`/`functionType`(2 words)/`weak`·`unowned`·`unmanaged`(1 word)/`metatype`(thin=0/thick=8) 各自处理；其余抛 `unknown` 降级。memoize 按限定名，`inProgressKeys` 防环兜底。
- **`EnumLayoutBridge`**：no-payload（最小 tag 字节）+ single-payload（含 `Optional`，用 payload 的 extra inhabitants 编码空 case，溢出才加 tag 字节）。`getEnumTagCounts` 公式从 runtime `EnumImpl` 移植。multi-payload 首期降级。
- **`ExistentialLayoutBridge`**：从 runtime `ExistentialTypeInfoBuilder`（`TypeLowering.cpp`）移植。opaque `any P` / 协议组合 = 3-word inline buffer + 1 metadata word + 每协议 1 witness word（`32 + 8N`）；class-bound（`AnyObject` / class 约束协议 / 显式 superclass）= 1 object word + N witness（`8·(1+N)`）；`any Error` = 1 boxed word（8）；existential metatype = 1 metadata word + N witness（`8·(1+N)`，与 class-bound 无关）。是否 class-bound 由各协议 descriptor 的 class 约束决定（`protocolListWithAnyObject`/`WithClass` 结构上即 class-bound）。**marker 协议（`Sendable` 等）已被编译器从 mangled field 名剥离**，故每个列出的协议都计 1 个 witness，无需自行过滤 marker。无法在单镜像内解析 class 约束的协议（跨模块）会降级该字段，与 runtime lowering 的 `markInvalid` 一致。

## 验证

`StaticLayoutVsRuntimeTests` 遍历 fixture 二进制（`SymbolTestsCore`）里**每个非泛型 struct/class**，以 runtime metadata accessor 读出的 field-offset vector 为 ground truth，断言静态引擎重算**逐字段相等**（引擎自身从不调用 accessor）。降级类型则断言**已算前缀**与 runtime 前缀一致。`ExistentialLayoutTests` 另以**字面值**锁定 existential / actor 类型的完整 field-offset 向量（如 `ExistentialFieldTest = [0, 40, 80, 120, 128, 136]`），独立于宽泛前缀套件，精确钉住容器尺寸公式。

当前结果：**138 个类型参与比较，133 个完全算对，0 个 mismatch**；其余 5 个为下列合理降级（ObjC 祖先 / 跨模块 resilient / 跨模块字段）。覆盖率下限断言（`comparedCount > 100`、`fullyComputedCount > 128`）防止「全降级静默通过」并锁定 existential + actor 收敛带来的提升。

> 单镜像阶段只验证 fixture 模块（`SymbolTests*`）自己定义的类型；跨模块 C-imported 类型（如 `__C.Decimal`，其 C bitfield 布局不反映在 Swift field records 里）排除在外，留待依赖闭包阶段。

## 实测发现（与调研的差异）

- **建「限定名 → descriptor」索引必须用 `MetadataReader.demangleContext(for: ContextDescriptorWrapper)`**，而非 `demangleType(descriptor.mangledName)`——后者对 descriptor 自身的 mangledName 解析失败（它不是可 demangle 的类型引用）。
- **`EnumLayoutCalculator.LayoutResult` 不含 enum 整体 `(size, align, stride, XI)`**，故 enum 整体布局由 `EnumLayoutBridge` 自行移植 runtime 公式得出，未复用 `calculateSinglePayload` 的返回值。
- **metatype 区分 thin/thick**：具体 value 类型的 metatype（`Int.Type`）是 thin（0 字节），class 的 metatype（`AnyObject.Type`）是 thick（8 字节）。
- **`Optional<T>` 特判**：其 descriptor 在 stdlib 不在本 image，直接从 payload 类型按 single-payload（1 空 case）计算。
- **marker 协议在 mangled field 名里已被剥离**：`any (P & Sendable)` 的 field 类型 demangle 后只剩 `P`（`sendableComposition` 实测），故 witness 计数直接数协议个数即可，无需识别/排除 marker。
- **existential class-bound 不能只看 Node 形态**：`any ClassBoundProtocolTest` 的 Node 是普通 `ProtocolList`（非 `WithAnyObject`），但结果是 16 字节 class existential。必须解析协议 descriptor 的 class 约束（`ProtocolContextDescriptorFlags.classConstraint`）。为此 `ImageReference` 额外建「协议限定名 → class 约束」索引；协议在 `__swift5_protos`（经 `protocolDescriptors`），与类型的 `__swift5_types`（`contextDescriptors`）是**不同 section**，须分别遍历。
- **`Builtin.DefaultActorStorage` = 96 字节、对齐 16**：`NumWords_DefaultActor`(12) × pointer size，对齐为 pointer 对齐的 2 倍。本 fixture 未 emit 其 builtin descriptor，故在 `builtinPrimitiveLayout` 按常量给出，移植自 runtime reflection lowering 的 `getDefaultActorStorageTypeInfo()`。actor 类型（如 `ActorTest = [16, 112]`）由此完全解析。
- **`TypeLowering.cpp`（RemoteInspection）是官方离线 lowering，是本引擎的权威对照**：existential 与 default-actor 公式均以它为准，并经 runtime accessor 真值交叉验证。

## 已知降级（首期范围外）

| 形态 | 原因 | 归属阶段 |
|---|---|---|
| ObjC 祖先 / ObjC 成员 | 需读 ObjC `class_ro_t` 起算 | 阶段 4 |
| 跨模块 resilient 字段 / 父类 | 需递归到定义镜像 | 阶段 3 |
| 泛型参数（`dependentGenericParamType`） | 需参数替换 | 阶段 5 |
| multi-payload enum | 需接 `SpareBitAnalyzer` | Phase 2.5 |
| ObjC 协议 existential / 跨模块协议 existential | 需读 ObjC 协议 / 跨镜像协议 class 约束 | 阶段 3/4 |

> **已落地（原降级，现已解析）**：existential（`any P` / 协议组合 / `AnyObject` / `any Error` / `existentialMetatype`）与 actor 默认存储（`Builtin.DefaultActorStorage`）。详见上文「核心算法」与「实测发现」。

## 后续工作（扩展点已预留）

- **阶段 3 跨依赖闭包**：求解器全程经 `ImageUniverse.resolveType(byQualifiedTypeName:)` / `resolveProtocolClassConstraint(byQualifiedTypeName:)` 编程，单镜像由 `ImageUniverse.singleImage` 填充；阶段 3 仅需新增 `dependencyClosure` 工厂（递归 `LC_LOAD_DYLIB` + dyld cache，扫各镜像 `__swift5_types` + `__swift5_protos` 建全局索引），**求解器代码零改动**。届时跨模块协议的 class 约束亦可解析，existential 不再因跨模块协议降级。
- **阶段 4 ObjC 祖先**：`superclassStartLayout` 已为 ObjC 父类预留降级分支；接 MachOObjCSection 的 `ObjCClassRODataProtocol` 读 `instanceSize` 作起点。
- **阶段 5 泛型**：`dependentGenericParamType` 分派点已就位，补参数替换逻辑即可。
- **existential 已落地**：opaque / class-bound / error / existential metatype 均已支持（见上）。残留仅 ObjC 协议 existential 与跨模块协议 existential（依赖阶段 3/4 的协议解析）。
- **路径 A（读 vector）未实现**：runtime accessor 已是更强的 ground truth，`FieldOffsetVectorReader` 未单独建。如需纯 MachOFile 的交叉校验可后补。
