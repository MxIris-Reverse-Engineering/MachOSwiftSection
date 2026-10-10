import Foundation
import Testing
import MachOKit
@testable import Demangling
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@testable @_spi(Internals) import SwiftInspection

/// A type declared in a function or closure body hangs off a chain of
/// anonymous contexts — the type's own, one per closure, the function's —
/// none of which carries a name in a release build (evolution proposal
/// `local-type-context-names`). `SymbolicDemangler` used to drop the chain,
/// so two methods' `Visitor`s both read as `Holder.Visitor`, or to borrow the
/// private discriminator of an enclosing private method, faking a private
/// type. Each `LocalTypeFixture` variant keeps one source of the full name
/// (`debugNames`, `anonymousDescriptorSymbols`, `symbolicReferences`), all of
/// them (`unstripped`) or none (`stripped`); every reader path must come back
/// with the compiler's own spelling where a source exists, and with distinct
/// position-based names where none does.
@Suite(.serialized, ExclusiveImageAccess(LocalTypeFixture.exclusiveAccessName))
struct LocalTypeContextNameTests {
    // MARK: - The compiler's spelling, from each source

    @Test(arguments: LocalTypeFixture.Variant.named)
    func fileNamesEveryLocalTypeTheWayTheCompilerDoes(variant: LocalTypeFixture.Variant) throws {
        let machOFile = try LocalTypeFixture.machOFile(variant)
        let names = try Self.localTypeNames(in: machOFile, context: machOFile.context)
        try Self.expectCompilerSpelling(names, variant: variant)
    }

    @Test(arguments: LocalTypeFixture.Variant.named)
    func imageNamesEveryLocalTypeTheWayTheCompilerDoes(variant: LocalTypeFixture.Variant) throws {
        let machOImage = try LocalTypeFixture.loadedImage(variant)
        let names = try Self.localTypeNames(in: machOImage, context: machOImage.context)
        try Self.expectCompilerSpelling(names, variant: variant)
    }

    /// The runtime-metadata paths reach a descriptor by address and demangle
    /// it through `InProcessContext`.
    @Test(arguments: LocalTypeFixture.Variant.named)
    func inProcessDescriptorsNameEveryLocalTypeTheWayTheCompilerDoes(variant: LocalTypeFixture.Variant) throws {
        let machOImage = try LocalTypeFixture.loadedImage(variant)
        var names: [String] = []
        for descriptor in try Self.localTypeDescriptors(in: machOImage) {
            let inProcessDescriptor: ContextDescriptorWrapper = try .resolve(at: machOImage.ptr.advanced(by: descriptor.contextDescriptor.offset), in: .inProcess)
            names.append(Self.printedName(of: try SymbolicDemangler.demangleContext(for: inProcessDescriptor, in: .inProcess)))
        }
        try Self.expectCompilerSpelling(names, variant: variant)
    }

    /// A private method's discriminator stays on the method. Taking the first
    /// `privateDeclName` anywhere in the anonymous context's symbol used to
    /// hang it on every anonymous context and then on the type, reading
    /// `Holder.(unknown context at _…).(Hidden in _…)` — a private type that
    /// does not exist.
    @Test(arguments: LocalTypeFixture.Variant.named)
    func privateMethodLendsNoDiscriminatorToItsLocalType(variant: LocalTypeFixture.Variant) throws {
        let machOFile = try LocalTypeFixture.machOFile(variant)
        let hidden = try #require(try Self.localTypeDescriptors(in: machOFile).first { try $0.namedContextDescriptor?.name(in: machOFile.context) == "Hidden" })
        let nominal = Self.nominal(of: try SymbolicDemangler.demangleContext(for: hidden, in: machOFile.context))

        #expect(nominal.children.at(1)?.kind == .localDeclName)
        #expect(nominal.first(of: .anonymousContext) == nil)
        #expect(nominal.children.first?.kind == .function)
        #expect(nominal.children.first?.children.at(1)?.kind == .privateDeclName)
    }

    // MARK: - No source: position-based names

    /// With every name source stripped, a local type is spelled by the
    /// address of the anonymous context wrapping it — the runtime's and
    /// Remote Mirror's convention — under the nearest context the
    /// descriptors can name. Two methods' `Visitor`s must not merge.
    @Test func strippedLocalTypesGetDistinctPositionBasedNames() throws {
        let machOFile = try LocalTypeFixture.machOFile(.stripped)
        let moduleName = LocalTypeFixture.Variant.stripped.moduleName
        var names: [String: String] = [:]
        for descriptor in try Self.localTypeDescriptors(in: machOFile) {
            let name = try #require(try descriptor.namedContextDescriptor?.name(in: machOFile.context))
            let printedName = Self.printedName(of: try SymbolicDemangler.demangleContext(for: descriptor, in: machOFile.context))
            #expect(names.updateValue(name, forKey: printedName) == nil, "two local types share the name \(printedName)")
            guard case .element(.anonymous(let anonymousContext))? = try descriptor.parent(in: machOFile.context) else { continue }
            let address = String(machOFile.address(forOffset: anonymousContext.offset), radix: 16)
            #expect(printedName.hasSuffix("(\(name) in $\(address))"), "\(printedName) does not name the anonymous context at \(address)")
        }
        #expect(names.values.filter { $0 == "Visitor" }.count == 2)
        #expect(names.values.filter { $0 == "Twin" }.count == 2)
        #expect(names.values.filter { $0 == "Key" }.count == 2)
        // The nearest named context stays: the type, the extended type, the module.
        #expect(names.keys.contains { $0.hasPrefix("\(moduleName).Holder.(Visitor in $") })
        #expect(names.keys.contains { $0.hasPrefix("(extension in \(moduleName)):Swift.String.(Wrapper in $") })
        #expect(names.keys.contains { $0.hasPrefix("\(moduleName).(TopLevel in $") })
        // A type nested in a local one keeps its own name under it.
        #expect(names.keys.contains { $0.hasPrefix("\(moduleName).Holder.(Generator in $") && $0.hasSuffix(").Element") })
    }

