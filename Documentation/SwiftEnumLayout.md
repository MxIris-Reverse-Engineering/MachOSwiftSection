# Swift Enum Memory Layout 内部机制 / Internals

本文档详细描述 Swift 编译器如何在内存中表示枚举（enum）值。所有细节均基于 Swift 运行时源码（`GenEnum.cpp`、`TypeLowering.cpp`、`Enum.cpp`、`EnumImpl.h`、`ABI/Enum.h`）以及经过运行时验证的 `EnumLayoutCalculator` 实现。

This document describes in detail how the Swift compiler represents enum values in memory. All details are based on the Swift runtime source (`GenEnum.cpp`, `TypeLowering.cpp`, `Enum.cpp`, `EnumImpl.h`, `ABI/Enum.h`) and the runtime-verified `EnumLayoutCalculator` implementation.

---

## 术语 / Terminology

| 术语 / Term | 说明 / Description |
|---|---|
| **Payload Case** | 携带关联值的 case / A case that carries an associated value |
| **Empty Case** | 无关联值的 case / A case with no associated value |
| **Payload Size** | 所有 payload case 中最大关联值的字节大小 / Byte size of the largest associated value among all payload cases |
| **Tag** | 用于区分不同 case 的判别值 / A discriminator value to distinguish cases |
| **Extra Inhabitants (XI)** | payload 类型中不代表有效值的位模式，可复用来编码 empty case / Bit patterns in the payload type that don't represent valid values, reusable to encode empty cases |
| **Spare Bits** | 所有 payload 类型共有的、在合法值中永远为零的位 / Bits common to all payload types that are always zero in valid values |
| **Occupied Bits** | 非 spare bits 的位，即实际承载 payload 数据的位 / Non-spare bits that carry actual payload data |
| **Overflow** | 当 XI 不足以编码所有 empty case 时，在 payload 之后追加的额外 tag 字节 / Extra tag bytes appended after the payload when XI are insufficient |

---

## 策略选择 / Strategy Selection

Swift 编译器根据 payload case 的数量选择不同的内存布局策略：

The Swift compiler chooses a memory layout strategy based on the number of payload cases:

```
if numPayloadCases == 0:
    → No-Payload Enum (simple tag, not covered here)
    → 无 Payload 枚举（简单 tag，本文不讨论）
elif numPayloadCases == 1:
    → Single Payload Enum (Strategy 3)
    → 单 Payload 枚举（策略 3）
elif numPayloadCases >= 2:
    if payloads have common spare bits:
        → Multi-Payload Spare Bits (Strategy 1)
        → 多 Payload Spare Bits（策略 1）
    else:
        → Tagged Multi-Payload (Strategy 2)
        → Tagged 多 Payload（策略 2）
```

---

## 策略 1: Multi-Payload Spare Bits / Strategy 1: Multi-Payload Spare Bits

### 适用条件 / When Used

多个 payload case 且所有 payload 类型共享 spare bits（例如 class reference 在 arm64 上高位字节有 spare bits）。

Multiple payload cases where all payload types share common spare bits (e.g., class references on arm64 have spare bits in the top byte).

### 内存布局 / Memory Layout

```
┌──────────────────────────────────┬──────────────────┐
│      Payload Area (N bytes)      │ Extra Tag Bytes   │
│  [spare bits = tag] [rest = data]│ (if spare bits    │
│                                  │  insufficient)    │
└──────────────────────────────────┴──────────────────┘
```

### 核心算法 / Core Algorithm

**1. 构建 CommonSpareBits 掩码 / Build the CommonSpareBits mask**

对所有 payload 类型的 spare bits 取交集，得到 `CommonSpareBits`。这些位在所有合法 payload 值中都为 0。

Intersect spare bits across all payload types to get `CommonSpareBits`. These bits are zero in all valid payload values.

**2. 计算 Occupied Bits / Compute Occupied Bits**

```
occupiedBitCount = totalBits - spareBitCount
```

Occupied bits 是 spare bits 的补集，承载实际 payload 数据。

Occupied bits are the complement of spare bits, carrying actual payload data.

**3. 计算所需 tag 数 / Compute required tag count**

```
if occupiedBitCount >= 32:
    numEmptyElementTags = 1    // 所有 empty case 共享一个 tag / all empty cases share one tag
else:
    emptyElementsPerTag = 2^occupiedBitCount
    numEmptyElementTags = ceil(numEmptyCases / emptyElementsPerTag)

numTags = numPayloadCases + numEmptyElementTags
numTagBits = ceil(log2(numTags))
```

