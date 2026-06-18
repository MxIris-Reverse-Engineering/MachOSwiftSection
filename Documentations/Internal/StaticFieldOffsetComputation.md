# 静态计算 Field Offset 调研

> 面向 `feature/swift-diffing` 的静态 ABI 分析需求：在**不加载进程、不调用 runtime** 的前提下，从 Mach-O 文件离线拿到准确的 stored-property field offset。本文是设计前的调研与实现指引，覆盖 fixed-layout、resilient、跨依赖闭包、ObjC 祖先、泛型五个维度。
>
> Swift runtime 源码行号针对 **Swift 6.3.2** checkout（`/Volumes/SwiftProjects/swift-project`）。本项目代码路径相对仓库根。

## 0. 问题与结论速览

诉求：非泛型类型「通过符号能找到 metadata，但 metadata 里的 field offset 不准、运行时会修正」，想离线把准确值算出来。

调研后的核心判断：**「不准」只发生在少数情况，绝大多数非泛型类型的 field offset 在二进制里就是准确终值，正确读出即可，根本不用模拟。** 只有含 resilient 字段 / resilient 或 ObjC 祖先的类型才是占位值、需要离线模拟运行时算法。而被模拟挡住的 resilient / ObjC 死角，可以靠**遍历依赖闭包**递归到定义模块解决——使整套计算在依赖完整时**纯静态闭合**。

| 维度 | 结论 | 难度 |
|---|---|---|
| fixed-layout 非泛型（单镜像） | 直接读 metadata 的 field-offset vector，准确终值 | 几乎零 |
| 含 resilient 字段、但字段类型在本镜像内可解析 | 移植 `performBasicLayout` 重算 | 低-中 |
| resilient 字段跨模块 | 遍历依赖闭包，递归到定义镜像 | 中（已有 dyld cache 取镜像底座） |
| ObjC 祖先 class | 用 MachOObjCSection 读 class_ro_t，模拟 ObjC ivar 布局 | 中（库已集成） |
| 泛型 | 地基与非泛型共享；增量主要是参数替换 + associated type | 中→高（associated type 是唯一硬骨头） |

---

## 1. 核心认识：field offset 的三种情况

「非泛型 metadata 里 field offset 不准」这个前提要拆细。按编译器实际行为分三种：

| 情况 | 二进制里的 field offset | 处理 |
|---|---|---|
| **(A) fixed-layout 非泛型**（字段全是 `Int`/指针/`Bool`/同模块 fixed struct 等） | 编译器**已写死真值**到 metadata 的 field-offset vector | **直接读，无需模拟** |
| **(B) 含 resilient 字段 / resilient 或 ObjC 祖先**的非泛型类型 | 占位：struct vector 写 **0**；class 走 `NonConstantDirect`、`Wvd` global 是占位/旧值 | **离线模拟算法重算** |
| **(C) 泛型** | metadata vector 由运行时按实例填（`ConstantIndirect`） | 见 §7 |

编译器侧判定依据：

- **Class** — `FieldAccess` 枚举（`lib/IRGen/ClassLayout.h:30-41`）+ `getFieldAccess`（`lib/IRGen/GenClass.cpp:452-478`）：
  - `ConstantDirect`：整链 fixed-size + 非 resilient + 无 ObjC resilient 祖先 → 偏移编译期常量，**二进制即终值**。
  - `NonConstantDirect`：有 resilient 成员 / resilient 缺失成员 / ObjC 祖先 → 偏移存 field-offset global（mangling 后缀 `Wvd`），**运行时初始化、二进制占位**。
  - `ConstantIndirect`：泛型布局，仅 (C)。
- **Struct** — `addFieldOffset`（`lib/IRGen/GenMeta.cpp:5885-5900`）：fixed 字段 → `B.add(offset)` 写常量进 metadata vector；否则 `B.addInt(Int32Ty, 0)` 写 **0 占位**，靠运行时 `swift_initStructMetadata` 回填。

### 静态分流信号：`MetadataInitialization` kind

