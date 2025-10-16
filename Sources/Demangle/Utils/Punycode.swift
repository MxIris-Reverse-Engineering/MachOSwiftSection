/// Punycode encoding and decoding utilities
enum Punycode {
    // Punycode constants (from RFC 3492, adapted for Swift)
    private static let base = 36
    private static let tmin = 1
    private static let tmax = 26
    private static let skew = 38
    private static let damp = 700
    private static let initialBias = 72
    private static let initialN: UInt32 = 128
    private static let delimiter: Character = "_"

    /// Encode a string using Punycode
    ///
    /// - Parameters:
    ///   - input: The string to encode
    ///   - mapNonSymbolChars: Whether to map non-symbol characters
    /// - Returns: The encoded string, or nil if encoding fails
    static func encodePunycode(_ input: String, mapNonSymbolChars: Bool) -> String? {
        // Convert input to Unicode scalars
        var codePoints = [UInt32]()
        for scalar in input.unicodeScalars {
            let value = scalar.value

            // Map non-symbol characters if requested
            if mapNonSymbolChars, value >= 0xD800, value < 0xD880 {
                // Already in the mapped range
                codePoints.append(value)
            } else if !isValidUnicodeScalar(value) {
                return nil
            } else {
                codePoints.append(value)
            }
        }

        return encodePunycode(codePoints)
    }

    /// Encode Unicode code points using Punycode
    private static func encodePunycode(_ inputCodePoints: [UInt32]) -> String? {
        var output = ""

        var n = initialN
        var delta = 0
        var bias = initialBias

        // Copy basic code points (< 0x80) to output
        var h = 0
        for c in inputCodePoints {
            if c < 0x80 {
                h += 1
                output.append(Character(UnicodeScalar(UInt8(c))))
            }
            if !isValidUnicodeScalar(c) {
                return nil
            }
        }
        let b = h

        // Add delimiter if we have basic code points
        if b > 0 {
            output.append(delimiter)
        }

        // Main encoding loop
        while h < inputCodePoints.count {
            // Find minimum code point >= n
            var m: UInt32 = 0x10FFFF
            for codePoint in inputCodePoints {
                if codePoint >= n, codePoint < m {
                    m = codePoint
                }
            }

            // Check for overflow
            if (m - n) > (UInt32(Int.max) - UInt32(delta)) / UInt32(h + 1) {
                return nil
            }
            delta = delta + Int(m - n) * (h + 1)
            n = m

            for c in inputCodePoints {
                if c < n {
                    if delta == Int.max {
                        return nil
                    }
                    delta += 1
                }

                if c == n {
                    var q = delta
                    var k = base
                    while true {
                        let t = k <= bias ? tmin
                            : k >= bias + tmax ? tmax
                            : k - bias

                        if q < t { break }

                        output.append(digitValue(t + ((q - t) % (base - t))))
                        q = (q - t) / (base - t)
                        k += base
                    }

                    output.append(digitValue(q))
                    bias = adapt(delta, h + 1, h == b)
                    delta = 0
                    h += 1
                }
            }

            delta += 1
            n += 1
        }

        return output
    }

    /// Convert a digit to its character representation
    /// - Swift-specific: Uses 'a'-'z' for 0-25, 'A'-'J' for 26-35
    private static func digitValue(_ digit: Int) -> Character {
        assert(digit < base, "invalid punycode digit")
        if digit < 26 {
            return Character(UnicodeScalar(UInt8(ascii: "a") + UInt8(digit)))
        }
        return Character(UnicodeScalar(UInt8(ascii: "A") - 26 + UInt8(digit)))
    }

    /// Bias adaptation function (from RFC 3492 Section 6.1)
    private static func adapt(_ delta: Int, _ numpoints: Int, _ firsttime: Bool) -> Int {
        var delta = delta
        if firsttime {
            delta = delta / damp
        } else {
            delta = delta / 2
        }

        delta += delta / numpoints
        var k = 0
        while delta > ((base - tmin) * tmax) / 2 {
            delta /= base - tmin
            k += base
        }
        return k + (((base - tmin + 1) * delta) / (delta + skew))
    }

    /// Check if a Unicode scalar value is valid
    private static func isValidUnicodeScalar(_ value: UInt32) -> Bool {
        // Accept the range 0xD800 - 0xD880 for non-symbol characters
        if value >= 0xD800 && value < 0xD880 {
            return true
        }
        // Standard Unicode scalar validation
        return value <= 0xD7FF || (value >= 0xE000 && value <= 0x10FFFF)
    }

    /// Rough adaptation of the pseudocode from 6.2 "Decoding procedure" in RFC3492
    static func decodeSwiftPunycode(_ value: String) throws -> String {
        let input = value.unicodeScalars
        var output = [UnicodeScalar]()

        var pos = input.startIndex

        // Unlike RFC3492, Swift uses underscore for delimiting
        if let ipos = input.lastIndex(of: "_" as UnicodeScalar) {
            output.append(contentsOf: input[input.startIndex ..< ipos].map { UnicodeScalar($0) })
            pos = input.index(ipos, offsetBy: 1)
        }

        // Magic numbers from RFC3492
        var n = 128
        var i = 0
        var bias = 72
        let symbolCount = 36
        let alphaCount = 26
        while pos != input.endIndex {
            let oldi = i
            var w = 1
            for k in stride(from: symbolCount, to: Int.max, by: symbolCount) {
                // Unlike RFC3492, Swift uses letters A-J for values 26-35
                let digit: Int
                if input[pos] >= UnicodeScalar("a") {
                    digit = Int(input[pos].value - UnicodeScalar("a").value)
                } else if input[pos] >= UnicodeScalar("A") {
                    digit = Int((input[pos].value - UnicodeScalar("A").value) + UInt32(alphaCount))
                } else {
                    throw SwiftSymbolParseError.punycodeParseError
                }

                if pos != input.endIndex {
                    pos = input.index(pos, offsetBy: 1)
                }

                i = i &+ (digit &* w)
                let t = max(min(k - bias, alphaCount), 1)
                if digit < t {
                    break
                }
                w = w &* (symbolCount - t)
            }

            // Bias adaptation function
            var delta = (i - oldi) / ((oldi == 0) ? 700 : 2)
            delta = delta + delta / (output.count + 1)
            var k = 0
            while delta > 455 {
                delta = delta / (symbolCount - 1)
                k = k + symbolCount
            }
            k += (symbolCount * delta) / (delta + symbolCount + 2)

            bias = k
            n = n + i / (output.count + 1)
            i = i % (output.count + 1)
            var scalarValue = n
            if scalarValue >= 0xD800, scalarValue < 0xD880 {
                scalarValue -= 0xD800
            }
            let validScalar = UnicodeScalar(scalarValue) ?? UnicodeScalar(".")
            output.insert(validScalar, at: i)
            i += 1
        }
        return String(output.map { Character($0) })
    }
}
