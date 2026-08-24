# 不透明返回类型解析专题：从二进制编码到归属裁决与调试方法

> 本文是领域知识文档：讲清 opaque 返回类型（`some P`）在 Mach-O 里如何编码、协议 /
> 关联类型 / 约束与它的关系、`Swift.Equatable<[A]>` 这个真实 bug 的完整成因与修复思路，
> 以及排查这类问题的可操作调试方法。
>
> 相关文档分工：[提案 0011](../Evolutions/0011-opaque-primary-associated-type-attribution.md)
> 是决策记录（为什么做、放弃了什么）；
> [OpaquePrimaryAssociatedTypeAttribution.md](OpaquePrimaryAssociatedTypeAttribution.md)
> 是实现说明（最终代码结构、与提案的差异）。本文不重复它们，聚焦原理与方法。
> 文中所有字节级素材取自 fixture `SymbolTestsCore` 的真实取证（2026-08-24 会话）。

---

## 1. `some P` 在二进制里长什么样

源码里的一个 opaque 返回类型，编译后拆成三样东西：

1. **函数符号里的占位**：mangled 符号中 opaque 返回值只是 `Qr`（单个）/ `QR`、`QR_`、`QR0_`
   （多个）这样的占位标记——符号本身**不含**任何约束信息。这就是 interface 输出里裸
   `some` 的来源：只 demangle 函数符号，最多知道「这里有一个 opaque 类型」。
2. **opaque type descriptor**：符号后缀 `QOMQ`（"opaque type descriptor for ..."），
   一个独立的 context descriptor，**约束信息全在这里**。这是本文的主角。
3. **underlying type arguments**：descriptor 尾部的 mangled name 指针列表，记录每个
   opaque 参数的真实底层类型与 witness tables——运行时凭它实例化，逆向时凭它可以
   「揭开」opaque（那是另一个话题，本文只管把 `some` 的**约束**还原成源码形态）。

### 1.1 descriptor 布局（以 `functionNested` 为实例）

fixture 源码：

```swift
public func functionNested<A: Protocols.ProtocolTest & Equatable, B: Protocols.ProtocolTest & Equatable>(_: A, _: B)
    -> (some Sequence<[A]> & Equatable,
        (some Protocols.ProtocolTest<A>)?,
        some Collection<[A]> & Protocols.TestCollection<[A]> & Equatable)?
    where A.Body == Generics.GenericRequirementTest<B>, A.Body.Body.Body == B
```

找到并 dump 它的 descriptor（§5 有完整命令），文件偏移 `0x42fa8` 起：

```
c4 00 09 00   flags:      kind=4 (OpaqueType), 0x80 generic, 0x40 unique,
                          kindSpecificFlags=0x0009 → 9 个 underlying type arguments
                          （3 个 metadata + 6 个 witness table，见 §2.1 末尾）
ac ff ff ff   parent:     相对指针 → 所属 anonymous context（函数）
05 00         NumParams = 5
0d 00         NumRequirements = 13
0d 00         NumKeyArguments = 13
00 00         NumExtraArguments = 0
80 80 80 80 80 00 00 00   5 个 GenericParamDescriptor（0x80 = type + key），补齐 4 字节
（此后是 13 × 12 字节的 requirement 三元组，再往后是 9 个 underlying arg 相对指针）
```

**5 个泛型参数是谁**：opaque 的泛型上下文是「外层函数签名 + opaque 自身参数」的拼接。
depth 0 是函数的 `<A, B>`（`τ_0_0`、`τ_0_1`），depth 1 是三个 opaque 位置各一个参数
（`τ_1_0`、`τ_1_1`、`τ_1_2`）。**每写一个 `some`，depth 1 就多一个参数**——元组里三个
`some` 就是三个参数，这是把约束对号入座的坐标系。

### 1.2 requirement 三元组

每条 generic requirement 是 12 字节 `{flags: u32, param: relptr, content: u32}`：

- `flags` 低 5 位是 kind：`0` = protocol（conformance 约束），`1` = sameType，
  `2` = baseClass，`0x1F` = layout；`0x80` 位 = 该约束需要 key argument（PWT 槽位）。
- `param` 相对指针指向 **subject 的 mangled 字符串**（约束的左边是谁）。
- `content` 按 kind 解释：protocol 约束是（可间接的）协议 descriptor 指针——外部协议
  经 GOT/bind；sameType 约束是右侧类型的 mangled 字符串指针。

