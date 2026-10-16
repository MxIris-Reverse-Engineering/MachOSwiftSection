import Foundation
import MachOKit
import ARM64InstructionDecoding

/// Decodes the functions of one image into ``CodeReference``s.
///
/// Only the instructions that call, branch out, or build an address are
/// decoded; every other instruction merely forgets what its destination
/// register held. Register tracking records only what is certain — an
/// address `adrp` / `add` built, a slot that address was loaded from, the
/// receiver an Objective-C method arrived with, a pointer-authentication
/// constant — and nothing is guessed.
///
/// A scanner memoizes how each call target resolves, so one scanner should
/// serve a whole image.
struct ReferenceScanner {
    private let analyzer: CrossReferenceAnalyzer
    private let table: ImageFunctionTable
    /// When set, only references filed under one of these keys are kept.
    private let keptKeys: Set<CodeReferenceTable.Key>?
    private let registers = RegisterFile()
    private var resolvedTargets: [UInt64: ResolvedTarget] = [:]
    private var selectorNames: [UInt: String] = [:]
    private var importedNames: [UInt: String] = [:]

    /// How many stubs and islands are followed from one call before giving
    /// up; a hop per subcache crossed is the worst case described.
    private static let maximumTrampolineHops = 8

    init(analyzer: CrossReferenceAnalyzer, table: ImageFunctionTable, keeping keptKeys: Set<CodeReferenceTable.Key>? = nil) {
        self.analyzer = analyzer
        self.table = table
        self.keptKeys = keptKeys
    }

    private static func keep(_ reference: CodeReference, ifFiledUnder keptKeys: Set<CodeReferenceTable.Key>?, in references: inout [CodeReference]) {
        if let keptKeys {
            guard let key = reference.target.tableKey, keptKeys.contains(key) else { return }
        }
        references.append(reference)
    }

    // MARK: - Scanning

    mutating func scanFunction(at index: Int, into references: inout [CodeReference]) {
        let start = table.starts[index]
        let end = table.end(ofFunctionAt: index)
        guard end > start else { return }
        let function = CodeLocation(imageIndex: table.imageIndex, address: start)
        let words = table.instructionPointer(at: start)
        let instructionCount = Int((end - start) / 4)
        let isObjectiveCMethod = table.isObjectiveCMethod(at: index)

        registers.reset()
        if isObjectiveCMethod { registers.setMethodReceiver(0) }

        for instructionIndex in 0 ..< instructionCount {
            let pc = start &+ UInt64(instructionIndex * 4)
            if table.isInDataInCode(pc) { continue }
            let word = UInt32(littleEndian: words[instructionIndex])

            if let target = ARM64InstructionWord.callTarget(word, at: pc) {
                Self.keep(reference(to: target, at: pc, in: function, kind: .call, isObjectiveCMethod: isObjectiveCMethod), ifFiledUnder: keptKeys, in: &references)
                registers.clobberCallerSavedRegisters()
            } else if let target = ARM64InstructionWord.branchTarget(word, at: pc) {
                if target < start || target >= end {
                    Self.keep(reference(to: target, at: pc, in: function, kind: .tailCall, isObjectiveCMethod: isObjectiveCMethod), ifFiledUnder: keptKeys, in: &references)
                }
            } else if let materialization = ARM64InstructionWord.addressMaterialization(word, at: pc) {
                registers.setAddress(materialization.address, of: materialization.destination)
            } else if let arithmetic = ARM64InstructionWord.addImmediate(word) {
                registers.add(arithmetic.addend, to: arithmetic.source, into: arithmetic.destination)
            } else if let load = ARM64InstructionWord.load(word) {
                registers.load(into: load.destination, base: load.base, displacement: load.displacement, writesBack: load.writesBack)
            } else if let move = ARM64InstructionWord.moveRegister(word) {
                registers.copy(move.source, to: move.destination)
            } else if let wide = ARM64InstructionWord.moveWide(word) {
                registers.moveWide(into: wide.destination, immediate: wide.immediate, shift: wide.shift, keepsOtherBits: wide.keepsOtherBits)
            } else if let branch = ARM64InstructionWord.registerBranch(word) {
                if branch.isCall {
                    Self.keep(indirectReference(through: branch, at: pc, in: function, kind: .call), ifFiledUnder: keptKeys, in: &references)
                    registers.clobberCallerSavedRegisters()
                } else if branch.isAuthenticated || registers.wasLoadedFromMemory(branch.target) {
                    // A computed `br` is a jump table; a pointer loaded from
                    // memory, or an authenticated one, is a tail call.
                    Self.keep(indirectReference(through: branch, at: pc, in: function, kind: .tailCall), ifFiledUnder: keptKeys, in: &references)
                }
            } else if let target = ARM64InstructionWord.conditionalBranchTarget(word, at: pc) {
                if target < start || target >= end {
                    Self.keep(reference(to: target, at: pc, in: function, kind: .tailCall, isObjectiveCMethod: isObjectiveCMethod), ifFiledUnder: keptKeys, in: &references)
                }
            } else {
                registers.forgetRegistersWritten(by: word)
            }
        }
    }

