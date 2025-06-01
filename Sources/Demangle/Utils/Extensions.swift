extension String {
	mutating func writeHex(prefix: String? = nil, _ value: UInt64) {
		if let prefix = prefix {
			write(prefix)
		}
		write(String(value, radix: 16, uppercase: true))
	}
}

extension Array {
	func at(_ index: Int) -> Element? {
		return self.indices.contains(index) ? self[index] : nil
	}
	func slice(_ from: Int, _ to: Int) -> ArraySlice<Element> {
		if from > to || from > self.endIndex || to < self.startIndex {
			return ArraySlice()
		} else {
			return self[(from > self.startIndex ? from : self.startIndex)..<(to < self.endIndex ? to : self.endIndex)]
		}
	}
}

extension TextOutputStream {
    mutating func write(conditional: Bool, _ value: String) {
        if conditional {
            write(value)
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
        return ("0"..."9").contains(self)
    }
    
    /// Tests if the scalar is a plain ASCII English alphabet lowercase letter
    var isLower: Bool {
        return ("a"..."z").contains(self)
    }
    
    /// Tests if the scalar is a plain ASCII English alphabet uppercase letter
    var isUpper: Bool {
        return ("A"..."Z").contains(self)
    }
    
    /// Tests if the scalar is a plain ASCII English alphabet letter
    var isLetter: Bool {
        return isLower || isUpper
    }
}
