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
