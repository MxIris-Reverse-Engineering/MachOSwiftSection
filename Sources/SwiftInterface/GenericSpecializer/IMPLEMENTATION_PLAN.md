# GenericSpecializer Implementation Plan

## Overview

`GenericSpecializer` provides an interactive API for specializing generic Swift types at runtime. Users can query the generic parameters and constraints of a type, receive candidate types that satisfy those constraints, make selections, and obtain specialized metadata including field offsets.

## Key Design Decisions

1. **Only protocol constraints require PWT**: `baseClass`, `layout`, and `sameType` constraints do not need special handling - only protocol conformance constraints require passing Protocol Witness Tables.

2. **Separation from Indexer**: This functionality is a separate `GenericSpecializer` class that uses `ConformanceProvider` protocol to query conformance information.

3. **Two-step API**: First call `makeRequest()` to get parameters and candidates, then call `specialize()` with user selections.

## Implementation Steps

### Phase 1: Core Models ✅
- [x] `SpecializationRequest` - Request model with parameters, constraints, candidates
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
- [x] Internal: Build constraints from requirements (protocol, sameType, baseClass, layout)
- [x] Internal: Build associated type constraints

### Phase 4: Specialization Execution
- [ ] `validate(selection:for:)` - Validate user selections
- [ ] `specialize(_:with:)` - Execute specialization
- [ ] Internal: Build metadata array and witness table array
- [ ] Internal: Call MetadataAccessorFunction
- [ ] Internal: Extract field offsets from specialized metadata

### Phase 5: Testing & Refinement
- [ ] Unit tests for each model
- [ ] Integration tests with real generic types
- [ ] Edge case handling (nested generics, associated types)

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
// Create specializer
let specializer = GenericSpecializer(indexer: indexer)

// Step 1: Get request with parameters and candidates
let request = try specializer.makeRequest(for: .struct(descriptor))

// Step 2: User makes selections
let selection = SpecializationSelection(
    "T": .metatype(Int.self),
    "U": .metatype(String.self)
)

// Step 3: Validate (optional)
let validation = specializer.validate(selection: selection, for: request)

// Step 4: Execute specialization
let result = try await specializer.specialize(request, with: selection)

// Use result
print("Size: \(result.layout.size)")
for field in result.fields {
    print("\(field.name): offset=\(field.offset)")
}
```

## Constraint Handling

| Constraint Type | Needs PWT | Handling |
|----------------|-----------|----------|
| Protocol (`T: P`) | Yes | Pass witness table to accessor |
| Same Type (`T == U`) | No | Validation only |
| Base Class (`T: C`) | No | Validation only |
| Layout (`T: AnyObject`) | No | Validation only |

## Progress Tracking

- **Current Phase**: Phase 4 - Specialization Execution
- **Last Updated**: 2026-01-26
- **Status**: In Progress

### Completed
- Phase 1: Core Models (SpecializationRequest, SpecializationSelection, SpecializationResult, SpecializationValidation)
- Phase 2: ConformanceProvider (protocol + IndexerConformanceProvider, CompositeConformanceProvider, EmptyConformanceProvider, StandardLibraryConformanceProvider)
- Phase 3: GenericSpecializer Core (makeRequest, constraint parsing, candidate finding)
