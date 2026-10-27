# Draft - 只剩 `@objc` thunk 或 initializing 入口的成员照样建出来

- **状态**: Accepted
- **创建日期**: 2026-10-27
- **最后更新**: 2026-10-27
- **关联 issue**: [#137](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/issues/137)（Swift 侧）、[#138](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/issues/138)
- **关联提案**: [0054-interface-descriptor-only-vtable-members](0054-interface-descriptor-only-vtable-members.md)（同一种「替身成员符号」的先例）
- **实现分支**: `fix/thunk-only-objc-members`

## 摘要

优化构建（`-O`、整模块优化）里，编译器常把成员的 Swift 实现内联掉，只留下另一个入口。一种是 `@objc` 成员：函数体被内联进它的 Objective-C 入口 thunk（`$s…To`），Swift 入口消失。另一种是 class 的 `init`：allocating 入口（`…fC`）被内联进调用方后删掉，只剩 initializing 入口（`…fc`）。成员模型只从实现符号（以及提案 0054 的 `Tq` 替身）建成员，所以这两种成员在 `interface` 里整个消失，前一种在 `dump` 里也消失。Xcode 27.2 的 `Xcode Service` 可执行文件里，前一种有 7 个类、22 个成员（`canBecomeKey`、`layout()`、`windowWillClose(_:)` 这类），后一种有 9 个 `init`。改法沿用提案 0054：真实符号没有声明这个成员时，用镜像里剩下的那个入口造一个替身成员符号。

## 方案

1. **符号索引**（MachOSymbols）：`To` thunk 符号照旧登记成「这个名字是 `@objc`」的标记，此外再按成员类别、类型名与类型节点分桶登记进第四个成员索引，与实现符号、`Tq`、protocol witness 三个索引并列。查询返回 thunk 自己的符号。
2. **声明模型**（SwiftDeclaration、SwiftIndexing）：类的各类成员与 extension 的成员，在实现符号和 0054 的 `Tq` 替身之后再补两种替身。只补真实符号没有声明的成员，判据与 0054 相同：按成员实体节点结构相等。
   - **initializing 入口替身**（#138）：把 `…fc` 符号改写成 allocator 的形状，即节点 `constructor` 换成 `allocator`、名字后缀 `fc` 换成 `fC`、偏移仍是 `fc` 的入口。这样 vtable 里实现为 null 的 `__allocating_init` 槽照常按节点联结上，ObjC 方法表照常按 allocator 名换成 `…fcTo` 联结，ABI 身份也与没被内联时相同。
   - **`@objc` thunk 替身**（#137）：去掉 `objCAttribute` 子节点得到成员节点，名字去掉 `To` 后缀（`…fcTo` 再按上一条改成 allocator），偏移用 thunk 自己的地址，因为它是这个成员唯一的代码。下游按名字推导的几处（导出判定、ObjC 方法表联结、`@objc` 标记）都把替身当成它顶替的实现符号来读，不用改。
3. **dump**（SwiftDump）：class 与 extension 的成员列表在各类别之后加一节 `/* [ObjC Thunk] <类别> */`，列出只剩 thunk 的成员。判断方法是实现名、它的合并形式（`Tm`）以及 `init` 的另一个入口都不存在。行尾照常挂 ObjC 方法表的联结注释。只剩 initializing 入口的 `init`，dump 本来就列在 `/* Constructor */` 下，不动。
4. **ABI 快照**：格式版本加一，旧基线会把新建出来的成员全报成新增。草案 `evolution-unobservable-presence` 也要加一，谁先落地谁取 8。

没有询问就采用的假设：

- interface 不给替身成员加额外标注，地址注释照常输出，指向 thunk 或 `fc` 入口；替身的来历只在 dump 里写明。
- 泛型类和经 `__objc_stublist` 登记的类没有静态的 ObjC 方法表，它们的替身成员只有 `@objc`、没有 `override`。这要等 #137 的 ObjC 侧，另立一份提案，并与 MachOObjCSection 协作。
- `…ToTm`（几个 thunk 共用的合并函数体）不建成员。
- 新索引走 `processMemberSymbol` 分类，`@objc subscript` 的 thunk 也一并进索引；原来的标记表不认 subscript，这一点顺带补上。

验证：

- 新增一个现场编译的 fixture，用 `-O` 编译、不 strip：内部类对 ObjC 成员的覆写、`@objc` 方法、`override init()`，泛型类的覆写，以及只剩 `fc` 的 `init`。先写测试，确认改动前失败。
- 改动涉及索引与打印，按项目规则跑渲染 A/B；预期系统框架的输出不变，或只多出替身成员。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-27 | Created as Draft | #137 与 #138 的 triage 定位到成员模型只认实现符号；用户要求本库与 MachOObjCSection 两边并行开工。 |
| 2026-10-27 | 轻量档，状态 Accepted | 用户批准开工；改法沿用提案 0054 已落地的替身成员符号。 |
| 2026-10-27 | #138 并入本提案 | `@objc` thunk 替身里的 `init` 来自 `…fcTo`，去掉后缀得到的是 initializing 入口，模型要先接受这种入口；分两次改要把同一处改两遍。 |
| 2026-10-27 | #137 的 ObjC 侧另立提案 | 让 `objc dump` 和 ObjC 方法表看见泛型类与 stub-list 类，需要 MachOObjCSection 先加 API，与本提案互不依赖。 |
