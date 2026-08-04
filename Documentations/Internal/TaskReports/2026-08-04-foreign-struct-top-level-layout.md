# 2026-08-04：SwiftLayout 系统框架保真度普查与 foreign struct / ObjC 滑动两批修复

## 问题

SwiftLayout 的既有保真度证据有两个盲区：文档记录的 5 框架普查只度量**解析率**
（不降级 ≠ 偏移正确），且普查代码不在仓库里无法回归；fixture 之外从未对真实系统框架做
过「静态偏移 vs 运行时真值」的正确率对拍。用户要求：对当前 dyld shared cache 里的
SwiftUI + SwiftUICore + SwiftData 全量对拍，运行时信息视为唯一真实来源。

## 普查方法（harness 位于会话 scratchpad `LayoutFidelitySurvey/`，未入库）

- **静态侧**：`FullDyldCache.host` 取出各框架的 `MachOFile`，
  `ImageUniverse.dependencyClosure(root:)`（系统 cache 搜索路径）+
  `StaticLayoutCalculator.fieldLayout(of:)` 顶层枚举每个非泛型 struct/class 描述符。
- **运行时侧（真值）**：`dlopen` 框架取 `MachOImage`，逐描述符调 metadata accessor：
  - struct：field-offset vector + VWT 五元组（size/stride/XI）；
  - class：**先 realize**（`class_getInstanceSize` 触发）再 `ivar_getOffset` 按字段名对拍。
- **join key**：两侧同用 `MetadataReader.demangleContext` + `node.print(using: .default)`，
  重名（private 类型跨文件同名）双双丢弃（3 例）。

### 方法论教训（首版 harness 的 101 个假不一致）

1. **未 realize 的 ObjC 祖先类**：类 metadata 里躺着编译期未滑动的 field-offset vector
   （NSButton 子类显示 `[8, 9]`），必须 realize 后经 ObjC runtime 读，metadata 向量不可信。
2. **resilient Swift 父类**：离线读向量为空，`[]` 不是「没有字段」而是「读不出」。
3. **零尺寸字段**：引擎按 IRGen `ElementLayout::completeEmpty` 约定报 offset 0，
   运行时 `performBasicLayout` 报累加器位置——两者对无存储字段都「对」，单独归类不算错。

## 普查结果（6246 类型：SwiftUICore 2438 / SwiftUI 3730 / SwiftData 78）

- 完全解析率 **99.95%**（6243/6246；降级仅 SwiftUICore 3 个 `unsupportedTypeKind` 字段）。
- 修复前真实不一致：偏移 5 型 + 整型 20 项，归结 4 个根因，逐项裁决如下。

### ① foreign（C-imported）struct 顶层布局无 builtin 防护 —— 本批修复

- **复现**：`__C.Decimal`（SwiftUI/SwiftData 携带的 foreign 描述符）顶层
  `fieldLayout(of:)` 得 `_mantissa@0`、size 16/align 2；真值 4、20/4（C bitfield
  exponent/length/flags 不在 Swift 字段记录里）。`__C.PathData`/`Size3D`/`Point3D`/
  `Vector3D`/`Rotation3D` 无字段记录，算成 size 0/stride 1（真值 32–96）。
- **根因**：builtin 查表只在**字段类型解析路径**（`StaticTypeLayoutResolver.structLayout
  (forNode:)`）；顶层入口直接结构化累加。`__C` foreign 描述符出现在每个引用方镜像的
  `__swift5_types` 里，顶层枚举（全量 dump、普查、RuntimeViewer 式逐类型渲染）必然踩到。
  同一描述符走 resolver 路径（`typeLayout(forDescriptor:)`）返回的 builtin 值全部正确，
  证明索引数据齐全、缺的只是顶层防护。
- **修复**：`StaticLayoutCalculator` 的 `fieldLayout(ofStruct:)` 与 `typeLayout(ofStruct:)`
  检测 `hasForeignMetadataInitialization`：有 builtin 记录时，结构化累加与 builtin 的
  size/stride/align 一致→保留逐字段结果（`__C.RBColor` 等完整记录的 C struct 本就正确，
  XI 仍取 builtin 权威值）；不一致→逐字段降级为新 reason
  `LayoutUnknownReason.foreignTypeFieldOffsetsUnavailable`、整型取 builtin；无 builtin
  记录维持现状（无从校验，已记录为限制）。
- **测试**：`ForeignStructTopLevelLayoutTests`（修复前失败：4 issue；修复后通过），
  fixture 自带 `__C.Decimal` foreign 描述符与 builtin 记录。
- **横向排查**：同类入口共两处（`fieldLayout` 族经 dispatch 单点收敛 + `typeLayout(ofStruct:)`），
  一并修复；enum 顶层按契约不报字段、`typeLayout(forDescriptor:)` 走 resolver 已有防护；
  foreign class（ObjC 类引用)无字段记录不受影响。
