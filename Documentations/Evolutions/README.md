# Evolution Proposals

- **项目类型**: 库（源码分发）—— SPM library product，下游仓库（RuntimeViewer、MachOKitUI、SymbolViewer 等）从源码重编译，无 ABI 约束，但每次公开 API 变更必须评估源码兼容性。`swift-section` 可执行产物是配套 CLI，不是对外契约。（完整声明见 [`Documentations/README.md`](../README.md) 头部。）

所有非平凡变更以提案形式落盘，一次改动 = 一份提案文件，从调研到落地全生命周期原地更新。状态机：`Draft` → `In Review` → `Accepted` → `In Progress` → `Implemented`，另有 `Rejected` / `Deferred` / `Withdrawn`；被否的提案保留不删。

**编号在落地时分配**（2026-08-24 起，成因：多线并行下创建期取号必撞——0008→0009、0009→0010 各让位一次，opaque 归属提案 0005→0006→0011 两次改号）：创建期文件名用 `draft-<slug>.md` 不占号、状态表编号列写 `draft`；合入长寿命共享分支（main / next）的落地 commit 里 fetch 全部远程共享分支、取 `Evolutions/` 编号全局最大值 +1，改名与互链同批完成。残余撞号以先推上共享分支者为准。in-flight 提案用 slug 引用；**代码与 fixture 注释引用提案只用 slug，不写编号**。演进账本 ProjectEvolutionLog 的节号同规则落地时取。存量 0001–0011 不动。

