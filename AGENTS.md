# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Test Commands

```bash
# Build the project
swift build

# Run all tests
swift test

# Run specific test suites
swift test --filter DemanglingTests
swift test --filter MachOSwiftSectionTests
swift test --filter SwiftDumpTests
swift test --filter SwiftInterfaceTests

# Run the CLI tool
swift run swift-section dump /path/to/binary
swift run swift-section interface /path/to/binary

# Build release executable
./build-executable-product.sh
```

Requires Swift 6.2+ / Xcode 26.0+.

## Architecture Overview

This is a Swift library for parsing Mach-O files to extract Swift metadata (types, protocols, conformances). It uses a custom Demangler to parse symbolic references and restore Swift Runtime logic.

### Module Dependency Hierarchy

```
swift-section (CLI)
    └── SwiftDump, SwiftInterface
            └── SwiftInspection
                    └── MachOSwiftSection
                            └── MachOFoundation
                                    └── MachOSymbols, MachOPointers
                                            └── MachOReading, MachOResolving
                                                    └── MachOExtensions, MachOCaches
                                                            └── MachOKit (external)
```

### Core Modules

**Demangling** - Custom Swift symbol demangler supporting symbolic references
- `Demangler` - Main demangling logic, parses mangled symbols into `Node` AST
- `Remangler` - Re-mangles nodes back to symbol strings
- `NodePrinter` - Prints nodes as human-readable Swift types
- `Node` - AST representation with `Kind` enum for ~200 mangling node types

**MachOSwiftSection** - Low-level Swift section parsing
- Reads `__swift5_types`, `__swift5_proto`, `__swift5_protos`, `__swift5_assocty`, `__swift5_builtin`
- `MachOFile.Swift` / `MachOImage.Swift` - Entry point via `.swift` property
- Models for descriptors: `TypeContextDescriptor`, `ProtocolDescriptor`, `ProtocolConformanceDescriptor`
- Relative pointer resolution for Swift's position-independent metadata

**SwiftDump** - High-level type wrappers
- `Struct`, `Enum`, `Class`, `Protocol`, `ProtocolConformance`, `AssociatedType`
- `DemangleResolver` - Resolves mangled names using the Demangler

**SwiftInterface** - Generates Swift interface files
- `SwiftInterfaceBuilder` - Main builder, call `prepare()` then `printRoot()`
- `SwiftInterfaceIndexer` - Indexes types, extensions, conformances
- `TypeNodePrinter`, `FunctionNodePrinter` - Print demangled nodes as Swift code
- `GenericSpecializer` - Specializes generic types with user-provided type arguments (see implementation plan below)

**SwiftInspection** - Runtime metadata analysis
- `EnumLayoutCalculator` - Calculates enum memory layouts (multi-payload enum support)
- `ClassHierarchyDumper` - Dumps class inheritance hierarchies
- `MetadataReader` - Reads runtime metadata from MachOImage

**Semantic** - Semantic string building for colored/annotated output
- `SemanticString` - String with semantic type annotations (keyword, type, variable)
- `SemanticType` - Categories: `.keyword`, `.typeName`, `.functionName`, `.variable`, etc.

### MachO Infrastructure Modules

- **MachOFoundation** - Combines reading, symbols, pointers
- **MachOReading** - File reading abstractions
- **MachOResolving** - Address/offset resolution
- **MachOSymbols** - Symbol table parsing and demangling
- **MachOPointers** - Pointer types (relative, indirect, etc.)
- **MachOCaches** - dyld shared cache support
- **MachOExtensions** - Extensions to MachOKit types

### Key Patterns

**Descriptor → Type Wrappers**: Raw descriptors from sections get wrapped:
```swift
let descriptors = try machO.swift.protocolDescriptors
for descriptor in descriptors {
    let proto = try Protocol(descriptor: descriptor, in: machO)
}
```

**Relative Pointers**: Swift uses position-independent relative offsets. The `RelativeDirectPointer<T>` and related types handle resolution.

**Node-based Demangling**: Mangled symbols parse to `Node` trees, then print via `NodePrinter`:
```swift
let node = try demangleAsNode("$sSiD")  // Returns Node tree
let string = node.print(using: .default) // "Swift.Int"
```

## Test Environment

Tests use `MACHO_SWIFT_SECTION_SILENT_TEST=1` to suppress verbose output.

Tests read Mach-O files from Xcode frameworks and dyld shared cache for real-world validation.

## Work In Progress

### GenericSpecializer (feature/generic-specializer branch)

Interactive API for specializing generic Swift types at runtime. Implementation plan located at:
`Sources/SwiftInterface/GenericSpecializer/IMPLEMENTATION_PLAN.md`

**Status:** Core implementation complete with tests.

**Key Design Points:**
- Only protocol requirements require Protocol Witness Tables (PWT)
- `baseClass`, `layout`, and `sameType` requirements need validation only, no PWT
- PWT passed in requirement order (critical for correct specialization)
- Generic parameter names derived from depth/index (A, B, A1, B1...) since names not preserved in binary
- Two-step API: `makeRequest()` returns parameters/candidates, `specialize()` executes with user selections
- Uses `ConformanceProvider` protocol to query type conformances from Indexer

**File Structure:**
```
Sources/SwiftInterface/GenericSpecializer/
├── IMPLEMENTATION_PLAN.md          # Implementation plan
├── GenericSpecializer.swift        # Main class
├── ConformanceProvider.swift       # Protocol and implementations
└── Models/
    ├── SpecializationRequest.swift   # Request with parameters, requirements, candidates
    ├── SpecializationSelection.swift # User selection with builder pattern
    ├── SpecializationResult.swift    # Result with metadata, fieldOffsets, valueWitnessTable
    └── SpecializationValidation.swift # Validation errors/warnings
```
