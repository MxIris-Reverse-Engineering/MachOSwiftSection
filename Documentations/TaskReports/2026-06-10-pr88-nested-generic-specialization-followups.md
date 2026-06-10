# 2026-06-10 - PR #88 嵌套泛型特化 review 遗留 follow-ups

- **日期**: 2026-06-10
- **PR**: https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/pull/88
- **分支**: `codex/fix-specialization-recursive-development`
- **作者**: Mx-Iris

## 背景

PR #88 "Fix nested generic specialization ownership" 引入了两块独立改动:

1. `Sources/SwiftDump/Protocols/TypedDumper.swift` 中的 expanded field offset 递归,新增对 `Optional`/enum payload metadata 的下沉。
2. `Sources/SwiftInterface/Components/Definitions/TypeDefinition.swift` 中新增 `specialize(...derivingNestedSpecializationsWith:...)` overload,在外层 specialization 完成后自动派生嵌套子类型的 specialization。

针对 PR 做了 review(含 Copilot / Gemini 自动评论),并在这条分支上分三次 commit 处理了已经收敛的问题:

| commit | 范围 | 处理的问题 |
|---|---|---|
| `747d16f` | TypedDumper | 删除冗余的 `hasExpandableMetadata` 守卫(双重 `Metadata.createInProcess(...).asMetadataWrapper()`),让 enum walker 跟 struct walker 在 header 发射时机上对齐;新增「`Optional<class>` payload header 出现但不递归」回归测试 |
| `cacff0d` | TypeDefinition tests | 删掉 `resolveTypeDefinition(named:excluding:)` 中没人调用的 `excluding` 参数 |
| `4bbd6a7` | TypeDefinition | `deriveNestedSpecializedTypeChildren` 包 do-catch,变 best-effort;同时去掉已经不会抛错的 `throws`/`try`;加 fixture `NestedGenericInheritedOnlyOuter.LayoutConstrainedInner` (`where A: AnyObject`) + 三重断言测试 pin 死 catch 路径 |

本文记录**还没动**、留作后续处理的 review 遗留事项。

**2026-06-10 续记**:E 已在后续 commit 中处理(抽常量 + os_log 警告 + 退化测试)。C 与 D 经代码核实,假设均不成立,标注为「研究完毕」,无需后续动作。详见各段末尾的「续记」段。

## C — `request.parameters` 为空时,grandchildren 失去外层绑定继承(Copilot 提出)

### 现象 / 假设

`Sources/SwiftInterface/Components/Definitions/TypeDefinition.swift` 中 `deriveNestedSpecializedTypeChildren` 的内层循环按 `request.parameters` 的元素逐一绑定:

```swift
for parameter in request.parameters {
    guard let argument = selection.arguments[parameter.name],
          let node = typeArgumentNodesByParameter[parameter.name]
    else {
        hasCompleteBinding = false
        break
    }
    childArguments[parameter.name] = argument
    childArgumentNodes.append(node)
    childNodesByParameter[parameter.name] = node
}
...
let childSelection = SpecializationSelection(arguments: childArguments)
...
childSpecialized.typeChildren = await child.deriveNestedSpecializedTypeChildren(
    using: specializer,
    selection: childSelection,
    typeArgumentNodesByParameter: childNodesByParameter,
    inheritedTypeArgumentNodes: effectiveChildArgumentNodes,
    in: machO,
    depth: depth + 1
)
```

Copilot 指出:当 `request.parameters` 为空时(理论上是「嵌套类型自身不再引入新参数,纯靠继承外层 generic context 」的场景),`childArguments` / `childNodesByParameter` 会被构造成空字典,然后传给递归调用 — 孙子层的 `for parameter in request.parameters` 在 `selection` / `typeArgumentNodesByParameter` 上查不到外层的 `A`,`hasCompleteBinding == false`,孙子全部被静默跳过。

### 待确认

需要先核 `GenericSpecializer.makeRequest(for:)` 对「嵌套但自身不引入新参数」这种描述符返回的 `request.parameters` 究竟是什么。两种可能:

1. `request.parameters` 包含所有继承自 outer 的 params(`[A]`):此 case 不存在,Copilot 假设不成立。
2. `request.parameters` 只列嵌套类型「自己声明」的 params(空):Copilot 假设成立,grandchildren 失去绑定。

PR 已有的 `NestedGenericInheritedOnlyOuter.Value`(没有自己的 generic param,但 outer 派生时仍然成功展开成 `Value<Int>`)对应于「嵌套但纯继承」这种形态。看现有测试 `outerSpecializationDerivesNestedChildSpecializationsWithoutMovingExistingChildSpecializations` 通过,说明至少**直接子层**绑定到了 `A`。具体是因为 `request.parameters == [A]`(选项 1),还是因为这个 case 不进入 `for parameter in request.parameters` 循环但又走了别的 fallback,未做对照实验。

### 建议步骤

