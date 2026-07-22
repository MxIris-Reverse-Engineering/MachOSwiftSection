# Runtime Enum Case Projection —— 基于 value witness 的枚举 case 内存图样投影

日期：2026-07-18
状态：已合入
影响模块：`SwiftInspection`（`RuntimeEnumCaseProjector` 新增、`EnumLayoutCalculator` 模型与渲染重构）、`SwiftDeclarationRendering`（`RuntimeFieldLayoutBackend` 接线）、`SwiftLayout`（`EnumLayoutBridge` 附加 case 名）

## 动机：一个真实的用户反馈

用户反馈 `SwiftUI.Text.Style.LineStyle` 的 Enum Layout 注释不对。该枚举形如：

```swift
package enum LineStyle {
    case implicit
    case explicit(Text.LineStyle)   // Text.LineStyle: { nsUnderlineStyleValue: Int, color: Color? }，16 字节
    case `default`
}
```

真实布局（用户反馈的版本，已逐字节验证正确）：

```
+0x8 的 8 字节字 = 0 或其他合法指针 → explicit（payload 有效）
+0x8 的 8 字节字 = 1               → implicit
+0x8 的 8 字节字 = 2               → default
```

原因链（对照 Swift 官方源码）：

1. `Text.LineStyle` 是 struct，struct 的 extra inhabitant（XI）取自「XI 最多的字段」
   （`Enum.cpp: findXIElement` / `swift_initStructMetadata`）——即 offset 0x8 处的 `Color?`。
2. `Color` 包一个 `AnyColorBox` 类引用；Darwin 64 位上 `LeastValidPointerValue = 0x100000000`
   （`shims/System.h`），堆指针的 XI #i 就是把整数 i 直接写成指针值
   （`Metadata.h: swift_storeHeapObjectExtraInhabitant`），数量饱和到 `INT_MAX`。
3. `Optional` 的 `nil` 消耗 XI #0（值 0），其余 XI 依次后移一位。
4. 单 payload 枚举的空 case i 存为 payload 的 XI #i
   （`EnumImpl.h: storeEnumTagSinglePayloadImpl`，`whichCase = i + 1` 走 `storeExtraInhabitantTag`）。
   于是 `implicit` → 字 = 1，`default` → 字 = 2，而全 0 反而是
   `explicit(.init(nsUnderlineStyleValue: [], color: nil))` 的合法编码。

## 旧实现的 bug

数值层面（策略选择、tag 计数、XI 计数）都是对的，错在**空 case 的内存图样投影**：

- `RuntimeFieldLayoutBackend.computeEnumLayout` 调 `calculateSinglePayload` 时只传 XI **个数**
  （来自 VWT，本身正确），不传任何图样信息。
- 旧 `calculateSinglePayload` 对 XI 空 case 用「`~index` scatter 进 spareBitMask」凭空捏造图样；
  mask 为空时 `memoryChanges` 为空，渲染成 **"(No bits set / Zero)"** ——两个空 case 无法区分，
  且与事实相反（全 0 其实选中的是 payload case）。
- 即使传了 spare bytes，`~index` scatter 对指针型 XI 也是错的：指针 XI 是「低无效地址上的小整数值」，
  不是 spare-bit 图样。根本问题是：**任何只知道 XI 个数的公式都推不出 XI 的具体字节** ——
  那是 payload 类型自己的语义（类引用的低地址、`String` 的 `_StringObject` 保留判别模式、
  嵌套 payload 逐层递归组合）。

## 新设计

### 1. `RuntimeEnumCaseProjector`（SwiftInspection，新增）

在进程内直接驱动枚举自己的 value witness，不再预测：

- 每个 case tag 各做两次注入：一块全 `0x00`、一块全 `0xFF` 的 scratch buffer 上调
  `destructiveInjectEnumTag(buffer, tag)`；注入后两块 buffer **一致的字节**就是该 case 的固定判别字节
  （witness 确定性写入），不一致的字节是 payload 存储/padding（witness 未触碰）。
- 空 case 用 `getEnumTag` 从零化 buffer 读回校验 round-trip；对不上就整体放弃、退回公式图样。
  （payload case 不能这样校验：注入不写 payload，残留的零字节可能恰好是某个空 case 的图样，
  例如非 Optional 类引用的空指针。）
