# 2026-05-16 - Fix SwiftInterface print path DAG explosion

- **日期**: 2026-05-16
- **任务**: Fix SwiftInterface print path DAG explosion
- **作者**: Mx-Iris
- **仓库**: https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection.git

## 1. 问题 / 任务

用户反馈集成测试 `SwiftInterfaceBuilderTestSuite.DyldCacheTests.buildFile` 在加载 `dyld_shared_cache_arm64e` 中的 `SnippetUI` 镜像时出现"死循环"。提供堆栈日志 `/Users/JH/Desktop/swift-section-backtrace-all.log`，要求查清根因并修复，参考 Apple Swift 源码做法。

## 2. 探索与调研

### 调研内容

- 读取并分析堆栈日志 `swift-section-backtrace-all.log`（423 行，含 ~500 帧深的 `BoundGenericNodePrintable` 嵌套）
- 查看测试入口 `Tests/IntegrationTests/SwiftInterface/SwiftInterfaceBuilderTests.swift`
- 查看打印协议链：`Sources/SwiftInterface/NodePrintables/{NodePrintable,InterfaceNodePrintable,TypeNodePrintable,BoundGenericNodePrintable}.swift`
- 查看 4 个 conformer：`Sources/SwiftInterface/NodePrinter/{Type,Function,Variable,Subscript}NodePrinter.swift`
- 查看 dump 入口 `Sources/SwiftDump/Dumper/AssociatedTypeDumper.swift`（`mergedRecords` + `OpaqueTypeRewriter` + `OpaqueTypeGenericParameterRewriter`）
- 查看 `swift-demangling/Sources/Demangling/Node/Node+Rewriter.swift`（post-order rewrite，`visit` 返回值不再 rewrite）
- 查看 `swift-demangling/Sources/Demangling/Node/Printer/{NodePrinter,NodePrinterTarget}.swift`
- 查看 `swift-semantic-string/Sources/Semantic/SemanticString.swift`（`append(_:)`、`subscript(range:)`、`components` lazy fold）
- 查看 `MetadataReader.demangleType` 与 `MetadataReaderCache`、`MangledName` 解析
- 在 `mergedRecords` 与 `OpaqueTypeRewriter.visit` 中加诊断日志（三轮迭代，最后用文件 logger `AssociatedTypeDumperDiagLogger` 绕过 swift testing 的 stdout buffer），跑 `swift test --filter "SwiftInterfaceBuilderTestSuite.DyldCacheTests/buildFile"` 复现
- 用 `sample <pid>` 多次抓取卡住进程的堆栈，确认嵌套位置始终在 `BoundGenericNodePrintable.printBoundGenericNoSugar` → `printChildren` → `printSequence` → `printName` → `printNameInType` → `printFirstChild` → `printOptional` → `printName` 循环
- 阅读 Apple 源码 `swift/lib/Demangling/NodePrinter.cpp`（`MaxDepth` 检查 line 1416）、`swift/include/swift/Demangling/Demangle.h`（`MaxDepth = 768` line 909）、`swift/lib/Demangling/Demangler.cpp`（`demangleMultiSubstitutions` 直接返回共享 `NodePointer`，line 1198）、`swift/include/swift/Demangling/ManglingUtils.h`（`MaxRepeatCount = 2048`）

### 关键发现

- 卡住 record 的诊断数据：`name=Body`、`mangledNameSize=320`（字节流 240 字节）、demangle 后 `depth=41 / unique=246 / maxRepeat=19`、`OpaqueTypeRewriter` 解析 3 个 opaque type 后 `depth=41 / unique=255 / maxRepeat=19`
- mangle name 中含 11 个 `0x02` symbolic-reference 字节 + 17 个 substitution 反向引用（`AC / AJ / AK / AP / AR / AT / AV / AY / A0_ … A25_`），`A25_` 已经回引到第 25 个 substitution
- demangle 出的不是 tree 而是 **DAG**：substitution 共享同一个 `Node` 实例（来自 swift-demangling `Demangler` 的设计，与 Apple 行为一致）
- `TypeNodePrinter` / `NodePrintable` 链按 `children` 朴素递归，没有共享节点去重 → DAG 被当 tree 完整展开 → `_measureExpansion` 实测 **394 062 节点访问**
- 这不是真正的死循环：22 分钟 CPU 仍在跑、`<<too complex>>` fallback 始终未触发，单条 root-to-leaf 路径深度只有 ~100，远小于任何合理阈值
- Apple `swift demangle` 命令面对同样 mangle 也会卡——它只在单条路径深度 > 768 时输出 `<<too complex>>` 兜底，对 DAG 共享展开慢这件事**没有处理**
- `swift-demangling` Swift port 的 `NodePrinter` 也没有 MaxDepth 兜底，但本仓库的死循环路径不经过它（仓库自定义 `TypeNodePrinter`）
- `SemanticString` 天然支持 `append(_:)` 与 `subscript(range:)`，可以用作 memoization 的缓存值；`NodePrinterTarget` 协议本身没有 append API，需要在仓库内通过 `where Target == SemanticString` 限定
- 4 个 conformer (`TypeNodePrinter` / `FunctionNodePrinter` / `VariableNodePrinter` / `SubscriptNodePrinter`) 全部使用 `SemanticString` 作为 `Target`，约束不会破坏现有代码

