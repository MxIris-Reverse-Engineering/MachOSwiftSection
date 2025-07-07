import Foundation
import Demangle

protocol InterfaceNodePrinter {
    mutating func write(_ content: String)

    mutating func printName(_ node: Node) -> Node?
}

extension InterfaceNodePrinter {
    mutating func printOptional(_ optional: Node?, prefix: String? = nil, suffix: String? = nil, asPrefixContext: Bool = false) -> Node? {
        guard let o = optional else { return nil }
        prefix.map { write($0) }
        let r = printName(o)
        suffix.map { write($0) }
        return r
    }

    mutating func printFirstChild(_ ofName: Node, prefix: String? = nil, suffix: String? = nil, asPrefixContext: Bool = false) {
        _ = printOptional(ofName.children.at(0), prefix: prefix, suffix: suffix)
    }

    mutating func printSequence<S>(_ names: S, prefix: String? = nil, suffix: String? = nil, separator: String? = nil) where S: Sequence, S.Element == Node {
        var isFirst = true
        prefix.map { write($0) }
        for c in names {
            if let s = separator, !isFirst {
                write(s)
            } else {
                isFirst = false
            }
            _ = printName(c)
        }
        suffix.map { write($0) }
    }

    mutating func printChildren(_ ofName: Node, prefix: String? = nil, suffix: String? = nil, separator: String? = nil) {
        printSequence(ofName.children, prefix: prefix, suffix: suffix, separator: separator)
    }
}
