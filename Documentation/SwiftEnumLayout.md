# Swift Enum Memory Layout Internals

This document describes in detail how the Swift compiler represents enum values in memory. All details are based on the Swift runtime source (`GenEnum.cpp`, `TypeLowering.cpp`, `Enum.cpp`, `EnumImpl.h`, `ABI/Enum.h`) and the runtime-verified `EnumLayoutCalculator` implementation.

---

## Terminology

| Term | Description |
|---|---|
| **Payload Case** | A case that carries an associated value |
| **Empty Case** | A case with no associated value |
| **Payload Size** | Byte size of the largest associated value among all payload cases |
| **Tag** | A discriminator value to distinguish cases |
| **Extra Inhabitants (XI)** | Bit patterns in the payload type that don't represent valid values, reusable to encode empty cases |
| **Spare Bits** | Bits common to all payload types that are always zero in valid values |
| **Occupied Bits** | Non-spare bits that carry actual payload data |
| **Overflow** | Extra tag bytes appended after the payload when XI are insufficient |

---

## Strategy Selection

The Swift compiler chooses a memory layout strategy based on the number of payload cases:

```
if numPayloadCases == 0:
    → No-Payload Enum (simple tag, not covered here)
elif numPayloadCases == 1:
    → Single Payload Enum (Strategy 3)
elif numPayloadCases >= 2:
    if payloads have common spare bits:
        → Multi-Payload Spare Bits (Strategy 1)
    else:
        → Tagged Multi-Payload (Strategy 2)
```

---

## Strategy 1: Multi-Payload Spare Bits

### When Used

Multiple payload cases where all payload types share common spare bits (e.g., class references on arm64 have spare bits in the top byte).

### Memory Layout

```
┌──────────────────────────────────┬──────────────────┐
│      Payload Area (N bytes)      │ Extra Tag Bytes   │
│  [spare bits = tag] [rest = data]│ (if spare bits    │
│                                  │  insufficient)    │
└──────────────────────────────────┴──────────────────┘
```

### Core Algorithm

**1. Build the CommonSpareBits mask**

Intersect spare bits across all payload types to get `CommonSpareBits`. These bits are zero in all valid payload values.

**2. Compute Occupied Bits**

```
occupiedBitCount = totalBits - spareBitCount
```

Occupied bits are the complement of spare bits, carrying actual payload data.

**3. Compute required tag count**

```
if occupiedBitCount >= 32:
    numEmptyElementTags = 1    // all empty cases share one tag
else:
    emptyElementsPerTag = 2^occupiedBitCount
    numEmptyElementTags = ceil(numEmptyCases / emptyElementsPerTag)

numTags = numPayloadCases + numEmptyElementTags
numTagBits = ceil(log2(numTags))
```

**4. Select tag bits**

```
if numTagBits <= spareBitCount:
    // Select required number of spare bits from most significant
    PayloadTagBits = keepMostSignificant(CommonSpareBits, numTagBits)
    extraTagBytes = 0
else:
    // Not enough spare bits: use all + extra tag bytes
    PayloadTagBits = CommonSpareBits
    extraTagBitCount = numTagBits - spareBitCount
    extraTagBytes = ceil(extraTagBitCount / 8)
```

### Case Encoding

**Payload Case (tag = caseIndex):**

The tag value is scattered into spare bit positions. Lower bits go into spare bits within the payload, upper bits overflow to extra tag bytes.

```
memory = scatterBits(PayloadTagBits, tag_low) | payload_data
extra_tag_bytes = tag >> numPayloadTagBits  // upper bits
```

**Empty Case:**

The tag and payloadValue are scattered into spare bits and occupied bits respectively.

```
if occupiedBitCount >= 32:
    payloadValue = emptyIndex
    tag = numPayloadCases         // single tag for all
else:
    payloadValue = emptyIndex & ((1 << occupiedBitCount) - 1)
    tag = numPayloadCases + (emptyIndex >> occupiedBitCount)

memory = scatterBits(PayloadTagBits, tag_low) | scatterBits(OccupiedBits, payloadValue)
```

### Example

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

## Strategy 2: Tagged Multi-Payload

### When Used

Multiple payload cases with no spare bits (e.g., integer types that use all bit patterns), or generic/resilient payloads.

### Memory Layout

```
┌──────────────────────────────────┬──────────────────┐
│      Payload Area (P bytes)      │  Tag (T bytes)   │
│     (user data or empty index)   │  (after payload) │
└──────────────────────────────────┴──────────────────┘
Total size = P + T
```

The number of tag bytes is determined by the `getEnumTagCounts` ABI function.

### getEnumTagCounts Algorithm

