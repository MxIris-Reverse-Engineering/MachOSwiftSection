# 2026-05-14 - Fix Conditional Invertible Protocols Region ABI Parsing

- **日期**: 2026-05-14
- **任务**: Fix Conditional Invertible Protocols Region ABI Parsing
- **作者**: Mx-Iris
- **仓库**: https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection (本次主要改动) 与 https://github.com/MxIris-Reverse-Engineering/RuntimeViewer (上游表现层)

## 1. 问题 / 任务

用户在 RuntimeViewer 的特化面板里选 `Swift.Result` 候选类型时,inner specialization request 必现报错:

```
Failed to fetch inner specialization request: Demangling.DemanglingError.matchFailed(wanted: "(read test function to succeed)", at: 0)
```

同一面板上 `Array` / `Optional` / `Dictionary` 都能正常展开。另外报错时 ViewController 还会残留一个 "Loading inner parameters…" placeholder row。

任务: 找到 `Swift.Result` 走不通的根因并修复,顺便修掉 placeholder 残留的对称漏洞。

## 2. 探索与调研

### 调研内容

- `RuntimeViewer/RuntimeViewerUsingAppKit/.../Specialization/SpecializationViewModel.swift` — 触发 inner fetch 的 catch 分支,定位 placeholder 残留是因为缺少 `reloadRowRelay.accept(row)`。
- `RuntimeViewer/RuntimeViewerCore/.../RuntimeSwiftSection.swift` `specializationRequest(forCandidateID:in:)` — 反查 candidateID 的入口。
- `RuntimeViewerCore/.../RuntimeEngine+GenericSpecialization.swift` `request {} remote {}` 路由 — 确认 `swiftSectionFactory.existingSection(for: candidate.imagePath)` 已经把 `self.machO` 绑到 candidate 自己的 image。
- `MachOSwiftSection/Sources/SwiftInterface/GenericSpecializer/GenericSpecializer.swift` — `makeRequest` → `buildParameters` → `collectRequirements` / `buildAssociatedTypeRequirements` → `paramMangledName + MetadataReader.demangleType` 的调用链。
- `MachOSwiftSection/Sources/MachOSwiftSection/Models/Generic/GenericRequirementDescriptor.swift` — 确认 `param: RelativeDirectPointer<MangledName>` 字段对所有 kind 都按 4-byte 偏移解析。
- `MachOSwiftSection/Sources/MachOSwiftSection/Models/Generic/GenericContext.swift` 两个 init 路径(Readable / ReadingContext) — 发现 `conditionalInvertibleProtocolsRequirementsCount` 当成**单个** UInt16 读且没有 4-byte align padding。
- `swift-demangling/Sources/Demangling/Main/Demangle/Demangler.swift` — `read(where:)` 是 `demangleIdentifier` 的入口,`at: 0` 强烈暗示输入字符串的第一个字节就不是数字 / endIndex。
- `swift-project/swift/include/swift/ABI/GenericContext.h` 上游 ABI 头文件 — 用 `TrailingObjects<...>` 列出顺序、`getNumConditionalInvertibleProtocolsRequirementCounts() = popcount(set.rawBits())`、`numTrailingObjects(GenericConditionalInvertibleProtocolRequirement) = counts.back().count`。
- `swift-project/swift/include/swift/ABI/InvertibleProtocols.h` 和 `swift/Basic/MathUtils.h` — `rawBits()` 是底层位掩码,`popcount` 数二进制 1 的个数。

### 关键发现

