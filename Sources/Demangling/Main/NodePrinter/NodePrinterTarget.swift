package protocol NodePrinterTarget: Sendable {
    init()
    var count: Int { get }
    mutating func write(_ content: String)
    mutating func write(_ content: String, context: NodePrintContext?)
}

extension NodePrinterTarget {
    package mutating func write(_ content: String, context: NodePrintContext?) {
        write(content)
    }

    package mutating func writeSpace(_ count: Int = 1) {
        write(" ")
    }

    package mutating func writeBreakLine() {
        write("\n")
    }
}

extension String: NodePrinterTarget {}