- 空 case 的注入只写 tag 机制（XI 图样按定义是**非法** payload 值，不会产生真实对象引用），
  buffer 无需 destroy。
- 双基线 diff 假设注入是**纯写入**：单 payload 策略成立（XI 存储与 extra tag 存储都是 plain store）；
  多 payload spare-bits 策略的注入是 OR 进 spare bits，**不适用**本投影器——它的图样本来就从
  `__swift5_mpenum` 的 mask 精确得出，无需投影。
- arm64e（ptrauth）上 VWT 函数指针带签名（IA key + address diversity + 每 slot 独立
  discriminator，如 `getEnumTag` = `0xa3b5`、`destructiveInjectEnumTag` = `0xb2e4`），直接
  `@convention(c)` 调用会 fault：经 `MachOSwiftSectionC` 的 `swift_section_vwt_getEnumTag` /
  `swift_section_vwt_destructiveInjectEnumTag` stub 调用——其 `EnumValueWitnessTable` C 结构体
  成员带 `__ptrauth_swift_value_witness_function_pointer` 限定符，clang 在调用点自动 auth
  验签（与 runtime 自身调用 witness 的方式一致，被篡改的指针会 fault 而非被执行；clang
  importer 不导入带 ptrauth 限定符的成员，故 Swift 侧必须经 stub）。非 arm64e 保持
  `unsafeBitCast` 直调路径（stub 仅在 `__arm64e__` 下编译）。初版曾用
  `#if _ptrauth(_arm64e)` 整体降级返回 nil，2026-07-22 起改为经 stub 全平台可用；arm64e
  路径目前只有交叉编译级验证（本机用户态跑不了 arm64e 进程）。

### 2. `EnumLayoutCalculator` 模型与渲染重构

`EnumCaseProjection` 增加字段：

- `declaredName: String?` —— 源码级 case 名（从 field records 读，payload 在前、空 case 在后，
  与 tag 序一致）；
- `isPayloadCase: Bool`；
- `patternResolution: PatternResolution` —— `.exactBytes`（`memoryChanges` 权威）或
  `.unresolvedExtraInhabitant(extraInhabitantIndex:)`（只知道是 payload 的第 i 个 XI 图样，
  具体字节未解析）；
- `encodingExplanation: String` —— 由构建投影的策略拼出的「这个 case 怎么编码」的整句说明
  （spare-bit tag 值、XI 图样序号、溢出 tag/索引、payload 范围），因为只有策略本身知道全部上下文。

`calculateSinglePayload` 移除 `spareBytes`/`spareBytesOffset` 参数与 scatter 捏造路径
（实际调用方从未传过）；XI 空 case 诚实标注为 `.unresolvedExtraInhabitant`；payload case 与
XI case 在存在 extra tag 字节时携带「tag 字节 = 0」这一确切约束（`EnumImpl.h:156-160`）。

### 默认渲染：信息拉满，裁剪交给 Transformer

设计取向（用户反馈）：库的**默认**渲染要尽量详尽，因为消费方（如 RuntimeViewer）可以通过
`enumLayoutCaseTransformer` / `enumLayoutTransformer` 自行挑字段、裁成更短的形式；默认给得少反而
逼每个消费方各自重造。于是 `EnumCaseProjection.description(indent:prefix:)` 输出多行块：

```
Case 1 (0x01) `implicit` — empty case #0
  encoding: stored as the payload's extra-inhabitant pattern #0 (an invalid payload bit pattern)
  note: the exact bytes depend on the payload type's extra-inhabitant scheme and were not resolved offline (the in-process runtime path resolves them)
  fixed bytes: not computed
```

runtime 精确路径下则是：

```
Case 1 (0x01) `implicit` — empty case #0
  encoding: stored as the payload's extra-inhabitant pattern #0 (an invalid payload bit pattern)
  fixed bytes: bytes[0x8..<0x10] = 0x1
    offset 0x08 = 0x01 (0b00000001)
    offset 0x09 = 0x00 (0b00000000)
    …
```

