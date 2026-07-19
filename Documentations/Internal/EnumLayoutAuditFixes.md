# Enum Layout Audit Fixes —— 对照 Swift 官方源码的全面审计与五项修复

日期：2026-07-19
状态：已合入
影响模块：`SwiftInspection`（`EnumLayoutCalculator` 模型与三策略）、`SwiftDeclarationRendering`（`RuntimeFieldLayoutBackend`）、`SwiftLayout`（`EnumLayoutBridge`）；RuntimeViewerCore 已同步

## 背景

在 [RuntimeEnumCaseProjection.md](RuntimeEnumCaseProjection.md)（`Text.Style.LineStyle` 修复）之后，
对枚举布局实现做了一次系统性审计：逐条公式对照 Swift 官方源码
（`ABI/Enum.h`、`stdlib/runtime/EnumImpl.h`、`stdlib/runtime/Enum.cpp`、
`lib/IRGen/GenEnum.cpp`、`RemoteInspection/TypeLowering.cpp`），并用运行时探针
（`MemoryLayout` + `withUnsafeBytes` 逐字节）实证验证。核心数值公式
（`getEnumTagCounts`、单 payload XI/overflow 分界、spare-bits tag 位选择、
三策略的 XI 公式）全部正确；发现并修复了以下五个问题。
**本轮以 runtime 路径的准确性为第一优先**；静态路径向 runtime 进一步收敛
（如指针 XI 的精确数值）留作后续。

## 修复清单

### 1. indirect 单 payload 枚举的 runtime 布局全错（最重要）

`RuntimeFieldLayoutBackend.enumPayloadExtraInhabitantCount` 遇到 `indirect case`
直接返回 `nil` → 被当作 0 个 XI → 所有空 case 走 overflow 路径。而 indirect
payload 实际是 `Builtin.NativeObject` box 指针，XI 数在 64 位 Darwin 上是
`INT_MAX`（`swift_getHeapObjectExtraInhabitantCount`：`LeastValidPointerValue
= 0x1_0000_0000 > INT_MAX` 饱和）。实证 `indirect enum { case node(Self);
case leaf; case sentinel }`：size = **8**，`leaf` = 全 0（XI #0 = null）、
`sentinel` = 1（XI #1）——空 case 全部走 XI，没有任何 extra tag byte。
旧输出会声称 "stored via extra tag bytes"、tag region `8..<9`（**越界**），
且投影器又把 fixedBytes 替换成正确的 XI 图样，图样与文字自相矛盾。

修复：

- indirect → 返回 `EnumLayoutCalculator.heapObjectExtraInhabitantCount`
  （新常量 `0x7FFF_FFFF`，注释注明官方出处与饱和推导）。
- payload 类型解析失败时，从**枚举自身 VWT 反推**
  （`inferredSinglePayloadExtraInhabitantCount`）：payload-sized 布局下
  runtime 计算过 `enumXI = payloadXI - emptyCases`，反演
  `payloadXI = enumXI + emptyCases` 是**精确**的（含 `enumXI == 0` ⇒
  `payloadXI == emptyCases`）；overflow 布局（`enumSize > payloadSize`）下
  enumXI 恒 0、不可反推 → 返回 nil。
- 反推也失败 → **放弃渲染**（返回 nil layout），绝不输出猜测的布局。

### 2. VWT size 交叉校验（稳健性）

公式的输入是**派生值**（逐 payload 解析出的 payloadSize、`__swift5_mpenum`
的 spare 字节），任何解析缺口都会变成"自信而错误"的布局。现在
`computeEnumLayout` 在输出前用 `LayoutResult.impliedTotalSize(payloadAreaSize:)`
（新 API：payload 区 + 其后的 extra tag 区）对照枚举自身 VWT 的 `size`，
不一致直接放弃渲染。metadata 缺失的 multi-payload 枚举跳过校验（公式只依赖
descriptor 数据）。同时删除了 `calculateSinglePayload` 的 `size:` 参数及其
"物理 padding"分支——该分支只在输入不一致时可达，且会把 padding 谎报为
"零 extra tag 字节"；公式现在与 runtime 完全同构，一致性交给调用方校验。

### 3. spare-bits payload case 的整字节过度声明（误导性）

旧模型按**字节**记录 `memoryChanges`，但 spare-bits 布局下 tag 所在字节的
occupied 位是**活的 payload 存储**。实证 `enum { case a(Bool); case b(Bool);
case e0 }`（1 字节，tag 在 bit 6-7，payload 在 bit 0）：旧输出对 `a` 声称
`byte[0x0] = 0x00`，而真实 `a(true)` 是 `0x01`。

