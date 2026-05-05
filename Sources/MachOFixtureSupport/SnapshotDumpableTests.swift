import Foundation
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftDump
import Demangling
// Needs SPI access to MetadataReader.demangleType for associated-type owning-protocol lookup.
@_spi(Internals) import SwiftInspection

@MainActor
package protocol SnapshotDumpableTests {}

extension SnapshotDumpableTests {
    package func collectDumpTypes<MachO: MachOSwiftSectionRepresentableWithCache>(
        for machO: MachO,
        options: DumpableTypeOptions = [.enum, .struct, .class],
        using configuration: DumperConfiguration? = nil
    ) async throws -> String {
        let typeContextDescriptors = try machO.swift.typeContextDescriptors
        var results: [String] = []
        for typeContextDescriptor in typeContextDescriptors {
            switch typeContextDescriptor {
            case .enum(let enumDescriptor):
                guard options.contains(.enum) else { continue }
                do {
                    let enumType = try Enum(descriptor: enumDescriptor, in: machO)
                    let output = try await enumType.dump(using: configuration ?? .demangleOptions(.test), in: machO).string
                    results.append(output)
                } catch {
                    results.append("Error: \(error)")
                }
            case .struct(let structDescriptor):
                guard options.contains(.struct) else { continue }
                do {
                    let structType = try Struct(descriptor: structDescriptor, in: machO)
                    let output = try await structType.dump(using: configuration ?? .demangleOptions(.test), in: machO).string
                    results.append(output)
                } catch {
                    results.append("Error: \(error)")
                }
            case .class(let classDescriptor):
                guard options.contains(.class) else { continue }
                do {
                    let classType = try Class(descriptor: classDescriptor, in: machO)
                    let output = try await classType.dump(using: configuration ?? .demangleOptions(.test), in: machO).string
                    results.append(output)
                } catch {
                    results.append("Error: \(error)")
                }
            }
        }
        return results.joined(separator: "\n")
    }

    package func collectDumpProtocols<MachO: MachOSwiftSectionRepresentableWithCache>(
        for machO: MachO
    ) async throws -> String {
        let protocolDescriptors = try machO.swift.protocolDescriptors
        var results: [String] = []
        for protocolDescriptor in protocolDescriptors {
            do {
                let output = try await Protocol(descriptor: protocolDescriptor, in: machO)
                    .dump(using: .demangleOptions(.test), in: machO).string
                results.append(output)
            } catch {
                results.append("Error: \(error)")
            }
        }
        return results.joined(separator: "\n")
    }

    package func collectDumpProtocolConformances<MachO: MachOSwiftSectionRepresentableWithCache>(
        for machO: MachO
    ) async throws -> String {
        let protocolConformanceDescriptors = try machO.swift.protocolConformanceDescriptors
        var results: [String] = []
        for protocolConformanceDescriptor in protocolConformanceDescriptors {
            do {
                let output = try await ProtocolConformance(descriptor: protocolConformanceDescriptor, in: machO)
                    .dump(using: .demangleOptions(.test), in: machO).string
                results.append(output)
            } catch {
                results.append("Error: \(error)")
            }
        }
        return results.joined(separator: "\n")
    }

    package func collectDumpAssociatedTypes<MachO: MachOSwiftSectionRepresentableWithCache>(
        for machO: MachO
    ) async throws -> String {
        let associatedTypeDescriptors = try machO.swift.associatedTypeDescriptors
        var results: [String] = []
        for associatedTypeDescriptor in associatedTypeDescriptors {
            do {
                let output = try await AssociatedType(descriptor: associatedTypeDescriptor, in: machO)
                    .dump(using: .demangleOptions(.test), in: machO).string
                results.append(output)
            } catch {
                results.append("Error: \(error)")
            }
        }
        return results.joined(separator: "\n")
    }
}

// MARK: - Namespace-filtered collectors

