import Demangling
import MachOSwiftSection
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

/// What the resolution chain knows about one protocol (the opaque-primary-associated-type-attribution evolution proposal).
struct ProtocolFacts {
    var qualifiedName: String
    /// Own declarations only, no inherited associated types.
    var declaredAssociatedTypeNames: [String]
    /// Direct refinements (requirement-signature protocol entries on `Self`).
    var refinedProtocols: [ProtocolReference]
    /// Known only from the builtin table — runtime metadata carries no
    /// primary-associated-type marker (SE-0346 leaves no trace).
    var primaryAssociatedTypeNames: [String]?
}

/// A protocol identified by qualified name, with its descriptor when the
/// current reader can reach one (same image on both readers; any image
/// in-process).
struct ProtocolReference {
    var qualifiedName: String
    var descriptor: ProtocolDescriptor?
}

/// Resolves `ProtocolFacts` through the opaque-primary-associated-type-attribution proposal's chain: a reachable
/// descriptor (local, or cross-image in-process — `resolvedContent` hands both
/// over the same way) first, enriched with the builtin table's primary list;
/// the builtin standard-library table alone when only the identity is known
/// (an offline bind).
struct ProtocolFactsResolver<MachO: MachOSwiftSectionRepresentableWithCache> {
    let machO: MachO

    func facts(for reference: ProtocolReference) async -> ProtocolFacts? {
        if let descriptor = reference.descriptor, var descriptorFacts = await facts(fromDescriptor: descriptor) {
            if let builtinFacts = BuiltinStandardLibraryProtocolFacts.factsByQualifiedName[descriptorFacts.qualifiedName] {
                descriptorFacts.primaryAssociatedTypeNames = builtinFacts.primaryAssociatedTypeNames
            }
            return descriptorFacts
        }
        return BuiltinStandardLibraryProtocolFacts.factsByQualifiedName[reference.qualifiedName]
    }

    /// Walks the refine closure of `facts` looking for the anchor protocol.
    /// Returns `true` when found, `false` when the complete closure excludes
    /// it, and `nil` when the closure is incomplete and the expanded part did
    /// not contain it (a hit is sufficient even in an incomplete closure; a
    /// miss there proves nothing).
    func refineClosureContainsAnchor(_ anchorProtocolName: String, startingFrom facts: ProtocolFacts) async -> Bool? {
        var visitedQualifiedNames: Set<String> = [facts.qualifiedName]
        var pendingReferences = facts.refinedProtocols
        var isIncomplete = false
        var currentIndex = 0
        while currentIndex < pendingReferences.count {
            let reference = pendingReferences[currentIndex]
            currentIndex += 1
            guard visitedQualifiedNames.insert(reference.qualifiedName).inserted else { continue }
            if reference.qualifiedName == anchorProtocolName { return true }
            if let referenceFacts = await self.facts(for: reference) {
                pendingReferences.append(contentsOf: referenceFacts.refinedProtocols)
            } else {
                isIncomplete = true
            }
        }
        return isIncomplete ? nil : false
    }

    func protocolReference(from symbolOrElement: SymbolOrElement<ProtocolDescriptorWithObjCInterop>) async -> ProtocolReference? {
        switch symbolOrElement {
        case .symbol(let symbol):
            guard let symbolNode = try? MetadataReader.demangleType(for: symbol, in: machO) else { return nil }
            let qualifiedName = await symbolNode.print(using: .opaqueTypeBuilderOnly)
            guard !qualifiedName.isEmpty else { return nil }
            return ProtocolReference(qualifiedName: qualifiedName, descriptor: nil)
        case .element(let descriptorWithObjCInterop):
            switch descriptorWithObjCInterop {
            case .swift(let descriptor):
                guard let contextNode = try? MetadataReader.demangleContext(for: .protocol(descriptor), in: machO) else { return nil }
                let qualifiedName = await contextNode.print(using: .opaqueTypeBuilderOnly)
                guard !qualifiedName.isEmpty else { return nil }
                return ProtocolReference(qualifiedName: qualifiedName, descriptor: descriptor)
            case .objc:
                // An ObjC protocol cannot declare Swift associated types, so it
                // can neither anchor a constraint nor extend a refine closure
                // toward one.
                return nil
            }
        }
    }

    private func facts(fromDescriptor descriptor: ProtocolDescriptor) async -> ProtocolFacts? {
        guard let protocolModel = try? `Protocol`(descriptor: descriptor, in: machO) else { return nil }
        guard let contextNode = try? MetadataReader.demangleContext(for: .protocol(descriptor), in: machO) else { return nil }
        let qualifiedName = await contextNode.print(using: .opaqueTypeBuilderOnly)
        guard !qualifiedName.isEmpty else { return nil }

        let declaredAssociatedTypeNames = (try? descriptor.associatedTypes(in: machO)) ?? []

        var refinedProtocols: [ProtocolReference] = []
        for requirement in protocolModel.requirementInSignatures {
            // Base conformances are the requirement-signature protocol entries
            // whose subject is `Self` (mangled `x`).
            guard requirement.paramManagledName.rawString == "x" else { continue }
            guard case .protocol(let symbolOrElement) = requirement.content else { continue }
            if let reference = await protocolReference(from: symbolOrElement) {
                refinedProtocols.append(reference)
            }
        }

        return ProtocolFacts(
            qualifiedName: qualifiedName,
            declaredAssociatedTypeNames: declaredAssociatedTypeNames,
            refinedProtocols: refinedProtocols,
            primaryAssociatedTypeNames: nil
        )
    }
}