不需要重做编译器判定——类型描述符里有现成的静态信号。`TypeContextDescriptorFlags`（`Sources/MachOSwiftSection/Models/Type/TypeContextDescriptorFlags.swift`，2 位宽字段）区分：

- `none` → metadata 完整、编译期静态化 → **vector 是真值，直接读**；
- `singleton` → 需运行时 `swift_initStructMetadata` / `initClassFieldOffsetVector` 完成 → **vector 是占位，要算**；
- `foreign` → C/ObjC 互操作，另算。

本项目已暴露 `SingletonMetadataInitialization` / `ForeignMetadataInitialization` 模型（`Sources/MachOSwiftSection/Models/Metadata/MetadataInitialization/`）及 `Struct.singletonMetadataInitialization` / `.foreignMetadataInitialization`。

> **第 0 步必须实测验证**：`MetadataInitialization == none` 的 fixed 类型，在 MachOFile（非 InProcess）上下文下读出来的 vector 是否 == 运行期值。两份子调研在此有分歧（一份认为 fixed struct vector 编译期写死、可静态读；另一份认为静态镜像里是 0 或 relocation）。本项目 `StructMetadata.fieldOffsets(for:in:)` 已有 MachOFile overload，用现有 fixture 二进制 + `otool` 即可确认。**这条结论是整个方案 (A) 类捷径的地基。**

---

## 2. 运行时算法（要模拟时照搬）

核心在 `swift/stdlib/public/runtime/Metadata.cpp`，struct / class / tuple 共用 `performBasicLayout`（`Metadata.cpp:2321-2360`）：

```
offset_accumulator = 起点          // struct: 0; class: 父类 instanceSize（根类 = sizeof(HeapObject) = 16）
alignMask = 起点对齐
for 每个字段 i:
    fieldAlignMask = 字段类型.alignMask
    offset = (offset_accumulator + fieldAlignMask) & ~fieldAlignMask   // roundUpToAlignMask 向上对齐
    fieldOffsets[i] = offset
    offset_accumulator = offset + 字段类型.size      // ★ 累加用 size，不是 stride
    alignMask = max(alignMask, fieldAlignMask)
size   = offset_accumulator
stride = max(1, roundUpToAlignMask(size, alignMask))  // 尾部 padding 只进 stride，不进 size
```

- **Struct** — `swift_initStructMetadata`（`Metadata.cpp:2924-2955`）。vector 元素 `uint32_t`，起点 0。`swift_cvw_initStructMetadataWithLayoutString`（`:2957-3074`）只是带 layout-string 的变体，field offset 计算 100% 相同。
- **Class** — `initClassFieldOffsetVector`（`Metadata.cpp:3755-3842`）。vector 元素 `uintptr_t`（8 字节），起点是**父类 `getInstanceSize()`**（根类 16 = isa 指针 + refcount word，`getInitialLayoutForHeapObject` @ `:2304-2308`）→ **必须递归算父类**。入口链 `swift_initClassMetadata`（`:4188`）→ `_swift_initClassMetadataImpl`（`:4087-4186`）。
- **对齐 / value witness flags** — alignment 用 mask 存（低 8 位，`align = mask + 1`），`ValueWitnessFlags`（`include/swift/ABI/MetadataValues.h:167-181`）。`roundUpToAlignMask`（`include/swift/Basic/MathUtils.h:38`）。
- **size 来源** — 运行时统一从字段类型 metadata 的 VWT 前 4 个 word（`TargetTypeLayout = {size, stride, flags, extraInhabitantCount}`，`include/swift/ABI/ValueWitnessTable.h:280-306`）取。离线要复刻成「mangled name → (size, align, stride, XI)」求解器（见 §3）。

本项目目前**零 aggregate-layout 实现**：`EnumLayoutCalculator` 只算 enum 的 tag/payload bit 投影，不算 struct/class size 累加。这是新计算器的主体，但算法本身照搬即可。

---

## 3. 字段 size/alignment 来源（分层）

离线要把「mangled name → (size, alignment, stride, extraInhabitants)」做成递归求解器，数据源分层：

