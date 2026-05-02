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

    /// Picks `Classes.ExternalObjCSubclassTest: NSObject` from the
    /// `SymbolTestsCore` fixture. Used to exercise the ObjC-interop class
    /// API surface (vtable shape, resilient class stub paths, etc.).
    package static func class_ObjCInteropTest(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> ClassDescriptor {
        try required(
            try machO.swift.typeContextDescriptors.compactMap(\.class).first(where: { descriptor in
                try descriptor.name(in: machO) == "ExternalObjCSubclassTest"
            })
        )
    }
}
