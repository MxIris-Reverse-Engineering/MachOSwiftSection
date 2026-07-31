# 2026-07-31 Leaf 迁移回归整批修复（差分验证）

## 问题

[LeafMigrationRegressionAudit.md](../LeafMigrationRegressionAudit.md) 审计出的 7 个
存活问题需要全部修复，用户的硬性要求：**重构后的逻辑必须与重构前一致**，且要用
「同一个测试在重构前提交跑一次、重构后再跑一次」的方式对比证明，同时补强测试覆盖。

## 调研

1. **行为基准提取**：从 `aa233bc^`（interface 路径基准）与 `ebb04d3^`（字段引擎
   基准）提取全部旧实现：`MultiPayloadEnumDescriptorCache`（整循环 do/catch 发布
   部分 map）、`TypedDumper` 的 `@Loggable` + `emitNestedFieldOffsetDepthLimitWarning`、
   `StructDumper.fields` / `EnumDumper.fields` 的 `try` 契约与 `!mangledTypeName.isEmpty`
   payload gating、`ProtocolConformanceDumper.protocolName` 的 nil-塌缩语义、
   `printTypeDefinition` 的 `try await dumper.fields` 传播。
2. **关键发现**：`printField` / `printEnumCase`（吞错 + 文本判 payload）在 `aa233bc^`
   就逐字存在——它们是 diff 渲染器的原语。leaf 迁移的问题不是「这些原语写错了」，
   而是把主 interface 路径**改道**到了这些 diff 原语上。因此正确修法是主路径恢复
   throwing + mangled-name gating，diff 路径的原语保持原契约不动。
3. **意外状况**：主工作区被并行会话用于 NodeStore 迁移（staged → reset → 重新落地，
   期间 `FieldDefinition.typeNode` 一度变为 `NodeReference`）。为避免互踩，全部修复
   改在独立 worktree `fix/leaf-migration-regressions` 分支（基于 `d9612cd`）进行。

## 最终方案

见 [LeafMigrationRegressionFixes.md](../LeafMigrationRegressionFixes.md)（7 项修复的
完整清单与语义依据）。要点：缓存恢复进 `SwiftDeclarationRendering` 供两路共享；
`storedFieldComments` / `enumCaseComments` / `renderModelFields` 全链 `throws` 化；
新增 `printThrowingEnumCase`（mangled-name 判 payload）；extension 子句恢复
nil-塌缩/抛错-丢弃二分；`#log` 恢复且沿用旧 subsystem/category；死代码删除 + 钉值
测试改指活值。

## 差分 harness（可复现）

独立 SPM 包，同一份 `Harness.swift` 分别以 `.package(path:)` 指向旧提交 worktree 与
修复后 worktree 构建（旧侧无 `SwiftDeclarationRendering` product，用
`#if canImport(SwiftDeclarationRendering)` 桥接 `DumperConfiguration` 的搬家）：

- **dump pass**：对每个 type descriptor 以全注释配置（field offset / type layout /
  enum layout / spare bit / expanded offsets）走 `Enum/Struct/Class.dump(using:in:)`，
  分隔行带类型名；`--skip <substring>` 跳过个别类型。
- **interface pass**：`SwiftInterfaceBuilder.prepare()+printRoot()`，固定 plain
  （旧提交在 noncopyable 元数据 + 注释开启下有当时未修的 SIGSEGV，且 printRoot 无
  per-type 跳过；注释面已由 dump pass 覆盖——重构前 interface 的注释本就来自同一套
  dumper）。
- **语料**：SymbolTestsCore fixture（366 类型，旧侧 `--skip Noncopyable --skip
  Invertible --skip WeakExistentialSubclass`）+ 现场编译的 `EdgeCaseFixture.dylib`
  （Void payload、tagged/spare-bits 多 payload、indirect、引用存储、嵌套 struct、
  泛型等 13 类型）。
- **运行**：`differential-harness <镜像绝对路径> <MachOImage 查找名> [--plain]
  [--skip 子串]...`，stdout 重定向成文件后逐对 diff；另有 python 脚本按类型统计
  四类注释块（enum layout / field offset / type layout / spare bit）的存在性。

### 结果