`functionNested` 的 13 条实测解析结果（这张表是理解一切的钥匙）：

| # | kind | subject（mangled → 语义） | content |
|---|------|--------------------------|---------|
| 0 | protocol | `x` → `A` | → Equatable |
| 1 | sameType | `x` → `A` | `4Body␂<ref>Qyd_0_` → `τ_1_1.[ProtocolTest]Body`（**反向 pin**，见 §2.3） |
| 2 | protocol | `q_` → `B` | → Equatable |
| 3 | sameType | `q_` → `B` | `4Body␂<ref>Qy_` → `B.Body`（外层 where 规约产物） |
| 4 | sameType | `4Body␂<ref>Qz` → `A.Body` | `␂<ref>y_q_G` → `GenericRequirementTest<B>` |
| 5 | protocol | `qd__` → `τ_1_0` | → Equatable |
| 6 | protocol | `qd__` → `τ_1_0` | → Sequence |
| 7 | protocol | `qd_0_` → `τ_1_1` | → ProtocolTest |
| 8 | protocol | `qd_1_` → `τ_1_2` | → Collection |
| 9 | protocol | `qd_1_` → `τ_1_2` | → TestCollection |
| 10 | protocol | `qd_1_` → `τ_1_2` | → Equatable |
| 11 | sameType | `7ElementSTQyd__` → `τ_1_0.[Swift.Sequence]Element` | `SayxG` → `[A]` |
| 12 | sameType | `7ElementSTQyd_1_` → `τ_1_2.[Swift.Sequence]Element` | `SayxG` → `[A]` |

subject 里的参数编码（读 mangled 字符串必背）：

| mangling | 参数 | 备注 |
|---|---|---|
| `x` | `τ_0_0` | depth 0, index 0 |
| `q_` | `τ_0_1` | depth 0, index 1 |
| `qd__` | `τ_1_0` | `d` 进一层 depth |
| `qd_0_` | `τ_1_1` | |
| `qd_1_` | `τ_1_2` | |
| `Qz` / `Qy_` / `Qyd__` … | dependent member 的 base 简写 | `Qz` base 即 `x`；`Qy` 后缀同上表去掉 `q` |

symbolic reference：字符串里的 `\x01`（直接）/ `\x02`（间接）+ 4 字节相对偏移，指向
descriptor（或其 GOT 槽）。本模块协议（ProtocolTest）走 `\x02<ref>`；stdlib 协议直接用
标准替换字母（`ST` = Sequence，`Sl`/`Sk` 集合系，`SQ` = Equatable…）。

---

## 2. 协议、关联类型、约束与 opaque 的关系

### 2.1 sugar 的脱糖：尖括号是怎么变成 same-type 约束的

源码 `some Sequence<[A]> & Equatable` 里没有「参数化协议」这种运行时实体。primary
associated type 的尖括号纯粹是语法糖，脱糖成两类 requirement：

```
some Sequence<[A]> & Equatable
   ⇒ τ_1_0: Sequence          （protocol requirement，表中 #6）
   ⇒ τ_1_0: Equatable         （protocol requirement，表中 #5）
   ⇒ τ_1_0.[Sequence]Element == [A]   （sameType requirement，表中 #11）
```

要点：**尖括号参数挂在哪个协议上，二进制里没有直接记录**——只有「某参数的某关联类型
== 某类型」这条约束。把它还原回 `Sequence<[A]>` 而不是 `Equatable<[A]>`，是**解析端的
推断责任**。这就是一切问题的出发点。

（顺带解释 kindSpecificFlags 的 9：underlying type arguments = 3 个 opaque 参数的
metadata + 每条带 key bit 的 protocol requirement 一张 witness table，2+1+3 = 6，共 9。）

### 2.2 anchor：关联类型天生带着「声明协议」

subject `7ElementSTQyd__` 拆开是：`7Element`（长度前缀标识符）+ `ST`（**Swift.Sequence**）
+ `Qyd__`（`τ_1_0` 的 dependent member）。也就是说 mangling 层面关联类型是**限定形式**
`τ_1_0.[Swift.Sequence]Element`——带着声明它的协议。我们把这个协议叫 **anchor**。

demangler 完整保留它：`dependentAssociatedTypeRef` 节点有两个 child
`[Identifier("Element"), Type(Protocol(Swift.Sequence))]`（无限定形式只有一个 child，
但 requirement subject 实际都是限定的）。

anchor 的两个关键脾气：