```
numTags = payloadCases
if emptyCases > 0:
    if payloadSize >= 4:
        numTags += 1           // one tag value suffices
    else:
        casesPerTagBitValue = 2^(payloadSize * 8)
        numTags += ceil(emptyCases / casesPerTagBitValue)

numTagBytes = 0 if numTags <= 1
            = 1 if numTags < 256
            = 2 if numTags < 65536
            = 4 otherwise
```

**Key Branch: payloadSize < 4 vs ≥ 4**

When payloadSize ≥ 4 (≥ 32 bits), the payload area is large enough to encode all empty case indices directly, so only one extra tag value is needed. When payloadSize < 4, the payload area has limited capacity, and empty cases must be spread across multiple tag values.

### Case Encoding

**Payload Case:**

```
tag = caseIndex                // unique tag per payload case
payload = user_data            // user data written to payload area
```

**Empty Case:**

```
if payloadSize >= 4:
    tag = numPayloadCases      // all share one tag
    payload = emptyIndex       // payload area stores empty index
else:
    tag = numPayloadCases + (emptyIndex >> (payloadSize * 8))
    payload = emptyIndex & ((1 << (payloadSize * 8)) - 1)
```

### Examples

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

## Strategy 3: Single Payload

### When Used

Exactly one payload case plus one or more empty cases. This is the most common pattern in Swift (e.g., `Optional<T>`).

### Encoding Priority

Single payload uses two-level encoding: try Extra Inhabitants first, fall back to Overflow.

```
1. Extra Inhabitants (XI)    → invalid bit patterns within payload area
2. Overflow                  → extra tag bytes after payload
```

### 3a. Extra Inhabitants (XI) Encoding

**What are Extra Inhabitants**

Some types don't use all their bit patterns. Unused patterns are called Extra Inhabitants and can be reused by the enclosing enum to encode empty cases **with zero memory overhead**.

| Type | Size | XI Count | Notes |
|---|---|---|---|
| `Bool` | 1 byte | 254 | Only uses 0 and 1; values 2..255 are XI |
| `UInt8` | 1 byte | 0 | Uses all 256 values |
| `UInt16` | 2 bytes | 0 | Uses all 65536 values |
| `UInt32` | 4 bytes | 0 | Uses all 2^32 values |
| `UInt64` | 8 bytes | 0 | Uses all 2^64 values |
| `Optional<UInt8>` | 2 bytes | 0 | 257 states (256 `.some` + `.none`) exhaust all bit patterns |
| Class reference | 8 bytes | 2^31 - 1 | Null pointer + aligned invalid pointers |

**Important: XI comes from the payload type's VWT**

`numExtraInhabitants` is obtained from the **payload type's** (not the outer enum's) Value Witness Table. After the outer enum consumes these XI, its own XI count decreases.

```swift
// Bool has 254 XI
enum SP_Bool_3E { case p(Bool); case e0; case e1; case e2 }
// Uses 3 XI from Bool's 254 → enum size = 1 byte (same as Bool!)

// Optional<UInt8> has 0 XI  (NOT 254!)
enum SP_OptU8_1E { case p(UInt8?); case e0 }
// Must use overflow → enum size = 3 bytes (2 payload + 1 tag)
```

**XI encoding rules:**