- **修复后复跑**：`__C` 类不一致全部清零（偏移 5→3、整型 20→6，余项均属 ②③）。

### ② ObjC 祖先链的类字段起点 —— 确认为真，同日第二批修复

- **表象**：`AppKitTableHeaderCell` 引擎从 NSTableHeaderCell 实际 `instanceSize`（241）
  直接排 Bool 字段，runtime 真值在 248；子类级联错 8；`SplitViewChildController` 116 vs
  120。最初以为「按字长对齐一行修复」，深挖后否定——真实语义是 objc 的 ivar 滑动。
- **语义核实**（对照 `swift/stdlib/public/runtime/Metadata.cpp`
  `initClassFieldOffsetVector:3778-3785` + objc4 `moveIvars`）：静态发射的 Swift 类把
  ivar 从**自己的** `class_ro_t.instanceStart`（编译期假设，resilient ObjC 父类模式下是
  base 8 一类的最小值）起排；realize 时实际父类尺寸超出则整体滑动，滑动量按**本类 ivar
  最大对齐**取整（不是无条件按字长）。dyld cache 镜像盘上 `instanceStart` 已是预滑终值
  （ROProbe 实测 `AppKitTableHeaderCell` = 248、`SplitViewChildController` = 120）。
  泛型 / singleton 初始化（resilient 父类）的类不在 `__objc_classlist`，走 Swift runtime
  的「精确父类尺寸起排」——即引擎原有规则，保持不变。
- **修复**：`ObjCClassIndex` 新增 Swift 类自身 `instanceStart` 索引（`_TtC…`/`$s…` 运行时
  名 demangle 后取 `.class` 节点建 `nominalQualifiedName` key——注意 `demangleAsNode`
  外层是 `.global` 包裹，直接建名会全表落空，首版即踩此坑致修复整体失效）；resolver 新增
  `classFieldStartOffset`（查到 `instanceStart` → `start = instanceStart +
  roundUp(max(0, superEnd − instanceStart), maxOwnFieldAlign)`；查不到 → 原规则），在
  `computeClassLayout` 与 calculator `fieldLayout(ofClass:)` 两个入口接入（后者对不可解析
  字段跳过取 maxAlign——那段区域本来就降级）。
- **测试**：`ObjCAncestorSlideLayoutTests`——fixture 索引守卫（`ObjCMembersTest`
  `instanceStart` = 8，无漂移零滑动、既有偏移逐字节不变）+ 真实漂移端到端（dyld cache
  SwiftUI 的两目标类，离线闭包计算 == realize 后 `ivar_getOffset`，修复失效版本实测 12
  处断言红、修好后绿）。
- **横向排查**：类起点的另一入口只有 resolver 的 `superclassStartLayout` 递归（父类级联,
  经 `computeClassLayout` 已走新起点）；泛型类（classlist 缺席）维持原行为——OS 泛型类
  若被预特化仍可能有同类偏差，随 ③ 一并留档。

### ③ 预特化泛型 multi-payload enum 的 spare-bits 布局 —— 模型边界，暂记不修

- `AttributedString.Keys.SetIterator` / `SpatialEventCollection.Iterator`（都包
  `Dictionary` 迭代器）：真值 40/40/XI 126（= 2⁷−2，7 个公共 spare bits 减 2 case），
  引擎 41/48/XI 254（运行时 tagged 公式）。
- 引擎假设「泛型 MPE 实例化恒走 `swift_initEnumMetadataMultiPayload` 附加 tag 字节」，
  对**编译器预特化（prespecialized）metadata**（stdlib/OS 二进制越来越常见）不成立——
  预特化记录按编译期 spare-bits 布局。修复需要识别预特化记录或结构化推导泛型 spare
  bits（官方 RemoteInspection 也不做后者），成本高、影响面小（普查 6246 型中 2 型），
  裁决：文档记为已知偏差，不修；若未来做「预特化 metadata 感知」再一并处理。

### ④ 零尺寸字段 offset 约定差异 —— 无害，文档已如实描述

- 10 个类型（`DragGesture.Value.platform`、gauge 的 `metrics` 等）：引擎报 0（IRGen
  约定），运行时布局的 vector 报累加器位置。字段无存储，任何一致性消费两值皆可；
  `accumulateFieldLayout` 的注释已同时描述两种权威的行为，不改。

## 验证

- `ForeignStructTopLevelLayoutTests` 修复前红、修复后绿。
- `swift test --filter SwiftLayoutTests`（22 套件 82 测试）+
  `SwiftDeclarationRenderingTests` 全绿；全量套件（`--skip IntegrationTests`）回归。
- 普查 harness 复跑：总不一致 106（首版，含 101 个方法论假阳性）→ 5（真值方法修正后）
  → 3（本修复后，均属 ②）。

## 偏离

- 无方案偏离。②③④ 未在本批修复：② 待用户确认后单独成批；③④ 按上述裁决留档。
