/// NOTE: This struct is fileprivate to avoid clashing with CwlUtils (from which it is taken). If you want to use this struct outside this file, consider including CwlUtils.
///
/// A structure for traversing a `String.UnicodeScalarView`.
///
/// **UNICODE WARNING**: this struct ignores all Unicode combining rules and parses each scalar individually. The rules for parsing must allow combined characters to be parsed separately or better yet, forbid combining characters at critical parse locations. If your data structure does not include these types of rule then you should be iterating over the `Character` elements in a `String` rather than using this struct.
struct ScalarScanner<C: Collection> where C.Iterator.Element == UnicodeScalar {
    /// The underlying storage
    let scalars: C

    /// Current scanning index
    var index: C.Index

    /// Number of scalars consumed up to `index` (since String.UnicodeScalarView.Index is not a RandomAccessIndex, this makes determining the position *much* easier)
    var consumed: Int

    /// Construct from a String.UnicodeScalarView and a context value
    init(scalars: C) {
        self.scalars = scalars
        self.index = self.scalars.startIndex
        self.consumed = 0
    }

    /// Sets the index back to the beginning and clears the consumed count
    mutating func reset() {
        index = scalars.startIndex
        consumed = 0
    }

    /// Throw if the scalars at the current `index` don't match the scalars in `value`. Advance the `index` to the end of the match.
    /// WARNING: `string` is used purely for its `unicodeScalars` property and matching is purely based on direct scalar comparison (no decomposition or normalization is performed).
    mutating func match(string: String) throws {
        let (newIndex, newConsumed) = try string.unicodeScalars.reduce((index: index, count: 0)) { (tuple: (index: C.Index, count: Int), scalar: UnicodeScalar) in
            if tuple.index == self.scalars.endIndex || scalar != self.scalars[tuple.index] {
                throw SwiftSymbolParseError.matchFailed(wanted: string, at: consumed)
            }
            return (index: self.scalars.index(after: tuple.index), count: tuple.count + 1)
        }
        index = newIndex
        consumed += newConsumed
    }

    /// Throw if the scalars at the current `index` don't match the scalars in `value`. Advance the `index` to the end of the match.
    mutating func match(scalar: UnicodeScalar) throws {
        if index == scalars.endIndex || scalars[index] != scalar {
            throw SwiftSymbolParseError.matchFailed(wanted: String(scalar), at: consumed)
        }
        index = scalars.index(after: index)
        consumed += 1
    }

    /// Throw if the scalars at the current `index` don't match the scalars in `value`. Advance the `index` to the end of the match.
    mutating func match(where test: @escaping (UnicodeScalar) -> Bool) throws {
        if index == scalars.endIndex || !test(scalars[index]) {
            throw SwiftSymbolParseError.matchFailed(wanted: "(match test function to succeed)", at: consumed)
        }
        index = scalars.index(after: index)
        consumed += 1
    }

    /// Throw if the scalars at the current `index` don't match the scalars in `value`. Advance the `index` to the end of the match.
    mutating func read(where test: @escaping (UnicodeScalar) -> Bool) throws -> UnicodeScalar {
        if index == scalars.endIndex || !test(scalars[index]) {
            throw SwiftSymbolParseError.matchFailed(wanted: "(read test function to succeed)", at: consumed)
        }
        let s = scalars[index]
        index = scalars.index(after: index)
        consumed += 1
        return s
    }

    /// Consume scalars from the contained collection, up to but not including the first instance of `scalar` found. `index` is advanced to immediately before `scalar`. Returns all scalars consumed prior to `scalar` as a `String`. Throws if `scalar` is never found.
    mutating func readUntil(scalar: UnicodeScalar) throws -> String {
        var i = index
        let previousConsumed = consumed
        try skipUntil(scalar: scalar)

        var result = ""
        result.reserveCapacity(consumed - previousConsumed)
        while i != index {
            result.unicodeScalars.append(scalars[i])
            i = scalars.index(after: i)
        }

        return result
    }

    /// Consume scalars from the contained collection, up to but not including the first instance of `string` found. `index` is advanced to immediately before `string`. Returns all scalars consumed prior to `string` as a `String`. Throws if `string` is never found.
    /// WARNING: `string` is used purely for its `unicodeScalars` property and matching is purely based on direct scalar comparison (no decomposition or normalization is performed).
    mutating func readUntil(string: String) throws -> String {
        var i = index
        let previousConsumed = consumed
        try skipUntil(string: string)

        var result = ""
        result.reserveCapacity(consumed - previousConsumed)
        while i != index {
            result.unicodeScalars.append(scalars[i])
            i = scalars.index(after: i)
        }

        return result
    }