1. 错误信息 `matchFailed(wanted: "(read test function to succeed)", at: 0)` 唯一来源是 `Demangler.demangleIdentifier()` 第一行 `scanner.read(where: { $0.isDigit })`。`at: 0` 说明 demangler 一开始就在 endIndex 或者首字节非数字 → 几乎可以肯定喂进 demangler 的就是垃圾字节,不是合法 mangled name。
2. 走过 2 条错误假设(都被否定):
   - **假设 A**: `self.specializer` 绑到了 outer image,跨 image 读 stdlib 候选描述符时偏移错位。实测发现 `existingSection(for: candidate.imagePath)` 已经把 self.machO 绑到 candidate 自己 image,该方向是 no-op。
   - **假设 B**: `invertedProtocols` kind 的 `paramMangledName` 字段本身没有合法 mangled name 指针。但 `GenericSpecializationTests` 里所有 invertedProtocols 相关 fixture (`invertedCopyableExposed` 等) 都过,说明 main `requirements` 数组里的 `invertedProtocols` entry 是正常的。
3. 写复现测试 `swiftResultMakeRequestSucceeds` 直接驱动 stdlib 中的 `Swift.Result` makeRequest,稳定复现 `matchFailed at: 0`,排除上游(Wire / IPC / 绑定)路径,把问题压缩到 MachOSwiftSection 内部。
4. 加诊断测试 `swiftResultGenericRequirementsDiagnostic`,逐条 dump 每个 requirement 的 `flags.raw`、`param.relativeOffset`、`content.raw`、mangled bytes,并 dump conditional 区域起始 48 字节原始内容,看到:

```
@5771128: 03 00 02 00 04 00 00 00 05 00 00 00 92 eb fe ff ...
direct[0]   kind=protocol            paramMangled="q_"  demangle OK
direct[1]   kind=invertedProtocols   paramMangled="x"   demangle OK
conditional[0] kind=sameShape (?!)   paramMangled=garbage  demangle FAIL  ← 不该是 sameShape
conditional[1] kind=layout (?!)      paramMangled=garbage  demangle FAIL  ← 不该是 layout
```

5. 对照 Swift ABI (`swift/include/swift/ABI/GenericContext.h`):
   - Conditional 区域 trailing 顺序: `ConditionalInvertibleProtocolSet, ConditionalInvertibleProtocolsRequirementCount, TargetConditionalInvertibleProtocolRequirement`。
   - `numTrailingObjects(ConditionalInvertibleProtocolsRequirementCount) = popcount(set.rawBits())` — count 字段是 **数组**,长度等于 set 中置位 bit 数。
   - counts 是**累计**,最后一个 entry 是 total。
   - `TrailingObjects` 在每个段切换时按下一种类型的 `alignof` 自动塞 padding;`GenericRequirementDescriptor` 要求 4-byte 对齐。
6. 用 ABI 规则重新切 Result 的字节布局:

```
@5771128  03 00          set = 3 = {Copyable, Escapable}
@5771130  02 00          count[0] = 2 (Copyable 累计)
@5771132  04 00          count[1] = 4 (累计到 Escapable 即 total)
@5771134  ?? ??          padding 2 字节 -> 4 byte 对齐
@5771136  05 00 00 00 ...  req[0] kind=invertedProtocols  ✓
@5771148  05 00 00 00 ...  req[1] kind=invertedProtocols  ✓
@5771160  05 00 00 00 ...  req[2] kind=invertedProtocols  ✓
@5771172  05 00 00 00 ...  req[3] kind=invertedProtocols  ✓
```

   MachOSwiftSection 旧实现从 @5771132 开始读 req[0](错位 4 字节: 漏读 1 个 count + 漏 2 字节 padding + 多读一字 align 误差),后续 4 个 12 字节 entry 全部错位,paramMangledName 当 RelativeDirectPointer 解析得到指向乱码内存的偏移,demangler 在第 0 字节炸。
7. `Swift.Result` 触发但 `Array` / `Optional` / `Dictionary` 不触发的原因: 这些类型的 conditional invertible set 要么为空、要么 popcount=1。popcount=1 时只需读 1 个 count 且 cursor 落在 4 字节对齐位置,旧实现侥幸正确;popcount≥2 时 cursor 错位才暴露。`Result` 同时声明 conditional Copyable 和 Escapable,popcount=2,正好踩中。

### 候选方案