1. **硬编码固定布局表（主力）**：`Int/UInt/Int64/Double/裸指针/任意 class 引用 = 8B@8`；`Int32/Float = 4B`；`Bool/Int8 = 1B`；`Int128 = 16B`；`String = 16B`。这些 ABI 永久冻结，照抄 runtime 的 known-layout 表。
2. **`__swift5_builtin` 的 `BuiltinTypeDescriptor`**：已确认静态内嵌 `size` / `alignmentAndFlags` / `stride` / `numExtraInhabitants`（`Sources/MachOSwiftSection/Models/BuiltinType/BuiltinTypeDescriptor.swift:6-12`，`alignment = alignmentAndFlags & 0xFFFF`，`isBitwiseTakable = (alignmentAndFlags >> 16) & 0x1`）。仅覆盖编译器实际发射的 builtin 原语，不能当唯一来源。
3. **嵌套 struct / enum** → 递归到目标 descriptor 重新跑 §2 算法。enum 复用 `EnumLayoutCalculator`，但要把它的 payload-size / XI 输入从「InProcess VWT」改接到本求解器。
4. **resilient / 跨模块字段** → 见 §4（遍历依赖闭包递归到定义镜像）。

> 现有唯一的「mangled name → 具体类型 size」路径是 `RuntimeFunctions.getTypeByMangledNameInContext`（`Sources/MachOSwiftSection/Runtime/RuntimeFunctions.swift`），是 **InProcess-only** runtime 函数。`PrimitiveTypeMapping` 只给类型名映射、**不给数值**。所以静态侧的数值化求解器是从零新建。

---

## 4. 跨依赖闭包：消解 resilient 跨模块死角

resilient 的本质是「编译当前二进制时不知道字段布局，但运行期布局由**定义该类型的模块**决定」。而定义模块的二进制里，那个类型对它自己往往是 fixed-layout（`MetadataInitialization == none`），field-offset vector 是编译期写死的真值。所以：

- 大量 resilient 字段类型，递归到它的定义二进制后**直接读 vector，不用模拟**；
- 只有「resilient 类型又层层依赖上游 resilient 类型」才逐层模拟，且在闭包内闭合；
- 链条终止于 fixed 叶子（§3 的固定表 / builtin）。

这正是 Swift runtime 启动时跨所有已加载镜像做的事（扫每个镜像的 `__swift5_types` 建全局类型索引，`swift_getTypeByMangledNameInContext` 查它）。我们在文件层面做同一件事。

### 已有基础设施

- **按依赖名解析镜像**：`Sources/MachOExtensions/DyldCache+.swift` 的 `machOFile(by mode:)` —— 按 install name / image name 从 dyld shared cache 捞 `MachOFile`。系统 Swift 库、Foundation、SwiftUI 等都在 cache 里，这条路已通。
- **符号索引**：`Sources/MachOSymbols/SymbolIndexStore.swift` —— 按 name/offset 建索引。
- **ReadingContext 抽象**：`MachOContext` 已把「从哪个镜像读」参数化，扩展成多镜像顺理成章。

### 需新建三块

1. **依赖闭包遍历器**：从主 `MachOFile` 的 `LC_LOAD_DYLIB` 列表出发，递归解析（含 `@rpath` / `@loader_path` / `@executable_path` + shared cache + 文件系统），构建 `[install name → MachOFile]` 镜像宇宙。
2. **跨镜像全局类型索引**：扫闭包内**所有**二进制的 `__swift5_types`，建 `fully-qualified type name → (MachOFile, descriptor)` 索引。跨模块字段在 field record 里是**纯文本 mangled name**（symbolic reference 只用于同编译单元内），解析即「文本 mangled name → 查全局索引」。这就是 `swift_getTypeByMangledNameInContext` 的纯静态等价物。
3. **多镜像递归求解器**：算某类型布局时，字段可能落在别的镜像，求解器要携带「当前类型属于哪个 `MachOFile`」，递归切换 `MachOContext`。配合 memoization 缓存 `mangled name → TypeLayout`（class 引用是指针、不递归 size，天然打破环；struct 编译器保证无环）。

### 剩余真死角

- **依赖确实缺失**：私有 / 未随包分发的 dylib、weak-link 且运行时才补的库 → 闭包不完整就标 `unknown`。
- **泛型实例化** → §7。

