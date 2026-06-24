import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
@testable import SwiftLayout
import SwiftDeclarationRendering
import Demangling
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Verifies the reader-specialized `FieldLayoutRenderer`:
///
/// - the **MachOFile** (static, SwiftLayout-backed) path surfaces, through the
///   generic facade, exactly the field offsets the `StaticLayoutCalculator`
///   computes — which `StaticLayoutVsRuntimeTests` independently proves match the
///   runtime metadata accessor offset-for-offset. So the renderer's offline
///   output is correct transitively, without re-materializing in-process
///   metadata here (that path can trap uncatchably for some fixture types);
/// - with no provider injected the static path degrades to nothing (exactly the
///   pre-SwiftLayout behaviour for an offline file, where metadata is
///   unavailable);
/// - the `// Field offset:` / `// Type Layout:` / `Enum Layout` comment
///   formatting renders.
@Suite(.serialized)
final class FieldLayoutRendererReaderSpecializationTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {

    private func qualifiedName(of descriptorWrapper: TypeContextDescriptorWrapper, in machO: some MachOSwiftSectionRepresentableWithCache) -> String? {
        guard let node = try? MetadataReader.demangleContext(for: descriptorWrapper.asContextDescriptorWrapper, in: machO) else { return nil }
        return NodeTypeNaming.nominalQualifiedName(of: node)
    }

    private func descriptorWrapper(of type: TypeContextWrapper) -> (wrapper: TypeContextDescriptorWrapper, isGeneric: Bool, isAggregate: Bool) {
        switch type {
        case .struct(let structType):
            return (.struct(structType.descriptor), structType.descriptor.isGeneric, true)
        case .class(let classType):
            return (.class(classType.descriptor), classType.descriptor.isGeneric, true)
        case .enum(let enumType):
            return (.enum(enumType.descriptor), enumType.descriptor.isGeneric, false)
        }
    }

    @MainActor
    @Test func staticRenderedFieldOffsetsMatchCalculator() async throws {
        let provider = try #require(MachOFileStaticFieldLayoutProvider(machOFile: machOFile, resolution: .singleImage))
        var configuration = DeclarationRenderConfiguration.demangleOptions(.default)
        configuration.printFieldOffset = true
        configuration.staticFieldLayoutProvider = provider

        // Independent ground truth at the SwiftLayout layer (the same engine
        // StaticLayoutVsRuntimeTests checks against the runtime accessor).
        let calculator = try StaticLayoutCalculator(machO: machOFile)

        var comparedCount = 0
        var nonEmptyCount = 0
        var mismatches: [String] = []

        for type in try machOFile.swift.types {
            let info = descriptorWrapper(of: type)
            guard info.isAggregate, !info.isGeneric else { continue }
            guard let name = qualifiedName(of: info.wrapper, in: machOFile), name.hasPrefix("SymbolTests") else { continue }

            let renderer = FieldLayoutRenderer(type: type, metadata: nil, machO: machOFile, configuration: configuration, autoResolveAccessorMetadata: false)
            let renderedOffsets = renderer.fieldOffsets ?? []
            let calculatedOffsets = (try? calculator.fieldLayout(of: info.wrapper).computedFieldOffsets) ?? []

            comparedCount += 1
            if !renderedOffsets.isEmpty { nonEmptyCount += 1 }
            if renderedOffsets != calculatedOffsets {
                mismatches.append("\(name): rendered=\(renderedOffsets) calculated=\(calculatedOffsets)")
            }
        }

        #expect(comparedCount > 80, "expected to compare many fixture types, got \(comparedCount)")
        #expect(nonEmptyCount > 30, "expected many types to render non-empty static offsets, got \(nonEmptyCount)")
        #expect(mismatches.isEmpty, Testing.Comment(rawValue: "renderer-vs-calculator field-offset mismatches:\n" + mismatches.joined(separator: "\n")))
    }

    @MainActor
    @Test func noProviderYieldsNilStaticOffsets() async throws {
        var configuration = DeclarationRenderConfiguration.demangleOptions(.default)
        configuration.printFieldOffset = true
        // No staticFieldLayoutProvider injected.

        var sawAggregate = false
        for type in try machOFile.swift.types {
            let info = descriptorWrapper(of: type)
            guard info.isAggregate, !info.isGeneric else { continue }
            sawAggregate = true
            let renderer = FieldLayoutRenderer(type: type, metadata: nil, machO: machOFile, configuration: configuration, autoResolveAccessorMetadata: false)
            #expect(renderer.fieldOffsets == nil, "offline file path must yield no offsets without a provider")
        }
        #expect(sawAggregate, "fixture should contain at least one non-generic aggregate")
    }

    @MainActor
    @Test func rendersStaticFieldAndTypeLayoutComments() async throws {
        let provider = try #require(MachOFileStaticFieldLayoutProvider(machOFile: machOFile, resolution: .singleImage))
        var configuration = DeclarationRenderConfiguration.demangleOptions(.default)
        configuration.printFieldOffset = true
        configuration.printTypeLayout = true
        configuration.staticFieldLayoutProvider = provider

        // Find the first non-generic struct whose first field resolves, then
        // render its leading field's comment block.
        for type in try machOFile.swift.types {
            guard case .struct(let structType) = type, !structType.descriptor.isGeneric else { continue }
            let renderer = FieldLayoutRenderer(type: type, metadata: nil, machO: machOFile, configuration: configuration, autoResolveAccessorMetadata: false)
            let offsets = renderer.fieldOffsets ?? []
            guard !offsets.isEmpty else { continue }
            let records = try structType.descriptor.fieldDescriptor(in: machOFile).records(in: machOFile)
            guard let firstRecord = records.first else { continue }
            let mangledTypeName = try firstRecord.mangledTypeName(in: machOFile)

            let comments = await renderer.storedFieldComments(forFieldAtIndex: 0, mangledTypeName: mangledTypeName, fieldOffsets: offsets).string
            #expect(comments.contains("Field offset"), "expected a Field offset comment, got: \(comments)")
            #expect(comments.contains("Type Layout"), "expected a Type Layout comment, got: \(comments)")
            return
        }
        Issue.record("no non-generic struct with a resolvable first field found in fixture")
    }

    @MainActor
    @Test func rendersStaticEnumLayoutComment() async throws {
        let provider = try #require(MachOFileStaticFieldLayoutProvider(machOFile: machOFile, resolution: .singleImage))
        var configuration = DeclarationRenderConfiguration.demangleOptions(.default)
        configuration.printEnumLayout = true
        configuration.staticFieldLayoutProvider = provider

        // Find the first non-generic payload-carrying enum and assert its layout
        // strategy projection renders.
        for type in try machOFile.swift.types {
            guard case .enum(let enumType) = type, !enumType.descriptor.isGeneric, enumType.descriptor.hasPayloadCases else { continue }
            let renderer = FieldLayoutRenderer(type: type, metadata: nil, machO: machOFile, configuration: configuration, autoResolveAccessorMetadata: false)
            guard let enumLayout = await renderer.enumLayout else { continue }
            let prefix = await renderer.enumPrefixComments(enumLayout: enumLayout).string
            #expect(prefix.contains("Payload") || prefix.contains("Tag") || prefix.contains("Single") || prefix.contains("Multi"), "expected an Enum Layout strategy comment, got: \(prefix)")
            return
        }
        Issue.record("no non-generic payload-carrying enum found in fixture")
    }
}
