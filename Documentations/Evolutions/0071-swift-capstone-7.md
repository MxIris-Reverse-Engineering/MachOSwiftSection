# 0071 - 迁到 swift-capstone 7.0

- **状态**: Implemented
- **创建日期**: 2026-10-17
- **最后更新**: 2026-10-17

## 摘要

swift-capstone 7.0 用按架构泛型的不可复制引擎 `Disassembler<AArch64>` 取代 6.x 的 `Capstone` 类与
`Instruction` 类层级，旧 API 直接删除、不留过渡垫片。方案由 swift-capstone 仓库的提案《用新 Swift 特性重写
封装层》（`Documentations/Evolutions/0003-rewrite-with-modern-swift.md`）决定，其中约定
本库与 swift-decompiler 同批迁移。本库只有 `SwiftThunkAnalysis` 的 `CapstoneThunkDecoder.swift` 用到
Capstone，迁移只改这一个文件，对外接口不变。

## 方案

- 每次 `decode` 建一个 `Disassembler<AArch64>`（创建很便宜，引擎不跨任务共享），在 `forEachInstruction` 的
  闭包里把每条指令直接转成 `ThunkInstruction`。swift-capstone 借出的指令视图带不出闭包，不再先拿一整组
  Capstone 指令对象。`decode` / `decodeFunction` 的签名与 `Data` 入参不变。
- 别名：改用 `alias`（`.aliasMov` → `.mov`，`.aliasCmp` → `.aliasCmp`，其余用 `identifier`），取代
  「`(instruction, mnemonic)` 配对」。
- 写回：改用 `writesBackBaseRegister`，取代 `isPostIndex == true || operandsString.contains("]!")`。
  `isPostIndex` 不再是可选值。
- 写寄存器：`registersAccessed().written + implicitRegistersWritten`，与 6.x 的
  `registersAccessed.written + registersAccessedImplicitly.written` 同义。
- 依赖：下限从 `from: "6.0.1"` 改成 `from: "7.0.0"`。7.0.0 发布之前本分支只能对着本地 swift-capstone
  编译，所以等它发布才合入 `next`。

没有询问就采用的假设：不在本库加新测试——`CapstoneThunkDecoderTests` 与整个 `SwiftThunkAnalysisTests`
已经用真实指令编码固定了解码结果，迁移前后应完全一致。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-17 | Created，直接进入实现 | swift-capstone 的重写提案已获用户批准（「可以，按你说的开工」），其中要求两个下游同批迁移；本库的改动只是跟随，走精简提案。 |
| 2026-10-17 | 本地验证通过，等 swift-capstone 7.0.0 发布 | 在分支 `feature/swift-capstone-7` 上，对着本地 swift-capstone（`feat/rewrite-modern-swift`）编译：用 `swift package edit` 只在 agent 的构建目录里覆盖依赖，不碰 `.worktrees/` 下共享的链接——加一个 `swift-capstone` 链接会让其他 worktree 的本地构建也切到 7.0 API。Swift 6.4.2 下 `SwiftThunkAnalysisTests` 82 个测试，以及间接用到解码器的 `ObjCMemberDumpTests`、`OpaqueWitnessDumpAnnotationTests`、`ObjCMemberRecoveryTests`、`CustomObjCClassNameInterfaceTests`、`AccessorFunctionReferenceRewriterTests` 共 52 个测试，原始退出码都是 0；随后全量 `swift test --skip IntegrationTests` 共 2450 个测试 / 470 个套件全部通过，原始退出码 0。fixture 链 `next` worktree 的 `Tests/Projects/SymbolTests/DerivedData`。 |
| 2026-10-17 | swift-capstone 7.0.0 发布，依赖下限改成 `from: "7.0.0"`；In Progress → Implemented，编号 0071，合入 `next` | 7.0.0 要求 capstone fork 6.0.101，后者修了两处上游缺陷：`cs_disasm_iter` 不清每条指令的标志、自定义助记符截坏别名。新鲜构建目录，`USING_LOCAL_DEPENDENCIES=1`（MachOKit 等仍链 `.worktrees/` 下的兄弟仓库），swift-capstone 从远端解析到 7.0.0、capstone 到 6.0.101：全量 `swift test --skip IntegrationTests` 共 2450 个测试 / 470 个套件全部通过，原始退出码 0。解析时撞上 SwiftPM 的 manifest 缓存：此前 `swift package edit` 让 swift-capstone 的 manifest 在本地路径下求过值，内容与 7.0.0 相同，缓存把那次的结果——指向本地 capstone 的路径依赖——套到了远端 7.0.0 上，解析报 `capstone` 无法解析；加 `--manifest-cache none` 即通过。编号取远程共享分支（`main`、`next`）提案编号最大值 0070 加 1。不另写使用指南或实现说明：解码边界已写在 `Modules/SwiftThunkAnalysis.md`；没有新术语。 |