| 方案 | 优点 | 缺点 |
|------|------|------|
| A: 在 `collectRequirements` / `buildAssociatedTypeRequirements` 用 `try?` 跳过 demangle 失败的 entry | 改动最小,只动 GenericSpecializer | 症状治疗;掩盖 conditional 区域读错的事实;后续真出问题难定位;且不修 `conditionalInvertibleProtocolsRequirements` 解析,该字段对外 API 永远是垃圾 |
| B: 在 collectRequirements 等处显式 `if kind == .invertedProtocols { continue }` 跳过 | 比 A 略稳一点 | 仍是症状治疗;真正的 conditional 区域 entry 本应都是 invertedProtocols,但被错位后 kind 才显示成 sameShape/layout — 这条 guard 对修过的代码反而错杀正常 entry |
| C: 在 `GenericContext.swift` 按 Swift ABI 正确解析 conditional 区域 — count 数组 + popcount + 4-byte align | 根因修复;conditionalInvertibleProtocolsRequirements 对外 API 也变正确;GenericSpecializer 不用动 | 改动 2 个 init 路径;需要确认 baseline 测试不回归 |
| D: 把 `conditionalInvertibleProtocolsRequirementsCount` 改成数组类型暴露 cumulative API | 最贴近 Swift ABI 语义 | breaking API change,baseline fixture、生成器、字段名都要改;收益相对 C 不大 |

## 3. 最终方案

采用 **C**: 在 `MachOSwiftSection/Sources/MachOSwiftSection/Models/Generic/GenericContext.swift` 两个 init 路径(Readable 和 ReadingContext)按上游 ABI 正确解析 conditional invertible 区域。

外部 API 保持不变 — `conditionalInvertibleProtocolsRequirementsCount: InvertibleProtocolsRequirementCount?` 字段名和类型都不动,只把它的含义从「单字段读出的值」改成「count 数组的最后一项,即累计 total」。这样:

- 不破坏 baseline (`GenericContextBaseline.swift` 里所有 fixture 都是 0,没有 conditional invertible)。
- `conditionalInvertibleProtocolsRequirements: [GenericRequirementDescriptor]` 字段对外可用且内容正确。
- GenericSpecializer 不用任何 `try?` 防御 — 修过之后 conditional 区域里所有 entry 都是合法的 `invertedProtocols` kind,paramMangledName 解析也正常。

附带在 `Tests/SwiftInterfaceTests/GenericSpecializationTests.swift` 加一个回归测试 `swiftResultMakeRequestSucceeds`,直接用 stdlib `libswiftCore` 中的 `Swift.Result` 描述符跑 `makeRequest`,把这次的现场固化下来。

RuntimeViewer 那侧(本次任务的下游表现层)同时做两处小修复:

- `RuntimeViewerCore/.../RuntimeSwiftSection.swift` `specializationRequest(forCandidateID:in:)` 显式按 candidate 自己的 image 构造 `GenericSpecializer`(对当前 case 是 no-op,但跨 image 时是必需的;同时加一行 error log 方便后续排查)。
- `RuntimeViewerUsingAppKit/.../SpecializationViewModel.swift` catch 分支补 `reloadRowRelay.accept(row)`,让 outline view 在 inner request 失败时也把 placeholder 删掉(与成功路径对称)。

## 4. 实际执行与改动

### 改动清单

| 仓库 | 文件 | 操作 | 说明 |
|------|------|------|------|
| MachOSwiftSection | `Sources/MachOSwiftSection/Models/Generic/GenericContext.swift` | 修改 | 两个 init 路径都改成按 `popcount(set.rawValue)` 循环读 N 个 UInt16 count entry,保留最后一个作为 cumulative total,再 `cursor.align(to: 4)`,然后按 total 读 GenericRequirementDescriptor 数组 |
| MachOSwiftSection | `Tests/SwiftInterfaceTests/GenericSpecializationTests.swift` | 修改 | 在 `Make Request` suite 末尾新增 `swiftResultMakeRequestSucceeds`,通过 `allAllTypeDefinitions` 反查 stdlib `Swift.Result`,给 makeRequest,断言两个参数 `A` / `B` |
| RuntimeViewer | `RuntimeViewerCore/Sources/RuntimeViewerCore/Core/RuntimeSwiftSection.swift` | 修改(待提交) | `specializationRequest(forCandidateID:in:)` 用 `matchedEntry.machO` 构造 candidate-bound `GenericSpecializer`,并加一行错误诊断 log |
| RuntimeViewer | `RuntimeViewerUsingAppKit/.../Specialization/SpecializationViewModel.swift` | 修改(已 commit + push,SHA `3e3736b`) | catch 分支补 `self.reloadRowRelay.accept(row)` |