extension SnapshotDumpableTests {
    /// Walks the parent chain of a ``TypeContextDescriptorWrapper`` and returns the name of
    /// the top-level enclosing type (the category namespace). Returns `nil` when no named
    /// enclosing context can be found (caller should treat the descriptor as living in the
    /// "GlobalDeclarations" bucket).
    ///
    /// For a descriptor like `Actors.SwiftActor` whose parent chain is
    /// `SwiftActor -> Actors -> <module>`, this returns `"Actors"`.
    /// For a descriptor sitting directly under the module, returns the descriptor's own
    /// name.
    package func rootNamespace<MachO: MachOSwiftSectionRepresentableWithCache>(
        of descriptor: TypeContextDescriptorWrapper,
        in machO: MachO
    ) throws -> String? {
        let selfName = try descriptor.namedContextDescriptor.name(in: machO)
        return try walkRootNamespace(
            initialName: selfName,
            startingParent: try descriptor.parent(in: machO),
            in: machO
        )
    }

    /// Walks the parent chain of a ``ProtocolDescriptor`` and returns the name of the
    /// top-level enclosing context (the category namespace), or `nil` when no named
    /// enclosing context can be found.
    package func rootNamespace<MachO: MachOSwiftSectionRepresentableWithCache>(
        of descriptor: ProtocolDescriptor,
        in machO: MachO
    ) throws -> String? {
        let selfName = try descriptor.name(in: machO)
        return try walkRootNamespace(
            initialName: selfName,
            startingParent: try descriptor.parent(in: machO),
            in: machO
        )
    }

    /// Walks the parent chain, returning the name of the last *named, non-module* context
    /// encountered. `initialName` is the name of the descriptor whose namespace is being
    /// resolved — it becomes the result if the descriptor sits directly under the module.
    private func walkRootNamespace<MachO: MachOSwiftSectionRepresentableWithCache>(
        initialName: String,
        startingParent: SymbolOrElement<ContextDescriptorWrapper>?,
        in machO: MachO
    ) throws -> String? {
        var lastNamedName: String? = initialName
        var currentParent: SymbolOrElement<ContextDescriptorWrapper>? = startingParent

        while let parent = currentParent {
            guard let parentWrapper = parent.resolved else {
                // Unresolved symbol along the parent chain — we can't keep walking, so
                // treat the last known named context as the root namespace.
                break
            }
            if parentWrapper.isModule {
                break
            }
            if let namedDescriptor = parentWrapper.namedContextDescriptor {
                lastNamedName = try namedDescriptor.name(in: machO)
            }
            currentParent = try parentWrapper.parent(in: machO)
        }

        return lastNamedName
    }

    /// Category-filtered counterpart of ``collectDumpTypes(for:options:using:)``. Filters
    /// type context descriptors by ``rootNamespace(of:in:)`` and dumps them using the same
    /// per-descriptor logic (including `Error: <error>` strings).
    package func collectDumpTypes<MachO: MachOSwiftSectionRepresentableWithCache>(
        for machO: MachO,
        inNamespace category: String,
        options: DumpableTypeOptions = [.enum, .struct, .class]
    ) async throws -> String {
        let typeContextDescriptors = try machO.swift.typeContextDescriptors
        var results: [String] = []
        for typeContextDescriptor in typeContextDescriptors {
            guard (try? rootNamespace(of: typeContextDescriptor, in: machO)) == category else { continue }
            switch typeContextDescriptor {
            case .enum(let enumDescriptor):
                guard options.contains(.enum) else { continue }
                do {
                    let enumType = try Enum(descriptor: enumDescriptor, in: machO)
                    let output = try await enumType.dump(using: .demangleOptions(.test), in: machO).string
                    results.append(output)
                } catch {
                    results.append("Error: \(error)")
                }
            case .struct(let structDescriptor):
                guard options.contains(.struct) else { continue }
                do {
                    let structType = try Struct(descriptor: structDescriptor, in: machO)
                    let output = try await structType.dump(using: .demangleOptions(.test), in: machO).string
                    results.append(output)
                } catch {
                    results.append("Error: \(error)")
                }
            case .class(let classDescriptor):
                guard options.contains(.class) else { continue }
                do {
                    let classType = try Class(descriptor: classDescriptor, in: machO)
                    let output = try await classType.dump(using: .demangleOptions(.test), in: machO).string
                    results.append(output)
                } catch {
                    results.append("Error: \(error)")
                }
            }
        }
        return results.joined(separator: "\n")
    }