1. **anchor 是「原始声明者」，不是你 sugar 里写的那个协议。** `Collection<[A]>` 的约束
   （表中 #12）anchor 是 **Sequence**——因为 `Collection.Element` 继承自
   `Sequence.Element`，Requirement Machine 规范化时把关联类型锚到继承链最上层的声明者。
   于是出现「anchor 不在组合成员里」的局面：组合是 {Collection, TestCollection,
   Equatable}，anchor 却是 Sequence。要把 `<[A]>` 挂回 Collection，必须知道
   **Collection refines Sequence**——这条事实在 libswiftCore 的 Collection protocol
   descriptor（requirement signature）里，本二进制没有。这是「要追 libswiftCore」的
   真实含义（旧记忆把它误记成「anchor 不在」）。
2. **等价类塌缩会吃掉约束。** 源码明明写了两处 sugar（`Collection<[A]>` 和
   `TestCollection<[A]>`，TestCollection 是独立协议、自声明 Element），descriptor 里
   τ_1_2 却只有 #12 一条 same-type。两个关联类型 pin 到同一具体类型后进了同一等价类，
   最小化签名只留 canonical anchor 一条。`TestCollection` 的 pin **物理上消失了**，
   只能靠「TestCollection 自己声明了名为 Element 的关联类型」按名字推断回来。

### 2.3 反向 pin：`some ProtocolTest<A>` 的编码长相

第二个 opaque 的约束（表中 #1）是 `x == τ_1_1.[ProtocolTest]Body`——**外层参数在左、
opaque 的 dependent member 在右**。这是 `some ProtocolTest<A>` 脱糖后
`τ_1_1.Body == A` 的规范化形态（哪边当 subject 由 canonical ordering 决定）。解析时要
识别这个方向：约束真正「属于」右边的 τ_1_1，尖括号参数是左边的 `A`（provider 里经
`SubstitutionMap.rootOriginal` 还原，因为可能有链式替换）。

### 2.4 primary 与否，运行时不知道

SE-0346 的 primary associated types **不产生任何运行时元数据**：protocol descriptor 有
`AssociatedTypeNames`（全部关联类型名，声明顺序）和 requirement signature（refine 关系），
但**没有 primary 标记**——libswiftCore 里也没有。能安全推断的原因只有一个：opaque 类型
在源码层**写不了 where 子句**，它参数上的 same-type 约束只可能来自 primary sugar。这个
前提在别的场景（比如泛型函数签名的还原）不成立，不要把这套推断搬过去。

多 primary 的**顺序**（`AsyncSequence<Element, Failure>`）同理无处可查，
`BuiltinStandardLibraryProtocolFacts` 内置表是唯一来源。

### 2.5 组合顺序也是 canonical 的

descriptor 里协议 requirement 的顺序（#5 Equatable、#6 Sequence）是 canonical 排序，
不是源码顺序（源码是 `Sequence<[A]> & Equatable`）。输出 `Equatable & Sequence<[A]>`
不是 bug，源码顺序**不可恢复**，别试图修。

---

## 3. 案例：`Swift.Equatable<[A]>` 是怎么发生的

### 3.1 症状与根因

修复前输出：

```swift
-> (some Swift.Equatable<[A]> & Swift.Sequence<[A]>, ...,
    some Swift.Collection<[A]> & Swift.Equatable<[A]> & ...TestCollection<[A]>)?
```

`Equatable` 连关联类型都没有，`Equatable<[A]>` 是非法 Swift。根因在
`SwiftInterfaceBuilderOpaqueTypeProvider` 的收集阶段：same-type 约束只按**泛型参数**
分组（key 是 `τ_1_0` 的打印名），subject 里的关联类型名和 anchor 协议**整个扔掉**，
渲染时把该参数攒下的尖括号参数列表**无差别发给参数上的每一个协议**。于是 τ_1_0 的
`[A]` 同时挂上了 Sequence 和 Equatable。

第三个 opaque 的 `Collection<[A]>` 和 `TestCollection<[A]>` 修复前看着是对的——那是
无差别分发的「碰巧对」：三个协议都拿到了 `[A]`，恰好其中两个该拿。

### 3.2 为什么会犯这个错（认知复盘）

这个错值得复盘，因为它的每一环都很典型：

1. **单协议场景先做出来，分组粒度就停在了参数级。** `some Sequence<A>`、
   `some ProtocolTest<A>` 这类单协议 opaque 是最初的目标场景——单协议时「按参数分组」
   和「按协议归属」结果完全一样，错误结构不可见。组合场景后来加进 fixture 时，错误
   已经披着「大部分输出正确」的外衣。
