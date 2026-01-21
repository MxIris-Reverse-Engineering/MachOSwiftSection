extension String {
    package var isSwiftSymbol: Bool {
        Demangler.getManglingPrefixLength(unicodeScalars) > 0
    }

    package var stripManglePrefix: String {
        guard isSwiftSymbol else { return self }
        return String(dropFirst(Demangler.getManglingPrefixLength(unicodeScalars)))
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

    package var second: Element? {
        return at(1)
    }
}

extension BinaryInteger {
    var hexadecimalString: String {
        String(self, radix: 16, uppercase: true)
    }
}

extension String {
    /// A computed property to capitalize the first letter of a string.
    var capitalizingFirstLetter: String {
        // 1. Get the first character.
        guard let first = first else {
            // Return an empty string if the original string is empty.
            return ""
        }

        // 2. Uppercase the first character and concatenate it with the rest of the string.
        return first.uppercased() + dropFirst()
    }

    /// You can also create a mutating method if you want to change the string in place.
    mutating func capitalizeFirstLetter() {
        self = capitalizingFirstLetter
    }
}

package func genericParameterName(depth: UInt64, index: UInt64) -> String {
    var name = ""
    var index = index
    repeat {
        if let scalar = UnicodeScalar(UnicodeScalar("A").value + UInt32(index % 26)) {
            name.unicodeScalars.append(scalar)
        }
        index /= 26
    } while index != 0
    if depth != 0 {
        name.append("\(depth)")
    }
    return name
}