    /// Category-filtered counterpart of ``collectDumpProtocols(for:)``.
    package func collectDumpProtocols<MachO: MachOSwiftSectionRepresentableWithCache>(
        for machO: MachO,
        inNamespace category: String
    ) async throws -> String {
        let protocolDescriptors = try machO.swift.protocolDescriptors
        var results: [String] = []
        for protocolDescriptor in protocolDescriptors {
            guard (try? rootNamespace(of: protocolDescriptor, in: machO)) == category else { continue }
            do {
                let output = try await Protocol(descriptor: protocolDescriptor, in: machO)
                    .dump(using: .demangleOptions(.test), in: machO).string
                results.append(output)
            } catch {
                results.append("Error: \(error)")
            }
        }
        return results.joined(separator: "\n")
    }

    /// Category-filtered counterpart of ``collectDumpProtocolConformances(for:)``.
    ///
    /// Attribution rules:
    /// - **Default rule:** the conformance is attributed to the category that matches the
    ///   root namespace of its *conforming type* (resolved via `typeReference` if that
    ///   produces a `TypeContextDescriptorWrapper`).
    /// - **Special case — `category == "NeverExtensions"`:** also keep conformances whose
    ///   conforming type is `Swift.Never` (detected via any Swift.Never-rooted mangled
    ///   symbol (`_$ss5NeverO…` in the Mach-O symbol table, i.e. the Swift ABI stem
    ///   `$ss5NeverO` with the C-style leading underscore) surfaced on an indirect
    ///   `SymbolOrElement.symbol` reference).
    /// - **No double-counting:** if the default rule places a conformance in the current
    ///   category, we don't additionally match `NeverExtensions`.
    package func collectDumpProtocolConformances<MachO: MachOSwiftSectionRepresentableWithCache>(
        for machO: MachO,
        inNamespace category: String
    ) async throws -> String {
        let protocolConformanceDescriptors = try machO.swift.protocolConformanceDescriptors
        var results: [String] = []
        for protocolConformanceDescriptor in protocolConformanceDescriptors {
            guard try matchesConformanceNamespace(
                descriptor: protocolConformanceDescriptor,
                category: category,
                in: machO
            ) else { continue }
            do {
                let output = try await ProtocolConformance(descriptor: protocolConformanceDescriptor, in: machO)
                    .dump(using: .demangleOptions(.test), in: machO).string
                results.append(output)
            } catch {
                results.append("Error: \(error)")
            }
        }
        return results.joined(separator: "\n")
    }

    private func matchesConformanceNamespace<MachO: MachOSwiftSectionRepresentableWithCache>(
        descriptor: ProtocolConformanceDescriptor,
        category: String,
        in machO: MachO
    ) throws -> Bool {
        let resolvedTypeReference = try descriptor.resolvedTypeReference(in: machO)
        let defaultRuleNamespace = try conformingTypeRootNamespace(
            resolvedTypeReference: resolvedTypeReference,
            in: machO
        )
        if let defaultRuleNamespace, defaultRuleNamespace == category {
            return true
        }
        // Special-case NeverExtensions when the default rule couldn't attribute the
        // conformance (e.g. the conforming type is an external symbol like Swift.Never).
        if category == snapshotDumpableNeverExtensionsCategory,
           defaultRuleNamespace == nil,
           isSwiftNeverConformance(resolvedTypeReference: resolvedTypeReference) {
            return true
        }
        return false
    }

