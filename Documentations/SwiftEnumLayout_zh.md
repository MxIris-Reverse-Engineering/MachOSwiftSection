# Swift Enum 内存布局 —— 从入门到精通

Swift 的枚举以紧凑著称：`Optional<SomeClass>` 只占 8 字节，包着两个类引用的
枚举也还是 8 字节，给包着 `Bool` 的枚举再加空 case 更是分文不花。支撑这一切
的机制是 Swift ABI 中最精巧的部分之一，分散在编译器 IR 生成、运行时与反射库
三处。

本文**从零开始**讲清这套机制：

- **[第一部分 —— 实用指南](#第一部分--实用指南)** 面向只想*预测大小、看懂
  布局输出*、不打算研究 ABI 的读者。若这就是你的全部需求，读完第一部分即可
  停下。
- **[第二部分 —— 三大策略](#第二部分--三大策略)** 推导真正的布局算法——
  公式、case 编码、精确到字节的模式——并配有完整的工作示例。
- **[第三部分 —— 精通](#第三部分--精通源码中的机器)** 解剖 Swift 源码树中
  的具体实现：谁在何时算什么、spare-bits 布局的位级解剖、离线工具为何在原理
  上无法恢复某些信息，以及本项目（MachOSwiftSection）如何同时实现了运行时
  精确引擎与静态（离线）布局引擎。

**全文约定：**

- 所有 Swift 源码引用固定在
  [`swift-6.3.3-RELEASE`](https://github.com/swiftlang/swift/tree/swift-6.3.3-RELEASE)
  标签，以 `path/to/File.ext:line` 形式给出。例如
  [`include/swift/ABI/Enum.h:29`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/ABI/Enum.h#L29)
  即该标签下该文件第 29 行。
- 平台为 **64 位小端序 Apple 平台**（arm64 / x86_64 的 macOS、iOS……）。
  字节转储从偏移 0 起自左向右打印（因此多字节整数的*最低*有效字节先出现）。
- **本文的每一段字节转储都是真实输出**，由探针程序（`MemoryLayout` +
  `withUnsafeBytes`）在 arm64 macOS 上用 Swift 6.3.3 工具链编译运行得到——
  与所引源码同一版本。

---

## 第一部分 —— 实用指南

### 1.1 三个问题决定一切

要预测一个枚举的布局，只需回答三个问题：

1. **有几个 case 带 payload？**
   零个 payload → 枚举就是一个小整数 tag。
   一个 payload → “单 payload”策略。
   两个及以上 → 两种“多 payload”策略之一。

2. **最大的 payload 有多大？**
   枚举总会预留一块与最大 payload 等大的 *payload 区*。其余问题全都归结为
   判别值（*tag*）放在哪里。

3. **payload 类型有没有用不到的位模式？**
   类引用、`Bool`、`String` 这类类型无法用满其存储的所有位模式。Swift 会
   激进地把这些“不可能出现的模式”回收利用，把 tag *藏进 payload 区内部*
   ——零开销。而 `Int`、`UInt8`、`Double` 这类用满所有位的类型，tag 只能
   放进 payload 之后追加的额外字节里。

“用不到的模式”有两种形态，后文会反复出现：

- **Extra inhabitants（XI，额外栖息值）**——payload 类型永远不会取到的完整
  *值*（例如类引用永远不会是 `0x0`、`0x1` 这样的小整数）。单 payload 枚举
  使用它。
- **Spare bits（空闲位）**——在*每个* payload 的每个合法值中都恒为零的单个
  *位*（例如 64 位指针的高位）。多 payload 枚举使用它。

### 1.2 五个枚举速览

下面这组转储就是全文内容的微缩版。

**无 payload 枚举就是一个字节大小的 tag**（按声明顺序取 0、1、2……）：

```swift
enum Direction { case north, south, east, west }
// size=1  north=[00]  west=[03]
```

**payload 类型没有可用模式时，单 payload 枚举追加一个 tag 字节**——并把
payload 区复用为空 case 的编号：

```swift
enum Fetched { case payload(UInt32); case missing; case failed }
// size=5（4 payload + 1 tag）
// .payload(1000) = [e8 03 00 00 | 00]   tag 0 = “合法 payload”
// .missing      = [00 00 00 00 | 01]   tag 1，payload 区存编号 0
// .failed       = [01 00 00 00 | 01]   tag 1，payload 区存编号 1
```

**payload 类型*有*可用模式时，单 payload 枚举零开销**：

```swift
final class Renderer { var identifier = 0 }
// Optional<Renderer>: size=8 —— 与裸引用一样大！
// .none = [00 00 00 00 00 00 00 00]    （“空指针”这一 extra inhabitant）

enum ThreeBools { case value(Bool); case unset; case invalid }
// size=1 —— Bool 只用 0 和 1，2..255 全是免费的 tag：
// .value(false)=[00]  .value(true)=[01]  .unset=[02]  .invalid=[03]
```

**类引用的多 payload 枚举把 tag 藏进指针位里**：

```swift
final class Compositor { var identifier = 0 }
enum Backend {
    case metal(Renderer)      // byte 7 高位 = 00
    case software(Compositor) // byte 7 高位 = 01（bit 62 置位）
    case headless             // [00 00 00 00 00 00 00 80]（bit 63 置位）
    case disabled             // [08 00 00 00 00 00 00 80]
}
// size=8 —— 仍然只有一个指针宽。
```

**整数的多 payload 枚举追加一个 tag 字节**：

```swift
enum TwoU32 { case a(UInt32); case b(UInt32); case e0 }
// size=5
// .a(1000) = [e8 03 00 00 | 00]   tag 0
// .b(0)    = [00 00 00 00 | 01]   tag 1
// .e0      = [00 00 00 00 | 02]   tag 2，payload 区清零
```

### 1.3 大小速查表

所有数值均在 arm64 macOS、Swift 6.3.3 上验证。

| 枚举形态 | 大小 | 原因 |
|---|---|---|
| `enum { case a, b, c }`（≤ 256 case） | 1 | tag 字节；至 65536 case 用 2 字节，再往上 4 字节 |
| `Optional<AnyObject>` / 任意类引用 | 8 | 空指针 + 低位无效地址都是 extra inhabitants |
| `Optional<UnsafeRawPointer>` | 8 | 空指针是*唯一*的 extra inhabitant |
| `Optional<UnsafeRawPointer?>` | 9 | ……于是第二层 `Optional` 只能追加 tag 字节 |
| `Optional<Bool>` | 1 | `Bool` 有 254 个 extra inhabitants（2…255） |
| `Optional<String>` | 16 | `String` 预留了巨大的 extra-inhabitant 空间 |
| `Optional<Int>` | 9 | `Int` 用满 2⁶⁴ 个模式 → 追加 tag 字节 |
| `Optional<Int?>` | 10 | 每包一层无 XI 的 `Optional` 多一个字节 |
| `Optional<(() -> Void)>` | 16 | 函数 =（代码指针，上下文）；代码指针字携带 XI |
| 2+ 个类引用 payload（上文 `Backend`） | 8 | tag 藏在指针的 spare bits 里 |
| 2+ 个整数 payload（上文 `TwoU32`） | payload + 1 | 没有 spare bits → 追加 tag 字节 |
| 任何 2+ payload 的*泛型*枚举，如 `enum G<T> { case a(T); case b(T) }` 之 `G<Renderer>` | 9 | 泛型布局从不使用 spare bits——见 [2.7](#27-tagged-多-payload) |
| `indirect` case | 每个 8 | indirect payload 是堆上 box 的指针 |
| `enum { case v(Void); case e }` | 1 | 零大小 payload 按空 case 布局 |
| `Never`（无值类型） | 0 | 没有值就没有存储（stride 仍为 1） |

> **`size` 与 `stride`：**`size` 是有效范围（本文讨论的对象）；`stride` 把
> size 向对齐取整，用于数组元素间距。`TwoU32` size 5 而 stride 8；`Int?`
> size 9 而 stride 16。

### 1.4 经验法则

- **空 case 在 payload 的 extra inhabitants 用完之前都是免费的。**
  给 `Optional<SomeClass>` 再加一百个空 case 也还是 8 字节。
- **指针是 XI 富矿，整数是 XI 荒漠。** 类引用有约 2³¹ 个 extra
  inhabitants；`Int`/`UInt8`/`Double` 一个也没有；`Bool` 有 254 个；
  `UnsafeRawPointer` 恰有 1 个（空指针）。
- **每层 `Optional` 恰好消耗一个 extra inhabitant。** 库存充足时层层免费
  （`Bool??` 仍 1 字节），库存耗尽后每层加一字节（`Int??` 10 字节、
  `Int???` 11 字节）。
- **类引用的多 payload 枚举保持指针大小**；混入一个没有 spare bits 的
  payload（如 `Int`）就会强制追加 tag 字节。
- **泛型枚举必付 tagged 的代价**，即使实参是指针类型：上文 `G<Renderer>`
  是 9 字节，而等价的非泛型枚举是 8 字节。
- **`indirect` 把 payload 变成指针**——indirect 单 payload 枚举与
  `Optional<类>` 形态完全一致：8 字节，空 case 取 `0x0`、`0x1`……

### 1.5 用 `swift-section` 直接查看布局

本项目可以直接从二进制渲染上述一切——无需加载进程：

```bash
swift-section dump --emit-enum-layout /path/to/binary
# 注释风格由详到简：
swift-section dump --emit-enum-layout --enum-layout-style explained ...
swift-section dump --emit-enum-layout --enum-layout-style standard ...
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

- **策略行**给出布局策略及其参数。
- 每个 **case 块**给出该 case 的 tag 值与固定（确定性）字节。
- `byte[0x7] & 0b11110000 = 0b01000000` 是**部分字节**：只有掩码内的位被
  声明。该字节的其余位承载活的 payload 数据（这里是指针位）——这是关键的
  诚实性细节，详见[第三部分 3.3](#33-spare-bits-布局的位级解剖)。
- `leftover extra inhabitants` 是*外层*枚举再包一层时仍可免费使用的量。

大多数用户到此已经够用。本文其余部分解释这些答案*为什么*成立。

---

## 第二部分 —— 三大策略

### 2.1 编译器如何选择策略

策略选择发生在
`EnumImplStrategy::get`（[`lib/IRGen/GenEnum.cpp:6394`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/GenEnum.cpp#L6394)）。
在给每个 case 分类之后，决策树是：

```
resilient 枚举（编译期布局未知）        → ResilientEnumImplStrategy   (GenEnum.cpp:6523)
C 导入 / @objc / C 兼容                → CCompatibleEnumImplStrategy (GenEnum.cpp:6541)
总 case 数 0 或 1                      → SingletonEnumImplStrategy   (GenEnum.cpp:6552)
≥ 2 个 payload case                    → MultiPayloadEnumImplStrategy(GenEnum.cpp:6559)
恰 1 个 payload case                   → SinglePayloadEnumImplStrategy (GenEnum.cpp:6567)
其余（全是空 case）                    → NoPayloadEnumImplStrategy   (GenEnum.cpp:6575)
```

计数*之前*有三个分类细节：

- **`indirect` case 按类型为 `Builtin.NativeObject`（堆 box 指针）的
  payload case 计**——`GenEnum.cpp:6452-6461`。payload 的真实类型不影响
  布局。
- **零大小 payload（如 `Void`、`Never`）按空 case 计**——
  `GenEnum.cpp:6483-6489`。这就是
  `enum { case v(Void); case e }` 是 1 字节无 payload 枚举的原因
  （实测：`.v(())` = `[00]`，`.e` = `[01]`）。
- **lowering 期间不可用（unavailable）的 case 按无 payload 处理**——
  `GenEnum.cpp:6445-6450`。

多 payload 策略内部再分两支：若各 payload 有公共 **spare bits**，tag 藏进
其中（[2.6](#26-多-payload-spare-bits)）；若没有——或枚举布局是泛型/动态的
——则追加 tag 字节（[2.7](#27-tagged-多-payload)）。

### 2.2 术语表

| 术语 | 含义 |
|---|---|
| **Payload case** | 携带关联值的 case |
| **空 case** | 无关联值的 case（经上述重分类之后） |
| **Payload 区** | 枚举值的前 `max(各 payload 大小)` 个字节 |
| **Tag** | 区分 case 的判别值 |
| **Extra inhabitants（XI）** | 类型的值永远不会使用的完整位*模式*，可被外层枚举复用 |
| **Spare bits** | 在类型的每个合法值中恒为零的单个*位* |
| **Occupied bits** | spare bits 的补集——承载真实 payload 数据的位 |
| **额外 tag 字节** | 追加在 payload 区之后的判别字节 |
| **Case 编号** | 先 payload case（按声明顺序），后空 case（按声明顺序）。`getEnumTag`、反射 field records 与所有公式都使用这一编号。 |

### 2.3 公共底层函数：`getEnumTagCounts`

ABI 中所有“需要几个 tag 字节？”的答案都出自同一个小函数，短到可以全文引用
（[`include/swift/ABI/Enum.h:28-49`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/ABI/Enum.h#L28-L49)）：

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

其中的逻辑：当某个 tag 值表示“这是空 case”时，payload 区就是死存储——于是
*复用*它来存空 case 的编号。`size` 字节的 payload 区每个 tag 值可以编号
`2^(size*8)` 个空 case：

- **`size >= 4`**：payload 区能编号 2³² 个空 case——超过任何真实枚举——
  所以*一个*额外 tag 值就能覆盖全部空 case。
- **`size < 4`**：小 payload 区每个 tag 值只能编号 `2^(size*8)` 个，空
  case 要摊到 `ceil(emptyCases / 2^(size*8))` 个 tag 值上。

工作示例：

```
getEnumTagCounts(size: 4, emptyCases: 2, payloadCases: 1)
  → numTags = 1 + 1 = 2       → 1 个 tag 字节     （`Fetched`：4+1 = 5 字节）

getEnumTagCounts(size: 1, emptyCases: 300, payloadCases: 1)
  → 300 个空 case / 每 tag 256 个 = 2 个 tag 值 → numTags = 3 → 1 个 tag 字节

getEnumTagCounts(size: 0, emptyCases: 300, payloadCases: 1)
  → 2^0 = 每 tag 1 个 → numTags = 1 + 300 = 301 → 2 个 tag 字节
```

注意阈值是 **4 字节**而非指针宽度——这是常见的记忆偏差。

### 2.4 无 payload 枚举

所有 case 都为空。值*就是* tag：第 `i` 个 case（声明顺序）以最小够用宽度的
小端整数存储 `i`：

| Case 数 | 大小 |
|---|---|
| 0 或 1 | 0 字节 |
| 2 … 256 | 1 字节 |
| 257 … 65536 | 2 字节 |
| 更多 | 4 字节 |

实测：`Direction.north` = `[00]`，`.west` = `[03]`。

最后一个 case *之上*的值就是该枚举自己的 extra inhabitants——
`NoPayloadEnumImplStrategy::getFixedExtraInhabitantCount`
（[`GenEnum.cpp:1228-1236`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/GenEnum.cpp#L1228-L1236)）：

```
XI = min(2^(size*8) − caseCount, MaxNumExtraInhabitants)
```

`Direction` 有 `256 − 4 = 252` 个 extra inhabitants，因此 `Direction?` 仍是
1 字节（`.none` 即 `[04]`）。上限 `MaxNumExtraInhabitants = 0x7FFFFFFF`
（[`include/swift/ABI/MetadataValues.h:183`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/ABI/MetadataValues.h#L183)）
只在 4 字节 tag 时才起作用。

两个特殊亲戚：

- **无值枚举**（`Never`、`enum Empty {}`）：由 `SingletonEnumImplStrategy`
  处理——size 0、stride 1、**0 个 extra inhabitants**（没有可复用的 tag
  存储）。
- **`@objc` / C 导入枚举**：C 兼容布局——大小即原始类型的大小，任何位模式
  皆合法，没有 extra inhabitants，也没有任何打包技巧。

### 2.5 单 payload 枚举

恰有一个 payload case、`N` 个空 case。这是 `Optional` 的策略，也是真实二进
制里最常见的形态。

#### 2.5.1 大小的决定

运行时的 metadata 实例化写得明明白白
（[`stdlib/public/runtime/Enum.cpp:138-146`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/Enum.cpp#L138-L146)）：

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

一句话：空 case 按声明顺序先消耗 payload 的 extra inhabitants；只有*溢出*
的部分——超出 XI 库存的空 case——才迫使追加 tag 字节。

#### 2.5.2 Extra inhabitants：这套机制的通货

Extra inhabitant 是 payload 类型永远不会产生的全宽位模式。**个数**来自
payload 的 value witness table；**模式本身**则是 payload 类型的私有约定。
64 位 Darwin 上的实测个数：

| Payload 类型 | XI 个数 | 模式 |
|---|---|---|
| `Bool` | 254 | 值 `2 … 255` |
| 类 / `AnyObject` / 堆引用 | `0x7FFF_FFFF`（饱和） | 小无效地址 `0x0, 0x1, 0x2, …` |
| `UnsafeRawPointer` 家族 | 1 | 仅空指针 |
| `String` | `0x7FFF_FFFF`（饱和） | 预留的 `_StringObject` 判别模式 |
| Thick 函数（`() -> Void`） | 代码指针字上 `0x7FFF_FFFF` | 无效函数地址 |
| `Int`、`UInt8`、`Double`…… | 0 | — |
| `weak` 引用 | 0 | — |
| 另一个枚举 | 其剩余 XI | 该枚举未用的 tag 编码 |

堆引用的个数值得推导一次，因为它无处不在。
[`include/swift/Runtime/Metadata.h:925-939`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/Runtime/Metadata.h#L925-L939)：

```cpp
inline constexpr unsigned swift_getHeapObjectExtraInhabitantCount() {
  // The runtime needs no more than INT_MAX inhabitants.
  return (LeastValidPointerValue >> ObjCReservedLowBits) > INT_MAX
    ? (unsigned)INT_MAX
    : (unsigned)(LeastValidPointerValue >> ObjCReservedLowBits);
}
```

Darwin 64 位上 `LeastValidPointerValue` 是 `0x1_0000_0000`——地址空间的前
4 GiB 永远不会放 Swift 堆对象
（[`stdlib/public/SwiftShims/swift/shims/System.h:153`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/SwiftShims/swift/shims/System.h#L153)）。
它超过 `INT_MAX`，于是个数饱和为 `0x7FFF_FFFF`。IRGen 侧的镜像实现是
`PointerInfo::getExtraInhabitantCount`
（[`lib/IRGen/ExtraInhabitants.cpp:50-61`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/ExtraInhabitants.cpp#L50-L61)）。

**消耗账本。** 枚举花掉 payload 的 `k` 个 inhabitants 后，枚举自己的 XI 个
数就是余额——`SinglePayloadEnumImplStrategy::getFixedExtraInhabitantCount`
（[`GenEnum.cpp:3457-3460`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/GenEnum.cpp#L3457-L3460)）：

```cpp
return getFixedPayloadTypeInfo().getFixedExtraInhabitantCount(IGM)
         - getNumExtraInhabitantTagValues();
```

且其 XI *取值*就是 payload 的模式序列跳过已消耗部分。看账本在真实链条上
运转（每段转储皆实测）：

```swift
enum ThreeBools { case value(Bool); case unset; case invalid }
// Bool 的 XI 模式：2, 3, 4, 5, ...
// .unset   = [02]    ← 消耗了 XI #0
// .invalid = [03]    ← 消耗了 XI #1
// ThreeBools 自己的 XI：还剩 252 个，模式从 4 起。

ThreeBools?.none          // = [04]  ← Optional 消耗了 ThreeBools 的 XI #0
```

以及库存耗尽的情形：

```swift
UnsafeRawPointer?          // 8 字节；.none = [00 00 00 00 00 00 00 00]（空指针 XI）
UnsafeRawPointer??         // 9 字节！内层 Optional 花掉了唯一的 XI；
                           // .none         = [00 ×8 | 01]  （溢出 tag）
                           // .some(.none)  = [00 ×8 | 00]
Int?    // 9 字节  （Int 没有 XI）
Int??   // 10 字节 （每层加一字节）
Int???  // 11 字节
```

#### 2.5.3 Case 编码

单 payload 的存取逻辑在
`storeEnumTagSinglePayloadImpl` / `getEnumTagSinglePayloadImpl`
（[`stdlib/public/runtime/EnumImpl.h:141-190`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/EnumImpl.h#L141-L190) /
[`EnumImpl.h:102-139`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/EnumImpl.h#L102-L139)）。
Case 编号：payload = 0，空 case 为 1…N。三种编码：

**Payload case（`whichCase == 0`）：** payload 字节即值本身；若存在额外
tag 字节则全部清零。选中方式是排除法——字节不匹配任何空 case 模式。

**Extra-inhabitant case（`1 <= whichCase <= payloadXI`）：** payload 区被
写成 payload 类型的第 `whichCase − 1` 号 XI 模式；若（因*其他* case 溢出
而）存在额外 tag 字节则清零（`EnumImpl.h:156-169`）。

**溢出 case：** 额外 tag 字节写入非零值，payload 区复用为编号
（`EnumImpl.h:172-189`）：

```cpp
unsigned caseIndex = (whichCase - 1) - payloadNumExtraInhabitants;
if (payloadSize >= 4) {
  extraTagIndex = 1;                 // 一个 tag 值覆盖一切
  payloadIndex = caseIndex;
} else {
  unsigned payloadBits = payloadSize * 8U;
  extraTagIndex = 1U + (caseIndex >> payloadBits);
  payloadIndex = caseIndex & ((1U << payloadBits) - 1U);
}
```

用小 payload 溢出枚举实测验证：

```swift
enum SP_U8 { case p(UInt8); case e0; case e1; case e2 }   // UInt8：0 XI
// size=2:  [payload 字节 | tag 字节]
// .p(0x2A) = [2a | 00]
// .e0      = [00 | 01]     caseIndex 0 → tag 1，payload 0
// .e1      = [01 | 01]     caseIndex 1 → tag 1，payload 1
// .e2      = [02 | 01]     caseIndex 2 → tag 1，payload 2
```

以及由此推出的 `Optional` 嵌套分层：

```swift
Int??.none         = [00 ×8 | 00 | 01]   // 外层 tag 字节 = 1
Int??.some(.none)  = [00 ×8 | 01 | 00]   // 内层 .none（tag 1），外层“合法 payload”（0）
```

### 2.6 多 payload spare-bits

两个及以上 payload case，且各 payload 类型留有公共 **spare bits**——在
*每个* payload 的每个合法值中都可证恒为零的位。

#### 2.6.1 Spare bits 从哪来

典型来源是指针。arm64 Darwin 上，Swift 堆引用的 spare-bit 掩码是
`0xF000_0000_0000_0007`
（[`shims/System.h:166`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/SwiftShims/swift/shims/System.h#L166)）：
最高的半字节（那里没有有意义的地址空间）加最低 3 位（堆对象至少 8 字节对
齐）。可能持有 Objective-C 对象的引用要让出最高位——ObjC tagged-pointer 位
（[`shims/System.h:170`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/SwiftShims/swift/shims/System.h#L170)）——
而指向 Swift 原生类的引用保有全部 7 位。其他来源：`Bool` 贡献第 1–7 位；
嵌套枚举未用的 tag 编码也可以浮出为 spare bits。

#### 2.6.2 布局算法

`MultiPayloadEnumImplStrategy::completeFixedLayout`
（[`GenEnum.cpp:7152-7304`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/GenEnum.cpp#L7152-L7304)）依次：

1. **求交。** `CommonSpareBits` = 所有 payload spare-bit 掩码的按位与，宽
   度取最大 payload（`GenEnum.cpp:7162-7210`）。凡是运行时可能需要重现布
   局的 payload（泛型/resilient）*不*贡献任何 spare bits——见 2.7。

2. **为空 case 计 tag 数**（`GenEnum.cpp:7216-7228`）。空 case 编号写进
   *occupied* 位里，每个 tag 值容纳 `2^occupiedBits` 个（occupied 位达到
   32 时一个 tag 全包）：

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

4. **放置 tag。** 若 `numTagBits` 塞得进公共 spare bits，就**从最高位起**
   选取那么多位（`GenEnum.cpp:7286-7302`）——它们成为 `PayloadTagBits`。
   否则用上*全部* spare bits，再追加 `numTagBits − spareBitCount` 个额外
   tag 位、向上取整到整字节（混合形态，`GenEnum.cpp:7232-7247`）。

5. **编码。** **payload case**：tag 值*散布*（scatter）进选中的 tag 位
   （tag 低位 → 掩码内最低位）；occupied 位承载活 payload。**空 case**：
   tag 与空 case 编号散布进一个**零值** payload——
   `getEmptyCasePayload`（[`GenEnum.cpp:4063-4073`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/GenEnum.cpp#L4063-L4073)）：

   ```cpp
   APInt v = scatterBits(PayloadTagBits.asAPInt(), tag);
   v |= scatterBits(~CommonSpareBits.asAPInt(), tagIndex);
   ```

   因为基底是零 `APInt`，**空 case 的每一个 payload 位都是固定的**——
   选中的 spare bits 携带 tag，occupied 位携带编号，其余位皆为零。

#### 2.6.3 工作示例：两个类引用 payload

```swift
final class Renderer { ... };  final class Compositor { ... }
enum Backend { case metal(Renderer); case software(Compositor); case headless; case disabled }
```

- CommonSpareBits = `0xF000_0000_0000_0007`（7 位；Swift 原生类引用）。
- Occupied 位 = 57 ≥ 32 → 所有空 case 共享一个 tag → numTags = 3。
- numTagBits = 2 → 从最高的 spare bits 选取：**bit 63 与 bit 62**。
- 编码（已实测——下面 byte 7 的值都是真实的）：

```
.metal(r)     tag 0 → bits{63,62} = 00 → byte 7 = 0x0?（高两位 00，其余为地址位）
.software(c)  tag 1 → bits{63,62} = 01 → byte 7 = 0x4?          （bit 62 置位）
.headless     tag 2，编号 0 → [00 00 00 00 00 00 00 80]         （bit 63 置位）
.disabled     tag 2，编号 1 → [08 00 00 00 00 00 00 80]         （编号 1 → 最低 occupied 位 = bit 3）
```

注意 `.disabled` 的编号落在 **bit 3**——最低的 *occupied* 位，因为 bit 0–2
是 spare。scatter 操作的寻址对象是掩码内部的位置，不是绝对位号。

#### 2.6.4 工作示例：亚字节级 spare bits

Spare bits 并不非要指针不可：

```swift
enum BoolPair { case a(Bool); case b(Bool); case e0 }
```

- 每个 `Bool` 占 bit 0；bit 1–7 是 spare → CommonSpareBits = `0b1111_1110`。
- Occupied 位 = 1 → 每个 tag 容纳 2 个空 case → 1 个空 tag；numTags = 3；
  numTagBits = 2。
- Tag 位：最高的两个 spare bits——**bit 7 与 bit 6**。
- 实测编码：

```
.a(false) = [00]   .a(true) = [01]     tag 0；bit 0 是活的 payload
.b(false) = [40]   .b(true) = [41]     tag 1（bit 6）
.e0       = [80]                       tag 2（bit 7），编号 0
```

这个例子说明为什么对 spare-bits 枚举做字节粒度的布局描述是错的：case `a`
的 byte 0 **并非**“恒为 `0x00`”——只有第 7–1 位固定，bit 0 属于 payload。
工具必须携带按位掩码（[第三部分 3.3](#33-spare-bits-布局的位级解剖)）。

#### 2.6.5 枚举自己的 extra inhabitants

未用的 tag 编码成为枚举自己的 XI——
`MultiPayloadEnumImplStrategy::getFixedExtraInhabitantCount`
（[`GenEnum.cpp:5843-5852`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/GenEnum.cpp#L5843-L5852)）：

```
totalTagBits = commonSpareBits + 额外 tag 位（向上取整到整字节）
XI = totalTagBits >= 32 ? MaxNumExtraInhabitants
                        : min(2^totalTagBits − numTags, MaxNumExtraInhabitants)
```

XI 取值在 tag 位上自全 1 *递减*（`GenEnum.cpp:5854-5900`）。`BoolPair`：
`2⁷ − 3 = 125` 个 XI——实测 `BoolPair?.none` = `[fe]`（七个 spare bits 全
置位，occupied 位不声明）。`Backend` 同样是 `2⁷ − 3 = 125`，所以
`Backend?` 仍是 8 字节。

### 2.7 Tagged 多 payload

payload 之间没有公共 spare bits——或布局必须能被运行时重现——时，tag 追加
在 payload 区之后。

#### 2.7.1 谁走这条路

1. **没有公共 spare bits。** 整数 payload 用满每一位。
2. **泛型枚举——永远如此。** 运行时用 `swift_initEnumMetadataMultiPayload`
   （[`Enum.cpp:384-443`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/Enum.cpp#L384-L443)）
   实例化泛型枚举的 metadata，而它对 spare bits 一无所知。IRGen 配合地对
   布局依赖泛型的 payload 清空 `CommonSpareBits`（`GenEnum.cpp:7189-7199`），
   保证编译期与运行时一致。实测代价：

   ```swift
   enum GenericPair<Element> { case a(Element); case b(Element) }
   // GenericPair<Renderer>: size = 9  （8 payload + 1 tag）
   // ……而等价的非泛型 TwoRefs 是 8（spare bits）。
   ```

3. **Resilient payload**（编译期布局未知），同理。

#### 2.7.2 布局

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

`swift_storeEnumTagMultiPayload`
（[`Enum.cpp:677-701`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/Enum.cpp#L677-L701)）：
payload case 在 tag 字节里存 case 编号，payload 区自由使用。空 case 在
tag 字节里存 `numPayloads + (emptyIndex >> payloadBits)`，并把
`emptyIndex` 的低位**零扩展写满整个 payload 区**——`storeMultiPayloadValue`
委托给 `storeEnumElement`
（[`EnumImpl.h:27-62`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/EnumImpl.h#L27-L62)），
其中 `memset(&dst[4], 0, size - 4)` 把存储字之后的一切清零。因此空 case 的
每个 payload 字节都是固定的——读取侧
（`swift_getEnumCaseMultiPayload`，`Enum.cpp:704-725`）会把它读回来参与
判别。

实测：

```swift
enum TwoU32 { case a(UInt32); case b(UInt32); case e0 }     // size 5
// .a(1000) = [e8 03 00 00 | 00]
// .b(0)    = [00 00 00 00 | 01]
// .e0      = [00 00 00 00 | 02]      整个 payload 区清零

enum GenericPairWithEmpty<Element> { case a(Element); case b(Element); case e0 }
// GenericPairWithEmpty<Renderer>.e0 = [00 ×8 | 02]         同一形态，size 9
```

#### 2.7.4 枚举自己的 extra inhabitants

即 tag 字节未用的值，**自顶向下**分配：XI 模式 `#i` 在 tag 字节里存 `~i`
（`storeMultiPayloadExtraInhabitantTag`，
[`Enum.cpp:649-655`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/Enum.cpp#L649-L655)）。
实测：`TwoU32?` 仍是 5 字节，且

```
TwoU32?.none = [00 00 00 00 | ff]     ← XI #0 = tag 字节 0xFF
```

### 2.8 `indirect` case 与其他特殊形态

**`indirect`** 在布局意义上把 payload 换成 `Builtin.NativeObject` 堆 box
指针（`GenEnum.cpp:6452-6461`）。因此 indirect 单 payload 枚举坐拥堆引用
饱和的 XI 库存——形态与 `Optional<某个类>` 完全一致：

```swift
indirect enum Tree { case node(Tree); case leaf; case sentinel }
// size = 8
// .leaf     = [00 00 00 00 00 00 00 00]    XI #0（空指针）
// .sentinel = [01 00 00 00 00 00 00 00]    XI #1
```

永远不会有 tag 字节——有二十多亿个 inhabitants 可花。（把解析不出的
indirect payload 当成“0 个 XI”、进而预测出溢出 tag 字节，正是本项目修过的
一个真实 bug；见[第三部分 3.7](#37-实现者的陷阱清单)。）

**单 case 枚举**（`SingletonEnumImplStrategy`）：布局与 payload 完全相同
（无 payload 则零大小）。**无值枚举**：size 0、XI 0。

### 2.9 字节序

所有 tag 值、空 case 编号与多字节固定模式在 Apple 平台上均以**小端序**存储
（`storeEnumElement` / `loadEnumElement` 处理了一般情形）。2 字节 tag 值
`0x0102` 在内存中是 `[02 01]`。

---

## 第三部分 —— 精通：源码中的机器

### 3.1 同一套 ABI，四处实现

上文的布局规则在 Swift 代码库里实现了**四遍**；弄清哪一份在何时运行，是
整个体系的总钥匙：

| 实现 | 位置 | 运行时机 | 能力范围 |
|---|---|---|---|
| IRGen | [`lib/IRGen/GenEnum.cpp`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/GenEnum.cpp) | 编译期 | 全部能力，含 spare bits |
| 运行时 metadata 初始化 | [`stdlib/public/runtime/Enum.cpp`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/Enum.cpp) | 泛型/resilient 枚举首次取 metadata 时 | **没有 spare bits**——只有 tagged |
| Value witnesses | 编译器生成，或 `EnumImpl.h` 模板 | 每次对 case 的运行时存取 | 该枚举自身的契约 |
| RemoteInspection | [`stdlib/public/RemoteInspection/TypeLowering.cpp`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/RemoteInspection/TypeLowering.cpp) | 离线，凭反射元数据 | spare bits 需要外援（见 3.5） |

它们之间的不对称之处正是这套 ABI 的锋利边缘：

- **运行时不会做 spare bits。** `swift_initEnumMetadataMultiPayload` 只会
  算 tagged 布局。因此凡是运行时可能要重现布局的场合，IRGen 都拒绝使用
  spare bits——这正是 `AllowFixedLayoutOptimizations` 挡板
  （`GenEnum.cpp:7189-7199`）的作用，也是所有泛型枚举都走 tagged 的原因。
- **单 payload 枚举从不暴露追加 tag 字节里的 XI。** 溢出之后额外 tag 字节
  明明还有未用的值，IRGen 却刻意不提供它们（`GenEnum.cpp:3445-3448` 与
  `7075-7078` 的 `FIXME`）——XI 个数*只*等于 payload 的余额。而 tagged 多
  payload 枚举**会**暴露未用的 tag 值。这就是 `Int??` 每层多一个字节、
  `TwoU32?` 却保持 5 字节的原因——凭直觉绝对猜不到的不对称。
- **RemoteInspection 对齐的是运行时，不是 IRGen。** 其
  `EnumTypeInfoBuilder::build`
  （[`TypeLowering.cpp:2028-2318`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/RemoteInspection/TypeLowering.cpp#L2028-L2318)）
  对无 payload / 单 payload 布局从头重推（`TypeLowering.cpp:2213-2214`
  甚至写着 “Below logic should match the runtime function
  swift_initEnumMetadataSinglePayload()”），但对 spare-bits 枚举必须读取
  编译器落盘的描述符（3.5）——spare bits 无法仅凭反射字段类型重建。

### 3.2 单 payload witness 的解剖

`getEnumTagSinglePayloadImpl`
（[`EnumImpl.h:102-139`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/EnumImpl.h#L102-L139)）
分三步读取 case，每一步都有可学之处：

```cpp
// 1. 若存在额外 tag 字节，其中的非零值立即定案：
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
// 3. 否则就是合法 payload。
return 0;
```

观察：

- **4 字节窗口。** 读溢出编号时 `loadEnumElement` 只取 payload 区的前 4
  字节——与写入侧的零扩展互为镜像。空 case 编号在这套 ABI 里处处是 32 位
  量。
- **XI 分发是函数指针。** 第 2 步委托给 *payload 类型自己的* XI 实现
  （`getExtraInhabitantTag`）。枚举层只知道个数。这层间接正是离线工具撞墙
  之处（3.4）——回调是代码，不是数据。
- **Tag 编号是层叠算术。** payload = 0，然后是按模式序的 XI case，然后是
  溢出 case。编译器、运行时、反射、本项目——每一份实现都必须与这套算术
  严格一致，否则布局会悄无声息地分叉。

### 3.3 Spare-bits 布局的位级解剖

scatter 操作是核心。`scatterBits(mask, value)` 把 `value` 的位自低向低沉积
进掩码的置位位置：

```
mask  = 0b1100_0000 （BoolPair 的两个 tag 位：7 和 6）
value = 0b10（tag 2）→ value 的 bit0 → bit 6（掩码内最低位）：0
                        value 的 bit1 → bit 7：1
结果  = 0b1000_0000 = 0x80          ← BoolPair.e0，已实测
```

三个后果值得强调：

**Payload case 的字节是部分固定的。** `BoolPair.a(…)` 的 byte 0 里，tag 位
（7、6 = `00`）加上*其余* spare bits（5–1，固定为零）是固定的，而 bit 0 是
活 payload。对该字节的正确断言是
`byte[0] & 0b1111_1110 == 0b0000_0000`——按位断言，不是按字节断言。凡是给
spare-bits 的 payload case 渲染整字节“固定字节”的工具，都会一边断言
`a(true) = [00]`，一边被内存里的 `[01]` 打脸。（本项目的渲染器曾存在恰好
这一类 bug，后来通过引入按字节的固定位掩码修复；第一部分 1.5 输出里的
`byte[0x0] & 0b00000111 = 0b00000000` 形式即由此而来。）

**空 case 是全固定的。** `getEmptyCasePayload` 从零 `APInt` 出发，向其中
OR 进两次 scatter（`GenEnum.cpp:4063-4073`）——因此空 case 的 payload 区
*每一位*都是模式的固定部分：选中的 spare bits = tag，occupied 位 = 编号，
其余位 = 0。只记录编号低几位的工具是对模式的不完整描述。

**空 case 按 tag 分组打包。** occupied 位不足 32 时，每个 tag 值携带
`2^occupiedBits` 个空 case（`GenEnum.cpp:4289-4310`），编号在每个 tag 内
重新从零起。`numTagBits == spareBitCount` 的边界要小心：“全部用上”分支
（`GenEnum.cpp:7257`，`numTagBits >= commonSpareBitCount`）与“从最高位选取”
分支恰在此汇合，且二者产出相同的选择——这里差一位，所有 tag 位都会静默
偏移。

**XI 取值在 tag 位上自全 1 递减**，并经过旋转使已用 tag 值与 inhabitants
干净分离（`getFixedExtraInhabitantValue`，`GenEnum.cpp:5854-5900`）。所以
`BoolPair?.none = [fe]`：spare bits 全置位，payload 位不声明。

### 3.4 为什么 XI 的*模式*无法从个数推出

离线工具的高频陷阱：value witness table 只公布 XI 的**个数**；**模式**是
各类型的私有约定：

| 类型 | XI 模式约定 |
|---|---|
| 堆引用 | 递增的无效地址：`0x0`、`0x1`、`0x2`…… |
| `Bool` | `2`、`3`、`4`…… |
| `String` | 预留的 `_StringObject` 判别态——实测：带 2 个空 case 时，`e0` = 全零，`e1` = 第二个字 = `0x1` |
| Tagged 多 payload | tag 字节自全 1 递减：`0xFF`、`0xFE`…… |
| Spare-bits 多 payload | tag 位模式自全 1 递减 |
| 无 payload 枚举 | 自 `caseCount` 递增的值 |
| 单 payload 枚举 | payload 的模式序列，跳过已消耗的个数 |
| 结构体/元组 | *XI 最多的那一个字段*的模式（见 `findXIElement`，[`Enum.cpp:199-222`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/Enum.cpp#L199-L222)） |

模式是**递归复合**的：`Optional<Optional<Bool>>.none` 是 Bool 模式 `#1`
（= `3`），因为内层 Optional 消耗了 `#0`。只凭个数的公式生产不出这些字节
——你要么持有各类型的具体约定（硬编码模型），要么持有活的 witness 代码。

这不是假想问题：真实二进制的 dump 里满是空 case 模式为 `String` 判别态或
嵌套枚举编码的单 payload 枚举。凡是从个数*编造*模式的工具，都会打印出貌似
可信、实则错误的字节。诚实的选项只有本项目实现的那两条（3.6）：运行
witness（精确），或明说“离线未解析”（诚实降级）。

### 3.5 `__swift5_mpenum` 描述符

Spare bits 只存在于编译器的脑海里，反射需要一份书面记录。编译器为每个固定
布局的多 payload 枚举向二进制的 `__swift5_mpenum` 段落盘一个
`MultiPayloadEnumDescriptor`
（[`include/swift/RemoteInspection/Records.h:381-484`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/RemoteInspection/Records.h#L381-L484)）：

```
TypeName            （指向 mangled 名的相对指针）
SizeFlags           （高 16 位：内容大小，单位 32 位字；最低位：是否用 spare bits）
[ByteOffset|Count]  （掩码字节窗口在 payload 区内的位置）
[PayloadSpareBits]  （公共 spare-bit 掩码本体，按字节窗口存储）
```

`EnumTypeInfoBuilder` 在 `TypeLowering.cpp:2242-2317` 消费它：有描述符
（外加提供权威 size/XI 的 builtin type descriptor）时，再按 case 与
spare-bit 掩码求交，构建 `MultiPayloadEnumTypeInfo`；没有描述符——或存在
任何泛型 payload——就直接退回 tagged 公式（`TypeLowering.cpp:2243-2279`）。
这是离线反射了解 spare bits 的*唯一*渠道；剥掉这个段，所有 spare-bits
枚举都会降级。

### 3.6 MachOSwiftSection 如何计算枚举布局

本项目把这套 ABI 实现了两遍，对应两种信任模型。

#### 运行时路径——构造上精确

用于枚举 metadata 已加载进本进程的场合（`MachOImage`）。流水线（在
`RuntimeFieldLayoutBackend` + `SwiftInspection` 中）：

1. **公式先行。** `EnumLayoutCalculator`
   （`Sources/SwiftInspection/EnumLayoutCalculator.swift`）是第二部分算法
   的逐行审计移植——`calculateSinglePayload`、`calculateMultiPayload`
   （spare bits，掩码来自 `__swift5_mpenum`）、
   `calculateTaggedMultiPayload`。它产出每个 case 的投影，含按字节的
   **固定位掩码**（3.3）与按策略的 XI 个数（2.6.5、2.7.4）。
2. **Payload 的 XI 取自真实 VWT。** payload 的 XI 个数从其活的 value
   witness table 读取。`indirect` payload 特判为堆对象个数
   `0x7FFF_FFFF`（2.5.2）。payload 类型解析不出时，从枚举自身的 VWT
   *反推*：payload-sized 布局下 `payloadXI = enumXI + emptyCases` 是运行
   时减法的精确逆运算（2.5.1）；溢出布局不可逆，于是宁可放弃布局也不猜。
3. **精确模式来自 witness 本体。** `RuntimeEnumCaseProjector`
   （`Sources/SwiftInspection/RuntimeEnumCaseProjector.swift`）通过*运行*
   枚举自己的 `destructiveInjectEnumTag` witness 来解析 XI 模式（3.4）：
   每个 case 注入两次——一次进全 `0x00` 缓冲区、一次进全 `0xFF`——两次
   结果一致的字节即被确定性写入的字节。空 case 还必须经 `getEnumTag`
   往返校验，否则整个投影被拒绝。（双基线技巧之所以成立，正因为单
   payload 注入是*覆盖写*模式；spare-bits 注入是 OR，故该策略的模式改从
   掩码取得。）
4. **对照 ground truth 交叉校验。** 组装出的布局，其推算总大小必须等于
   枚举 VWT 的 size，否则整个布局被丢弃——派生输入（payload 大小、spare
   掩码）可能出错，而一个自信的错误答案比没有答案更糟。

#### 静态路径——离线，对极限诚实

用于 `MachOFile`（无进程）。`EnumLayoutBridge`
（`Sources/SwiftLayout/EnumLayoutBridge.swift`）按序解析：

1. **优先取编译器自己的答案**：`__swift5_builtin` 整型布局描述符
   （IRGen 算出的 size/stride/alignment/XI 原文照录）——与
   RemoteInspection 信任同一来源。
2. **否则结构化计算**：payload 类型经镜像依赖闭包递归解析，
   `__swift5_mpenum` 掩码喂给 `calculateMultiPayload`，并且——比官方离线
   实现更进一步——**spare-bits 的 XI 个数也结构化推导**
   （`TypeLowering.cpp` 从不这样做；没有 builtin 描述符时它直接退回
   tagged XI）。
3. **泛型枚举一律走 tagged 分支**——无论是否实例化——与运行时对齐
   （2.7.1）。
4. **对模式诚实降级**：单 payload 空 case 的具体 XI 字节若需要执行
   witness 才能得到，就渲染为
   “stored as the payload's extra-inhabitant pattern #N” 并显式标注
   *离线未解析*——绝不编造字节（3.4）。

### 3.7 实现者的陷阱清单

以下条目提炼自本项目对照上述源码的逐行审计——每一条要么是这里真实修过的
bug，要么是源码自己的警示：

1. **indirect 单 payload 枚举是 XI 布局，不是溢出布局。** payload 是坐拥
   `0x7FFF_FFFF` 个 inhabitants 的 box 指针。从“payload 类型解析不出”推出
   “0 个 XI”，会产出越界的 tag 区域和自相矛盾的 dump（2.8）。
2. **空 case 固定的是*整个* payload 区。** tagged：零扩展
   （`storeEnumElement` 的 `memset`）；spare-bits：零 `APInt` scatter。
   只记录 `ceil(log2(N))` 位会诱导“其余字节任意”的误读（2.6.2、2.7.3）。
3. **spare-bits 的 payload case 必须按位描述，不能按字节。** 同一个字节
   可以同时容纳 tag 位与活 payload 位（`BoolPair`，3.3）。
4. **饱和上限出现两次。** 堆引用 XI 在 `INT_MAX` 处饱和
   （`Metadata.h:925`），且每个策略的 XI 公式都封顶于
   `MaxNumExtraInhabitants`（`MetadataValues.h:183`）。近似其中任何一个
   （硬编码 4096、不封顶的 `1 << bits`）都会把真实枚举算错大小。
5. **小 payload 阈值是 4 字节，不是指针宽度**——在 `getEnumTagCounts`
   里、在溢出因式分解里、在运行时的读取窗口里都是（2.3、3.2）。
6. **派生布局要对照 VWT 交叉校验。** payload 大小与 spare 掩码都是*派生*
   输入；输入一错，公式会兴高采烈地产出错误布局。
   `impliedTotalSize == vwt.size` 能拦下一整类静默错误（3.6）。
7. **XI 消耗有序且分层。** 空 case 按声明顺序消耗模式；外层包装从内层停下
   的地方继续消耗（`ThreeBools?.none = [04]`，2.5.2）。这里差一，所有嵌套
   模式全体偏移。
8. **Case 编号是 payload-cases-first**——field records 里、`getEnumTag`
   里、所有公式里皆然。还要记住编号前的重分类：零大小 payload → 空 case；
   unavailable case → 空 case（2.1）。
9. **不要指望单 payload 的 tag 字节产出 XI。** 3.1 的不对称（`Int??` 变大
   而 `TwoU32?` 不变）是刻意的、带 `FIXME` 注释的行为——按原样建模。

### 3.8 源码地图

全部引用汇总一表（标签 `swift-6.3.3-RELEASE`）：

| 文件 | 角色 | 关键符号 |
|---|---|---|
| [`include/swift/ABI/Enum.h`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/ABI/Enum.h) | 公共 tag 计数公式 | `getEnumTagCounts` (28) |
| [`stdlib/public/runtime/EnumImpl.h`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/EnumImpl.h) | 单 payload 存取模板 | `storeEnumElement` (27)、`getEnumTagSinglePayloadImpl` (102)、`storeEnumTagSinglePayloadImpl` (141) |
| [`stdlib/public/runtime/Enum.cpp`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/runtime/Enum.cpp) | 运行时 metadata 初始化 + 多 payload witnesses | `swift_initEnumMetadataSinglePayload` (126)、`swift_initEnumMetadataMultiPayload` (384)、`swift_storeEnumTagMultiPayload` (677) |
| [`lib/IRGen/GenEnum.cpp`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/GenEnum.cpp) | 编译期布局 | `EnumImplStrategy::get` (6394)、单 payload `completeFixedLayout` (7029)、多 payload `completeFixedLayout` (7152)、`getEmptyCasePayload` (4063)、各 XI 计数 (1228、3457、5843) |
| [`lib/IRGen/ExtraInhabitants.cpp`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/lib/IRGen/ExtraInhabitants.cpp) | 指针 XI | `PointerInfo::getExtraInhabitantCount` (50) |
| [`include/swift/Runtime/Metadata.h`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/Runtime/Metadata.h) | 堆对象 XI 个数 | `swift_getHeapObjectExtraInhabitantCount` (925) |
| [`include/swift/ABI/MetadataValues.h`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/ABI/MetadataValues.h) | XI 上限 | `MaxNumExtraInhabitants` (183) |
| [`stdlib/public/SwiftShims/swift/shims/System.h`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/SwiftShims/swift/shims/System.h) | 各平台指针 ABI | `LEAST_VALID_POINTER` (153)、arm64 spare-bit 掩码 (166-171) |
| [`stdlib/public/RemoteInspection/TypeLowering.cpp`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/RemoteInspection/TypeLowering.cpp) | 官方离线实现 | `EnumTypeInfoBuilder::build` (2028)、各 `*EnumTypeInfo` 类 (613-1150) |
| [`include/swift/RemoteInspection/Records.h`](https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/include/swift/RemoteInspection/Records.h) | spare bits 的书面记录 | `MultiPayloadEnumDescriptor` (381) |

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

`swift-section dump --emit-enum-layout`（及库内渲染器）输出的注释由 token
模板 `Transformer.SwiftEnumLayout`（`SemanticTransformer` 模块）驱动。三层
模板对应注释结构——类型级策略行、逐 case 块、逐固定字节行——以
`${token}` 占位（与 RuntimeViewerCore 的 transformer UI 同名）。内置四种
预设，CLI 通过 `--enum-layout-style` 选择：

| 预设 | 逐字节行 | 风格 |
|---|---|---|
| `detailed`（默认） | 有 | 完整内置渲染；部分固定字节用二进制掩码（`fixed bits 0b11110000 = 0b01000000`） |
| `explained` | 有 | 信息相同，但部分固定字节改为位段叙述：`bits 7-4 are always 0100; the other bits (3-0) hold payload data` |
| `standard` | 无 | Case 标题 + 编码语句 + 一行固定字节摘要 |
| `compact` | 无 | 每个 case 一行：`` [0x01] `caseName` — payload case, tag 1 `` |

库用户在 `DeclarationRenderConfiguration` 或
`SwiftDeclarationPrintConfiguration` 上调用 `applyTransformers(_:)`，传入
`swiftEnumLayout` 为预设（`Transformer.SwiftEnumLayout.Preset`）或自定义
模块的 `Transformer.SwiftConfiguration`；同一机制也覆盖 field-offset /
type-layout / member-address / vtable-offset 注释模板。`detailed` 预设经
单元测试保证与内置默认渲染完全一致，默认输出永不漂移。
