# Swift Enum 内存布局内部机制

本文档详细描述 Swift 编译器如何在内存中表示枚举（enum）值。所有细节均基于 Swift 运行时源码（`GenEnum.cpp`、`TypeLowering.cpp`、`Enum.cpp`、`EnumImpl.h`、`ABI/Enum.h`）以及经过运行时验证的 `EnumLayoutCalculator` 实现。

---

## 术语

| 术语 | 说明 |
|---|---|
| **Payload Case** | 携带关联值的 case |
| **Empty Case** | 无关联值的 case |
| **Payload Size** | 所有 payload case 中最大关联值的字节大小 |
| **Tag** | 用于区分不同 case 的判别值 |
| **Extra Inhabitants (XI)** | payload 类型中不代表有效值的位模式，可复用来编码 empty case |
| **Spare Bits** | 所有 payload 类型共有的、在合法值中永远为零的位 |
| **Occupied Bits** | 非 spare bits 的位，即实际承载 payload 数据的位 |
| **Overflow** | 当 XI 不足以编码所有 empty case 时，在 payload 之后追加的额外 tag 字节 |

---

## 策略选择

Swift 编译器根据 payload case 的数量选择不同的内存布局策略：

```
if numPayloadCases == 0:
    → 无 Payload 枚举（简单 tag，本文不讨论）
elif numPayloadCases == 1:
    → 单 Payload 枚举（策略 3）
elif numPayloadCases >= 2:
    if 所有 payload 类型共享 spare bits:
        → 多 Payload Spare Bits（策略 1）
    else:
        → Tagged 多 Payload（策略 2）
```

---

## 策略 1: Multi-Payload Spare Bits

### 适用条件

多个 payload case 且所有 payload 类型共享 spare bits（例如 class reference 在 arm64 上高位字节有 spare bits）。

### 内存布局

```
┌──────────────────────────────────┬──────────────────┐
│      Payload Area (N bytes)      │ Extra Tag Bytes   │
│  [spare bits = tag] [rest = data]│ (spare bits 不够  │
│                                  │  时才有)           │
└──────────────────────────────────┴──────────────────┘
```

### 核心算法

**1. 构建 CommonSpareBits 掩码**

对所有 payload 类型的 spare bits 取交集，得到 `CommonSpareBits`。这些位在所有合法 payload 值中都为 0。

**2. 计算 Occupied Bits**

```
occupiedBitCount = totalBits - spareBitCount
```

Occupied bits 是 spare bits 的补集，承载实际 payload 数据。

**3. 计算所需 tag 数**

```
if occupiedBitCount >= 32:
    numEmptyElementTags = 1    // 所有 empty case 共享一个 tag
else:
    emptyElementsPerTag = 2^occupiedBitCount
    numEmptyElementTags = ceil(numEmptyCases / emptyElementsPerTag)

numTags = numPayloadCases + numEmptyElementTags
numTagBits = ceil(log2(numTags))
```

**4. 选择 tag 位**

```
if numTagBits <= spareBitCount:
    // 从最高有效位选取所需数量的 spare bits 作为 tag
    PayloadTagBits = keepMostSignificant(CommonSpareBits, numTagBits)
    extraTagBytes = 0
else:
    // Spare bits 不够：全部 spare bits + 额外 tag 字节
    PayloadTagBits = CommonSpareBits
    extraTagBitCount = numTagBits - spareBitCount
    extraTagBytes = ceil(extraTagBitCount / 8)
```

### Case 编码

**Payload Case（tag = caseIndex）：**

tag 值 scatter 到 spare bits 位置，低位在 payload 内的 spare bits，高位溢出到 extra tag bytes。

```
memory = scatterBits(PayloadTagBits, tag_low) | payload_data
extra_tag_bytes = tag >> numPayloadTagBits  // 高位
```

**Empty Case：**

tag 和 payloadValue 分别 scatter 到 spare bits 和 occupied bits 中。

```
if occupiedBitCount >= 32:
    payloadValue = emptyIndex
    tag = numPayloadCases         // 所有 empty case 共享同一 tag
else:
    payloadValue = emptyIndex & ((1 << occupiedBitCount) - 1)
    tag = numPayloadCases + (emptyIndex >> occupiedBitCount)

memory = scatterBits(PayloadTagBits, tag_low) | scatterBits(OccupiedBits, payloadValue)
```