    /// Returns the root namespace of the conformance's conforming type when that type is
    /// a ``TypeContextDescriptorWrapper`` reachable from the binary. Returns `nil` for
    /// external symbols, ObjC classes, or any reference we don't know how to attribute.
    private func conformingTypeRootNamespace<MachO: MachOSwiftSectionRepresentableWithCache>(
        resolvedTypeReference: ResolvedTypeReference,
        in machO: MachO
    ) throws -> String? {
        switch resolvedTypeReference {
        case .directTypeDescriptor(let contextDescriptor):
            guard let typeWrapper = contextDescriptor?.typeContextDescriptorWrapper else {
                return nil
            }
            return try rootNamespace(of: typeWrapper, in: machO)
        case .indirectTypeDescriptor(let symbolOrElement):
            guard case .element(let contextDescriptor) = symbolOrElement,
                  let typeWrapper = contextDescriptor.typeContextDescriptorWrapper else {
                return nil
            }
            return try rootNamespace(of: typeWrapper, in: machO)
        case .directObjCClassName,
             .indirectObjCClass:
            return nil
        }
    }

    /// Detects `Swift.Never` conforming types surfaced as an external symbol reference.
    /// The match is a prefix test against any Swift.Never-rooted mangled symbol
    /// (`_$ss5NeverO…` in the Mach-O symbol table, i.e. the Swift ABI stem `$ss5NeverO`
    /// with the C-style leading underscore). The kind suffix (`Mn`, `N`, `Ma`,
    /// witness-table mangles, etc.) tells us *what kind* of Never-symbol it is, but all
    /// variants still indicate that the conforming type is `Swift.Never`.
    ///
    /// The prefix match is collision-free: the `_$ss` mangling namespace (Swift ABI
    /// stem `$ss`, C-linkage-prefixed to `_$ss`) is reserved for the Swift stdlib
    /// (`s` module), so user code cannot mint a symbol starting with `_$ss5NeverO`.
    private func isSwiftNeverConformance(resolvedTypeReference: ResolvedTypeReference) -> Bool {
        switch resolvedTypeReference {
        case .indirectTypeDescriptor(let symbolOrElement):
            if case .symbol(let symbol) = symbolOrElement {
                return symbol.name.hasPrefix(swiftNeverMangledSymbolPrefix)
            }
            return false
        case .indirectObjCClass(let symbolOrElement):
            if case .symbol(let symbol) = symbolOrElement {
                return symbol.name.hasPrefix(swiftNeverMangledSymbolPrefix)
            }
            return false
        case .directTypeDescriptor,
             .directObjCClassName:
            return false
        }
    }

    /// Category-filtered counterpart of ``collectDumpAssociatedTypes(for:)``. Filters by
    /// the owning protocol's root namespace — owning protocol is resolved by matching the
    /// associated type descriptor's `protocolTypeName` against the `ProtocolDescriptor`s
    /// discovered in the binary's protocol descriptors section.
    package func collectDumpAssociatedTypes<MachO: MachOSwiftSectionRepresentableWithCache>(
        for machO: MachO,
        inNamespace category: String
    ) async throws -> String {
        let associatedTypeDescriptors = try machO.swift.associatedTypeDescriptors
        let protocolDescriptors = try machO.swift.protocolDescriptors

        // Build a lookup from `"<module>.<name>"` to ProtocolDescriptor so we can resolve
        // an associated type's owning protocol via its mangled `protocolTypeName`.
        let protocolIndex = try buildProtocolLookup(protocolDescriptors: protocolDescriptors, in: machO)

        var results: [String] = []
        for associatedTypeDescriptor in associatedTypeDescriptors {
            let owningNamespace = try associatedTypeOwningNamespace(
                descriptor: associatedTypeDescriptor,
                protocolIndex: protocolIndex,
                in: machO
            )
            guard owningNamespace == category else { continue }
            do {
                let output = try await AssociatedType(descriptor: associatedTypeDescriptor, in: machO)
                    .dump(using: .demangleOptions(.test), in: machO).string
                results.append(output)
            } catch {
                results.append("Error: \(error)")
            }
        }
        return results.joined(separator: "\n")
    }

