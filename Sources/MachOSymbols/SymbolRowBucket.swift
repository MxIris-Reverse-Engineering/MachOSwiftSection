/// Row-index bucket for `SymbolIndexStore`'s offset and member indexes
/// (evolution proposal 0003): almost every offset / member key maps to
/// exactly one symbol-table row, so the single-row form stays inline in the
/// dictionary slot and only a bucket that actually collects a second row
/// pays a heap allocation. The former `[UInt32]` buckets paid an array
/// allocation per key — one per hundreds of thousands of keys in a
/// framework-scale image.
///
/// Iteration order is insertion order in both forms (`multiple` preserves
/// the array's append order, `single` is trivially ordered), so query
/// output is byte-identical to the `[UInt32]` representation it replaces.
enum SymbolRowBucket: Equatable, Sendable {
    case single(UInt32)
    case multiple([UInt32])

    /// Starting value for the `dictionary[key, default: .empty].append(row)`
    /// accumulation idiom. `.multiple([])` allocates nothing (an empty
    /// `Array` shares the global empty storage singleton) and the first
    /// `append` rewrites it to the inline `single` form.
    static var empty: SymbolRowBucket { .multiple([]) }

    mutating func append(_ row: UInt32) {
        switch self {
        case .multiple(let rows) where rows.isEmpty:
            self = .single(row)
        case .single(let existingRow):
            self = .multiple([existingRow, row])
        case .multiple(var rows):
            // Drop the payload's array reference before mutating so the
            // append never triggers a copy-on-write of the whole bucket.
            self = .empty
            rows.append(row)
            self = .multiple(rows)
        }
    }
}

extension SymbolRowBucket: RandomAccessCollection {
    var startIndex: Int { 0 }

    var endIndex: Int {
        switch self {
        case .single:
            return 1
        case .multiple(let rows):
            return rows.count
        }
    }

    subscript(position: Int) -> UInt32 {
        switch self {
        case .single(let row):
            precondition(position == 0, "single-row bucket only has index 0")
            return row
        case .multiple(let rows):
            return rows[position]
        }
    }
}
