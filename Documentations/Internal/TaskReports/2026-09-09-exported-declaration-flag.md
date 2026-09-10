# 2026-09-09 Type / Protocol Definition 的导出标志

对应提案：[0024-exported-declaration-flag](../../Evolutions/0024-exported-declaration-flag.md)

## 问题

用户要在 RuntimeViewer 的类型列表里逐行标注「这个类型是不是导出类型」，希望 `TypeDefinition` / `ProtocolDefinition` 直接带一个标志。

这个事实库里已经有了，但只活在打印器里：提案 0008（标注 `// not exported`）与 0016（`--exported-only` 过滤）建立的裁决位于 `SwiftDeclarationPrinter+ExportFilter.swift` 的私有方法，宿主拿不到；打印器内部也重复——`printRoot()` 打开过滤开关时 `installExportFilterScope` 对全镜像类型 / 协议裁决一遍，每个类型打印时再裁决一次。

## 调研

用户提了两个前提，都需要先证伪或证实，否则实现形态完全不同。

**前提一：「每个类型都要消费，惰性查询不行，索引期填充性能怎么样？」**

原本我判断索引期无条件填充有风险：裁决的第 2 条腿（重整名 + 查 trie）对 strip 过的系统框架应该是常态，几千个类型就是几百毫秒的白付出。写了一次性探针（`ExportVerdictProbeTests`，跑完即删）在四个镜像上量：

| 镜像 | 类型数 | 第 1 腿命中率 | 走重整名 | 导出 / 未导出 / 无从判断 | 裁决总耗时 | `prepare()` |
|---|---|---|---|---|---|---|
| SwiftUICore（当前 dyld shared cache） | 3992 | 100% | 0 | 2113 / 1879 / 0 | 28 ms | 18.16 s |
| SwiftUICore（iOS 18.5 模拟器 runtime） | 2991 | 100% | 0 | 1588 / 1403 / 0 | 20 ms | 22.17 s |
| libswiftCore（进程内 `MachOImage`） | 463 | 100% | 0 | 387 / 76 / 0 | 2.4 ms | 2.80 s |
| SymbolTestsCore（fixture） | 394 | 100% | 0 | 378 / 16 / 0 | 2.8 ms | 2.28 s |

协议侧同形（400 / 325 / 105 / 56 条，同样 100% 命中）。判断错了：Swift 的 descriptor 符号在 strip 过的模拟器框架和 dyld shared cache 里都还在，第 2 腿一次都没触发，总耗时占 `prepare()` 的 0.15% 以内。结论翻转为「无条件填充，不设开关」——一个默认关闭的开关只会让宿主必须记得打开，而收益是毫秒。

**前提二：「导出符号表找不到肯定不是导出类型，直接 Bool 就行。」**

对了一半。「符号表里查不到」确实是确定的「未导出」；但 `SymbolIndexStore.isExported(name:in:)` 的 `nil` 不是这个意思，它表示**镜像本身没有导出信息**（没有 export trie，如 `.o` 目标文件），此时读成 `false` 会让那个镜像里每个类型都被谎报。另有一个声明级的无从判断：名字里含 `.extension` context 时重整不可信（`publicTypeNestedInConstrainedExtensionIsKept` 钉的就是这条——constrained extension 里的 `public` 嵌套类型，重整名必然查不到 trie）。实测里这两种一次都没出现，恰恰说明它们不是噪声而是罕见的正确性分支。

## 方案

用户看过数据后选了枚举而不是 `Bool?`（原话「Bool 就写死这 3 种情况了」），顺势把压在 `nil` 里的两个原因按**作用域**拆开：

```swift
public enum ExportStatus: Sendable, Hashable {
    case exported
    case notExported
    case imageHasNoExportInformation      // 镜像级：没有 export trie，任何声明都判不了
    case descriptorSymbolNameUnresolvable // 声明级：trie 正常，这一条的名字重整不可信
}
```

投影 `isExported: Bool?`（与 `SymbolIndexStore` 同形）与 `isDefinitelyNotExported`（过滤 / 标注唯一该认的条件）。属性是 `let`，在带 machO 的构造入口算好；裁决只要描述符 offset 与名字节点，不碰 `index(in:)` 的产物，所以 `prepare()` 返回时整张表就都有值——正是列表 UI 需要的时刻。特化定义继承泛型原型的值（同一个 descriptor 即同一个事实）。

打印器的两个 public `exportVerdict(...) -> Bool?` 签名不动、改为转发；`installExportFilterScope` 只筛 `isDefinitelyNotExported`。成员级 / 字段级 / 扩展级判定完全不碰——判据不同（派生符号、目标归属）。

## 实际执行

按方案落地，没有偏离：新增 `Sources/SwiftDeclaration/Components/Definitions/ExportStatus.swift`（枚举 + 两腿裁决 + `descriptorSymbolName` 重整，整体从 `SwiftPrinting` 搬来，语义一行未改），两个 definition 各加一个 `let` 与构造参数，`TypeDefinition+Specialization` 传入继承值，`SwiftDeclarationPrinter+ExportFilter` 的类型 / 协议裁决段落缩成两个转发。

一处需要留意的默认值：不带 machO 的 `package` init（测试用的错误契约构造）默认 `.descriptorSymbolNameUnresolvable`——那种定义本来就没有可信的描述符可裁决，给「无从判断」而不是给 `false`。

## 验证

- 新增 `ExportStatusTests`（`SymbolTestsCore`）：全表逐个类型 / 协议的 `exportStatus.isExported` 必须等于**独立从符号存储重算**的 trie 裁决（不经模型读回，所以改动裁决顺序不会让测试自我印证）；两个 no-verdict case 在有 trie 的镜像上出现即 `Issue.record`；断言导出与未导出两侧计数都 > 0，防止空转通过。
- 具体取值钉住三条已知声明：`private` 类型、`private` 协议、以及 constrained extension 里的 `public` 嵌套类型（后者同时钉住 `ExportStatus.descriptorSymbolName` 对它返回 `nil`——这正是第 1 腿不可省的理由）。
- `ExportStatusProjectionTests` 钉两个投影的逐 case 映射。
- `SpecializedExportStatusTests` 钉特化定义继承原型取值。
- 既有端到端测试全绿：`ExportedOnlyInterfaceTests`、`ExportStatusAnnotationTests`、`ExportStatusDumpAnnotationTests`、`HeaderAndExportStatusFlagTests`，以及全量 `swift test --skip IntegrationTests`。

## 偏差

无。唯一与初始判断相反的是索引期填充的成本——探针推翻了我的预估，方案据此从「带开关的填充」改成「无条件填充」。