    /// Consume scalars from the contained collection, up to but not including the first instance of any character in `set` found. `index` is advanced to immediately before `string`. Returns all scalars consumed prior to `string` as a `String`. Throws if no matching characters are ever found.
    mutating func readUntil(set inSet: Set<UnicodeScalar>) throws -> String {
        var i = index
        let previousConsumed = consumed
        try skipUntil(set: inSet)

        var result = ""
        result.reserveCapacity(consumed - previousConsumed)
        while i != index {
            result.unicodeScalars.append(scalars[i])
            i = scalars.index(after: i)
        }

        return result
    }

    /// Peeks at the scalar at the current `index`, testing it with function `f`. If `f` returns `true`, the scalar is appended to a `String` and the `index` increased. The `String` is returned at the end.
    mutating func readWhile(true test: (UnicodeScalar) -> Bool) -> String {
        var string = ""
        while index != scalars.endIndex {
            if !test(scalars[index]) {
                break
            }
            string.unicodeScalars.append(scalars[index])
            index = scalars.index(after: index)
            consumed += 1
        }
        return string
    }

    /// Repeatedly peeks at the scalar at the current `index`, testing it with function `f`. If `f` returns `true`, the `index` increased. If `false`, the function returns.
    mutating func skipWhile(true test: (UnicodeScalar) -> Bool) {
        while index != scalars.endIndex {
            if !test(scalars[index]) {
                return
            }
            index = scalars.index(after: index)
            consumed += 1
        }
    }

    /// Consume scalars from the contained collection, up to but not including the first instance of `scalar` found. `index` is advanced to immediately before `scalar`. Throws if `scalar` is never found.
    mutating func skipUntil(scalar: UnicodeScalar) throws {
        var i = index
        var c = 0
        while i != scalars.endIndex && scalars[i] != scalar {
            i = scalars.index(after: i)
            c += 1
        }
        if i == scalars.endIndex {
            throw SwiftSymbolParseError.searchFailed(wanted: String(scalar), after: consumed)
        }
        index = i
        consumed += c
    }

    /// Consume scalars from the contained collection, up to but not including the first instance of any scalar from `set` is found. `index` is advanced to immediately before `scalar`. Throws if `scalar` is never found.
    mutating func skipUntil(set inSet: Set<UnicodeScalar>) throws {
        var i = index
        var c = 0
        while i != scalars.endIndex && !inSet.contains(scalars[i]) {
            i = scalars.index(after: i)
            c += 1
        }
        if i == scalars.endIndex {
            throw SwiftSymbolParseError.searchFailed(wanted: "One of: \(inSet.sorted())", after: consumed)
        }
        index = i
        consumed += c
    }

    /// Consume scalars from the contained collection, up to but not including the first instance of `string` found. `index` is advanced to immediately before `string`. Throws if `string` is never found.
    /// WARNING: `string` is used purely for its `unicodeScalars` property and matching is purely based on direct scalar comparison (no decomposition or normalization is performed).
    mutating func skipUntil(string: String) throws {
        let match = string.unicodeScalars
        guard let first = match.first else { return }
        if match.count == 1 {
            return try skipUntil(scalar: first)
        }
        var i = index
        var j = index
        var c = 0
        var d = 0
        let remainder = match[match.index(after: match.startIndex) ..< match.endIndex]
        outerLoop: repeat {
            while scalars[i] != first {
                if i == scalars.endIndex {
                    throw SwiftSymbolParseError.searchFailed(wanted: String(match), after: consumed)
                }
                i = scalars.index(after: i)
                c += 1

                // Track the last index and consume count before hitting the match
                j = i
                d = c
            }
            i = scalars.index(after: i)
            c += 1
            for s in remainder {
                if i == scalars.endIndex {
                    throw SwiftSymbolParseError.searchFailed(wanted: String(match), after: consumed)
                }
                if scalars[i] != s {
                    continue outerLoop
                }
                i = scalars.index(after: i)
                c += 1
            }
            break
        } while true
        index = j
        consumed += d
    }

    /// Attempt to advance the `index` by count, returning `false` and `index` unchanged if `index` would advance past the end, otherwise returns `true` and `index` is advanced.
    mutating func skip(count: Int = 1) throws {
        if count == 1 && index != scalars.endIndex {
            index = scalars.index(after: index)
            consumed += 1
        } else {
            var i = index
            var c = count
            while c > 0 {
                if i == scalars.endIndex {
                    throw SwiftSymbolParseError.endedPrematurely(count: count, at: consumed)
                }
                i = scalars.index(after: i)
                c -= 1
            }
            index = i
            consumed += count
        }
    }

    /// Attempt to advance the `index` by count, returning `false` and `index` unchanged if `index` would advance past the end, otherwise returns `true` and `index` is advanced.
    mutating func backtrack(count: Int = 1) throws {
        if count <= consumed {
            if count == 1 {
                index = scalars.index(index, offsetBy: -1)
                consumed -= 1
            } else {
                let limit = consumed - count
                while consumed != limit {
                    index = scalars.index(index, offsetBy: -1)
                    consumed -= 1
                }
            }
        } else {
            throw SwiftSymbolParseError.endedPrematurely(count: -count, at: consumed)
        }
    }