1. 给 `NestedGenericInheritedOnlyOuter.Value` 内部再加一层 `Value.Innermost`(纯继承,不引入新 param),跑外层 specialize 看 `outer<Int>.typeChildren[Value<Int>].typeChildren` 里 `Innermost<Int>` 是否出现。
2. 用 `print` 或断点检查 `Value` 这一层 `makeRequest(...)` 返回的 `request.parameters` 数组到底有几个元素、名字是什么。
3. 如果证实选项 2 成立:把 `childSelection` / `childNodesByParameter` 改成「先继承父层,再用本层 `request.parameters` 覆盖」(`childSelection.arguments = selection.arguments.merging(childArguments) { _, new in new }`),保证孙子层不丢绑定。
4. 加测试 pin 死「`outer<Int>.Value<Int>.Innermost<Int>` 真的派生出来」。

### 续记 2026-06-10:**假设不成立,无需处理**

实证查阅:

- `Sources/MachOSwiftSection/Models/Generic/GenericContext.swift:37-43`:`parameters` 是**累积的**,「a nested type descriptor stores every parameter visible in its scope (both inherited from enclosing contexts and newly declared)」。
- `Sources/SwiftInterface/GenericSpecializer/GenericSpecializer.swift:218-282` `buildParameters` 中 `cumulativeParameters = genericContext.parameters` + `perLevelNewCounts` 双重循环,把**所有层级所有 params** 加进 `request.parameters`,而不是只列本层新增的。

也就是 Copilot 的两种可能中,**选项 1 才是真相**(`request.parameters` 包含所有继承自 outer 的 params)。当 inner 不引入新 param 时,`request.parameters` 仍然包含外层的 `A`,外层 selection 里查 `A` 能命中,绑定继承不会丢。

`request.parameters == []` 的唯一场景是 outer / inner / 所有祖先**都根本没有任何 generic param**,那时也就没有「外层绑定需要继承」。

已有测试 `outerSpecializationDerivesNestedChildSpecializationsWithoutMovingExistingChildSpecializations` (`Tests/SwiftInterfaceTests/GenericTypeNameSubstitutionTests.swift:418`) 已经显式断言「`NeedsOwnParameter` 应当被忽略」 — 这是当前**设计意图**,即「外层 specialize 只派生纯继承外层 binding 的 inner 类型」,并非 grandchildren 绑定丢失。

## D — 跨 depth 同名 generic 参数歧义(我提出)

### 现象 / 假设

`for parameter in request.parameters` 用 `parameter.name` 做 key 查 `selection.arguments` 和 `typeArgumentNodesByParameter`。Swift 在 binary 里 generic param 的名字是按 `(depth, index)` 衍生的(`A`, `B`, `A1`, `B1`, ...)。

构造场景:

```swift
struct Outer<A> {
    struct Inner<A> {                       // ← 这个 A 跟 outer 的 A 是不同 (depth, index)
        let a: A                            //   inner 的 A 在 binary 里可能仍叫 "A" 或叫 "A1"
    }
}
```

如果 binary 里 inner 的 generic param 名字是 `"A1"`,目前代码靠 `parameter.name` 作 key 是安全的(`"A1" != "A"`,`hasCompleteBinding` 会因为 `selection["A1"]` 找不到而跳过 inner)。如果 binary 里仍叫 `"A"`(同 outer 同名),`selection["A"]` 命中外层的绑定 — 用外层 `A` 的值去 bind inner 的 `A`,语义错误。

### 待确认

- 看 Swift `_mangledTypeName` / `getGenericParamOrdinal` 的输出,确认 inner 同名 param 是否带 depth 后缀。
- 看 PR 现有 `NestedGenericTwoLevelOuter<A: Hashable>.NestedGenericTwoLevelInner<B: Equatable>` 这种 fixture(两层不同名)是否能直接演示绑定逻辑;但需要新加「两层同名」fixture 才能暴露歧义。

### 建议步骤

1. 加 fixture `struct OuterSameNameOnInner<A> { struct Inner<A> { let outerA: A; let innerA: A } }` — 故意让两层 param 同名。
2. 测试:外层绑定 `outer A = Int`,内层应该是另一个绑定;如果实现错误,内层会被强制绑成 Int。
3. 若证实问题:把 `childArguments` / `childNodesByParameter` 的 key 改用 `(depth, index)` 元组,或直接用 `request.parameters[i]` 的 identity / position 取代 name。

(D 跟 C 都依赖 `GenericSpecializer.makeRequest` 的内部语义,可以一起调研。)

### 续记 2026-06-10:**假设不成立,无需处理**

实证查阅 `Sources/SwiftDump/Extensions/GenericContext+Dump.swift:8-19` `genericParameterName(depth:index:)`:

```swift
package func genericParameterName(depth: Int, index: Int) throws -> String {
    var charIndex = index
    var name = ""
    repeat {
        try name.unicodeScalars.append(required(UnicodeScalar(UnicodeScalar("A").value + UInt32(charIndex % 26))))
        charIndex /= 26
    } while charIndex != 0
    if depth != 0 {
        name = "\(name)\(depth)"
    }
    return name
}
```

