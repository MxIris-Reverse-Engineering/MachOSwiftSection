# `swift-section objc`

Reads Objective-C metadata straight out of a Mach-O file or an image inside a dyld shared
cache — any architecture, platform or OS version, nothing loaded into a process — and renders
headers from it. The Objective-C libraries underneath (MachOObjCSection) are the ones
RuntimeViewer renders Objective-C with, so its headers and address comments read like a
RuntimeViewer export.

**It needs `swift-section` 0.20.0 or later.** These commands used to ship as a separate
`objc-section` executable; 0.20.0 moved them into `swift-section` with the same options,
output and exit codes, and the standalone tool is retired. Anything written for
`objc-section <subcommand>` works as `swift-section objc <subcommand>`. An older install has no
`objc` subcommand — `swift-section objc --help` fails — so upgrade it with
`brew upgrade swift-section`.

## The usual commands

```bash
# One class with its method and accessor addresses, from a cache file on disk
swift-section objc interface NSTextInputContext \
  /path/to/dyld_shared_cache_arm64e --dyld-shared-cache -n AppKit \
  --emit-method-imp-addresses --emit-property-accessor-addresses --emit-ivar-offsets

# The same from the running system's cache — no path
swift-section objc interface NSTextInputContext --uses-system-dyld-shared-cache -n AppKit \
  --emit-method-imp-addresses --emit-property-accessor-addresses

# A standalone binary; a universal one needs -a, and without it the error lists the slices
swift-section objc interface SomeClass /path/to/Binary -a arm64e --emit-method-imp-addresses

# A whole image into one header. -o does not create directories.
swift-section objc dump /path/to/dyld_shared_cache_arm64e --dyld-shared-cache -n AppKit \
  --emit-method-imp-addresses --emit-property-accessor-addresses \
  --emit-ivar-offsets --emit-property-attributes \
  -o AppKit.h
```

- The loading options are spelled exactly as in the Swift subcommands: `--dyld-shared-cache`
  (the path is a cache), `--uses-system-dyld-shared-cache` (no path), `-n` /
  `--cache-image-name`, `-p` / `--cache-image-path` (exact install path, when a leaf name is
  ambiguous), `-a` / `--architecture`. Pass a cache's main file, never a `.01` /
  `.dylddata` shard — the shards are found automatically.
- **Every address and offset comment is off by default** — a bare `interface` prints no
  addresses. `--emit-method-imp-addresses` appends `// IMP: 0x…` to each method,
  `--emit-property-accessor-addresses` appends `// getter IMP: … // setter IMP: …` to each
  property.
- IMP addresses are unslid virtual addresses — what a disassembler shows for the same file or
  cache. They are only meaningful in that exact build.
- `interface` looks a name up in classes, protocols, categories, structs and unions, in that
  order, and takes the first hit; `--kind` picks one when a name is both a class and a struct.
  A category is named `ClassName(CategoryName)`.
- `-f` / `--filter <text>` narrows `dump` to names containing the text, case-insensitively.
- stdout carries only declarations; indexing progress goes to stderr, and only with `-v`.
  Unlike the Swift `interface`, redirecting stdout is safe here.
- `swift-section --version` prints the version to record beside a generated header.

## Traps

- **`--sections` is comma-separated here** (`--sections classes,protocols`) — the opposite of
  the Swift `dump` in the same executable, where a comma is an error and the values are
  space-separated.
- **An empty `dump` still exits 0.** The reason goes to stderr only:
  `no Objective-C metadata found in <image>`, `no <kind> found in <image>`, or
  `--filter '<text>' matched none of the <N> declarations in <image>`. Read stderr before
  concluding that a class is not there. `interface` is the opposite: a name it cannot find is
  exit 1 with `Error: No class, protocol, category, struct or union named '<name>' …`.
- **A standalone file's superclass chain stops at its own boundary.** Outside a shared cache, a
  superclass defined in another binary is not followed, so `--strip-overrides` removes almost
  nothing and inherited members such as `init` stay listed. Inside one cache the chain crosses
  images normally. When you need the full chain, read the image inside its cache.
- **The ivar offsets of pure Swift classes (`_TtC…` names) are unreliable** — file and
  in-process readings disagree, and some ivars are dropped. Take Swift layout from the Swift
  subcommands (`--emit-field-offsets`).
- **An API diff cannot tell public from private.** Objective-C has no access control, so a
  renamed private selector is reported as API-breaking just like a public one. A pure change
  of an ivar's offset is deliberately not reported at all.
- **Snapshots do not cross format versions.** A snapshot JSON carries a `formatVersion`; any
  other version is rejected with `Unsupported ObjC API snapshot format version …`, and the fix
  is to regenerate the baseline with the current tool.

## Where the details live

`Documentations/ObjCCommandLine.md` in the MachOSwiftSection repository covers all five
subcommands — including the `snapshot` / `diff` / `evolution` trio for comparing the
Objective-C API of two builds — the ten generation switches and the comment templates.
`swift-section objc <subcommand> --help` is generated from the code and cannot drift.
