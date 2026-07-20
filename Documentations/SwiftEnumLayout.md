# Swift Enum Memory Layout — From First Principles to Mastery

Swift enums are famously compact: `Optional<SomeClass>` is 8 bytes, an enum over two class references is still 8 bytes, and adding empty cases to an enum wrapping a `Bool` costs nothing at all. The machinery behind this is one of the most intricate parts of the Swift ABI, spread across the compiler's IR generation, the runtime, and the reflection library.

This document explains that machinery **from the ground up**:

- **[Part 1 — The Practical Guide](#part-1--the-practical-guide)** is for readers who want to *predict sizes and read layout dumps* without studying the ABI. If that is all you need, you can stop after Part 1.
- **[Part 2 — The Three Strategies](#part-2--the-three-strategies)** derives the actual layout algorithms — the formulas, the case encodings, the exact byte patterns — with worked examples.
- **[Part 3 — Mastery](#part-3--mastery-the-machinery-in-the-source)** dissects the implementation across the Swift source tree: who computes what and when, the bit-level anatomy of spare-bits layouts, why offline tools fundamentally cannot recover some information, and how this project (MachOSwiftSection) implements both a runtime-exact and a static (offline) layout engine.

**Conventions used throughout:**

- All Swift source citations are pinned to the [`swift-6.3.3-RELEASE`](https://github.com/swiftlang/swift/tree/swift-6.3.3-RELEASE) tag and given as `path/to/File.ext:line`. For example [`include/swift/ABI/Enum.h:29`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/ABI/Enum.h#L29) is line 29 of that file at that tag.
- The platform is **64-bit little-endian Apple platforms** (arm64 / x86_64 macOS, iOS, …). Byte dumps read left to right from offset 0, so a multi-byte integer's *least* significant byte prints first.
- **Every byte dump in this document is real output**, produced by probe programs (`MemoryLayout` + `withUnsafeBytes`) compiled with the Swift 6.3.3 toolchain on arm64 macOS — the same version as the cited sources.

---

## Part 1 — The Practical Guide

### 1.1 Three questions decide everything

To predict an enum's layout you only need to answer three questions:

1. **How many cases carry a payload?** Zero payloads means the enum is just a small integer tag. One payload selects the "single-payload" strategy. Two or more selects one of two "multi-payload" strategies.
2. **How big is the biggest payload?** The enum always reserves a *payload area* the size of its largest payload. Everything else is about where the discriminator (the *tag*) goes.
3. **Do the payloads have unused bit patterns?** Types like class references, `Bool`, and `String` cannot use every possible bit pattern of their storage. Swift aggressively reuses those impossible patterns to store the tag *inside* the payload area — for free. Types like `Int`, `UInt8`, or `Double` use all their bits, so the tag must live in extra bytes appended after the payload.

The unused patterns come in two flavors you will meet constantly:

- **Extra inhabitants (XI)** — whole *values* the payload type can never be (for example, a class reference is never a small integer like `0x0` or `0x1`). Used by single-payload enums.
- **Spare bits** — individual *bits* that are zero in every valid value of every payload (for example, the top bits of a 64-bit pointer). Used by multi-payload enums.

### 1.2 A tour of five enums

The following dumps are the entire subject of this document in miniature.

**A no-payload enum is a byte-sized tag** (0, 1, 2, … in declaration order):

```swift
enum Direction {
    case north
    case south
    case east
    case west
}
// size=1  .north=[00]  .west=[03]
```

**A single-payload enum over a type with no unused patterns appends a tag byte** — and reuses the payload area to number the empty cases:

```swift
enum Fetched {
    case payload(UInt32)
    case missing
    case failed
}
// size=5 (4 payload + 1 tag)
// .payload(1000) = [e8 03 00 00 | 00]   tag 0 = "valid payload"
// .missing       = [00 00 00 00 | 01]   tag 1, payload area holds index 0
// .failed        = [01 00 00 00 | 01]   tag 1, payload area holds index 1
```

**A single-payload enum over a type *with* unused patterns is free**:

```swift
final class Renderer {
    var identifier = 0
}
// Optional<Renderer>: size=8 — same as the bare reference!
// .none = [00 00 00 00 00 00 00 00]    (the "null pointer" extra inhabitant)

enum ThreeBools {
    case value(Bool)
    case unset
    case invalid
}
// size=1 — Bool only uses 0 and 1, so 2..255 are free tags:
// .value(false)=[00]  .value(true)=[01]  .unset=[02]  .invalid=[03]
```

**A multi-payload enum over class references hides its tag in pointer bits**:

```swift
final class Compositor {
    var identifier = 0
}

enum Backend {
    case metal(Renderer)      // byte 7 top bits = 00
    case software(Compositor) // byte 7 top bits = 01  (bit 62 set)
    case headless             // [00 00 00 00 00 00 00 80]  (bit 63 set)
    case disabled             // [08 00 00 00 00 00 00 80]
}
// size=8 — still just one pointer wide.
```

**A multi-payload enum over integers appends a tag byte**:

```swift
enum TwoU32 {
    case a(UInt32)
    case b(UInt32)
    case e0
}
// size=5
// .a(1000) = [e8 03 00 00 | 00]   tag 0
// .b(0)    = [00 00 00 00 | 01]   tag 1
// .e0      = [00 00 00 00 | 02]   tag 2, payload area zeroed
```

### 1.3 Size cheat sheet

All values verified on arm64 macOS, Swift 6.3.3.

| Enum shape | Size | Why |
|---|---|---|
| `enum { case a, b, c }` (≤ 256 cases) | 1 | tag byte; 2 bytes up to 65536 cases, 4 beyond |
| `Optional<AnyObject>` / any class reference | 8 | null + low invalid addresses are extra inhabitants |
| `Optional<UnsafeRawPointer>` | 8 | null is the *single* extra inhabitant |
| `Optional<UnsafeRawPointer?>` | 9 | …so the second `Optional` layer must add a tag byte |
| `Optional<Bool>` | 1 | `Bool` has 254 extra inhabitants (2…255) |
| `Optional<String>` | 16 | `String` reserves a huge extra-inhabitant space |
| `Optional<Int>` | 9 | `Int` uses all 2⁶⁴ patterns → tag byte appended |
| `Optional<Int?>` | 10 | each XI-less `Optional` layer adds one byte |
| `Optional<(() -> Void)>` | 16 | function = (code pointer, context); code pointer word carries XI |
| 2+ class payloads (`Backend` above) | 8 | tag lives in the pointers' spare bits |
| 2+ integer payloads (`TwoU32` above) | payload + 1 | no spare bits → appended tag byte |
| any *generic* enum with 2+ payloads, e.g. `enum G<T> { case a(T); case b(T) }` as `G<Renderer>` | 9 | generic layouts never use spare bits — see [2.7](#27-tagged-multi-payload) |
| `indirect` cases | 8 per case | an indirect payload is a heap box pointer |
| `enum { case v(Void); case e }` | 1 | zero-sized payloads are laid out as empty cases |
| `Never` (uninhabited) | 0 | no values, no storage (stride still 1) |

> **`size` vs `stride`:** `size` is the meaningful extent (what this document discusses); `stride` rounds size up to alignment for array elements. `TwoU32` has size 5 but stride 8; `Int?` has size 9 but stride 16.

### 1.4 Rules of thumb

- **Empty cases are free until the payload's extra inhabitants run out.** `Optional<SomeClass>` with a hundred more empty cases would still be 8 bytes.
- **Pointers are XI goldmines; integers are XI deserts.** Class references have about 2³¹ extra inhabitants; `Int`, `UInt8`, and `Double` have none; `Bool` has 254; `UnsafeRawPointer` has exactly 1 (null).
- **Each `Optional` layer consumes exactly one extra inhabitant.** Layers are free while inhabitants last (`Bool??` is 1 byte), then each costs a byte (`Int??` is 10, `Int???` is 11).
- **Multi-payload enums of class references stay pointer-sized;** mixing in a payload without spare bits (an `Int`) forces an appended tag byte.
- **Generic enums pay the tagged cost** even when instantiated with pointer-rich types: `G<Renderer>` above is 9 bytes where the equivalent non-generic enum is 8.
- **`indirect` makes the payload a pointer** — an indirect single-payload enum is exactly `Optional`-of-class-shaped: 8 bytes, empty cases at `0x0`, `0x1`, ….

### 1.5 Seeing layouts with `swift-section`

This project renders all of the above from a binary — no process needed:

```bash
swift-section dump --emit-enum-layout /path/to/binary
# or, with progressively terser comment styles:
swift-section dump --emit-enum-layout --enum-layout-style explained ...
swift-section dump --emit-enum-layout --enum-layout-style standard ...
swift-section dump --emit-enum-layout --enum-layout-style inline ...
swift-section dump --emit-enum-layout --enum-layout-style compact ...
```

Real output for the `Backend` enum above (`detailed` style, abridged):

```
enum EnumSample.Backend {
    /* Multi-Payload (tag in payload spare bits) — cases: 4 (2 payload + 2 empty);
       tag values used: 3; tag bits: 2; tag region: offsets 7..<8 (2 bits);
       occupied-bits region: offsets 0..<8 (57 bits);
       leftover extra inhabitants for an outer enum: 125 */

    // Case 1 (0x01) `software` — payload case #1
    //   encoding: tag 1 scattered into the payloads' common spare bits; ...
    //   fixed bytes: byte[0x0] & 0b00000111 = 0b00000000, byte[0x7] & 0b11110000 = 0b01000000
    case software(EnumSample.Compositor)

    // Case 2 (0x02) `headless` — empty case #0
    //   encoding: tag 2 in the common spare bits + empty-case value 0 in the occupied bits
    //   fixed bytes: bytes[0x0..<0x8] = 0x8000000000000000
    case headless
    ...
}
```

How to read it:

- The **strategy line** names the layout strategy and its parameters.
- Each **case block** gives the case's tag value and the bytes that are fixed (deterministic) for that case.
- `byte[0x7] & 0b11110000 = 0b01000000` is a **partial byte**: only the masked bits are claimed. The other bits of that byte hold live payload data (here: pointer bits) — a crucial honesty detail explained in [Part 3.3](#33-bit-level-anatomy-of-the-spare-bits-layout).
- `leftover extra inhabitants` is what an *outer* enum wrapping this one could still use for free.

That is everything most users need. The rest of this document explains *why* these are the answers.

---

## Part 2 — The Three Strategies

### 2.1 How the compiler picks a strategy

Strategy selection happens in `EnumImplStrategy::get` ([`lib/IRGen/GenEnum.cpp:6394`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/GenEnum.cpp#L6394)). After classifying every case, the decision tree is:

```
resilient enum (layout unknown at compile time)   → ResilientEnumImplStrategy   (GenEnum.cpp:6523)
imported from C / @objc / C-compatible            → CCompatibleEnumImplStrategy (GenEnum.cpp:6541)
0 or 1 cases total                                → SingletonEnumImplStrategy   (GenEnum.cpp:6552)
≥ 2 payload cases                                 → MultiPayloadEnumImplStrategy(GenEnum.cpp:6559)
exactly 1 payload case                            → SinglePayloadEnumImplStrategy (GenEnum.cpp:6567)
otherwise (all cases empty)                       → NoPayloadEnumImplStrategy   (GenEnum.cpp:6575)
```

Three classification subtleties happen *before* the count:

- **`indirect` cases count as payload cases of type `Builtin.NativeObject`** (a heap box pointer) — `GenEnum.cpp:6452-6461`. The payload's real type never affects layout.
- **Zero-sized payloads (e.g. `Void`, `Never`) count as empty cases** — `GenEnum.cpp:6483-6489`. That is why `enum { case v(Void); case e }` is a 1-byte no-payload enum (verified: `.v(())` = `[00]`, `.e` = `[01]`).
- **Cases unavailable during lowering are treated as having no payload** — `GenEnum.cpp:6445-6450`.

The multi-payload strategy internally splits again: if the payloads share **spare bits**, the tag hides inside them ([2.6](#26-multi-payload-spare-bits)); if not — or the enum's layout is generic/dynamic — tag bytes are appended ([2.7](#27-tagged-multi-payload)).

### 2.2 Vocabulary

| Term | Meaning |
|---|---|
| **Payload case** | A case carrying an associated value |
| **Empty case** | A case with no associated value (after the reclassifications above) |
| **Payload area** | The first `max(payload sizes)` bytes of the enum value |
| **Tag** | The discriminator distinguishing cases |
| **Extra inhabitants (XI)** | Whole bit *patterns* a type's values never use, reusable by an enclosing enum |
| **Spare bits** | Individual *bits* that are zero in every valid value of a type |
| **Occupied bits** | The complement of spare bits — bits carrying real payload data |
| **Extra tag bytes** | Discriminator bytes appended after the payload area |
| **Case numbering** | Payload cases first (in declaration order), then empty cases (in declaration order). This is the numbering `getEnumTag`, reflection field records, and all formulas use. |

### 2.3 The shared helper: `getEnumTagCounts`

One tiny function underlies every "how many tag bytes?" answer in the ABI. It is short enough to quote in full ([`include/swift/ABI/Enum.h:28-49`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/ABI/Enum.h#L28-L49)):

```cpp
inline EnumTagCounts
getEnumTagCounts(size_t size, unsigned emptyCases, unsigned payloadCases) {
  // We can use the payload area with a tag bit set somewhere outside of the
  // payload area to represent cases. See how many bytes we need to cover
  // all the empty cases.
  unsigned numTags = payloadCases;
  if (emptyCases > 0) {
    if (size >= 4)
      // Assume that one tag bit is enough if the precise calculation overflows
      // an int32.
      numTags += 1;
    else {
      unsigned bits = size * 8U;
      unsigned casesPerTagBitValue = 1U << bits;
      numTags += ((emptyCases + (casesPerTagBitValue-1U)) >> bits);
    }
  }
  unsigned numTagBytes = (numTags <=    1 ? 0 :
                          numTags <   256 ? 1 :
                          numTags < 65536 ? 2 : 4);
  return {numTags, numTagBytes};
}
```

The reasoning: when a tag value says "this is an empty case", the payload area is dead storage — so it is *reused* to store an empty-case index. A payload area of `size` bytes can number `2^(size*8)` empty cases per tag value:

- **`size >= 4`**: the payload area can index 2³² empty cases — more than any real enum — so *one* extra tag value covers all empty cases.
- **`size < 4`**: a small payload area can only number `2^(size*8)` cases per tag value, so empty cases spread across `ceil(emptyCases / 2^(size*8))` tag values.

Worked examples:

```
getEnumTagCounts(size: 4, emptyCases: 2, payloadCases: 1)
  → numTags = 1 + 1 = 2       → 1 tag byte        (the `Fetched` enum: 4+1 = 5 bytes)

getEnumTagCounts(size: 1, emptyCases: 300, payloadCases: 1)
  → 300 empty cases / 256 per tag = 2 tag values → numTags = 3 → 1 tag byte

getEnumTagCounts(size: 0, emptyCases: 300, payloadCases: 1)
  → 2^0 = 1 case per tag → numTags = 1 + 300 = 301 → 2 tag bytes
```

Note the threshold is **4 bytes**, not pointer size — a common misremembering.

### 2.4 No-payload enums

All cases empty. The value *is* the tag: case `i` (declaration order) stores `i` as a little-endian integer of the smallest sufficient width:

| Case count | Size |
|---|---|
| 0 or 1 | 0 bytes |
| 2 … 256 | 1 byte |
| 257 … 65536 | 2 bytes |
| more | 4 bytes |

Verified: `Direction.north` = `[00]`, `.west` = `[03]`.

The values *above* the last case are the enum's own extra inhabitants — `NoPayloadEnumImplStrategy::getFixedExtraInhabitantCount` ([`GenEnum.cpp:1228-1236`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/GenEnum.cpp#L1228-L1236)):

```
XI = min(2^(size*8) − caseCount, MaxNumExtraInhabitants)
```

`Direction` has `256 − 4 = 252` extra inhabitants, so `Direction?` is still 1 byte (verified: `.none` = `[04]`). The cap `MaxNumExtraInhabitants = 0x7FFFFFFF` ([`include/swift/ABI/MetadataValues.h:183`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/ABI/MetadataValues.h#L183)) only matters for the 4-byte tag.

Two special relatives:

- **Uninhabited enums** (`Never`, `enum Empty {}`): handled by `SingletonEnumImplStrategy` — size 0, stride 1, **0 extra inhabitants** (there is no tag storage to reuse).
- **`@objc` / C-imported enums**: C-compatible layout — the size of the raw type, every bit pattern is a legal value, no extra inhabitants, no packing tricks.

### 2.5 Single-payload enums

Exactly one payload case, `N` empty cases. This is `Optional`'s strategy and the most common in real binaries.

The encoding has a strict two-level priority:

```
1. Extra inhabitants (XI)  — invalid payload bit patterns, inside the payload area, zero cost
2. Overflow                — extra tag bytes appended after the payload area
```

Memory shape:

```
XI-only form (enough inhabitants):     Overflow form (inhabitants ran out):
┌───────────────────────────┐          ┌───────────────────────────┬─────────────────┐
│   payload area (P bytes)  │          │   payload area (P bytes)  │ extra tag bytes │
│   payload value or        │          │   payload value or        │ (0 = "valid     │
│   XI pattern              │          │   overflow index          │  payload / XI") │
└───────────────────────────┘          └───────────────────────────┴─────────────────┘
size = P                               size = P + numTagBytes
```

#### 2.5.1 The size decision

The runtime's metadata instantiation states it exactly ([`stdlib/public/runtime/Enum.cpp:138-146`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/Enum.cpp#L138-L146)):

```cpp
size_t size;
if (payloadNumExtraInhabitants >= emptyCases) {
  size = payloadSize;
  unusedExtraInhabitants = payloadNumExtraInhabitants - emptyCases;
} else {
  size = payloadSize + getEnumTagCounts(payloadSize,
                                    emptyCases - payloadNumExtraInhabitants,
                                      1 /*payload case*/).numTagBytes;
}
```

In words: empty cases consume the payload's extra inhabitants first, in declaration order. Only the *overflow* — empty cases beyond the XI supply — forces extra tag bytes.

#### 2.5.2 Extra inhabitants: the currency

An extra inhabitant is a full-width bit pattern the payload type never produces. The **count** comes from the payload's value witness table; the **patterns** are the payload type's own private convention. Verified counts on 64-bit Darwin:

| Payload type | XI count | The patterns |
|---|---|---|
| `Bool` | 254 | values `2 … 255` |
| Class / `AnyObject` / heap references | `0x7FFF_FFFF` (saturated) | small invalid addresses `0x0, 0x1, 0x2, …` |
| `UnsafeRawPointer` family | 1 | null only |
| `String` | `0x7FFF_FFFF` (saturated) | reserved `_StringObject` discriminator patterns |
| Thick functions (`() -> Void`) | `0x7FFF_FFFF` on the code-pointer word | invalid function addresses |
| `Int`, `UInt8`, `Double`, … | 0 | — |
| `weak` references | 0 | — |
| `Optional<UInt8>` | 0 — **not 254!** | an overflowed single-payload enum keeps only its payload's leftover XI (`UInt8` has none); the unused values in its tag byte are deliberately not offered (see 3.1) |
| Another enum | its leftover XI | that enum's unused tag encodings |

The heap-reference count is worth deriving once, because it recurs everywhere. [`include/swift/Runtime/Metadata.h:925-939`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/Runtime/Metadata.h#L925-L939):

```cpp
inline constexpr unsigned swift_getHeapObjectExtraInhabitantCount() {
  // The runtime needs no more than INT_MAX inhabitants.
  return (LeastValidPointerValue >> ObjCReservedLowBits) > INT_MAX
    ? (unsigned)INT_MAX
    : (unsigned)(LeastValidPointerValue >> ObjCReservedLowBits);
}
```

On Darwin 64-bit, `LeastValidPointerValue` is `0x1_0000_0000` — the first 4 GiB of address space never holds Swift heap objects ([`stdlib/public/SwiftShims/swift/shims/System.h:153`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/SwiftShims/swift/shims/System.h#L153)). That exceeds `INT_MAX`, so the count saturates at `0x7FFF_FFFF`. The IRGen mirror is `PointerInfo::getExtraInhabitantCount` ([`lib/IRGen/ExtraInhabitants.cpp:50-61`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/ExtraInhabitants.cpp#L50-L61)).

**The consumption ledger.** When an enum spends `k` of its payload's inhabitants, the enum's own XI count is what remains — `SinglePayloadEnumImplStrategy::getFixedExtraInhabitantCount` ([`GenEnum.cpp:3457-3460`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/GenEnum.cpp#L3457-L3460)):

```cpp
return getFixedPayloadTypeInfo().getFixedExtraInhabitantCount(IGM)
         - getNumExtraInhabitantTagValues();
```

and its XI *values* are the payload's, shifted past the consumed ones. Watch the ledger run in a real chain (every dump verified):

```swift
enum ThreeBools {
    case value(Bool)
    case unset
    case invalid
}
// Bool's XI patterns: 2, 3, 4, 5, ...
// .unset   = [02]    ← consumed XI #0
// .invalid = [03]    ← consumed XI #1
// ThreeBools's own XI: 252 remaining, patterns starting at 4.

ThreeBools?.none          // = [04]  ← Optional consumed ThreeBools's XI #0
```

And the depletion case:

```swift
UnsafeRawPointer?          // 8 bytes; .none = [00 00 00 00 00 00 00 00] (the null XI)
UnsafeRawPointer??         // 9 bytes! the inner Optional consumed the only XI;
                           // .none         = [00 ×8 | 01]   (overflow tag)
                           // .some(.none)  = [00 ×8 | 00]
Int?    // 9 bytes   (Int has 0 XI)
Int??   // 10 bytes  (each layer appends a byte)
Int???  // 11 bytes
```

**Where these numbers live: the value witness table (VWT).** Every type's runtime metadata carries a VWT with four layout fields:

| Field | Meaning |
|---|---|
| `size` | the value's meaningful extent in bytes |
| `stride` | `size` rounded up to alignment — the distance between array elements |
| `flags` | alignment, bitwise-takability, "has enum witnesses", … |
| `extraInhabitantCount` | how many XI patterns the type still offers |

The count an enum consumes is read from the **payload type's** VWT. The enum's own VWT then publishes the *remainder* — which is exactly what the next enum layer wrapping it will read. `ThreeBools` above reads 254 from `Bool`'s VWT, spends 2, and publishes 252 in its own.

#### 2.5.3 Case encoding

The single-payload store/load logic lives in `storeEnumTagSinglePayloadImpl` / `getEnumTagSinglePayloadImpl` ([`stdlib/public/runtime/EnumImpl.h:141-190`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/EnumImpl.h#L141-L190) / [`EnumImpl.h:102-139`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/EnumImpl.h#L102-L139)). Cases are numbered payload = 0, then empty cases 1…N. Three encodings:

**Payload case (`whichCase == 0`):** the payload bytes are the value; any extra tag bytes are zeroed. Selection is by elimination — the bytes match no empty-case pattern.

**Extra-inhabitant case (`1 <= whichCase <= payloadXI`):** the payload area is set to the payload type's XI pattern `#(whichCase − 1)`; extra tag bytes (if any exist because *other* cases overflowed) are zeroed (`EnumImpl.h:156-169`).

**Overflow case:** the extra tag bytes get a non-zero value and the payload area is reused as an index (`EnumImpl.h:172-189`):

```cpp
unsigned caseIndex = (whichCase - 1) - payloadNumExtraInhabitants;
if (payloadSize >= 4) {
  extraTagIndex = 1;                 // one tag value covers everything
  payloadIndex = caseIndex;
} else {
  unsigned payloadBits = payloadSize * 8U;
  extraTagIndex = 1U + (caseIndex >> payloadBits);
  payloadIndex = caseIndex & ((1U << payloadBits) - 1U);
}
```

All three encodings in one pseudocode summary — the XI-first split is what makes a *hybrid* layout when both mechanisms are active:

```
numXICases       = min(numEmptyCases, payloadXI)      // these empty cases become XI patterns
numOverflowCases = numEmptyCases − numXICases         // these need the extra tag bytes
extraTagBytes    = numOverflowCases == 0 ? 0
                 : getEnumTagCounts(payloadSize, numOverflowCases, 1).numTagBytes

// overflow case number overflowIndex (0-based):
if payloadSize >= 4:
    tagValue     = 1
    payloadValue = overflowIndex
else:
    payloadBits  = payloadSize * 8
    tagValue     = 1 + (overflowIndex >> payloadBits)
    payloadValue = overflowIndex & ((1 << payloadBits) − 1)
```

Verified against a small-payload overflow enum:

```swift
enum SP_U8 {
    case p(UInt8)
    case e0
    case e1
    case e2
}
// Trace: payloadXI = 0 → numXICases = 0, numOverflowCases = 3
//        getEnumTagCounts(1, 3, 1): casesPerTag = 2^8 = 256 → numTags = 2 → 1 tag byte
//        size = 1 + 1 = 2:  [payload byte | tag byte]
// .p(0x2A) = [2a | 00]
// .e0      = [00 | 01]     caseIndex 0 → tag 1, payload 0
// .e1      = [01 | 01]     caseIndex 1 → tag 1, payload 1
// .e2      = [02 | 01]     caseIndex 2 → tag 1, payload 2
```

and the nested-`Optional` layering this implies:

```swift
Int??.none         = [00 ×8 | 00 | 01]   // outer tag byte = 1
Int??.some(.none)  = [00 ×8 | 01 | 00]   // inner .none (tag 1), outer "valid payload" (0)
```

### 2.6 Multi-payload spare-bits

Two or more payload cases whose types leave common **spare bits** — bits that are provably zero in every valid value of *every* payload.

#### 2.6.1 Where spare bits come from

The canonical source is pointers. On arm64 Darwin, a Swift heap reference's spare-bit mask is `0xF000_0000_0000_0007` ([`shims/System.h:166`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/SwiftShims/swift/shims/System.h#L166)): the top nibble (no meaningful address space there) plus the low 3 bits (heap objects are at least 8-byte aligned). References that may hold Objective-C objects give up the top bit — the ObjC tagged-pointer bit ([`shims/System.h:170`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/SwiftShims/swift/shims/System.h#L170)) — but references to Swift-native classes keep all 7. Other sources: `Bool` contributes bits 1–7, and a nested enum's unused tag encodings can surface as spare bits too.

#### 2.6.2 Warm-up: the scatter operation

The word "scatter" appears everywhere below. `scatterBits(mask, value)` deposits `value`'s bits into the mask's set positions — the lowest bit of `value` goes into the lowest set bit of the mask, and so on upward:

```
mask = 0b1000_0001            (bit 0 and bit 7 are set)

store value 3 (0b11):  bit 0 of value → bit 0 = 1
                       bit 1 of value → bit 7 = 1
                       result = 0b1000_0001

store value 2 (0b10):  bit 0 of value → bit 0 = 0
                       bit 1 of value → bit 7 = 1
                       result = 0b1000_0000
```

A payload case scatters its tag into the selected spare bits. An empty case additionally scatters its index into the occupied bits, and the two results are ORed together.

#### 2.6.3 The layout algorithm

The memory shape being built:

```
┌────────────────────────────────────────┬─────────────────┐
│  payload area (largest payload)        │ extra tag bytes │
│  [spare bits → tag] [occupied → data]  │ (only if spare  │
│                                        │  bits run out)  │
└────────────────────────────────────────┴─────────────────┘
```

`MultiPayloadEnumImplStrategy::completeFixedLayout` ([`GenEnum.cpp:7152-7304`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/GenEnum.cpp#L7152-L7304)) proceeds:

1. **Intersect.** `CommonSpareBits` = AND of every payload's spare-bit mask, sized to the largest payload (`GenEnum.cpp:7162-7210`). Payloads whose layout the runtime would have to reproduce (generic/resilient) contribute *no* spare bits — see 2.7.

2. **Count tags for the empty cases** (`GenEnum.cpp:7216-7228`). Empty cases are numbered inside the *occupied* bits, `2^occupiedBits` per tag value (one tag covers everything once there are 32 or more occupied bits):

   ```
   occupiedBits = totalPayloadBits − commonSpareBits
   emptyElementsPerTag = occupiedBits >= 32 ? all : 2^occupiedBits
   NumEmptyElementTags = ceil(numEmptyCases / emptyElementsPerTag)
   ```

3. **Size the tag** (`GenEnum.cpp:7230-7233`):

   ```
   numTags    = numPayloadCases + NumEmptyElementTags
   numTagBits = ceil(log2(numTags))
   ```

4. **Place the tag.** If `numTagBits` fit in the common spare bits, select that many spare bits **starting from the most significant** (`GenEnum.cpp:7286-7302`) — these become `PayloadTagBits`. Otherwise use *all* spare bits and append `numTagBits − spareBitCount` extra tag bits, rounded up to whole bytes (the hybrid form, `GenEnum.cpp:7232-7247`):

   ```
   if numTagBits <= commonSpareBitCount:
       PayloadTagBits = keepMostSignificant(CommonSpareBits, numTagBits)
       extraTagBytes  = 0
   else:
       PayloadTagBits = CommonSpareBits              // use every spare bit
       extraTagBytes  = ceil((numTagBits − commonSpareBitCount) / 8)
   ```

5. **Encode.** For a **payload case**, the tag value is *scattered* into the selected tag bits (low tag bit goes to the lowest selected bit); the occupied bits carry the live payload. For an **empty case**, tag and empty-case index are scattered into a **zero** payload — `getEmptyCasePayload` ([`GenEnum.cpp:4063-4073`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/GenEnum.cpp#L4063-L4073)):

   ```cpp
   APInt v = scatterBits(PayloadTagBits.asAPInt(), tag);
   v |= scatterBits(~CommonSpareBits.asAPInt(), tagIndex);
   ```

   Because the base is a zero `APInt`, **every payload bit of an empty case is fixed** — spare bits carry the tag, occupied bits carry the index, and everything else is zero.

   In formula form:

   ```
   payload case:  memory = scatterBits(PayloadTagBits, tag) | live payload bits
                  extra tag bytes (if any) = tag >> numPayloadTagBits
   empty case:    memory = scatterBits(PayloadTagBits, tag) | scatterBits(occupiedBits, index)
                  with   tag   = numPayloadCases + (emptyIndex >> occupiedBitCount)   // one shared tag once occupiedBits ≥ 32
                         index = emptyIndex & ((1 << occupiedBitCount) − 1)
   ```

#### 2.6.4 Worked example: two class payloads

```swift
final class Renderer {
    var identifier = 0
}

final class Compositor {
    var identifier = 0
}

enum Backend {
    case metal(Renderer)
    case software(Compositor)
    case headless
    case disabled
}
```

- CommonSpareBits = `0xF000_0000_0000_0007` (7 bits; Swift-native class references).
- Occupied bits = 57 ≥ 32, so all empty cases share one tag → numTags = 3.
- numTagBits = 2 → selected from the most significant spare bits: **bits 63, 62**.
- The tag fits entirely inside the spare bits — no extra tag bytes, size stays 8.
- Encodings (verified — the byte-7 values below are real):

```
.metal(r)     tag 0 → bits{63,62} = 00 → byte 7 = 0x0? (top bits 00, rest = address bits)
.software(c)  tag 1 → bits{63,62} = 01 → byte 7 = 0x4?           (bit 62 set)
.headless     tag 2, index 0 → [00 00 00 00 00 00 00 80]         (bit 63 set)
.disabled     tag 2, index 1 → [08 00 00 00 00 00 00 80]         (index 1 → lowest occupied bit = bit 3)
```

Note `.disabled`'s index lands on **bit 3** — the lowest *occupied* bit, since bits 0–2 are spare. Scatter operations address positions within their mask, not absolute bit positions.

#### 2.6.5 Worked example: sub-byte spare bits

Spare bits do not require pointers:

```swift
enum BoolPair {
    case a(Bool)
    case b(Bool)
    case e0
}
```

- Each `Bool` occupies bit 0; bits 1–7 are spare → CommonSpareBits = `0b1111_1110`.
- Occupied bits = 1 → 2 empty cases per tag → 1 empty tag; numTags = 3; numTagBits = 2.
- Tag bits: the two most significant spare bits — **bits 7, 6**.
- Verified encodings:

```
.a(false) = [00]   .a(true) = [01]     tag 0; bit 0 is LIVE payload
.b(false) = [40]   .b(true) = [41]     tag 1 (bit 6)
.e0       = [80]                       tag 2 (bit 7), index 0
```

This example is why byte-granular layout descriptions are wrong for spare-bits enums: byte 0 of case `a` is **not** "always `0x00`" — only bits 7–1 are fixed, bit 0 belongs to the payload. Tooling must track per-bit masks ([Part 3.3](#33-bit-level-anatomy-of-the-spare-bits-layout)).

#### 2.6.6 The enum's own extra inhabitants

Unused tag encodings become the enum's XI — `MultiPayloadEnumImplStrategy::getFixedExtraInhabitantCount` ([`GenEnum.cpp:5843-5852`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/GenEnum.cpp#L5843-L5852)):

```
totalTagBits = commonSpareBits + extraTagBits(rounded up to whole bytes)
XI = totalTagBits >= 32 ? MaxNumExtraInhabitants
                        : min(2^totalTagBits − numTags, MaxNumExtraInhabitants)
```

XI values count *down* from all-ones across the tag bits (`GenEnum.cpp:5854-5900`). `BoolPair`: `2⁷ − 3 = 125` XI — and indeed `BoolPair?.none` = `[fe]` (all seven spare bits set, the occupied bit unclaimed). `Backend`: also `2⁷ − 3 = 125`, so `Backend?` is still 8 bytes (verified: `.none` = `[07 00 00 00 00 00 00 f0]` — every spare bit set).

### 2.7 Tagged multi-payload

When payloads share no spare bits — or the layout must be reproducible by the runtime — the tag is appended after the payload area.

#### 2.7.1 Who takes this path

1. **No common spare bits.** Integer payloads use every bit.
2. **Generic enums — always.** The runtime instantiates a generic enum's metadata with `swift_initEnumMetadataMultiPayload` ([`Enum.cpp:384-443`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/Enum.cpp#L384-L443)), which knows nothing about spare bits. IRGen cooperates by clearing `CommonSpareBits` for layout-dependent payloads (`GenEnum.cpp:7189-7199`), so compile-time and runtime agree. Verified cost:

   ```swift
   enum GenericPair<Element> {
       case a(Element)
       case b(Element)
   }
   // GenericPair<Renderer>: size = 9   (8 payload + 1 tag)
   // ...while the non-generic two-class-payload equivalent is 8 (spare bits).
   ```

3. **Resilient payloads** (layout unknown at compile time), same reasoning.

#### 2.7.2 The layout

Memory shape:

```
┌────────────────────────────────────────┬─────────────────┐
│  payload area (P = largest payload)    │  tag (T bytes)  │
│  payload value, or empty-case index    │                 │
└────────────────────────────────────────┴─────────────────┘
size = P + T
```

From `swift_initEnumMetadataMultiPayload`:

```
payloadSize = max over payload types
(numTags, numTagBytes) = getEnumTagCounts(payloadSize, emptyCases, payloadCases)
size = payloadSize + numTagBytes
XI   = numTagBytes == 4 ? INT_MAX
                        : (1 << (numTagBytes * 8)) − numTags     // Enum.cpp:411-415
XI   = min(XI, MaxNumExtraInhabitants)
```

#### 2.7.3 Case encoding

`swift_storeEnumTagMultiPayload` ([`Enum.cpp:677-701`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/Enum.cpp#L677-L701)): a payload case stores its case index in the tag bytes and uses the payload area freely. An empty case stores `numPayloads + (emptyIndex >> payloadBits)` in the tag bytes and **zero-extends the low bits of `emptyIndex` across the whole payload area** — `storeMultiPayloadValue` delegates to `storeEnumElement` ([`EnumImpl.h:27-62`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/EnumImpl.h#L27-L62)), whose `memset(&dst[4], 0, size - 4)` zeroes everything past the stored word. Every payload byte of an empty case is therefore fixed — the read side (`swift_getEnumCaseMultiPayload`, `Enum.cpp:704-725`) loads it back to discriminate.

In formula form:

```
payload case:  tag bytes    = caseIndex
               payload area = the payload value (free-form)
empty case:    if payloadSize >= 4:
                   tag bytes    = numPayloadCases
                   payload area = emptyIndex, zero-extended across all P bytes
               else:
                   tag bytes    = numPayloadCases + (emptyIndex >> payloadBits)
                   payload area = emptyIndex & ((1 << payloadBits) − 1)
```

Verified:

```swift
enum TwoU32 {
    case a(UInt32)
    case b(UInt32)
    case e0
}
// Trace: payloadSize = 4, payloadCases = 2, emptyCases = 1
//        getEnumTagCounts(4, 1, 2): payloadSize ≥ 4 → numTags = 2 + 1 = 3 → 1 tag byte
//        size = 4 + 1 = 5
// .a(1000) = [e8 03 00 00 | 00]
// .b(0)    = [00 00 00 00 | 01]
// .e0      = [00 00 00 00 | 02]      whole payload area zeroed

enum GenericPairWithEmpty<Element> {
    case a(Element)
    case b(Element)
    case e0
}
// GenericPairWithEmpty<Renderer>.e0 = [00 ×8 | 02]         same shape, size 9
```

#### 2.7.4 The enum's own extra inhabitants

The unused tag-byte values, assigned from the **top down**: XI pattern `#i` stores `~i` in the tag bytes (`storeMultiPayloadExtraInhabitantTag`, [`Enum.cpp:649-655`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/Enum.cpp#L649-L655)). Verified: `TwoU32?` is still 5 bytes, and

```
TwoU32?.none = [00 00 00 00 | ff]     ← XI #0 = tag byte 0xFF
```

### 2.8 `indirect` cases and other special forms

**`indirect`** replaces the payload with a `Builtin.NativeObject` heap-box pointer *for layout purposes* (`GenEnum.cpp:6452-6461`). An indirect single-payload enum therefore rides the heap reference's saturated XI supply — it is shaped exactly like `Optional<SomeClass>`:

```swift
indirect enum Tree {
    case node(Tree)
    case leaf
    case sentinel
}
// size = 8
// .leaf     = [00 00 00 00 00 00 00 00]    XI #0 (null)
// .sentinel = [01 00 00 00 00 00 00 00]    XI #1
```

No tag bytes, ever — there are two billion inhabitants to spend. (Getting this wrong — treating an unresolvable indirect payload as "0 XI" and predicting overflow tag bytes — was a real bug this project fixed; see [Part 3.7](#37-the-implementers-pitfall-checklist).)

**Single-case enums** (`SingletonEnumImplStrategy`): layout-identical to the payload (or zero-sized if empty). **Uninhabited enums**: size 0, XI 0.

### 2.9 Byte order

All tag values, empty-case indexes, and multi-byte fixed patterns are stored **little-endian** on Apple platforms (the `storeEnumElement` / `loadEnumElement` helpers handle the general case). A 2-byte tag value `0x0102` appears in memory as `[02 01]`.

### 2.10 The three strategies side by side

| | Multi-payload spare-bits | Tagged multi-payload | Single-payload |
|---|---|---|---|
| Payload cases | ≥ 2, fixed layout, common spare bits exist | ≥ 2 — no common spare bits, or generic/resilient | exactly 1 |
| Tag location | selected spare bits inside the payload area (+ extra tag bytes only if they run out) | extra tag bytes after the payload area | XI patterns inside the payload area; extra tag bytes once XI run out |
| Size overhead | usually 0 | numTagBytes (1/2/4) | 0 while XI last, then numTagBytes |
| Empty-case encoding | tag → spare bits, index → occupied bits, every other bit 0 | tag bytes = tag; payload area = index, zero-extended | the payload's XI pattern #k; or tag bytes + index |
| Enum's own XI | `2^tagBits − numTags`, patterns counting down from all-ones | `2^(8·numTagBytes) − numTags`, tag bytes counting down from `0xFF` | the payload's leftover XI only — appended tag bytes contribute nothing |
| Typical payloads | class references, nested enums with headroom | integers, mixed payloads, any generic enum | anything (this is `Optional`) |
| Source entry point | `GenEnum.cpp` `MultiPayloadEnumImplStrategy` | `Enum.cpp` `swift_initEnumMetadataMultiPayload` | `EnumImpl.h` `storeEnumTagSinglePayloadImpl` |

---

## Part 3 — Mastery: The Machinery in the Source

### 3.1 One ABI, four implementations

The layout rules above are implemented **four times** in the Swift codebase, and knowing which one runs when is the master key to the whole system:

| Implementation | Where | When it runs | Scope |
|---|---|---|---|
| IRGen | [`lib/IRGen/GenEnum.cpp`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/GenEnum.cpp) | compile time | everything, including spare bits |
| Runtime metadata init | [`stdlib/public/runtime/Enum.cpp`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/Enum.cpp) | first metadata access of a generic/resilient enum | **no spare bits** — tagged only |
| Value witnesses | compiler-emitted, or `EnumImpl.h` templates | every runtime store/read of a case | the enum's own contract |
| RemoteInspection | [`stdlib/public/RemoteInspection/TypeLowering.cpp`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/RemoteInspection/TypeLowering.cpp) | offline, from reflection metadata | needs help for spare bits (see 3.5) |

The asymmetries between them *are* the ABI's sharp edges:

- **The runtime cannot do spare bits.** `swift_initEnumMetadataMultiPayload` computes only the tagged layout. IRGen therefore refuses to use spare bits whenever the runtime might have to reproduce the layout — that is precisely the `AllowFixedLayoutOptimizations` guard (`GenEnum.cpp:7189-7199`) and the reason every generic enum is tagged.
- **Single-payload enums never expose appended-tag XI.** After overflow, the extra tag byte has unused values, but IRGen deliberately does not offer them (the `FIXME` at `GenEnum.cpp:3445-3448` and `7075-7078`) — the XI count is *only* the payload's leftovers. Tagged multi-payload enums **do** expose their unused tag values. That is why `Int??` grows a byte per layer while `TwoU32?` stays 5 bytes — an asymmetry no amount of intuition predicts.
- **RemoteInspection mirrors the runtime, not IRGen.** Its `EnumTypeInfoBuilder::build` ([`TypeLowering.cpp:2028-2318`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/RemoteInspection/TypeLowering.cpp#L2028-L2318)) re-derives no-payload / single-payload layouts from first principles (`TypeLowering.cpp:2213-2214` even says "Below logic should match the runtime function swift_initEnumMetadataSinglePayload()"), but for spare-bits enums it must read a compiler-emitted descriptor (3.5) — spare bits cannot be reconstructed from reflection field types alone.

### 3.2 Anatomy of the single-payload witnesses

`getEnumTagSinglePayloadImpl` ([`EnumImpl.h:102-139`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/EnumImpl.h#L102-L139)) reads a case in three steps, and every step teaches something:

```cpp
// 1. If there are extra tag bytes, a nonzero value there decides immediately:
if (emptyCases > payloadNumExtraInhabitants) {
    unsigned extraTagBits = loadEnumElement(extraTagBitAddr, numBytes);
    if (extraTagBits > 0) {
      unsigned caseIndexFromExtraTagBits =
          payloadSize >= 4 ? 0 : (extraTagBits - 1U) << (payloadSize * 8U);
      unsigned caseIndexFromValue = loadEnumElement(valueAddr, payloadSize);
      return (caseIndexFromExtraTagBits | caseIndexFromValue)
             + payloadNumExtraInhabitants + 1;
    }
}
// 2. Otherwise ask the payload whether its bytes are an XI pattern:
if (payloadNumExtraInhabitants > 0)
    return getExtraInhabitantTag(enumAddr, payloadNumExtraInhabitants, payload);
// 3. Otherwise it is a valid payload.
return 0;
```

Observations:

- **The 4-byte window.** `loadEnumElement` truncates the payload area to its first 4 bytes when reading an overflow index — matching the store side's zero-extension. Empty-case indexes are 32-bit quantities everywhere in this ABI.
- **XI dispatch is a function pointer.** Step 2 delegates to the *payload type's* XI implementation (`getExtraInhabitantTag`). The enum layer knows only the count. This indirection is exactly why offline tools hit a wall (3.4) — the callback is code, not data.
- **Tag numbering is layered arithmetic.** Payload = 0, then XI cases in payload-pattern order, then overflow cases. Every implementation (compiler, runtime, reflection, this project) must agree on this exact arithmetic or layouts diverge silently.

### 3.3 Bit-level anatomy of the spare-bits layout

The scatter operation (introduced in 2.6.2) is the heart of this layout. Here it is again on `BoolPair`'s real tag bits:

```
mask  = 0b1100_0000  (BoolPair's two tag bits: 7 and 6)
value = 0b10 (tag 2) → bit 0 of value → bit 6 (lowest set bit of the mask): 0
                       bit 1 of value → bit 7: 1
result = 0b1000_0000 = 0x80          ← BoolPair.e0, verified
```

Three consequences deserve emphasis:

**Payload cases have partially-fixed bytes.** For `BoolPair.a(…)`, byte 0 carries tag bits (7,6 = `00`), the *other* spare bits (5–1) are fixed zero, and bit 0 is live payload. The correct claim about that byte is `byte[0] & 0b1111_1110 == 0b0000_0000` — a bitwise claim, not a byte claim. Any tool that renders whole-byte "fixed bytes" for spare-bits payload cases will assert `a(true) = [00]` while memory reads `[01]`. (This precise bug class existed in this project's renderer and was fixed by introducing per-byte fixed-bit masks; the `swift-section` output in Part 1.5 shows the `byte[0x0] & 0b00000111 = 0b00000000` form that resulted.)

**Empty cases are fully fixed.** `getEmptyCasePayload` starts from a zero `APInt` and ORs two scatters into it (`GenEnum.cpp:4063-4073`) — so *every* bit of the payload area is a fixed part of an empty case's pattern: selected spare bits = tag, occupied bits = index, all remaining bits = 0. A tool that records only the "meaningful" low bits of the index under-describes the pattern.

**Empty cases pack per-tag.** With fewer than 32 occupied bits, each tag value carries `2^occupiedBits` empty cases (`GenEnum.cpp:4289-4310`), indexes resetting per tag. The `numTagBits == spareBitCount` boundary needs care: the "use everything" path (`GenEnum.cpp:7257`, `numTagBits >= commonSpareBitCount`) and the "select most-significant" path meet exactly there, and both produce the same selection — an off-by-one here silently shifts every tag bit.

**XI values count down from all-ones** across the tag bits, rotated so used tag values and inhabitants separate cleanly (`getFixedExtraInhabitantValue`, `GenEnum.cpp:5854-5900`). Hence `BoolPair?.none = [fe]`: all spare bits set, the payload bit unclaimed.

### 3.4 Why XI *patterns* cannot be derived from counts

A recurring trap for offline tooling: the value witness table publishes the XI **count**; the **patterns** are private per-type conventions:

| Type | XI pattern convention |
|---|---|
| Heap references | ascending invalid addresses: `0x0`, `0x1`, `0x2`, … |
| `Bool` | `2`, `3`, `4`, … |
| `String` | reserved `_StringObject` discriminator states — verified: with 2 empty cases, `e0` = all zeros, `e1` = second word `0x1` |
| Tagged multi-payload | tag bytes descending from all-ones: `0xFF`, `0xFE`, … |
| Spare-bits multi-payload | tag-bit patterns descending from all-ones |
| No-payload enums | values ascending from `caseCount` |
| Single-payload enums | the payload's patterns, shifted by the consumed count |
| Structs/tuples | the patterns of *the one field with the most XI* (see `findXIElement`, [`Enum.cpp:199-222`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/Enum.cpp#L199-L222)) |

Patterns compose **recursively**: `Optional<Optional<Bool>>.none` is Bool pattern `#1` (= `3`, verified: `Bool??.none` = `[03]`, `.some(.none)` = `[02]`), because the inner Optional consumed pattern `#0`. A formula over counts alone cannot produce these bytes — you need either the type-specific convention (a hardcoded model) or the live witness code.

This is not a hypothetical: real-world dumps are full of single-payload enums whose empty-case patterns are `String` discriminator states or nested enum encodings. Any tool that *fabricates* patterns from counts will print convincing, wrong bytes. The honest options are the two this project implements (3.6): run the witness (exact), or say "not resolved offline" (honest degradation).

### 3.5 The `__swift5_mpenum` descriptor

Since spare bits exist only in the compiler's head, reflection needs a paper trail. For every fixed-layout multi-payload enum the compiler emits a `MultiPayloadEnumDescriptor` into the binary's `__swift5_mpenum` section ([`include/swift/RemoteInspection/Records.h:381-484`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/RemoteInspection/Records.h#L381-L484)):

```
TypeName            (relative pointer to the mangled name)
SizeFlags           (upper 16: contents size in words; low bit: uses spare bits?)
[ByteOffset|Count]  (where in the payload area the mask bytes sit)
[PayloadSpareBits]  (the common spare-bit mask itself, byte-granular window)
```

`EnumTypeInfoBuilder` consumes it at `TypeLowering.cpp:2242-2317`: with the descriptor (and a builtin type descriptor for the authoritative size/XI), it ANDs in per-case spare-bit masks and builds a `MultiPayloadEnumTypeInfo`; without it — or with any generic payload — it falls back to the tagged formula (`TypeLowering.cpp:2243-2279`). This is the *only* place offline reflection learns about spare bits; strip the section and every spare-bits enum degrades.

### 3.6 How MachOSwiftSection computes enum layouts

This project implements the ABI twice, for two different trust models.

#### The runtime path — exact by construction

Used when the enum's metadata is loaded in-process (`MachOImage`). Pipeline (in `RuntimeFieldLayoutBackend` + `SwiftInspection`):

1. **Formulas first.** `EnumLayoutCalculator` (in `Sources/SwiftInspection/EnumLayoutCalculator.swift`) is a line-audited port of the algorithms in Part 2 — `calculateSinglePayload`, `calculateMultiPayload` (spare bits, from the `__swift5_mpenum` mask), `calculateTaggedMultiPayload`. It produces per-case projections including per-byte **fixed-bit masks** (3.3) and per-strategy XI counts (2.6.6, 2.7.4).
2. **Payload XI from the real VWT.** The payload's XI count is read from its live value witness table. An `indirect` payload is special-cased to the heap-object count `0x7FFF_FFFF` (2.5.2). If the payload type cannot be resolved, the count is *inverted* from the enum's own VWT: for a payload-sized layout, `payloadXI = enumXI + emptyCases` exactly reverses the runtime's subtraction (2.5.1) — and for an overflow layout it is not invertible, so the layout is dropped rather than guessed.
3. **Exact patterns from the witnesses.** `RuntimeEnumCaseProjector` (`Sources/SwiftInspection/RuntimeEnumCaseProjector.swift`) resolves XI patterns (3.4) by *running* the enum's own `destructiveInjectEnumTag` witness twice per case — once into an all-`0x00` buffer, once into all-`0xFF` — and keeping the bytes both runs agree on: those were deterministically written. Empty cases must round-trip through `getEnumTag`, or the projection is rejected. (The dual-baseline trick is valid precisely because single-payload injection *stores* patterns; a spare-bits injection ORs, so that strategy takes its patterns from the mask instead.)
4. **Cross-check against ground truth.** The assembled layout's implied total size must equal the enum VWT's size, or the layout is discarded — derived inputs (payload sizes, spare masks) can be subtly wrong, and a confident wrong answer is worse than none.

#### The static path — offline, honest about limits

Used for `MachOFile` (no process). `EnumLayoutBridge` (`Sources/SwiftLayout/EnumLayoutBridge.swift`) resolves, in order:

1. **The compiler's own answer when available:** the `__swift5_builtin` whole-type descriptor (size/stride/alignment/XI as IRGen computed them) — the same source RemoteInspection trusts.
2. **Structural computation otherwise:** payload types are resolved recursively (through the image's dependency closure), the `__swift5_mpenum` mask feeds `calculateMultiPayload`, and — going one step beyond the official offline implementation — **spare-bits XI counts are derived structurally** (`TypeLowering.cpp` never does this; it falls back to tagged XI without a builtin descriptor).
3. **Generic enums always take the tagged branch** — instantiated or not — mirroring the runtime (2.7.1).
4. **Honest degradation for patterns:** a single-payload empty case whose concrete XI bytes would require witness execution is emitted as "stored as the payload's extra-inhabitant pattern #N" with an explicit *not resolved offline* marker — never fabricated bytes (3.4).

### 3.7 The implementer's pitfall checklist

Distilled from auditing this project's implementation line-by-line against the sources above — each of these was either a real bug found here or a trap the sources themselves warn about:

1. **`indirect` single-payload enums are XI layouts, not overflow layouts.** The payload is a box pointer with `0x7FFF_FFFF` inhabitants. Deriving "0 XI" from an unresolvable payload type produces out-of-bounds tag regions and self-contradictory dumps (2.8).
2. **Empty cases fix the *entire* payload area.** Tagged: zero-extension (`storeEnumElement`'s `memset`); spare-bits: zero-`APInt` scatter. Recording only `ceil(log2(N))` bits invites "the other bytes are arbitrary" misreads (2.6.3, 2.7.3).
3. **Spare-bits payload cases must be described per-bit, not per-byte.** A byte can host tag bits *and* live payload bits simultaneously (`BoolPair`, 3.3).
4. **Saturation applies twice.** Heap-reference XI saturates at `INT_MAX` (`Metadata.h:925`), and every strategy's XI formula caps at `MaxNumExtraInhabitants` (`MetadataValues.h:183`). Approximating either (a hardcoded 4096, an uncapped `1 << bits`) mis-sizes real enums.
5. **The small-payload threshold is 4 bytes, not pointer size** — in `getEnumTagCounts`, in overflow factoring, in the runtime's load window (2.3, 3.2).
6. **Cross-check derived layouts against the VWT.** Payload sizes and spare masks are *derived* inputs; when they are wrong the formulas cheerfully produce a wrong layout. `impliedTotalSize == vwt.size` catches an entire class of silent errors (3.6).
7. **XI consumption is ordered and layered.** Empty cases consume patterns in declaration order; wrappers consume the leftovers starting where the inner enum stopped (`ThreeBools?.none = [04]`, 2.5.2). Off-by-one here shifts every nested pattern.
8. **Case numbering is payload-cases-first** — in field records, in `getEnumTag`, in every formula. Also remember pre-numbering reclassification: zero-sized payloads → empty; unavailable cases → empty (2.1).
9. **Do not expect single-payload tag bytes to yield XI.** The asymmetry in 3.1 (`Int??` grows; `TwoU32?` does not) is deliberate, `FIXME`-documented behavior — model it as-is.

### 3.8 Source map

Everything cited, in one table (tag `swift-6.3.3-RELEASE`):

| File | Role | Key symbols |
|---|---|---|
| [`include/swift/ABI/Enum.h`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/ABI/Enum.h) | the shared tag-count formula | `getEnumTagCounts` (28) |
| [`stdlib/public/runtime/EnumImpl.h`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/EnumImpl.h) | single-payload store/read templates | `storeEnumElement` (27), `getEnumTagSinglePayloadImpl` (102), `storeEnumTagSinglePayloadImpl` (141) |
| [`stdlib/public/runtime/Enum.cpp`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/Enum.cpp) | runtime metadata init + multi-payload witnesses | `swift_initEnumMetadataSinglePayload` (126), `swift_initEnumMetadataMultiPayload` (384), `swift_storeEnumTagMultiPayload` (677) |
| [`lib/IRGen/GenEnum.cpp`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/GenEnum.cpp) | compile-time layout | `EnumImplStrategy::get` (6394), single-payload `completeFixedLayout` (7029), multi-payload `completeFixedLayout` (7152), `getEmptyCasePayload` (4063), XI counts (1228, 3457, 5843) |
| [`lib/IRGen/ExtraInhabitants.cpp`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/ExtraInhabitants.cpp) | pointer XI | `PointerInfo::getExtraInhabitantCount` (50) |
| [`include/swift/Runtime/Metadata.h`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/Runtime/Metadata.h) | heap-object XI count | `swift_getHeapObjectExtraInhabitantCount` (925) |
| [`include/swift/ABI/MetadataValues.h`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/ABI/MetadataValues.h) | the XI cap | `MaxNumExtraInhabitants` (183) |
| [`stdlib/public/SwiftShims/swift/shims/System.h`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/SwiftShims/swift/shims/System.h) | per-platform pointer ABI | `LEAST_VALID_POINTER` (153), arm64 spare-bit masks (166-171) |
| [`stdlib/public/RemoteInspection/TypeLowering.cpp`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/RemoteInspection/TypeLowering.cpp) | the official offline implementation | `EnumTypeInfoBuilder::build` (2028), the `*EnumTypeInfo` classes (613-1150) |
| [`include/swift/RemoteInspection/Records.h`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/RemoteInspection/Records.h) | the spare-bits paper trail | `MultiPayloadEnumDescriptor` (381) |

In this repository:

| File | Role |
|---|---|
| `Sources/SwiftInspection/EnumLayoutCalculator.swift` | the formula port (all three strategies, per-case projections, fixed-bit masks) |
| `Sources/SwiftInspection/RuntimeEnumCaseProjector.swift` | witness-driven exact pattern projection |
| `Sources/SwiftDeclarationRendering/RuntimeFieldLayoutBackend.swift` | runtime-path assembly: VWT reads, XI inversion, size cross-check |
| `Sources/SwiftLayout/EnumLayoutBridge.swift` | static-path assembly: builtin descriptors, `__swift5_mpenum`, structural fallback |
| `Tests/SwiftInspectionTests/EnumLayoutVerificationTests.swift` | every formula in this document, verified against live memory |

---

## Appendix: Comment rendering — templates and presets

The comments `swift-section dump --emit-enum-layout` (and the library renderers) emit are driven by a token template, `Transformer.SwiftEnumLayout` (in the `SemanticTransformer` module). Three template levels mirror the comment structure — the type-level strategy line, the per-case block, and the per-fixed-byte line — with `${token}` placeholders (the same names RuntimeViewerCore's transformer UI uses). Five presets ship built in, selectable on the CLI via `--enum-layout-style`:

| Preset | Per-byte lines | Style |
|---|---|---|
| `detailed` (default) | yes | The full built-in rendering; partially-fixed bytes use binary masks (`fixed bits 0b11110000 = 0b01000000`) |
| `explained` | yes | Same information, but partially-fixed bytes are narrated as bit ranges: `bits 7-4 are always 0100; the other bits (3-0) hold payload data` |
| `standard` | no | Case header + encoding sentence + one-line fixed-byte summary |
| `inline` | no | One line per case with the byte summary inline: `` Case 1 `implicit` (empty case #0): bytes[0x8..<0x10] = 0x1 `` |
| `compact` | no | One line per case, no byte information: `` [0x01] `caseName` — payload case, tag 1 `` |

Library users call `applyTransformers(_:)` on `DeclarationRenderConfiguration` or `SwiftDeclarationPrintConfiguration` with a `Transformer.SwiftConfiguration` whose `swiftEnumLayout` is a preset (`Transformer.SwiftEnumLayout.Preset`) or a custom module; the same mechanism covers the field-offset / type-layout / member-address / vtable-offset comment templates. The `detailed` preset is guaranteed identical to the built-in default rendering by unit test, so the default output never drifts.