---

## 5. ObjC 祖先 class

本项目**已依赖 MachOObjCSection**（`Package.swift:122`，`useCustomObjCSection=true`），已用于 `SwiftInspection/ClassHierarchyDumper.swift`、`TypeIndexing/ObjCInterfaceIndexer.swift`。它提供 `ObjCIvarListProtocol`（ivar list）、`ClassROData`（class_ro_t），能静态读 ObjC class 的 **instanceStart / instanceSize / ivars**。

对应运行时算法：`initClassFieldOffsetVector`（`Metadata.cpp:3771-3776`）对 ObjC 父类**从 `rodata->InstanceStart` 起算、对齐 `0xF`**。解法：

1. Swift class 继承 ObjC class → 读 ObjC 父类 class_ro_t 的 `instanceSize`，作为 Swift 子类字段布局起点；
2. ObjC 父类自己又继承别的 ObjC 类（跨二进制）→ 用 §4 依赖闭包递归读父类二进制的 class_ro_t，逐层累加 ivar，静态重算「realize 后」的真实大小。

等于**把 ObjC runtime 的 `realizeClass` ivar-layout 计算也静态模拟一遍**。「ObjC ivar slide 不可预知」的担忧，本质是「子类编译时不知道父类确切大小」——只要能读到父类二进制里真实 instanceSize（依赖闭包保证），slide 后的值就能静态重算。工作量：中（ObjC ivar 累加 + 读 class_ro_t，算法与 Swift 版同构）。

---

## 6. 现有能力清单 vs 缺口清单

**可直接复用：**

- 字段记录读取：`FieldDescriptor` / `FieldRecord`（三 overload 全静态可读，给字段类型名 + 顺序 + flags）。
- 数据模型：`ValueWitnessTable` / `TypeLayout` / `ValueWitnessFlags`（`Sources/MachOSwiftSection/Models/ValueWitnessTable/`）、`BuiltinTypeDescriptor`（带数值）。
- enum 算法骨架：`EnumLayoutCalculator` + `BitMask` + `SpareBitAnalyzer`（`Sources/SwiftInspection/`）。
- 名字解析：`MetadataReader` + `ReadingContext` 抽象（静态/运行期通吃）。
- 静态分流信号：`MetadataInitialization` kind、`singleton/foreignMetadataInitialization` 模型。
- 现成 vector 读取：`StructMetadata.fieldOffsets(...)` / `FinalClassMetadata.fieldOffsets(...)`（含 MachOFile overload）。
- dyld cache 取镜像：`DyldCache+.swift` 的 `machOFile(by:)`；符号索引 `SymbolIndexStore`。
- ObjC ivar：MachOObjCSection 的 `ObjCIvarListProtocol` / `ClassROData`。

**缺口（需新建）：**

1. 静态 aggregate layout 算法（`performBasicLayout` / class 版 / tuple 版的离线移植）—— 完全没有。
2. 静态 `mangled name → (size, align, stride, XI)` 求解器 —— 现有唯一路径 `getTypeByMangledNameInContext` 是 InProcess-only。
3. 依赖闭包遍历器 + 跨镜像全局类型索引 + 多镜像递归 ReadingContext（§4 三块）。
4. ObjC ivar 累加器（§5）。

---

## 7. 泛型静态化难度评估

现有 `SwiftSpecialization` 模块（约 3600 行）几乎 100% 是 runtime 调用的薄包装：`specialize` / `runtimePreflight` / `resolveAssociatedTypeWitnesses` 全部 `where MachO == MachOImage` 约束（`GenericSpecializer.swift:792` / `:1319` / `:1858`），最终目的是调 metadata accessor（`swift_getGenericMetadata`）让 runtime 实例化 specialized metadata、再从其 field-offset vector 读 offset（`FieldLayoutRenderer.swift:98-110`，泛型走 `InProcessContext.shared`）。模块本身**没有任何静态布局算法**。