**4. 选择 tag 位 / Select tag bits**

```
if numTagBits <= spareBitCount:
    // 从最高有效位选取所需数量的 spare bits 作为 tag
    // Select required number of spare bits from most significant
    PayloadTagBits = keepMostSignificant(CommonSpareBits, numTagBits)
    extraTagBytes = 0
else:
    // Spare bits 不够：全部 spare bits + 额外 tag 字节
    // Not enough spare bits: use all + extra tag bytes
    PayloadTagBits = CommonSpareBits
    extraTagBitCount = numTagBits - spareBitCount
    extraTagBytes = ceil(extraTagBitCount / 8)
```

### Case 编码 / Case Encoding

**Payload Case（tag = caseIndex）：**

tag 值 scatter 到 spare bits 位置，低位在 payload 内的 spare bits，高位溢出到 extra tag bytes。

The tag value is scattered into spare bit positions. Lower bits go into spare bits within the payload, upper bits overflow to extra tag bytes.

```
memory = scatterBits(PayloadTagBits, tag_low) | payload_data
extra_tag_bytes = tag >> numPayloadTagBits  // 高位 / upper bits
```

**Empty Case：**

tag 和 payloadValue 分别 scatter 到 spare bits 和 occupied bits 中。

The tag and payloadValue are scattered into spare bits and occupied bits respectively.

```
if occupiedBitCount >= 32:
    payloadValue = emptyIndex
    tag = numPayloadCases         // 所有 empty case 共享同一 tag / single tag for all
else:
    payloadValue = emptyIndex & ((1 << occupiedBitCount) - 1)
    tag = numPayloadCases + (emptyIndex >> occupiedBitCount)

memory = scatterBits(PayloadTagBits, tag_low) | scatterBits(OccupiedBits, payloadValue)
```

### 示例 / Example

```swift
final class Ref1 { var x: Int = 0 }
final class Ref2 { var y: Int = 0 }
enum E { case a(Ref1); case b(Ref2); case e0; case e1; case e2 }
// arm64: spare bits in byte 7 (top byte), e.g. mask = 0x80 at offset 7
// 2 payload cases + 3 empty cases
// numTags = 2 + 1 = 3, numTagBits = 2
// 2 spare bits available → fits, no extra tag bytes
// Payload case a: tag=0 → spare bits = 0b00, byte 7 unchanged
// Payload case b: tag=1 → spare bits = 0b01, byte 7 bit set
// Empty case e0:  tag=2, payloadValue=0
// Empty case e1:  tag=2, payloadValue=1
// Empty case e2:  tag=2, payloadValue=2
```

---

## 策略 2: Tagged Multi-Payload / Strategy 2: Tagged Multi-Payload

### 适用条件 / When Used

多个 payload case 但无 spare bits（例如整数类型占满全部位域），或 generic/resilient payload。

Multiple payload cases with no spare bits (e.g., integer types that use all bit patterns), or generic/resilient payloads.

### 内存布局 / Memory Layout

```
┌──────────────────────────────────┬──────────────────┐
│      Payload Area (P bytes)      │  Tag (T bytes)   │
│     (user data or empty index)   │  (after payload) │
└──────────────────────────────────┴──────────────────┘
Total size = P + T
```

Tag 字节数由 `getEnumTagCounts` ABI 函数决定。

The number of tag bytes is determined by the `getEnumTagCounts` ABI function.

### getEnumTagCounts 算法 / getEnumTagCounts Algorithm

```
numTags = payloadCases
if emptyCases > 0:
    if payloadSize >= 4:
        numTags += 1           // 单个 tag 值足够 / one tag value suffices
    else:
        casesPerTagBitValue = 2^(payloadSize * 8)
        numTags += ceil(emptyCases / casesPerTagBitValue)

numTagBytes = 0 if numTags <= 1
            = 1 if numTags < 256
            = 2 if numTags < 65536
            = 4 otherwise
```

**关键分支：payloadSize < 4 vs ≥ 4 / Key Branch: payloadSize < 4 vs ≥ 4**

当 payloadSize ≥ 4（≥ 32 位）时，payload 区域足够大，可以用 payload 值直接编码所有 empty case 的索引，因此只需一个额外的 tag 值。当 payloadSize < 4 时，payload 区域容量有限，empty case 需要跨多个 tag 值分散编码。

When payloadSize ≥ 4 (≥ 32 bits), the payload area is large enough to encode all empty case indices directly, so only one extra tag value is needed. When payloadSize < 4, the payload area has limited capacity, and empty cases must be spread across multiple tag values.

### Case 编码 / Case Encoding

