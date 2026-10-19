import SwiftDeclaration

/// The keywords of a computed member's accessor block: `{ get }` and
/// `{ get set }`, or SE-0507's `{ borrow }` and `{ borrow mutate }`.
///
/// A declared `borrow` excludes a `get` and a `mutate` requires a `borrow`
/// (SE-0507), so the SE-0507 accessors decide the block whenever the member
/// has them: a getter or setter beside them is one the compiler synthesized,
/// for instance to satisfy a protocol requirement.
struct AccessorBlockKeywords: Equatable, Sendable {
    let read: String

    let write: String?

    var hasWriteAccessor: Bool { write != nil }

    static func getter(hasSetter: Bool) -> AccessorBlockKeywords {
        AccessorBlockKeywords(read: "get", write: hasSetter ? "set" : nil)
    }

    init(read: String, write: String?) {
        self.read = read
        self.write = write
    }

    init(of member: some AccessorRepresentable) {
        read = member.hasBorrowAccessor ? "borrow" : "get"
        write = if member.hasMutateAccessor {
            "mutate"
        } else if member.hasSetter {
            "set"
        } else {
            nil
        }
    }
}
