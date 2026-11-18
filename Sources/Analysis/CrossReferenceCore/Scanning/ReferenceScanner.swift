import Foundation
import MachOKit
import ARM64InstructionDecoding

/// Decodes the functions of one image and records what they reference.
///
/// Only the instructions that call, branch out, or build an address are
/// decoded; every other instruction merely forgets what its destination
/// register held. Register tracking records only what is certain — an
/// address `adrp` / `add` built, a slot that address was loaded from, a tag
/// a session put on a register, a pointer-authentication constant — and
/// nothing is guessed.
///
/// The scanner knows no language. What a call, an address or a slot means
/// to Objective-C or Swift is the sessions' to say
/// (``CodeReferenceRecognitionSession``); the scanner records only what is
/// left: plain calls, imported symbols, indirect calls.
///
/// A scanner memoizes how each call target resolves, and which session
/// claimed each address and slot, so one scanner should serve a whole image.
package struct ReferenceScanner {
    private let images: CodeImageSet
    private let table: ImageFunctionTable
    private let sessions: [any CodeReferenceRecognitionSession]
    private let recording: any CodeReferenceRecording
    private let resolver: CallTargetResolver
    /// Whether register state follows the branches inside a function: a
    /// forward branch carries what the registers hold to its target, an
    /// instruction after an unconditional transfer starts from what the
    /// branches to it carried, and a loop header forgets the caller-saved
    /// registers. Off, the scan reads straight down, as the first batch did —
    /// only to measure what following them changes.
    package let followsBranches: Bool
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
    private var callPlans: [UInt64: CallPlan] = [:]
    /// Which session recorded a reference for each address and slot, or -1
    /// when none did: an image builds the same few hundred class and type
    /// addresses again and again, and most addresses it builds are no
    /// reference at all.
    private var addressClaims: [UInt64: Int8] = [:]
    private var slotClaims: [UInt64: Int8] = [:]
    /// The image's GOT and the sessions' reference slot ranges.
    private let referenceSlotRanges: [Range<UInt64>]
    /// The ranges sessions watch loads from, and the session watching each.
    private let watchedSlotRanges: [(range: Range<UInt64>, sessionIndex: Int)]
    /// Whether any session looks at the addresses code builds and the slots
    /// it loads from.
    private let looksForAddressReferences: Bool

    /// What a call target resolves to, and what each session makes of it —
    /// copied out for every call, so held in values that take no reference
    /// counting.
    private struct CallPlan {
        let target: ResolvedCallTarget
        /// By session; 0 for none.
        var roles = SIMD4<UInt32>(repeating: 0)
        /// The sessions, by bit, whose role may stand in for the call, and
        /// those whose role notes the call after it.
        var standInSessions: UInt8 = 0
        var notingSessions: UInt8 = 0
        var isRuntimeHelper = false

        mutating func add(_ role: CalleeRole, ofSessionAt sessionIndex: Int) {
            roles[sessionIndex] = role.code
            let bit = UInt8(1) << UInt8(sessionIndex)
            if role.mayStandIn { standInSessions |= bit }
            if role.notesCallMade { notingSessions |= bit }
            isRuntimeHelper = isRuntimeHelper || role.isRuntimeHelper
        }
    }

    /// The most sessions a scan takes: a plan holds their roles inline.
    package static let maximumSessionCount = 4

    package init(
        images: CodeImageSet,
        table: ImageFunctionTable,
        sessions: [any CodeReferenceRecognitionSession],
        recording: any CodeReferenceRecording,
        followsBranches: Bool = true
    ) {
        precondition(sessions.count <= Self.maximumSessionCount, "a plan holds at most \(Self.maximumSessionCount) sessions' roles")
        self.images = images
        self.table = table
        self.sessions = sessions
        self.recording = recording
        self.resolver = CallTargetResolver(images: images, table: table)
        self.followsBranches = followsBranches
        self.referenceSlotRanges = table.globalOffsetTableRanges + sessions.flatMap(\.referenceSlotRanges)
        self.watchedSlotRanges = sessions.enumerated().flatMap { sessionIndex, session in
            session.watchedSlotRanges.map { (range: $0, sessionIndex: sessionIndex) }
        }
        self.looksForAddressReferences = sessions.contains { $0.looksForAddressReferences }
    }

    // MARK: - Scanning

    package mutating func scanFunction(at index: Int) {
        let start = table.starts[index]
        let end = table.end(ofFunctionAt: index)
        guard end > start else { return }
        let function = CodeLocation(imageIndex: table.imageIndex, address: start)
        let instructionCount = Int((end - start) / 4)
        guard let words = table.instructionPointer(at: start, count: instructionCount) else { return }

        registers.reset()
        for session in sessions {
            session.enterFunction(at: index, registers: registers)
        }

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
                let keptRegisters = noteCall(to: target, at: ScanSite(function: function, instructionAddress: instructionAddress, kind: .call))
                registers.clobberCallerSavedRegisters(keepingMask: keptRegisters)
            } else if let target = ARM64InstructionWord.branchTarget(word, at: instructionAddress) {
                previousInstructionTransfers = true
                if target < start || target >= end {
                    _ = noteCall(to: target, at: ScanSite(function: function, instructionAddress: instructionAddress, kind: .tailCall))
                } else if target > instructionAddress {
                    carry(to: target)
                }
            } else if let materialization = ARM64InstructionWord.addressMaterialization(word, at: instructionAddress) {
                registers.setAddress(materialization.address, of: materialization.destination)
                // `adr` builds the whole address an `adrp` / `add` pair builds
                // — what ld64 makes of such a pair within a megabyte.
                if !materialization.isPageAddress, looksForAddressReferences, let address = registers.builtAddress(of: materialization.destination) {
                    noteAddress(address, at: ScanSite(function: function, instructionAddress: instructionAddress, kind: .reference))
                }
            } else if let arithmetic = ARM64InstructionWord.addImmediate(word) {
                registers.add(arithmetic.addend, to: arithmetic.source, into: arithmetic.destination)
                if looksForAddressReferences, let address = registers.builtAddress(of: arithmetic.destination) {
                    noteAddress(address, at: ScanSite(function: function, instructionAddress: instructionAddress, kind: .reference))
                }
            } else if let load = ARM64InstructionWord.load(word) {
                let slot = registers.builtAddress(of: load.base).map { ARM64InstructionWord.adding(load.displacement, to: $0) }
                registers.load(into: load.destination, base: load.base, displacement: load.displacement, writesBack: load.writesBack)
                if let slot { noteLoad(fromSlot: slot, into: load.destination, at: ScanSite(function: function, instructionAddress: instructionAddress, kind: .reference)) }
            } else if let literal = ARM64InstructionWord.loadLiteral(word, at: instructionAddress) {
                // What ld64 makes of an `adrp` / `ldr` pair whose slot lies
                // within a megabyte: the selector reference a send passes in
                // `x1`, a class reference, a GOT slot.
                registers.load(into: literal.destination, fromSlotAt: literal.slotAddress)
                noteLoad(fromSlot: literal.slotAddress, into: literal.destination, at: ScanSite(function: function, instructionAddress: instructionAddress, kind: .reference))
            } else if let move = ARM64InstructionWord.moveRegister(word) {
                registers.copy(move.source, to: move.destination)
            } else if let wide = ARM64InstructionWord.moveWide(word) {
                registers.moveWide(into: wide.destination, immediate: wide.immediate, shift: wide.shift, keepsOtherBits: wide.keepsOtherBits)
            } else if let branch = ARM64InstructionWord.registerBranch(word) {
                if branch.isCall {
                    recordIndirectCall(through: branch, at: ScanSite(function: function, instructionAddress: instructionAddress, kind: .call))
                    registers.clobberCallerSavedRegisters()
                } else {
                    previousInstructionTransfers = true
                    // A computed `br` is a jump table; a pointer loaded from
                    // memory, or an authenticated one, is a tail call.
                    if branch.isAuthenticated || registers.wasLoadedFromMemory(branch.target) {
                        recordIndirectCall(through: branch, at: ScanSite(function: function, instructionAddress: instructionAddress, kind: .tailCall))
                    }
                }
            } else if let target = ARM64InstructionWord.conditionalBranchTarget(word, at: instructionAddress) {
                if target < start || target >= end {
                    _ = noteCall(to: target, at: ScanSite(function: function, instructionAddress: instructionAddress, kind: .tailCall))
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

    /// The references a call, or a branch out of the function, makes: what a
    /// session records in its place — or the plain call — then what the
    /// sessions record besides. Returns the caller-saved registers that keep
    /// their contents across it, by bit.
    private mutating func noteCall(to target: UInt64, at site: ScanSite) -> UInt32 {
        let plan = plan(for: target)
        var stoodIn = false
        var remaining = plan.standInSessions
        while remaining != 0 {
            let sessionIndex = remaining.trailingZeroBitCount
            remaining &= remaining - 1
            let call = ScannedCall(site: site, targetAddress: target, target: plan.target, role: plan.roles[sessionIndex])
            if sessions[sessionIndex].recordCallStandIn(call, registers: registers) {
                stoodIn = true
                break
            }
        }
        if !stoodIn {
            recording.recordCall(to: plan.target, targetAddress: target, at: site, isRuntimeHelperCall: plan.isRuntimeHelper)
        }
        var keptRegisters: UInt32 = 0
        remaining = plan.notingSessions
        while remaining != 0 {
            let sessionIndex = remaining.trailingZeroBitCount
            remaining &= remaining - 1
            let call = ScannedCall(site: site, targetAddress: target, target: plan.target, role: plan.roles[sessionIndex])
            keptRegisters |= sessions[sessionIndex].noteCallMade(call, registers: registers)
        }
        return keptRegisters
    }

    /// What a load from the slot at the unslid `slot` tells besides what the
    /// register now holds: what a session watching the slot makes of it, or
    /// a reference the slot holds.
    private mutating func noteLoad(fromSlot slot: UInt64, into destination: Int, at site: ScanSite) {
        guard destination != ARM64InstructionWord.zeroOrStackPointerRegister else { return }
        for watched in watchedSlotRanges where watched.range.contains(slot) {
            sessions[watched.sessionIndex].noteWatchedSlotLoad(from: slot)
            return
        }
        if looksForAddressReferences {
            noteSlotReference(fromSlot: slot, at: site)
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

    private func recordIndirectCall(through branch: ARM64InstructionWord.RegisterBranch, at site: ScanSite) {
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
        recording.recordIndirectCall(evidence, at: site)
    }

    /// The address at the unslid `address` an instruction built. Most
    /// addresses code builds lie in its own image outside its code and data —
    /// strings, selectors, constants — and are turned away before any
    /// session is asked.
    private mutating func noteAddress(_ address: UInt64, at site: ScanSite) {
        let isCode = address >= table.textStart && address < table.textEnd
        if !isCode, !table.dataSegmentRanges.contains(where: { $0.contains(address) }), table.segmentRanges.contains(where: { $0.contains(address) }) { return }
        let runtimeAddress = table.runtimeAddress(ofUnslid: address)
        if let claim = addressClaims[address] {
            if claim >= 0 { _ = sessions[Int(claim)].recordAddressReference(toRuntimeAddress: runtimeAddress, isCode: isCode, at: site) }
            return
        }
        var claim: Int8 = -1
        for sessionIndex in sessions.indices where sessions[sessionIndex].looksForAddressReferences {
            if sessions[sessionIndex].recordAddressReference(toRuntimeAddress: runtimeAddress, isCode: isCode, at: site) {
                claim = Int8(sessionIndex)
                break
            }
        }
        addressClaims[address] = claim
    }

    /// A load from the slot at the unslid `slot`. Only a slot of this image's
    /// GOT or of a session's reference sections counts, or one of the GOT
    /// pool the shared cache keeps outside every image: a constant string's
    /// `isa` also points at a class, and is no reference to it.
    private mutating func noteSlotReference(fromSlot slot: UInt64, at site: ScanSite) {
        // Most loads through an `adrp` read the image's own data, which holds
        // no reference: turned away before anything is looked up.
        let isOwnReferenceSlot = referenceSlotRanges.contains { $0.contains(slot) }
        if !isOwnReferenceSlot, table.segmentRanges.contains(where: { $0.contains(slot) }) { return }
        if let claim = slotClaims[slot] {
            if claim >= 0, let value = slotValue(atUnslid: slot, isOwnReferenceSlot: isOwnReferenceSlot) {
                _ = sessions[Int(claim)].recordSlotReference(holding: value, at: site)
            }
            return
        }
        var claim: Int8 = -1
        if let value = slotValue(atUnslid: slot, isOwnReferenceSlot: isOwnReferenceSlot) {
            for sessionIndex in sessions.indices where sessions[sessionIndex].looksForAddressReferences {
                if sessions[sessionIndex].recordSlotReference(holding: value, at: site) {
                    claim = Int8(sessionIndex)
                    break
                }
            }
        }
        slotClaims[slot] = claim
    }

    /// What the slot at the unslid `slot` holds, when it is a reference slot:
    /// one of the image's own, or one of the shared cache's GOT pool.
    private func slotValue(atUnslid slot: UInt64, isOwnReferenceSlot: Bool) -> UInt? {
        let runtimeSlot = table.runtimeAddress(ofUnslid: slot)
        guard isOwnReferenceSlot || images.isSlotOutsideEveryImage(runtimeAddress: runtimeSlot), runtimeSlot != 0 else { return nil }
        return images.memory.pointer(at: runtimeSlot)
    }

    // MARK: - Resolving call targets

    /// Where an unslid address in this image's address space leads, and
    /// what each session makes of it.
    private mutating func plan(for target: UInt64) -> CallPlan {
        if let known = callPlans[target] { return known }
        let plan = makePlan(for: target)
        callPlans[target] = plan
        return plan
    }

    private func makePlan(for target: UInt64) -> CallPlan {
        for (sessionIndex, session) in sessions.enumerated() {
            guard let claim = session.claimCallTarget(at: target) else { continue }
            var plan = CallPlan(target: .unrecognized)
            if case .role(let role) = claim {
                plan.add(role, ofSessionAt: sessionIndex)
            }
            return plan
        }
        let resolved = resolver.resolve(target)
        var plan = CallPlan(target: resolved)
        plan.isRuntimeHelper = resolver.isRuntimeHelper(resolved)
        for (sessionIndex, session) in sessions.enumerated() {
            guard let role = session.role(of: resolved) else { continue }
            plan.add(role, ofSessionAt: sessionIndex)
        }
        return plan
    }
}

/// Resolves a call target through stubs, GOT slots and stub islands to the
/// function it reaches — what the core can tell without any language. A
/// value, so that a session can resolve the targets a helper function calls
/// as the scan does.
package struct CallTargetResolver {
    package let images: CodeImageSet
    package let table: ImageFunctionTable

    /// How many stubs and islands are followed from one call before giving
    /// up; a hop per subcache crossed is the worst case described.
    private static let maximumTrampolineHops = 8

    package init(images: CodeImageSet, table: ImageFunctionTable) {
        self.images = images
        self.table = table
    }

    /// Where an unslid address in the table's image's address space leads.
    package func resolve(_ target: UInt64) -> ResolvedCallTarget {
        if let stub = table.symbolStubs[target] {
            // dyld binds every slot when it loads the image, lazy pointers
            // included (macOS 27.2, `LazyBindingTests`), so the slot is read
            // as it stands.
            if let slotAddress = stub.slotAddress,
               let resolved = resolveSlot(atRuntimeAddress: table.runtimeAddress(ofUnslid: slotAddress), hops: 0) {
                return resolved
            }
            if let name = stub.name { return .importedSymbol(name) }
            return .unrecognized
        }
        if target >= table.textStart, target < table.textEnd {
            return .function(CodeLocation(imageIndex: table.imageIndex, address: target))
        }
        return resolve(runtimeAddress: table.runtimeAddress(ofUnslid: target), hops: 0)
    }

    /// Whether the core counts calls to `target` as runtime helper calls: an
    /// imported symbol or a function named as one, or a runtime library's
    /// helper.
    package func isRuntimeHelper(_ target: ResolvedCallTarget) -> Bool {
        switch target {
        case .function(let location):
            return images.runtimeHelperLocations.contains(location)
                || (location.imageIndex == table.imageIndex && table.runtimeHelperStarts.contains(location.address))
        case .importedSymbol(let name):
            return images.isRuntimeHelperName(name)
        case .registerSettingTrampoline, .unrecognized:
            return false
        }
    }

    private func resolve(runtimeAddress address: UInt, hops: Int) -> ResolvedCallTarget {
        if let location = images.location(ofRuntimeAddress: address) {
            return .function(location)
        }
        // Between images: a stub or island the cache builder put there.
        guard hops < Self.maximumTrampolineHops,
              address != 0,
              images.isExecutable(runtimeAddress: address, length: UInt(ARM64Trampoline.maximumInstructionCount * 4)),
              let pointer = images.memory.bytes(at: address, length: ARM64Trampoline.maximumInstructionCount * 4)?.baseAddress,
              let trampoline = ARM64Trampoline(readingAt: pointer, address: UInt64(address))
        else { return .unrecognized }
        switch trampoline {
        case .selectorStub(let constant, _):
            return .registerSettingTrampoline(register: 1, value: constant)
        case .slotLoad(let slotAddress):
            return resolveSlot(atRuntimeAddress: UInt(slotAddress), hops: hops + 1) ?? .unrecognized
        case .computed(let computedTarget):
            return resolve(runtimeAddress: UInt(computedTarget), hops: hops + 1)
        }
    }

    /// Follows the pointer a GOT slot holds — dyld or the cache builder bound
    /// it already.
    private func resolveSlot(atRuntimeAddress slotAddress: UInt, hops: Int) -> ResolvedCallTarget? {
        guard slotAddress != 0, images.isMapped(runtimeAddress: slotAddress, length: 8),
              let target = images.memory.pointer(at: slotAddress), target != 0
        else { return nil }
        return resolve(runtimeAddress: target, hops: hops)
    }
}