**关键框定**：泛型最大的硬骨头——「静态 value-witness / size / extra-inhabitants 计算引擎」——**和 §2/§3 非泛型静态计算器是同一块地基**，不该重复计入泛型成本。刨掉地基后，泛型相对「已有非泛型引擎」的**增量**：

**已是静态、可复用（好消息）：**

- `makeRequest` / 候选收集 / requirements 分类、`ConformanceProvider`（纯查 indexer）、`SpecializationSelection`、`SpecializationValidation` —— 这半边本就没碰 runtime。
- `FieldLayoutRenderer.swift:388-420` 的 `substitutingGenericParameters` 已有 **depth-0 泛型参数节点替换骨架**（现从 runtime metadata 的 inline argument vector 读，要改成从 user selection 读）。

**泛型独有的增量硬骨头：**

| 项 | 难度 | 说明 |
|---|---|---|
| 参数替换扩展 | 中 | `substitutingGenericParameters` 从「depth-0 + 从 metadata vector 读」扩到「depth>0 + 嵌套泛型 + value/pack 形态 + 从 selection 读」。有骨架，可控。 |
| **associated type 静态解析**（`T.Element`） | **高** | 泛型真正独有的骨头。简单情形（witness 是静态 mangled name，本项目有 `__swift5_assocty` 静态读能力）可做；conditional / 需再代入的 witness 要复刻 runtime `swift_getAssociatedTypeWitness` 的递归求值 + conformance 选择，正确性极难验证。 |
| stdlib known-layout 表 | 低-中 | `Array`/`Dictionary`/`Set` 与 T 无关、恒为 8 字节指针 → 识别 `Sa`/`SD`/`Sh` 直接返回。`String`=16、指针=8 照抄 runtime known-layout 表。 |
| `Optional<T>` 布局 | 中（依赖地基） | single-payload enum，依赖 T 的 extra inhabitants。`EnumLayoutCalculator.calculateSinglePayload` 已就位，只要地基能静态供 XI。 |

**纯静态能力上限（无论怎么做都解不掉）：**

- **resilient 类型** → 被 §4 依赖闭包接住（递归到定义模块按 fixed 算）；只有依赖缺失才真失败。
- **conditional / 任意代码的 associated-type witness** → witness access function 可能执行非平凡代码，纯静态只能处理「witness 是静态 mangled name」子集。

**双轨优势**：现有 runtime 路径（`MachO == MachOImage`）既是**验证静态实现的 ground truth**（逐字段对齐），又是**静态算不出时的 fallback**（若允许加载进程）。建议策略：**静态优先，算不出回退 runtime / 标 unknown**。

务实子集：泛型先做「**非 resilient + stdlib 容器 known-layout + 直接泛型参数（非 associated type）**」，覆盖绝大多数常见泛型；conditional / associated-type / 缺失依赖标 `unknown` 或 fallback。

---

## 8. 落地路线（分阶段）

0. **（验证）** 确认 `MetadataInitialization == none` 的 fixed 类型在 MachOFile 下读 vector == 运行期值（§1 实测）。这是 (A) 类捷径的地基。
1. **单镜像直接读**：按 `MetadataInitialization` 分流，fixed 类型直接读 vector（覆盖绝大多数）。
2. **单镜像模拟**：移植 `performBasicLayout`，字段叶子靠固定表 + `BuiltinTypeDescriptor`，同镜像嵌套递归（覆盖「resilient 字段恰好在本镜像内可解析」）。
3. **跨依赖闭包**：依赖闭包遍历 + 全局类型索引 + 多镜像求解器，把 resilient 跨模块字段递归到定义镜像。此步让计算在依赖完整时**理论闭合**。
4. **ObjC 祖先**：读 class_ro_t + ivar 累加，补 ObjC 继承链起点。
5. **泛型（可选）**：在 1-3 的静态引擎之上加参数替换 + stdlib known-layout，先做务实子集；associated-type / conditional 留作 fallback。

综合难度直觉：

