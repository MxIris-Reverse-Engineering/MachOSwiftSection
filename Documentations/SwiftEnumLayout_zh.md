# Swift Enum 内存布局 —— 从入门到精通

Swift 的枚举以紧凑著称：`Optional<SomeClass>` 只占 8 字节，包着两个类引用的枚举也还是 8 字节，给包着 `Bool` 的枚举再加 empty case 更是一点空间都不多花。支撑这一切的机制是 Swift ABI 中最精巧的部分之一，分散在编译器 IR 生成、运行时与反射库三处。

本文**从零开始**讲清这套机制：

- **[第一部分 —— 实用指南](#第一部分--实用指南)** 面向只想*预测大小、看懂布局输出*、不打算研究 ABI 的读者。如果这就是你的全部需求，读完第一部分就可以停下。
- **[第二部分 —— 三大策略](#第二部分--三大策略)** 推导真正的布局算法——公式、case 编码、精确到字节的模式——并配有完整的工作示例。
- **[第三部分 —— 精通](#第三部分--精通源码中的机器)** 解剖 Swift 源码树中的具体实现：谁在什么时候算什么、spare-bits 布局的位级解剖、离线工具为什么从原理上就无法恢复某些信息，以及本项目（MachOSwiftSection）如何同时实现了运行时精确引擎与静态（离线）布局引擎。

**全文约定：**

- 所有 Swift 源码引用固定在 [`swift-6.3.3-RELEASE`](https://github.com/swiftlang/swift/tree/swift-6.3.3-RELEASE) 标签，以 `path/to/File.ext:line` 形式给出。例如 [`include/swift/ABI/Enum.h:29`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/ABI/Enum.h#L29) 就是该标签下该文件的第 29 行。
- 平台为 **64 位小端序 Apple 平台**（arm64 / x86_64 的 macOS、iOS……）。字节转储从偏移 0 起、从左到右打印，所以多字节整数的*最低*有效字节先出现。
- **本文的每一段字节转储都是真实输出**，由探针程序（`MemoryLayout` + `withUnsafeBytes`）在 arm64 macOS 上用 Swift 6.3.3 工具链编译运行得到——与所引源码同一版本。

---

## 第一部分 —— 实用指南

### 1.1 三个问题决定一切

要预测一个枚举的布局，只需要回答三个问题：

1. **有几个 case 带 payload？** 零个 payload：枚举就是一个小整数 tag。一个 payload：走 single-payload 策略。两个及以上：走两种 multi-payload 策略之一。
2. **最大的 payload 有多大？** 枚举总会预留一块和最大 payload 一样大的 **payload area**。剩下的问题全都归结为：判别用的 **tag** 放在哪里。
3. **payload 类型有没有用不到的位模式？** 类引用、`Bool`、`String` 这类类型用不满自己存储的所有位模式。Swift 会激进地回收这些“不可能出现的模式”，把 tag *藏进 payload area 内部*——零开销。而 `Int`、`UInt8`、`Double` 这类每一位都用满的类型，tag 只能放进 payload 之后追加的额外字节里。

“用不到的模式”有两种形态，后文会反复出现：

- **Extra inhabitants（XI）**——payload 类型永远不会取到的完整*值*（比如类引用永远不会是 `0x0`、`0x1` 这样的小整数）。single-payload enum 用它。
- **Spare bits**——在*每个* payload 的每个合法值里都是 0 的那些*位*（比如 64 位指针的高位）。multi-payload enum 用它。

### 1.2 五个枚举速览

下面这组转储就是全文内容的微缩版。

**no-payload enum 就是一个字节大小的 tag**（按声明顺序取 0、1、2……）：

```swift
enum Direction {
    case north
    case south
    case east
    case west
}
// size=1  .north=[00]  .west=[03]
```

**payload 类型没有可用模式时，single-payload enum 追加一个 tag byte**——并把 payload area 复用来存 empty case 的编号：

```swift
enum Fetched {
    case payload(UInt32)
    case missing
    case failed
}
// size=5（4 payload + 1 tag）
// .payload(1000) = [e8 03 00 00 | 00]   tag 0 = “合法 payload”
// .missing       = [00 00 00 00 | 01]   tag 1，payload area 存编号 0
// .failed        = [01 00 00 00 | 01]   tag 1，payload area 存编号 1
```

**payload 类型*有*可用模式时，single-payload enum 零开销**：

```swift
final class Renderer {
    var identifier = 0
}
// Optional<Renderer>: size=8 —— 和裸引用一样大！
// .none = [00 00 00 00 00 00 00 00]    （“空指针”这个 extra inhabitant）

enum ThreeBools {
    case value(Bool)
    case unset
    case invalid
}
// size=1 —— Bool 只用 0 和 1，2..255 全是免费的 tag：
// .value(false)=[00]  .value(true)=[01]  .unset=[02]  .invalid=[03]
```

**类引用的 multi-payload enum 把 tag 藏进指针位里**：

```swift
final class Compositor {
    var identifier = 0
}

enum Backend {
    case metal(Renderer)      // byte 7 高位 = 00
    case software(Compositor) // byte 7 高位 = 01（bit 62 置位）
    case headless             // [00 00 00 00 00 00 00 80]（bit 63 置位）
    case disabled             // [08 00 00 00 00 00 00 80]
}
// size=8 —— 仍然只有一个指针宽。
```

**整数的 multi-payload enum 追加一个 tag byte**：

```swift
enum TwoU32 {
    case a(UInt32)
    case b(UInt32)
    case e0
}
// size=5
// .a(1000) = [e8 03 00 00 | 00]   tag 0
// .b(0)    = [00 00 00 00 | 01]   tag 1
// .e0      = [00 00 00 00 | 02]   tag 2，payload area 清零
```

### 1.3 大小速查表

所有数值都在 arm64 macOS、Swift 6.3.3 上验证过。

| 枚举形态 | 大小 | 原因 |
|---|---|---|
| `enum { case a, b, c }`（不超过 256 个 case） | 1 | 一个 tag byte；到 65536 个 case 用 2 字节，再多用 4 字节 |
| `Optional<AnyObject>` / 任意类引用 | 8 | 空指针 + 低位无效地址都是 extra inhabitants |
| `Optional<UnsafeRawPointer>` | 8 | 空指针是*唯一*的 extra inhabitant |
| `Optional<UnsafeRawPointer?>` | 9 | ……所以第二层 `Optional` 只能追加 tag byte |
| `Optional<Bool>` | 1 | `Bool` 有 254 个 extra inhabitants（2…255） |
| `Optional<String>` | 16 | `String` 预留了巨大的 extra-inhabitant 空间 |
| `Optional<Int>` | 9 | `Int` 用满全部 2⁶⁴ 个模式 → 追加 tag byte |
| `Optional<Int?>` | 10 | 每包一层没有 XI 的 `Optional` 就多一个字节 |
| `Optional<(() -> Void)>` | 16 | 函数 =（代码指针，上下文）；代码指针那个字携带 XI |
| 2+ 个类引用 payload（上文 `Backend`） | 8 | tag 藏在指针的 spare bits 里 |
| 2+ 个整数 payload（上文 `TwoU32`） | payload + 1 | 没有 spare bits → 追加 tag byte |
| 任何 2+ payload 的*泛型*枚举，如 `enum G<T> { case a(T); case b(T) }` 的 `G<Renderer>` | 9 | 泛型布局从不使用 spare bits——见 [2.7](#27-tagged-multi-payload) |
| `indirect` case | 每个 8 | indirect payload 是指向堆上 box 的指针 |
| `enum { case v(Void); case e }` | 1 | 零大小的 payload 按 empty case 布局 |
| `Never`（uninhabited enum） | 0 | 没有值就不需要存储（stride 仍是 1） |

> **`size` 和 `stride` 的区别：**`size` 是值真正占用的范围（本文讨论的对象）；`stride` 是把 size 向对齐取整后的结果，用作数组里元素之间的间距。`TwoU32` 的 size 是 5 而 stride 是 8；`Int?` 的 size 是 9 而 stride 是 16。

### 1.4 经验法则

- **在 payload 的 extra inhabitants 用完之前，empty case 都是免费的。** 给 `Optional<SomeClass>` 再加一百个 empty case 也还是 8 字节。
- **指针是 XI 富矿，整数是 XI 荒漠。** 类引用有大约 2³¹ 个 extra inhabitants；`Int`、`UInt8`、`Double` 一个也没有；`Bool` 有 254 个；`UnsafeRawPointer` 恰好有 1 个（空指针）。
- **每层 `Optional` 恰好消耗一个 extra inhabitant。** 库存够用时层层免费（`Bool??` 还是 1 字节），库存耗尽后每层多一个字节（`Int??` 是 10 字节、`Int???` 是 11 字节）。
- **类引用的 multi-payload enum 保持指针大小**；混进一个没有 spare bits 的 payload（比如 `Int`）就会强制追加 tag byte。
- **泛型枚举必须付 tagged 布局的代价**，就算实参是指针类型也一样：上文的 `G<Renderer>` 是 9 字节，而等价的非泛型枚举是 8 字节。
- **`indirect` 把 payload 变成指针**——indirect 的 single-payload enum 和 `Optional<某个类>` 形态完全一致：8 字节，empty case 取 `0x0`、`0x1`……

### 1.5 用 `swift-section` 直接查看布局

本项目可以直接从二进制渲染上面这一切——不需要加载进程：

```bash
swift-section dump --emit-enum-layout /path/to/binary
# 注释风格由详到简：
swift-section dump --emit-enum-layout --enum-layout-style explained ...
swift-section dump --emit-enum-layout --enum-layout-style standard ...
swift-section dump --emit-enum-layout --enum-layout-style inline ...
swift-section dump --emit-enum-layout --enum-layout-style compact ...
```

上文 `Backend` 枚举的真实输出（`detailed` 风格，节选）：

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

读法：

- **策略行**给出布局策略和它的参数。
- 每个 **case 块**给出这个 case 的 tag value，以及哪些字节是固定（确定性）的。
- `byte[0x7] & 0b11110000 = 0b01000000` 是**部分固定的字节**：只有掩码内的位有断言。这个字节的其余位放的是活的 payload 数据（这里是指针位）——这是一个关键的诚实性细节，详见[第三部分 3.3](#33-spare-bits-布局的位级解剖)。
- `leftover extra inhabitants` 是*外层*枚举再包一层时还能免费使用的量。

大多数用户到这里已经够用。本文其余部分解释这些答案*为什么*成立。

---

## 第二部分 —— 三大策略

### 2.1 编译器怎么选策略

策略选择发生在 `EnumImplStrategy::get`（[`lib/IRGen/GenEnum.cpp:6394`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/GenEnum.cpp#L6394)）。给每个 case 分类之后，决策树是：

```
resilient 枚举（编译期不知道布局）      → ResilientEnumImplStrategy   (GenEnum.cpp:6523)
C 导入 / @objc / C 兼容                → CCompatibleEnumImplStrategy (GenEnum.cpp:6541)
总 case 数 0 或 1                      → SingletonEnumImplStrategy   (GenEnum.cpp:6552)
≥ 2 个 payload case                    → MultiPayloadEnumImplStrategy(GenEnum.cpp:6559)
恰好 1 个 payload case                 → SinglePayloadEnumImplStrategy (GenEnum.cpp:6567)
其余（全是 empty case）                → NoPayloadEnumImplStrategy   (GenEnum.cpp:6575)
```

计数*之前*有三个分类细节：

- **`indirect` case 按“payload 类型是 `Builtin.NativeObject`（堆 box 指针）的 payload case”来算**——`GenEnum.cpp:6452-6461`。payload 的真实类型不影响布局。
- **零大小的 payload（比如 `Void`、`Never`）按 empty case 算**——`GenEnum.cpp:6483-6489`。这就是为什么 `enum { case v(Void); case e }` 是 1 字节的 no-payload enum（实测：`.v(())` = `[00]`，`.e` = `[01]`）。
- **lowering 期间不可用（unavailable）的 case 按没有 payload 处理**——`GenEnum.cpp:6445-6450`。

multi-payload 策略内部再分两支：如果各 payload 有公共的 **spare bits**，tag 就藏进去（[2.6](#26-multi-payload-spare-bits)）；如果没有——或者枚举布局是泛型/动态的——就追加 tag byte（[2.7](#27-tagged-multi-payload)）。

### 2.2 术语表

| 术语 | 含义 |
|---|---|
| **Payload case** | 带关联值的 case |
| **Empty case** | 不带关联值的 case（经过上面的重分类之后） |
| **Payload area** | 枚举值开头的 `max(各 payload 大小)` 个字节 |
| **Tag** | 区分 case 的判别值 |
| **Extra inhabitants（XI）** | 类型的值永远不会用到的完整位*模式*，可以被外层枚举复用 |
| **Spare bits** | 在类型的每个合法值里都是 0 的那些*位* |
| **Occupied bits** | spare bits 的补集——承载真实 payload 数据的位 |
| **Extra tag bytes** | 追加在 payload area 之后的判别字节 |
| **Case index** | 先 payload case（按声明顺序），后 empty case（按声明顺序）。`getEnumTag`、反射 field records 和所有公式都用这套编号。 |

### 2.3 公共底层函数：`getEnumTagCounts`

ABI 里所有“需要几个 tag byte？”的答案都出自同一个小函数，短到可以全文引用（[`include/swift/ABI/Enum.h:28-49`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/ABI/Enum.h#L28-L49)）：

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

它的道理是：当某个 tag value表示“这是 empty case”时，payload area 就成了闲置存储——于是*复用*它来存 empty case 的编号。`size` 字节的 payload area，每个 tag value可以编号 `2^(size*8)` 个 empty case：

- **`size >= 4`**：payload area 能编号 2³² 个 empty case——比任何真实枚举都多——所以*一个*额外的 tag value就能覆盖全部 empty case。
- **`size < 4`**：小 payload area 每个 tag value只能编号 `2^(size*8)` 个，empty case 要摊到 `ceil(emptyCases / 2^(size*8))` 个 tag value上。

工作示例：

```
getEnumTagCounts(size: 4, emptyCases: 2, payloadCases: 1)
  → numTags = 1 + 1 = 2       → 1 个 tag byte     （`Fetched`：4+1 = 5 字节）

getEnumTagCounts(size: 1, emptyCases: 300, payloadCases: 1)
  → 300 个 empty case / 每个 tag value 256 个 = 2 个 tag value → numTags = 3 → 1 个 tag byte

getEnumTagCounts(size: 0, emptyCases: 300, payloadCases: 1)
  → 2^0 = 每个 tag value 1 个 → numTags = 1 + 300 = 301 → 2 个 tag byte
```

注意阈值是 **4 字节**，不是指针宽度——这是很常见的记忆偏差。

### 2.4 No-payload enum

所有 case 都不带 payload。值本身*就是* tag：第 `i` 个 case（声明顺序）用最小够用宽度的小端整数存 `i`：

| Case 数 | 大小 |
|---|---|
| 0 或 1 | 0 字节 |
| 2 … 256 | 1 字节 |
| 257 … 65536 | 2 字节 |
| 更多 | 4 字节 |

实测：`Direction.north` = `[00]`，`.west` = `[03]`。

最后一个 case *之上*的那些值，就是这个枚举自己的 extra inhabitants——`NoPayloadEnumImplStrategy::getFixedExtraInhabitantCount`（[`GenEnum.cpp:1228-1236`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/GenEnum.cpp#L1228-L1236)）：

```
XI = min(2^(size*8) − caseCount, MaxNumExtraInhabitants)
```

`Direction` 有 `256 − 4 = 252` 个 extra inhabitants，所以 `Direction?` 还是 1 字节（实测：`.none` = `[04]`）。上限 `MaxNumExtraInhabitants = 0x7FFFFFFF`（[`include/swift/ABI/MetadataValues.h:183`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/ABI/MetadataValues.h#L183)）只在 4 字节 tag 时才会碰到。

两个特殊亲戚：

- **Uninhabited enum**（`Never`、`enum Empty {}`）：由 `SingletonEnumImplStrategy` 处理——size 0、stride 1、**0 个 extra inhabitants**（根本没有可以复用的 tag 存储）。
- **`@objc` / C 导入的枚举**：C 兼容布局——大小就是原始类型的大小，任何位模式都是合法值，没有 extra inhabitants，也没有任何打包技巧。

### 2.5 Single-payload enum

恰好一个 payload case，加 `N` 个 empty case。这是 `Optional` 的策略，也是真实二进制里最常见的形态。

编码有严格的两级优先顺序：

```
1. Extra inhabitants (XI)  — payload 的无效位模式，就在 payload area 里，零开销
2. Overflow                — 追加在 payload area 之后的 extra tag bytes
```

内存形状：

```
XI 形态（inhabitants 够用）：           Overflow 形态（inhabitants 用完了）：
┌───────────────────────────┐          ┌───────────────────────────┬─────────────────┐
│   payload area (P bytes)  │          │   payload area (P bytes)  │ extra tag bytes │
│   payload 值或 XI 模式    │          │   payload 值或溢出编号    │ (0 = 合法      │
│                           │          │                           │  payload / XI)  │
└───────────────────────────┘          └───────────────────────────┴─────────────────┘
size = P                               size = P + numTagBytes
```

#### 2.5.1 大小怎么定

运行时的 metadata 实例化代码写得明明白白（[`stdlib/public/runtime/Enum.cpp:138-146`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/Enum.cpp#L138-L146)）：

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

一句话：empty case 按声明顺序先消耗 payload 的 extra inhabitants；只有*溢出*的部分——超出 XI 库存的 empty case——才会迫使追加 extra tag bytes。

#### 2.5.2 Extra inhabitants：这套机制的通货

Extra inhabitant 是 payload 类型永远不会产生的全宽位模式。**数量**来自 payload 的 value witness table；**模式本身**是 payload 类型的私有约定。64 位 Darwin 上的实测数量：

| Payload 类型 | XI 数量 | 模式 |
|---|---|---|
| `Bool` | 254 | 值 `2 … 255` |
| 类 / `AnyObject` / 堆引用 | `0x7FFF_FFFF`（饱和） | 小的无效地址 `0x0, 0x1, 0x2, …` |
| `UnsafeRawPointer` 家族 | 1 | 只有空指针 |
| `String` | `0x7FFF_FFFF`（饱和） | 预留的 `_StringObject` 判别模式 |
| Thick 函数（`() -> Void`） | 代码指针那个字上 `0x7FFF_FFFF` | 无效的函数地址 |
| `Int`、`UInt8`、`Double`…… | 0 | — |
| `weak` 引用 | 0 | — |
| `Optional<UInt8>` | 0 —— **不是 254！** | 溢出后的 single-payload enum 只保留 payload 剩下的 XI（`UInt8` 一个都没有）；它 tag byte 里没用到的值被刻意不提供（见 3.1） |
| 另一个枚举 | 它剩下的 XI | 那个枚举没用完的 tag 编码 |

堆引用的数量值得推导一次，因为它到处出现。[`include/swift/Runtime/Metadata.h:925-939`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/Runtime/Metadata.h#L925-L939)：

```cpp
inline constexpr unsigned swift_getHeapObjectExtraInhabitantCount() {
  // The runtime needs no more than INT_MAX inhabitants.
  return (LeastValidPointerValue >> ObjCReservedLowBits) > INT_MAX
    ? (unsigned)INT_MAX
    : (unsigned)(LeastValidPointerValue >> ObjCReservedLowBits);
}
```

Darwin 64 位上 `LeastValidPointerValue` 是 `0x1_0000_0000`——地址空间的前 4 GiB 永远不会放 Swift 堆对象（[`stdlib/public/SwiftShims/swift/shims/System.h:153`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/SwiftShims/swift/shims/System.h#L153)）。这个数超过了 `INT_MAX`，于是数量饱和成 `0x7FFF_FFFF`。IRGen 那边的镜像实现是 `PointerInfo::getExtraInhabitantCount`（[`lib/IRGen/ExtraInhabitants.cpp:50-61`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/ExtraInhabitants.cpp#L50-L61)）。

**消耗账本。** 枚举花掉 payload 的 `k` 个 inhabitants 之后，枚举自己的 XI 数量就是余额——`SinglePayloadEnumImplStrategy::getFixedExtraInhabitantCount`（[`GenEnum.cpp:3457-3460`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/GenEnum.cpp#L3457-L3460)）：

```cpp
return getFixedPayloadTypeInfo().getFixedExtraInhabitantCount(IGM)
         - getNumExtraInhabitantTagValues();
```

而且它的 XI *取值*就是 payload 的模式序列跳过已消耗的部分。看账本在真实链条上运转（每段转储都实测过）：

```swift
enum ThreeBools {
    case value(Bool)
    case unset
    case invalid
}
// Bool 的 XI 模式：2, 3, 4, 5, ...
// .unset   = [02]    ← 消耗了 XI #0
// .invalid = [03]    ← 消耗了 XI #1
// ThreeBools 自己的 XI：还剩 252 个，模式从 4 开始。

ThreeBools?.none          // = [04]  ← Optional 消耗了 ThreeBools 的 XI #0
```

以及库存耗尽的情形：

```swift
UnsafeRawPointer?          // 8 字节；.none = [00 00 00 00 00 00 00 00]（空指针这个 XI）
UnsafeRawPointer??         // 9 字节！内层 Optional 花掉了唯一的 XI；
                           // .none         = [00 ×8 | 01]  （溢出 tag）
                           // .some(.none)  = [00 ×8 | 00]
Int?    // 9 字节  （Int 没有 XI）
Int??   // 10 字节 （每层多一个字节）
Int???  // 11 字节
```

**这些数字住在哪里：value witness table（VWT）。** 每个类型的运行时元数据都带一张 VWT，其中有四个布局字段：

| 字段 | 含义 |
|---|---|
| `size` | 值真正占用的字节数 |
| `stride` | `size` 向对齐取整后的结果——数组里元素之间的间距 |
| `flags` | 对齐、bitwise-takability、"has enum witnesses" 等标志 |
| `extraInhabitantCount` | 这个类型还能提供多少个 XI 模式 |

枚举消耗的数量是从 **payload 类型的** VWT 里读的。枚举自己的 VWT 里发布的则是*余额*——外面再包一层枚举时，读到的正是这个余额。上文的 `ThreeBools` 从 `Bool` 的 VWT 读到 254，花掉 2 个，在自己的 VWT 里发布 252。

#### 2.5.3 Case 编码

single-payload 的存取逻辑在 `storeEnumTagSinglePayloadImpl` / `getEnumTagSinglePayloadImpl`（[`stdlib/public/runtime/EnumImpl.h:141-190`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/EnumImpl.h#L141-L190) / [`EnumImpl.h:102-139`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/EnumImpl.h#L102-L139)）。case index：payload case = 0，empty case 是 1…N。三种编码：

**Payload case（`whichCase == 0`）：** payload bytes 就是值本身；如果有 extra tag bytes，全部清零。它的“选中”方式是排除法——字节不匹配任何 empty case 的模式。

**Extra-inhabitant case（`1 <= whichCase <= payloadXI`）：** payload area 写成 payload 类型的第 `whichCase − 1` 号 XI 模式；如果（因为*别的* case 溢出）存在 extra tag bytes，就清零（`EnumImpl.h:156-169`）。

**溢出 case：** extra tag bytes 写进一个非零值，payload area 复用来存编号（`EnumImpl.h:172-189`）：

```cpp
unsigned caseIndex = (whichCase - 1) - payloadNumExtraInhabitants;
if (payloadSize >= 4) {
  extraTagIndex = 1;                 // 一个 tag value就够覆盖全部
  payloadIndex = caseIndex;
} else {
  unsigned payloadBits = payloadSize * 8U;
  extraTagIndex = 1U + (caseIndex >> payloadBits);
  payloadIndex = caseIndex & ((1U << payloadBits) - 1U);
}
```

三种编码合成一段伪代码总结——XI 优先的这次拆分，在两种机制同时生效时就是所谓的 *hybrid* 形态：

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

用小 payload 的溢出枚举实测验证：

```swift
enum SP_U8 {
    case p(UInt8)
    case e0
    case e1
    case e2
}
// 推导：payloadXI = 0 → numXICases = 0，numOverflowCases = 3
//       getEnumTagCounts(1, 3, 1)：casesPerTag = 2^8 = 256 → numTags = 2 → 1 个 tag byte
//       size = 1 + 1 = 2:  [payload byte | tag byte]
// .p(0x2A) = [2a | 00]
// .e0      = [00 | 01]     caseIndex 0 → tag 1，payload 0
// .e1      = [01 | 01]     caseIndex 1 → tag 1，payload 1
// .e2      = [02 | 01]     caseIndex 2 → tag 1，payload 2
```

以及由此推出的 `Optional` 嵌套分层：

```swift
Int??.none         = [00 ×8 | 00 | 01]   // 外层 tag byte = 1
Int??.some(.none)  = [00 ×8 | 01 | 00]   // 内层 .none（tag 1），外层是“合法 payload”（0）
```

### 2.6 Multi-payload spare-bits

两个及以上的 payload case，且各 payload 类型留有公共的 **spare bits**——能证明在*每个* payload 的每个合法值里都是 0 的那些位。

#### 2.6.1 Spare bits 从哪来

典型来源是指针。arm64 Darwin 上，Swift 堆引用的 spare-bit mask 是 `0xF000_0000_0000_0007`（[`shims/System.h:166`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/SwiftShims/swift/shims/System.h#L166)）：最高的半字节（那里没有有意义的地址空间）加最低 3 位（堆对象至少 8 字节对齐）。可能持有 Objective-C 对象的引用要让出最高位——那是 ObjC tagged-pointer 位（[`shims/System.h:170`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/SwiftShims/swift/shims/System.h#L170)）——而指向 Swift 原生类的引用保有全部 7 位。其他来源：`Bool` 贡献第 1–7 位；嵌套枚举没用完的 tag 编码也可以变成 spare bits。

#### 2.6.2 热身：scatter 操作

下文到处会出现 "scatter" 这个词。`scatterBits(mask, value)` 把 `value` 的各个位填进掩码中被置位的位置——`value` 的最低位填进掩码里最低的置位位，依次往上：

```
mask = 0b1000_0001            (bit 0 和 bit 7 被置位)

存入 value 3 (0b11):  value 的 bit 0 → bit 0 = 1
                      value 的 bit 1 → bit 7 = 1
                      结果 = 0b1000_0001

存入 value 2 (0b10):  value 的 bit 0 → bit 0 = 0
                      value 的 bit 1 → bit 7 = 1
                      结果 = 0b1000_0000
```

payload case 把 tag scatter 进选中的 spare bits；empty case 还要把自己的编号 scatter 进 occupied bits，两个结果按位 OR 到一起。

#### 2.6.3 布局算法

要构建的内存形状：

```
┌────────────────────────────────────────┬─────────────────┐
│  payload area（最大的 payload）        │ extra tag bytes │
│  [spare bits → tag] [occupied → 数据]  │（spare bits 不  │
│                                        │  够用时才有）   │
└────────────────────────────────────────┴─────────────────┘
```

`MultiPayloadEnumImplStrategy::completeFixedLayout`（[`GenEnum.cpp:7152-7304`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/GenEnum.cpp#L7152-L7304)）依次做这几步：

1. **求交集。** `CommonSpareBits` = 所有 payload 的 spare-bit mask 按位与，宽度取最大的 payload（`GenEnum.cpp:7162-7210`）。凡是运行时可能需要重现布局的 payload（泛型/resilient）*不*贡献任何 spare bits——见 2.7。

2. **为 empty case 数 tag**（`GenEnum.cpp:7216-7228`）。empty case 的编号写在 *occupied bits* 里，每个 tag value容纳 `2^occupiedBits` 个（occupied bits 达到 32 之后一个 tag value就全装得下）：

   ```
   occupiedBits = payload 总位数 − commonSpareBits
   emptyElementsPerTag = occupiedBits >= 32 ? 全部 : 2^occupiedBits
   NumEmptyElementTags = ceil(numEmptyCases / emptyElementsPerTag)
   ```

3. **定 tag 宽度**（`GenEnum.cpp:7230-7233`）：

   ```
   numTags    = numPayloadCases + NumEmptyElementTags
   numTagBits = ceil(log2(numTags))
   ```

4. **放置 tag。** 如果 `numTagBits` 塞得进公共 spare bits，就**从最高位开始**选出那么多位（`GenEnum.cpp:7286-7302`）——它们成为 `PayloadTagBits`。不够的话就用上*全部* spare bits，再追加 `numTagBits − spareBitCount` 个 extra tag bit、向上取整到整字节（混合形态，`GenEnum.cpp:7232-7247`）：

   ```
   if numTagBits <= commonSpareBitCount:
       PayloadTagBits = keepMostSignificant(CommonSpareBits, numTagBits)
       extraTagBytes  = 0
   else:
       PayloadTagBits = CommonSpareBits              // use every spare bit
       extraTagBytes  = ceil((numTagBits − commonSpareBitCount) / 8)
   ```

5. **编码。** **payload case**：tag value*散布*（scatter）进选中的 tag bits（tag 的低位对应掩码里最低的选中位）；occupied bits 承载活的 payload。**empty case**：tag 和 empty case 编号散布进一个**全零**的 payload——`getEmptyCasePayload`（[`GenEnum.cpp:4063-4073`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/GenEnum.cpp#L4063-L4073)）：

   ```cpp
   APInt v = scatterBits(PayloadTagBits.asAPInt(), tag);
   v |= scatterBits(~CommonSpareBits.asAPInt(), tagIndex);
   ```

   因为起点是一个全零的 `APInt`，**empty case 的每一个 payload bit 都是固定的**——选中的 spare bits 携带 tag，occupied bits 携带编号，其余的位全是 0。

   写成公式：

   ```
   payload case:  memory = scatterBits(PayloadTagBits, tag) | live payload bits
                  extra tag bytes (if any) = tag >> numPayloadTagBits
   empty case:    memory = scatterBits(PayloadTagBits, tag) | scatterBits(occupiedBits, index)
                  with   tag   = numPayloadCases + (emptyIndex >> occupiedBitCount)   // one shared tag once occupiedBits ≥ 32
                         index = emptyIndex & ((1 << occupiedBitCount) − 1)
   ```

#### 2.6.4 工作示例：两个类引用 payload

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

- CommonSpareBits = `0xF000_0000_0000_0007`（7 位；Swift 原生类引用）。
- Occupied bits = 57，达到 32，所以所有 empty case 共享一个 tag → numTags = 3。
- numTagBits = 2 → 从最高的 spare bits 里选：**bit 63 和 bit 62**。
- tag 完全装进了 spare bits——没有 extra tag bytes，size 保持 8。
- 编码（实测过——下面 byte 7 的值都是真实的）：

```
.metal(r)     tag 0 → bits{63,62} = 00 → byte 7 = 0x0?（高两位 00，其余是地址位）
.software(c)  tag 1 → bits{63,62} = 01 → byte 7 = 0x4?          （bit 62 置位）
.headless     tag 2，编号 0 → [00 00 00 00 00 00 00 80]         （bit 63 置位）
.disabled     tag 2，编号 1 → [08 00 00 00 00 00 00 80]         （编号 1 → 最低的 occupied bit = bit 3）
```

注意 `.disabled` 的编号落在 **bit 3**——最低的 *occupied* bit，因为 bit 0–2 是 spare。scatter 操作寻址的是掩码内部的位置，不是绝对位号。

#### 2.6.5 工作示例：不满一个字节的 spare bits

Spare bits 并不是非要指针不可：

```swift
enum BoolPair {
    case a(Bool)
    case b(Bool)
    case e0
}
```

- 每个 `Bool` 只用 bit 0；bit 1–7 是 spare → CommonSpareBits = `0b1111_1110`。
- Occupied bits = 1 → 每个 tag value容纳 2 个 empty case → 1 个 empty tag；numTags = 3；numTagBits = 2。
- Tag 位：最高的两个 spare bits——**bit 7 和 bit 6**。
- 实测编码：

```
.a(false) = [00]   .a(true) = [01]     tag 0；bit 0 是活的 payload
.b(false) = [40]   .b(true) = [41]     tag 1（bit 6）
.e0       = [80]                       tag 2（bit 7），编号 0
```

这个例子说明为什么对 spare-bits 枚举做字节粒度的布局描述是错的：case `a` 的 byte 0 **并不是**“永远等于 `0x00`”——只有第 7–1 位固定，bit 0 属于 payload。工具必须携带按位的掩码（[第三部分 3.3](#33-spare-bits-布局的位级解剖)）。

#### 2.6.6 枚举自己的 extra inhabitants

没用完的 tag 编码成为枚举自己的 XI——`MultiPayloadEnumImplStrategy::getFixedExtraInhabitantCount`（[`GenEnum.cpp:5843-5852`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/GenEnum.cpp#L5843-L5852)）：

```
totalTagBits = commonSpareBits + extra tag bits（向上取整到整字节）
XI = totalTagBits >= 32 ? MaxNumExtraInhabitants
                        : min(2^totalTagBits − numTags, MaxNumExtraInhabitants)
```

XI 的取值在 tag bits 上从全 1 往下*递减*（`GenEnum.cpp:5854-5900`）。`BoolPair`：`2⁷ − 3 = 125` 个 XI——实测 `BoolPair?.none` = `[fe]`（七个 spare bits 全置位，occupied bit 不做断言）。`Backend` 同样是 `2⁷ − 3 = 125`，所以 `Backend?` 还是 8 字节（实测：`.none` = `[07 00 00 00 00 00 00 f0]`——每个 spare bit 都置位了）。

### 2.7 Tagged multi-payload

payload 之间没有公共 spare bits——或者布局必须能被运行时重现——的时候，tag 追加在 payload area 之后。

#### 2.7.1 谁走这条路

1. **没有公共 spare bits。** 整数 payload 每一位都在用。
2. **泛型枚举——永远如此。** 运行时用 `swift_initEnumMetadataMultiPayload`（[`Enum.cpp:384-443`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/Enum.cpp#L384-L443)）实例化泛型枚举的 metadata，而它对 spare bits 一无所知。IRGen 也配合：对布局依赖泛型参数的 payload 直接清空 `CommonSpareBits`（`GenEnum.cpp:7189-7199`），保证编译期和运行时一致。实测代价：

   ```swift
   enum GenericPair<Element> {
       case a(Element)
       case b(Element)
   }
   // GenericPair<Renderer>: size = 9  （8 payload + 1 tag）
   // ……而等价的非泛型两类引用枚举是 8（spare bits）。
   ```

3. **Resilient payload**（编译期不知道布局），同样的道理。

#### 2.7.2 布局

内存形状：

```
┌────────────────────────────────────────┬─────────────────┐
│  payload area（P = 最大的 payload）    │  tag（T bytes） │
│  payload 值，或 empty case 的编号      │                 │
└────────────────────────────────────────┴─────────────────┘
size = P + T
```

出自 `swift_initEnumMetadataMultiPayload`：

```
payloadSize = 各 payload 类型的最大值
(numTags, numTagBytes) = getEnumTagCounts(payloadSize, emptyCases, payloadCases)
size = payloadSize + numTagBytes
XI   = numTagBytes == 4 ? INT_MAX
                        : (1 << (numTagBytes * 8)) − numTags     // Enum.cpp:411-415
XI   = min(XI, MaxNumExtraInhabitants)
```

#### 2.7.3 Case 编码

`swift_storeEnumTagMultiPayload`（[`Enum.cpp:677-701`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/Enum.cpp#L677-L701)）：payload case 在 tag byte 里存 case index，payload area 自由使用。empty case 在 tag byte 里存 `numPayloads + (emptyIndex >> payloadBits)`，并把 `emptyIndex` 的低位**零扩展写满整个 payload area**——`storeMultiPayloadValue` 委托给 `storeEnumElement`（[`EnumImpl.h:27-62`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/EnumImpl.h#L27-L62)），里面的 `memset(&dst[4], 0, size - 4)` 把存储字之后的部分全部清零。所以 empty case 的每个 payload byte 都是固定的——读取那边（`swift_getEnumCaseMultiPayload`，`Enum.cpp:704-725`）会把它读回来参与判别。

写成公式：

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

实测：

```swift
enum TwoU32 {
    case a(UInt32)
    case b(UInt32)
    case e0
}
// 推导：payloadSize = 4，payloadCases = 2，emptyCases = 1
//       getEnumTagCounts(4, 1, 2)：payloadSize ≥ 4 → numTags = 2 + 1 = 3 → 1 个 tag byte
//       size = 4 + 1 = 5
// .a(1000) = [e8 03 00 00 | 00]
// .b(0)    = [00 00 00 00 | 01]
// .e0      = [00 00 00 00 | 02]      整个 payload area 清零

enum GenericPairWithEmpty<Element> {
    case a(Element)
    case b(Element)
    case e0
}
// GenericPairWithEmpty<Renderer>.e0 = [00 ×8 | 02]         同一形态，size 9
```

#### 2.7.4 枚举自己的 extra inhabitants

就是 tag byte 里没用到的值，**从最大值往下**分配：XI 模式 `#i` 在 tag byte 里存 `~i`（`storeMultiPayloadExtraInhabitantTag`，[`Enum.cpp:649-655`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/Enum.cpp#L649-L655)）。实测：`TwoU32?` 还是 5 字节，而且

```
TwoU32?.none = [00 00 00 00 | ff]     ← XI #0 = tag byte 0xFF
```

### 2.8 `indirect` case 与其他特殊形态

**`indirect`** 在布局意义上把 payload 换成 `Builtin.NativeObject` 堆 box 指针（`GenEnum.cpp:6452-6461`）。所以 indirect 的 single-payload enum 拥有堆引用那饱和的 XI 库存——形态和 `Optional<某个类>` 完全一样：

```swift
indirect enum Tree {
    case node(Tree)
    case leaf
    case sentinel
}
// size = 8
// .leaf     = [00 00 00 00 00 00 00 00]    XI #0（空指针）
// .sentinel = [01 00 00 00 00 00 00 00]    XI #1
```

永远不会出现 tag byte——有二十多亿个 inhabitants 可以花。（把解析不出的 indirect payload 当成“0 个 XI”、进而预测出溢出 tag byte，正是本项目修过的一个真实 bug；见[第三部分 3.7](#37-实现者的陷阱清单)。）

**单 case 枚举**（`SingletonEnumImplStrategy`）：布局和 payload 完全相同（没有 payload 就是零大小）。**Uninhabited enum**：size 0、XI 0。

### 2.9 字节序

所有 tag value、empty case index 和多字节固定模式在 Apple 平台上都按**小端序**存储（`storeEnumElement` / `loadEnumElement` 处理了一般情形）。2 字节的 tag value `0x0102` 在内存里是 `[02 01]`。

### 2.10 三大策略对照表

| | Multi-payload spare-bits | Tagged multi-payload | Single-payload |
|---|---|---|---|
| Payload case 数 | ≥ 2，布局固定，存在公共 spare bits | ≥ 2——没有公共 spare bits，或泛型/resilient | 恰好 1 |
| Tag 的位置 | payload area 内选中的 spare bits（不够用时才追加 extra tag bytes） | payload area 之后的 extra tag bytes | payload area 内的 XI 模式；XI 用完后是 extra tag bytes |
| 大小开销 | 通常为 0 | numTagBytes（1/2/4） | XI 够用时为 0，之后是 numTagBytes |
| Empty case 编码 | tag → spare bits，编号 → occupied bits，其余位全是 0 | tag bytes = tag；payload area = 编号，零扩展 | payload 的第 k 号 XI 模式；或 tag bytes + 编号 |
| 枚举自己的 XI | `2^tagBits − numTags`，模式从全 1 往下数 | `2^(8·numTagBytes) − numTags`，tag byte 从 `0xFF` 往下数 | 只有 payload 剩下的 XI——追加的 tag bytes 一个也不贡献 |
| 典型 payload | 类引用、还有余量的嵌套枚举 | 整数、混合 payload、任何泛型枚举 | 什么都行（`Optional` 就是它） |
| 源码入口 | `GenEnum.cpp` `MultiPayloadEnumImplStrategy` | `Enum.cpp` `swift_initEnumMetadataMultiPayload` | `EnumImpl.h` `storeEnumTagSinglePayloadImpl` |

---

## 第三部分 —— 精通：源码中的机器

### 3.1 同一套 ABI，四处实现

上文的布局规则在 Swift 代码库里实现了**四遍**；弄清楚哪一份在什么时候运行，是整个体系的总钥匙：

| 实现 | 位置 | 运行时机 | 能力范围 |
|---|---|---|---|
| IRGen | [`lib/IRGen/GenEnum.cpp`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/GenEnum.cpp) | 编译期 | 全部能力，含 spare bits |
| 运行时 metadata 初始化 | [`stdlib/public/runtime/Enum.cpp`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/Enum.cpp) | 泛型/resilient 枚举第一次取 metadata 时 | **没有 spare bits**——只有 tagged |
| Value witnesses | 编译器生成，或 `EnumImpl.h` 模板 | 每次对 case 的运行时存取 | 这个枚举自己的契约 |
| RemoteInspection | [`stdlib/public/RemoteInspection/TypeLowering.cpp`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/RemoteInspection/TypeLowering.cpp) | 离线，靠反射元数据 | spare bits 需要外援（见 3.5） |

它们之间的不对称，正是这套 ABI 最容易踩坑的地方：

- **运行时不会做 spare bits。** `swift_initEnumMetadataMultiPayload` 只会算 tagged 布局。所以凡是运行时可能要重现布局的场合，IRGen 都拒绝使用 spare bits——这正是 `AllowFixedLayoutOptimizations` 这道闸门（`GenEnum.cpp:7189-7199`）的作用，也是所有泛型枚举都走 tagged 的原因。
- **Single-payload enum 从不把追加的 tag byte 暴露成 XI。** 溢出之后 extra tag byte 明明还有没用到的值，IRGen 却故意不提供它们（`GenEnum.cpp:3445-3448` 和 `7075-7078` 的 `FIXME`）——XI 数量*只*等于 payload 的余额。而 tagged multi-payload enum **会**暴露没用完的 tag value。这就是 `Int??` 每包一层多一个字节、`TwoU32?` 却保持 5 字节的原因——光凭直觉绝对猜不到的不对称。
- **RemoteInspection 对齐的是运行时，不是 IRGen。** 它的 `EnumTypeInfoBuilder::build`（[`TypeLowering.cpp:2028-2318`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/RemoteInspection/TypeLowering.cpp#L2028-L2318)）对 no-payload / single-payload 布局是从头重新推的（`TypeLowering.cpp:2213-2214` 甚至写着 “Below logic should match the runtime function swift_initEnumMetadataSinglePayload()”），但对 spare-bits 枚举，它必须去读编译器写进二进制的描述符（3.5）——光靠反射里的字段类型信息，重建不出 spare bits。

### 3.2 Single-payload witness 的解剖

`getEnumTagSinglePayloadImpl`（[`EnumImpl.h:102-139`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/EnumImpl.h#L102-L139)）分三步读取 case，每一步都有可学的东西：

```cpp
// 1. 如果有 extra tag bytes，里面的非零值直接判定结果：
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
// 2. 否则问 payload：这些字节是不是某个 XI 模式：
if (payloadNumExtraInhabitants > 0)
    return getExtraInhabitantTag(enumAddr, payloadNumExtraInhabitants, payload);
// 3. 都不是，那就是合法 payload。
return 0;
```

值得注意的地方：

- **4 字节窗口。** 读溢出编号时，`loadEnumElement` 只取 payload area 的前 4 字节——和写入那边的零扩展互为镜像。empty case index 在这套 ABI 里处处是 32 位的数。
- **XI 的分发是函数指针。** 第 2 步委托给 *payload 类型自己的* XI 实现（`getExtraInhabitantTag`）。枚举这一层只知道数量。这层间接正是离线工具撞墙的地方（3.4）——那个回调是代码，不是数据。
- **Tag 编号是层叠的算术。** payload = 0，然后是按模式顺序的 XI case，然后是溢出 case。编译器、运行时、反射、本项目——每一份实现都必须和这套算术严格一致，否则布局会悄无声息地岔开。

### 3.3 Spare-bits 布局的位级解剖

scatter 操作（2.6.2 已经热身过）是这套布局的核心。这里用 `BoolPair` 真实的 tag bits 再走一遍：

```
mask  = 0b1100_0000 （BoolPair 的两个 tag bit：bit 7 和 bit 6）
value = 0b10（tag 2）→ value 的 bit 0 → bit 6（掩码里最低的置位位）：0
                        value 的 bit 1 → bit 7：1
结果  = 0b1000_0000 = 0x80          ← BoolPair.e0，实测一致
```

三个后果值得强调：

**Payload case 的字节是部分固定的。** `BoolPair.a(…)` 的 byte 0 里，tag bits（bit 7、6 = `00`）加上*其余*的 spare bits（bit 5–1，固定是 0）是固定的，而 bit 0 是活的 payload。对这个字节的正确断言是 `byte[0] & 0b1111_1110 == 0b0000_0000`——按位断言，不是按字节断言。凡是给 spare-bits 的 payload case 渲染整字节“固定字节”的工具，都会一边断言 `a(true) = [00]`，一边被内存里的 `[01]` 打脸。（本项目的渲染器以前就有恰好这一类 bug，后来靠引入按字节的固定位掩码修好；第一部分 1.5 输出里的 `byte[0x0] & 0b00000111 = 0b00000000` 就是修复后的形式。）

**Empty case 是全固定的。** `getEmptyCasePayload` 从一个全零的 `APInt` 出发，往里 OR 进两次 scatter（`GenEnum.cpp:4063-4073`）——所以 empty case 的 payload area *每一位*都是模式的固定部分：选中的 spare bits = tag，occupied bits = 编号，剩下的位 = 0。只记录编号低几位的工具，是对模式的不完整描述。

**Empty case 按 tag 分组打包。** occupied bits 不到 32 时，每个 tag value携带 `2^occupiedBits` 个 empty case（`GenEnum.cpp:4289-4310`），编号在每个 tag 内重新从 0 开始。`numTagBits == spareBitCount` 这个边界要小心：“全部用上”分支（`GenEnum.cpp:7257`，`numTagBits >= commonSpareBitCount`）和“从最高位选取”分支恰好在这里汇合，而且两条路选出的位相同——这里差一位，所有 tag bit 都会悄悄偏移。

**XI 的取值在 tag bits 上从全 1 往下递减**，还经过一次旋转，让已用的 tag value和 inhabitants 干净地分开（`getFixedExtraInhabitantValue`，`GenEnum.cpp:5854-5900`）。所以 `BoolPair?.none = [fe]`：spare bits 全置位，payload bit 不做断言。

### 3.4 为什么 XI 的*模式*没法从数量推出来

离线工具的高频陷阱：value witness table 只公布 XI 的**数量**；**模式**是各类型的私有约定：

| 类型 | XI 模式的约定 |
|---|---|
| 堆引用 | 递增的无效地址：`0x0`、`0x1`、`0x2`…… |
| `Bool` | `2`、`3`、`4`…… |
| `String` | 预留的 `_StringObject` 判别状态——实测：带 2 个 empty case 时，`e0` = 全零，`e1` = 第二个字 = `0x1` |
| Tagged multi-payload | tag byte 从全 1 往下递减：`0xFF`、`0xFE`…… |
| Spare-bits multi-payload | tag bits 的模式从全 1 往下递减 |
| No-payload enum | 从 `caseCount` 往上递增的值 |
| Single-payload enum | payload 的模式序列，跳过已消耗的数量 |
| 结构体/元组 | *XI 最多的那一个字段*的模式（见 `findXIElement`，[`Enum.cpp:199-222`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/Enum.cpp#L199-L222)） |

模式是**递归复合**的：`Optional<Optional<Bool>>.none` 是 Bool 的模式 `#1`（= `3`，实测：`Bool??.none` = `[03]`、`.some(.none)` = `[02]`），因为内层 Optional 消耗了模式 `#0`。只拿着数量的公式生产不出这些字节——你要么持有各类型的具体约定（硬编码一套模型），要么持有活的 witness 代码。

这不是假想问题：真实二进制的 dump 里满是 empty case 模式为 `String` 判别状态或嵌套枚举编码的 single-payload enum。凡是从数量*编造*模式的工具，都会打印出貌似可信、实际错误的字节。诚实的选项只有本项目实现的那两条（3.6）：跑 witness（精确），或者明说“离线未解析”（诚实降级）。

### 3.5 `__swift5_mpenum` 描述符

Spare bits 只存在于编译器的脑海里，反射需要一份留档。编译器为每个固定布局的 multi-payload enum，往二进制的 `__swift5_mpenum` 段里写一个 `MultiPayloadEnumDescriptor`（[`include/swift/RemoteInspection/Records.h:381-484`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/RemoteInspection/Records.h#L381-L484)）：

```
TypeName            （指向 mangled 名字的相对指针）
SizeFlags           （高 16 位：内容大小，单位是 32 位字；最低位：是否用了 spare bits）
[ByteOffset|Count]  （掩码字节窗口在 payload area 里的位置）
[PayloadSpareBits]  （公共 spare-bit mask 本体，按字节窗口存储）
```

`EnumTypeInfoBuilder` 在 `TypeLowering.cpp:2242-2317` 消费它：有描述符（外加提供权威 size/XI 的 builtin type descriptor）时，再按 case 和 spare-bit mask 求交集，构建 `MultiPayloadEnumTypeInfo`；没有描述符——或者存在任何泛型 payload——就直接退回 tagged 公式（`TypeLowering.cpp:2243-2279`）。这是离线反射了解 spare bits 的*唯一*渠道；把这个段剥掉，所有 spare-bits 枚举都会降级。

### 3.6 MachOSwiftSection 怎么算枚举布局

本项目把这套 ABI 实现了两遍，对应两种信任模型。

#### 运行时路径——从构造上就精确

用在枚举 metadata 已经加载进本进程的场合（`MachOImage`）。流水线在 `RuntimeFieldLayoutBackend` + `SwiftInspection` 里：

1. **公式先行。** `EnumLayoutCalculator`（`Sources/SwiftInspection/EnumLayoutCalculator.swift`）是第二部分那些算法的逐行审计移植——`calculateSinglePayload`、`calculateMultiPayload`（spare bits，掩码来自 `__swift5_mpenum`）、`calculateTaggedMultiPayload`。它产出每个 case 的投影，包括按字节的**固定位掩码**（3.3）和按策略算出的 XI 数量（2.6.6、2.7.4）。
2. **Payload 的 XI 取自真实 VWT。** payload 的 XI 数量从它活的 value witness table 里读。`indirect` payload 特判为堆对象的数量 `0x7FFF_FFFF`（2.5.2）。payload 类型解析不出来时，从枚举自己的 VWT *反推*：payload-sized 布局下，`payloadXI = enumXI + emptyCases` 就是运行时那步减法的精确逆运算（2.5.1）；溢出布局反推不出来，那就宁可放弃这个布局也不去猜。
3. **精确模式来自 witness 本体。** `RuntimeEnumCaseProjector`（`Sources/SwiftInspection/RuntimeEnumCaseProjector.swift`）靠*运行*枚举自己的 `destructiveInjectEnumTag` witness 来解析 XI 模式（3.4）：每个 case 注入两次——一次注进全 `0x00` 的缓冲区、一次注进全 `0xFF` 的——两次结果一致的字节就是被确定性写入的字节。empty case 还必须经 `getEnumTag` 往返校验，否则整个投影被拒绝。（双基线这一招之所以成立，正是因为 single-payload 的注入是*覆盖写*；spare-bits 的注入是 OR，所以那个策略的模式改从掩码取得。）
4. **对照 ground truth 交叉校验。** 组装出的布局，它推算出的总大小必须等于枚举 VWT 的 size，否则整个布局作废——派生输入（payload 大小、spare mask）可能出错，而一个自信的错误答案比没有答案更糟。

#### 静态路径——离线，对自己的极限诚实

用在 `MachOFile`（没有进程）。`EnumLayoutBridge`（`Sources/SwiftLayout/EnumLayoutBridge.swift`）按下面的顺序解析：

1. **优先拿编译器自己的答案**：`__swift5_builtin` 整型布局描述符（IRGen 算出的 size/stride/alignment/XI 原样照录）——和 RemoteInspection 信任的是同一来源。
2. **没有就结构化计算**：payload 类型经镜像依赖闭包递归解析，`__swift5_mpenum` 的掩码喂给 `calculateMultiPayload`，而且——比官方离线实现更进一步——**spare-bits 的 XI 数量也结构化推导**（`TypeLowering.cpp` 从来不这么做；没有 builtin 描述符时它直接退回 tagged 的 XI）。
3. **泛型枚举一律走 tagged 分支**——不管有没有实例化——和运行时对齐（2.7.1）。
4. **对模式诚实降级**：single-payload 的 empty case，如果它具体的 XI 字节需要执行 witness 才能得到，就渲染成 “stored as the payload's extra-inhabitant pattern #N” 并明确标注*离线未解析*——绝不编造字节（3.4）。

### 3.7 实现者的陷阱清单

以下条目提炼自本项目对照上述源码的逐行审计——每一条要么是这里真实修过的 bug，要么是源码自己写下的警示：

1. **indirect 的 single-payload enum 是 XI 布局，不是溢出布局。** 它的 payload 是一个拥有 `0x7FFF_FFFF` 个 inhabitants 的 box 指针。从“payload 类型解析不出来”推出“0 个 XI”，会产出越界的 tag 区域和自相矛盾的 dump（2.8）。
2. **Empty case 固定的是*整个* payload area。** tagged：零扩展（`storeEnumElement` 里的 `memset`）；spare-bits：从全零 `APInt` 出发的 scatter。只记录 `ceil(log2(N))` 位，会诱导“其余字节随便是什么”的误读（2.6.3、2.7.3）。
3. **Spare-bits 的 payload case 必须按位描述，不能按字节。** 同一个字节可以同时装着 tag bit 和活的 payload bit（`BoolPair`，3.3）。
4. **饱和上限出现两次。** 堆引用的 XI 在 `INT_MAX` 处饱和（`Metadata.h:925`），而且每个策略的 XI 公式都封顶在 `MaxNumExtraInhabitants`（`MetadataValues.h:183`）。近似其中任何一个（硬编码 4096、不封顶的 `1 << bits`）都会把真实枚举的大小算错。
5. **小 payload 的阈值是 4 字节，不是指针宽度**——`getEnumTagCounts` 里、溢出编号的拆分里、运行时的读取窗口里都是（2.3、3.2）。
6. **派生出的布局要对照 VWT 交叉校验。** payload 大小和 spare mask 都是*派生*输入；输入一错，公式会兴高采烈地产出一个错误布局。`impliedTotalSize == vwt.size` 能拦下一整类静默错误（3.6）。
7. **XI 的消耗有顺序、有层次。** empty case 按声明顺序消耗模式；外层包装从内层停下的地方接着消耗（`ThreeBools?.none = [04]`，2.5.2）。这里差一，所有嵌套模式全体偏移。
8. **Case index 是 payload case 在前**——field records 里、`getEnumTag` 里、所有公式里都是。还要记住编号之前的重分类：零大小 payload → empty case；unavailable 的 case → empty case（2.1）。
9. **不要指望 single-payload 的 tag byte 产出 XI。** 3.1 那个不对称（`Int??` 变大而 `TwoU32?` 不变）是故意的、带着 `FIXME` 注释的行为——按它的原样建模。

### 3.8 源码地图

全部引用汇总成一张表（标签 `swift-6.3.3-RELEASE`）：

| 文件 | 角色 | 关键符号 |
|---|---|---|
| [`include/swift/ABI/Enum.h`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/ABI/Enum.h) | 公共 tag 计数公式 | `getEnumTagCounts` (28) |
| [`stdlib/public/runtime/EnumImpl.h`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/EnumImpl.h) | single-payload 存取模板 | `storeEnumElement` (27)、`getEnumTagSinglePayloadImpl` (102)、`storeEnumTagSinglePayloadImpl` (141) |
| [`stdlib/public/runtime/Enum.cpp`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/Enum.cpp) | 运行时 metadata 初始化 + multi-payload witnesses | `swift_initEnumMetadataSinglePayload` (126)、`swift_initEnumMetadataMultiPayload` (384)、`swift_storeEnumTagMultiPayload` (677) |
| [`lib/IRGen/GenEnum.cpp`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/GenEnum.cpp) | 编译期布局 | `EnumImplStrategy::get` (6394)、single-payload `completeFixedLayout` (7029)、multi-payload `completeFixedLayout` (7152)、`getEmptyCasePayload` (4063)、各 XI 计数 (1228、3457、5843) |
| [`lib/IRGen/ExtraInhabitants.cpp`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/ExtraInhabitants.cpp) | 指针 XI | `PointerInfo::getExtraInhabitantCount` (50) |
| [`include/swift/Runtime/Metadata.h`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/Runtime/Metadata.h) | 堆对象 XI 数量 | `swift_getHeapObjectExtraInhabitantCount` (925) |
| [`include/swift/ABI/MetadataValues.h`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/ABI/MetadataValues.h) | XI 上限 | `MaxNumExtraInhabitants` (183) |
| [`stdlib/public/SwiftShims/swift/shims/System.h`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/SwiftShims/swift/shims/System.h) | 各平台指针 ABI | `LEAST_VALID_POINTER` (153)、arm64 spare-bit mask (166-171) |
| [`stdlib/public/RemoteInspection/TypeLowering.cpp`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/RemoteInspection/TypeLowering.cpp) | 官方离线实现 | `EnumTypeInfoBuilder::build` (2028)、各 `*EnumTypeInfo` 类 (613-1150) |
| [`include/swift/RemoteInspection/Records.h`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/RemoteInspection/Records.h) | spare bits 的留档 | `MultiPayloadEnumDescriptor` (381) |

本仓库中：

| 文件 | 角色 |
|---|---|
| `Sources/SwiftInspection/EnumLayoutCalculator.swift` | 公式移植（三大策略、逐 case 投影、固定位掩码） |
| `Sources/SwiftInspection/RuntimeEnumCaseProjector.swift` | witness 驱动的精确模式投影 |
| `Sources/SwiftDeclarationRendering/RuntimeFieldLayoutBackend.swift` | 运行时路径组装：VWT 读取、XI 反推、大小交叉校验 |
| `Sources/SwiftLayout/EnumLayoutBridge.swift` | 静态路径组装：builtin 描述符、`__swift5_mpenum`、结构化回退 |
| `Tests/SwiftInspectionTests/EnumLayoutVerificationTests.swift` | 本文每一条公式对照活内存的验证 |

---

## 附录：注释渲染——模板与预设

`swift-section dump --emit-enum-layout`（以及库内渲染器）输出的注释由 token 模板 `Transformer.SwiftEnumLayout`（`SemanticTransformer` 模块）驱动。三层模板对应注释结构——类型级策略行、逐 case 块、逐固定字节行——用 `${token}` 占位（和 RuntimeViewerCore 的 transformer UI 同名）。内置五种预设，CLI 通过 `--enum-layout-style` 选择：

| 预设 | 逐字节行 | 风格 |
|---|---|---|
| `detailed`（默认） | 有 | 完整的内置渲染；部分固定的字节用二进制掩码（`fixed bits 0b11110000 = 0b01000000`） |
| `explained` | 有 | 信息相同，但部分固定的字节改成位段叙述：`bits 7-4 are always 0100; the other bits (3-0) hold payload data` |
| `standard` | 无 | Case 标题 + 编码语句 + 一行固定字节摘要 |
| `inline` | 无 | 每个 case 一行，字节摘要内联在冒号后：`` Case 1 `implicit` (empty case #0): bytes[0x8..<0x10] = 0x1 `` |
| `compact` | 无 | 每个 case 一行，不含字节信息：`` [0x01] `caseName` — payload case, tag 1 `` |

库用户在 `DeclarationRenderConfiguration` 或 `SwiftDeclarationPrintConfiguration` 上调用 `applyTransformers(_:)`，传入一个 `Transformer.SwiftConfiguration`，其 `swiftEnumLayout` 可以是预设（`Transformer.SwiftEnumLayout.Preset`）或自定义模块；同一机制也覆盖 field-offset / type-layout / member-address / vtable-offset 注释模板。`detailed` 预设有单元测试保证和内置默认渲染完全一致，所以默认输出永远不会漂移。