    /// The position comes from the image's own address space, so the file
    /// and the loaded image agree on it.
    @Test func strippedLocalTypesAreNamedAlikeInTheFileAndInProcess() throws {
        let machOFile = try LocalTypeFixture.machOFile(.stripped)
        let machOImage = try LocalTypeFixture.loadedImage(.stripped)
        let fileNames = try Self.localTypeNames(in: machOFile, context: machOFile.context).sorted()
        let imageNames = try Self.localTypeNames(in: machOImage, context: machOImage.context).sorted()
        var inProcessNames: [String] = []
        for descriptor in try Self.localTypeDescriptors(in: machOImage) {
            let inProcessDescriptor: ContextDescriptorWrapper = try .resolve(at: machOImage.ptr.advanced(by: descriptor.contextDescriptor.offset), in: .inProcess)
            inProcessNames.append(Self.printedName(of: try SymbolicDemangler.demangleContext(for: inProcessDescriptor, in: .inProcess)))
        }
        #expect(fileNames == imageNames)
        #expect(fileNames == inProcessNames.sorted())
    }

    // MARK: - Qualified names

    /// The static layout engine and the ObjC-side lookups key a type by
    /// `NodeTypeNaming`'s qualified name, both for its descriptor and for a
    /// field typed as it. A local type's key has to tell its function apart:
    /// keyed by its bare name, two methods' `Visitor`s share one key, and a
    /// field typed as one resolves to the other.
    @Test(arguments: LocalTypeFixture.Variant.allCases)
    func qualifiedNamesOfLocalTypesAreDistinct(variant: LocalTypeFixture.Variant) throws {
        let machOFile = try LocalTypeFixture.machOFile(variant)
        var qualifiedNames: [String] = []
        for descriptor in try Self.localTypeDescriptors(in: machOFile) {
            let node = try SymbolicDemangler.demangleContext(for: descriptor, in: machOFile.context)
            qualifiedNames.append(try #require(NodeTypeNaming.nominalQualifiedName(of: node), "\(Self.printedName(of: node)) has no qualified name"))
        }
        #expect(qualifiedNames.count == 20)
        #expect(Set(qualifiedNames).count == qualifiedNames.count, "\(qualifiedNames.sorted())")
    }

    // MARK: - Opaque result types

    /// A generic method's opaque result type hangs off the method's anonymous
    /// context. Its name is the method's: from the descriptor's own name in a
    /// debug build, from the `MXX` symbol in an unstripped one. Both used to
    /// fail for a method that is not private — the anonymous context was
    /// dropped before the opaque type could ask it for its name.
    @Test(arguments: [LocalTypeFixture.Variant.debugNames, .anonymousDescriptorSymbols, .unstripped])
    func opaqueResultTypeOfAGenericMethodIsNamedAfterTheMethod(variant: LocalTypeFixture.Variant) throws {
        let machOFile = try LocalTypeFixture.machOFile(variant)
        // Exported, so it survives every strip; a dylib's `__TEXT` sits at 0,
        // so the symbol's value is the descriptor's offset.
        let symbol = try #require(machOFile.symbols.first { $0.name.hasSuffix("6HolderV11opaqueValueyQrxlFQOMQ") }, "the fixture exports no opaque type descriptor for opaqueValue")
        let descriptor = try OpaqueTypeDescriptor.resolve(at: symbol.offset, in: machOFile.context)
        // The compiler's spelling: the descriptor symbol names the opaque type.
        let compilerSpelled = try #require(try demangleAsNodeTransient(symbol.name).first(of: .opaqueReturnTypeOf))

        let descriptorBuilt = try SymbolicDemangler.demangleContext(for: .opaqueType(descriptor), in: machOFile.context)

        #expect(descriptorBuilt.print(using: .default) == compilerSpelled.print(using: .default))
    }

    // MARK: - Helpers

    /// Every type context the fixture declares in a body, nested types of
    /// local types included.
    private static func localTypeDescriptors(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> [ContextDescriptorWrapper] {
        try machO.swift.typeContextDescriptors.map(\.asContextDescriptorWrapper).filter { try LocalTypeFixture.isDeclaredInABody($0, in: machO.context) }
    }

    private static func localTypeNames(in machO: some MachOSwiftSectionRepresentableWithCache, context: some ReadingContext) throws -> [String] {
        try localTypeDescriptors(in: machO).map { printedName(of: try SymbolicDemangler.demangleContext(for: $0, in: context)) }
    }

    private static func expectCompilerSpelling(_ names: [String], variant: LocalTypeFixture.Variant, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let hiddenNames = names.filter { LocalTypeFixture.isCompilerSpelledHiddenName($0, of: variant) }
        #expect(hiddenNames.count == 1, "\(names)", sourceLocation: sourceLocation)
        #expect(names.filter { !LocalTypeFixture.isCompilerSpelledHiddenName($0, of: variant) }.sorted() == LocalTypeFixture.compilerSpelledNames(of: variant).sorted(), sourceLocation: sourceLocation)
    }

    private static func nominal(of node: Node) -> Node {
        var nominal = node
        while nominal.kind == .global || nominal.kind == .type || nominal.kind == .typeMangling, let child = nominal.children.first {
            nominal = child
        }
        return nominal
    }

    private static func printedName(of node: Node) -> String {
        nominal(of: node).print(using: .default)
    }
}
