import Foundation
import MachOExtensions
import MachOFoundation
import MachOKit
@testable import MachOSwiftSection

/// Centralizes the "pick (main + variants) fixture entities for each descriptor type"
/// logic, ensuring Suites and their corresponding BaselineGenerators look at the
/// same set of entities.
///
/// Both target descriptors have unique `name(in:)` values within the
/// `SymbolTestsCore` fixture, so a parent-chain disambiguator is unnecessary.
package enum BaselineFixturePicker {
    /// Picks the concrete (non-generic) struct `Structs.StructTest` from the
    /// `SymbolTestsCore` fixture.
    package static func struct_StructTest(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> StructDescriptor {
        try required(
            try machO.swift.typeContextDescriptors.compactMap(\.struct).first(where: { descriptor in
                try descriptor.name(in: machO) == "StructTest"
            })
        )
    }

    /// Picks the generic struct
    /// `GenericFieldLayout.GenericStructNonRequirement<A>` from the
    /// `SymbolTestsCore` fixture. Exercises generic context paths.
    package static func struct_GenericStructNonRequirement(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> StructDescriptor {
        try required(
            try machO.swift.typeContextDescriptors.compactMap(\.struct).first(where: { descriptor in
                try descriptor.name(in: machO) == "GenericStructNonRequirement"
            })
        )
    }

    /// Picks the generic struct
    /// `GenericFieldLayout.GenericStructLayoutRequirement<A: AnyObject>` from
    /// the `SymbolTestsCore` fixture. Exercises a layout-class generic
    /// requirement (`A: AnyObject`) — surfaces a single
    /// `GenericRequirementDescriptor` whose flags carry
    /// `GenericRequirementKind.layout` with payload `class`.
    package static func struct_GenericStructLayoutRequirement(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> StructDescriptor {
        try required(
            try machO.swift.typeContextDescriptors.compactMap(\.struct).first(where: { descriptor in
                try descriptor.name(in: machO) == "GenericStructLayoutRequirement"
            })
        )
    }

    /// Picks the generic struct
    /// `GenericFieldLayout.GenericStructSwiftProtocolRequirement<A: Equatable>`
    /// from the `SymbolTestsCore` fixture. Exercises a Swift-protocol
    /// generic requirement (`A: Equatable`) — surfaces
    /// `GenericRequirementDescriptor` with kind `.protocol`, content carrying a
    /// Swift `RelativeProtocolDescriptorPointer`.
    package static func struct_GenericStructSwiftProtocolRequirement(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> StructDescriptor {
        try required(
            try machO.swift.typeContextDescriptors.compactMap(\.struct).first(where: { descriptor in
                try descriptor.name(in: machO) == "GenericStructSwiftProtocolRequirement"
            })
        )
    }

    /// Picks the generic struct
    /// `GenericFieldLayout.GenericStructObjCProtocolRequirement<A: NSCopying>`
    /// from the `SymbolTestsCore` fixture. Exercises an ObjC-protocol
    /// generic requirement (`A: NSCopying`) — surfaces a
    /// `GenericRequirementDescriptor` with kind `.protocol`, content carrying
    /// an ObjC `RelativeProtocolDescriptorPointer`.
    package static func struct_GenericStructObjCProtocolRequirement(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> StructDescriptor {
        try required(
            try machO.swift.typeContextDescriptors.compactMap(\.struct).first(where: { descriptor in
                try descriptor.name(in: machO) == "GenericStructObjCProtocolRequirement"
            })
        )
    }

    /// Picks the generic struct
    /// `GenericRequirementVariants.SameTypeRequirementTest<First, Second>`
    /// (`where First == Second`) from the `SymbolTestsCore` fixture.
    /// Exercises a `sameType` generic requirement — surfaces a
    /// `GenericRequirementDescriptor` with kind `.sameType`, content carrying
    /// a `RelativeDirectPointer<MangledName>`.
    package static func struct_SameTypeRequirementTest(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> StructDescriptor {
        try required(
            try machO.swift.typeContextDescriptors.compactMap(\.struct).first(where: { descriptor in
                try descriptor.name(in: machO) == "SameTypeRequirementTest"
            })
        )
    }

    /// Picks the generic struct
    /// `GenericRequirementVariants.ParameterPackRequirementTest<each Element>`
    /// from the `SymbolTestsCore` fixture. Exercises a parameter-pack
    /// generic context — the type's generic context surfaces a non-nil
    /// `typePackHeader` and at least one `GenericPackShapeDescriptor`.
    package static func struct_ParameterPackRequirementTest(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> StructDescriptor {
        try required(
            try machO.swift.typeContextDescriptors.compactMap(\.struct).first(where: { descriptor in
                try descriptor.name(in: machO) == "ParameterPackRequirementTest"
            })
        )
    }

    /// Picks the generic struct
    /// `GenericRequirementVariants.InvertibleProtocolRequirementTest<Element: ~Copyable>: ~Copyable`
    /// from the `SymbolTestsCore` fixture. Exercises a generic context
    /// carrying conditional invertible-protocol requirements (the `~Copyable`
    /// bit is encoded inline on the type's generic signature) — surfaces a
    /// non-nil `conditionalInvertibleProtocolSet` /
    /// `conditionalInvertibleProtocolsRequirementsCount` on the
    /// `TargetGenericContext`.
    package static func struct_InvertibleProtocolRequirementTest(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> StructDescriptor {
        try required(
            try machO.swift.typeContextDescriptors.compactMap(\.struct).first(where: { descriptor in
                try descriptor.name(in: machO) == "InvertibleProtocolRequirementTest"
            })
        )
    }

    /// Picks the generic struct
    /// `GenericRequirementVariants.BaseClassRequirementTest<Element: GenericBaseClassForRequirementTest>`
    /// from the `SymbolTestsCore` fixture. Exercises a `baseClass` generic
    /// requirement — surfaces a `GenericRequirementDescriptor` with kind
    /// `.baseClass`, content carrying a `RelativeDirectPointer<MangledName>`
    /// to the base-class mangled name.
    package static func struct_BaseClassRequirementTest(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> StructDescriptor {
        try required(
            try machO.swift.typeContextDescriptors.compactMap(\.struct).first(where: { descriptor in
                try descriptor.name(in: machO) == "BaseClassRequirementTest"
            })
        )
    }

    /// Picks an `AnonymousContextDescriptor` from the `SymbolTestsCore`
    /// fixture. Anonymous contexts arise from generic parameter scopes,
    /// closures, and other unnamed contexts; they don't appear directly in
    /// `__swift5_types`/`__swift5_types2` records, so we discover them by
    /// walking the parent chain of every type descriptor and returning the
    /// first anonymous one encountered.
    package static func anonymous_first(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> AnonymousContextDescriptor {
        for typeDescriptor in try machO.swift.contextDescriptors {
            var current: SymbolOrElement<ContextDescriptorWrapper>? = try typeDescriptor.parent(in: machO)
            while let cursor = current {
                if let resolved = cursor.resolved {
                    if let anonymous = resolved.anonymousContextDescriptor {
                        return anonymous
                    }
                    current = try resolved.parent(in: machO)
                } else {
                    current = nil
                }
            }
        }
        throw RequiredError.requiredNonOptional
    }

    /// Picks the `SymbolTestsCore` module's `ModuleContextDescriptor` —
    /// every type in the fixture chains up to it. Module contexts don't
    /// appear directly in `__swift5_types`/`__swift5_types2` records, so we
    /// discover them by walking the parent chain of every type descriptor
    /// and selecting the module whose `name(in:)` is `"SymbolTestsCore"`.
    package static func module_SymbolTestsCore(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> ModuleContextDescriptor {
        for typeDescriptor in try machO.swift.contextDescriptors {
            var current: SymbolOrElement<ContextDescriptorWrapper>? = try typeDescriptor.parent(in: machO)
            while let cursor = current {
                if let resolved = cursor.resolved {
                    if let module = resolved.moduleContextDescriptor,
                       try module.name(in: machO) == "SymbolTestsCore" {
                        return module
                    }
                    current = try resolved.parent(in: machO)
                } else {
                    current = nil
                }
            }
        }
        throw RequiredError.requiredNonOptional
    }

    /// Picks an `ExtensionContextDescriptor` from the `SymbolTestsCore`
    /// fixture. Extensions don't appear directly in
    /// `__swift5_types`/`__swift5_types2` records (only the types declared
    /// inside an extension do), so we discover them by walking the parent
    /// chain of every type descriptor and returning the first extension
    /// context encountered. The fixture declares several extensions (e.g.
    /// `Structs.StructTest: Protocols.ProtocolWitnessTableTest`).
    package static func extension_first(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> ExtensionContextDescriptor {
        for typeDescriptor in try machO.swift.contextDescriptors {
            var current: SymbolOrElement<ContextDescriptorWrapper>? = try typeDescriptor.parent(in: machO)
            while let cursor = current {
                if let resolved = cursor.resolved {
                    if let ext = resolved.extensionContextDescriptor {
                        return ext
                    }
                    current = try resolved.parent(in: machO)
                } else {
                    current = nil
                }
            }
        }
        throw RequiredError.requiredNonOptional
    }

    /// Picks the concrete plain Swift class `Classes.ClassTest` from the
    /// `SymbolTestsCore` fixture. Used as the primary class fixture: it has
    /// instance/dynamic vars and methods (so a non-empty vtable), no
    /// resilient superclass, no ObjC interop, and is not a generic class.
    package static func class_ClassTest(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> ClassDescriptor {
        try required(
            try machO.swift.typeContextDescriptors.compactMap(\.class).first(where: { descriptor in
                try descriptor.name(in: machO) == "ClassTest"
            })
        )
    }

    /// Picks `Classes.SubclassTest: ClassTest` from the `SymbolTestsCore`
    /// fixture. Used to exercise inheritance/superclass paths in the
    /// `ClassDescriptor` API surface (e.g. `superclassTypeMangledName`).
    package static func class_SubclassTest(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> ClassDescriptor {
        try required(
            try machO.swift.typeContextDescriptors.compactMap(\.class).first(where: { descriptor in
                try descriptor.name(in: machO) == "SubclassTest"
            })
        )
    }

    /// Picks the no-payload enum `Enums.NoPayloadEnumTest` (4 cases:
    /// north/south/east/west) from the `SymbolTestsCore` fixture. Used as
    /// the primary enum fixture: zero payload cases means `isMultiPayload`
    /// is false and `payloadSizeOffset` is zero.
    package static func enum_NoPayloadEnumTest(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> EnumDescriptor {
        try required(
            try machO.swift.typeContextDescriptors.compactMap(\.enum).first(where: { descriptor in
                try descriptor.name(in: machO) == "NoPayloadEnumTest"
            })
        )
    }

    /// Picks the single-payload enum `Enums.SinglePayloadEnumTest`
    /// (`case value(String)`, `case none`, `case error`) from the
    /// `SymbolTestsCore` fixture. Used to exercise the `isSinglePayload`
    /// branch of the predicate accessors on `EnumDescriptor`.
    package static func enum_SinglePayloadEnumTest(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> EnumDescriptor {
        try required(
            try machO.swift.typeContextDescriptors.compactMap(\.enum).first(where: { descriptor in
                try descriptor.name(in: machO) == "SinglePayloadEnumTest"
            })
        )
    }

    /// Picks the multi-payload enum `Enums.MultiPayloadEnumTests`
    /// (closure / NSObject / tuple / empty) from the `SymbolTestsCore`
    /// fixture. Used as the primary multi-payload fixture: it surfaces a
    /// `MultiPayloadEnumDescriptor` in `__swift5_mpenum` and exercises the
    /// `isMultiPayload` branch on `EnumDescriptor`.
    package static func enum_MultiPayloadEnumTest(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> EnumDescriptor {
        try required(
            try machO.swift.typeContextDescriptors.compactMap(\.enum).first(where: { descriptor in
                try descriptor.name(in: machO) == "MultiPayloadEnumTests"
            })
        )
    }

    /// Picks the `MultiPayloadEnumDescriptor` for `Enums.MultiPayloadEnumTests`
    /// from the `SymbolTestsCore` fixture's `__swift5_mpenum` section. The
    /// section emits one descriptor per multi-payload enum found.
    ///
    /// The mangled-name string applies Swift's identifier substitution rules
    /// (repeat tokens become `O[A-Z]` byte references), so the literal
    /// `MultiPayloadEnumTests` may not appear textually. Instead we resolve
    /// the matching `EnumDescriptor` (which uses its own `name(in:)` ivar)
    /// and pick the multi-payload descriptor whose mangled-name lookup
    /// targets it.
    package static func multiPayloadEnumDescriptor_MultiPayloadEnumTest(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> MultiPayloadEnumDescriptor {
        let enumDescriptor = try enum_MultiPayloadEnumTest(in: machO)
        let targetOffset = enumDescriptor.offset
        return try required(
            try machO.swift.multiPayloadEnumDescriptors.first(where: { descriptor in
                let mangledName = try descriptor.mangledTypeName(in: machO)
                for lookup in mangledName.lookupElements {
                    guard case .relative(let relative) = lookup.reference else { continue }
                    let resolvedOffset = lookup.offset + Int(relative.relativeOffset)
                    if resolvedOffset == targetOffset {
                        return true
                    }
                }
                return false
            })
        )
    }

    /// Picks the associated-type protocol `Protocols.ProtocolTest` from the
    /// `SymbolTestsCore` fixture. Used as the primary protocol fixture: it
    /// declares an associated type (`Body`) and the `body` requirement, and
    /// has a default implementation extension that surfaces a non-empty
    /// `associatedTypes(in:)` payload.
    package static func protocol_ProtocolTest(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> ProtocolDescriptor {
        try required(
            try machO.swift.protocolDescriptors.first(where: { descriptor in
                try descriptor.name(in: machO) == "ProtocolTest"
            })
        )
    }

    /// Picks `Protocols.ProtocolWitnessTableTest` from the `SymbolTestsCore`
    /// fixture. Used to exercise non-trivial witness-table layout: the
    /// protocol declares five method requirements (`a`/`b`/`c`/`d`/`e`),
    /// so `numRequirements` is non-zero and the trailing
    /// `ProtocolRequirement` array is fully populated.
    package static func protocol_ProtocolWitnessTableTest(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> ProtocolDescriptor {
        try required(
            try machO.swift.protocolDescriptors.first(where: { descriptor in
                try descriptor.name(in: machO) == "ProtocolWitnessTableTest"
            })
        )
    }

    /// Picks `Protocols.BaseProtocolTest` from the `SymbolTestsCore`
    /// fixture. Used as the base side of the inheritance fixture pair
    /// (`BaseProtocolTest` / `DerivedProtocolTest`). Has a single
    /// `baseMethod()` requirement.
    package static func protocol_BaseProtocolTest(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> ProtocolDescriptor {
        try required(
            try machO.swift.protocolDescriptors.first(where: { descriptor in
                try descriptor.name(in: machO) == "BaseProtocolTest"
            })
        )
    }

    /// Picks the first `ProtocolRecord` from the `SymbolTestsCore` fixture's
    /// `__swift5_protos` section. Each record is a one-pointer entry that
    /// resolves to a `ProtocolDescriptor`; we pick the first record so a
    /// stable, deterministic offset is always available.
    ///
    /// The section walk requires the concrete `MachOFile` API
    /// (`section(for:)`), so the helper is `MachOFile`-only. The companion
    /// `MachOImage` lookup is performed by re-reading the same section
    /// offset from the in-memory image.
    package static func protocolRecord_first(in machO: MachOFile) throws -> ProtocolRecord {
        let section = try machO.section(for: .__swift5_protos)
        let sectionOffset: Int
        if let cache = machO.cache {
            sectionOffset = section.address - cache.mainCacheHeader.sharedRegionStart.cast()
        } else {
            sectionOffset = section.offset
        }
        let recordSize = ProtocolRecord.layoutSize
        let count = section.size / recordSize
        guard count > 0 else { throw RequiredError.requiredNonOptional }
        let records: [ProtocolRecord] = try machO.readWrapperElements(
            offset: sectionOffset,
            numberOfElements: count
        )
        return try required(records.first)
    }

    /// Image-side companion to `protocolRecord_first(in:)`. Resolves the
    /// `__swift5_protos` section from the in-memory MachOImage layout so
    /// the Suite can compare records read via two different code paths.
    package static func protocolRecord_first(in machO: MachOImage) throws -> ProtocolRecord {
        let section = try machO.section(for: .__swift5_protos)
        let sectionOffset: Int
        if let cache = machO.cache {
            sectionOffset = section.address - cache.mainCacheHeader.sharedRegionStart.cast()
        } else {
            sectionOffset = section.offset
        }
        let recordSize = ProtocolRecord.layoutSize
        let count = section.size / recordSize
        guard count > 0 else { throw RequiredError.requiredNonOptional }
        let records: [ProtocolRecord] = try machO.readWrapperElements(
            offset: sectionOffset,
            numberOfElements: count
        )
        return try required(records.first)
    }

    /// Picks the first `ProtocolConformance` from the `SymbolTestsCore`
    /// fixture that declares resilient witnesses. Used to surface a
    /// non-empty `ResilientWitnessesHeader` and at least one
    /// `ResilientWitness`. Falls back to a `RequiredError` if no
    /// resilient-witness conformance exists.
    package static func protocolConformance_resilientWitnessFirst(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> ProtocolConformance {
        try required(
            try machO.swift.protocolConformances.first(where: { conformance in
                conformance.descriptor.flags.hasResilientWitnesses
                    && !conformance.resilientWitnesses.isEmpty
            })
        )
    }

    /// Picks the `Structs.StructTest: Protocols.ProtocolTest` conformance
    /// from the `SymbolTestsCore` fixture. Used as the primary
    /// `ProtocolConformance` fixture: the conforming type is a concrete
    /// struct, the protocol is the plain associated-type-bearing
    /// `ProtocolTest`, and the conformance is non-retroactive with no
    /// global-actor isolation, so the trailing-objects layout exercises
    /// the simplest path.
    ///
    /// Identification scheme: walk the conformance list and match the
    /// pair (conforming-type-descriptor name, protocol-descriptor name).
    /// Both names are resolved via `NamedContextDescriptorProtocol.name(in:)`
    /// and are unique within the fixture, so no parent-chain disambiguator
    /// is needed.
    package static func protocolConformance_StructTestProtocolTest(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> ProtocolConformance {
        try required(
            try machO.swift.protocolConformances.first(where: { conformance in
                guard try conformanceProtocolName(of: conformance, in: machO) == "ProtocolTest" else {
                    return false
                }
                return try conformanceTypeName(of: conformance, in: machO) == "StructTest"
            })
        )
    }

    /// Picks the first conditional `ProtocolConformance` from the
    /// `SymbolTestsCore` fixture — i.e. a conformance whose
    /// `ProtocolConformanceFlags.numConditionalRequirements > 0`. Used to
    /// exercise the trailing `conditionalRequirements` array on
    /// `ProtocolConformance` and the `numConditionalRequirements` accessor
    /// on `ProtocolConformanceFlags`. The fixture's
    /// `ConditionalConformanceVariants.ConditionalContainerTest` extensions
    /// (e.g. `: Equatable where Element: Equatable`) emit several
    /// such conformances.
    package static func protocolConformance_conditionalFirst(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> ProtocolConformance {
        try required(
            try machO.swift.protocolConformances.first(where: { conformance in
                conformance.descriptor.flags.numConditionalRequirements > 0
                    && !conformance.conditionalRequirements.isEmpty
            })
        )
    }

    /// Picks the first `ProtocolConformance` from the `SymbolTestsCore`
    /// fixture that has the `hasGlobalActorIsolation` bit set. The fixture
    /// declares two such conformances under `Actors`:
    ///   - `Actors.GlobalActorIsolatedConformanceTest: @MainActor Actors.GlobalActorIsolatedProtocolTest`
    ///   - `Actors.GlobalActorIsolatedConformanceTest: @CustomGlobalActor Actors.CustomGlobalActorIsolatedProtocolTest`
    /// Used to surface a non-nil `globalActorReference` so the
    /// `GlobalActorReference` Suite has a live carrier.
    package static func protocolConformance_globalActorFirst(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> ProtocolConformance {
        try required(
            try machO.swift.protocolConformances.first(where: { conformance in
                conformance.descriptor.flags.hasGlobalActorIsolation
                    && conformance.globalActorReference != nil
            })
        )
    }

    /// Helper: extract the protocol-descriptor name from a conformance,
    /// returning `nil` when the protocol pointer is unresolved (a
    /// cross-image symbol bind) or absent.
    private static func conformanceProtocolName(
        of conformance: ProtocolConformance,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> String? {
        guard let protocolReference = conformance.protocol else { return nil }
        guard case .element(let descriptor) = protocolReference else { return nil }
        return try descriptor.name(in: machO)
    }

    /// Helper: extract the conforming-type-descriptor name from a
    /// conformance, returning `nil` for indirect / ObjC type references
    /// (which don't carry a Swift name we can match against).
    private static func conformanceTypeName(
        of conformance: ProtocolConformance,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> String? {
        switch conformance.typeReference {
        case .directTypeDescriptor(let wrapper):
            guard let wrapper else { return nil }
            return try wrapper.namedContextDescriptor?.name(in: machO)
        case .indirectTypeDescriptor:
            return nil
        case .directObjCClassName:
            return nil
        case .indirectObjCClass:
            return nil
        }
    }

    /// Picks the first ObjC protocol prefix referenced anywhere in the
    /// `SymbolTestsCore` fixture. The fixture's `ObjCInheritingProtocolTest`
    /// inherits from `NSObjectProtocol`, so at least one ObjC reference is
    /// materialized via the protocol's requirementInSignatures.
    ///
    /// We materialize a `Protocol` for `ObjCInheritingProtocolTest`, then
    /// walk its requirementInSignatures looking for a `.protocol(ObjC(...))`
    /// case, returning the resolved `ObjCProtocolPrefix`.
    package static func objcProtocolPrefix_first(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> ObjCProtocolPrefix {
        let inheritingProtoDescriptor = try required(
            try machO.swift.protocolDescriptors.first(where: { descriptor in
                try descriptor.name(in: machO) == "ObjCInheritingProtocolTest"
            })
        )
        let protocolType = try `Protocol`(descriptor: inheritingProtoDescriptor, in: machO)
        for requirementInSignature in protocolType.requirementInSignatures {
            if case .protocol(let symbolOrElement) = requirementInSignature.content,
               case .element(let descriptorWithObjCInterop) = symbolOrElement,
               case .objc(let objcPrefix) = descriptorWithObjCInterop {
                return objcPrefix
            }
        }
        throw RequiredError.requiredNonOptional
    }

    /// Picks the first `ClassDescriptor` from the `SymbolTestsCore` fixture
    /// that carries the `hasSingletonMetadataInitialization` bit. Used as
    /// the live carrier for `SingletonMetadataInitialization`. The bit
    /// fires for resilient-superclass scenarios and certain generic-class
    /// shapes (e.g. `Classes.ExternalSwiftSubclassTest`).
    package static func class_singletonMetadataInitFirst(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> ClassDescriptor {
        try required(
            try machO.swift.typeContextDescriptors.compactMap(\.class).first(where: { descriptor in
                descriptor.hasSingletonMetadataInitialization
            })
        )
    }

    /// Picks the SymbolTestsCore class
    /// `ResilientClassFixtures.ResilientChild` — a subclass of the
    /// cross-module `SymbolTestsHelper.ResilientBase` (library-evolution
    /// build mode), which causes the descriptor to carry a
    /// `ResilientSuperclass` tail record (tail-objects layout) and forces
    /// metadata bounds to be resolved at runtime via
    /// `StoredClassMetadataBounds`.
    package static func class_ResilientChild(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> ClassDescriptor {
        try required(
            try machO.swift.typeContextDescriptors.compactMap(\.class).first(where: { descriptor in
                try descriptor.name(in: machO) == "ResilientChild"
            })
        )
    }

    /// Picks the SymbolTestsCore class
    /// `ObjCClassWrapperFixtures.ObjCBridge` — an NSObject-derived Swift
    /// class. The class's metadata accessor returns
    /// `ClassMetadataObjCInterop`, and its superclass chain reaches
    /// NSObject's `ObjCClassWrapperMetadata` (kind 0x305). Phase B3
    /// introduced the fixture to give the ObjC-interop metadata Suites a
    /// fixture-owned, deterministic carrier (rather than relying on a
    /// plain Swift class that happens to use the ObjC-interop metadata
    /// shape on Apple platforms).
    package static func class_ObjCBridge(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> ClassDescriptor {
        try required(
            try machO.swift.typeContextDescriptors.compactMap(\.class).first(where: { descriptor in
                try descriptor.name(in: machO) == "ObjCBridge"
            })
        )
    }

    /// Picks the SymbolTestsCore class
    /// `ObjCClassWrapperFixtures.ObjCBridgeWithProto` — an NSObject-derived
    /// Swift class conforming to the `@objc protocol ObjCProto`. Phase B3
    /// reserves the picker for completeness; `@objc protocol` does not
    /// emit a Swift-side conformance descriptor, so the conformance is
    /// not reachable through `swift.protocolConformances`.
    package static func class_ObjCBridgeWithProto(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> ClassDescriptor {
        try required(
            try machO.swift.typeContextDescriptors.compactMap(\.class).first(where: { descriptor in
                try descriptor.name(in: machO) == "ObjCBridgeWithProto"
            })
        )
    }

    /// Picks the SymbolTestsCore class
    /// `ObjCResilientStubFixtures.ResilientObjCStubChild` — a non-generic
    /// Swift class subclassing the cross-module
    /// `SymbolTestsHelper.Object`, which forces the resilient metadata
    /// strategy. Combined with ObjC interop being on, the Swift compiler
    /// emits an `ObjCResilientClassStubInfo` trailing record on the
    /// class descriptor (and a corresponding `<mangled>CMt` "full ObjC
    /// resilient class stub" symbol). Phase B4 added the fixture to give
    /// the `ObjCResilientClassStubInfo` Suite a stably-named,
    /// deterministic carrier independent of any other fixture's
    /// vTable/method shape.
    package static func class_ResilientObjCStubChild(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> ClassDescriptor {
        try required(
            try machO.swift.typeContextDescriptors.compactMap(\.class).first(where: { descriptor in
                try descriptor.name(in: machO) == "ResilientObjCStubChild"
            })
        )
    }

    /// Picks the `AssociatedTypeDescriptor` whose conforming type is
    /// `AssociatedTypeWitnessPatterns.ConcreteWitnessTest` and whose protocol
    /// is `AssociatedTypeWitnessPatterns.AssociatedPatternProtocol`. The
    /// fixture declares this conformance with five concrete witnesses
    /// (`First = Int`, `Second = [String]`, `Third = Double`, `Fourth = Bool`,
    /// `Fifth = Character`), so the descriptor surfaces five
    /// `AssociatedTypeRecord`s — non-trivial test data for both
    /// `AssociatedTypeDescriptor` (the raw payload) and `AssociatedType`
    /// (the high-level wrapper).
    ///
    /// Identification scheme: `AssociatedTypeDescriptor` does not carry a
    /// direct name. Instead its `conformingTypeName(in:)` resolves to a
    /// `MangledName` whose lookup elements point back to the
    /// `TypeContextDescriptor` for the conforming type. We resolve the
    /// `StructDescriptor` for `ConcreteWitnessTest` first, then walk the
    /// `__swift5_assocty` records and pick the one whose conformingTypeName
    /// targets that descriptor's offset. (Mirrors
    /// `multiPayloadEnumDescriptor_MultiPayloadEnumTest`'s strategy.)
    package static func associatedTypeDescriptor_ConcreteWitnessTest(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> AssociatedTypeDescriptor {
        let conformingDescriptor = try required(
            try machO.swift.typeContextDescriptors.compactMap(\.struct).first(where: { descriptor in
                try descriptor.name(in: machO) == "ConcreteWitnessTest"
            })
        )
        let targetOffset = conformingDescriptor.offset
        return try required(
            try machO.swift.associatedTypeDescriptors.first(where: { descriptor in
                let mangledName = try descriptor.conformingTypeName(in: machO)
                for lookup in mangledName.lookupElements {
                    guard case .relative(let relative) = lookup.reference else { continue }
                    let resolvedOffset = lookup.offset + Int(relative.relativeOffset)
                    if resolvedOffset == targetOffset {
                        return true
                    }
                }
                return false
            })
        )
    }

    /// Picks the first `BuiltinTypeDescriptor` from the `SymbolTestsCore`
    /// fixture's `__swift5_builtin` section. The fixture's
    /// `BuiltinTypeFields` namespace declares structs with `Int`/`Float`/
    /// `Bool`/`Character`/`String` fields, which causes the Swift compiler
    /// to emit one `BuiltinTypeDescriptor` per primitive backing type used
    /// in fields. We pick the first descriptor for stability — the order
    /// is deterministic across builds with the same toolchain.
    package static func builtinTypeDescriptor_first(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> BuiltinTypeDescriptor {
        try required(try machO.swift.builtinTypeDescriptors.first)
    }

    // Note: an `opaqueTypeDescriptor_first` picker was attempted but
    // SymbolTestsCore's opaque-type descriptors don't surface via
    // `swift.contextDescriptors` (the `__swift5_types2` records on the
    // current toolchain index struct/enum extras, not opaque types) nor
    // via any context's parent chain. The OpaqueType, OpaqueTypeDescriptor,
    // and OpaqueTypeDescriptorProtocol Suites therefore exercise their
    // public surface against synthetic memberwise instances. Adding a
    // fixture variant that emits an opaque type via a discoverable
    // channel (e.g. a top-level typealias whose underlying-type
    // relationship can be walked back) would let those Suites use a
    // live carrier.

}
