# 不透明类型的泛型实参收集错位（RuntimeViewer issue #5 复发）

- **日期**：2026-09-11
- **提案**：无（bug 修复，按 evolution 制豁免）
- **起因**：用户要求"测一下 SwiftUI 和 SwiftUICore 的不透明类型的真实类型"，并指出
  [RuntimeViewer issue #5](https://github.com/MxIris-Reverse-Engineering/RuntimeViewer/issues/5)
  （`SwiftUI.FeedbackGenerator.Body` 类型信息不完整）"这个问题没修好"。该 issue 当年被标记为
  已由新版 swift-section 修复并关闭。

## 问题

`swift-section dump --sections associatedTypes` 输出的 `typealias Body = …` 里，大量类型带着
未被替换的裸泛型参数（`A`、`A1`），例如：

```
extension SwiftUI.ExternalGestureActionModifier: SwiftUI.ViewModifier {
    typealias Body = SwiftUI.ModifiedContent<A, SwiftUI.ViewInputFlagModifier<A1>>
}
```

`ExternalGestureActionModifier` 不是泛型类型，它的 `Body` 里不该出现任何泛型参数。

## 调研

### 一条被推翻的假设

最先怀疑的是 ordinal：SwiftUI 里 307 个 `StaticIf<谓词, 真分支, 假分支>` 实例中有 17 个两个
分支渲染成完全相同的类型（`CircularPercentageGauge` 两边都是 `SizedCircularPercentageGauge`，
`NavigationSplitCore` 两边都是 `NavigationSplitRepresentable`），看起来像是
`underlyingTypeArgumentMangledNames[safe: 0]` 这行硬编码把两个 `some` 解析成了同一个。

**实测推翻**：写探查测试打印未解析形态，两个分支在 mangled name 里本来就是同一个 descriptor、
同一个 ordinal 0：

```
StaticIf<InterfaceIdiomPredicate<VisionInterfaceIdiom>,
         opaque type symbolic reference 0xADFD15FC.0,
         opaque type symbolic reference 0xADFD15FC.0>
```

那 17 例是 SwiftUI 自己的形状，不是缺陷。

### 真正的根因

`Node+OpaqueType.swift` 收集实参的那两行：

```swift
for (depth, typeList) in rootTypeListNode.children.enumerated() {
    for type in typeList {                       // ← 这里
        allTypeList[depth, default: []].append(type)
    }
}
```

`Node` 遵循 `Sequence`，而 `makeIterator()` 返回的是 `preorder()`，前序序列的第一个元素是
**节点自己**（`PreorderSequence.Iterator` 以 `stack = [root]` 起手）。所以内层循环收集到的
不是"这一层的实参"，而是"`typeList` 节点自己 + 每个实参 + 每个实参的全部后代"。

两个后果都不报错：

1. **位置 0 永远是 `typeList` 节点本身**，kind 是 `.typeList`，被替换器的
   `isKind(of: .type)` 守卫挡掉 → 第 0 个参数从来没被替换过，渲染成 `A` / `A1`。
2. **后面每个参数读到的是左邻居，或左邻居子树里的碎片** → 渲染出一个**属于别的参数的真实
   类型**，完全看不出是错的。

`NavigationSplitCore.ColumnView.Body` 是最清楚的一例。实参表是
`[StyleContextAcceptsPredicate<SidebarStyleContext>, ToolbarControlledNavigationPredicate]`，
underlying 是 `StaticIf<AndOperationViewInputPredicate<A1, B1>, A, EmptyModifier>`：

| | 第一参数 | 第二参数 |
|---|---|---|
| 正确 | `StyleContextAcceptsPredicate<SidebarStyleContext>` | `ToolbarControlledNavigationPredicate` |
| 修复前 | `A1`（没替换） | `StyleContextAcceptsPredicate<SidebarStyleContext>`（拿了左邻居） |

`TitleAndIconLabelStyle` 那条更直观：`StaticIf<A1, SwiftUI.Solarium, C1>` 修复后变成
`StaticIf<SwiftUI.Solarium, ModifiedContent<LabelStyleConfiguration.Icon, …>, …>` ——
`Solarium` 从第 2 个位置挪回第 1 个，错位一格看得见。

顺带解释了历史：`OpaqueTypeGenericParameterSubstitutionTests` 当年修的那个"返回 depth 字面量
渲染成裸数字 `1`"的 bug，之所以能取到 `dependentGenericParamType` 的 index 子节点，正是因为
前序遍历把那些 index 节点也塞进了实参列表。那次只修了取值，没修列表本身。

### 另外两条

- **ordinal 仍然该修**。用一个 fixture 验证了数组布局：一个返回
  `ProbePair<some ProbeView, some ProbeView>` 的函数，其 descriptor 的
  `numUnderlyingTypeArguments == 4`，内容是
  `[underlying 0, underlying 1, conformance 0, conformance 1]` —— 所有替换类型在前、
  conformance 在后，正是 IRGen 写 underlying substitution map 的顺序，也是 runtime
  `_getOpaqueTypeMetadata` 读回的顺序。所以 `[safe: 0]` 对 ordinal 1 的 opaque 会静默取错。
  SwiftUI / SwiftUICore 的 assocty 记录里 ordinal 全是 0，所以这条在这两个框架上不触发。
- **嵌套 opaque 只展开一层**。`Node.Rewriter` 是自底向上的，`visit` 的返回值不会被再次访问，
  所以替换进来的实参若本身是 opaque，就停在那里，渲染成 `opaque type symbolic reference 0x…`。

## 最终方案

1. 把实参收集抽成 `Node.opaqueTypeGenericArgumentsByDepth(of:)`，改用 `typeListNode.children`，
   并照 swift-demangling 自己的 `TypeDecoder.decodeMangledType` 那样在遇到非 `typeList` 的层
   时停下。抽成独立函数是为了能直接单测——这个契约的失败在渲染输出里完全静默。
2. ordinal 从 `opaqueType` 节点的第二个子节点取（缺省 0），用它索引
   `underlyingTypeArgumentMangledNames`。
3. 替换完成后，若结果里还含 `opaqueType` 节点，再过一遍同一个重写器
   （`expandingNestedOpaqueTypes(in:)`），上限 8 层——这个关系可能成环（opaque 的 underlying
   type 可以绕回它自己），且没有便宜的办法证明它不成环。到顶时保留最内层引用，与
   descriptor 读不出来时的降级一致。

## 验证

- **单测**：`OpaqueTypeGenericParameterSubstitutionTests` 新增 3 个（收集契约 + 空实参 +
  两层端到端），`OpaqueTypeOrdinalTests` 新增 2 个（数组布局 + 按 ordinal 解析），fixture 是
  当场编译的 dylib。两批都按规矩验过红：把旧的前序遍历放回去，
  `everyParameterOfATwoLevelOpaqueTypeSubstitutesToItsOwnArgument` 一次暴露三种症状
  （`A` 未替换 / 拿到左邻居 `Swift.Int` / `A1` 未替换）；把 ordinal 改回 `[safe: 0]`，
  `resolvingByOrdinalYieldsThatOrdinalsUnderlyingType` 在 ordinal 1 上返回 `ProbeLeafA`。
- **全量对照**（macOS 26 系统 dyld 共享缓存）：

  | | SwiftUI | SwiftUICore |
  |---|---|---|
  | `typealias` 总数 | 4698 | 3325 |
  | 改变的行 | 231 | 0 |
  | depth≥1 裸参数残留 | 178 → 10 | 15 → 15 |
  | 未解析 opaque 引用 | 15 → 17 | 0 → 0 |

  剩下的 10 条经逐条核对全部**合法**——它们的 conforming type 本身就是嵌套泛型
  （`AccessibilityListStyle.Body<A>.AccessibilityList<A1>`、
  `AccessibilityToggleModifier<A>.RepresentationModifier<A1>`），`A1` 是内层参数。真正的残留
  178 → 0。

  SwiftUICore 一行没变：它的 assocty 记录里根本没有 opaque 引用。这个缺陷是 SwiftUI 独有的。

  未解析引用 15 → 17 的 +2 是**诚实度提升**而非退步：修好替换后，被替换进来的 opaque
  （`FeedbackGenerator` 内层的 `0x367D5978`）显式露出来了，而在此之前它被错误地印成 `A`。

- **全量回归**：`swift test --skip IntegrationTests`，1796 个测试 / 333 个套件，2 个 issue，
  都是已知的 `SharedCacheTests.differentKeysParallel*`（用墙钟断言并行度，全量跑必假失败）；
  单独跑 `--filter SharedCache` 9 个测试全过。
- **耗时**：`dump --sections associatedTypes` SwiftUI 11.6s → 13.0s（+12%），SwiftUICore
  3.8s → 3.6s（持平）。增量主要是 231 条记录展开出了更多类型要打印，递归展开本身有
  `node.contains(.opaqueType)` 的前置检查，没有 opaque 时不重跑重写器。

## 与 issue #5 的关系

issue 期望 `FeedbackGenerator.Body` 是三层 `ModifiedContent`，最内层是
`ModifiedContent<Content, _TaskValueModifier<T>>`。修复后：

- `CustomFeedbackGenerator`（同一批里的姊妹类型）拿到了完整的
  `ModifiedContent<ModifiedContent<_ViewModifier_Content<CustomFeedbackGenerator<A>>, _ValueActionModifier2<A>>, _AppearanceActionModifier>`
  ——issue 期望里的 `Content` 就是这个 `_ViewModifier_Content<…>`。
- `FeedbackGenerator` 本身停在 `ModifiedContent<ModifiedContent<opaque …0x367D5978, _ValueActionModifier2<A>>, _AppearanceActionModifier>`：
  内层那个 opaque 的 underlying type 在 descriptor 里是
  `accessor function at 891776140`，**离线拿不到**——要执行目标进程里的代码才能得到类型。
  递归展开对它无能为力，这是诚实的天花板，不是遗漏。

## 未决

`Slider` / `Toggle` / `TextField` / `Picker` 等 15 条 `Body` 整条渲染成
`opaque type symbolic reference 0x367C6120.0`，同样因为 underlying type 只有运行时 accessor。
当前文案对非 ABI 专家毫无信息量，而节点自己的实参里其实带着可读信息（`Slider` 那条的实参是
完整的 `ModifiedContent<…ResolvedSliderStyle…>` 链）。建议另开一批改成诚实且有信息量的渲染，
与 `accessor function at <offset>` 的既有降级文案对齐。
