import MachOSwiftSection

extension GenericRequirement {
    /// A protocol-signature requirement that represents an *inherited protocol*
    /// (i.e. the `: Inherited` clause of a `protocol` declaration), as opposed to
    /// a `where`-clause constraint. Detected by the `Self` parameter (`x`) paired
    /// with a protocol / layout / base-class requirement kind.
    package var isProtocolInherited: Bool {
        paramManagledName.rawString == "x" && (descriptor.flags.kind == .protocol || descriptor.flags.kind == .layout || descriptor.flags.kind == .baseClass)
    }
}

extension RangeReplaceableCollection {
    /// Removes and returns the elements that satisfy the given predicate.
    /// This method performs the filtering and removal in a single pass.
    ///
    /// - Parameter predicate: A closure that takes an element of the
    ///   sequence as its argument and returns a Boolean value indicating
    ///   whether the element should be extracted.
    /// - Returns: An array containing the elements that were removed from the collection.
    /// - Complexity: O(n), where n is the length of the collection.
    @discardableResult
    package mutating func extract(
        where predicate: (Element) throws -> Bool
    ) rethrows -> [Element] {
        var remainingElements = Self()
        var extractedElements: [Element] = []
        for element in self {
            if try predicate(element) {
                extractedElements.append(element)
            } else {
                remainingElements.append(element)
            }
        }
        self = remainingElements
        return extractedElements
    }
}