| # | 标题 | 状态 |
|---|------|------|
| [0001](0001-symbol-name-offsetization.md) | SymbolIndexStore 符号名 offset 化：驻留字符串换字符串表引用 | Implemented |
| [0002](0002-declaration-model-descriptor-slimming.md) | 声明模型 descriptor 化：TypeDefinition / ExtensionDefinition / ProtocolDefinition 不再驻留急切解析的胖 wrapper | Implemented |
| [0003](0003-symbol-row-bucket-flattening.md) | SymbolIndexStore `[UInt32]` 行号桶扁平化：单元素桶内联化 | Implemented |
| [0004](0004-arm64e-signed-vwt-pointer-hardening.md) | arm64e 签名 VWT 指针加固：进程内裸读 strip + 真 PAC 环境的回归验证形态 | Implemented |
| [0005](0005-event-based-degradation-reporting.md) | 降级上报统一走事件：库侧不再自选落点，Dispatcher 兜底零 handler | Implemented |
| [0006](0006-final-keyword-and-lazy-accessor-type-recovery.md) | `final` 成员关键字还原与 lazy var 访问器类型修正（issue #106 §1/§4） | Implemented |
| [0007](0007-extension-container-dedup-and-default-impl-attribution.md) | Extension 容器索引期去重与协议默认实现归属标注（issue #106 §5） | Implemented |
| [0008](0008-interface-header-and-export-status-annotations.md) | Interface 文件头部与导出状态标注（issue #106 §2/§3/§8） | Implemented |
| [0009](0009-type-indexing-revival.md) | TypeIndexing 重启：`__C` 类型模块归属解析的索引管线修复与重构（两线合并时由 0008 重排至 0009，见提案「编号说明」） | Implemented |
| [0010](0010-community-type-mapping-bundles.md) | 补充类型映射：私有框架 `__C` 类型的用户自备 APINotes 加载（AttributeGraph 等；合并时由 0009 重排） | Implemented |
| [0011](0011-opaque-primary-associated-type-attribution.md) | opaque 返回类型的 primary associated type 归属：anchor 协议裁决 + 协议事实解析链（main 直落线并入 next 时由 0006 重排） | Implemented |
| [0012](0012-in-process-metadata-type-builder.md) | RuntimeMetadataTypeBuilder：TypeBuilder 的首个生产 conformer，node → 进程内活 metadata | Implemented |
| [0013](0013-swift-evolution-interface-builder.md) | SwiftEvolutionInterfaceBuilder：ABI 演进的并集注解接口渲染（`evolution --interface`） | Implemented |
| [0014](0014-unify-interface-renderers.md) | 统一 diff / evolution 接口渲染器的结构遍历核心（顺带修 diff accessor 双重缩进） | Implemented |
| [0015](0015-type-name-resolver-role-split.md) | TypeNameResolvable 角色化拆分：printer 查询解析器按能力分协议 | Implemented |
| [0017](0017-macho-dependencies-module.md) | 依赖闭包下沉为 MachODependencies 模块：两套依赖加载合一 | Implemented |
| [0016](0016-exported-only-interface.md) | Interface 只打印导出声明（`--exported-only`）：提案 0008 标注的过滤形态，打印期按描述符 / 派生符号 / 扩展目标裁决 | Implemented |
| [0018](0018-self-contained-abi-layer.md) | ABI 层自包含：MachOSwiftSection 不再依赖符号索引——描述符只暴露实现地址，符号查询上移 SwiftInspection，值类型下沉 MachOResolving | Implemented |
| [0019](0019-large-stack-executor-and-cross-version-parallelism.md) | 大栈任务执行器接入与跨版本并行准备：打印路径零线程跳转（执行器本体在 swift-demangling 0014），diff / evolution 多版本并行 | Implemented |
| [0020](0020-vtable-slot-attribution-via-method-descriptor-symbols.md) | vtable 槽归属改用 method descriptor 符号：ICF 折叠下的错名修正与墓碑槽还原 | Implemented |
| [0021](0021-metadata-reader-deterministic-node-extraction.md) | MetadataReader 符号引用解析去搜索化：ObjC protocol 引用与 extension 目标按 ABI 固定形状取节点，删掉靠深度优先搜索碰运气的 `typeSymbol` / `extensionSymbol` | Implemented |
| [0022](0022-rename-metadata-reader-to-symbolic-demangler.md) | `MetadataReader` 改名为 `SymbolicDemangler`：它只做 symbolic reference 回镜像解析的 demangle，与 metadata 记录无关；留一个 deprecated typealias 过渡 | Implemented |
| [0023](0023-type-import-info-identity.md) | 读取 TypeImportInfo，按运行时 `_swift_buildDemanglingForContext` 的规则给 C 导入类型定名字和种类：ABI 名覆盖、typedef 改 typeAlias、C tag 枚举改 structure、关联实体包 relatedEntityDeclName | Implemented |
| [0024](0024-exported-declaration-flag.md) | Type / Protocol Definition 的导出标志：四态 `ExportStatus` 下沉到声明模型，索引期无条件填充 | Implemented |
| [0025](0025-key-path-component-and-property-descriptor.md) | Key path component header 与 property descriptor 的 ABI 模型：`…vpMV` 符号指向的那段常量按 key path component 编码解析，四种形态（trivial / 内联偏移 / 元数据内偏移 / computed）齐全 | Implemented |
| [0026](0026-missing-abi-structures.md) | 补齐五组缺失的 ABI 结构：async / coro function pointer 记录、capture descriptor（`__swift5_capture`）、generic metadata pattern 家族、accessible function record（`__swift5_acfuncs`）、function type metadata 尾随对象 | Implemented |
| [0027](0027-locatable-layout-wrapping-macro.md) | `@LocatableLayoutWrapping`：`LocatableLayoutWrapper` 三项存储级要求（`layout` / `offset` / `init(layout:offset:)`）收进宏，97 处手写样板一次性替换 | Implemented |
| [0028](0028-offline-opaque-accessor-thunk-resolution.md) | 离线解析不透明类型的 accessor thunk：SwiftUI 那 17 条渲染成裸地址的 `Body`，其 underlying type 是 availability-conditional 的 kind-9 thunk（版本检查 + 两分支各指一个类型）。用 Capstone 反汇编把两支都解出来，新增可选 target `SwiftThunkAnalysis`（SPM trait，默认关闭）；实测 17 → 5 | Implemented |
| [0029](0029-thunk-type-construction-evaluation.md) | accessor thunk 的类型构造求值：离线解掉最后的 kind-9 引用——thunk 是只用 metadata accessor / `swift_getWitnessTable` / mangled name 实例化写成的类型构造程序，按指令顺序做符号求值即可得到每一支的类型；SwiftUI 离线 6 → 0，field record 的 kind-9 走同一条路（0028 的延续） | Implemented |
| [0030](0030-standalone-file-thunk-resolution.md) | 独立文件上的 accessor thunk 解析：第三方 app、iOS 26 及更早的模拟器运行时这类不在 dyld cache 里的 Mach-O，跨镜像调用全走 GOT bind，求值器一失败，单查找回退就把中间值当答案（`OnModifierKeysChangedModifier.Body` 印成 `_TaskModifier2`）。收紧回退；bind 名经依赖镜像的 accessor 索引解析（新增 `DependencySearchPath.systemRoot` 与 RuntimeRoot 推断）；带符号的 bound-generic accessor 直接取符号里的类型。合并 accessor `…MaTm` 留给下一个提案 | Implemented |
| [0031](0031-merged-accessor-inline-evaluation.md) | 合并 accessor 的内联求值：SwiftUICore 剩下两个 `Mutex` 字段的 thunk 调的是编译器合并的 `…MaTm` 函数体（真正的 accessor 从 `x3` 传入，函数体只查缓存、`blr x3`），类型信息全在调用方寄存器里。求值器现在跟进本镜像内没名字的被调函数（带当前寄存器状态的子求值器）、解码 `blr`、把 GOT bind 槽读出来的函数指针当函数引用；可用性检查绝不跟进，递归不跟进，深度上限 3。iOS 26.5 模拟器与 macOS cache 的 SwiftUICore 未读 2 → 0 | Implemented |
| [0032](0032-cache-stub-islands-and-unmodelled-instructions.md) | cache 里的 stub island，和不认识的指令不再被跳过：iOS 设备 cache 的跨镜像调用是 `bl` 到镜像之间的跳板（读槽的 stub 或算地址的 island），环境对任何地址都认跳板并对目标再认一次；不认识的条件跳转放弃那一支（直行落点是 `brk` 的例外，按跳走）、不认识的指令作废它写的寄存器、PAC 指令保值。iOS 26.3.1 SwiftUI 7 → 0、SwiftUICore 2 → 0 | Implemented |
| [0033](0033-by-name-opaque-reference-expansion.md) | 按名字引用的 opaque 类型也展开：独立文件的 witness 用到别的镜像的 `some` 结果时只有一个 bind 名，demangler 解成 `opaqueReturnTypeOf`，dump 印 `<<opaque return type of …>>`，interface 更是把 conformer 印成 witness。rewriter 把描述符符号名重新 mangle 出来、按搜索路径定位镜像、在那个镜像里展开。iOS 26.5 模拟器 SwiftUI dump 207 行 witness → 0 | Implemented |
| draft | [AGENTS.md 瘦身：指令文件回归指令，架构细节回归文档](draft-agents-md-slimming.md) | Draft |
| draft | [FieldLayoutRenderable 不再继承 MachOSwiftSectionRepresentableWithCache：渲染能力与 reader 能力解耦，上层约束改用组合 typealias `MachOFieldLayoutRenderable`](draft-field-layout-renderable-decoupling.md) | In Progress |
| draft | [`Builtin.Borrow` 支持：Swift 6.4 新元数据种类的读取、进程内构建与静态布局](draft-builtin-borrow-support.md) | In Progress |
| draft | [`@_rawLayout` 人造字段、空名字 enum case 与静态布局的依赖搜索路径](draft-raw-layout-artificial-field-handling.md) | In Progress |
| draft | [interface 不打印编译器合成的成员：actor 默认存储与 property wrapper 的 `_x` / `$x`](draft-interface-hides-compiler-synthesized-members.md) | In Progress |