| 对比 | diff 行数 | 判定 |
| --- | --- | --- |
| edge plain：`aa233bc^` vs 修复后 | **0** | 逐字节一致（修复前差 6 行 = Void 括号回归） |
| fixture plain：同上 | 20 | 全部为 SE-0452 整数泛型实参打印的有意修复 |
| edge / fixture comments：同上 | 259 / 696 | 全部为枚举布局注释措辞的有意演进；注释块存在性 371/371 类型一致 |
| 修复前 vs 修复后（当前代码自身） | 仅 edge 语料 Void 括号 ×2 遍 | 修复零附带输出变化 |

### Harness 源码（重跑用）

`Package.swift`（旧侧把 path 与 `package:` 标签换成旧 worktree / `prerefactor`，
且去掉 `SwiftDeclarationRendering` product 行）：

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "differential-harness",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "<被测 checkout 的绝对路径>"),
        .package(url: "https://github.com/MxIris-Reverse-Engineering/MachOKit.git", from: "0.46.100"),
        .package(url: "https://github.com/MxIris-Reverse-Engineering/swift-demangling", from: "0.4.0"),
        .package(url: "https://github.com/MxIris-Reverse-Engineering/swift-semantic-string", from: "0.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "differential-harness",
            dependencies: [
                .product(name: "MachOSwiftSection", package: "<目录名>"),
                .product(name: "SwiftDump", package: "<目录名>"),
                .product(name: "SwiftDeclarationRendering", package: "<目录名>"),
                .product(name: "SwiftPrinting", package: "<目录名>"),
                .product(name: "SwiftInterface", package: "<目录名>"),
                .product(name: "MachOKit", package: "MachOKit"),
                .product(name: "Demangling", package: "swift-demangling"),
                .product(name: "Semantic", package: "swift-semantic-string"),
            ]
        ),
    ]
)
```

`Sources/differential-harness/Harness.swift` 与本报告同批归档在会话 scratchpad；
核心结构（详见 LeafMigrationRegressionFixes.md 的方法节）：dlopen → `MachOImage(name:)`
→ `setvbuf(stdout, nil, _IOLBF, 0)`（崩溃点精确归因）→ dump pass（`--skip` 过滤，
每类型 do/catch 打 `DUMP ERROR:`）→ interface pass（plain）。

### 踩坑记录

- **SwiftPM 增量构建不认路径依赖里新增的源文件**：fixwork 新增
  `MultiPayloadEnumDescriptorCache.swift` 后，harness 包的增量构建持续报
  "cannot find in scope"（fixwork 自身构建正常），`rm -rf .build` 全量重建才解决——
  与 AGENTS.md 记载的 MachOSymbols 陈旧链接问题同族。管道 `swift build | grep`
  会吞退出码，害得一版「修复后」输出实际来自旧二进制（收敛 diff 全 0 的假象），
  改为独立校验二进制存在 + 时间戳后发现。
- **旧提交自身的崩溃**：`aa233bc^` 在 noncopyable/~Copyable 类型上开注释 dump 会
  SIGSEGV 且崩溃点随内存状态漂移（疑似元数据实体化的内存破坏，后续版本已修）；
  块缓冲让崩溃归因错位，`setvbuf` 行缓冲后定位到确切三类，`--skip` 跳过。
- **zsh 不分词未加引号的变量**：`$SKIPS` 展开成单参数导致 usage 报错；改逐字传参。
- **`#expect` 消息闭包不支持 async 调用**：`node.print(using:)` 不能内联在消息里。

## 执行与验证

- 代码：`SwiftDeclarationRendering` 3 文件（新缓存 + backend + facade/协议）、
  `SwiftPrinting` 3 文件、`SwiftDump` 5 文件（3 个 dumper 加 `try`、2 处死代码删除）、
  `Package.swift`（SwiftDeclarationRendering 依赖 + SwiftPrintingTests 依赖）。
- 测试：新增 2 个 Suite（缓存 3 项、括号对偶 2 项）+ 钉值测试改指活值；全量
  `swift test --skip IntegrationTests` 见下方结论。
- 文档：LeafMigrationRegressionFixes.md（新）、审计文档状态标注、演进日志 §22、
  README 索引、AGENTS.md SwiftPrinting/渲染条目补注、本报告。

## 偏差

- 差分对比的 interface pass 固定 plain（旧提交崩溃所迫）；注释行为的等价性由
  dump pass（两路共用引擎/dumper）+ 新增单元测试覆盖，未留盲区。
- 审计 #5 的修复恢复了「悬空 `extension Foo: `」旧形态——审计文档曾倾向新行为更干净，
  按用户「与重构前一致」的要求选择恢复；若日后想要占位注释形态，在
  `printExtensionHeader` 的塌缩分支上改一处即可。