**Payload Case：**

```
tag = caseIndex                // 每个 payload case 一个唯一 tag / unique tag per payload case
payload = user_data            // 用户数据写入 payload 区域 / user data written to payload area
```

**Empty Case：**

```
if payloadSize >= 4:
    tag = numPayloadCases      // 所有 empty case 共享一个 tag / all share one tag
    payload = emptyIndex       // payload 区域存储 empty 索引 / payload area stores empty index
else:
    tag = numPayloadCases + (emptyIndex >> (payloadSize * 8))
    payload = emptyIndex & ((1 << (payloadSize * 8)) - 1)
```

### 示例 / Example

```swift
enum E { case a(UInt8); case b(UInt8); case e0; case e1; case e2 }
// payloadSize = 1, payloadCases = 2, emptyCases = 3
// payloadSize < 4 → casesPerTag = 2^8 = 256
// numTags = 2 + ceil(3/256) = 3, numTagBytes = 1
// Memory: [payload: 1 byte][tag: 1 byte] = 2 bytes total

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
// Memory: [payload: 4 bytes][tag: 1 byte] = 5 bytes total

// case a(1000):  payload=0xE8030000, tag=0x00
// case b(0):     payload=0x00000000, tag=0x01
// case e0:       payload=0x00000000, tag=0x02
```

---

## 策略 3: Single Payload / Strategy 3: Single Payload

### 适用条件 / When Used

恰好一个 payload case，加上一个或多个 empty case。这是 Swift 中最常见的模式（如 `Optional<T>`）。

Exactly one payload case plus one or more empty cases. This is the most common pattern in Swift (e.g., `Optional<T>`).

### 编码优先级 / Encoding Priority

Single payload 使用两级编码：先尝试 Extra Inhabitants，不够再用 Overflow。

Single payload uses two-level encoding: try Extra Inhabitants first, fall back to Overflow.

```
1. Extra Inhabitants (XI)    → 在 payload 区域内利用无效位模式 / invalid bit patterns within payload area
2. Overflow                  → 在 payload 之后追加 tag 字节 / extra tag bytes after payload
```

### 3a. Extra Inhabitants (XI) 编码 / Extra Inhabitants Encoding

**什么是 Extra Inhabitants / What are Extra Inhabitants**

某些类型不会用到全部位模式。未使用的位模式称为 Extra Inhabitants，可以被外层 enum 复用来编码 empty case，**无需额外内存开销**。

Some types don't use all their bit patterns. Unused patterns are called Extra Inhabitants and can be reused by the enclosing enum to encode empty cases **with zero memory overhead**.

| 类型 / Type | 大小 / Size | XI 数量 / XI Count | 说明 / Notes |
|---|---|---|---|
| `Bool` | 1 byte | 254 | 仅使用 0 和 1，值 2..255 为 XI / Only uses 0 and 1; values 2..255 are XI |
| `UInt8` | 1 byte | 0 | 使用全部 256 个值 / Uses all 256 values |
| `UInt16` | 2 bytes | 0 | 使用全部 65536 个值 / Uses all 65536 values |
| `UInt32` | 4 bytes | 0 | 使用全部 2^32 个值 / Uses all 2^32 values |
| `UInt64` | 8 bytes | 0 | 使用全部 2^64 个值 / Uses all 2^64 values |
| `Optional<UInt8>` | 2 bytes | 0 | 257 个状态（256 个 `.some` + `.none`）占满全部位模式 / 257 states (256 `.some` + `.none`) exhaust all bit patterns |
| Class reference | 8 bytes | 2^31 - 1 | 空指针 + 对齐无效指针 / Null pointer + aligned invalid pointers |

**重要：XI 来自 payload 类型的 VWT / Important: XI comes from the payload type's VWT**

`numExtraInhabitants` 从 payload 类型（而非外层 enum）的 Value Witness Table 获取。外层 enum 消耗这些 XI 后，其自身的 XI 会减少。

`numExtraInhabitants` is obtained from the **payload type's** (not the outer enum's) Value Witness Table. After the outer enum consumes these XI, its own XI count decreases.

```swift
// Bool has 254 XI
enum SP_Bool_3E { case p(Bool); case e0; case e1; case e2 }
// Uses 3 XI from Bool's 254 → enum size = 1 byte (same as Bool!)
// 从 Bool 的 254 个 XI 中消耗 3 个 → enum 大小 = 1 字节（与 Bool 相同！）

// Optional<UInt8> has 0 XI  (NOT 254!)
enum SP_OptU8_1E { case p(UInt8?); case e0 }
// Must use overflow → enum size = 3 bytes (2 payload + 1 tag)
// 必须用 overflow → enum 大小 = 3 字节（2 payload + 1 tag）
```

