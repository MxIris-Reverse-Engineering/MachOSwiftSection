import Foundation
import MachOExtensions
import MachOFoundation
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
}
