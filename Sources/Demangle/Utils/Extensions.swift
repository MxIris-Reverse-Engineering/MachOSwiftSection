extension String {
    package var isSwiftSymbol: Bool {
        getManglingPrefixLength(unicodeScalars) > 0
    }
}

extension Array {
    package func at(_ index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }

    package func slice(_ from: Int, _ to: Int) -> ArraySlice<Element> {
        if from > to || from > endIndex || to < startIndex {
            return ArraySlice()
        } else {
            return self[(from > startIndex ? from : startIndex) ..< (to < endIndex ? to : endIndex)]
        }
    }
}

/// NOTE: This extension is fileprivate to avoid clashing with CwlUtils (from which it is taken). If you want to use these functions outside this file, consider including CwlUtils.
extension UnicodeScalar {
    /// Tests if the scalar is within a range
    func isInRange(_ range: ClosedRange<UnicodeScalar>) -> Bool {
        return range.contains(self)
    }

    /// Tests if the scalar is a plain ASCII digit
    var isDigit: Bool {
        return ("0" ... "9").contains(self)
    }

    /// Tests if the scalar is a plain ASCII English alphabet lowercase letter
    var isLower: Bool {
        return ("a" ... "z").contains(self)
    }

    /// Tests if the scalar is a plain ASCII English alphabet uppercase letter
    var isUpper: Bool {
        return ("A" ... "Z").contains(self)
    }

    /// Tests if the scalar is a plain ASCII English alphabet letter
    var isLetter: Bool {
        return isLower || isUpper
    }
}

extension Array {
    /// Reverse the first n elements of the array
    /// - Parameter count: Number of elements to reverse from the beginning
    mutating func reverseFirst(_ count: Int) {
        guard count > 0, count <= self.count else { return }
        let endIndex = count - 1
        for i in 0 ..< (count / 2) {
            swapAt(i, endIndex - i)
        }
    }

    /// Returns a new array with the first n elements reversed
    /// - Parameter count: Number of elements to reverse from the beginning
    /// - Returns: New array with first n elements reversed
    func reversedFirst(_ count: Int) -> Array {
        var result = self
        result.reverseFirst(count)
        return result
    }
}

extension BinaryInteger {
    var hexadecimalString: String {
        String(self, radix: 16, uppercase: true)
    }
}