    // MARK: - References

    private mutating func reference(to target: UInt64, at pc: UInt64, in function: CodeLocation, kind: CodeReference.Kind, isObjectiveCMethod: Bool) -> CodeReference {
        let referenceTarget: CodeReferenceTarget
        var isRuntimeHelperCall = false
        switch resolve(target) {
        case .selector(let selector):
            referenceTarget = .messageSend(selector: selectorName(selector), receiver: receiverHint(isObjectiveCMethod: isObjectiveCMethod))
        case .function(let location, let isRuntimeHelper, let messageSendKind):
            switch messageSendKind {
            case .classic?:
                if let selector = selectorInSelectorRegister() {
                    referenceTarget = .messageSend(selector: selector, receiver: receiverHint(isObjectiveCMethod: isObjectiveCMethod))
                } else {
                    referenceTarget = .function(location)
                }
            case .superclass?:
                if let selector = selectorInSelectorRegister() {
                    referenceTarget = .superMessageSend(selector: selector)
                } else {
                    referenceTarget = .function(location)
                }
            case nil:
                referenceTarget = .function(location)
                isRuntimeHelperCall = isRuntimeHelper
            }
        case .importedSymbol(let name):
            let importedName = importedSymbolName(name)
            referenceTarget = .importedSymbol(name: importedName)
            isRuntimeHelperCall = RuntimeHelperNames.isRuntimeHelper(name)
        case .unrecognized:
            referenceTarget = .unrecognized(address: target)
        }
        return CodeReference(function: function, instructionAddress: pc, kind: kind, target: referenceTarget, isRuntimeHelperCall: isRuntimeHelperCall)
    }

    private func indirectReference(through branch: ARM64InstructionWord.RegisterBranch, at pc: UInt64, in function: CodeLocation, kind: CodeReference.Kind) -> CodeReference {
        var constant: UInt16?
        var isAddressBlended = false
        if let modifier = branch.modifier, let modifierConstant = registers.constant(of: modifier) {
            constant = modifierConstant.value
            isAddressBlended = modifierConstant.isBlended
        }
        let evidence = IndirectCallEvidence(
            table: .none,
            tableOffset: registers.loadDisplacement(of: branch.target),
            pointerAuthenticationConstant: constant,
            isAddressBlended: isAddressBlended
        )
        return CodeReference(function: function, instructionAddress: pc, kind: kind, target: .indirect(evidence), isRuntimeHelperCall: false)
    }

    private func receiverHint(isObjectiveCMethod: Bool) -> ReceiverClassHint {
        isObjectiveCMethod && registers.holdsMethodReceiver(0) ? .methodReceiver : .unknown
    }

    /// The selector `x1` was loaded with, when it came from this image's
    /// selector references.
    private mutating func selectorInSelectorRegister() -> String? {
        guard let slotAddress = registers.slotAddress(of: 1),
              let range = table.selectorReferenceRange, range.contains(slotAddress),
              let selector = ImageFunctionTable.selectorString(inSlotAt: slotAddress, slide: table.slide)
        else { return nil }
        return selectorName(selector)
    }

    private mutating func selectorName(_ pointer: UnsafePointer<CChar>) -> String {
        let key = UInt(bitPattern: pointer)
        if let known = selectorNames[key] { return known }
        let name = String(cString: pointer)
        selectorNames[key] = name
        return name
    }

    private mutating func importedSymbolName(_ pointer: UnsafePointer<CChar>) -> String {
        let key = UInt(bitPattern: pointer)
        if let known = importedNames[key] { return known }
        let name = String(cString: pointer)
        importedNames[key] = name
        return name
    }

    // MARK: - Resolving call targets

    private enum MessageSendKind {
        case classic
        case superclass
    }

