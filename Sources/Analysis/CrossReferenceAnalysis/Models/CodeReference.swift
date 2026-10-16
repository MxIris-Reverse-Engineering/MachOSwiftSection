/// What an Objective-C send's receiver is known to be.
public enum ReceiverClassHint: Hashable, Sendable {
    /// The sending method's own receiver, still in `x0` where it arrived, or a
    /// copy of it.
    case methodReceiver
    /// Loaded from a class reference: `[NSWindow alloc]`.
    case classLiteral(String)
    case unknown
}

/// Evidence for where an indirect call may go.
public struct IndirectCallEvidence: Hashable, Sendable {
    /// The table the callee was loaded from.
    public enum Table: Hashable, Sendable {
        case classVirtualTable
        case protocolWitnessTable
        case valueWitnessTable
        /// A function value, or a table the analysis cannot identify.
        case none
    }

    public let table: Table
    /// The displacement of the load that produced the callee, when it came
    /// from memory.
    public let tableOffset: Int64?
    /// The 16-bit arm64e discriminator constant, when there is one.
    public let pointerAuthenticationConstant: UInt16?
    /// Whether the constant was blended into an address (`movk xN, #imm,
    /// lsl #48`) or used alone (`mov x17, #imm`).
    public let isAddressBlended: Bool

    public init(table: Table, tableOffset: Int64?, pointerAuthenticationConstant: UInt16?, isAddressBlended: Bool) {
        self.table = table
        self.tableOffset = tableOffset
        self.pointerAuthenticationConstant = pointerAuthenticationConstant
        self.isAddressBlended = isAddressBlended
    }
}

/// What one instruction references.
public enum CodeReferenceTarget: Hashable, Sendable {
    /// A function: in the same image, in another, or wherever a stub, a GOT
    /// slot or a stub island led.
    case function(CodeLocation)
    /// A stub whose slot could not be followed; the name its indirect symbol
    /// carries.
    case importedSymbol(name: String)
    /// An Objective-C message send whose selector is known.
    case messageSend(selector: String, receiver: ReceiverClassHint)
    /// A send through `objc_msgSendSuper2` whose selector is known.
    case superMessageSend(selector: String)
    /// A call to a Swift type metadata accessor (`$s…Ma`).
    case typeMetadataAccessor(symbolName: String)
    /// A type instantiated from its mangled name.
    case mangledTypeName(String)
    /// An Objective-C class reference.
    case objectiveCClass(name: String)
    case indirect(IndirectCallEvidence)
    /// Code that lies in no image and in no recognized trampoline — or data
    /// in `__text` that decoded as a branch.
    case unrecognized(address: UInt64)
}

/// One instruction's reference.
public struct CodeReference: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case call
        /// A branch out of the function that does not return to it.
        case tailCall
    }

    /// The first instruction of the function the referencing instruction
    /// belongs to.
    public let function: CodeLocation
    /// The referencing instruction's unslid address, in the same image as
    /// ``function``.
    public let instructionAddress: UInt64
    public let kind: Kind
    public let target: CodeReferenceTarget
    /// A retain or release, an outlined value operation or another runtime
    /// helper; the target says which function.
    public let isRuntimeHelperCall: Bool

    public init(function: CodeLocation, instructionAddress: UInt64, kind: Kind, target: CodeReferenceTarget, isRuntimeHelperCall: Bool) {
        self.function = function
        self.instructionAddress = instructionAddress
        self.kind = kind
        self.target = target
        self.isRuntimeHelperCall = isRuntimeHelperCall
    }
}
