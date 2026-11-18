/// Where one referencing instruction lies, and what kind of reference it
/// makes.
package struct ScanSite: Sendable {
    /// The first instruction of the function the instruction belongs to.
    package let function: CodeLocation
    /// The instruction's unslid address, in the same image as `function`.
    package let instructionAddress: UInt64
    package let kind: CodeReferenceKind

    package init(function: CodeLocation, instructionAddress: UInt64, kind: CodeReferenceKind) {
        self.function = function
        self.instructionAddress = instructionAddress
        self.kind = kind
    }
}

/// Where a call, or a branch out of a function, leads, as far as the core
/// can tell without knowing any language: through the image's own stubs,
/// its GOT, the stub islands and the stubs the shared cache keeps between
/// images.
package enum ResolvedCallTarget: Hashable, @unchecked Sendable {
    /// A function in some image.
    case function(CodeLocation)
    /// A stub whose slot could not be followed: the name its indirect symbol
    /// entry carries, pointing into the image's string table.
    case importedSymbol(UnsafePointer<CChar>)
    /// A trampoline that puts a constant in a register before it branches
    /// on: macOS / iOS 27's cache-shared selector stubs set `x1`. Where it
    /// branches to is not followed.
    case registerSettingTrampoline(register: Int, value: UInt64)
    /// Code that lies in no image and in no recognized trampoline — or data
    /// in `__text` that decoded as a branch.
    case unrecognized
}

/// What a recognizer makes of a call target only it knows how to read: an
/// address in a section of its own, such as `__objc_stubs`.
package enum CallTargetClaim: Sendable {
    /// The target is the recognizer's, and this is the role it notes the
    /// call with (see ``CodeReferenceRecognitionSession/role(of:)``).
    case role(CalleeRole)
    /// The target lies in the recognizer's section but cannot be read: the
    /// call is reported as leading nowhere known.
    case unrecognized
}

/// What a recognizer makes of a call target the core resolved.
package struct CalleeRole: Sendable {
    /// What the recognizer notes the call with — its own code, never 0.
    package let code: UInt32
    /// Whether the session may record what a call stands for in place of the
    /// plain call (``CodeReferenceRecognitionSession/recordCallStandIn(_:registers:)``).
    package let mayStandIn: Bool
    /// Whether the session records something after the call's own reference
    /// or keeps a register across it
    /// (``CodeReferenceRecognitionSession/noteCallMade(_:registers:)``).
    package let notesCallMade: Bool
    /// Whether the callee only manages memory or values: a retain, an
    /// outlined copy.
    package let isRuntimeHelper: Bool

    /// Only the methods the role names are called: most calls with a role
    /// need one, and the scan pays for every call it makes.
    package init(code: UInt32, mayStandIn: Bool, notesCallMade: Bool, isRuntimeHelper: Bool = false) {
        precondition(code != 0, "role 0 means no role")
        self.code = code
        self.mayStandIn = mayStandIn
        self.notesCallMade = notesCallMade
        self.isRuntimeHelper = isRuntimeHelper
    }
}

/// One call or branch out of the function, as the core resolved it.
package struct ScannedCall {
    package let site: ScanSite
    /// The branch target the instruction encodes, unslid.
    package let targetAddress: UInt64
    package let target: ResolvedCallTarget
    /// The role the session gave the target, never 0.
    package let role: UInt32
}

/// One language's knowledge of what code references, plugged into the
/// core's scan. A recognizer is built once per analyzer and reads what it
/// needs from every image up front — the runtime functions it recognizes by
/// name — then makes a session for each scan of an image.
///
/// The core asks the sessions, in the order the host lists them, at five
/// moments of a scan: entering a function, resolving a call target only a
/// session can read, a call, an address built, and a load from a slot. A new
/// language is one more recognizer; the core does not change. Evolution
/// proposal `offline-cross-references-and-symbolication`.
package protocol CodeReferenceRecognitionSession: AnyObject {
    /// Address ranges, unslid, whose slots hold references the session
    /// reads besides the core's GOT: `__objc_classrefs`.
    var referenceSlotRanges: [Range<UInt64>] { get }

    /// Address ranges, unslid, a load from which the session watches on
    /// every load, whether or not it looks for references:
    /// `__objc_superrefs`, which says where a super send starts.
    var watchedSlotRanges: [Range<UInt64>] { get }

    /// Whether the session looks at the addresses code builds and the slots
    /// it loads from. A query for the callers of a function wants neither,
    /// and skipping them keeps it fast.
    var looksForAddressReferences: Bool { get }

    /// The function at index `functionIndex` of the scanned image's table
    /// starts; the session may tag registers — an Objective-C method's
    /// receiver arrives in `x0`.
    func enterFunction(at functionIndex: Int, registers: RegisterFile)

    /// A call target the core has not resolved yet, at the unslid `target`:
    /// answered when it lies in a section only this session reads.
    func claimCallTarget(at target: UInt64) -> CallTargetClaim?

    /// The role of a target the core resolved, or `nil` when the session
    /// has nothing to note about calls to it. Asked once for each distinct
    /// target of a scan.
    func role(of target: ResolvedCallTarget) -> CalleeRole?

    /// Records what a call stands for in place of the plain call reference —
    /// an Objective-C message send — and returns whether it did. The first
    /// session that does wins; the core records the plain call when none
    /// does.
    func recordCallStandIn(_ call: ScannedCall, registers: RegisterFile) -> Bool

    /// After the call's own reference: records what the call references
    /// besides — the type a metadata accessor stands for — and returns the
    /// caller-saved registers that keep their contents across the call, by
    /// bit (`objc_opt_self` returns what `x0` held).
    func noteCallMade(_ call: ScannedCall, registers: RegisterFile) -> UInt32

    /// `adrp` / `add` or `adr` built an address, which lies at the runtime
    /// `address`; `isCode` when it lies in the scanned image's `__text`.
    /// Most addresses code builds in its own image — strings, constants —
    /// are turned away before any session is asked. Records a reference and
    /// returns whether it did; the first session that does wins, and is
    /// asked again for the same address.
    func recordAddressReference(toRuntimeAddress address: UInt, isCode: Bool, at site: ScanSite) -> Bool

    /// A load from a reference slot — the core's GOT, the shared cache's GOT
    /// pool, or one of `referenceSlotRanges` — that holds the runtime
    /// address `value`. Records a reference and returns whether it did.
    func recordSlotReference(holding value: UInt, at site: ScanSite) -> Bool

    /// A load from a slot in one of `watchedSlotRanges`.
    func noteWatchedSlotLoad(from slot: UInt64)
}

/// Where the references a scan finds go. The core records the ones it
/// recognizes itself; each language layer refines the protocol with the
/// references only it recognizes, and the host implements every refinement
/// it plugs a recognizer in for.
package protocol CodeReferenceRecording: AnyObject {
    /// A call to `target`, which `targetAddress` encoded; no session stood
    /// in for it.
    func recordCall(to target: ResolvedCallTarget, targetAddress: UInt64, at site: ScanSite, isRuntimeHelperCall: Bool)
    func recordIndirectCall(_ evidence: IndirectCallEvidence, at site: ScanSite)
}
