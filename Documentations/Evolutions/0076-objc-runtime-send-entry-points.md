# 0076 - 交叉引用把 libobjc 的专用发送入口记成消息发送

- **状态**: Implemented
- **创建日期**: 2026-10-27
- **最后更新**: 2026-10-27
- **所属愿景**: 无
- **关联提案**: [0072](0072-cross-reference-analysis.md)（交叉引用分析）
- **实现分支 / PR**: `fix/cross-reference-review-findings`（worktree `.worktrees/MachOSwiftSection-CrossReferenceReviewFixes`，基于 `next`），2026-10-27 本地合入 `next`
- **配套文档**: [Modules/CrossReferenceAnalysis.md](../Internal/Modules/CrossReferenceAnalysis.md)「libobjc 的发送入口」一节；[2026-10-27 审查记录](../../Roadmaps/2026-10-27-cross-reference-analysis-second-review-findings.md) 第 2 条

## 摘要

clang 不把每个 Objective-C 发送都编成 `objc_msgSend`：`[[Foo alloc] init]` 编成 `objc_alloc_init(Foo)`，`[x isKindOfClass:c]` 编成 `objc_opt_isKindOfClass(x, c)`，`[Foo new]`、`[x class]`、`[x self]`、`[x respondsToSelector:s]`、`[Foo alloc]` 也各有一个 libobjc 入口。交叉引用扫描只把 `objc_msgSend` 和 `objc_msgSendSuper2` 当发送，这些入口记成普通函数调用，按 selector 查调用者时就漏掉。macOS 26.6 的 AppKit 里，`objc_alloc_init` 有 2,488 处调用，而按 selector 发送的 `init` 只有 720 处，查 `init` 的调用者漏掉约 78%；`isKindOfClass:`、`respondsToSelector:`、`alloc`、`new` 按 selector 发送的一处都没有（`objc_opt_isKindOfClass` 3,369 处、`objc_opt_respondsToSelector` 2,977 处、`objc_alloc` 4,180 处、`objc_opt_new` 590 处），查它们的调用者结果是空的。本案把这些入口的调用记成它们代表的发送。

## 方案

**认哪些入口，记成什么。** 入口和 `objc_msgSend` 一样按 libobjc 里的位置认：经桩、GOT 或缓存共用的桩到达那里都算；桩跟不过去、只剩导入名时按名字认。

| 入口 | 记成的发送 |
|------|-----------|
| `objc_alloc` | `alloc` |
| `objc_allocWithZone` | `allocWithZone:` |
| `objc_alloc_init` | `alloc` 与 `init` 两条，同一条指令 |
| `objc_opt_new` | `new` |
| `objc_opt_self` | `self` |
| `objc_opt_class` | `class` |
| `objc_opt_isKindOfClass` | `isKindOfClass:` |
| `objc_opt_respondsToSelector` | `respondsToSelector:` |

**结果的形状不变，没有公开 API 改动。**

- 发送照旧是 `.messageSend(selector:receiver:)`，`kind` 是 `.call` 或 `.tailCall`，`isRuntimeHelperCall` 为 false，表里归在 `.selector(名字)` 下，`CodeReferenceIndex` 不用改。
- 和 `objc_msgSend` 一样，这处调用只记发送、不再同时记成对这个 C 函数的调用：按函数查 `_objc_alloc_init` 的调用者不再有结果。这些调用的 selector 永远已知，按 selector 查才是对的问法。
- 接收者按 `x0` 判断，和 `objc_msgSend` 相同（`methodReceiver`、`classLiteral`、`unknown`）。`objc_alloc_init` 的 `init` 发给刚分配出来的实例，不是 `x0` 里的类，接收者记 `.unknown`。给它一个「某类的新实例」的提示要往公开的 `ReceiverClassHint` 里加一个 case，RuntimeViewer 里对它的穷举 switch 会编不过，这次不做。
- `objc_opt_self`、`objc_opt_class` 调用之后 `x0` 照旧保留，类字面量接收者的识别不受影响。

**不认的入口。** `objc_retain`、`objc_release`、`objc_autorelease` 不算：ARC 插入的调用和 MRC 下源码里的 `[x retain]` 编出来的是同一个调用，分不开，继续当作 runtime helper。`swift_getInitializedObjCClass` 不是发送，只保留「原样返回传入的类」的处理。

**预筛。** `imageIndices(referencingSelector:among:)` 只看镜像的 `__objc_selrefs`，而一个镜像可能只经 `objc_alloc_init` 发送 `init`，`__objc_selrefs` 里根本没有 `init`。查上表里的 selector 时，导入了对应入口符号（`_objc_alloc_init` 等）的镜像也留下，定义这些入口的 libobjc 也留下。

**测试。** 测试里现场编一个 Objective-C dylib，覆盖上表每个入口，断言每处调用记成对应的发送；修改前这些调用是对 libobjc 函数的 `.function`。预筛另测这个一个 selector 引用都没有的镜像，八个 selector 的预筛都留下它；整个缓存上的预筛测试加上 `isKindOfClass:`（AppKit 里它只经 `objc_opt_isKindOfClass` 发送）。

**影响。** 查这些 selector 的调用者，结果会多出很多；按函数查这些 C 入口的调用者，结果会消失。RuntimeViewer 不用改代码，发版说明里要写这个行为变化。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-27 | Created as Draft | 2026-10-27 的审查发现，查 selector 的调用者会漏掉经 libobjc 专用入口的发送，AppKit 里查 `init` 漏掉约 78% |
| 2026-10-27 | `objc_alloc_init` 记 `alloc` 与 `init` 两条发送 | 它就是 `[[cls alloc] init]`，查 `alloc` 和查 `init` 的人都该找到它 |
| 2026-10-27 | 只记发送，不同时记成对 C 函数的调用 | 与 `objc_msgSend` 的处理一致；同时记两种会让每处调用多一条引用，按函数查这些入口的需求又几乎不存在 |
| 2026-10-27 | `init` 的接收者记 `.unknown`，不加新的接收者提示 | 新 case 是公开 enum 的破坏性改动；`.unknown` 不失真 |
| 2026-10-27 | 不认 `objc_retain` / `objc_release` / `objc_autorelease` | ARC 插入的调用与源码里的发送分不开 |
| 2026-10-27 | 用户批准，状态改为 Accepted | — |
| 2026-10-27 | 实现完成，状态改为 In Progress | 修复前 16 个用例全部失败、修复后通过；全量测试在 JHs-Mac-Studio-Ultra 上通过。合入 `next` 时取号并改为 Implemented |
| 2026-10-27 | 合入 `next`，取号 0076，状态改为 Implemented | 与方案只有一处不同：预筛除了导入这些入口的镜像，也留下定义它们的 libobjc。模块文档的「libobjc 的发送入口」一节就是实现说明，不另写使用指南；没有新术语要登记。没做完的项：无 |