### 示例

```swift
final class Ref1 { var x: Int = 0 }
final class Ref2 { var y: Int = 0 }
enum E { case a(Ref1); case b(Ref2); case e0; case e1; case e2 }
// arm64: spare bits 在 byte 7（高位字节），例如 mask = 0x80 at offset 7
// 2 个 payload case + 3 个 empty case
// numTags = 2 + 1 = 3, numTagBits = 2
// 有 2 个 spare bits → 足够，无需 extra tag bytes
// Payload case a: tag=0 → spare bits = 0b00, byte 7 不变
// Payload case b: tag=1 → spare bits = 0b01, byte 7 某位置位
// Empty case e0:  tag=2, payloadValue=0
// Empty case e1:  tag=2, payloadValue=1
// Empty case e2:  tag=2, payloadValue=2
```

---

## 策略 2: Tagged Multi-Payload

### 适用条件

多个 payload case 但无 spare bits（例如整数类型占满全部位域），或 generic/resilient payload。

### 内存布局

```
┌──────────────────────────────────┬──────────────────┐
│      Payload Area (P bytes)      │  Tag (T bytes)   │
│    (用户数据或 empty 索引)         │  (payload 之后)   │
└──────────────────────────────────┴──────────────────┘
总大小 = P + T
```

Tag 字节数由 `getEnumTagCounts` ABI 函数决定。

### getEnumTagCounts 算法

```
numTags = payloadCases
if emptyCases > 0:
    if payloadSize >= 4:
        numTags += 1           // 单个 tag 值足够
    else:
        casesPerTagBitValue = 2^(payloadSize * 8)
        numTags += ceil(emptyCases / casesPerTagBitValue)

numTagBytes = 0 if numTags <= 1
            = 1 if numTags < 256
            = 2 if numTags < 65536
            = 4 otherwise
```

**关键分支：payloadSize < 4 vs ≥ 4**

当 payloadSize ≥ 4（≥ 32 位）时，payload 区域足够大，可以用 payload 值直接编码所有 empty case 的索引，因此只需一个额外的 tag 值。当 payloadSize < 4 时，payload 区域容量有限，empty case 需要跨多个 tag 值分散编码。

### Case 编码

**Payload Case：**

```
tag = caseIndex                // 每个 payload case 一个唯一 tag
payload = user_data            // 用户数据写入 payload 区域
```

**Empty Case：**

```
if payloadSize >= 4:
    tag = numPayloadCases      // 所有 empty case 共享一个 tag
    payload = emptyIndex       // payload 区域存储 empty 索引
else:
    tag = numPayloadCases + (emptyIndex >> (payloadSize * 8))
    payload = emptyIndex & ((1 << (payloadSize * 8)) - 1)
```

### 示例

```swift
enum E { case a(UInt8); case b(UInt8); case e0; case e1; case e2 }
// payloadSize = 1, payloadCases = 2, emptyCases = 3
// payloadSize < 4 → casesPerTag = 2^8 = 256
// numTags = 2 + ceil(3/256) = 3, numTagBytes = 1
// 内存：[payload: 1 字节][tag: 1 字节] = 共 2 字节

// case a(42):  payload=0x2A, tag=0x00
// case b(99):  payload=0x63, tag=0x01
// case e0:     payload=0x00, tag=0x02
// case e1:     payload=0x01, tag=0x02
// case e2:     payload=0x02, tag=0x02
```

```swift
enum E { case a(UInt32); case b(UInt32); case e0 }
// payloadSize = 4, payloadCases = 2, emptyCases = 1
// payloadSize >= 4 → numTags = 2 + 1 = 3, numTagBytes = 1
// 内存：[payload: 4 字节][tag: 1 字节] = 共 5 字节

// case a(1000):  payload=0xE8030000, tag=0x00
// case b(0):     payload=0x00000000, tag=0x01
// case e0:       payload=0x00000000, tag=0x02
```

---

## 策略 3: Single Payload

### 适用条件

恰好一个 payload case，加上一个或多个 empty case。这是 Swift 中最常见的模式（如 `Optional<T>`）。

### 编码优先级

Single payload 使用两级编码：先尝试 Extra Inhabitants，不够再用 Overflow。

