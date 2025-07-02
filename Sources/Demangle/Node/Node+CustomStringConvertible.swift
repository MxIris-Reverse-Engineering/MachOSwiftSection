extension Node: CustomStringConvertible {
    /// Overridden method to allow simple printing with default options
    public var description: String {
        var string = ""
        printNode(output: &string, node: self)
        return string
    }

    /// Prints `SwiftSymbol`s to a String with the full set of printing options.
    ///
    /// - Parameter options: an option set containing the different `DemangleOptions` from the Swift project.
    /// - Returns: `self` printed to a string according to the specified options.
    public func print(using options: DemangleOptions = .default) -> String {
        var printer = NodePrinter<String>(options: options)
        return printer.printRoot(self)
    }
    
    
    private func printNode(output: inout String, node: Node, depth: Int = 0) {
        (0..<(depth * 2)).forEach { _ in output.append(" ") }
        output.append("kind=\(node.kind)")
        switch node.contents {
        case .none:
            break
        case .index(let index):
            output.append(", index=\(index)")
        case .name(let name):
            output.append(", name=\(name)")
        }
        output.append("\n")
        for child in node.children {
            printNode(output: &output, node: child, depth: depth + 1)
        }
    }
}