    private enum ResolvedTarget {
        case function(CodeLocation, isRuntimeHelper: Bool, messageSendKind: MessageSendKind?)
        /// A stub that names its selector.
        case selector(UnsafePointer<CChar>)
        case importedSymbol(UnsafePointer<CChar>)
        case unrecognized
    }

    /// Where an unslid address in this image's address space leads.
    private mutating func resolve(_ target: UInt64) -> ResolvedTarget {
        if let known = resolvedTargets[target] { return known }
        let resolved = computeResolution(of: target)
        resolvedTargets[target] = resolved
        return resolved
    }

    private func computeResolution(of target: UInt64) -> ResolvedTarget {
        if let range = table.objectiveCStubRange, range.contains(target) {
            guard let selector = table.objectiveCStubSelectors[target] else { return .unrecognized }
            return .selector(selector)
        }
        if let stub = table.symbolStubs[target] {
            // dyld binds every slot when it loads the image, lazy pointers
            // included (macOS 27.2, `LazyBindingTests`), so the slot is read
            // as it stands.
            if let slotAddress = stub.slotAddress,
               let resolved = resolveSlot(atRuntimeAddress: runtimeAddress(ofUnslid: slotAddress, slide: table.slide), hops: 0) {
                return resolved
            }
            if let name = stub.name { return .importedSymbol(name) }
            return .unrecognized
        }
        if target >= table.textStart, target < table.textEnd {
            return functionTarget(CodeLocation(imageIndex: table.imageIndex, address: target))
        }
        return resolve(runtimeAddress: runtimeAddress(ofUnslid: target, slide: table.slide), hops: 0)
    }

    private func resolve(runtimeAddress address: UInt, hops: Int) -> ResolvedTarget {
        if let location = analyzer.location(ofRuntimeAddress: address) {
            return functionTarget(location)
        }
        // Between images: a stub or island the cache builder put there.
        guard hops < Self.maximumTrampolineHops,
              analyzer.isExecutable(runtimeAddress: address, length: UInt(ARM64Trampoline.maximumInstructionCount * 4)),
              let pointer = UnsafeRawPointer(bitPattern: address),
              let trampoline = ARM64Trampoline(readingAt: pointer, address: UInt64(address))
        else { return .unrecognized }
        switch trampoline {
        case .selectorStub(let selectorAddress, _):
            guard analyzer.isMapped(runtimeAddress: UInt(selectorAddress), length: 1),
                  let selector = UnsafePointer<CChar>(bitPattern: UInt(selectorAddress))
            else { return .unrecognized }
            return .selector(selector)
        case .slotLoad(let slotAddress):
            return resolveSlot(atRuntimeAddress: UInt(slotAddress), hops: hops + 1) ?? .unrecognized
        case .computed(let computedTarget):
            return resolve(runtimeAddress: UInt(computedTarget), hops: hops + 1)
        }
    }

    /// Follows the pointer a GOT slot holds — dyld or the cache builder bound
    /// it already.
    private func resolveSlot(atRuntimeAddress slotAddress: UInt, hops: Int) -> ResolvedTarget? {
        guard analyzer.isMapped(runtimeAddress: slotAddress, length: 8),
              let slot = UnsafeRawPointer(bitPattern: slotAddress)
        else { return nil }
        // Strip the pointer-authentication bits; user addresses fit in 47.
        let target = UInt(slot.loadUnaligned(as: UInt64.self) & 0x0000_7FFF_FFFF_FFFF)
        guard target != 0 else { return nil }
        return resolve(runtimeAddress: target, hops: hops)
    }

    private func functionTarget(_ location: CodeLocation) -> ResolvedTarget {
        if analyzer.messageSendLocations.contains(location) {
            return .function(location, isRuntimeHelper: false, messageSendKind: .classic)
        }
        if analyzer.superMessageSendLocations.contains(location) {
            return .function(location, isRuntimeHelper: false, messageSendKind: .superclass)
        }
        let isRuntimeHelper = analyzer.runtimeHelperLocations.contains(location)
            || (location.imageIndex == table.imageIndex && table.runtimeHelperStarts.contains(location.address))
        return .function(location, isRuntimeHelper: isRuntimeHelper, messageSendKind: nil)
    }

    private func runtimeAddress(ofUnslid address: UInt64, slide: Int) -> UInt {
        UInt(bitPattern: Int(bitPattern: UInt(address)) &+ slide)
    }
}