- `tagValue = 0` (same as payload case's tag value)
- Extra tag bytes = 0 (entirely within payload area)
- enum size = payload size (no overhead)

### 3b. Overflow Encoding

When XI are insufficient for all empty cases, the excess uses overflow: extra tag bytes are appended after the payload, and the payload area is reused to store the overflow case index.

```
┌──────────────────────────────────┬──────────────────┐
│  Payload Area (reused for index) │ Extra Tag Bytes   │
└──────────────────────────────────┴──────────────────┘
```

**Overflow encoding algorithm:**

```
overflowCases = numEmptyCases - numXICases
extraTagBytes = getEnumTagCounts(payloadSize, overflowCases, 1).numTagBytes

// For each overflow case:
if payloadSize >= 4:
    tagValue = 1                    // single tag value
    payloadValue = overflowIndex    // index stored in payload
else:
    payloadBits = payloadSize * 8
    payloadValue = overflowIndex & ((1 << payloadBits) - 1)
    tagValue = 1 + (overflowIndex >> payloadBits)
```

### 3c. Hybrid: XI + Overflow

When the payload type has some XI but not enough for all empty cases, both strategies are combined:

```
numXICases = min(numEmptyCases, numExtraInhabitants)
numOverflowCases = numEmptyCases - numXICases

// First numXICases empty cases use XI
// Remaining use overflow
```

### Examples

```swift
// XI only — Bool payload (254 XI)
enum E { case p(Bool); case e0 }
// XI #0 → value = 2 (stored in single byte)
// Size = 1 byte, same as Bool

// Overflow only — UInt32 payload (0 XI)
enum E { case p(UInt32); case e0; case e1; case e2; case e3; case e4 }
// payloadSize=4, 5 overflow cases
// getEnumTagCounts(4, 5, 1) → numTags=2, numTagBytes=1
// Size = 5 bytes (4 payload + 1 tag)
//
// e0: tag=1, payload=0x00000000
// e1: tag=1, payload=0x01000000  (little-endian)
// e2: tag=1, payload=0x02000000
// ...

// Overflow with small payload — UInt8 (0 XI)
enum E { case p(UInt8); case e0; case e1; case e2 }
// payloadSize=1, 3 overflow cases
// payloadSize < 4 → casesPerTag = 256
// getEnumTagCounts(1, 3, 1) → numTags=2, numTagBytes=1
// Size = 2 bytes (1 payload + 1 tag)
//
// e0: tag=1, payload=0x00
// e1: tag=1, payload=0x01
// e2: tag=1, payload=0x02
```

---

## Byte Order

Swift enums use **little-endian** byte order in memory. Multi-byte integer values have the least significant byte first.

```swift
enum E { case a(UInt32); case b(UInt32); case e0 }
// case a(1000):
//   payload bytes: [0xE8, 0x03, 0x00, 0x00]  (1000 in little-endian)
//   tag byte:      [0x00]                      (case index 0)
```

---

## Scatter Bits Operation

In the spare bits strategy, the tag value is not stored contiguously but **scattered** into spare bit positions.

```
Suppose spare bits mask = 0b1000_0001 (bit 0 and bit 7 are spare)

To store tag = 3 (0b11):
  bit 0 of tag → spare bit position 0 → byte bit 0 = 1
  bit 1 of tag → spare bit position 1 → byte bit 7 = 1
  result: 0b1000_0001

To store tag = 2 (0b10):
  bit 0 of tag → spare bit position 0 → byte bit 0 = 0
  bit 1 of tag → spare bit position 1 → byte bit 7 = 1
  result: 0b1000_0000
```

For empty cases, occupied bits (complement of spare bits) store the payloadValue using the same scatter operation. Both are OR-combined to form the final memory bytes.

---

## Key Fields in Value Witness Table

| Field | Description |
|---|---|
| `size` | Actual size of the value in bytes |
| `stride` | Stride in arrays (includes alignment padding) |
| `flags` | Contains alignment mask and other flags |
| `numExtraInhabitants` | Number of XI this type provides |

For single-payload enums, `numExtraInhabitants` determines available XI. This value is read from the **payload type's** VWT, not the enum's own VWT (the enum's own VWT shows the remaining count after consuming XI).

---

## Runtime Source References

| File | Description |
|---|---|
| `GenEnum.cpp` | IRGen layer enum codegen (compile-time strategy selection and encoding) |
| `TypeLowering.cpp` | Enum layout info in type lowering (`MultiPayloadEnumTypeInfo`, `SinglePayloadEnumTypeInfo`, `TaggedMultiPayloadEnumTypeInfo`) |
| `Enum.cpp` | Runtime enum metadata init and tag store/load functions |
| `EnumImpl.h` | Template implementations for single-payload tag operations (`storeEnumTagSinglePayloadImpl` / `getEnumTagSinglePayloadImpl`) |
| `ABI/Enum.h` | ABI function for tag count calculation (`getEnumTagCounts`) |

---

## Summary Comparison Table

| Feature | Multi-Payload Spare Bits | Tagged Multi-Payload | Single Payload |
|---|---|---|---|
| Payload Case Count | ≥ 2 | ≥ 2 | = 1 |
| Tag Location | Spare bits within payload (+ optional extra bytes) | Extra bytes after payload | XI: within payload; Overflow: extra bytes |
| Memory Overhead | Usually 0 (reuses spare bits) | numTagBytes (1/2/4 bytes) | XI: 0; Overflow: numTagBytes |
| Suitable Types | Types with spare bits (class reference, Optional, etc.) | Full-range types like integers | Any single-payload type |
| Empty Case Encoding | Tag + payloadValue scattered into spare/occupied bits | Tag + payloadValue written to extra tag bytes + payload area | XI: invalid pattern; Overflow: tag + index in payload area |
| Runtime Source | `GenEnum.cpp: MultiPayloadEnumImplStrategy` | `Enum.cpp: swift_storeEnumTagMultiPayload` | `EnumImpl.h: storeEnumTagSinglePayloadImpl` |