    private func buildProtocolLookup<MachO: MachOSwiftSectionRepresentableWithCache>(
        protocolDescriptors: [ProtocolDescriptor],
        in machO: MachO
    ) throws -> [String: ProtocolDescriptor] {
        var lookup: [String: ProtocolDescriptor] = [:]
        for protocolDescriptor in protocolDescriptors {
            let name: String
            do {
                name = try protocolDescriptor.name(in: machO)
            } catch {
                continue
            }
            let moduleName = (try? protocolDescriptor.moduleContextDescriptor(in: machO)?.name(in: machO)) ?? ""
            let key = "\(moduleName).\(name)"
            // First writer wins; this produces stable behavior if duplicates exist.
            if lookup[key] == nil {
                lookup[key] = protocolDescriptor
            }
        }
        return lookup
    }

    private func associatedTypeOwningNamespace<MachO: MachOSwiftSectionRepresentableWithCache>(
        descriptor: AssociatedTypeDescriptor,
        protocolIndex: [String: ProtocolDescriptor],
        in machO: MachO
    ) throws -> String? {
        let protocolTypeName = try descriptor.protocolTypeName(in: machO)
        let protocolNode: Node
        do {
            protocolNode = try MetadataReader.demangleType(for: protocolTypeName, in: machO)
        } catch {
            return nil
        }

        // Walk the tree looking for a `.protocol` node and extract its module + name.
        guard let key = protocolLookupKey(from: protocolNode) else { return nil }
        guard let owningProtocol = protocolIndex[key] else { return nil }
        return try rootNamespace(of: owningProtocol, in: machO)
    }

    private func protocolLookupKey(from node: Node) -> String? {
        if let protocolNode = node.first(of: .protocol) {
            let moduleName = protocolNode.children.first(where: { $0.kind == .module })?.text ?? ""
            let identifierText = protocolNode.children.first(where: { $0.kind == .identifier })?.text ?? ""
            guard !identifierText.isEmpty else { return nil }
            return "\(moduleName).\(identifierText)"
        }
        return nil
    }

    /// Combined per-category dump. Concatenates Types / Protocols / Protocol Conformances /
    /// Associated Types sections with `// MARK:` headers, skipping any section whose
    /// filtered output is empty after whitespace trimming. Returns an empty string when all
    /// four sections are empty (used by the "GlobalDeclarations" edge-case bucket).
    package func collectDump<MachO: MachOSwiftSectionRepresentableWithCache>(
        for machO: MachO,
        inNamespace category: String
    ) async throws -> String {
        let typesOutput = try await collectDumpTypes(for: machO, inNamespace: category)
        let protocolsOutput = try await collectDumpProtocols(for: machO, inNamespace: category)
        let protocolConformancesOutput = try await collectDumpProtocolConformances(for: machO, inNamespace: category)
        let associatedTypesOutput = try await collectDumpAssociatedTypes(for: machO, inNamespace: category)

        let sections: [(header: String, body: String)] = [
            ("// MARK: - Types", typesOutput),
            ("// MARK: - Protocols", protocolsOutput),
            ("// MARK: - Protocol Conformances", protocolConformancesOutput),
            ("// MARK: - Associated Types", associatedTypesOutput),
        ]

        var chunks: [String] = []
        for (header, body) in sections {
            if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            chunks.append("\(header)\n\n\(body)")
        }
        return chunks.joined(separator: "\n\n")
    }
}

/// Marker string used to opt a category into the Swift.Never-extensions bucket.
private let snapshotDumpableNeverExtensionsCategory = "NeverExtensions"

/// Mangled stem for `Swift.Never` (from the Swift standard library ABI). Symbol-table
/// references to `Swift.Never` always carry a kind suffix (e.g. `Mn` for the nominal type
/// descriptor, `N` for type metadata, `Ma` for the metadata accessor, `s5ErrorsWP` for a
/// witness table), so matching must be done via prefix rather than exact equality. The
/// leading `_` is the C-style symbol-name prefix attached by the Mach-O symbol table.
private let swiftNeverMangledSymbolPrefix = "_$ss5NeverO"
