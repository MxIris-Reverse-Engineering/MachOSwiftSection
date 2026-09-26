# 嵌套字段值大小 review findings（commit `ffbcf5964`，2026-09-24）

`/code-review xhigh` 对 commit `ffbcf5964`（`feature(layout): expose proven nested field extents`，分支 `feature/nested-coordinate-fields`，经 `0748b372` 合入 `next`）提出 11 条发现，已按四问（复现 / 基线对比 / 值不值得修 / 既往修复）逐条裁决：**真缺陷 2 条（都是基线既有）、文档缺陷 3 处、误报或不修 7 条**。发现 3 拆成两半：文档注释部分归入文档缺陷，其余部分登记为不修。

本表是原始清单与处置状态。「不修 / 误报」的终审条目收录进 [ReviewAdjudications.md](../Documentations/Internal/ReviewAdjudications.md)（A40–A46）。

**当前状态：只落记录，代码未改。** 用户裁定先把审查结论记下来、暂不修复（2026-09-24）。

审查对象：`git show ffbcf5964`。`NestedFieldOffset` 新增 `byteWidth`（字段的值大小，不含尾部对齐填充），结构体展开从 `resolver.computeStructLayout` 改走带 C 结构体 builtin record 校验的 `StaticLayoutCalculator.fieldLayout(ofStruct:)`，另有新测试 `NestedFieldExtentTests` 与三处文档。

**总体结论**：改动方向正确。新增的 `NestedFieldExtentTests` 8 项与既有的 `RecursiveNestedFieldOffsetTreeTests` 4 项在 `next`（`0748b372`）上全部通过，原始退出码 0。两个真缺陷都不是本次引入的，但本次新增的 `byteWidth` 把它们算错的大小也标成了「已证明」，经 swift-decompiler 的嵌套字段命名流到下游。

下文行号按 `next`（`5cbf0378`）；审查对象 `ffbcf5964` 上的行号不同。

## 复现环境

发现 1、2、3、4 的结论都在现场编译的 fixture 上实跑过，CLI 是在 `next`（`0748b372`）上构建的 `swift-section`（主机 macOS 26.7，25G229）。fixture 分三部分：一个 C 模块、一个依赖库、一个根库。临时产物放在 `/tmp/claude/review-ffbcf5964/fx`（会被清理），源码记录如下，可按原样重建。

C 模块 `cmod/Packed.h`：

```c
#pragma pack(push, 1)
typedef struct PackedPair {
    char tag;
    int value;
} PackedPair;
#pragma pack(pop)
```

`cmod/module.modulemap`：

```
module PackedC {
    header "Packed.h"
    export *
}
```

依赖库 `dep/ExtentDependency.swift`：

```swift
public struct CoordinatePair<Element> {
    public var horizontal: Element
    public var vertical: Element
}

public struct DependencyOpaque {
    public var first: Int64
    public var second: Int64
}

public final class DependencyAnchor {}
```

根库 `root/Root.swift`：

```swift
import ExtentDependency
import PackedC

public struct Envelope {
    public var coordinates: CoordinatePair<PackedPair>
    public var tail: Int8
}

public struct DirectEnvelope {
    public var packed: PackedPair
    public var tail: Int8
}

public struct Partial {
    public var leading: Int64
    public var middle: DependencyOpaque
    public var trailing: Int32
}

public struct PartialHolder {
    public var partial: Partial
}

public struct EmptyMarker {}

public struct InnerWithMarker {
    public var leading: Int64
    public var marker: EmptyMarker
    public var trailing: Int32
}

public struct MarkerHolder {
    public var padding: Int32
    public var inner: InnerWithMarker
}

public final class RootAnchor {}
```

根库 `root/PrivateA.swift`：

```swift
fileprivate struct Point {
    var horizontal: Int32
    var vertical: Int32
    var depth: Int32
}

struct HolderA {
    fileprivate var point: Point
    var tag: Int8
}
```

根库 `root/PrivateB.swift`：

```swift
fileprivate struct Point {
    var value: Int64
}

struct HolderB {
    fileprivate var point: Point
    var tag: Int8
}
```

编译：

```bash
xcrun swiftc -emit-library -emit-module -module-name ExtentDependency \
  -emit-module-path dep/ExtentDependency.swiftmodule \
  -module-cache-path ModuleCache \
  -Xlinker -install_name -Xlinker @rpath/libExtentDependency.dylib \
  dep/ExtentDependency.swift -o dep/libExtentDependency.dylib

xcrun swiftc -emit-library -module-name ExtentRoot \
  -module-cache-path ModuleCache \
  -I dep -I cmod -L dep -lExtentDependency \
  root/Root.swift root/PrivateA.swift root/PrivateB.swift \
  -o root/libExtentRoot.dylib
```

