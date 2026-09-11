#if THUNK_ANALYSIS

import Foundation
import FoundationToolbox
import MachOKit
import MachOFoundation
import MachOSwiftSection
import Demangling
@_spi(Internals) import SwiftInspection

@Loggable(.fileprivate, subsystem: "com.machoswiftsection.swift-thunk-analysis", category: "AccessorThunkReader")
fileprivate protocol AccessorThunkReadingLogging {}

/// One underlying type a thunk yields, with the condition under which it does.
public struct ResolvedUnderlyingType: Sendable {
    public let condition: ThunkCandidate.Condition
    public let typeNode: Node

    public init(condition: ThunkCandidate.Condition, typeNode: Node) {
        self.condition = condition
        self.typeNode = typeNode
    }
}

/// Everything readable about one accessor thunk.
public struct ResolvedAccessorThunk: Sendable {
    public let availabilityCheck: PlatformAvailabilityCheck?
    public let underlyingTypes: [ResolvedUnderlyingType]
    public let limitations: [ThunkAnalysisLimitation]

    public init(
        availabilityCheck: PlatformAvailabilityCheck?,
        underlyingTypes: [ResolvedUnderlyingType],
        limitations: [ThunkAnalysisLimitation]
    ) {
        self.availabilityCheck = availabilityCheck
        self.underlyingTypes = underlyingTypes
        self.limitations = limitations
    }
}

/// Reads a metadata accessor thunk without executing it.
public enum AccessorThunkReader: AccessorThunkReadingLogging {
    /// How many bytes to read before disassembling.
    ///
    /// Generous relative to the ~14-instruction thunks measured, because the
    /// function-boundary rule needs to see past a forward branch to decide
    /// where the function ends; the decoder's own instruction cap is the real
    /// bound.
    private static let machineCodeWindowSize = 1024

    /// Resolves the underlying types the thunk at `thunkOffset` yields.
    ///
    /// `thunkOffset` is the offset a kind-9 `accessorFunctionReference` node
    /// carries — which for a shared-cache image is *not* a file offset; see
    /// ``ThunkAddressSpace``.
    public static func read(thunkAtOffset thunkOffset: Int, in machO: MachOFile) throws -> ResolvedAccessorThunk {
        let addressSpace = ThunkAddressSpace(of: machO)
        guard let thunkAddress = addressSpace.address(forOffset: thunkOffset) else {
            return ResolvedAccessorThunk(availabilityCheck: nil, underlyingTypes: [], limitations: [.noRecognizedShape])
        }

        let machineCode = Data(try machO.readElements(offset: thunkOffset, numberOfElements: machineCodeWindowSize) as [UInt8])
        let instructions = try CapstoneThunkDecoder.decodeFunction(machineCode: machineCode, startAddress: thunkAddress)
        let program = AccessorThunkAnalyzer.analyze(instructions: instructions)

        var underlyingTypes: [ResolvedUnderlyingType] = []
        var limitations = program.limitations
        for candidate in program.candidates {
            guard let typeNode = typeNode(for: candidate.reference, addressSpace: addressSpace, in: machO) else {
                limitations.append(.selectionNotRecognized)
                continue
            }
            underlyingTypes.append(ResolvedUnderlyingType(condition: candidate.condition, typeNode: typeNode))
        }
        return ResolvedAccessorThunk(
            availabilityCheck: program.availabilityCheck,
            underlyingTypes: underlyingTypes,
            limitations: limitations
        )
    }

    // MARK: - Naming a candidate

