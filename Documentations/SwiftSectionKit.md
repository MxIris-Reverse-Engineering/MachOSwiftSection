# SwiftSectionKit — everything `swift-section` does, as a library

`SwiftSectionKit` is the library behind the `swift-section` command-line tool. Every subcommand is one request type; you build the request, run it, and receive the product and the diagnostics through an output you supply. The command-line tool is a thin wrapper around it, so a request run from your own code produces exactly what the matching command line prints.

中文版：[SwiftSectionKit_zh.md](SwiftSectionKit_zh.md)

## Adding it

```swift
.product(name: "SwiftSectionKit", package: "MachOSwiftSection"),
```

Declare the products of every other module whose types you name as well — `SwiftOutputTransformer` for `Transformer.SwiftConfiguration`, `SwiftDiffing` for `ABIDiff` and `ABISnapshotDocument`, `SwiftDeclaration` for `SwiftIndexEvents.Handler`, and so on.

## Quick start

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
    // fail the build
}
```

## The requests

| Request | Command line | Returns |
|---|---|---|
| `DumpRequest` | `swift-section dump` | — |
| `InterfaceRequest` | `swift-section interface` | — |
| `ABISnapshotRequest` | `swift-section snapshot` | the `ABISnapshotDocument` |
| `ABIDiffRequest` | `swift-section diff` | `ABIDiffOutcome` (the diff, `hasBreakingChange`) |
| `ABIEvolutionRequest` | `swift-section evolution` | `ABIEvolutionOutcome` (the evolution, `hasBreakingChange`) |
| `TransformerTokensRequest`, `TransformerTemplatesRequest`, `TransformerConfigurationRequest` | `swift-section transformer tokens / templates / config` | — |
| `ObjCDumpRequest` | `swift-section objc dump` | `ObjCDumpRequest.Outcome` (what was found) |
| `ObjCInterfaceRequest` | `swift-section objc interface` | — |
| `ObjCAPISnapshotRequest`, `ObjCAPIDiffRequest`, `ObjCAPIEvolutionRequest` | `swift-section objc snapshot / diff / evolution` | the document / an outcome |

Options that exclude each other are one enum rather than several flags: an `ABIDiffRequest.Report` is a change list, a summary, JSON or an annotated interface, never two at once. Where the command line has a flag that implies another (`--emit-expanded-field-offsets` implies field offsets), the request has one value covering both (`FieldOffsetComments.expanded`).

A binary is named by a `MachOSource` — a thin or fat file, an image inside a dyld shared cache file, or an image of the running system's cache. `snapshot`, `diff` and `evolution` take `SnapshotSource.path`, which may name a binary or a snapshot document; the file's first non-whitespace byte tells them apart, as on the command line.

## The output contract

These are the rules an implementation of `SwiftSectionOutput` must honour. None of them is visible in the protocol's signature.

- **It is called concurrently.** `diff` and `evolution` index their inputs side by side, and each in-flight input reports through the same output. Protect any state with a lock.
- **Three channels, kept apart.** `write(_:)` receives the product only. `report(_:)` receives progress lines, warnings, notes and per-declaration errors. `indexEventHandlers(forInputLabeled:)` returns the handlers that hear about indexing degradations; the default returns none, which leaves those to `os_log`. The label names the input when a request indexes several (`"old"`, `"new"`, a version label).
- **Every product piece is followed by a newline when printed.** To reproduce `swift-section`'s stdout byte for byte, print each `.declarations(_:)` (its `.string`, or colored by its semantic types), `.text(_:)`, `.annotatedInterface(_:style:)` and `.data(_:)` followed by `"\n"`.
- **A file destination bypasses the output.** With `destination: .file(path:)`, the request writes the file itself, the way the command line writes `-o`, and the output receives diagnostics only. One exception: the verdict line of a `.summary` diff report goes to the output even then, as it always has on the command line.
- **`.annotatedInterface` lines carry their own coloring rule.** `InterfaceAnnotationStyle.lineKinds(of:)` classifies each line as added, removed, modified, header or plain — the rule `swift-section` colors by.
- **`dump` and `objc dump` say what each declaration is.** Every top-level declaration they hand over arrives through `write(_:declaring:)` with a `DumpedDeclaration`: the Swift section or the Objective-C kind it comes from, and its name. A conformance and an associated type are named after the type they extend, spelled as that type's own name is, so the pieces of one type can be filed together; a Swift name that could not be rendered is `nil`. The default implementation forwards to `write(_:)`, so an output that only prints needs nothing more. Everything else — a header, the empty line after each Objective-C declaration, the single piece of an `interface` — comes through `write(_:)`.

## Diagnostics

A `SwiftSectionDiagnostic` is a severity and a message. The message is the line exactly as `swift-section` prints it, so some messages name command-line options (`warning: --supplementary-apinotes path does not exist: …`). Severities let a host filter: show warnings, drop progress.

Where the command line prints a diagnostic is the command line's business: it writes `interface`'s progress lines and `dump`'s per-declaration errors to stdout and everything else to stderr. A host chooses for itself.

## Errors

Thrown errors are worded without naming command-line options: `MachOSourceError` (a fat binary without an architecture, a missing slice, a cache image that is not there), `SnapshotSourceError.binaryRequired(path:)` (a snapshot document handed to an annotated interface), `AvailabilityPlatformInferenceError` (an annotated evolution asked to infer its `@available` platform, when an input's platform has no `@available` name or the inputs' platforms differ), `ObjCDeclarationLookupError`. Errors from the layers below — a missing file, a snapshot document of an unsupported format version, `ABIEvolutionError.labelCountMismatch` — pass through unchanged.

`swift-section` translates the first group back into the wording it has always printed, and reports a usage mistake as a validation error (exit code 64). A host that wants its own wording does the same.

## The environment

`SwiftSectionEnvironment` holds what a request stamps into its product without computing it: the generator's name and version (interface headers, snapshot provenance) and the current date (snapshot provenance's `createdAt`). Pass your own tool's identity; pass a fixed date in tests to get the same bytes on every run.

## Source compatibility

`SwiftSectionKit` is distributed as source, like the rest of the package. New request fields arrive with default values, so existing calls keep compiling. The enums a caller constructs — `ABIDiffRequest.Report`, `DumpSection`, `ObjCDeclarationKind` and the like — may gain cases in a later release; build them, but do not rely on switching over them exhaustively. So may `DumpedDeclaration`, which a host only receives.