分析：

```bash
swift-section dump root/libExtentRoot.dylib -s types \
  --emit-expanded-field-offsets --emit-type-layout \
  --dependency-search-path dep/libExtentDependency.dylib
```

发现 3 另跑一次不带 `--dependency-search-path` 的同一命令，让 `DependencyOpaque` 无法解析。

真值取自编译器写进二进制的静态 metadata：用 `nm -m` 取 `$s10ExtentRoot…VN` 的地址，跳过开头 16 字节（kind 与 description 两个指针），按小端 `UInt32` 读出 field offset vector。这个 fixture 的 `__DATA_CONST` 段虚拟地址与文件偏移相同，可以直接用 `xxd -s` 读。

| 类型 | 编译器的 field offset vector | `swift-section` 的静态结果 |
|---|---|---|
| `Envelope` | `[0, 10]` | `tail` 在 16；嵌套 `vertical` 在 +8；`coordinates` 的类型大小 16、对齐 4 |
| `DirectEnvelope` | `[0, 5]` | 一致；`packed` 的类型大小 5、对齐 1 |
| `HolderA` | `[0, 12]` | `tag` 在 8；`point` 展开成 B 文件 `Point` 的 `value: Int64`，类型大小 8 |
| `HolderB` | `[0, 8]` | 一致 |
| `InnerWithMarker` | `[0, 0, 8]` | 一致（`marker` 报 0） |
| `MarkerHolder` | `[0, 8]` | 一致；嵌套的 `marker` 在 8（父偏移 8 加 0） |

## 一、真缺陷（2 条，基线既有，待修）

### 发现 1 — 泛型定义在另一个镜像、实参是 C 结构体时，布局算错

`Sources/SwiftLayout/StaticTypeLayoutResolver.swift:508`（`structureLayout`）

- **能复现吗 / 是不是误报**：能，已实跑。`Envelope.coordinates` 的类型是 `CoordinatePair<PackedPair>`：`CoordinatePair` 定义在依赖库，`PackedPair` 是 `#pragma pack(1)` 的 C 结构体，真实大小 5、对齐 1。静态结果是嵌套 `vertical` 在 +8、`coordinates` 的类型大小 16、对齐 4，顶层 `tail` 在 16；编译器的 field offset vector 是 `tail` 在 10。对照组 `DirectEnvelope` 直接存同一个 C 结构体，结果正确。
- **机制**：解析 `CoordinatePair` 的字段时，字段记录所在的镜像（代码里的 `originImage`）是定义它的依赖库。代入实参之后，`structureLayout` 只在这个镜像的 builtin record（编译器为 C 导入类型写进 `__swift5_builtin` 的整体 size / alignment / stride）里查 `__C.PackedPair`。依赖库的字段记录里只有泛型参数，没有这条记录，于是退回 `computeStructLayout` 的逐字段累加；`#pragma pack`、bitfield、union 这类 C 布局，靠 Swift 字段记录累加是算不对的。在这个 fixture 里，这条 builtin record 只存在于根库：根库的 `__swift5_builtin` 正好 20 字节、一条记录（size 5、alignment 1、stride 5），依赖库没有 `__swift5_builtin` 段。
- **与 main 基线对比**：基线既有，`next` 与 `main` 上是同一段代码。本次改动新增的只是 `byteWidth`：同一条错误结果现在额外带出 `horizontal.byteWidth == 8`（真实是 5），而文档称它为已证明的大小。
- **值不值得修**：值得，中等优先级。触发条件窄：C 结构体的 Swift 字段记录必须与 C 布局不一致（`#pragma pack` 造成字段错位、bitfield、union、隐藏存储；源码注释里点名过 `__C.Decimal` 与 `__C.CMTime`），并且它被代入另一个镜像里定义的泛型 struct。`CMTime` 只有 aggregate alignment 不同，只有前面的字段恰好在 4 字节对齐处结束时才会错位；size 不同的 bitfield 结构体一旦出现就必错。但一旦触发就是「自信地给出错误偏移」，`5a6d5b02` 明确把这类错误定为比「未知」更糟。影响顶层字段偏移、类型大小、嵌套展开，以及 swift-decompiler 的字段命名。
- **修法方向**：`Sources/SwiftLayout/EnumLayoutBridge.swift:64` 的枚举路径已有现成做法：`originImage` 里查不到时，再查找到 descriptor 的那个镜像（`resolved.image`）。struct 路径可以照此补上；C 类型的布局在所有镜像里一致，也可以在整个 `ImageUniverse` 里找任意一条该类型的 builtin record。一条记录都找不到时，是否继续信任逐字段累加（现行策略），修复时一并决定。
- **同类位置**：`StaticTypeLayoutResolver.swift:182`（`cImportedTypeAliasLayout`，处理 typedef 提升出来的 C 类型，例如 `__C.CMTime`、`__C.NSDecimal`）同样只查 `originImage`，随后进入同一个 `structureLayout`，必须一起修。
- **既往修复**：修过一半。`5a6d5b02`（2026-08-04，给顶层入口加 C 结构体的 builtin record 校验）的提交说明写着「字段类型解析路径已经查过 builtin 索引，只有顶层入口缺这道校验」，这个前提只在 `originImage` 恰好带着该记录时成立。`8fe0871c`（2026-08-05）给枚举补了「再查定义镜像」的回退，注释的理由是「导入 C 类型的记录跟着引用它的镜像走」，没有考虑泛型实参是从别的镜像代入进来的。PR #117（修 issue #116：`CMTime` 被整体降级）也只改了顶层入口。所以这不是回归，而是「跨镜像泛型实参」这种情形一直没被覆盖。

