# 2026-08-02 · kind-9 accessor-function reference 渲染修复（层 0）

## 问题

PR #98 的 max 级 code review 报出：interface 路径对 Xcode 26.5 Testing.framework 输出 `indirect case valueAttached()` 与 `case type()`（空括号，`swiftc -parse` 拒绝），dump 路径同一 case 输出 `case type(accessor function at 750396)`。用户要求独立验证评审结论、查清触发机理、给出修法。

## 调研结论

- **不是 PR 新引入，也不是 leaf 迁移引入**：把迁移前（`aa233bc^`）构建出来对同一二进制跑 interface，除日志行外与 PR 分支输出逐字节一致，空括号两行同样存在。post-迁移 main 的「按渲染文本 gating」只是遮住了它（代价是 Void payload 回归）。
- **根因是渲染器缺 kind**：payload 的 mangled name 是 kind-9（`0x09`）symbolic reference——编译器判定部署目标的 runtime demangler 不认识该类型的 mangling（两个 case 都因 `~Copyable` 泛型需要 Swift 6.0 runtime，而 Testing.framework 向后部署），于是嵌入 metadata accessor thunk 指针而非类型名（`GenReflection.cpp` 的 `getTypeRefByFunction`）。离线不可解析，`MetadataReader` 存 thunk 文件偏移；Demangling 包的 `NodePrinter` 有兜底文案 `accessor function at N`，而 `SwiftPrinting` 的 `NodePrintable` 家族对该 kind 零处理、静默渲染为空串，叠加「mangled name 非空就加括号」gating 产出非法 Swift。
- 数字实证：750396/428216 分别落在 `TypeInfo._Kind` / `Event.Kind` 自身 metadata accessor 之后 16 字节的匿名 thunk 处（private linkage，被 strip）；payload 源码为 `Attachment<AnyAttachable>` 与 `any (~Copyable & ~Escapable).Type`（swift-testing 开源仓库核对）。

## 方案（三层解析阶梯，本次只做层 0）

详见 [AccessorFunctionReferenceRendering.md](../AccessorFunctionReferenceRendering.md)。层 0 = 占位渲染补齐（本次落地）；层 1 = 进程内经 `swift_getTypeByMangledNameInContext` 真解析（已记录挂接点，待做）；层 2 = 离线符号表还原 `get_type_metadata` thunk 符号（待验证可行性）。

## 实际执行（PR #98 分支追加）

1. `SwiftPrinting/NodePrintables/NodePrintable.swift`：`printNameInBase` 补 `.accessorFunctionReference` case，文案与 Demangling `NodePrinter` 逐字一致。
2. `SwiftDeclaration`：`FieldFlags.hasMangledTypeName`（`1 << 7`），`TypeDefinition.index` 从 record 捕获；`renderModelFields` 的 payload gating 改读 flag，`printThrowingEnumCase` 删去 `hasPayload:` 参数（消除按下标读 record 的隐式位置依赖）。
3. 双防护网：`printThrowingEnumCase` 与 `EnumDumper.fields` 在 payload 渲染为空串时退回裸 case，括号绝不包空。
4. 文档：新设计文档 + README 索引 + 演进日志 22 节补记 + LeafMigrationRegressionFixes §3 补充。

## 验证

- 新单测 `NodePrinterTests.typeNodePrinterAccessorFunctionReference`（合成 kind-9 节点钉兜底文案）；`EnumCaseRenderingParityTests` 全绿（Void payload 括号契约不受影响）。
- Testing.framework（arm64e）A/B：整文件 interface diff 仅三行变化——两个枚举 case 空括号修复之外，还顺带修出一处评审未发现的存储字段同源问题（`var _storage: ` 悬空冒号 → `var _storage: accessor function at 283740`）。三行均与 dump 路径拼写逐字一致。

## 后续补充（同日）

- **与重构前基线的全量 A/B**：以 `a583aa8`（`47b5961^`）为基线、对齐本地依赖（`USING_LOCAL_DEPENDENCIES=1` + 四个兄弟目录）与同一 fixture 后：dump 两语料 0 diff；interface 差异恰为 kind-9 修复（3 处）+ SE-0452 integer 节点修复（6 处），无未解释差异。期间定位并修复了本机 fixture 二进制过期导致的 8 个快照假失败（环境问题，与任何分支无关），两类环境漂移排查已写入 AGENTS.md。
- **fixture 覆盖补齐**：`SymbolTestsCore` 新增 `AccessorFunctionReferences` 命名空间（always-noncopyable 字段的 capability-check 路径，部署目标无关），四个形态各就位；`accessorFunctionReferencesSnapshot` + 整模块 interface 快照经 `normalizingAccessorFunctionOffsets` 偏移归一化保持重建稳定；`actors` / `builtinTypeFields` 两份快照因二进制布局平移重录（经核对为纯排序差异）；ABI 字面量基线按 AGENTS 流程重生成（59 文件、102 行对称替换，全部为偏移值）。
- **Void payload fixture 覆盖**：`Enums.swift` 新增 `VoidPayloadEnumTest`（`case unitPayload(Void)` + `indirect case indirectUnitPayload(Void)` + Int payload + 裸 case），把审计 #3 的括号契约从「测试二进制 in-process fixture」扩展到离线（`MachOFile`）快照两路——dump/interface 均渲染 `case unitPayload()`；`enums` 与整模块 interface 快照重录（diff 即新类型本身），基线随布局偏移重生成。

## 偏差与遗留

- `case type(accessor function at 750396)` 仍非合法 Swift——离线诚实标注（与 dump 历史行为一致），可编译性需层 1/层 2。
- 层 1/层 2 未实施，已连同挂接点、风险评估、验证前置记录在设计文档中。
- `any (~Copyable & ~Escapable).Type`（组合带 inverse 的 existential metatype）在 fixture 的 macOS 26 部署目标下不触发 kind-9，覆盖它需要低部署目标的独立 target——记录在设计文档，未做。