```
fixed-layout 非泛型（单镜像）         直接读 vector，几乎零成本   ← 覆盖大多数
  + resilient 字段（单镜像内可解）    移植 performBasicLayout     低-中
  + 跨依赖闭包（resilient 跨模块）    依赖遍历 + 全局类型索引     中（有 dyld cache 底座）
  + ObjC 祖先                       读 class_ro_t + ivar 累加   中（MachOObjCSection 已集成）
  + 泛型（非 associated-type 字段）   参数替换 + stdlib known-layout 中（有替换骨架）
  + 泛型 associated-type            复刻 witness 递归求值        高 ← 唯一真正难啃的
```

---

## 9. 关键源码索引

### Swift runtime（Swift 6.3.2）

| 主题 | 位置 |
|---|---|
| `performBasicLayout`（共用核心算法） | `stdlib/public/runtime/Metadata.cpp:2321-2360` |
| `swift_initStructMetadata` | `Metadata.cpp:2924-2955` |
| `initClassFieldOffsetVector`（class 字段布局） | `Metadata.cpp:3755-3842` |
| `_swift_initClassMetadataImpl` | `Metadata.cpp:4087-4186` |
| `copySuperclassMetadataToSubclass` | `Metadata.cpp:3573-3647` |
| `getInitialLayoutForValueType` / `...HeapObject` | `Metadata.cpp:2300-2308` |
| `roundUpToAlignMask` | `include/swift/Basic/MathUtils.h:38` |
| `ValueWitnessFlags`（alignment mask 低 8 位） | `include/swift/ABI/MetadataValues.h:167-181` |
| `TargetTypeLayout` / `TargetValueWitnessTable` | `include/swift/ABI/ValueWitnessTable.h:280-306` / `:132-229` |
| `FieldAccess` 枚举（静态可知性核心） | `lib/IRGen/ClassLayout.h:30-41` |
| `getFieldAccess` 决策 | `lib/IRGen/GenClass.cpp:452-478` |
| struct `addFieldOffset` 占位逻辑 | `lib/IRGen/GenMeta.cpp:5885-5900` |

### 本项目

| 主题 | 位置 |
|---|---|
| 字段记录静态读取 | `Sources/MachOSwiftSection/Models/FieldDescriptor/FieldDescriptor.swift`、`Models/FieldRecord/FieldRecord.swift` |
| field-offset vector 读取（含 MachOFile overload） | `Models/Type/Struct/StructMetadataProtocol.swift:16-29`、`Models/Type/Class/Metadata/FinalClassMetadataProtocol.swift` |
| value witness / type layout 模型 | `Models/ValueWitnessTable/{ValueWitnessTable,TypeLayout,ValueWitnessFlags}.swift` |
| builtin 静态数值 | `Models/BuiltinType/BuiltinTypeDescriptor.swift:6-12` |
| MetadataInitialization 分流信号 | `Models/Type/TypeContextDescriptorFlags.swift`、`Models/Metadata/MetadataInitialization/` |
| enum 静态布局算法 | `Sources/SwiftInspection/EnumLayoutCalculator.swift`、`SpareBitAnalyzer.swift`、`BitMask.swift` |
| 现有 field rendering（runtime 依赖点） | `Sources/SwiftDeclarationRendering/FieldLayoutRenderer.swift`（`:98-110` fieldOffsets、`:189-203` substitution、`:388-420` 节点替换骨架、`:497` deref runtime metadata vector）、`FieldLayoutRenderer+Enum.swift:113-148`（payloadSize/XI 全靠 runtime VWT） |
| dyld cache 取镜像 / 符号索引 | `Sources/MachOExtensions/DyldCache+.swift`（`machOFile(by:)`）、`Sources/MachOSymbols/SymbolIndexStore.swift` |
| InProcess-only runtime 桥 | `Sources/MachOSwiftSection/Runtime/RuntimeFunctions.swift` |
| 泛型 specialization（runtime 编排，可作 ground truth/fallback） | `Sources/SwiftSpecialization/GenericSpecializer.swift`、`ConformanceProvider.swift`（已静态、可复用） |
| ObjC ivar / class_ro_t | MachOObjCSection `ObjCIvarListProtocol`、`ClassROData`；本项目用例 `Sources/SwiftInspection/ClassHierarchyDumper.swift`、`Sources/TypeIndexing/ObjCInterfaceIndexer.swift` |
