import Semantic

extension Node: CustomStringConvertible {
    /// Overridden method to allow simple printing with default options
    public var description: String {
        print()
    }

    /// Prints `SwiftSymbol`s to a String with the full set of printing options.
    ///
    /// - Parameter options: an option set containing the different `DemangleOptions` from the Swift project.
    /// - Returns: `self` printed to a string according to the specified options.
    public func print(using options: DemangleOptions = .default) -> String {
        printSemantic(using: options).string
    }

    public func printSemantic(using options: DemangleOptions = .default) -> SemanticString {
        var printer = NodePrinter(options: options)
        _ = printer.printName(self)
        return printer.target
    }
}
