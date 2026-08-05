# 2026-08-05：泛型 fixed MPE 的 spare-bits 布局——「硬骨头 ③」定性修正与修复

## 问题

第 27 节普查（[2026-08-04 报告](2026-08-04-foreign-struct-top-level-layout.md)）留档的最后一块硬骨头：
`AttributedString.Keys.SetIterator` / `SpatialEventCollection.Iterator`（都包 `Dictionary`
迭代器）真值 40/40/XI 126，引擎按「泛型 multi-payload enum 恒 tagged」模型算 41/48/254。
当时定性为「编译器**预特化（prespecialized）** metadata 按编译期 spare-bits 布局」，
记为已知偏差，列了三个修复方向（识别预特化记录 / 结构化推导 spare bits / 保守降级）。

## 调研（旧定性被实验推翻）

1. **决定性实验**：探针二进制里全新定义 `FreshKey`/`FreshValue` 两个类型，实例化
   `Dictionary<FreshKey, FreshValue>.Iterator` 并直接读运行时 VWT——**40/40/align 8/XI 126**，
   与 OS 类型完全一致；`dladdr` 显示 metadata 位于 runtime 的 `InitialAllocationPool`
   （运行时分配）。没有任何编译器见过这个参数组合，「预特化」理论就此出局。
2. **运行时源码**（`swift/stdlib/public/runtime/Enum.cpp:384`）：
   `swift_initEnumMetadataMultiPayload` 与 layout-string 变体都是纯 tagged
   （`payloadSize + numTagBytes`，无 spare bits）——引擎的移植没错，错在**适用范围**：
   它只对「布局依赖实参」的 MPE 运行。布局与实参无关的泛型 MPE
   （`Dictionary.Iterator._Variant` 的两个 payload 都是引用 + 定长字），编译器把完整
   spare-bits VWT 烘焙进 generic metadata pattern，完成函数什么都不算，所有实例化共享。
3. **编译器契约**（`lib/IRGen/GenReflection.cpp` `emitFieldDescriptor`）：
   `payload 数 > 1 && !needsPayloadSizeInMetadata()`（即静态 fixed）时**同时**发射
   `__swift5_builtin`（整体五元组，`FixedTypeMetadataBuilder`）与 `__swift5_mpenum`
   （spare-bits mask，`MultiPayloadEnumDescriptorBuilder`，`usesPayloadSpareBits =
   bytesInMask > 0`）；两个 builder 都对 `typeInContext` 直接 `cast<FixedTypeInfo>`——
   即「抽象泛型形态下就 fixed」。反向一致性（`GenEnum.cpp:7192`）：
   `!AllowFixedLayoutOptimizations`（unsubstituted payload 含泛型参数、或在可见 resilience
   域内非 fixed）时编译器**自己也清空 CommonSpareBits**，静态布局退化为与 runtime tagged
   公式一致的附加 tag 字节，且不发记录。**所以「记录存在 ⇔ spare-bits/fixed 布局」在构造上
   精确，判据零启发式。**
4. **真实二进制实证**（5 个 OS 镜像：libswiftCore / SwiftUICore / SwiftUI / SwiftData /
   Foundation）：libswiftCore 的 builtin 段就有 `Swift.Dictionary.Iterator._Variant`
   40/40/8/XI 126（`Set.Iterator._Variant` 同型；`Dictionary.Index._Variant` 17/24/254——
   fixed 但无公共 spare bits，两种模型数字恰好相同），mpenum 记录带 7 位 mask
   `07 00 00 00 00 00 00 f0`（XI = 2⁷ − 2 = 126）；对照组 `Environment.Content`
   （依赖实参）两个段均无记录。**全部记录的 typeref demangle 出来就是无参数的普通 nominal
   节点**——与 `BuiltinTypeLayoutIndex` 现有的剥参数 key 完全一致，这些记录早已在索引里；
   零个带类型参数或 bound-concrete 实例化形态的记录（索引注释里担心的 key 冲突现实中不存在）。
5. **引擎缺陷定位**：`EnumLayoutBridge` 两道基于错误模型的门——builtin 查表的
   `environment.isEmpty`（实例化节点永不查）与 `multiPayloadEnumLayout` /
   `enumCaseLayoutResult` 的 `!descriptor.isGeneric`（泛型永不走 spare-bits）。fixture 的
   `ClassBoundContent<Element: AnyObject>` 注释也写着同一错误模型——它侥幸没暴露：
   class-bound archetype 不贡献 spare bits（可能装 ObjC tagged pointer，GenEnum.cpp ~7205），
   其 mpenum 记录 `usesPayloadSpareBits = false`，两种模型数字相同。

## 最终方案