### 关键命令

```sh
# 触发复现并迭代调试 — MachOSwiftSection 内 Swift Package Manager
swift test --filter "swiftResultMakeRequestSucceeds"           # 复现
swift test --filter "swiftResultGenericRequirementsDiagnostic" # 诊断 (后已删除)

# 修复验证 — 全套
swift test --filter "GenericSpecializationTests|GenericContextTests"
# → 122 tests 全过

# RuntimeViewer 编译验证
xcodebuild build -workspace MxIris-Reverse-Engineering.xcworkspace \
  -scheme RuntimeViewerCore -configuration Debug \
  -destination 'generic/platform=macOS' 2>&1 | xcsift
# → success / 0 errors / 0 warnings
```

### 验证

- `GenericSpecializationTests` + `GenericContextTests` 共 **122 个测试全过**,包括新增的 `swiftResultMakeRequestSucceeds`,旧 80 个 fixture 测试无回归。
- `RuntimeViewerCore` SPM scheme Debug build 成功,0 错误 0 警告。
- UI 端实测(用户复现): 在 SwiftUICore 中选 `Swift.Result` → inner request 不再炸,正常展开 `Success` / `Failure` 两个子参数行。

### 与原方案的差异

执行过程一共绕了 2 次弯路,最终落点跟 Phase 3 列出的 **C** 完全一致;偏差是过程性的,不影响最终结果:

- **偏差 1**: 最早 commit `8c1fd1c` 在 RuntimeViewer 侧加了 "specializer 绑 candidate 自己 image" 的修复,以为是 root cause。
  - **原因**: 误把 commit `f0c272e` 只修了 `resolveUpstreamArgument` 这件事推广到 `specializationRequest(forCandidateID:in:)`,但实际后者由 `swiftSectionFactory.existingSection(for: candidate.imagePath)` 已经把 self.machO 绑到 candidate image — 当前路径上该修复是 no-op。
  - **处理**: revert 该 commit(`1802dfc`),之后又作为防御性 + 诊断 log 重新加回(语义更明确,跨 image 时依然正确)。

- **偏差 2**: 中间一度怀疑 invertedProtocols kind 的 paramMangledName 是 garbage,在 GenericSpecializer 的 `collectRequirements` / `buildAssociatedTypeRequirements` 加了 skip。
  - **原因**: 看到诊断输出中 conditional[0]/[1] 的 kind 不是 invertedProtocols,误以为 paramMangledName 字段对这些 kind 不安全。
  - **处理**: 现有 fixture 测试 `invertedCopyableExposed` 等仍过 + 用户报告"还是不行" → 立即撤回。最终定位是 conditional 区域**整体错位**,所有 entry kind 都被错读;根因修了之后这条 guard 不再需要。

- **真正根因(C 方案)**: 命中 Swift ABI `numTrailingObjects(ConditionalInvertibleProtocolsRequirementCount) = popcount(set)` + `TrailingObjects` 自动 4-byte align。

## 5. 修复细节:为什么这样改

### 关键术语

- **`rawBits()`** (`swift/include/swift/ABI/InvertibleProtocols.h:59`): `InvertibleProtocolSet` 底层是一个整数位掩码,`Copyable = bit 0`、`Escapable = bit 1`。
  | 集合内容 | bits 二进制 | rawBits 十进制 |
  |---|---|---|
  | `{}` | `0b00` | 0 |
  | `{Copyable}` | `0b01` | 1 |
  | `{Escapable}` | `0b10` | 2 |
  | `{Copyable, Escapable}` | `0b11` | 3 |

