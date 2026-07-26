# CLI 注释模板自定义接口（swift-section transformer）

## 动机

`OutputTransformer` 模块把 RuntimeViewer 的注释模板机制搬到了库里：五个 Swift 侧注释模块（`SwiftFieldOffset`、`SwiftVTableOffset`、`SwiftMemberAddress`、`SwiftTypeLayout`、`SwiftEnumLayout`）各自持有一份 `${token}` 模板串、一组可用 token、一批内置命名模板，`applyTransformers(_:)` 负责把启用的模块灌进渲染配置的闭包槽位。渲染侧和持久化侧都已经完备。

缺的是命令行入口。`swift-section` 目前只开了一个口子：`dump --enum-layout-style`，五选一的预设，而且只对 `dump` 生效——`interface` 命令完全没有接 transformer。也就是说库支持的自定义能力，命令行用户一点也用不上：既没法传自己的模板，也没法复用 RuntimeViewer 里已经调好的那份配置。

本文记录补这层入口的设计。

## 范围

新增：

- `Sources/swift-section/Models/TransformerOptionGroup.swift` —— `dump` 与 `interface` 共享的参数组
- `Sources/swift-section/Commands/TransformerCommand.swift` —— `swift-section transformer` 发现性子命令（`tokens` / `templates` / `config`）

修改：

- `DumpCommand` —— 用参数组取代独立的 `--enum-layout-style` 选项
- `InterfaceCommand` —— 引入参数组，补上缺失的 `--emit-type-layout` / `--emit-enum-layout`，接上 `applyTransformers`
- `SwiftSectionCommand` —— 注册 `TransformerCommand`

库侧（`OutputTransformer` 及以下）不改动。这一批纯粹是 CLI 表面。

## 三层入口

参数组提供三层入口，后面的层覆盖前面的层：

**第一层：JSON 配置文件。** `--transformer-config <path.json>` 把文件解码成 `Transformer.SwiftConfiguration`。这个类型本来就是 `Codable` 且缺 key 容错（属性名即存储 key，与 RuntimeViewer 此前持久化的 MetaCodable JSON 兼容），所以 RuntimeViewer 存下来的那份配置可以原样喂进 CLI，不需要任何转换层。这是"跟 RuntimeViewer 一样"最直接的兑现方式。

**第二层：整模块预设。** `--enum-layout-style <preset>` 保留现有语义（`detailed` / `explained` / `standard` / `inline` / `compact`），整体替换 `swiftEnumLayout` 模块。只有 enum layout 有预设概念，因为只有它是三层模板的组合体，单独调一层没什么意义；其余四个模块单模板，直接传模板即可。

**第三层：逐模块选项。** 覆盖单个字段：

| 模块 | 模板选项 | 其他 |
| --- | --- | --- |
| `swiftFieldOffset` | `--field-offset-template` | `--field-offset-hex` / `--no-field-offset-hex` |
| `swiftVTableOffset` | `--vtable-offset-template`、`--vtable-offset-labeled-template` | `--vtable-offset-hex` / `--no-vtable-offset-hex` |
| `swiftMemberAddress` | `--member-address-template` | `--member-address-hex` / `--no-member-address-hex` |
| `swiftTypeLayout` | `--type-layout-template` | `--type-layout-hex` / `--no-type-layout-hex` |
| `swiftEnumLayout` | `--enum-layout-template`（策略行）、`--enum-layout-case-template`（每个 case）、`--enum-layout-byte-template`（每个固定字节） | `--enum-layout-hex` / `--no-enum-layout-hex`、`--enum-layout-append-omitted-details` / `--no-enum-layout-append-omitted-details` |

hex 与 `appendsOmittedDetails` 这类布尔项声明为 `Bool?`，不传就是 `nil`，保留下层（配置文件或模块默认值）的取值——避免"没传的开关把配置文件里的设置冲掉"。

## 命名模板 vs 字面模板

每个模块都带一份内置命名模板清单（`Templates.all`，形如 `("Range", "${startOffset} ..< ${endOffset}")`）。命令行同时接受两种写法：

- 值里含 `${` → 当作字面模板直接使用
- 值里不含 `${` → 按名字去清单里查，比较前把两侧都归一化（转小写、去掉空格/连字符/下划线），所以 `Start Only`、`start-only`、`startOnly` 都能命中同一项
- 查不到 → 抛 `ValidationError`，把可用名字列出来

这条规则的关键是**查不到就报错，而不是退化成字面模板**。退化听起来更宽容，但代价是 `--field-offset-template rnge` 这种拼写错误会静默变成一段内容为 `rnge` 的注释——一个不含任何 token 的字面模板本身就没有意义，不值得为它牺牲拼写错误的可发现性。