```
1. Extra Inhabitants (XI)    → 在 payload 区域内利用无效位模式
2. Overflow                  → 在 payload 之后追加 tag 字节
```

### 3a. Extra Inhabitants (XI) 编码

**什么是 Extra Inhabitants**

某些类型不会用到全部位模式。未使用的位模式称为 Extra Inhabitants，可以被外层 enum 复用来编码 empty case，**无需额外内存开销**。

| 类型 | 大小 | XI 数量 | 说明 |
|---|---|---|---|
| `Bool` | 1 字节 | 254 | 仅使用 0 和 1，值 2..255 为 XI |
| `UInt8` | 1 字节 | 0 | 使用全部 256 个值 |
| `UInt16` | 2 字节 | 0 | 使用全部 65536 个值 |
| `UInt32` | 4 字节 | 0 | 使用全部 2^32 个值 |
| `UInt64` | 8 字节 | 0 | 使用全部 2^64 个值 |
| `Optional<UInt8>` | 2 字节 | 0 | 257 个状态（256 个 `.some` + `.none`）占满全部位模式 |
| Class reference | 8 字节 | 2^31 - 1 | 空指针 + 对齐无效指针 |

**重要：XI 来自 payload 类型的 VWT**

`numExtraInhabitants` 从 payload 类型（而非外层 enum）的 Value Witness Table 获取。外层 enum 消耗这些 XI 后，其自身的 XI 会减少。

```swift
// Bool 有 254 个 XI
enum SP_Bool_3E { case p(Bool); case e0; case e1; case e2 }
// 从 Bool 的 254 个 XI 中消耗 3 个 → enum 大小 = 1 字节（与 Bool 相同！）

// Optional<UInt8> 有 0 个 XI（不是 254！）
enum SP_OptU8_1E { case p(UInt8?); case e0 }
// 必须用 overflow → enum 大小 = 3 字节（2 payload + 1 tag）
```

**XI 编码规则：**

- `tagValue = 0`（与 payload case 的 tag 值相同）
- Extra tag bytes = 0（全部在 payload 区域内完成）
- enum 大小 = payload 大小（无额外开销）

### 3b. Overflow 编码

当 XI 不足以编码所有 empty case 时，超出部分使用 overflow：在 payload 之后追加 extra tag bytes，并复用 payload 区域存储 overflow case 的索引。

```
┌──────────────────────────────────┬──────────────────┐
│  Payload Area (复用存储索引)       │ Extra Tag Bytes   │
└──────────────────────────────────┴──────────────────┘
```

**Overflow 编码算法：**

```
overflowCases = numEmptyCases - numXICases
extraTagBytes = getEnumTagCounts(payloadSize, overflowCases, 1).numTagBytes

// 对每个 overflow case：
if payloadSize >= 4:
    tagValue = 1                    // 单个 tag 值
    payloadValue = overflowIndex    // 索引直接存入 payload
else:
    payloadBits = payloadSize * 8
    payloadValue = overflowIndex & ((1 << payloadBits) - 1)
    tagValue = 1 + (overflowIndex >> payloadBits)
```

### 3c. Hybrid: XI + Overflow 混合

当 payload 类型有部分 XI 但不够编码所有 empty case 时，两种策略混合使用：

```
numXICases = min(numEmptyCases, numExtraInhabitants)
numOverflowCases = numEmptyCases - numXICases

// 前 numXICases 个 empty case 用 XI 编码
// 剩余 numOverflowCases 个用 overflow 编码
```

### 示例

```swift
// 纯 XI — Bool payload（254 个 XI）
enum E { case p(Bool); case e0 }
// XI #0 → value = 2（存入单字节）
// 大小 = 1 字节，与 Bool 相同

// 纯 Overflow — UInt32 payload（0 个 XI）
enum E { case p(UInt32); case e0; case e1; case e2; case e3; case e4 }
// payloadSize=4, 5 个 overflow case
// getEnumTagCounts(4, 5, 1) → numTags=2, numTagBytes=1
// 大小 = 5 字节（4 payload + 1 tag）
//
// e0: tag=1, payload=0x00000000
// e1: tag=1, payload=0x01000000  (little-endian)
// e2: tag=1, payload=0x02000000
// ...

// 小 payload overflow — UInt8（0 个 XI）
enum E { case p(UInt8); case e0; case e1; case e2 }
// payloadSize=1, 3 个 overflow case
// payloadSize < 4 → casesPerTag = 256
// getEnumTagCounts(1, 3, 1) → numTags=2, numTagBytes=1
// 大小 = 2 字节（1 payload + 1 tag）
//
// e0: tag=1, payload=0x00
// e1: tag=1, payload=0x01
// e2: tag=1, payload=0x02
```