2. **anchor 信息在别处被当噪声删掉，强化了「它没用」的印象。**
   `SwiftDeclarationRendering/Extensions/OpaqueType+.swift` 的 requirement 过滤器专门把
   `dependentAssociatedTypeRef` 的协议 child **移除**再和函数符号签名比对——那个场景要的
   是「等价性」（符号侧签名是无限定形式），删协议 child 是对的。但它留下了一个危险的
   心智暗示：这个 child 是需要抹平的编码差异，而不是有用信号。
3. **记忆偏差把问题记成了「无解」。**「信息不够，必须追到 libswiftCore」——取证后发现
   这句话只对一半（refine 关系确实在外面），anchor 身份本身一直都在二进制里。一个被
   记成「要跨镜像才能解决」的问题，自然被搁置成「已知限制」。**教训：把「哪一部分信息
   缺失」精确写下来，不要笼统记「信息不够」。**
4. **弱断言让错误输出变成了「预期」。** E2E 只有
   `#expect(output.contains("some Swift.Sequence") || ...)` 这种 contains 断言，注释里
   甚至照抄了错误输出（`// has composition: some Swift.Equatable<[A]> & ...`）当场景
   描述。测试从没红过，注释反过来成了错误的背书。**教训：快照/精确串断言对「输出形态」
   类功能是必需的，contains 只配当冒烟。**

### 3.3 怎么解决的（摘要）

完整方案见提案 0011 与实现说明，这里只给推断链的骨架：

```
对参数 τ 的每个协议 P、每条约束 c（关联类型名 N、anchor A、右侧 X）：
1. A == P                    → 挂。纯身份比对，离线 bind 符号也能判。
2. A ∈ P 的 refine 闭包      → 挂。闭包沿「descriptor 可达就读、否则查内置表」逐环展开；
                               读不到的环节标记 incomplete（命中是充分的，未命中不能下结论）。
3. 名字兜底                  → 仅当 P 无任何 anchor 命中、P 自声明了名为 N 的关联类型、
                               候选恰一条、且 A 不在组合成员内。恢复被塌缩的
                               TestCollection<[A]>；anchor 在组合内时禁用——因为
                               「塌缩」与「根本没 pin」在 descriptor 里逐字节同形，
                               挂了就是捏造。
4. 其余                      → 不挂。宁缺毋滥：错挂产生非法/误导代码，漏挂只是信息
                               丢失的诚实呈现。
```

信息来源三层：本模块 descriptor → 内置 stdlib 表（primary 名单/顺序的唯一来源）→
进程内跨镜像（MachOImage 的间接指针直接解引用到别的镜像，`SymbolOrElement.resolve`
只在 MachOFile 分支查 bind，所以进程内跨镜像**零额外代码**）。离线 + 非 stdlib 外部
协议的 refine 事实拿不到 → 降级不挂，两种 reader 输出深度允许不同。

---

## 4. 怎么调试这类问题

原则：**别从代码猜，从字节读。** opaque 解析的 bug 几乎都是「二进制里明明有/没有 X」
与「代码以为没有/有 X」的错位，一次字节级取证能终结所有争论。

### 4.1 第一步：拿到 descriptor

```bash
# 1. 找 opaque type descriptor 符号（后缀 QOMQ）
nm <binary> | grep "QOMQ"
# → 0000000000042fa8 S _$s...functionNested...lFQOMQ

# 2. 地址换文件偏移：看 __TEXT 段基址（dylib 通常 vmaddr=0，偏移=地址）
otool -l <binary> | grep -B1 -A4 "segname __TEXT$"

# 3. dump
xxd -s $((0x42fa8)) -l 288 <binary>
```

### 4.2 第二步：手工解析（对着 §1.1/§1.2 的布局）

- flags 低 5 位 `== 4` 确认是 opaque descriptor；
- header 的 NumParams / NumRequirements 定位 requirement 数组（param 区补齐到 4 字节）；
- 逐条 12 字节拆 `{flags, param, content}`，**相对指针 = 字段自身的文件偏移 + 有符号值**；
- 数一下每个参数有几条 protocol / sameType，先和源码对总账（对不上就是这里出问题）。

### 4.3 第三步：读 mangled 字符串

`xxd` dump 每个 subject / content 字符串，对照 §1.2 的参数编码表读。经验：

