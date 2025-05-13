package let stdlibName = "Swift"
package let objcModule = "__C"
package let cModule = "__C_Synthesized"
package let lldbExpressionsModuleNamePrefix = "__lldb_expr_"
let maxRepeatCount = 2048
let maxNumWords = 26

func archetypeName(_ index: UInt64, _ depth: UInt64) -> String {
    var result = ""
    var i = index
    repeat {
        result.unicodeScalars.append(UnicodeScalar(("A" as UnicodeScalar).value + UInt32(i % 26))!)
        i /= 26
    } while i > 0
    if depth != 0 {
        result += depth.description
    }
    return result
}

// MARK: Punycode.h

/// Rough adaptation of the pseudocode from 6.2 "Decoding procedure" in RFC3492
func decodeSwiftPunycode(_ value: String) throws -> String {
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
        let validScalar = UnicodeScalar(n) ?? UnicodeScalar(".")
        output.insert(validScalar, at: i)
        i += 1
    }
    return String(output.map { Character($0) })
}

package func getManglingPrefixLength<C: Collection>(_ scalars: C) -> Int where C.Iterator.Element == UnicodeScalar {
    var scanner = ScalarScanner(scalars: scalars)
    if scanner.conditional(string: "_T0") || scanner.conditional(string: "_$S") || scanner.conditional(string: "_$s") || scanner.conditional(string: "_$e") {
        return 3
    } else if scanner.conditional(string: "$S") || scanner.conditional(string: "$s") || scanner.conditional(string: "$e") {
        return 2
    } else if scanner.conditional(string: "@__swiftmacro_") {
        return 14
    }

    return 0
}