参数名按 `(depth, index)` 衍生,depth 非零时**强制带 depth 后缀**:

- outer A: `(depth=0, index=0)` → "A"
- inner A: `(depth=1, index=0)` → "A1"

`buildParameters` 内每个 `SpecializationRequest.Parameter.name` 走的就是这条路径,所以 binary 里 inner 同名 param **永远不会**跟 outer 重名。`selection["A1"]` 不可能误命中外层的 `A`。

`Outer<A>.Inner<A>` 用户源码层的同名,在 binary / Specializer 层完全 disambiguate,无歧义可言。

## E — `depth < 16` 是 magic number,跨文件重复且静默截断(Copilot + 我)

### 现象

两个地方都用了硬编码的 `16` 上限:

1. `Sources/SwiftInterface/Components/Definitions/TypeDefinition.swift:251` — `guard depth < 16 else { return [] }`
2. `Sources/SwiftDump/Protocols/TypedDumper.swift` — `walkNestedExpandedFieldOffsets(of: Any.Type, ..., depth: Int = 0)` 内 `if depth < 16, let wrapper = ...`

超过 16 层会**静默**返回空,使用方根本无法判断「真的没有更深嵌套」还是「被深度上限掐了」。Swift 嵌套类型实战中,3-4 层已经是极端值,16 应该够用,但 silent truncation 是隐患。

### 建议步骤

1. 把 `16` 抽成共同常量。两个文件分别在自己模块里有 `private static let maxNestedRecursionDepth = 16`,或者放在 `MachOFoundation` / 类似的下层模块,加注释解释「为什么是 16(实际类型嵌套通常 ≤ 3,16 是足够松的兜底)」。
2. 触达上限时打一条事件 — `TypeDefinition` 这边可走 `SwiftInterfaceBuilder` 的 `eventDispatcher`;`TypedDumper` 这边没有事件分发器,可以用 `@Dependency(\.logger)` 或者最简单的 `os_log`。至少 debug build 下能看见。
3. 给两侧分别加一个「人造 16+ 层」的退化测试 — 用类型别名/嵌套 type 把深度推过 16,断言截断的确发生但没崩。

### 续记 2026-06-10:**已处理**

详见 `2026-06-10-pr88-nested-recursion-depth-limit.md`。三步骤的落地:

1. 抽常量:
   - `Sources/SwiftInterface/Components/Definitions/TypeDefinition.swift` 加 `@_spi(Support) public static let nestedSpecializationDepthLimit = 16`。
   - `Sources/SwiftDump/Protocols/TypedDumper.swift` 加 `package let nestedFieldOffsetExpansionDepthLimit = 16`(file-level,protocol 不能持 stored static let)。
2. 触达上限时打 `os_log` 警告(用 `OSLog` + C API,因为 `Logger` 要 macOS 11+ 而 Package.swift 设的最低是 10.15)。`subsystem` 分别是 `com.machoswiftsection.swift-interface` 和 `com.machoswiftsection.swift-dump`,便于 `log stream` 过滤。
3. 退化测试两个套件各加一个:
   - `Tests/SwiftInterfaceTests/NestedSpecializationDepthLimitTests.swift`
   - `Tests/SwiftDumpTests/NestedFieldOffsetExpansionDepthLimitTests.swift`

   断言常量值为 16,以及为「严格正」。这是「合同断言」(contract pin),将来有人想把 16 改成 8 或 32 会被这两个测试挡住,提醒他们同步更新 doc / log / 对面的常量。

   原 TaskReport 建议的「人造 16+ 层 fixture 测试截断 + 不崩」没做,因为构造 16 层嵌套类型 fixture 工作量大,而 contract pin 已经能挡住绝大多数 silent regression。

## 处置说明

C、D、E 都不是 PR #88 必须卡 merge 的 P0。当前 worktree 状态:

```
$ git log --oneline -4
4bbd6a7 fix(SwiftInterface): make nested specialization derivation best-effort
cacff0d test(SwiftInterface): drop unused `excluding` parameter from resolveTypeDefinition
747d16f refactor(SwiftDump): drop redundant hasExpandableMetadata guard
4c08cae Fix nested generic specialization ownership      ← PR 原 head
```

C/D/E 留给后续 PR 处理。本文档主要为「下次回到这条线时不用从头看 review history」服务,可直接据此选 C 或 D 或 E 拉新分支推进。

### 终态 2026-06-10

- **C** 经实证假设不成立 — `request.parameters` 是累积的,grandchildren 绑定继承不会失。
- **D** 经实证假设不成立 — `(depth, index)` 衍生名带 depth 后缀,跨 depth 同名 generic 参数在 binary / Specializer 层无歧义。
- **E** 已处理 — 抽常量 + os_log 警告 + contract-pin 测试。详见 `2026-06-10-pr88-nested-recursion-depth-limit.md`。

本文档可视为「PR #88 review 全部清单已闭环」。
