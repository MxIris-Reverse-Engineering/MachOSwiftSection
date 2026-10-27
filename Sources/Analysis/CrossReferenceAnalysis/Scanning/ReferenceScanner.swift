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
    /// What the call being decoded stands for besides the call itself: a
    /// metadata accessor, a mangled-name instantiation.
    private var calledTypeFunction: TypeFunction?
    /// The sends a call to a libobjc entry point makes after its first:
    /// `init`, for `objc_alloc_init`.
    private var followingSendSelectors: ArraySlice<String> = []
    /// What each slot and address holds, remembered: an image loads the same
    /// few hundred classes and types again and again.
    private var slotReferences: [UInt64: AddressReference?] = [:]
    private var addressReferences: [UInt64: AddressReference?] = [:]
    /// The class and type indexes this scan asked for, kept here so that a
    /// lookup does not contend for the analyzer's lock — a whole-cache scan
    /// spent most of its time waiting on it. A reference, so that resolving
    /// a call target, which does not mutate the scanner, uses it too.
    private let indexes: ScanIndexes
    /// When set, the references to one Swift type are kept besides the
    /// ones `keptKeys` names.
    private let swiftTypeQuery: SwiftTypeQuery?
    /// Whether the scan looks for class and type references at all. A query
    /// for the callers of a selector or a function keeps none, and skipping
    /// them keeps it as fast as before they existed; a send's class-literal
    /// receiver is still told, at the send.
    private let findsTypeReferences: Bool

    /// How many stubs and islands are followed from one call before giving
    /// up; a hop per subcache crossed is the worst case described.
    private static let maximumTrampolineHops = 8

    init(analyzer: CrossReferenceAnalyzer, table: ImageFunctionTable, keeping keptKeys: Set<CodeReferenceTable.Key>? = nil, matching swiftTypeQuery: SwiftTypeQuery? = nil, followsBranches: Bool = true) {
        self.analyzer = analyzer
        self.table = table
        self.keptKeys = keptKeys ?? (swiftTypeQuery == nil ? nil : [])
        self.swiftTypeQuery = swiftTypeQuery
        self.followsBranches = followsBranches
        self.indexes = ScanIndexes(analyzer: analyzer)
        self.findsTypeReferences = swiftTypeQuery != nil || keptKeys.map { keys in
            keys.contains { key in
                switch key {
                case .objectiveCClass, .swiftTypeDescriptor: return true
                case .function, .selector, .importedSymbol: return false
                }
            }
        } ?? true
    }

    /// Takes the reference ready-made: a reference built in the call's
    /// argument list would mutate the scanner while this non-mutating call
    /// holds it, and Swift copies the whole scanner — its memo dictionaries
    /// included — to keep the two apart, which made a scan of the cache
    /// forty times slower.
    private func keep(_ reference: CodeReference, in references: inout [CodeReference]) {
        if let keptKeys {
            let isFiled = reference.target.tableKey.map(keptKeys.contains) ?? false
            guard isFiled || swiftTypeQuery?.matches(reference.target) == true else { return }
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
            let instructionAddress = start &+ UInt64(instructionIndex * 4)
            if table.isInDataInCode(instructionAddress) { continue }
            let word = UInt32(littleEndian: words[instructionIndex])
            if followsBranches { enter(instructionAddress, afterTransfer: previousInstructionTransfers) }
            previousInstructionTransfers = false

            if let target = ARM64InstructionWord.callTarget(word, at: instructionAddress) {
                callReturnsArgument = false
                noteCall(to: target, at: instructionAddress, in: function, kind: .call, isObjectiveCMethod: isObjectiveCMethod, references: &references)
                if callReturnsArgument {
                    registers.clobberCallerSavedRegisters(keeping: 0)
                } else {
                    registers.clobberCallerSavedRegisters()
                }
            } else if let target = ARM64InstructionWord.branchTarget(word, at: instructionAddress) {
                previousInstructionTransfers = true
                if target < start || target >= end {
                    noteCall(to: target, at: instructionAddress, in: function, kind: .tailCall, isObjectiveCMethod: isObjectiveCMethod, references: &references)
                } else if target > instructionAddress {
                    carry(to: target)
                }
            } else if let materialization = ARM64InstructionWord.addressMaterialization(word, at: instructionAddress) {
                registers.setAddress(materialization.address, of: materialization.destination)
                // `adr` builds the whole address an `adrp` / `add` pair builds
                // — what ld64 makes of such a pair within a megabyte.
                if !materialization.isPageAddress, findsTypeReferences, let address = registers.builtAddress(of: materialization.destination), let addressReference = addressReference(atAddress: address) {
                    let typeReference = reference(to: addressReference, at: instructionAddress, in: function)
                    keep(typeReference, in: &references)
                }
            } else if let arithmetic = ARM64InstructionWord.addImmediate(word) {
                registers.add(arithmetic.addend, to: arithmetic.source, into: arithmetic.destination)
                if findsTypeReferences, let address = registers.builtAddress(of: arithmetic.destination), let addressReference = addressReference(atAddress: address) {
                    let typeReference = reference(to: addressReference, at: instructionAddress, in: function)
                    keep(typeReference, in: &references)
                }
            } else if let load = ARM64InstructionWord.load(word) {
                let slot = registers.builtAddress(of: load.base).map { ARM64InstructionWord.adding(load.displacement, to: $0) }
                registers.load(into: load.destination, base: load.base, displacement: load.displacement, writesBack: load.writesBack)
                if let slot { noteLoad(fromSlot: slot, into: load.destination, at: instructionAddress, in: function, references: &references) }
            } else if let literal = ARM64InstructionWord.loadLiteral(word, at: instructionAddress) {
                // What ld64 makes of an `adrp` / `ldr` pair whose slot lies
                // within a megabyte: the selector reference a send passes in
                // `x1`, a class reference, a GOT slot.
                registers.load(into: literal.destination, fromSlotAt: literal.slotAddress)
                noteLoad(fromSlot: literal.slotAddress, into: literal.destination, at: instructionAddress, in: function, references: &references)
            } else if let move = ARM64InstructionWord.moveRegister(word) {
                registers.copy(move.source, to: move.destination)
            } else if let wide = ARM64InstructionWord.moveWide(word) {
                registers.moveWide(into: wide.destination, immediate: wide.immediate, shift: wide.shift, keepsOtherBits: wide.keepsOtherBits)
            } else if let branch = ARM64InstructionWord.registerBranch(word) {
                if branch.isCall {
                    let indirectCall = indirectReference(through: branch, at: instructionAddress, in: function, kind: .call)
                    keep(indirectCall, in: &references)
                    registers.clobberCallerSavedRegisters()
                } else {
                    previousInstructionTransfers = true
                    // A computed `br` is a jump table; a pointer loaded from
                    // memory, or an authenticated one, is a tail call.
                    if branch.isAuthenticated || registers.wasLoadedFromMemory(branch.target) {
                        let indirectTailCall = indirectReference(through: branch, at: instructionAddress, in: function, kind: .tailCall)
                        keep(indirectTailCall, in: &references)
                    }
                }
            } else if let target = ARM64InstructionWord.conditionalBranchTarget(word, at: instructionAddress) {
                if target < start || target >= end {
                    noteCall(to: target, at: instructionAddress, in: function, kind: .tailCall, isObjectiveCMethod: isObjectiveCMethod, references: &references)
                } else if target > instructionAddress {
                    carry(to: target)
                }
            } else if ARM64InstructionWord.isReturn(word) {
                previousInstructionTransfers = true
            } else {
                registers.forgetRegistersWritten(by: word)
            }
        }
    }

    /// The references a call, or a branch out of the function, makes: the
    /// call itself — or the sends a libobjc entry point stands for, a later
    /// one to what the one before it returned, which the scan does not know —
    /// and the type a metadata accessor or a mangled-name helper references.
    private mutating func noteCall(to target: UInt64, at instructionAddress: UInt64, in function: CodeLocation, kind: CodeReference.Kind, isObjectiveCMethod: Bool, references: inout [CodeReference]) {
        let callReference = reference(to: target, at: instructionAddress, in: function, kind: kind, isObjectiveCMethod: isObjectiveCMethod)
        keep(callReference, in: &references)
        for selector in followingSendSelectors {
            let send = CodeReference(function: function, instructionAddress: instructionAddress, kind: kind, target: .messageSend(selector: selector, receiver: .unknown), isRuntimeHelperCall: false)
            keep(send, in: &references)
        }
        if let typeReference = typeReferenceOfCalledFunction(at: instructionAddress, in: function) { keep(typeReference, in: &references) }
    }

    /// What a load from the slot at the unslid `slot` tells besides what the
    /// register now holds: the class a super send in this function starts
    /// above, or a class or a type it references.
    private mutating func noteLoad(fromSlot slot: UInt64, into destination: Int, at instructionAddress: UInt64, in function: CodeLocation, references: inout [CodeReference]) {
        guard destination != ARM64InstructionWord.zeroOrStackPointerRegister else { return }
        if let range = table.superclassReferenceRange, range.contains(slot) {
            superclassReferenceClassName = classObject(storedAt: runtimeAddress(ofUnslid: slot, slide: table.slide))?.name
        } else if findsTypeReferences, let slotReference = slotReference(fromSlot: slot) {
            let typeReference = reference(to: slotReference, at: instructionAddress, in: function)
            keep(typeReference, in: &references)
        }
    }

    // MARK: - Branches

    /// The targets of the function's backward branches: what reaches them
    /// from below is not known when the scan gets there.
    private mutating func findLoopHeaders(start: UInt64, end: UInt64, words: UnsafePointer<UInt32>, instructionCount: Int) {
        for instructionIndex in 0 ..< instructionCount {
            let instructionAddress = start &+ UInt64(instructionIndex * 4)
            let word = UInt32(littleEndian: words[instructionIndex])
            guard let target = ARM64InstructionWord.branchTarget(word, at: instructionAddress) ?? ARM64InstructionWord.conditionalBranchTarget(word, at: instructionAddress),
                  target >= start, target <= instructionAddress
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

    /// Sets the registers up for the instruction at `instructionAddress` from the paths that
    /// reach it: the branches that carried state here, falling through unless
    /// the instruction before was an unconditional transfer, and nothing
    /// known about a loop's back edge. An instruction after a transfer that
    /// no branch here targets is reached some way the scan does not see — a
    /// jump table — so the caller-saved registers are unknown there.
    private mutating func enter(_ instructionAddress: UInt64, afterTransfer: Bool) {
        // Targets the scan stepped over (data in code) are dropped.
        while pendingCursor < pendingTargets.count, pendingTargets[pendingCursor] < instructionAddress { pendingCursor += 1 }
        if pendingCursor < pendingTargets.count, pendingTargets[pendingCursor] == instructionAddress {
            if afterTransfer {
                registers.restore(pendingSnapshots[pendingCursor])
            } else {
                registers.meet(pendingSnapshots[pendingCursor])
            }
            pendingCursor += 1
        } else if afterTransfer {
            registers.clobberCallerSavedRegisters()
        }
        while loopHeaderCursor < loopHeaders.count, loopHeaders[loopHeaderCursor] < instructionAddress { loopHeaderCursor += 1 }
        if loopHeaderCursor < loopHeaders.count, loopHeaders[loopHeaderCursor] == instructionAddress {
            registers.clobberCallerSavedRegisters()
        }
    }

    // MARK: - References

    private mutating func reference(to target: UInt64, at instructionAddress: UInt64, in function: CodeLocation, kind: CodeReference.Kind, isObjectiveCMethod: Bool) -> CodeReference {
        let referenceTarget: CodeReferenceTarget
        var isRuntimeHelperCall = false
        calledTypeFunction = nil
        followingSendSelectors = []
        switch resolve(target) {
        case .selector(let selector):
            referenceTarget = .messageSend(selector: selectorName(selector), receiver: receiverHint(isObjectiveCMethod: isObjectiveCMethod))
        case .entryPoint(let selectors, let returnsItsClassArgument):
            referenceTarget = .messageSend(selector: selectors[0], receiver: receiverHint(isObjectiveCMethod: isObjectiveCMethod))
            followingSendSelectors = selectors.dropFirst()
            callReturnsArgument = returnsItsClassArgument
        case .function(let functionTarget):
            switch functionTarget.messageSendKind {
            case .classic?:
                if let selector = selectorInSelectorRegister() {
                    referenceTarget = .messageSend(selector: selector, receiver: receiverHint(isObjectiveCMethod: isObjectiveCMethod))
                } else {
                    referenceTarget = .function(functionTarget.location)
                }
            case .superclass?:
                if let selector = selectorInSelectorRegister() {
                    referenceTarget = .superMessageSend(selector: selector, className: superclassSendClassName())
                } else {
                    referenceTarget = .function(functionTarget.location)
                }
            case nil:
                referenceTarget = .function(functionTarget.location)
                isRuntimeHelperCall = functionTarget.isRuntimeHelper
                callReturnsArgument = functionTarget.returnsItsClassArgument
                calledTypeFunction = functionTarget.typeFunction
            }
        case .importedSymbol(let name):
            let importedName = importedSymbolName(name)
            referenceTarget = .importedSymbol(name: importedName)
            isRuntimeHelperCall = RuntimeHelperNames.isRuntimeHelper(name)
            callReturnsArgument = CrossReferenceAnalyzer.returnsItsClassArgument(name)
            if let accessorSymbol = Self.accessorSymbol(name) { calledTypeFunction = .accessorSymbol(accessorSymbol) }
        case .unrecognized:
            referenceTarget = .unrecognized(address: target)
        }
        return CodeReference(function: function, instructionAddress: instructionAddress, kind: kind, target: referenceTarget, isRuntimeHelperCall: isRuntimeHelperCall)
    }

    private func indirectReference(through branch: ARM64InstructionWord.RegisterBranch, at instructionAddress: UInt64, in function: CodeLocation, kind: CodeReference.Kind) -> CodeReference {
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
        return CodeReference(function: function, instructionAddress: instructionAddress, kind: kind, target: .indirect(evidence), isRuntimeHelperCall: false)
    }

    private mutating func receiverHint(isObjectiveCMethod: Bool) -> ReceiverClassHint {
        if isObjectiveCMethod, registers.holdsMethodReceiver(0) { return .methodReceiver }
        if case .objectiveCClass(let classObject)? = reference(inRegister: 0) { return .classLiteral(classObject.name) }
        return .unknown
    }

    // MARK: - Classes and types

    /// A class or a Swift type an address or a slot leads to.
    private enum AddressReference {
        case objectiveCClass(ObjectiveCClassObject)
        /// The type's context descriptor.
        case swiftType(CodeLocation)
    }

    private func reference(to addressReference: AddressReference, at instructionAddress: UInt64, in function: CodeLocation) -> CodeReference {
        let target: CodeReferenceTarget
        switch addressReference {
        case .objectiveCClass(let classObject):
            target = .objectiveCClass(name: classObject.name, location: classObject.location)
        case .swiftType(let descriptor):
            target = .swiftType(descriptor: descriptor)
        }
        return CodeReference(function: function, instructionAddress: instructionAddress, kind: .reference, target: target, isRuntimeHelperCall: false)
    }

    /// What a register holds: an `adrp` / `add` of a class object or type
    /// metadata, or a load from a slot holding one.
    private mutating func reference(inRegister register: Int) -> AddressReference? {
        if let address = registers.builtAddress(of: register) { return addressReference(atAddress: address) }
        if let slot = registers.slotAddress(of: register) { return slotReference(fromSlot: slot) }
        return nil
    }

    /// The class object, type metadata or metadata accessor at the unslid
    /// `address`. Most addresses code builds lie in its own image outside
    /// these — strings, selectors, constants — and are turned away before any
    /// lookup.
    private mutating func addressReference(atAddress address: UInt64) -> AddressReference? {
        let isCode = address >= table.textStart && address < table.textEnd
        if !isCode, !table.dataSegmentRanges.contains(where: { $0.contains(address) }), table.segmentRanges.contains(where: { $0.contains(address) }) { return nil }
        if let known = addressReferences[address] { return known }
        let runtimeAddress = runtimeAddress(ofUnslid: address, slide: table.slide)
        let addressReference = isCode ? accessorReference(atRuntimeAddress: runtimeAddress) : self.addressReference(atRuntimeAddress: runtimeAddress)
        addressReferences[address] = addressReference
        return addressReference
    }

    /// What a load from the slot at the unslid `slot` yields. Only a slot of
    /// this image's GOT or class references counts, or one of the GOT pool the
    /// shared cache keeps outside every image: a constant string's `isa` also
    /// points at a class, and is no reference to it.
    private mutating func slotReference(fromSlot slot: UInt64) -> AddressReference? {
        let isOwnReferenceSlot = table.referenceSlotRanges.contains { $0.contains(slot) }
        // Any other slot of the image's own holds no reference.
        if !isOwnReferenceSlot, table.segmentRanges.contains(where: { $0.contains(slot) }) { return nil }
        if let known = slotReferences[slot] { return known }
        var slotReference: AddressReference?
        let runtimeSlot = runtimeAddress(ofUnslid: slot, slide: table.slide)
        let isReferenceSlot = isOwnReferenceSlot
            || (analyzer.imageIndex(containingDataAddress: runtimeSlot) == nil
                && analyzer.imageIndex(containingRuntimeAddress: runtimeSlot) == nil
                && analyzer.isMapped(runtimeAddress: runtimeSlot, length: 8))
        if isReferenceSlot, let pointer = UnsafeRawPointer(bitPattern: runtimeSlot) {
            let value = StoredPointer.address(in: pointer.loadUnaligned(as: UInt64.self))
            slotReference = addressReference(atRuntimeAddress: value) ?? accessorReference(atRuntimeAddress: value)
        }
        slotReferences[slot] = slotReference
        return slotReference
    }

    /// A class object, or the metadata of a struct, an enum or an imported
    /// type, at the runtime `address`. A Swift class's metadata is its
    /// Objective-C class object.
    private mutating func addressReference(atRuntimeAddress address: UInt) -> AddressReference? {
        if let classObject = classObject(atRuntimeAddress: address) { return .objectiveCClass(classObject) }
        if let descriptor = valueMetadataDescriptor(atRuntimeAddress: address) { return .swiftType(descriptor) }
        return nil
    }

    /// The class a slot at the runtime `slot` points at.
    private mutating func classObject(storedAt runtimeSlot: UInt) -> ObjectiveCClassObject? {
        guard let pointer = UnsafeRawPointer(bitPattern: runtimeSlot) else { return nil }
        return classObject(atRuntimeAddress: StoredPointer.address(in: pointer.loadUnaligned(as: UInt64.self)))
    }

    private func classObject(atRuntimeAddress address: UInt) -> ObjectiveCClassObject? {
        guard let imageIndex = analyzer.imageIndex(containingDataAddress: address) else { return nil }
        return indexes.classIndex(ofImageAt: imageIndex).classObject(atRuntimeAddress: address)
    }

    /// The type whose metadata accessor starts at the runtime `address`.
    private mutating func accessorReference(atRuntimeAddress address: UInt) -> AddressReference? {
        guard let imageIndex = analyzer.imageIndex(containingRuntimeAddress: address) else { return nil }
        return swiftTypeIndex(ofImageAt: imageIndex).descriptorLocation(ofAccessorAt: address).map { .swiftType($0) }
    }

    /// The descriptor of the type whose metadata lies at the runtime
    /// `address`: a struct, an enum, an optional or an imported type, whose
    /// metadata holds its kind first and its descriptor next.
    private mutating func valueMetadataDescriptor(atRuntimeAddress address: UInt) -> CodeLocation? {
        guard analyzer.isMapped(runtimeAddress: address, length: 16), let metadata = UnsafeRawPointer(bitPattern: address) else { return nil }
        // MetadataKind: struct 0x200, enum 0x201, optional 0x202, foreign
        // class 0x203, foreign reference type 0x204.
        let kind = metadata.loadUnaligned(as: UInt64.self)
        guard kind >= 0x200, kind <= 0x204 else { return nil }
        let descriptor = StoredPointer.address(in: metadata.loadUnaligned(fromByteOffset: 8, as: UInt64.self))
        guard let imageIndex = analyzer.imageIndex(containingRuntimeAddress: descriptor) else { return nil }
        let index = swiftTypeIndex(ofImageAt: imageIndex)
        return index.describesType(descriptorAt: descriptor) ? index.location(ofRuntimeAddress: descriptor) : nil
    }

    private func swiftTypeIndex(ofImageAt imageIndex: Int) -> SwiftTypeIndex {
        indexes.swiftTypeIndex(ofImageAt: imageIndex)
    }

    /// The type reference a call makes besides the call itself: to the type
    /// whose metadata accessor it calls, or to the types the mangled name it
    /// instantiates names.
    private mutating func typeReferenceOfCalledFunction(at instructionAddress: UInt64, in function: CodeLocation) -> CodeReference? {
        guard let typeFunction = calledTypeFunction else { return nil }
        let target: CodeReferenceTarget
        switch typeFunction {
        case .accessor(let descriptor):
            target = .swiftType(descriptor: descriptor)
        case .accessorSymbol(let symbol):
            target = .swiftTypeName(.accessorSymbol(symbol))
        case .instantiationHelper(let takesRecord):
            guard let name = takesRecord ? mangledNameInRecord(inRegister: 1) : mangledNameInCacheVariable(inRegister: 0) else { return nil }
            target = .swiftTypeName(name)
        case .runtimeEntry(let nameRegister):
            guard let name = mangledName(inRegister: nameRegister) else { return nil }
            target = .swiftTypeName(name)
        }
        return CodeReference(function: function, instructionAddress: instructionAddress, kind: .reference, target: target, isRuntimeHelperCall: false)
    }

    /// The longest mangled name read; a longer one is taken for something
    /// else.
    private static let maximumMangledNameLength = 4096

    /// `__swift_instantiateConcreteTypeFromMangledNameV2`'s second argument:
    /// `{ int32 offset from the record to the name, int32 length }`.
    private func mangledNameInRecord(inRegister register: Int) -> SwiftTypeName? {
        guard let record = registers.builtAddress(of: register) else { return nil }
        let runtimeRecord = runtimeAddress(ofUnslid: record, slide: table.slide)
        guard analyzer.isMapped(runtimeAddress: runtimeRecord, length: 8), let pointer = UnsafeRawPointer(bitPattern: runtimeRecord) else { return nil }
        let offset = pointer.loadUnaligned(as: Int32.self)
        let length = Int(pointer.loadUnaligned(fromByteOffset: 4, as: Int32.self))
        return mangledName(at: ARM64InstructionWord.adding(Int64(offset), to: record), length: length)
    }

    /// The first argument of the older helper: a cache variable that holds
    /// `{ int32 offset from the variable to the name, int32 negated length }`
    /// until the type is instantiated, and its metadata afterwards — then the
    /// name is gone, and nothing is reported.
    private func mangledNameInCacheVariable(inRegister register: Int) -> SwiftTypeName? {
        guard let cache = registers.builtAddress(of: register) else { return nil }
        let runtimeCache = runtimeAddress(ofUnslid: cache, slide: table.slide)
        guard analyzer.isMapped(runtimeAddress: runtimeCache, length: 8), let pointer = UnsafeRawPointer(bitPattern: runtimeCache) else { return nil }
        let value = pointer.loadUnaligned(as: Int64.self)
        guard value < 0 else { return nil }
        return mangledName(at: ARM64InstructionWord.adding(Int64(Int32(truncatingIfNeeded: value)), to: cache), length: -Int(Int32(truncatingIfNeeded: value >> 32)))
    }

    /// The name a runtime entry point is handed, which runs to its
    /// terminator: a symbolic reference's payload is skipped, since it may
    /// hold zero bytes.
    private func mangledName(inRegister register: Int) -> SwiftTypeName? {
        guard let name = registers.builtAddress(of: register) else { return nil }
        let runtimeName = runtimeAddress(ofUnslid: name, slide: table.slide)
        let readableLength = Int(min(analyzer.mappedLength(fromRuntimeAddress: runtimeName), UInt(Self.maximumMangledNameLength)))
        guard readableLength > 0, let bytes = UnsafePointer<UInt8>(bitPattern: runtimeName) else { return nil }
        var length = 0
        while length < readableLength {
            let byte = bytes[length]
            if byte == 0 { return mangledName(at: name, length: length) }
            length += byte >= 0x01 && byte <= 0x17 ? 5 : (byte >= 0x18 && byte <= 0x1F ? 9 : 1)
        }
        return nil
    }

    private func mangledName(at name: UInt64, length: Int) -> SwiftTypeName? {
        guard length > 0, length <= Self.maximumMangledNameLength,
              analyzer.isMapped(runtimeAddress: runtimeAddress(ofUnslid: name, slide: table.slide), length: UInt(length))
        else { return nil }
        return .mangledName(location: CodeLocation(imageIndex: table.imageIndex, address: name), length: length)
    }

    /// `_$s…Ma` without its leading underscore, for a metadata accessor's
    /// symbol.
    private static func accessorSymbol(_ name: UnsafePointer<CChar>) -> String? {
        guard name[0] == 0x5F, name[1] == 0x24, name[2] == 0x73 else { return nil }
        let length = strlen(name)
        guard length > 5, name[length - 2] == 0x4D, name[length - 1] == 0x61 else { return nil }
        return String(cString: name + 1)
    }

    /// The class a super send in the current function starts above: the one
    /// its `__objc_superrefs` slot holds — a category method's class too —
    /// or, when no such load was seen, the class its symbol names.
    private func superclassSendClassName() -> String? {
        superclassReferenceClassName ?? table.primaryName(ofFunctionAt: currentFunctionIndex).flatMap(Self.className(ofMethodSymbol:))
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

    /// What calling a function stands for besides the call.
    private enum TypeFunction {
        /// A type's metadata accessor: the type's descriptor.
        case accessor(descriptor: CodeLocation)
        /// A metadata accessor no descriptor stands for: its symbol, without
        /// the leading underscore.
        case accessorSymbol(String)
        /// `__swift_instantiateConcreteTypeFromMangledName…`: the V2 helpers
        /// take the name's `{ offset, length }` record in `x1`, the older ones
        /// a cache variable in `x0`.
        case instantiationHelper(takesRecord: Bool)
        /// `swift_getTypeByMangledName…`: the name in this register.
        case runtimeEntry(nameRegister: Int)
    }

    private struct FunctionTarget {
        let location: CodeLocation
        var isRuntimeHelper = false
        var messageSendKind: MessageSendKind?
        /// `swift_getInitializedObjCClass`; `objc_opt_self` and
        /// `objc_opt_class` resolve as the entry points they are.
        var returnsItsClassArgument = false
        var typeFunction: TypeFunction?
    }

    private enum ResolvedTarget {
        case function(FunctionTarget)
        /// A stub that names its selector.
        case selector(UnsafePointer<CChar>)
        /// A libobjc entry point that stands for these sends, the first to
        /// the receiver in `x0`; `returnsItsClassArgument` as for
        /// `FunctionTarget`.
        case entryPoint(selectors: [String], returnsItsClassArgument: Bool)
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

    /// `detectsTypeFunctions`: whether to tell metadata accessors and
    /// mangled-name helpers apart, which looks into the helper candidates'
    /// own calls — not while looking into one.
    private func computeResolution(of target: UInt64, detectsTypeFunctions: Bool = true) -> ResolvedTarget {
        if let range = table.objectiveCStubRange, range.contains(target) {
            guard let selector = table.objectiveCStubSelectors[target] else { return .unrecognized }
            return .selector(selector)
        }
        if let stub = table.symbolStubs[target] {
            // dyld binds every slot when it loads the image, lazy pointers
            // included (macOS 27.2, `LazyBindingTests`), so the slot is read
            // as it stands.
            if let slotAddress = stub.slotAddress,
               let resolved = resolveSlot(atRuntimeAddress: runtimeAddress(ofUnslid: slotAddress, slide: table.slide), hops: 0, detectsTypeFunctions: detectsTypeFunctions) {
                return resolved
            }
            if let name = stub.name {
                if let selectors = MessageSendEntryPoints.selectors(ofSymbol: name) {
                    return .entryPoint(selectors: selectors, returnsItsClassArgument: CrossReferenceAnalyzer.returnsItsClassArgument(name))
                }
                return .importedSymbol(name)
            }
            return .unrecognized
        }
        if target >= table.textStart, target < table.textEnd {
            return functionTarget(CodeLocation(imageIndex: table.imageIndex, address: target), detectsTypeFunctions: detectsTypeFunctions)
        }
        return resolve(runtimeAddress: runtimeAddress(ofUnslid: target, slide: table.slide), hops: 0, detectsTypeFunctions: detectsTypeFunctions)
    }

    private func resolve(runtimeAddress address: UInt, hops: Int, detectsTypeFunctions: Bool) -> ResolvedTarget {
        if let location = analyzer.location(ofRuntimeAddress: address) {
            return functionTarget(location, detectsTypeFunctions: detectsTypeFunctions)
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
            return resolveSlot(atRuntimeAddress: UInt(slotAddress), hops: hops + 1, detectsTypeFunctions: detectsTypeFunctions) ?? .unrecognized
        case .computed(let computedTarget):
            return resolve(runtimeAddress: UInt(computedTarget), hops: hops + 1, detectsTypeFunctions: detectsTypeFunctions)
        }
    }

    /// Follows the pointer a GOT slot holds — dyld or the cache builder bound
    /// it already.
    private func resolveSlot(atRuntimeAddress slotAddress: UInt, hops: Int, detectsTypeFunctions: Bool) -> ResolvedTarget? {
        guard analyzer.isMapped(runtimeAddress: slotAddress, length: 8),
              let slot = UnsafeRawPointer(bitPattern: slotAddress)
        else { return nil }
        let target = StoredPointer.address(in: slot.loadUnaligned(as: UInt64.self))
        guard target != 0 else { return nil }
        return resolve(runtimeAddress: target, hops: hops, detectsTypeFunctions: detectsTypeFunctions)
    }

    private func functionTarget(_ location: CodeLocation, detectsTypeFunctions: Bool) -> ResolvedTarget {
        var functionTarget = FunctionTarget(location: location)
        if analyzer.messageSendLocations.contains(location) {
            functionTarget.messageSendKind = .classic
            return .function(functionTarget)
        }
        if analyzer.superMessageSendLocations.contains(location) {
            functionTarget.messageSendKind = .superclass
            return .function(functionTarget)
        }
        if let selectors = analyzer.messageSendEntryPoints[location] {
            return .entryPoint(selectors: selectors, returnsItsClassArgument: analyzer.classReturningFunctionLocations.contains(location))
        }
        functionTarget.isRuntimeHelper = analyzer.runtimeHelperLocations.contains(location)
            || (location.imageIndex == table.imageIndex && table.runtimeHelperStarts.contains(location.address))
        functionTarget.returnsItsClassArgument = analyzer.classReturningFunctionLocations.contains(location)
        if detectsTypeFunctions { functionTarget.typeFunction = typeFunction(at: location) }
        return .function(functionTarget)
    }

    /// What a function stands for besides a call: a type's metadata
    /// accessor — by its descriptor, or by its symbol when no descriptor
    /// stands for it — a mangled-name instantiation helper, or one of the
    /// runtime's entry points that instantiate a type from its mangled name.
    private func typeFunction(at location: CodeLocation) -> TypeFunction? {
        guard findsTypeReferences else { return nil }
        if let nameRegister = analyzer.typeByMangledNameEntries[location] { return .runtimeEntry(nameRegister: nameRegister) }
        if let slide = analyzer.images[location.imageIndex].vmaddrSlide,
           let descriptor = swiftTypeIndex(ofImageAt: location.imageIndex).descriptorLocation(ofAccessorAt: runtimeAddress(ofUnslid: location.address, slide: slide)) {
            return .accessor(descriptor: descriptor)
        }
        // Accessors of generic instances and mangled-name helpers are emitted
        // into each image that uses them.
        guard location.imageIndex == table.imageIndex,
              let functionIndex = table.functionIndex(containing: location.address),
              table.starts[functionIndex] == location.address
        else { return nil }
        if let name = table.primaryName(ofFunctionAt: functionIndex) {
            if let accessorSymbol = Self.accessorSymbol(name) { return .accessorSymbol(accessorSymbol) }
            guard strstr(name, "instantiateConcreteTypeFromMangledName") != nil else { return nil }
            let length = strlen(name)
            return .instantiationHelper(takesRecord: length > 2 && name[length - 2] == 0x56 && name[length - 1] == 0x32)
        }
        return instantiationHelperByShape(ofFunctionAt: functionIndex)
    }

    /// A mangled-name helper without a symbol, told by what it does: a short
    /// function that calls the runtime's `swift_getTypeByMangledName…`. The V2
    /// helpers read their record through `x1` (`ldr x9, [x1]`); the older
    /// ones take nothing in `x1`.
    private func instantiationHelperByShape(ofFunctionAt functionIndex: Int) -> TypeFunction? {
        let start = table.starts[functionIndex]
        let end = table.end(ofFunctionAt: functionIndex)
        guard end > start, end - start <= 0x90 else { return nil }
        let words = table.instructionPointer(at: start)
        var readsRecord = false
        var callsRuntime = false
        for instructionIndex in 0 ..< Int((end - start) / 4) {
            let instructionAddress = start &+ UInt64(instructionIndex * 4)
            let word = UInt32(littleEndian: words[instructionIndex])
            if let load = ARM64InstructionWord.load(word), load.base == 1, load.displacement == 0 {
                readsRecord = true
            } else if let callee = ARM64InstructionWord.callTarget(word, at: instructionAddress) ?? ARM64InstructionWord.branchTarget(word, at: instructionAddress),
                      callee < start || callee >= end,
                      case .function(let calleeTarget) = computeResolution(of: callee, detectsTypeFunctions: false),
                      analyzer.typeByMangledNameEntries[calleeTarget.location] != nil {
                callsRuntime = true
            }
        }
        return callsRuntime ? .instantiationHelper(takesRecord: readsRecord) : nil
    }

    private func runtimeAddress(ofUnslid address: UInt64, slide: Int) -> UInt {
        UInt(bitPattern: Int(bitPattern: UInt(address)) &+ slide)
    }
}

/// The class and Swift type indexes one scan has asked the analyzer for.
/// A scan runs on one thread, so the dictionaries need no lock.
private final class ScanIndexes {
    private let analyzer: CrossReferenceAnalyzer
    private var classIndexes: [Int: ObjectiveCClassIndex] = [:]
    private var swiftTypeIndexes: [Int: SwiftTypeIndex] = [:]

    init(analyzer: CrossReferenceAnalyzer) {
        self.analyzer = analyzer
    }

    func classIndex(ofImageAt imageIndex: Int) -> ObjectiveCClassIndex {
        if let index = classIndexes[imageIndex] { return index }
        let index = analyzer.objectiveCClassIndex(ofImageAt: imageIndex)
        classIndexes[imageIndex] = index
        return index
    }

    func swiftTypeIndex(ofImageAt imageIndex: Int) -> SwiftTypeIndex {
        if let index = swiftTypeIndexes[imageIndex] { return index }
        let index = analyzer.swiftTypeIndex(ofImageAt: imageIndex)
        swiftTypeIndexes[imageIndex] = index
        return index
    }
}