    private static func typeNode(
        for reference: ThunkCandidate.Reference,
        addressSpace: ThunkAddressSpace,
        in machO: MachOFile
    ) -> Node? {
        switch reference {
        case .metadata(let address):
            guard let offset = addressSpace.offset(forAddress: address) else { return nil }
            // The metadata symbol first: `…VN` is an *exported* symbol, so it
            // survives the stripping that removes the thunk's own
            // `_get_type_metadata …` symbol, and it carries the complete
            // mangled type. Measured on SwiftUI: one of
            // `ResolvedMenuStyle.Body`'s two candidates is named this way.
            if let node = typeNodeFromMetadataSymbol(atOffset: offset, in: machO) { return node }
            // Otherwise go through the record: a nominal type's metadata
            // stores its context descriptor in the word after the kind.
            return typeNodeFromMetadataRecord(atOffset: offset, in: machO)
        case .metadataAccessor(let address):
            // An accessor carries no symbol in a stripped image, so the way
            // back to a name is the descriptor that points *at* it.
            guard let offset = addressSpace.offset(forAddress: address),
                  let descriptorOffset = MetadataAccessorIndex.index(for: machO).descriptorOffset(forAccessorOffset: offset)
            else { return nil }
            do {
                let descriptor: ContextDescriptorWrapper = try ContextDescriptorWrapper.resolve(from: descriptorOffset, in: machO)
                return try SymbolicDemangler.demangleContext(for: descriptor, in: machO)
            } catch {
                #log(.info, "could not name the accessor at offset \(offset, privacy: .public): \(String(describing: error), privacy: .public)")
                return nil
            }
        }
    }

    private static func typeNodeFromMetadataSymbol(atOffset offset: Int, in machO: MachOFile) -> Node? {
        guard let symbols = machO.symbols(offset: offset) else { return nil }
        for symbol in symbols {
            guard let symbolNode = try? SymbolicDemangler.demangleSymbol(for: symbol, in: machO) ?? nil else { continue }
            // `…VN` demangles to a `typeMetadata` node wrapping the type.
            guard let metadataNode = symbolNode.first(of: Node.Kind.typeMetadata),
                  let typeNode = metadataNode.firstChild
            else { continue }
            return typeNode
        }
        return nil
    }

    /// Names a nominal type from its metadata record's context descriptor.
    ///
    /// Deliberately **not** through `ValueMetadataProtocol.descriptor(in:)`.
    /// That goes `Pointer.resolve(in:)` → `MachORepresentableWithCache.resolveOffset(at:)`
    /// → `fileOffset(of:)`, which for a shared-cache image answers in the file
    /// accounting while every subsequent read expects the section accounting —
    /// the two differ by a constant and the read fails `offsetOutOfBounds`
    /// (measured on SwiftUI for *both* of `ResolvedMenuStyle.Body`'s
    /// candidates). That is a pre-existing gap in reading absolute pointers
    /// offline, not something this module introduced; the ABI model's own
    /// reads go through *relative* pointers, which are pure arithmetic inside
    /// one accounting and so never hit it.
    ///
    /// `resolveRebase(fileOffset:)` sidesteps it: it answers directly in the
    /// accounting the rest of the read path uses.
    private static func typeNodeFromMetadataRecord(atOffset offset: Int, in machO: MachOFile) -> Node? {
        do {
            let kind: StoredPointer = try machO.readElement(offset: offset)
            guard let metadataKind = MetadataKind(rawValue: numericCast(kind)),
                  metadataKind == .struct || metadataKind == .enum || metadataKind == .optional
            else {
                // A class's descriptor sits at a different offset and a
                // non-nominal metadata record has none at all; naming either
                // from this layout would read an unrelated word as a pointer.
                #log(.info, "metadata at offset \(offset, privacy: .public) is not a value type (kind \(kind, privacy: .public))")
                return nil
            }
            let descriptorFieldOffset = offset + StructMetadata.descriptorOffset
            guard let descriptorOffset = machO.resolveRebase(fileOffset: descriptorFieldOffset) else { return nil }
            // Annotated because `ContextDescriptorWrapper` vends both a
            // `Self`- and a `Self?`-returning `resolve(from:in:)`.
            let descriptor: ContextDescriptorWrapper = try ContextDescriptorWrapper.resolve(from: Int(descriptorOffset), in: machO)
            return try SymbolicDemangler.demangleContext(for: descriptor, in: machO)
        } catch {
            #log(.info, "could not name the metadata at offset \(offset, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

#endif
