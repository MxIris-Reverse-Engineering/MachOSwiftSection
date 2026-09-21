import Foundation
import MachOKit
import MachOKitExtensions
@_spi(Internals) import MachOSymbols

/// What an ObjC method's IMP references (evolution proposal
/// `objc-ancestor-override-recovery`): the addresses its code calls,
/// tail-calls or materializes, reduced to the Swift symbols found there.
///
/// OS frameworks strip the `To` thunk symbols, so the IMP of
/// `-[NSGlassEffectView layout]` is anonymous code — but that code still
/// calls `$sSo17NSGlassEffectViewC6AppKitE6layoutyyF` (a `bl`), a class
/// method's thunk materializes the implementation's address for an outlined
/// helper (`adrp` / `add`, then `b`), and an initializer's calls the
/// initializing entry point. Decoding the thunk recovers the reference the
/// symbol table no longer records. A thunk whose body was inlined (a bare
/// `super.viewDidHide()` becomes an outlined `objc_msgSendSuper` helper)
/// references nothing of the class and yields an empty list.
///
/// ARM64 only, like the rest of the module; another architecture yields
/// nothing rather than decoding garbage.
package enum ObjCMethodThunkReferences {
    /// How many bytes to read for one thunk: every shape seen fits in a few
    /// dozen instructions, and the decoder stops at the function's end.
    private static let windowSize = 512

    private static let maximumInstructionCount = 96

    /// The names of the Swift symbols the IMP at `implementationOffset`
    /// references, in first-reference order.
    package static func referencedSwiftSymbolNames(atImplementationOffset implementationOffset: Int, in machO: some MachORepresentableWithCache) -> [String] {
        if let machOFile = machO as? MachOFile {
            return referencedSwiftSymbolNames(atImplementationOffset: implementationOffset, in: machOFile)
        } else if let machOImage = machO as? MachOImage {
            return referencedSwiftSymbolNames(atImplementationOffset: implementationOffset, in: machOImage)
        }
        return []
    }

    private static func referencedSwiftSymbolNames(atImplementationOffset implementationOffset: Int, in machO: MachOFile) -> [String] {
        guard machO.header.cpuType == .arm64 else { return [] }
        let addressSpace = ThunkAddressSpace(of: machO)
        guard let startAddress = addressSpace.address(forOffset: implementationOffset),
              addressSpace.isInTextSegment(startAddress),
              let bytes: [UInt8] = try? machO.readElements(offset: implementationOffset, numberOfElements: windowSize)
        else { return [] }
        let addresses = referencedAddresses(machineCode: Data(bytes), startAddress: startAddress)
        var names: [String] = []
        for address in addresses where addressSpace.containsAddress(address) {
            guard let offset = addressSpace.offset(forAddress: address), let symbols = machO.symbols(offset: offset) else { continue }
            for symbol in symbols where !names.contains(symbol.name) {
                names.append(symbol.name)
            }
        }
        return names
    }

    private static func referencedSwiftSymbolNames(atImplementationOffset implementationOffset: Int, in machO: MachOImage) -> [String] {
        guard machO.header.cpuType == .arm64 else { return [] }
        let imageBase = UInt64(UInt(bitPattern: machO.ptr))
        let startAddress = imageBase &+ UInt64(implementationOffset)
        // Read only what the containing segment maps: a thunk near the end of
        // `__TEXT` must not drag the window into unmapped memory.
        let segmentRanges = machO.segments.map { segment -> Range<UInt64> in
            let slid = imageBase &+ UInt64(segment.virtualMemoryAddress) &- UInt64(machO.segments.first { $0.segmentName == "__TEXT" }?.virtualMemoryAddress ?? 0)
            return slid ..< slid &+ UInt64(segment.virtualMemorySize)
        }
        guard let textRange = segmentRanges.first(where: { $0.contains(startAddress) }) else { return [] }
        let readableCount = Int(min(UInt64(windowSize), textRange.upperBound - startAddress))
        guard readableCount >= 4 else { return [] }
        let machineCode = Data(bytes: machO.ptr.advanced(by: implementationOffset), count: readableCount)
        let addresses = referencedAddresses(machineCode: machineCode, startAddress: startAddress)
        var names: [String] = []
        for address in addresses where segmentRanges.contains(where: { $0.contains(address) }) {
            guard let symbols = machO.symbols(offset: machO.resolveOffset(at: address)) else { continue }
            for symbol in symbols where !names.contains(symbol.name) {
                names.append(symbol.name)
            }
        }
        return names
    }

    /// The addresses one function's code refers to: `bl` targets, tail-call
    /// `b` targets (a `b` leaving the decoded function), and every address a
    /// register is seen to hold after an `adrp` / `add` pair or an `adr`.
    package static func referencedAddresses(machineCode: Data, startAddress: UInt64) -> [UInt64] {
        guard let instructions = try? CapstoneThunkDecoder.decodeFunction(machineCode: machineCode, startAddress: startAddress, maximumInstructionCount: maximumInstructionCount),
              let lastInstruction = instructions.last
        else { return [] }
        let functionEnd = lastInstruction.address &+ 4
        var tracker = ThunkRegisterTracker()
        var addresses: [UInt64] = []
        func note(_ address: UInt64) {
            if !addresses.contains(address) {
                addresses.append(address)
            }
        }
        for instruction in instructions {
            switch instruction.operation {
            case .call(let target):
                note(target)
            case .branch(let target):
                if target < startAddress || target >= functionEnd {
                    note(target)
                }
            default:
                break
            }
            tracker.apply(instruction.operation)
            switch instruction.operation {
            case .materializePageAddress(let destination, _), .addImmediate(let destination, _, _):
                if let address = tracker.address(of: destination) {
                    note(address)
                }
            default:
                break
            }
        }
        return addresses
    }
}
