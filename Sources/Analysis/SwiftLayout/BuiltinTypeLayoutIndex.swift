import MachOSwiftSection
@_spi(Internals) import SwiftInspection
import Demangling

/// A per-image index of the `__swift5_builtin` section's `BuiltinTypeDescriptor`
/// records, keyed by the type's fully-qualified name (e.g. `"__C.CGRect"`,
/// `"SymbolTestsCore.Enums.MultiPayloadEnumTests"`) — or, for a builtin leaf
/// type, by the builtin's own name (`"Builtin.Int1"`) — each carrying the
/// statically embedded `(size, stride, alignment, extra inhabitants)`.
///
/// The compiler emits a builtin descriptor for a type whose layout the
/// reflection reader cannot derive structurally — imported C value types and
/// multi-payload enums in particular — recording the layout Clang / IRGen
/// computed at compile time. Imported C records are emitted in *every image
/// that references the type reflectively* (e.g. as a stored field); enum
/// records are emitted by the *declaring* module. This is the authoritative
/// whole-type layout for those types, which the resolver consults before its
/// structural paths.
///
/// libswiftCore additionally records the compiler's builtin leaf types
/// (`Builtin.Int1`, `Builtin.BridgeObject`, `Builtin.FPIEEE16`, …), the
/// layouts every standard library type bottoms out in: IRGen collects the
/// builtin types a field mentions only while compiling the standard library
/// (`GenReflection.cpp`, `addBuiltinTypeRefs`). Every other image declaring
/// builtin-typed fields (`_Concurrency`) carries none of them; the resolver
/// answers those from its own fallback.
///
/// A **generic** multi-payload enum gets a record exactly when its layout is
/// argument-independent (statically fixed — every payload's layout resolves
/// without an argument), in which case the record's quintuple holds for the
/// unbound form and every instantiation alike; an argument-dependent generic
/// enum gets no record, so record presence is the compiler's own
/// fixed-vs-runtime-tagged verdict, and the generic-argument-free key below is
/// safe for instantiated lookups.
///
/// A nominal type's descriptor `typeName` is a **symbolic reference** (a
/// relative pointer to the type's context descriptor), so its raw string is
/// empty; the name is recovered by demangling, then keyed with the same
/// `nominalQualifiedName` formatting the resolver looks types up by. A builtin
/// leaf's is a plain mangling (`Bi1_`), keyed by the name it demangles to —
/// the spelling the resolver looks a `.builtinTypeName` node up by.
public struct BuiltinTypeLayoutIndex: Sendable {
    private let layoutsByTypeName: [String: StaticTypeLayout]

    public init(machO: some MachOSwiftSectionRepresentableWithCache) throws {
        var index: [String: StaticTypeLayout] = [:]
        // A missing `__swift5_builtin` section is a normal state — most images
        // emit no builtin descriptors — so it yields an empty index rather than
        // failing. This matters for dependency-closure images (a sibling
        // framework, a pure-ObjC/C dylib) that have no builtin section at all.
        let builtinTypeDescriptors: [BuiltinTypeDescriptor]
        do {
            builtinTypeDescriptors = try machO.swift.builtinTypeDescriptors
        } catch let MachOSwiftSectionError.sectionNotFound(section, _) where section == .__swift5_builtin {
            builtinTypeDescriptors = []
        }
        for descriptor in builtinTypeDescriptors {
            guard let mangledTypeName = try descriptor.typeName(in: machO.context) else { continue }
            let demangledNode = try? SymbolicDemangler.demangleType(for: mangledTypeName, in: machO.context)
            // A record whose type reference is a *concrete* bound-generic
            // instantiation (`Foo<Int>`) describes only that instantiation;
            // under the generic-argument-free key it would be misattributed to
            // every other instantiation, so skip it. Declaration records — the
            // only shape observed across the OS frameworks, including for
            // argument-independent generic multi-payload enums — demangle as
            // plain nominal references and enter the map under the
            // generic-argument-free name the resolver looks types up by.
            if let demangledNode, Self.isConcreteBoundGenericReference(demangledNode) { continue }
            let typeName: String
            if let demangledNode, let nominalQualifiedName = NodeTypeNaming.nominalQualifiedName(of: demangledNode) {
                typeName = nominalQualifiedName
            } else if let demangledNode, let builtinTypeName = Self.builtinTypeName(of: demangledNode) {
                typeName = builtinTypeName
            } else {
                // Fall back to the raw string for any plain-named entry.
                let rawName = mangledTypeName.typeString
                guard !rawName.isEmpty else { continue }
                typeName = rawName
            }
            let layout = StaticTypeLayout(
                size: Int(descriptor.layout.size),
                stride: Int(descriptor.layout.stride),
                alignmentMask: max(0, descriptor.alignment - 1),
                extraInhabitantCount: Int(descriptor.layout.numExtraInhabitants),
                isBitwiseTakable: descriptor.isBitwiseTakable
            )
            // First writer wins: qualified names are unique per declaration
            // (instantiation-specific records are skipped above).
            if index[typeName] == nil {
                index[typeName] = layout
            }
        }
        self.layoutsByTypeName = index
    }

    /// The name of a builtin type reference (`Builtin.Int1` for `Bi1_`), or
    /// `nil` for any other type.
    private static func builtinTypeName(of node: Node) -> String? {
        let typeNode = node.kind == .type ? node.firstChild : node
        guard let typeNode, typeNode.kind == .builtinTypeName else { return nil }
        return typeNode.text
    }

    /// Whether a demangled type reference is a concrete bound-generic
    /// instantiation (`Foo<Int>`): it carries a bound-generic shell and no
    /// type parameters. The unbound declaration records the compiler emits for
    /// generic multi-payload enums demangle as plain nominal references and
    /// return `false` here.
    private static func isConcreteBoundGenericReference(_ node: Node) -> Bool {
        let containsBoundGenericShell = node.first(where: { childNode in
            childNode.kind == .boundGenericStructure
                || childNode.kind == .boundGenericEnum
                || childNode.kind == .boundGenericClass
        }) != nil
        guard containsBoundGenericShell else { return false }
        return node.first(where: { $0.kind == .dependentGenericParamType }) == nil
    }

    /// Returns the embedded whole-type layout for a fully-qualified type name or
    /// a builtin type name (`"Builtin.Int1"`), or `nil` if this image emits no
    /// builtin descriptor for it.
    public func layout(forTypeName qualifiedTypeName: String) -> StaticTypeLayout? {
        layoutsByTypeName[qualifiedTypeName]
    }
}
