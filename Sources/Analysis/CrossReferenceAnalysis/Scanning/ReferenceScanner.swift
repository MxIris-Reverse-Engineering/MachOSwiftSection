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
    /// Whether register state follows the branches inside a function: a
    /// forward branch carries what the registers hold to its target, an
    /// instruction after an unconditional transfer starts from what the
    /// branches to it carried, and a loop header forgets the caller-saved
    /// registers. Off, the scan reads straight down, as the first batch did —
    /// only to measure what following them changes.
    let followsBranches: Bool
    private let registers = RegisterFile()
    /// The current function's forward branch targets not yet reached,
    /// ascending from `pendingCursor`, and the state the branches to each
    /// carried, met over every branch to the same target. Sorted lists with a
    /// cursor rather than hash tables: the scan only moves forward, so each
    /// instruction compares against one entry.
    private var pendingTargets: [UInt64] = []
    private var pendingSnapshots: [RegisterFile.Snapshot] = []
    private var pendingCursor = 0
    /// The targets of the current function's backward branches, ascending.
    private var loopHeaders: [UInt64] = []
    private var loopHeaderCursor = 0
    private var resolvedTargets: [UInt64: ResolvedTarget] = [:]
    private var selectorNames: [UInt: String] = [:]
    private var importedNames: [UInt: String] = [:]
    /// Whether the call being decoded is to a function that returns the class
    /// it was handed (`objc_opt_self` …), so `x0` survives it.
    private var callReturnsArgument = false
    /// The function being scanned, and the class its last load from
    /// `__objc_superrefs` yielded: a super send in it starts above that class.
    private var currentFunctionIndex = 0
    private var superclassReferenceClassName: String?
    /// Which slots and addresses hold a class, remembered: an image loads the
    /// same few hundred classes again and again.
    private var classObjectsBySlot: [UInt64: ObjectiveCClassObject?] = [:]
    private var classObjectsByAddress: [UInt64: ObjectiveCClassObject?] = [:]
    /// The class indexes this scan asked for, kept here so that a lookup does
    /// not contend for the analyzer's lock.
    private var classIndexes: [Int: ObjectiveCClassIndex] = [:]

    /// How many stubs and islands are followed from one call before giving
    /// up; a hop per subcache crossed is the worst case described.
    private static let maximumTrampolineHops = 8

    init(analyzer: CrossReferenceAnalyzer, table: ImageFunctionTable, keeping keptKeys: Set<CodeReferenceTable.Key>? = nil, followsBranches: Bool = true) {
        self.analyzer = analyzer
        self.table = table
        self.keptKeys = keptKeys
        self.followsBranches = followsBranches
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
        currentFunctionIndex = index
        superclassReferenceClassName = nil

        pendingTargets.removeAll(keepingCapacity: true)
        pendingSnapshots.removeAll(keepingCapacity: true)
        pendingCursor = 0
        loopHeaders.removeAll(keepingCapacity: true)
        loopHeaderCursor = 0
        if followsBranches { findLoopHeaders(start: start, end: end, words: words, instructionCount: instructionCount) }

        var previousInstructionTransfers = false
        for instructionIndex in 0 ..< instructionCount {
            let pc = start &+ UInt64(instructionIndex * 4)
            if table.isInDataInCode(pc) { continue }
            let word = UInt32(littleEndian: words[instructionIndex])
            if followsBranches { enter(pc, afterTransfer: previousInstructionTransfers) }
            previousInstructionTransfers = false

            if let target = ARM64InstructionWord.callTarget(word, at: pc) {
                callReturnsArgument = false
                Self.keep(reference(to: target, at: pc, in: function, kind: .call, isObjectiveCMethod: isObjectiveCMethod), ifFiledUnder: keptKeys, in: &references)
                if callReturnsArgument {
                    registers.clobberCallerSavedRegisters(keeping: 0)
                } else {
                    registers.clobberCallerSavedRegisters()
                }
            } else if let target = ARM64InstructionWord.branchTarget(word, at: pc) {
                previousInstructionTransfers = true
                if target < start || target >= end {
                    Self.keep(reference(to: target, at: pc, in: function, kind: .tailCall, isObjectiveCMethod: isObjectiveCMethod), ifFiledUnder: keptKeys, in: &references)
                } else if target > pc {
                    carry(to: target)
                }
            } else if let materialization = ARM64InstructionWord.addressMaterialization(word, at: pc) {
                registers.setAddress(materialization.address, of: materialization.destination)
            } else if let arithmetic = ARM64InstructionWord.addImmediate(word) {
                registers.add(arithmetic.addend, to: arithmetic.source, into: arithmetic.destination)
                if let address = registers.builtAddress(of: arithmetic.destination), let classObject = classObject(atAddress: address) {
                    Self.keep(classReference(to: classObject, at: pc, in: function), ifFiledUnder: keptKeys, in: &references)
                }
            } else if let load = ARM64InstructionWord.load(word) {
                let slot = registers.builtAddress(of: load.base).map { ARM64InstructionWord.adding(load.displacement, to: $0) }
                registers.load(into: load.destination, base: load.base, displacement: load.displacement, writesBack: load.writesBack)
                if load.destination != 31, let slot {
                    if let range = table.superclassReferenceRange, range.contains(slot) {
                        superclassReferenceClassName = classObject(storedAt: runtimeAddress(ofUnslid: slot, slide: table.slide))?.name
                    } else if let classObject = classObjectLoaded(fromSlot: slot) {
                        Self.keep(classReference(to: classObject, at: pc, in: function), ifFiledUnder: keptKeys, in: &references)
                    }
                }
            } else if let move = ARM64InstructionWord.moveRegister(word) {
                registers.copy(move.source, to: move.destination)
            } else if let wide = ARM64InstructionWord.moveWide(word) {
                registers.moveWide(into: wide.destination, immediate: wide.immediate, shift: wide.shift, keepsOtherBits: wide.keepsOtherBits)
            } else if let branch = ARM64InstructionWord.registerBranch(word) {
                if branch.isCall {
                    Self.keep(indirectReference(through: branch, at: pc, in: function, kind: .call), ifFiledUnder: keptKeys, in: &references)
                    registers.clobberCallerSavedRegisters()
                } else {
                    previousInstructionTransfers = true
                    // A computed `br` is a jump table; a pointer loaded from
                    // memory, or an authenticated one, is a tail call.
                    if branch.isAuthenticated || registers.wasLoadedFromMemory(branch.target) {
                        Self.keep(indirectReference(through: branch, at: pc, in: function, kind: .tailCall), ifFiledUnder: keptKeys, in: &references)
                    }
                }
            } else if let target = ARM64InstructionWord.conditionalBranchTarget(word, at: pc) {
                if target < start || target >= end {
                    Self.keep(reference(to: target, at: pc, in: function, kind: .tailCall, isObjectiveCMethod: isObjectiveCMethod), ifFiledUnder: keptKeys, in: &references)
                } else if target > pc {
                    carry(to: target)
                }
            } else if ARM64InstructionWord.isReturn(word) {
                previousInstructionTransfers = true
            } else {
                registers.forgetRegistersWritten(by: word)
            }
        }
    }

    // MARK: - Branches

    /// The targets of the function's backward branches: what reaches them
    /// from below is not known when the scan gets there.
    private mutating func findLoopHeaders(start: UInt64, end: UInt64, words: UnsafePointer<UInt32>, instructionCount: Int) {
        for instructionIndex in 0 ..< instructionCount {
            let pc = start &+ UInt64(instructionIndex * 4)
            let word = UInt32(littleEndian: words[instructionIndex])
            guard let target = ARM64InstructionWord.branchTarget(word, at: pc) ?? ARM64InstructionWord.conditionalBranchTarget(word, at: pc),
                  target >= start, target <= pc
            else { continue }
            loopHeaders.append(target)
        }
        loopHeaders.sort()
    }

    /// Carries what the registers hold to a forward branch's target.
    private mutating func carry(to target: UInt64) {
        let snapshot = registers.snapshot()
        var lower = pendingCursor
        var upper = pendingTargets.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if pendingTargets[middle] < target { lower = middle + 1 } else { upper = middle }
        }
        if lower < pendingTargets.count, pendingTargets[lower] == target {
            pendingSnapshots[lower].meet(snapshot)
        } else {
            pendingTargets.insert(target, at: lower)
            pendingSnapshots.insert(snapshot, at: lower)
        }
    }

    /// Sets the registers up for the instruction at `pc` from the paths that
    /// reach it: the branches that carried state here, falling through unless
    /// the instruction before was an unconditional transfer, and nothing
    /// known about a loop's back edge. An instruction after a transfer that
    /// no branch here targets is reached some way the scan does not see — a
    /// jump table — so the caller-saved registers are unknown there.
    private mutating func enter(_ pc: UInt64, afterTransfer: Bool) {
        // Targets the scan stepped over (data in code) are dropped.
        while pendingCursor < pendingTargets.count, pendingTargets[pendingCursor] < pc { pendingCursor += 1 }
        if pendingCursor < pendingTargets.count, pendingTargets[pendingCursor] == pc {
            if afterTransfer {
                registers.restore(pendingSnapshots[pendingCursor])
            } else {
                registers.meet(pendingSnapshots[pendingCursor])
            }
            pendingCursor += 1
        } else if afterTransfer {
            registers.clobberCallerSavedRegisters()
        }
        while loopHeaderCursor < loopHeaders.count, loopHeaders[loopHeaderCursor] < pc { loopHeaderCursor += 1 }
        if loopHeaderCursor < loopHeaders.count, loopHeaders[loopHeaderCursor] == pc {
            registers.clobberCallerSavedRegisters()
        }
    }

    // MARK: - References

    private mutating func reference(to target: UInt64, at pc: UInt64, in function: CodeLocation, kind: CodeReference.Kind, isObjectiveCMethod: Bool) -> CodeReference {
        let referenceTarget: CodeReferenceTarget
        var isRuntimeHelperCall = false
        switch resolve(target) {
        case .selector(let selector):
            referenceTarget = .messageSend(selector: selectorName(selector), receiver: receiverHint(isObjectiveCMethod: isObjectiveCMethod))
        case .function(let location, let isRuntimeHelper, let messageSendKind, let returnsItsClassArgument):
            switch messageSendKind {
            case .classic?:
                if let selector = selectorInSelectorRegister() {
                    referenceTarget = .messageSend(selector: selector, receiver: receiverHint(isObjectiveCMethod: isObjectiveCMethod))
                } else {
                    referenceTarget = .function(location)
                }
            case .superclass?:
                if let selector = selectorInSelectorRegister() {
                    referenceTarget = .superMessageSend(selector: selector, className: superclassSendClassName())
                } else {
                    referenceTarget = .function(location)
                }
            case nil:
                referenceTarget = .function(location)
                isRuntimeHelperCall = isRuntimeHelper
                callReturnsArgument = returnsItsClassArgument
            }
        case .importedSymbol(let name):
            let importedName = importedSymbolName(name)
            referenceTarget = .importedSymbol(name: importedName)
            isRuntimeHelperCall = RuntimeHelperNames.isRuntimeHelper(name)
            callReturnsArgument = Self.returnsItsClassArgument(name)
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

    private mutating func receiverHint(isObjectiveCMethod: Bool) -> ReceiverClassHint {
        if isObjectiveCMethod, registers.holdsMethodReceiver(0) { return .methodReceiver }
        if let classObject = classObject(inRegister: 0) { return .classLiteral(classObject.name) }
        return .unknown
    }

    // MARK: - Classes

    private func classReference(to classObject: ObjectiveCClassObject, at pc: UInt64, in function: CodeLocation) -> CodeReference {
        CodeReference(function: function, instructionAddress: pc, kind: .reference, target: .objectiveCClass(name: classObject.name, location: classObject.location), isRuntimeHelperCall: false)
    }

    /// The class a register holds: an `adrp` / `add` of the class object, or
    /// a load from a slot holding it.
    private mutating func classObject(inRegister register: Int) -> ObjectiveCClassObject? {
        if let address = registers.builtAddress(of: register) { return classObject(atAddress: address) }
        if let slot = registers.slotAddress(of: register) { return classObjectLoaded(fromSlot: slot) }
        return nil
    }

    /// The class object at the unslid `address`, when an image lists one
    /// there. Most addresses code builds lie in its own image outside the
    /// class objects' segments — strings, selectors, constants — and are
    /// turned away before any lookup.
    private mutating func classObject(atAddress address: UInt64) -> ObjectiveCClassObject? {
        if !table.dataSegmentRanges.contains(where: { $0.contains(address) }), table.segmentRanges.contains(where: { $0.contains(address) }) { return nil }
        if let known = classObjectsByAddress[address] { return known }
        let classObject = self.classObject(atRuntimeAddress: runtimeAddress(ofUnslid: address, slide: table.slide))
        classObjectsByAddress[address] = classObject
        return classObject
    }

    /// The class a load from the slot at the unslid `slot` yields. Only a
    /// slot of this image's GOT or class references counts, or one of the GOT
    /// pool the shared cache keeps outside every image: a constant string's
    /// `isa` also points at a class, and is no reference to it.
    private mutating func classObjectLoaded(fromSlot slot: UInt64) -> ObjectiveCClassObject? {
        let isOwnClassSlot = table.classReferenceSlotRanges.contains { $0.contains(slot) }
        // Any other slot of the image's own is no class reference.
        if !isOwnClassSlot, table.segmentRanges.contains(where: { $0.contains(slot) }) { return nil }
        if let known = classObjectsBySlot[slot] { return known }
        var classObject: ObjectiveCClassObject?
        let runtimeSlot = runtimeAddress(ofUnslid: slot, slide: table.slide)
        let isClassSlot = isOwnClassSlot
            || (analyzer.imageIndex(containingDataAddress: runtimeSlot) == nil
                && analyzer.imageIndex(containingRuntimeAddress: runtimeSlot) == nil
                && analyzer.isMapped(runtimeAddress: runtimeSlot, length: 8))
        if isClassSlot { classObject = self.classObject(storedAt: runtimeSlot) }
        classObjectsBySlot[slot] = classObject
        return classObject
    }

    /// The class a slot at the runtime `slot` points at.
    private mutating func classObject(storedAt runtimeSlot: UInt) -> ObjectiveCClassObject? {
        guard let pointer = UnsafeRawPointer(bitPattern: runtimeSlot) else { return nil }
        // Strip the pointer-authentication bits; user addresses fit in 47.
        return classObject(atRuntimeAddress: UInt(pointer.loadUnaligned(as: UInt64.self) & 0x0000_7FFF_FFFF_FFFF))
    }

    private mutating func classObject(atRuntimeAddress address: UInt) -> ObjectiveCClassObject? {
        guard let imageIndex = analyzer.imageIndex(containingDataAddress: address) else { return nil }
        if let index = classIndexes[imageIndex] { return index.classObject(atRuntimeAddress: address) }
        let index = analyzer.objectiveCClassIndex(ofImageAt: imageIndex)
        classIndexes[imageIndex] = index
        return index.classObject(atRuntimeAddress: address)
    }

    /// The class a super send in the current function starts above: the one
    /// its `__objc_superrefs` slot holds — a category method's class too —
    /// or, when no such load was seen, the class its symbol names.
    private func superclassSendClassName() -> String? {
        superclassReferenceClassName ?? table.primaryName(ofFunctionAt: currentFunctionIndex).flatMap(Self.className(ofMethodSymbol:))
    }

    /// `objc_opt_self`, `objc_opt_class`, `swift_getInitializedObjCClass`:
    /// the class they are handed is what they return.
    private static func returnsItsClassArgument(_ name: UnsafePointer<CChar>) -> Bool {
        strcmp(name, "_objc_opt_self") == 0 || strcmp(name, "_objc_opt_class") == 0 || strcmp(name, "_swift_getInitializedObjCClass") == 0
    }

    /// `-[NSView(NSLayout) frame]` → `NSView`.
    private static func className(ofMethodSymbol symbol: UnsafePointer<CChar>) -> String? {
        guard symbol[0] == 0x2D || symbol[0] == 0x2B, symbol[1] == 0x5B else { return nil }
        var length = 0
        while symbol[2 + length] != 0, symbol[2 + length] != 0x20, symbol[2 + length] != 0x28 { length += 1 }
        guard length > 0 else { return nil }
        return String(decoding: UnsafeRawBufferPointer(start: symbol + 2, count: length), as: UTF8.self)
    }

    /// The selector a classic send passes in `x1`: loaded from this image's
    /// selector references, or the selector string's own address.
    ///
    /// The second is what a classic send looks like inside the shared cache.
    /// The cache builder rewrites the `adrp` / `ldr` of a selector reference
    /// into an `adrp` / `add` of the string it points at, so the instructions
    /// carry only the string's address — macOS 27.2 compiles
    /// `-[NSObject debugDescription]` to `adrp x8; add x1, x8; b _objc_msgSend`.
    private mutating func selectorInSelectorRegister() -> String? {
        if let slotAddress = registers.slotAddress(of: 1) {
            guard let range = table.selectorReferenceRange, range.contains(slotAddress),
                  let selector = ImageFunctionTable.selectorString(inSlotAt: slotAddress, slide: table.slide)
            else { return nil }
            return selectorName(selector)
        }
        if let stringAddress = registers.builtAddress(of: 1),
           let selector = selectorString(atRuntimeAddress: runtimeAddress(ofUnslid: stringAddress, slide: table.slide)) {
            return selectorName(selector)
        }
        return nil
    }

    /// The longest selector read; longer ones are taken for something else.
    private static let maximumSelectorLength = 1024

    /// A selector string at `address`: mapped, and printable up to its
    /// terminator. Checked rather than assumed — `x1` holds the selector by
    /// convention only, and a string runs to wherever its terminator is.
    private func selectorString(atRuntimeAddress address: UInt) -> UnsafePointer<CChar>? {
        let readableLength = min(analyzer.mappedLength(fromRuntimeAddress: address), UInt(Self.maximumSelectorLength))
        guard readableLength > 0, let bytes = UnsafePointer<UInt8>(bitPattern: address) else { return nil }
        for index in 0 ..< Int(readableLength) {
            let byte = bytes[index]
            if byte == 0 {
                return index > 0 ? UnsafeRawPointer(bytes).assumingMemoryBound(to: CChar.self) : nil
            }
            // Selectors are identifiers and colons: printable, never a space.
            guard byte > 0x20, byte < 0x7F else { return nil }
        }
        return nil
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
        /// `returnsItsClassArgument`: `objc_opt_self`, `objc_opt_class`,
        /// `swift_getInitializedObjCClass`.
        case function(CodeLocation, isRuntimeHelper: Bool, messageSendKind: MessageSendKind?, returnsItsClassArgument: Bool)
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
            return .function(location, isRuntimeHelper: false, messageSendKind: .classic, returnsItsClassArgument: false)
        }
        if analyzer.superMessageSendLocations.contains(location) {
            return .function(location, isRuntimeHelper: false, messageSendKind: .superclass, returnsItsClassArgument: false)
        }
        let isRuntimeHelper = analyzer.runtimeHelperLocations.contains(location)
            || (location.imageIndex == table.imageIndex && table.runtimeHelperStarts.contains(location.address))
        return .function(location, isRuntimeHelper: isRuntimeHelper, messageSendKind: nil, returnsItsClassArgument: analyzer.classReturningFunctionLocations.contains(location))
    }

    private func runtimeAddress(ofUnslid address: UInt64, slide: Int) -> UInt {
        UInt(bitPattern: Int(bitPattern: UInt(address)) &+ slide)
    }
}
