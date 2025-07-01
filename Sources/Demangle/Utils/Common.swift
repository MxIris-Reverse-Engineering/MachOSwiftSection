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
