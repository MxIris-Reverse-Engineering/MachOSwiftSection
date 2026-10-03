# SwiftSectionKit —— `swift-section` 的全部功能，以库的形式提供

`SwiftSectionKit` 是 `swift-section` 命令行背后的库。每个子命令对应一个请求类型：构造请求、运行它，产物和诊断通过你提供的输出端交回来。命令行本身只是它的一层包装，所以在你自己的代码里运行一个请求，得到的就是对应命令行打印的内容。

English: [SwiftSectionKit.md](SwiftSectionKit.md)

## 引入

```swift
.product(name: "SwiftSectionKit", package: "MachOSwiftSection"),
```

用到其他模块的类型时，把对应的 product 也声明上——`Transformer.SwiftConfiguration` 来自 `SwiftOutputTransformer`，`ABIDiff` 与 `ABISnapshotDocument` 来自 `SwiftDiffing`，`SwiftIndexEvents.Handler` 来自 `SwiftDeclaration`，依此类推。

## 快速上手

```swift
import SwiftSectionKit

final class CollectingOutput: SwiftSectionOutput, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var text = ""

    func write(_ product: SwiftSectionProduct) {
        lock.withLock {
            if case .text(let line) = product {
                text += line + "\n"
            }
        }
    }

    func report(_ diagnostic: SwiftSectionDiagnostic) {}
}

let output = CollectingOutput()
let outcome = try await ABIDiffRequest(
    old: .path("Old.framework/Old"),
    new: .path("New.framework/New"),
    report: .changeList
).run(
    output: output,
    environment: SwiftSectionEnvironment(generator: GeneratorIdentity(name: "MyTool", version: "1.0"))
)
if outcome.hasBreakingChange == true {
    // 让构建失败
}
```

## 请求一览

| 请求 | 对应命令行 | 返回 |
|---|---|---|
| `DumpRequest` | `swift-section dump` | — |
| `InterfaceRequest` | `swift-section interface` | — |
| `ABISnapshotRequest` | `swift-section snapshot` | `ABISnapshotDocument` |
| `ABIDiffRequest` | `swift-section diff` | `ABIDiffOutcome`（diff 本身与 `hasBreakingChange`） |
| `ABIEvolutionRequest` | `swift-section evolution` | `ABIEvolutionOutcome`（evolution 本身与 `hasBreakingChange`） |
| `TransformerTokensRequest`、`TransformerTemplatesRequest`、`TransformerConfigurationRequest` | `swift-section transformer tokens / templates / config` | — |
| `ObjCDumpRequest` | `swift-section objc dump` | `ObjCDumpRequest.Outcome`（找到了什么） |
| `ObjCInterfaceRequest` | `swift-section objc interface` | — |
| `ObjCAPISnapshotRequest`、`ObjCAPIDiffRequest`、`ObjCAPIEvolutionRequest` | `swift-section objc snapshot / diff / evolution` | 文档 / outcome |

互斥的选项是一个 enum 而不是几个开关：`ABIDiffRequest.Report` 只能是 change list、summary、JSON、annotated interface 之一，不会同时是两个。命令行上一个 flag 隐含另一个的（`--emit-expanded-field-offsets` 隐含字段偏移），请求里是一个值同时表达两者（`FieldOffsetComments.expanded`）。

二进制用 `MachOSource` 指明：瘦或胖的文件、dyld shared cache 文件里的一个镜像、或运行系统 cache 里的一个镜像。`snapshot`、`diff`、`evolution` 收 `SnapshotSource.path`，它可以指向二进制，也可以指向 snapshot 文档；和命令行一样，按文件第一个非空白字节区分。

## 输出端契约

实现 `SwiftSectionOutput` 必须遵守下面几条，它们都不在协议签名里。

- **会被并发调用。** `diff` 和 `evolution` 并行索引多个输入，每个进行中的输入都通过同一个输出端汇报。内部状态要加锁。
- **三路分开。** `write(_:)` 只收产物；`report(_:)` 收进度、警告、提示和单个声明的错误；`indexEventHandlers(forInputLabeled:)` 返回接收索引降级事件的 handler，默认一个都不返回，这些事件就落到 `os_log`。请求索引多个输入时，label 指明是哪一个（`"old"`、`"new"`、版本标签）。
- **每块产物打印时后面跟一个换行。** 要逐字节复现 `swift-section` 的 stdout，就把每个 `.declarations(_:)`（取 `.string`，或按语义类型着色）、`.text(_:)`、`.annotatedInterface(_:style:)`、`.data(_:)` 后面各补一个 `"\n"` 打印出来。
- **文件目的地不经过输出端。** `destination: .file(path:)` 时由请求自己写文件，写法和命令行的 `-o` 一样，输出端只收诊断。唯一例外：`.summary` 报告的结论行即使在这种情况下也写给输出端，命令行一直如此。
- **`.annotatedInterface` 自带着色规则。** `InterfaceAnnotationStyle.lineKinds(of:)` 把每一行归为 added、removed、modified、header、plain 之一，`swift-section` 就按这个着色。

## 诊断

`SwiftSectionDiagnostic` 是一个级别加一条消息。消息就是 `swift-section` 打印的那一行原文，所以有些消息里带命令行选项名（`warning: --supplementary-apinotes path does not exist: …`）。宿主可以按级别过滤：显示警告、丢掉进度。

诊断写到哪里由命令行自己决定：它把 `interface` 的进度行和 `dump` 的单个声明错误写到 stdout，其余写到 stderr。宿主自己决定自己的去处。

## 错误

抛出的错误不提命令行选项：`MachOSourceError`（胖二进制没给架构、没有那个切片、cache 里没有那个镜像）、`SnapshotSourceError.binaryRequired(path:)`（把 snapshot 文档交给了 annotated interface）、`ObjCDeclarationLookupError`。来自下层的错误原样透传——文件不存在、snapshot 文档格式版本不支持、`ABIEvolutionError.labelCountMismatch`。

`swift-section` 把第一类错误翻译回它一直打印的文案，并把用法错误报成 validation error（退出码 64）。宿主想用自己的措辞，也照这样做。

## 环境

`SwiftSectionEnvironment` 装的是请求会盖进产物、但不由它自己计算的东西：生成器的名字和版本（interface header、snapshot provenance），以及当前时间（snapshot provenance 的 `createdAt`）。传你自己工具的身份；测试里传固定时间，每次运行就能得到相同的字节。

## 源码兼容性

`SwiftSectionKit` 和包里其他模块一样以源码分发。请求的新字段一律带默认值，已有的调用照常编译。调用方构造的 enum——`ABIDiffRequest.Report`、`DumpSection`、`ObjCDeclarationKind` 之类——以后的版本可能加 case；可以构造它们，但不要依赖对它们做穷举 `switch`。