- **`popcount`** (`swift/include/swift/Basic/MathUtils.h:42`): "Population Count" — 数二进制里 1 的个数。Swift 端对应 `Int.nonzeroBitCount`。
  | value | popcount |
  |---|---|
  | `0b00` | 0 |
  | `0b01` | 1 |
  | `0b11` | 2 |

- **组合语义**: `popcount(set.rawBits())` = **set 里到底装了几个 invertible 协议**。C++ 那边没现成的 `count()`,所以用位运算直接数。

- **4-byte 对齐的来源**: 对齐**不在那段 C++ 显式代码里**,是 LLVM `TrailingObjects<...>` 模板在每个段切换时按下一种类型的 `alignof` 自动塞 padding 实现的。Conditional 区域顺序是 `Set (alignof 2) → Count[] (alignof 2) → GenericRequirementDescriptor (alignof 4)`,所以 Count 数组结束后若停在 2-byte 边界,自动塞 2 字节 padding 把 cursor 推到 4-byte 边界。

### Cursor 演进对照

```
修复前: 5771128 -- +2(set) --> 5771130 -- +2(count) --> 5771132 <-- 从这儿读 req[0]   ❌
修复后: 5771128 -- +2(set) --> 5771130 -- +2(count[0]) --> 5771132 -- +2(count[1]) --> 5771134 -- align4 --> 5771136 <-- 从这儿读 req[0]   ✓
```

旧实现的 cursor 比正确位置**少 4 字节**(缺 1 个 count 字段 = 2 字节 + 缺 2 字节 padding),后续每个 12 字节 entry 整段错位 4 字节读取。

### 三处具体改动各自治什么病

| # | 改动 | 治什么 |
|---|------|--------|
| 1 | 把 `count` 从单字段读改成循环读 `popcount(set)` 个 UInt16 | `{Copyable, Escapable}` 时 count 数组有 2 个 UInt16,少读 1 个就少走 2 字节 |
| 2 | 取最后一个 count 作为 cumulative total | Swift ABI 规定 counts 是累计的(`GenericContext.h:583-587` "The counts are cumulative … the last entry is, therefore, the total count");旧实现拿第一个当 total,popcount > 1 时数量本身就错 |
| 3 | `currentOffset.align(to: 4)` 在读 GenericRequirementDescriptor 之前 | TrailingObjects 在 2-byte 段(Count[])和 4-byte 段(GenericRequirementDescriptor)之间会插 padding,Swift 端必须跟着 align,否则即使 #1#2 都修了仍然错位 2 字节 |

### 修复前 vs 修复后读到的 req[0] 内容

```
共享字节: 05 00 00 00 92 eb fe ff ff ff fe ff (req[0] 真实的 12 字节)

修复前从 5771132 当 req[0] 起点解析:
  flags  = 04 00 00 00 = 0x00000004 -> kind = 4 = sameShape (其实是 count[1])
  param  = 05 00 00 00 = 5            (其实是 padding + req[0].flags 低位)
  content= 92 eb fe ff = -70766       (其实是 req[0].param)
  -> paramMangledName 解析时跳到无意义内存,读到 0xeb 0xfe 0xfe ... 当 mangled name
  -> demangler 第 0 字节 (0xeb) 既不在 switch case 列表也不是 digit -> matchFailed(at: 0) ✗

修复后从 5771136 当 req[0] 起点解析:
  flags  = 05 00 00 00 -> kind = 5 = invertedProtocols  ✓
  param  = 92 eb fe ff (relativeOffset = -70766)
  content= ff ff fe ff (interpreted as InvertedProtocols struct)
  -> paramMangledName 跳到合法 mangled name buffer ("x" 或 "q_")
  -> demangler 正常构造 Type 节点  ✓
```

至此 root cause 被精准修复在 ABI 层,GenericSpecializer 不再需要任何防御性 guard。