每行块含：头（case 序号、hex、`declaredName`、结构标签）、encoding 解释、未解析时的 note、
run 压缩摘要（连续字节压成 little-endian run，如 `bytes[0x8..<0x10] = 0x1`；单字节附二进制
`byte[0x7] = 0x40 (0b01000000)`，方便读 spare-bit 子字节 tag）、以及逐字节
`offset / hex / binary` 明细。全零图样（如非 Optional 类引用的空 case #0 = 空指针）显示为
`bytes[0x0..<0x8] = 0x0`，与「没算出来」不再混淆。

类型级前缀注释改用 `LayoutResult.summaryDescription`：策略 + case 计数（payload/empty）+
tag 值/位数 + tag/occupied-bit 区域 + 「留给外层 enum 的剩余 XI」，一行拉满。策略行本身也改写为
完整语句（如 `Single Payload (2 empty cases stored as payload extra inhabitants)`）。

### 3. 两条路径的接线

- **Runtime（`MachOImage`，`RuntimeFieldLayoutBackend`）**：单 payload 枚举先跑公式拿
  策略/计数骨架，再用投影器把每个 case 的 `memoryChanges` 替换为精确字节
  （`LayoutResult.applyingExactCasePatterns`），最后附加真实 case 名
  （`attachingDeclaredCaseNames`）。元数据绝对地址 = `machO.ptr + metadata.offset`
  （wrapper 经 `MachOContext(machO)` 解析，offset 相对 image base；泛型特化元数据经
  `InProcessContext`，offset 即绝对地址）。投影失败（无 enum witness、round-trip 失败）
  自动退回公式图样。
- **Static（`MachOFile`，`EnumLayoutBridge.enumCaseLayoutResult`）**：同样附加真实 case 名；
  XI 空 case 保持 `.unresolvedExtraInhabitant` 的诚实标注。离线解析指针型 XI 图样
  （静态推导「XI 落在哪个 offset、值序列如何」）留作后续工作。

## 验证

- **Ground truth**：脚本对真实 `SwiftUI.Text.Style.LineStyle`（mangling
  `7SwiftUI4TextV5StyleV9LineStyleO`，注意 `Text.Style` 是 struct）的元数据直接调
  `destructiveInjectEnumTag`：tag 0 → 全 0；tag 1（implicit）→ +0x8 字 = 1；
  tag 2（default）→ +0x8 字 = 2。与用户反馈完全一致。
- **单元测试** `SwiftInspectionTests/RuntimeEnumCaseProjectorTests`：本地枚举
  （LineStyle 同构形、非 Optional 类引用全零图样、Bool 子字节图样、溢出 tag 字节）
  投影图样与真实 case 值 `withUnsafeBytes` 逐字节对拍。
- **集成测试** `SwiftDeclarationRenderingTests/RuntimeEnumLayoutRenderingTests`：fixture 的
  `Enums.SinglePayloadOverStructTest`（LineStyle 同构）与 `SinglePayloadEnumTest`（String payload）
  走完整渲染链路，断言精确图样、全零图样显式呈现、case 名附加、注释文本。
- 全量 `swift test --skip IntegrationTests`：1166 通过。

## 兼容性

- `EnumCaseProjection` 的 memberwise init 增加了必填的 `isPayloadCase`（`declaredName`/
  `patternResolution`/`encodingExplanation` 有默认值）；`calculateSinglePayload` 移除了两个
  从未被使用的参数（仓库内唯一调用点 `IntegrationTests/MultiPayloadEnumTests` 已改为用
  `calculateMultiPayload` 结果的 `extraInhabitantCount` —— 语义反而更正确）。
- 快照测试不含 enum layout 输出（该选项默认关闭），无需重录。
- `enumLayoutCaseTransformer`/`enumLayoutTransformer` 自定义渲染的外部消费者会看到新增字段，
  默认渲染文本已变化。**RuntimeViewerCore 已同步**（`Transformer.SwiftEnumLayout`）：`CaseInput`
  新增 `declaredName`/`encoding`/`patternKind`/`patternNote`/`fixedBytesSummary` token，`Input`
  新增 `summary`/`leftoverExtraInhabitantCount`；case 分类改用 `isPayloadCase`；默认 Standard
  模板对齐库的详细格式，旧格式保留为 `Classic`；不再对未解析/payload case 打
  `(No bits set / Zero)`。
