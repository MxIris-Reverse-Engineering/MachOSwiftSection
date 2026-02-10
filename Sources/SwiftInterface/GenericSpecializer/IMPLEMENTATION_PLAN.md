# GenericSpecializer Implementation Plan

## Overview

`GenericSpecializer` provides an interactive API for specializing generic Swift types at runtime. Users can query the generic parameters and requirements of a type, receive candidate types that satisfy those requirements, make selections, and obtain specialized metadata including field offsets.

## Key Design Decisions

1. **Only protocol requirements require PWT**: `baseClass`, `layout`, and `sameType` requirements do not need special handling - only protocol conformance requirements require passing Protocol Witness Tables (in requirement order).

2. **Separation from Indexer**: This functionality is a separate `GenericSpecializer` class that uses `ConformanceProvider` protocol to query conformance information.

3. **Two-step API**: First call `makeRequest()` to get parameters and candidates, then call `specialize()` with user selections.

## Implementation Steps

### Phase 1: Core Models ✅
- [x] `SpecializationRequest` - Request model with parameters, requirements, candidates
- [x] `SpecializationSelection` - User selection model
- [x] `SpecializationResult` - Result model with metadata, layout, fields
- [x] `SpecializationValidation` - Validation result model

### Phase 2: ConformanceProvider ✅
- [x] `ConformanceProvider` protocol definition
- [x] `IndexerConformanceProvider` implementation (SPI)
- [x] `CompositeConformanceProvider` for combining multiple providers
- [x] `EmptyConformanceProvider` for testing
- [x] `StandardLibraryConformanceProvider` for common stdlib conformances

### Phase 3: GenericSpecializer Core ✅
- [x] `GenericSpecializer` class definition
- [x] `makeRequest(for:)` - Create specialization request
- [x] Internal: Parse generic context and build parameter list
- [x] Internal: Find candidate types for each parameter
- [x] Internal: Build requirements from generic requirements (protocol, sameType, baseClass, layout)
- [x] Internal: Build associated type requirements

### Phase 4: Specialization Execution ✅
- [x] `validate(selection:for:)` - Validate user selections
- [x] `specialize(_:with:)` - Execute specialization
- [x] Internal: Build metadata array and witness table array (in requirement order)
- [x] Internal: Call MetadataAccessorFunction
- [x] Internal: Extract field offsets from specialized metadata (`result.fieldOffsets()`)

### Phase 5: Testing & Refinement
- [x] Unit tests for core models (SpecializationSelection builder, validation)
- [x] Integration tests with real generic types (TestGenericStruct with multiple constraints)
- [ ] Edge case handling (nested generics, associated types) - future enhancement

## File Structure

```
Sources/SwiftInterface/GenericSpecializer/
├── IMPLEMENTATION_PLAN.md          # This file
├── GenericSpecializer.swift        # Main class
├── ConformanceProvider.swift       # Protocol and implementations
└── Models/
    ├── SpecializationRequest.swift
    ├── SpecializationSelection.swift
    ├── SpecializationResult.swift
    └── SpecializationValidation.swift
```

## API Summary

```swift
// Create specializer (requires MachOImage for runtime specialization)
let specializer = GenericSpecializer(indexer: indexer)

// Step 1: Get request with parameters and candidates
let request = try specializer.makeRequest(for: .struct(descriptor))

// Inspect parameters and their requirements
for param in request.parameters {
    print("Parameter: \(param.name) (depth=\(param.depth), index=\(param.index))")
    for req in param.requirements {
        switch req {
        case .protocol(let info):
            print("  - Protocol: \(info.protocolName.name), needsPWT: \(info.requiresWitnessTable)")
        case .baseClass(let node):
            print("  - BaseClass: \(node)")
        case .sameType(let node):
            print("  - SameType: \(node)")
        case .layout(let kind):
            print("  - Layout: \(kind)")
        }
    }
    print("  Candidates: \(param.candidates.map { $0.typeName.name })")
}

// Step 2: User makes selections
let selection: SpecializationSelection = [
    "A": .metatype(Int.self),
    "B": .metatype(String.self)
]

// Step 3: Validate (optional)
let validation = specializer.validate(selection: selection, for: request)
guard validation.isValid else {
    print("Validation errors: \(validation.errors)")
    return
}

// Step 4: Execute specialization (MachOImage only)
let result = try specializer.specialize(request, with: selection)

// Use result
let metadata = try result.metadata()
let metadataWrapper = try result.resolveMetadata()
// Access resolved arguments
for arg in result.resolvedArguments {
    print("\(arg.parameterName): witnessTables=\(arg.witnessTables.count)")
}
```

## Requirement Handling

| Requirement Type | Needs PWT | Handling |
|-----------------|-----------|----------|
| Protocol (`T: P`) | Yes | Pass witness table to accessor (in requirement order) |
| Same Type (`T == U`) | No | Validation only |
| Base Class (`T: C`) | No | Validation only |
| Layout (`T: AnyObject`) | No | Validation only |

**Note**: Generic parameter names are derived from depth and index (e.g., A, B, C... for depth=0; A1, B1, C1... for depth=1) since original names are not preserved in binaries.

## Progress Tracking

- **Current Phase**: Complete
- **Last Updated**: 2026-01-27
- **Status**: Core Implementation Complete with Tests

### Completed
- Phase 1: Core Models (SpecializationRequest, SpecializationSelection, SpecializationResult, SpecializationValidation)
- Phase 2: ConformanceProvider (protocol + IndexerConformanceProvider, CompositeConformanceProvider, EmptyConformanceProvider, StandardLibraryConformanceProvider)
- Phase 3: GenericSpecializer Core (makeRequest, requirement parsing, candidate finding)
- Phase 4: Specialization Execution (validate, specialize, metadata/witness table building, fieldOffsets)
- Phase 5: Testing (unit tests, integration tests with real generic types)
