package protocol NodePrinterTarget: Sendable {
    init()
    var count: Int { get }
    mutating func write(_ content: String)
    mutating func write(_ content: String, context: NodePrintContext)
}

extension NodePrinterTarget {
    package mutating func write(_ content: String, context: NodePrintContext) {
        write(content)
    }
}

extension String: NodePrinterTarget {}