---

## 字节序

Swift 枚举在内存中使用 **little-endian** 字节序。多字节整数值低字节在前。

```swift
enum E { case a(UInt32); case b(UInt32); case e0 }
// case a(1000):
//   payload 字节: [0xE8, 0x03, 0x00, 0x00]  (1000 的 little-endian 表示)
//   tag 字节:     [0x00]                      (case 索引 0)
```

---

## Scatter Bits 操作

在 spare bits 策略中，tag 值不是连续存储的，而是 **scatter**（散射）到 spare bits 的位置上。

```
假设 spare bits mask = 0b1000_0001（bit 0 和 bit 7 是 spare）

要存储 tag = 3 (0b11):
  tag 的 bit 0 → spare bit 位置 0 → 字节 bit 0 = 1
  tag 的 bit 1 → spare bit 位置 1 → 字节 bit 7 = 1
  结果: 0b1000_0001

要存储 tag = 2 (0b10):
  tag 的 bit 0 → spare bit 位置 0 → 字节 bit 0 = 0
  tag 的 bit 1 → spare bit 位置 1 → 字节 bit 7 = 1
  结果: 0b1000_0000
```

对于 empty case，occupied bits（spare bits 的补集）用同样的 scatter 方式存储 payloadValue。两者 OR 合并形成最终的内存字节。

---

## Value Witness Table 中的关键字段

| 字段 | 说明 |
|---|---|
| `size` | 值的实际大小（字节） |
| `stride` | 值在数组中的步长（含对齐填充） |
| `flags` | 包含对齐掩码等标志 |
| `numExtraInhabitants` | 该类型提供的 XI 数量 |

对于 single-payload enum，`numExtraInhabitants` 决定了可用的 XI 数量。这个值从 **payload 类型**的 VWT 读取，而不是 enum 自身的 VWT（enum 自身的 VWT 是已经消耗过 XI 后的剩余数）。

---

## 运行时源码参考

| 文件 | 说明 |
|---|---|
| `GenEnum.cpp` | IRGen 层枚举类型的代码生成（编译时策略选择和编码） |
| `TypeLowering.cpp` | 类型降级中的 enum 布局信息（包括 `MultiPayloadEnumTypeInfo`、`SinglePayloadEnumTypeInfo`、`TaggedMultiPayloadEnumTypeInfo`） |
| `Enum.cpp` | 运行时 enum metadata 初始化和 tag 存储/读取函数 |
| `EnumImpl.h` | `storeEnumTagSinglePayloadImpl` / `getEnumTagSinglePayloadImpl` 的模板实现 |
| `ABI/Enum.h` | `getEnumTagCounts` ABI 函数 |

---

## 总结对照表

| 特性 | Multi-Payload Spare Bits | Tagged Multi-Payload | Single Payload |
|---|---|---|---|
| Payload Case 数量 | ≥ 2 | ≥ 2 | = 1 |
| Tag 存储位置 | Payload 内的 spare bits（+ 可选 extra bytes） | Payload 之后的 extra bytes | XI: payload 内; Overflow: extra bytes |
| 内存开销 | 通常为 0（spare bits 复用） | numTagBytes（1/2/4 字节） | XI: 0; Overflow: numTagBytes |
| 适合的类型 | Class reference、Optional 等有 spare bits 的类型 | Integer、全值域类型 | 任何单 payload 类型 |
| Empty Case 编码 | Tag + payloadValue scatter 到 spare/occupied bits | Tag + payloadValue 到 extra tag bytes + payload area | XI: 无效位模式; Overflow: tag + payload 区域存索引 |
| 运行时源码 | `GenEnum.cpp: MultiPayloadEnumImplStrategy` | `Enum.cpp: swift_storeEnumTagMultiPayload` | `EnumImpl.h: storeEnumTagSinglePayloadImpl` |