**XI 编码规则 / XI encoding rules：**

- `tagValue = 0`（与 payload case 的 tag 值相同 / same as payload case's tag value）
- Extra tag bytes = 0（全部在 payload 区域内完成 / entirely within payload area）
- enum 大小 = payload 大小（无额外开销 / no overhead）

### 3b. Overflow 编码 / Overflow Encoding

当 XI 不足以编码所有 empty case 时，超出部分使用 overflow：在 payload 之后追加 extra tag bytes，并复用 payload 区域存储 overflow case 的索引。

When XI are insufficient for all empty cases, the excess uses overflow: extra tag bytes are appended after the payload, and the payload area is reused to store the overflow case index.

```
┌──────────────────────────────────┬──────────────────┐
│  Payload Area (reused for index) │ Extra Tag Bytes   │
└──────────────────────────────────┴──────────────────┘
```

**Overflow 编码算法 / Overflow encoding algorithm：**

```
overflowCases = numEmptyCases - numXICases
extraTagBytes = getEnumTagCounts(payloadSize, overflowCases, 1).numTagBytes

// 对每个 overflow case / For each overflow case:
if payloadSize >= 4:
    tagValue = 1                    // 单个 tag 值 / single tag value
    payloadValue = overflowIndex    // 索引直接存入 payload / index stored in payload
else:
    payloadBits = payloadSize * 8
    payloadValue = overflowIndex & ((1 << payloadBits) - 1)
    tagValue = 1 + (overflowIndex >> payloadBits)
```

### 3c. Hybrid: XI + Overflow 混合 / Hybrid: XI + Overflow

当 payload 类型有部分 XI 但不够编码所有 empty case 时，两种策略混合使用：

When the payload type has some XI but not enough for all empty cases, both strategies are combined:

```
numXICases = min(numEmptyCases, numExtraInhabitants)
numOverflowCases = numEmptyCases - numXICases

// 前 numXICases 个 empty case 用 XI 编码 / First numXICases empty cases use XI
// 剩余 numOverflowCases 个用 overflow 编码 / Remaining use overflow
```

### 示例 / Examples

```swift
// XI only — Bool payload (254 XI)
// 纯 XI — Bool payload（254 个 XI）
enum E { case p(Bool); case e0 }
// XI #0 → value = 2 (stored in single byte)
// Size = 1 byte, same as Bool
// 大小 = 1 字节，与 Bool 相同

// Overflow only — UInt32 payload (0 XI)
// 纯 Overflow — UInt32 payload（0 个 XI）
enum E { case p(UInt32); case e0; case e1; case e2; case e3; case e4 }
// payloadSize=4, 5 overflow cases
// getEnumTagCounts(4, 5, 1) → numTags=2, numTagBytes=1
// Size = 5 bytes (4 payload + 1 tag)
// 大小 = 5 字节（4 payload + 1 tag）
//
// e0: tag=1, payload=0x00000000
// e1: tag=1, payload=0x01000000  (little-endian)
// e2: tag=1, payload=0x02000000
// ...

// Overflow with small payload — UInt8 (0 XI)
// 小 payload overflow — UInt8（0 个 XI）
enum E { case p(UInt8); case e0; case e1; case e2 }
// payloadSize=1, 3 overflow cases
// payloadSize < 4 → casesPerTag = 256
// getEnumTagCounts(1, 3, 1) → numTags=2, numTagBytes=1
// Size = 2 bytes (1 payload + 1 tag)
// 大小 = 2 字节（1 payload + 1 tag）
//
// e0: tag=1, payload=0x00
// e1: tag=1, payload=0x01
// e2: tag=1, payload=0x02
```

---

## 字节序 / Byte Order

Swift 枚举在内存中使用 **little-endian** 字节序。多字节整数值低字节在前。

Swift enums use **little-endian** byte order in memory. Multi-byte integer values have the least significant byte first.

```swift
enum E { case a(UInt32); case b(UInt32); case e0 }
// case a(1000):
//   payload bytes: [0xE8, 0x03, 0x00, 0x00]  (1000 in little-endian)
//   tag byte:      [0x00]                      (case index 0)
```

---

## Scatter Bits 操作 / Scatter Bits Operation

在 spare bits 策略中，tag 值不是连续存储的，而是 **scatter**（散射）到 spare bits 的位置上。

In the spare bits strategy, the tag value is not stored contiguously but **scattered** into spare bit positions.