### 发现 2 — 同名私有类型在 SwiftLayout 里被当成同一个

`Sources/SwiftInspection/NodeTypeNaming.swift:142`（`qualifiedName(ofNominal:)`，经 `:156` 的 `declaredName(of:)` 取 `node.identifier`）；`Sources/SwiftLayout/ImageUniverse.swift:108`（`resolveType(byQualifiedTypeName:)`）

- **能复现吗 / 是不是误报**：能，已实跑。fixture 的 `PrivateA.swift` 与 `PrivateB.swift` 各声明一个 `fileprivate struct Point`（A 是三个 `Int32`，12 字节；B 是一个 `Int64`，8 字节），`HolderA` 与 `HolderB` 各存一个。静态结果把 `HolderA.point` 当成了 B 的 `Point`：嵌套展开出 `value: Int64`，类型大小 8，`HolderA.tag` 在 8；编译器的 field offset vector 是 `tag` 在 12。`HolderB` 碰巧正确。
- **机制**：类型索引的 key 是去掉 private discriminator 的全名。`declaredName(of:)` 对 `privateDeclName` 走 `node.identifier`，只取名字、丢掉文件哈希，于是两个 `Point` 都成了 `ExtentRoot.Point`；而 `ImageUniverse` 的各个索引都是 first-writer-wins。
- **与 main 基线对比**：基线既有。SwiftLayout 引擎建立时（`564ef6ee` 与 `e55978e0`，2026-06-21）就用这个 key 建索引；`e273bb8a`（2026-09-20）把 `NodeTypeNaming` 下移到 SwiftInspection，行为没变。审查对象的演进日志（[ProjectEvolutionLog.md](../Documentations/Internal/ProjectEvolutionLog.md) 2026-09-23 节）写着「依赖解析沿用字段的定义镜像及泛型实参，不从显示名称猜测」，与事实不符：嵌套类型是按名字在整个 `ImageUniverse` 里查的。
- **值不值得修**：值得，但真实触发率可能不高。对本机（macOS 26.7）系统 dyld shared cache 里的 SwiftUICore 跑 `swift-section dump -s types` 做统计：3626 个类型声明里有 1058 个私有类型，去掉 private discriminator 后撞名的有 6 组、13 个（`ChildEnvironment`、`ChildTransaction`、`CustomModifier` 三个、`Error`、`GestureFilter`、`GlassEffectContainerModifier`，全是 struct 或 enum），但没有一个出现在任何存储属性的类型里，所以 SwiftUICore 自身的布局不受影响。触发需要「同名私有值类型被用作字段类型，并且两者布局不同」。一旦触发，同样是自信的错误输出，影响顶层偏移、类型大小、嵌套展开与下游命名。
- **修法方向**：让 key 带上 private discriminator。建索引与查找两侧都经过 `NodeTypeNaming`，改这一处两侧就一致。退一步的做法是建索引时发现同一个 key 对应多个 descriptor，就把这个 key 标成歧义，查找时降级为未知，不再挑第一个。
- **同类位置**：`NodeTypeNaming` 现在不只 SwiftLayout 在用：SwiftLayout 里 11 个文件，另有 SwiftInspection 2 个、SwiftDump 2 个、SwiftIndexing 1 个、SwiftDeclaration 1 个文件。改 key 格式之前，要逐个核对这些调用方是否依赖「同名私有类型共用一个 key」。SwiftLayout 内部用同一个 key 的还有：`ImageUniverse` 的类型索引与协议索引、`StaticTypeLayoutResolver` 的 memoization cache 与 cycle guard、关联类型 witness 索引（key 里含 conforming type 的名字）。
- **既往修复**：同一类问题修过两次，都没修到这里。① issue #115（dump 把同名私有类型的成员混在一起）由 PR #117（2026-08-26）修复，只改了符号索引、成员归属与 `typeInfoByName`，说明文档 [PrivateTypeMemberAttribution.md](../Documentations/Internal/PrivateTypeMemberAttribution.md) 没有提到 SwiftLayout。② `1c8d8588`（2026-09-09，提案 0023）在 `declaredName(of:)` 里给 importer 合成的 related entity 加了专门处理，原因是所有合成的错误结构体共享实体标签 `e`、会撞 key。那是同一个函数、同一种撞名，但当时只处理了 related entity，没有处理 `privateDeclName`。