### 候选方案

| 方案 | 优点 | 缺点 |
|------|------|------|
| A. Print 阶段 visited 集合 + 占位符 | 实现最简，能彻底防死循环 | 共享类型只展开第一次，后续输出占位符，类型显示不完整 |
| B. SemanticString memoization（首次完整 print + 缓存片段，后续复用） | 输出完整、O(unique nodes) 复杂度、兼具兜底功能 | 需要给 NodePrintable 加缓存状态 + 限定 `Target == SemanticString` |
| C. `mergedRecords` 局部 expansion-size cap + 降级输出 | 最小改动、不影响其它路径 | 仅保护 `mergedRecords` 一处入口，覆盖面窄 |
| D. Apple-style MaxDepth=768 单一兜底（仅项 1 完成） | 与 Apple 完全一致、抗病态深嵌套 | 当前 case 路径深度只有 ~100，触不到阈值，对本死循环无效 |

## 3. 最终方案

用户最终选 **方案 B + 同时保留 Apple-style MaxDepth 兜底（D）**，思路：

1. 模仿 Apple `swift/include/swift/Demangling/Demangle.h:909` 与 `NodePrinter.cpp:1416` 加 `maxPrintDepth = 768` 单条递归路径深度兜底，超阈值输出 `<<too complex>>` 并 return（防御未来病态 mangle）
2. 在 `InterfaceNodePrintable.printName` 入口加 DAG memoization：
   - 缓存键 `ObjectIdentifier(name)`，缓存值 `SemanticString`
   - 仅在 default-context (`!asPrefixContext && context == nil && dependentMemberTypeDepth == 0`) 下读写缓存，避免 context-dependent 输出污染
   - 命中：`target.append(cached)` 直接返回
   - 未命中：`swap(&target, &subTarget)` 重定向到 fresh sub-target，dispatch 完成后写回主 target 并把 sub-target 缓存
3. 把缓存类型与 `target.append(_:)` 操作收进 `extension InterfaceNodePrintable where Target == SemanticString`，4 个 conformer 都满足约束
4. 4 个 conformer 各加 `var printDepth: Int = 0` + `var printCache: [ObjectIdentifier: SemanticString] = [:]` stored property
5. 不改 `swift-demangling`：Demangler 的 substitution 共享行为与 Apple 一致，是正确设计；该模块的 NodePrinter 也未参与本死循环路径

## 4. 实际执行与改动

### 改动清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `Sources/SwiftInterface/NodePrintables/NodePrintable.swift` | 修改 | 加 `import Semantic`；协议加 `var printDepth: Int { get set }` 与 `var printCache: [ObjectIdentifier: SemanticString] { get set }`；extension 提供 `static var maxPrintDepth: Int { 768 }`，注释指向 Apple `Demangle.h:909` |
| `Sources/SwiftInterface/NodePrintables/InterfaceNodePrintable.swift` | 修改 | `printName` 实现限定 `where Target == SemanticString`；入口先做 `printDepth > maxPrintDepth` 兜底输出 `<<too complex>>`；default-context 下走 cache 命中复用或 `swap(&target, &subTarget)` 捕获子 target 后缓存；非 default-context 走原 dispatch；原 dispatch 抽到 `private mutating func dispatchPrintName` |
| `Sources/SwiftInterface/NodePrinter/TypeNodePrinter.swift` | 修改 | 加 `var printDepth: Int = 0` + `var printCache: [ObjectIdentifier: SemanticString] = [:]` |
| `Sources/SwiftInterface/NodePrinter/FunctionNodePrinter.swift` | 修改 | 同上 |
| `Sources/SwiftInterface/NodePrinter/VariableNodePrinter.swift` | 修改 | 同上 |
| `Sources/SwiftInterface/NodePrinter/SubscriptNodePrinter.swift` | 修改 | 同上 |

`git diff --stat` 输出：6 files changed, 80 insertions(+), 1 deletion(-)。

### 关键命令

```
swift test --filter "SwiftInterfaceBuilderTestSuite.DyldCacheTests/buildFile"
swift test --skip IntegrationTests
```

调研期间还使用 `sample <pid>` 多次抓取卡住进程的堆栈以及 `MetadataReader.demangleType` + `OpaqueTypeRewriter` 加临时诊断日志（已清理，最终改动只剩上面 6 个文件）。

### 验证

- 卡死的 case：`Test buildFile() passed after 5.563 seconds.`（之前 22+ 分钟 CPU 仍跑不完）
- 完整测试套件：`Test run with 1003 tests in 191 suites passed after 78.061 seconds.`（0 失败）
- `<<too complex>>` 兜底在该 case 中没有触发——证明 memoization 已经把 print 复杂度从 394 062 节点访问降到 ~unique 节点级别，单条路径远未触及 768 阈值

### 与原方案的差异

无，与最终方案一致。调研期为了诊断在 `AssociatedTypeDumper.swift` 临时加过 `_logFlushed` / `_measureNode` / `_measureExpansion` / `AssociatedTypeDumperDiagLogger` 等辅助代码，定位到根因后已全部还原（`git diff Sources/SwiftDump/` 为空），最终落库的改动只在 `Sources/SwiftInterface/` 的 6 个文件内。
