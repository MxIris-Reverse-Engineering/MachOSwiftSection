import Foundation
import Testing
import MachOKit
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@testable import SwiftDump
import MachOFixtureSupport
import Semantic

// MARK: - Specialized dumper field-type substitution

/// End-to-end check on the dumper-side substitution that pairs with
/// `SpecializedMangledNameResolutionTests`: when a `StructDumper` /
/// `EnumDumper` / `ClassDumper` runs against a specialized in-process
/// metadata, each field's printed type must mention the concrete generic
/// argument instead of the unbound parameter name.
///
/// The unit under test is `TypedDumper.fieldDemangledTypeNode(for:)` plus
/// the dumper-side wiring that calls it. We render the dumper's `body`
/// to a plain `String` and assert containment / non-containment on the
/// substituted type name.
@Suite(.serialized)
struct SpecializedDumperFieldTypeTests {
    private typealias Fixtures = SpecializedMangledNameFixtures

    private var machO: MachOImage { .current() }

    private var configuration: DumperConfiguration {
        DumperConfiguration(demangleResolver: .options(.test))
    }

    // MARK: - Helpers

    private func structDescriptor(named nameContains: String) throws -> StructDescriptor {
        try #require(
            try machO.swift.typeContextDescriptors.first {
                try $0.struct?.name(in: machO).contains(nameContains) == true
            }?.struct,
            "expected a struct descriptor whose name contains \"\(nameContains)\""
        )
    }

    private func enumDescriptor(named nameContains: String) throws -> EnumDescriptor {
        try #require(
            try machO.swift.typeContextDescriptors.first {
                try $0.enum?.name(in: machO).contains(nameContains) == true
            }?.enum,
            "expected an enum descriptor whose name contains \"\(nameContains)\""
        )
    }

    private func classDescriptor(named nameContains: String) throws -> ClassDescriptor {
        try #require(
            try machO.swift.typeContextDescriptors.first {
                try $0.class?.name(in: machO).contains(nameContains) == true
            }?.class,
            "expected a class descriptor whose name contains \"\(nameContains)\""
        )
    }

    // MARK: - Struct

    @Test("specialized struct dump renders concrete field type instead of generic param")
    func specializedStructFieldShowsConcreteType() async throws {
        _ = Fixtures.SingleParameterBox<Int>.self

        let descriptor = try structDescriptor(named: "SingleParameterBox")
        let structValue = try Struct(descriptor: descriptor, in: machO)
        let specializedMetadata = try StructMetadata.createInProcess(Fixtures.SingleParameterBox<Int>.self)
        let metadataContext = DumperMetadataContext(metadata: specializedMetadata, readingContext: InProcessContext.shared)

        let dumper = StructDumper(structValue, metadataContext: metadataContext, using: configuration, in: machO)
        let renderedFields = try await dumper.fields.string

        // The unbound source was `let value: A`. Substituted output must
        // surface `Int` somewhere in the field block.
        #expect(renderedFields.contains("Int"),
                "expected substituted concrete type 'Int' in fields; got: \(renderedFields)")
    }

    @Test("two specializations of one struct render distinct concrete field types")
    func twoStructSpecializationsShowDistinctTypes() async throws {
        _ = Fixtures.SingleParameterBox<Int>.self
        _ = Fixtures.SingleParameterBox<String>.self

        let descriptor = try structDescriptor(named: "SingleParameterBox")
        let structValue = try Struct(descriptor: descriptor, in: machO)

        let intMetadata = try StructMetadata.createInProcess(Fixtures.SingleParameterBox<Int>.self)
        let intContext = DumperMetadataContext(metadata: intMetadata, readingContext: InProcessContext.shared)
        let intDumper = StructDumper(structValue, metadataContext: intContext, using: configuration, in: machO)
        let intFields = try await intDumper.fields.string

        let stringMetadata = try StructMetadata.createInProcess(Fixtures.SingleParameterBox<String>.self)
        let stringContext = DumperMetadataContext(metadata: stringMetadata, readingContext: InProcessContext.shared)
        let stringDumper = StructDumper(structValue, metadataContext: stringContext, using: configuration, in: machO)
        let stringFields = try await stringDumper.fields.string

        // Each specialization must point at its own resolved concrete type
        // — same dumper class, same descriptor, but different metadata
        // contexts feed different substitution paths.
        #expect(intFields.contains("Int"))
        #expect(stringFields.contains("String"))
        #expect(intFields != stringFields,
                "two specializations should render different field text; both produced: \(intFields)")
    }

    @Test("specialized struct substitutes inside Array<A> field")
    func specializedStructSubstitutesIntoArrayField() async throws {
        _ = Fixtures.GenericArrayWrapper<Double>.self

        let descriptor = try structDescriptor(named: "GenericArrayWrapper")
        let structValue = try Struct(descriptor: descriptor, in: machO)
        let specializedMetadata = try StructMetadata.createInProcess(Fixtures.GenericArrayWrapper<Double>.self)
        let metadataContext = DumperMetadataContext(metadata: specializedMetadata, readingContext: InProcessContext.shared)

        let dumper = StructDumper(structValue, metadataContext: metadataContext, using: configuration, in: machO)
        let renderedFields = try await dumper.fields.string

        // The unbound source was `let values: [A]`. After substitution the
        // rendered text must mention Double (inside whatever Array form
        // the demangler produces — e.g. "[Double]" or "Array<Double>").
        #expect(renderedFields.contains("Double"),
                "expected substituted Double in Array<A> field; got: \(renderedFields)")
    }

    // MARK: - Enum

    @Test("specialized enum dump renders concrete payload type")
    func specializedEnumPayloadShowsConcreteType() async throws {
        _ = Fixtures.GenericResultEnum<Int, Fixtures.FixtureError>.self

        let descriptor = try enumDescriptor(named: "GenericResultEnum")
        let enumValue = try Enum(descriptor: descriptor, in: machO)
        let specializedMetadata = try EnumMetadata.createInProcess(Fixtures.GenericResultEnum<Int, Fixtures.FixtureError>.self)
        let metadataContext = DumperMetadataContext(metadata: specializedMetadata, readingContext: InProcessContext.shared)

        let dumper = EnumDumper(enumValue, metadataContext: metadataContext, using: configuration, in: machO)
        let renderedFields = try await dumper.fields.string

        // `case success(A)` substitutes A=Int; the rendered case payload
        // must mention Int rather than the generic param.
        #expect(renderedFields.contains("Int"),
                "expected substituted Int in enum payload; got: \(renderedFields)")
    }

    // MARK: - Class

    @Test("specialized class dump renders concrete field type")
    func specializedClassFieldShowsConcreteType() async throws {
        _ = Fixtures.GenericContainerClass<Int>.self

        let descriptor = try classDescriptor(named: "GenericContainerClass")
        let classValue = try Class(descriptor: descriptor, in: machO)
        let specializedMetadata = try ClassMetadataObjCInterop.createInProcess(Fixtures.GenericContainerClass<Int>.self)
        let metadataContext = DumperMetadataContext(metadata: specializedMetadata, readingContext: InProcessContext.shared)

        let dumper = ClassDumper(classValue, metadataContext: metadataContext, using: configuration, in: machO)
        let renderedFields = try await dumper.fields.string

        #expect(renderedFields.contains("Int"),
                "expected substituted Int in class field; got: \(renderedFields)")
    }

    // MARK: - Declaration substitution

    @Test("specialized struct declaration shows bound generic name and skips signature")
    func specializedStructDeclarationShowsBoundName() async throws {
        _ = Fixtures.SingleParameterBox<Int>.self

        let descriptor = try structDescriptor(named: "SingleParameterBox")
        let structValue = try Struct(descriptor: descriptor, in: machO)
        let specializedMetadata = try StructMetadata.createInProcess(Fixtures.SingleParameterBox<Int>.self)
        let metadataContext = DumperMetadataContext(metadata: specializedMetadata, readingContext: InProcessContext.shared)

        let dumper = StructDumper(structValue, metadataContext: metadataContext, using: configuration, in: machO)
        let renderedDeclaration = try await dumper.declaration.string

        // Bound name carries the type argument; the unbound parameter name
        // `A` must NOT appear (would imply we re-emitted the generic clause).
        #expect(renderedDeclaration.contains("Int"),
                "expected bound declaration to mention Int; got: \(renderedDeclaration)")
        #expect(!renderedDeclaration.contains("<A>"),
                "expected bound declaration to drop the unbound `<A>` form; got: \(renderedDeclaration)")
    }

    @Test("two specializations render distinct declarations from the same descriptor")
    func twoSpecializationsRenderDistinctDeclarations() async throws {
        _ = Fixtures.SingleParameterBox<Int>.self
        _ = Fixtures.SingleParameterBox<String>.self

        let descriptor = try structDescriptor(named: "SingleParameterBox")
        let structValue = try Struct(descriptor: descriptor, in: machO)

        let intMetadata = try StructMetadata.createInProcess(Fixtures.SingleParameterBox<Int>.self)
        let intDumper = StructDumper(
            structValue,
            metadataContext: DumperMetadataContext(metadata: intMetadata, readingContext: InProcessContext.shared),
            using: configuration,
            in: machO
        )
        let intDeclaration = try await intDumper.declaration.string

        let stringMetadata = try StructMetadata.createInProcess(Fixtures.SingleParameterBox<String>.self)
        let stringDumper = StructDumper(
            structValue,
            metadataContext: DumperMetadataContext(metadata: stringMetadata, readingContext: InProcessContext.shared),
            using: configuration,
            in: machO
        )
        let stringDeclaration = try await stringDumper.declaration.string

        #expect(intDeclaration.contains("Int"))
        #expect(stringDeclaration.contains("String"))
        #expect(intDeclaration != stringDeclaration,
                "different specializations should produce distinct declarations; both produced: \(intDeclaration)")
    }

    @Test("specialized class declaration shows bound generic name")
    func specializedClassDeclarationShowsBoundName() async throws {
        _ = Fixtures.GenericContainerClass<Int>.self

        let descriptor = try classDescriptor(named: "GenericContainerClass")
        let classValue = try Class(descriptor: descriptor, in: machO)
        let specializedMetadata = try ClassMetadataObjCInterop.createInProcess(Fixtures.GenericContainerClass<Int>.self)
        let metadataContext = DumperMetadataContext(metadata: specializedMetadata, readingContext: InProcessContext.shared)

        let dumper = ClassDumper(classValue, metadataContext: metadataContext, using: configuration, in: machO)
        let renderedDeclaration = try await dumper.declaration.string

        #expect(renderedDeclaration.contains("Int"),
                "expected bound class declaration to mention Int; got: \(renderedDeclaration)")
        #expect(!renderedDeclaration.contains("<A>"),
                "expected bound class declaration to drop unbound `<A>` form; got: \(renderedDeclaration)")
    }

    @Test("non-specialized struct declaration keeps unbound generic clause")
    func nonSpecializedStructDeclarationKeepsUnboundClause() async throws {
        // Sanity: when the dumper has no metadataContext, declaration must
        // fall back to the existing unbound path — the bound substitution
        // is gated on the in-process specialized metadata being present.
        let descriptor = try structDescriptor(named: "SingleParameterBox")
        let structValue = try Struct(descriptor: descriptor, in: machO)

        let dumper = StructDumper(structValue, using: configuration, in: machO)
        let renderedDeclaration = try await dumper.declaration.string

        // Without a metadata context, we expect the unbound generic clause
        // (e.g. `<A>`) to appear and no concrete substitution.
        #expect(renderedDeclaration.contains("<A>"),
                "expected unbound declaration to keep `<A>`; got: \(renderedDeclaration)")
    }

    // MARK: - Expanded-field-offset substitution

    @Test("expanded field offsets substitute generic params at the top hop")
    func expandedFieldOffsetsSubstituteAtTopHop() async throws {
        _ = Fixtures.NestedStructHostingStruct<Int>.self

        let descriptor = try structDescriptor(named: "NestedStructHostingStruct")
        let structValue = try Struct(descriptor: descriptor, in: machO)
        let specializedMetadata = try StructMetadata.createInProcess(Fixtures.NestedStructHostingStruct<Int>.self)
        let metadataContext = DumperMetadataContext(metadata: specializedMetadata, readingContext: InProcessContext.shared)

        // Turn on the expanded-field-offset path so the dumper actually
        // walks nested fields under each top-level field.
        var expandedConfig = configuration
        expandedConfig.printFieldOffset = true
        expandedConfig.printExpandedFieldOffsets = true

        let dumper = StructDumper(structValue, metadataContext: metadataContext, using: expandedConfig, in: machO)
        let body = try await dumper.body.string

        // Expanded-offset comments walk *into* each field's type; for
        // `inner: SingleParameterBox<A>` substituted to
        // `SingleParameterBox<Int>`, the first nested comment line is the
        // box's `value: A` field. Substitution must propagate through the
        // top-level dumper context so we see `value (Swift.Int)` rather
        // than the unbound `value (A)` form.
        //
        // Pre-fix, the top hop's bare `getTypeByMangledNameInContext` can't
        // resolve the generic `inner` type, the gate `!descriptor.isGeneric`
        // would also reject the resolved generic struct, and we'd see no
        // expanded line at all.
        #expect(body.contains("value (Swift.Int)") || body.contains("value (Int)"),
                "expected expanded line to substitute A → Int; got: \(body)")
    }

    @Test("expanded field offsets recurse with nested specialized metadata")
    func expandedFieldOffsetsRecurseWithNestedMetadata() async throws {
        _ = Fixtures.NestedStructHostingStruct<Double>.self

        let descriptor = try structDescriptor(named: "NestedStructHostingStruct")
        let structValue = try Struct(descriptor: descriptor, in: machO)
        let specializedMetadata = try StructMetadata.createInProcess(Fixtures.NestedStructHostingStruct<Double>.self)
        let metadataContext = DumperMetadataContext(metadata: specializedMetadata, readingContext: InProcessContext.shared)

        var expandedConfig = configuration
        expandedConfig.printFieldOffset = true
        expandedConfig.printExpandedFieldOffsets = true

        let dumper = StructDumper(structValue, metadataContext: metadataContext, using: expandedConfig, in: machO)
        let body = try await dumper.body.string

        // The recursive walk needs the *nested* `SingleParameterBox<Double>`
        // metadata as the substitution context for its `value: A` field.
        // If recursion fell back to the bare resolver, `value` would render
        // with the unbound `A`, so we'd see "value (A):" rather than the
        // substituted form below.
        #expect(body.contains("value (Double):") || body.contains("value (Swift.Double):"),
                "expected nested expanded line to substitute A → Double; got: \(body)")
    }

    // MARK: - Bound declaration semantic styling

    @Test("specialized name keeps inner type arguments at .name (not .declaration)")
    func specializedNameKeepsInnerArgumentsAtNameContext() async throws {
        // The bound name `SingleParameterBox<Int>` ought to look semantically
        // like the unbound declaration `SingleParameterBox` plus a
        // *type-reference* `Int` inside `<...>` — exactly the way a regular
        // type reference is rendered elsewhere. Pre-fix, the blanket
        // `replacingTypeNameOrOtherToTypeDeclaration()` walk upgraded every
        // nested `.type(_, .name)` to `.type(_, .declaration)`, so the inner
        // `Int` ended up tagged as a declaration too. This test pins that
        // the head and the inner argument now carry distinct semantic
        // contexts.
        _ = Fixtures.SingleParameterBox<Int>.self

        let descriptor = try structDescriptor(named: "SingleParameterBox")
        let structValue = try Struct(descriptor: descriptor, in: machO)
        let specializedMetadata = try StructMetadata.createInProcess(Fixtures.SingleParameterBox<Int>.self)
        let metadataContext = DumperMetadataContext(metadata: specializedMetadata, readingContext: InProcessContext.shared)

        let dumper = StructDumper(structValue, metadataContext: metadataContext, using: configuration, in: machO)
        let renderedName = try await dumper.name

        var declarationStringSegments: [String] = []
        var nameStringSegments: [String] = []
        for component in renderedName.components {
            switch component.type {
            case .type(_, .declaration):
                declarationStringSegments.append(component.string)
            case .type(_, .name):
                nameStringSegments.append(component.string)
            default:
                continue
            }
        }
        let declarationJoined = declarationStringSegments.joined()
        let nameJoined = nameStringSegments.joined()

        // Outer dumped type appears in the `.declaration` segments.
        #expect(declarationJoined.contains("SingleParameterBox"),
                "expected outer head in .declaration components; got declarations: \(declarationJoined)")
        // Inner argument `Int` appears in the `.name` segments — not in
        // `.declaration`.
        #expect(nameJoined.contains("Int"),
                "expected inner Int in .name components; got names: \(nameJoined)")
        #expect(!declarationJoined.contains("Int"),
                "Int leaked into .declaration components: \(declarationJoined)")
    }

    @Test("expanded field offsets do not crash when a nested field is a class")
    func expandedFieldOffsetsHandlesClassFieldWithoutCrash() async throws {
        // Regression: pre-fix, the recursion happily called
        // `StructMetadata.createInProcess` on a class metatype, producing a
        // misaligned `StructMetadata`. The next iteration's
        // `structDescriptor()` then triggered an internal `descriptor().struct!`
        // force-unwrap and trapped (a `try?` does not catch a force-unwrap
        // trap). The kind-checked `structMetadata(forMetatype:)` helper
        // returns nil for class metatypes, so recursion stops cleanly.
        _ = Fixtures.StructHostingClassField<Int>.self

        let descriptor = try structDescriptor(named: "StructHostingClassField")
        let structValue = try Struct(descriptor: descriptor, in: machO)
        let specializedMetadata = try StructMetadata.createInProcess(Fixtures.StructHostingClassField<Int>.self)
        let metadataContext = DumperMetadataContext(metadata: specializedMetadata, readingContext: InProcessContext.shared)

        var expandedConfig = configuration
        expandedConfig.printFieldOffset = true
        expandedConfig.printExpandedFieldOffsets = true

        let dumper = StructDumper(structValue, metadataContext: metadataContext, using: expandedConfig, in: machO)
        // The assertion is just "did not crash". We also sanity-check that
        // the top-level field rendering still substituted the class
        // reference's generic argument so we know we didn't accidentally
        // bail out before producing useful output.
        let body = try await dumper.body.string
        #expect(body.contains("GenericContainerClass<Swift.Int>") || body.contains("GenericContainerClass<Int>"),
                "expected class field to render with substituted generic; got: \(body)")
    }
}
