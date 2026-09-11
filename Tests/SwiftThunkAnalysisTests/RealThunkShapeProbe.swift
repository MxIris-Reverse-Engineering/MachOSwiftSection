#if THUNK_ANALYSIS

import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import MachOFixtureSupport
import Demangling
@_spi(Internals) import SwiftInspection
@testable import SwiftThunkAnalysis

/// Prints the full instruction sequence of every distinct accessor thunk an
/// opaque associated type in SwiftUI points at.
///
/// **A probe, not an assertion.** It exists so the shape recognizer is written
/// against what the thunks actually contain rather than against the first
/// dozen instructions of one of them.
@Suite(.disabled("Research probe — enable explicitly when revisiting thunk shapes"))
struct RealThunkShapeProbe {
    @Test func printsEveryDistinctThunkShape() async throws {
        let cache = try DyldCache(path: .current)
        let machO = try #require(cache.machOFile(named: .SwiftUI))

        var printedThunkOffsets: Set<Int> = []
        var descriptions: [String] = []

        for associatedType in try machO.swift.associatedTypes {
            for record in associatedType.records {
                guard let thunkOffset = try accessorThunkOffset(ofRecord: record, in: machO) else { continue }
                guard printedThunkOffsets.insert(thunkOffset).inserted else { continue }

                let conformingTypeName = await (try SymbolicDemangler
                    .demangleType(for: associatedType.conformingTypeName, in: machO))
                    .print(using: DemangleOptions.default)
                var description = "######## \(conformingTypeName).\(try record.name(in: machO)) — thunk at file offset \(thunkOffset)"

                if let virtualAddress = virtualAddress(ofFileOffset: thunkOffset, in: machO) {
                    description += " / VM 0x\(String(virtualAddress, radix: 16))"
                    let machineCode = Data(try machO.readElements(offset: thunkOffset, numberOfElements: 1024) as [UInt8])
                    let instructions = try CapstoneThunkDecoder.decodeFunction(machineCode: machineCode, startAddress: virtualAddress, maximumInstructionCount: 256)
                    for instruction in instructions {
                        description += "\n  0x\(String(instruction.address, radix: 16))  \(instruction.mnemonic.padding(toLength: 10, withPad: " ", startingAt: 0))\(instruction.operation)"
                    }
                } else {
                    description += " — no virtual address"
                }
                descriptions.append(description)
            }
        }

        print(descriptions.joined(separator: "\n"))
        print("distinct thunks seen: \(printedThunkOffsets.count)")
    }

    /// Walks an associated-type record to the accessor thunk its opaque
    /// underlying type points at, if it has one.
    private func accessorThunkOffset(ofRecord record: AssociatedTypeRecord, in machO: MachOFile) throws -> Int? {
        let substitutedTypeNode = try SymbolicDemangler.demangleType(for: record.substitutedTypeName(in: machO), in: machO)
        guard let opaqueTypeNode = substitutedTypeNode.first(of: Node.Kind.opaqueType),
              let descriptorReference = opaqueTypeNode.firstChild,
              descriptorReference.isKind(of: .opaqueTypeDescriptorSymbolicReference),
              let descriptorOffset: Int = descriptorReference.index?.cast()
        else { return nil }

        let ordinal: Int = opaqueTypeNode[safeChild: 1]?.index?.cast() ?? 0
        let descriptor = try OpaqueTypeDescriptor.resolve(from: descriptorOffset, in: machO)
        let opaqueType = try OpaqueType(descriptor: descriptor, in: machO)
        guard ordinal < opaqueType.underlyingTypeArgumentMangledNames.count else { return nil }
        let underlyingTypeNode = try SymbolicDemangler.demangleType(
            for: opaqueType.underlyingTypeArgumentMangledNames[ordinal],
            in: machO
        )
        guard let accessorReference = underlyingTypeNode.first(of: Node.Kind.accessorFunctionReference),
              let offset: Int = accessorReference.index?.cast()
        else { return nil }
        return offset
    }

    /// File offset → virtual address, through the segment that contains it.
    ///
    /// `MachOFile.fileOffset(of:)` runs the other way and, for an image inside
    /// a shared cache, honestly answers `nil` when the target lives in another
    /// subcache — so the reverse mapping is built from the segment commands
    /// and cross-checked by round-tripping back through it.
    private func virtualAddress(ofFileOffset fileOffset: Int, in machO: MachOFile) -> UInt64? {
        for segment in machO.segments {
            let segmentFileOffset = Int(segment.fileOffset)
            guard fileOffset >= segmentFileOffset, fileOffset < segmentFileOffset + Int(segment.fileSize) else { continue }
            return UInt64(fileOffset - segmentFileOffset + Int(segment.virtualMemoryAddress))
        }
        return nil
    }
}

#endif
