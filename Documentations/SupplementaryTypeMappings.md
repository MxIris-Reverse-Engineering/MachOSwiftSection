# Supplementary Type Mappings

`swift-section interface --resolve-c-module-names` resolves `__C.NSString` to
`Foundation.NSString` by indexing the SDK. Private frameworks such as
**AttributeGraph** have no SDK module at all — no headers, no `.swiftmodule`,
no `.apinotes` — so nothing can be indexed, and their `swift_name` renames
(`AG_SWIFT_NAME(Graph)`) exist *only* in headers: no tool can recover
`AttributeGraph.Graph` from a binary. That knowledge has to come from outside.

Supplementary type mappings are that outside channel: user-provided
[APINotes](https://clang.llvm.org/docs/APINotes.html) files loaded on top of
the SDK's own, so `__C.AGGraphRef` renders as `AttributeGraph.Graph`. The
library ships no mappings of its own — you write (or obtain) the files and
point the tool at them:

- CLI: `swift-section interface --resolve-c-module-names
  --supplementary-apinotes <file-or-directory>` (repeatable),
- API: `SwiftInterfaceBuilderTypeNameProvider(machO:dependencies:supplementaryAPINotesURLs:)`.

Later sources override earlier ones per C name: SDK APINotes first, then your
files in argument order — so a supplementary file can also correct an SDK
entry.

## Writing a mapping file

A mapping file is a standard `.apinotes` YAML file, named after the framework
it describes:

```yaml
Name: AttributeGraph
Typedefs:
- Name: AGGraphRef
  SwiftName: Graph
Tags:
- Name: AGGraphStorage
  SwiftName: Graph
```

- `Name` is the module the types belong to — it becomes the rendered module
  qualifier.
- Every entry's `Name` is the **C spelling** (what the binary records);
  `SwiftName` is the imported Swift spelling from the header's
  `swift_name` / `NS_SWIFT_NAME` / `AG_SWIFT_NAME` attribute. An entry
  without `SwiftName` still registers module attribution for its C name.

### Register both spellings of a CF-bridged type

A CF-bridged type (`CF_BRIDGED_TYPE` / `objc_bridge` typedefs like
`typedef struct AGGraphStorage *AGGraphRef`) reaches Swift manglings under
**two C spellings**, and both need an entry:

| Spelling | Where it appears | Section |
|---|---|---|
| Typedef name (`AGGraphRef`) | symbol signatures | `Typedefs` |
| Storage/tag name (`AGGraphStorage`) | field-metadata foreign descriptors | `Tags` |

(A third shape — the imported Swift name itself, `__C.Graph` — is derived
from `SwiftName` automatically; no extra entry is needed.)

### Choosing the section

- CF-bridged pointer typedefs: `Typedefs` (the `…Ref` name) **and** `Tags`
  (the storage struct name), as above.
- Real Objective-C classes: `Classes`.
- Objective-C protocols: `Protocols`.
- C structs/unions and enums: `Tags`; C enum constants: `Enumerators`;
  plain typedefs: `Typedefs`.

The section matters: lookups are category-isolated so that, e.g., the
protocol-only `NSObject` → `NSObjectProtocol` rename can never rewrite class
references.

## Verifying a mapping

Run the interface generation with and without your file and compare:

```bash
swift-section interface MyBinary --resolve-c-module-names \
    --supplementary-apinotes MyFramework.apinotes -o after.txt
```

Every `__C.<name>` your file covers should now render module-qualified and
renamed. If a name stays `__C.…`, check that both spellings are registered
and that the file's `Name:` is the intended module. A path that does not
exist or a file that fails to parse is reported as a `warning:` on stderr and
skipped.

## Sourcing mappings

Base entries on header-level evidence: the reverse-engineered header
declaration, or a project such as
[OpenGraph](https://github.com/OpenSwiftUIProject/OpenGraph) that documents
it. Mappings are external knowledge: a wrong entry produces wrong output, so
keep entries limited to spellings you can back with a source.