- **判据用「编译器记录的存在性」**，不做结构化 fixedness 推导——后者要重放 resilience
  语义（`layoutScope`），而 `@frozen` 从二进制里读不出来，必然引入启发式误差；记录存在性
  是编译器原话，且解析设施（`BuiltinTypeLayoutIndex` / `MultiPayloadEnumDescriptorCache`
  同款 mpenum 读取）早已就位，修复只是放行。
- 引擎三处改动：
  1. `enumLayout` 的 builtin 查表放行 `.enum` / `.boundGenericEnum` 节点（不再要求空环境）；
  2. `multiPayloadEnumLayout` + `enumCaseLayoutResult` 删 `!descriptor.isGeneric`，
     只按 `usesPayloadSpareBits` 分流；
  3. `compute()` 在结构化计算前补查**定义镜像**的 builtin 索引（enum 记录按声明模块发射，
     与 imported C 的逐引用方发射不同；顺带闭合 mask>16k 不发 mpenum 记录的边角）。
  另 `BuiltinTypeLayoutIndex` 防御性跳过 typeref 为 bound-concrete 实例化的记录（实测零例）。

## 实际执行

- fixture 新增 `Dictionary.Iterator._Variant` 形态类型族（`SpareBitsNativeStorage<First,
  Second>`（类引用 + 2 Int，24 字节）、`SpareBitsVariantEnum<First, Second>`（native/bridged
  双 payload + exhausted 空 case）、非泛型 holder `SpareBitsVariantEnumFieldHolder`），并
  修正 `ClassBoundContent` 的错误注释。
- 新套件 `GenericSpareBitsEnumLayoutTests` 三针：fixture 实例化对 runtime VWT/offset
  （双 reader）、builtin 记录存在性判别（fixed 有、依赖实参的无——工具链契约守卫）、
  OS 端到端（SetIterator / SpatialEventCollection.Iterator 对 realize 后 VWT 四元组）。
- **红字确认**（引擎未改时）：fixture 侧 34/253 + offsets [0,8,33]（真值 33/125 + [0,8,32]，
  即 enum 25 vs 24）；OS 侧 41/48/254 vs 40/40/126——与普查记录的数字逐位一致。
- 引擎修复后三针全绿；`SwiftLayoutTests` 全套 87 测试 / 24 套件绿。
- **顺带修出既有测试缺陷**：`MultiPayloadEnumStructuralTests` 遍历 fixture MPE 描述符
  未过滤泛型；此前所有泛型 MPE 的 payload 在空环境下都解析失败被跳过，新 fixture 类型是
  第一个空环境可解析的泛型 MPE，测试继续走到「对泛型 enum 无参调 metadata accessor」
  → SIGSEGV。补 `!isGeneric` 守卫（泛型形态的 runtime 真值经非泛型 holder 走新套件）。
- **渲染对拍**（行为修复，非重构，故不适用 byte-identical A/B 脚本；用 before/after diff
  裁决影响面）：SwiftUI 全量 dump（`--field-offset-template Standard --enum-layout-style
  detailed`）before/after 共 **117 行 diff，全部是 enum-layout 注释行**，恰好 4 个枚举——
  `NSHostingView.AllowAutomationElementsState`（XI 254→126）、`AnimatedValueState<A>` 及其
  两个嵌套 enum（XI 253→125 等）——全是「泛型上下文 + 带 spare-bits mask 记录」的直接
  受益者；声明本体零变化（默认输出不受影响）。
- 普查 harness 复跑（重指向 workspace）：见「验证」。

## 验证

- `GenericSpareBitsEnumLayoutTests` 修复前红（8 issue）、修复后绿（3/3）。
- `swift test --filter SwiftLayoutTests`：87 测试 / 24 套件全绿。
- 全量套件（`--skip IntegrationTests`）+ fixture 基线再生成：见提交说明。
- 普查复跑（SwiftUICore + SwiftUI + SwiftData，运行时唯一真值）：整型（whole-type）偏差
  从 6 项（2 型 × size/stride/XI）清零。
- 环境注记：本批在 `/tmp/claude/Workspace/MachOSwiftSection`（main 的 git worktree，按 CI
  同款远端 pin 解析依赖）完成——用户主检出被 pin 在 `3396cfd`（PR #97 前）且 sibling
  `swift-demangling` 同步回退，直接在主检出上构建 main 会因 `NodeReference` 缺失失败，
  而挪动用户的 sibling 检出已被证明会被复位（上一批的快进被外部还原）。

## 偏离

- 无方案偏离。第 27 节报告与 StaticLayoutEngine.md 当时写下的「预特化」定性与三个修复
  方向由本批**整体推翻并改写**（真实机制更简单：pattern 烘焙 + 记录存在性判据；修复
  ~20 行，而非当时预估的「新段解析 / 编译期 spare-bit 分析」）。