修复：`EnumCaseProjection` 新增 `fixedBitMasks: [Int: UInt8]`
（`fixedBitMask(atByteOffset:)` 默认 `0xFF` 全固定）。spare-bits payload case
的固定位 = **全部 common spare bits**（选中的 tag 位携带 scatter 的 tag 值，
未选中的 spare 位固定为 0——spare bit 的定义即合法 payload 表示中恒 0 的位；
occupied 位不做任何声明）。渲染端 partial 字节输出
`byte[0x0] & 0b11111110 = 0b00000000`（摘要）与
`offset 0x00: fixed bits 0b11111110 = 0b00000000 (the other bits hold payload
storage)`（明细），且 partial 字节不参与 little-endian run 合并。

### 4. empty case 固定字节不完整

官方两条路径的 empty case 都固定**整个 payload 区**：tagged 路径
`storeEnumElement` 把 empty-case 值零扩展写满全区且 `loadEnumElement` 读回
前 4 字节判别（实证 `TwoInt64s.emptyA` = `00×8 + tag 02`，bytes 1..7 是判别
相关的固定零）；spare-bits 路径 `getEmptyCasePayload` 从零 APInt scatter，
payload 每一位都固定。旧实现只记录 `ceil(log2(N))` 位取整的 "meaningful"
字节，读者会把缺失字节误解为"任意"。修复：两个策略的 empty case 均记录
完整 payload 区（+ extra tag 字节），`meaningfulPayloadMask` 机制整体删除。
tagged empty case 的 encoding 文案补充 "zero-extended across bytes[…]"。

### 5. no-payload 枚举 XI 未封顶

`EnumLayoutBridge.noPayloadEnumLayout` 按官方
`NoPayloadEnumImplStrategy::getFixedExtraInhabitantCount` 补上
`min(…, MaxNumExtraInhabitants)`。仅 >65536 case（4 字节 tag）的角落情形受影响。

## 测试增量（runtime 准确性保障）

- `EnumLayoutVerificationTests`（既有 runtime 对拍套件，全部在修复后通过）新增：
  - `MP_Bool_2P_1E` 位掩码保真：payload case 必须带 partial mask、payload 位
    （bit 0）不得被声明、声明的固定位对 `a(false)`/`a(true)` 等**每个** payload
    值都成立（"固定"的定义）；渲染文本不得出现整字节声明。
  - empty case 判别区完整性：`verifyEmptyCaseCoversWholePayloadArea` 断言
    empty case 覆盖 payload 区每个字节（全 mask）+ extra tag 区，tagged 与
    spare-bits 各一测（并与真实值逐字节对拍）。
  - `impliedTotalSize` vs `MemoryLayout<T>.size` 三策略对拍。
- `RuntimeEnumCaseProjectorTests` 新增 indirect 单 payload 投影对拍
  （ground truth：size == 8；`leaf` 全零、`sentinel` = 1；公式喂
  `heapObjectExtraInhabitantCount` 后结构一致：无 tagRegion、tagValue 全 0）。
- `RuntimeEnumLayoutRenderingTests` 新增：
  - fixture 新类型 `Enums.IndirectSinglePayloadEnumTest` 的端到端渲染回归
    （策略必须是 extra inhabitants、无越界 offset、投影图样正确）。
  - `inferredSinglePayloadExtraInhabitantCount` 的精确反演/不可反演单元测试。
- fixture 重建 + baselines 重生成（drift 全为偏移平移）+ 两个 snapshot 重录
  （新枚举出现在 dump/interface 输出中）。

## RuntimeViewerCore 同步

- `MemoryOffsetInput` 新增 `fixedBitMask`（默认 `0xFF`）与
  `fixedBitMaskBinaryPadded(Raw)` 派生值；`MemoryOffsetToken` 新增
  `fixedBitMask` / `fixedBitMaskBinaryPadded`（8 → 10 个）。
- `RuntimeSwiftSection` 接线：`memoryChangesDetail` 对 partial 字节输出
  `[0]&0b11111110=0b00000000`；逐字节行在 mask ≠ 0xFF 时绕过用户模板、
  输出库风格的 "fixed bits" 行（整字节值走模板会过度声明）。
- `fixedBytesSummary` 走库的 `formattedFixedBytes()`，自动跟上新格式。

## 审计中确认无误的部分（简记）

`getEnumTagCounts` 逐行一致；`EnumImpl.h` 单 payload store/get 全公式
（XI/overflow 分界、`payloadSize >= 4` 阈值、extra tag 清零）；
`GenEnum.cpp` spare-bits 布局（most-significant spare 位选择及
`numTagBits == count` 边界、empty case tag/index 拆分与 ≥32 饱和、hybrid
extra tag 高位）；三策略 XI 公式（extra tag 位取整到整字节、cap、≥32 饱和）；
`BitMask` 的 scatter/选位语义；投影器机制；generic 枚举强制 tagged 的判定。