- `swift demangle` **吃不了**这些字符串——它们是 type-mangling 片段（无 `$s` 前缀）且常
  内嵌 symbolic reference 控制字节。要么手读（片段都很短），要么走项目内路径：
  `MetadataReader.buildGenericSignature(for:in:)` 返回 Node，`node.print(using:)` 看结果。
- 完整符号（如 `...QOMQ` 本身、bind 符号 `$sSTMp`）可以直接 `swift demangle`。
- 认不出的标准替换查 demangler 源码（sibling `swift-demangling` 的
  `Demangler.swift`）或 Swift 源码树 `docs/ABI/Mangling.rst`。

### 4.4 第四步：核对 demangler 节点结构

代码层的错位往往在「节点树长什么样」上。快速核对手段：

- 找现成消费者当参照——本案里 `OpaqueType+.swift` 对 `dependentAssociatedTypeRef`
  child 1 的删除操作，就是「协议 child 存在于节点树」的现成证据；
- 拿不准就在 demangler 源码里搜 `createNode(kind: .dependentAssociatedTypeRef`，
  构造点五分钟内能找全。

### 4.5 第五步：快速迭代回路

改一行看一次全量输出，别靠跑测试套件迭代：

```bash
# fixture 变了先重建（DerivedData 是 per-checkout 的 gitignored 产物）
xcodebuild -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj \
  -scheme SymbolTestsCore -configuration Release build \
  -derivedDataPath Tests/Projects/SymbolTests/DerivedData/SymbolTests 2>&1 | xcsift

# CLI 直出 + grep，秒级看到指定函数的 opaque 输出
swift run --scratch-path <scratch> swift-section interface --parse-opaque-return-type \
  Tests/Projects/SymbolTests/DerivedData/.../SymbolTestsCore.framework/SymbolTestsCore \
  2>/dev/null | grep "functionNested"
```

注意 `--parse-opaque-return-type` 不开就是裸 `some`——CLI 默认不挂 opaque provider，
别把这当成回归（interfaceSnapshot 同理，它锁的是不挂 provider 的输出）。

### 4.6 第六步：对照权威来源

- **编译器/运行时行为**（约束怎么最小化、什么会塌缩、descriptor 怎么 emit）：本机
  Swift 源码树 `/Volumes/SwiftProjects/swift-project/swift`（`swift-6.3.2-RELEASE`）。
  关键位置：`lib/AST/RequirementMachine/`（最小化与 canonical anchor）、
  `lib/IRGen/GenReflection.cpp`（requirement 编码）、`include/swift/ABI/Metadata.h`
  （descriptor 布局）、`docs/ABI/Mangling.rst`。
- **stdlib 协议的 primary / refine 事实**：源码树 `stdlib/public/core/*.swift` grep
  `^public protocol \w+<`，或 SDK 的 `Swift.swiftmodule/*.swiftinterface`。注意
  Concurrency 协议 mangle 在 `Swift` 模块名下（`$sSciMp` → `Swift.AsyncSequence`），
  内置表 key 一律 `Swift.` 前缀。
- **对拍**：怀疑运行时语义时，写十行 probe 程序把真类型 `dlopen`/实例化对拍，比读
  三小时代码可靠。

### 4.7 陷阱清单

- **「测试绿」≠「行为对」**：本案的错误输出在弱 contains 断言下绿了很久。判断测试
  成败一律看 `swift test` 退出码，xcsift 的测试摘要不可信（全局 CLAUDE.md 有完整
  实测记录）；断言强度对输出形态类功能必须到精确串/快照级。
- **fixture 二进制陈旧**：snapshot 掉了整段类型、没有 Error 行 → 先怀疑 fixture 二进制
  比 fixture 源码旧（AGENTS.md「环境漂移检查」第 1 条），重建再说。
- **snapshot 首录必红**：swift-snapshot-testing `record: .missing` 模式下删掉旧文件重录，
  第一跑 fail 是录制成功的正常信号，第二跑才是验证。
- **canonical ≠ 源码**：组合顺序、anchor 归属、requirement 顺序都是规范化产物。拿输出
  和源码逐字比对前，先想清楚哪些差异是 canonical 化的合法结果。
- **descriptor 同形不可强分**：塌缩 pin 与未 pin 同形（§2.2/§3.3）是这个领域的硬边界。
  遇到「两种源码编译出相同字节」的情形，解析端只能选边并记录，不要发明启发式硬分。