```
假设 spare bits mask = 0b1000_0001（bit 0 和 bit 7 是 spare）
Suppose spare bits mask = 0b1000_0001 (bit 0 and bit 7 are spare)

要存储 tag = 3 (0b11):
To store tag = 3 (0b11):
  bit 0 of tag → spare bit position 0 → byte bit 0 = 1
  bit 1 of tag → spare bit position 1 → byte bit 7 = 1
  结果 / result: 0b1000_0001

要存储 tag = 2 (0b10):
To store tag = 2 (0b10):
  bit 0 of tag → spare bit position 0 → byte bit 0 = 0
  bit 1 of tag → spare bit position 1 → byte bit 7 = 1
  结果 / result: 0b1000_0000
```

对于 empty case，occupied bits（spare bits 的补集）用同样的 scatter 方式存储 payloadValue。两者 OR 合并形成最终的内存字节。

For empty cases, occupied bits (complement of spare bits) store the payloadValue using the same scatter operation. Both are OR-combined to form the final memory bytes.

---

## Value Witness Table 中的关键字段 / Key Fields in VWT

| 字段 / Field | 说明 / Description |
|---|---|
| `size` | 值的实际大小（字节）/ Actual size of the value in bytes |
| `stride` | 值在数组中的步长（含对齐填充）/ Stride in arrays (includes alignment padding) |
| `flags` | 包含对齐掩码等标志 / Contains alignment mask and other flags |
| `numExtraInhabitants` | 该类型提供的 XI 数量 / Number of XI this type provides |

对于 single-payload enum，`numExtraInhabitants` 决定了可用的 XI 数量。这个值从 **payload 类型**的 VWT 读取，而不是 enum 自身的 VWT（enum 自身的 VWT 是已经消耗过 XI 后的剩余数）。

For single-payload enums, `numExtraInhabitants` determines available XI. This value is read from the **payload type's** VWT, not the enum's own VWT (the enum's own VWT shows the remaining count after consuming XI).

---

## 运行时源码参考 / Runtime Source References

| 文件 / File | 说明 / Description |
|---|---|
| `GenEnum.cpp` | IRGen 层枚举类型的代码生成（编译时策略选择和编码）/ IRGen layer enum codegen (compile-time strategy selection and encoding) |
| `TypeLowering.cpp` | 类型降级中的 enum 布局信息（包括 `MultiPayloadEnumTypeInfo`、`SinglePayloadEnumTypeInfo`、`TaggedMultiPayloadEnumTypeInfo`）/ Enum layout info in type lowering |
| `Enum.cpp` | 运行时 enum metadata 初始化和 tag 存储/读取函数 / Runtime enum metadata init and tag store/load functions |
| `EnumImpl.h` | `storeEnumTagSinglePayloadImpl` / `getEnumTagSinglePayloadImpl` 的模板实现 / Template implementations for single-payload tag operations |
| `ABI/Enum.h` | `getEnumTagCounts` ABI 函数 / ABI function for tag count calculation |

---

## 总结对照表 / Summary Comparison Table

| 特性 / Feature | Multi-Payload Spare Bits | Tagged Multi-Payload | Single Payload |
|---|---|---|---|
| Payload Case 数量 / Count | ≥ 2 | ≥ 2 | = 1 |
| Tag 存储位置 / Tag Location | Payload 内的 spare bits（+ 可选 extra bytes）/ Spare bits within payload (+ optional extra bytes) | Payload 之后的 extra bytes / Extra bytes after payload | XI: payload 内 / within payload; Overflow: extra bytes |
| 内存开销 / Memory Overhead | 通常为 0（spare bits 复用）/ Usually 0 (reuses spare bits) | numTagBytes（1/2/4 字节）/ numTagBytes (1/2/4 bytes) | XI: 0; Overflow: numTagBytes |
| 适合的类型 / Suitable Types | Class reference、Optional 等有 spare bits 的类型 / Types with spare bits | Integer、全值域类型 / Full-range types like integers | 任何单 payload 类型 / Any single-payload type |
| Empty Case 编码 / Encoding | Tag + payloadValue scatter 到 spare/occupied bits / Scattered into spare/occupied bits | Tag + payloadValue 到 extra tag bytes + payload area / Written to extra tag bytes + payload area | XI: 无效位模式 / invalid pattern; Overflow: tag + index in payload area |
| 运行时源码 / Runtime Source | `GenEnum.cpp: MultiPayloadEnumImplStrategy` | `Enum.cpp: swift_storeEnumTagMultiPayload` | `EnumImpl.h: storeEnumTagSinglePayloadImpl` |
