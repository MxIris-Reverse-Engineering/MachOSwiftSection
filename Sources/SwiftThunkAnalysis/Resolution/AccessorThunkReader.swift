#if THUNK_ANALYSIS

import Foundation
import FoundationToolbox
import MachOKit
import MachOFoundation
import MachOSwiftSection
import Demangling
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering

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
    /// Generous relative to the ~14-instruction lookup thunks measured,
    /// because a type-construction thunk runs to some ninety instructions
    /// and the function-boundary rule needs to see past a forward branch to
    /// decide where the function ends; the decoder's own instruction cap is
    /// the real bound.
    private static let machineCodeWindowSize = 1024

    /// Resolves the underlying types the thunk at `thunkOffset` yields.
    ///
    /// `thunkOffset` is the offset a kind-9 `accessorFunctionReference` node
    /// carries — which for a shared-cache image is *not* a file offset; see
    /// ``ThunkAddressSpace``. `ownerLayout` describes the generic parameters
    /// of the declaration the thunk belongs to, so an argument the thunk reads
    /// out of its buffer can be named as that parameter.
    public static func read(
        thunkAtOffset thunkOffset: Int,
        in machO: MachOFile,
        ownerLayout: AccessorThunkOwnerLayout = .unknown
    ) throws -> ResolvedAccessorThunk {
        let environment = MachOThunkEnvironment(machO: machO)
        let addressSpace = environment.addressSpace
        guard let thunkAddress = addressSpace.address(forOffset: thunkOffset) else {
            return ResolvedAccessorThunk(availabilityCheck: nil, underlyingTypes: [], limitations: [.noRecognizedShape])
        }

        let machineCode = Data(try machO.readElements(offset: thunkOffset, numberOfElements: machineCodeWindowSize) as [UInt8])
        let instructions = try CapstoneThunkDecoder.decodeFunction(
            machineCode: machineCode,
            startAddress: thunkAddress,
            maximumInstructionCount: CapstoneThunkDecoder.constructionMaximumInstructionCount,
            isKnownFunction: { target in
                if case .unknown = environment.callee(at: target) { return false }
                return true
            }
        )
        let program = AccessorThunkAnalyzer.analyze(instructions: instructions, environment: environment)
        let nodeBuilder = ThunkTypeNodeBuilder(machO: machO, environment: environment, ownerLayout: ownerLayout)

        var underlyingTypes: [ResolvedUnderlyingType] = []
        var limitations = program.limitations
        for candidate in program.candidates {
            guard let typeNode = typeNode(for: candidate.reference, nodeBuilder: nodeBuilder, addressSpace: addressSpace, in: machO) else {
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
        nodeBuilder: ThunkTypeNodeBuilder,
        addressSpace: ThunkAddressSpace,
        in machO: MachOFile
    ) -> Node? {
        switch reference {
        case .metadata(let address):
            return MetadataNaming.typeNode(forMetadataAt: address, addressSpace: addressSpace, in: machO)
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
        case .constructed(let expression):
            return nodeBuilder.typeNode(for: expression)
        }
    }
}

#endif
