import SwiftDeclaration
import Demangling

/// The keywords of a computed member's accessor block: `{ get }` and
/// `{ get set }`, or SE-0507's `{ borrow }` and `{ borrow mutate }`, opened by
/// SE-0400's `init` when a variable has an init accessor.
///
/// A declared `borrow` excludes a `get` and a `mutate` requires a `borrow`
/// (SE-0507), so the SE-0507 accessors decide the block whenever the member
/// has them: a getter or setter beside them is one the compiler synthesized,
/// for instance to satisfy a protocol requirement.
struct AccessorBlockKeywords: Equatable, Sendable {
    /// The `init` line a variable's block opens with when it has a SE-0400
    /// init accessor (evolution proposal `init-accessor-recovery`); `nil`
    /// without one.
    let initAccessor: InitAccessorLine?

    let read: String

    let write: String?

    /// A SE-0400 init accessor's line.
    struct InitAccessorLine: Equatable, Sendable {
        /// What `@storageRestrictions(initializes:)` lists, as far as the
        /// image tells (`VariableDefinition.initializedFieldNames`); `nil`
        /// prints the bare `init`, and a comment above the declaration says
        /// the binary does not record them.
        let initializedFieldNames: [String]?
    }

    var hasWriteAccessor: Bool { write != nil }

    static func getter(hasSetter: Bool) -> AccessorBlockKeywords {
        AccessorBlockKeywords(read: "get", write: hasSetter ? "set" : nil)
    }

    init(initAccessor: InitAccessorLine? = nil, read: String, write: String?) {
        self.initAccessor = initAccessor
        self.read = read
        self.write = write
    }

    /// A subscript's block, or any member's without an init accessor line.
    init(of member: some AccessorRepresentable) {
        self.init(initAccessor: nil, accessorsOf: member)
    }

    /// A variable's block, which its init accessor opens.
    init(of variable: VariableDefinition) {
        let initAccessor = variable.hasInitAccessor ? InitAccessorLine(initializedFieldNames: variable.initializedFieldNames) : nil
        self.init(initAccessor: initAccessor, accessorsOf: variable)
    }

    private init(initAccessor: InitAccessorLine?, accessorsOf member: some AccessorRepresentable) {
        self.initAccessor = initAccessor
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

extension AccessorBlockKeywords.InitAccessorLine {
    /// Writes `@storageRestrictions(initializes: _x) init`, on one line as
    /// the compiler's own `.swiftinterface` writes it, or the bare `init`
    /// when the image does not tell what it initializes — the one rendering
    /// every accessor block shares. Never a parameter name: none is
    /// recorded, and the default `newValue` needs none.
    func write<Target: NodePrinterTarget>(into target: inout Target) {
        if let initializedFieldNames, !initializedFieldNames.isEmpty {
            target.write("@storageRestrictions", context: .context(state: .printKeyword))
            target.write("(initializes: ")
            for (index, fieldName) in initializedFieldNames.enumerated() {
                if index > 0 {
                    target.write(", ")
                }
                target.write(fieldName, context: .context(parentKind: .variable, state: .printIdentifier))
            }
            target.write(")")
            target.writeSpace()
        }
        target.write("init", context: .context(state: .printKeyword))
    }
}