    /// Returns all content after the current `index`. `index` is advanced to the end.
    mutating func remainder() -> String {
        var string = ""
        while index != scalars.endIndex {
            string.unicodeScalars.append(scalars[index])
            index = scalars.index(after: index)
            consumed += 1
        }
        return string
    }

    /// If the next scalars after the current `index` match `value`, advance over them and return `true`, otherwise, leave `index` unchanged and return `false`.
    /// WARNING: `string` is used purely for its `unicodeScalars` property and matching is purely based on direct scalar comparison (no decomposition or normalization is performed).
    mutating func conditional(string: String) -> Bool {
        var i = index
        var c = 0
        for s in string.unicodeScalars {
            if i == scalars.endIndex || s != scalars[i] {
                return false
            }
            i = scalars.index(after: i)
            c += 1
        }
        index = i
        consumed += c
        return true
    }

    /// If the next scalar after the current `index` match `value`, advance over it and return `true`, otherwise, leave `index` unchanged and return `false`.
    mutating func conditional(scalar: UnicodeScalar) -> Bool {
        if index == scalars.endIndex || scalar != scalars[index] {
            return false
        }
        index = scalars.index(after: index)
        consumed += 1
        return true
    }

    /// If the next scalar after the current `index` match `value`, advance over it and return `true`, otherwise, leave `index` unchanged and return `false`.
    mutating func conditional(where test: (UnicodeScalar) -> Bool) -> UnicodeScalar? {
        if index == scalars.endIndex || !test(scalars[index]) {
            return nil
        }
        let s = scalars[index]
        index = scalars.index(after: index)
        consumed += 1
        return s
    }

    /// If the `index` is at the end, throw, otherwise, return the next scalar at the current `index` without advancing `index`.
    func requirePeek() throws -> UnicodeScalar {
        if index == scalars.endIndex {
            throw SwiftSymbolParseError.endedPrematurely(count: 1, at: consumed)
        }
        return scalars[index]
    }

    /// If `index` + `ahead` is within bounds, return the scalar at that location, otherwise return `nil`. The `index` will not be changed in any case.
    func peek(skipCount: Int = 0) -> UnicodeScalar? {
        var i = index
        var c = skipCount
        while c > 0 && i != scalars.endIndex {
            i = scalars.index(after: i)
            c -= 1
        }
        if i == scalars.endIndex {
            return nil
        }
        return scalars[i]
    }

    /// If the `index` is at the end, throw, otherwise, return the next scalar at the current `index`, advancing `index` by one.
    mutating func readScalar() throws -> UnicodeScalar {
        if index == scalars.endIndex {
            throw SwiftSymbolParseError.endedPrematurely(count: 1, at: consumed)
        }
        let result = scalars[index]
        index = scalars.index(after: index)
        consumed += 1
        return result
    }

    /// Throws if scalar at the current `index` is not in the range `"0"` to `"9"`. Consume scalars `"0"` to `"9"` until a scalar outside that range is encountered. Return the integer representation of the value scanned, interpreted as a base 10 integer. `index` is advanced to the end of the number.
    mutating func readInt() throws -> UInt64 {
        let result = try conditionalInt()
        guard let r = result else {
            throw SwiftSymbolParseError.expectedInt(at: consumed)
        }
        return r
    }

    /// Throws if scalar at the current `index` is not in the range `"0"` to `"9"`. Consume scalars `"0"` to `"9"` until a scalar outside that range is encountered. Return the integer representation of the value scanned, interpreted as a base 10 integer. `index` is advanced to the end of the number.
    mutating func conditionalInt() throws -> UInt64? {
        var result: UInt64 = 0
        var i = index
        var c = 0
        while i != scalars.endIndex && scalars[i].isDigit {
            let digit = UInt64(scalars[i].value - UnicodeScalar("0").value)

            // The Swift compiler allows overflow here for malformed inputs, so we're obliged to do the same
            result = result &* 10 &+ digit

            i = scalars.index(after: i)
            c += 1
        }
        if i == index {
            return nil
        }
        index = i
        consumed += c
        return result
    }

    /// Consume and return `count` scalars. `index` will be advanced by count. Throws if end of `scalars` occurs before consuming `count` scalars.
    mutating func readScalars(count: Int) throws -> String {
        var result = String()
        result.reserveCapacity(count)
        var i = index
        for _ in 0 ..< count {
            if i == scalars.endIndex {
                throw SwiftSymbolParseError.endedPrematurely(count: count, at: consumed)
            }
            result.unicodeScalars.append(scalars[i])
            i = scalars.index(after: i)
        }
        index = i
        consumed += count
        return result
    }

    /// Returns a throwable error capturing the current scanner progress point.
    func unexpectedError() -> SwiftSymbolParseError {
        return SwiftSymbolParseError.unexpected(at: consumed)
    }

    var isAtEnd: Bool {
        return index == scalars.endIndex
    }
}