## 二、文档缺陷（3 处，待修）

### 发现 3（文档部分）— `children` 的注释过时

`Sources/SwiftLayout/NestedFieldOffsetTree.swift:26`

注释仍写着 "empty for a leaf, a class reference, or an aggregate the engine could not expand"。本次改动之后，嵌套结构体中间有字段算不出时，会返回它前面已经算出的字段（main 上是整组返回空）。前缀里的偏移与大小都经证明，行为本身不改（见 A40），只需把注释改成「截到第一个算不出的字段为止」。前缀截断的测试可以随这次注释修改一起补（对应 A46 的后半）。

### 发现 7、8 — 公开仓库的文档链接到私有仓库里的提案

`Documentations/Evolutions/README.md:11`、`Documentations/README.md:62`、`Documentations/Internal/ProjectEvolutionLog.md`（2026-09-23 节的「关联文档」）

- **能复现吗**：属实。`gh repo view` 显示 swift-decompiler 是 PRIVATE、MachOSwiftSection 是 PUBLIC，所以这三处链接对外部读者现在就是 404。链接还钉在工作分支 `fix/microcode-operand-pairs` 与文件名 `draft-nested-coordinate-field-extents.md` 上，分支删除或提案落地改名之后，对所有人都会失效。
- **与 main 基线对比**：本次新增。
- **值不值得修**：值得，改动很小。但「只在 swift-decompiler 留一份提案」是用户 2026-09-23 批准过的方案：那份提案的方案第 6 步与决策日志都写明「此提案作为跨仓库改动的唯一决策记录，由依赖仓库索引链接」；拆成两份又违反「一次改动一份提案」。本仓库的先例是 0019（大栈执行器）与 swift-demangling 的提案 0014：两边各留一份、互相链接。待用户选：本仓库补一份精简提案并与对方互链（沿用 0019 的先例）；或者保留链接，但标明是私有仓库，并以本仓库演进日志的条目为准。
- **既往修复**：无。这是第一次跨仓库只留一份提案；当初这样做是为了避免出现两份权威记录，没有考虑到两个仓库一个公开、一个私有。

### 发现 2 附带 — 演进日志里「不从显示名称猜测」的措辞

`Documentations/Internal/ProjectEvolutionLog.md:1916`

与发现 2 的事实不符。随发现 2 的修复一起更正：只有 key 带上 private discriminator 之后，这句话才成立。

## 三、误报或不修（7 条，已登记）

| 发现 | 结论 | 登记 |
|---|---|---|
| 3 — 嵌套展开只返回前半段、不标截断；审查认为 dump 会多出新行 | 截断标记不修；「dump 多出新行」误报（现有调用方走不到） | A40 |
| 4 — 零大小字段的嵌套偏移从累加位置变成 0 | 误报：与编译器的 field offset vector 一致 | A41 |
| 5 — 公开入口默认把根的子字段当成无条件存储 | 不修：没有调用方把枚举 payload 当根传入 | A42 |
| 6 — `byteWidth == nil` 同时表示「未证明」与「条件存储」 | 不修：当前没有行为差异 | A43 |
| 9 — 换用 `fieldLayout(ofStruct:)` 之后多做工作 | 误报：多出的工作现有调用方走不到；实测耗时无差异 | A44 |
| 10 — 测试把同一个 fixture 编译 6 次 | 不修：整组 1.96 秒 | A45 |
| 11 — 默认值测试同义反复；缺前缀与零大小的测试 | 前半误报；后半随发现 3 的注释修改一起补 | A46 |

## 附：本次改动对 dump / interface 输出的实际影响

开启 `--emit-expanded-field-offsets` 时，本次改动带来的输出变化只有一处：嵌套的 C 结构体如果通不过 builtin record 校验，就不再展开。main 上走 `computeStructLayout` 的逐字段累加，会给出错误的嵌套偏移，例如 fixture 里的 `DirectEnvelope.packed` 在 main 上会展开成 `tag` 在 0、`value` 在 4，而真实的 `value` 在 1（这一条来自读代码，没有用 main 的构建实跑）。所以这是修复。「展开到第一个算不出的字段为止」这一变化，dump 与 swift-decompiler 两个调用方都走不到（见 A40），不改变输出。
