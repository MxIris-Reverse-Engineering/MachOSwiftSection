/// Code the linker or the dyld cache builder put between a call and its
/// callee, recognized by its shape.
///
/// Three shapes exist:
///
/// - **A stub that loads its target from a GOT slot.** A standalone binary's
///   `__stubs` entry is `adrp x16, page` / `ldr x16, [x16, #offset]` /
///   `br x16`; an arm64e `__auth_stubs` entry, and the stubs a dyld cache
///   shares between all of its images (macOS 27, iOS 27), are `adrp x17,
///   page` / `add x17, x17, #offset` / `ldr x16, [x17]` / `braa x16, x17`.
/// - **A stub island**, which computes its target outright and loads
///   nothing: `adrp x16, page` / `add x16, x16, #offset` / `br x16`. The cache
///   builder places these between images when a `bl` cannot reach across the
///   cache's subcaches; islands may chain.
/// - **An Objective-C selector stub shared by the whole cache** (macOS 27,
///   iOS 27): `adrp x1, page` / `add x1, x1, #offset` / `b <objc_msgSend>`.
///   `x1` receives the selector string itself, so the stub names the message.
///   A cache carries one such stub per selector per subcache, so the selector
///   string's address — not the stub's — identifies the message.
///
/// The image's own `__objc_stubs` entries (`adrp x1` / `ldr x1, [x1, #selref]`
/// / `adrp x16` / `ldr x16, [x16, #objc_msgSend]` / `br x16`) are read through
/// MachOKit's `objcStubs(in:)`, not here.
package enum ARM64Trampoline: Equatable, Sendable {
    /// The trampoline loads its target from the slot at `slotAddress`.
    case slotLoad(slotAddress: UInt64)
    /// The trampoline jumps to `target`, which it computes without a load.
    case computed(target: UInt64)
    /// A shared selector stub: the selector string lies at
    /// `selectorAddress`, and the stub branches to `messageSendAddress`.
    case selectorStub(selectorAddress: UInt64, messageSendAddress: UInt64)

    /// How many instruction words the longest shape occupies.
    package static let maximumInstructionCount = 4

    /// Recognizes the trampoline whose first instructions are `words`,
    /// located at `address`. `words` may hold more instructions than the
    /// shape needs.
    package init?(words: some Collection<UInt32>, at address: UInt64) {
        let instructions = Array(words.prefix(Self.maximumInstructionCount))
        if instructions.count >= 3,
           let page = ARM64InstructionWord.addressMaterialization(instructions[0], at: address), page.destination == 1,
           let offset = ARM64InstructionWord.addImmediate(instructions[1]), offset.destination == 1, offset.source == 1,
           let messageSendAddress = ARM64InstructionWord.branchTarget(instructions[2], at: address &+ 8) {
            self = .selectorStub(
                selectorAddress: ARM64InstructionWord.adding(offset.addend, to: page.address),
                messageSendAddress: messageSendAddress
            )
            return
        }

        // A GOT stub or an island: address arithmetic, then a load or a jump
        // through the register the arithmetic produced.
        var registerValues: [Int: UInt64] = [:]
        for (index, word) in instructions.enumerated() {
            let instructionAddress = address &+ UInt64(index * 4)
            if let materialization = ARM64InstructionWord.addressMaterialization(word, at: instructionAddress) {
                registerValues[materialization.destination] = materialization.address
            } else if let arithmetic = ARM64InstructionWord.addImmediate(word) {
                guard let source = registerValues[arithmetic.source] else { return nil }
                registerValues[arithmetic.destination] = ARM64InstructionWord.adding(arithmetic.addend, to: source)
            } else if let load = ARM64InstructionWord.load(word) {
                guard !load.writesBack, let base = registerValues[load.base] else { return nil }
                self = .slotLoad(slotAddress: ARM64InstructionWord.adding(load.displacement, to: base))
                return
            } else if let branch = ARM64InstructionWord.registerBranch(word), !branch.isCall {
                guard let target = registerValues[branch.target] else { return nil }
                self = .computed(target: target)
                return
            } else if word != ARM64InstructionWord.noOperation {
                return nil
            }
        }
        return nil
    }

    /// Reads the trampoline at `pointer`, the location in memory of the
    /// code whose address is `address`.
    package init?(readingAt pointer: UnsafeRawPointer, address: UInt64) {
        var words: [UInt32] = []
        words.reserveCapacity(Self.maximumInstructionCount)
        for index in 0 ..< Self.maximumInstructionCount {
            words.append(UInt32(littleEndian: pointer.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self)))
        }
        self.init(words: words, at: address)
    }
}