## 启用规则：`isEnabled` 驱动 emit 开关

模块的 `isEnabled` 与渲染配置的 emit 开关（`printFieldOffset` 等）是两回事：前者决定"用不用模板渲染"，后者决定"这类注释出不出现"。此前 `--enum-layout-style compact` 不配 `--emit-enum-layout` 就完全没有输出，用户看不出哪里错了。

新规则一句话：**最终配置里 `isEnabled == true` 的模块，自动打开它对应的 emit 开关。**

| 模块 | 对应开关 |
| --- | --- |
| `swiftFieldOffset` | `printFieldOffset` |
| `swiftVTableOffset` | `printVTableOffset` |
| `swiftMemberAddress` | `printMemberAddress` |
| `swiftTypeLayout` | `printTypeLayout` |
| `swiftEnumLayout` | `printEnumLayout` |

而设置任意一个模板/hex 选项，或从配置文件里读到 `isEnabled: true`，都会让该模块 `isEnabled = true`。于是 `swift-section dump Foo --field-offset-template range` 直接就有输出，不需要额外记住配套的 emit 开关。

这条规则会让 `--enum-layout-style` 的行为发生变化：以前不配 emit 开关无输出，现在有输出。这是把一个静默失效的组合变成能用的组合，不破坏任何原本有输出的命令行。

反向不成立：`--emit-field-offsets` 不会启用 `swiftFieldOffset` 模块，仍然走库内置的渲染路径。这一点必须保留——内置渲染是 `detailed` 预设的字节级等价物（有单元测试保证），把它换成模板路径会带来不必要的行为漂移风险。

## 发现性子命令

不做这一层的话，用户没有任何途径知道有哪些 token 可用，只能翻源码。`swift-section transformer` 带三个子命令：

- `transformer tokens [--module <name>]` —— 列出每个模块的 token（占位符 + 显示名）。enum layout 分三段列出（策略行 / case / 固定字节），因为它的三层模板各有各的 token 集合，混在一起列会误导。
- `transformer templates [--module <name>]` —— 列出内置命名模板及其展开，这些名字正是模板选项接受的名字。
- `transformer config` —— 输出配置 JSON。它复用同一个 `TransformerOptionGroup`，所以 `swift-section transformer config --enum-layout-style compact --field-offset-template range` 打印的就是那组选项解析后的完整配置，可以重定向成文件再用 `--transformer-config` 喂回去。不带任何选项时输出的是全默认（五个模块都 `isEnabled: false`）的骨架。

## interface 命令的补齐

`interface` 的打印配置（`SwiftDeclarationPrintConfiguration`）本来就有 `printTypeLayout` / `printEnumLayout` 两个字段，静态 layout provider 也由 `SwiftDeclarationPrinter` 按需自建（见 `staticFieldLayoutProvider()`），只是 CLI 从没暴露过这两个开关。补上 `--emit-type-layout` / `--emit-enum-layout`，否则 enum layout 与 type layout 的模板选项在 `interface` 上无处可用。

## 取舍与局限

**没有给其余四个模块做预设枚举。** 它们的 `Templates.all` 是给设置界面用的展示清单，直接作为命令行枚举会把五个模块 × 五到十项的名字全塞进 `--help`。命名模板通过模板选项按名字取用即可，`transformer templates` 负责列出来。

**配置文件不校验模板里的 token 是否存在。** 模板是自由文本，未知的 `${foo}` 会原样保留在输出里——这与库侧行为一致（`replacingOccurrences` 只替换认识的占位符），也是 RuntimeViewer 的既有行为。做校验意味着 CLI 与库对"合法模板"的判断可能分叉，不值得。

**`expandedFieldOffsetTransformer` 槽位没有对应模块。** `Transformer.SwiftConfiguration` 里没有展开字段偏移的模块，`applyTransformers` 也不碰这个槽位，所以 `--emit-expanded-field-offsets` 的输出不受模板影响。这是库侧现状，本批次不动。

**ObjC 侧模块仍在 RuntimeViewerCore。** `CType`、`ObjCIvarOffset` 以及聚合的 `Configuration` 还没搬到库里，所以 `--transformer-config` 只解 Swift 侧那部分。喂一份 RuntimeViewer 的完整配置 JSON 进来时，ObjC 侧的键会被忽略而不是报错（`SwiftConfiguration` 的解码是缺 key 容错的，多余的键本来就不参与解码）。

## 影响面

命令行使用者获得注释格式的完全控制权；RuntimeViewer 用户可以把界面里调好的配置导出成 JSON 直接给 CLI 用。库的公开 API 不变，现有命令行的默认输出逐字节不变——不传任何 transformer 选项时，五个模块全部 `isEnabled: false`，走的仍是库内置渲染。
