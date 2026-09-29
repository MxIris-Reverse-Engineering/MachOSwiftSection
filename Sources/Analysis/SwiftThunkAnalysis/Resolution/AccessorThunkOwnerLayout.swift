import MachOSwiftSection

/// The generic parameters of the declaration an accessor thunk belongs to —
/// an opaque type descriptor, or the type whose field record the thunk
/// stands in — so an argument the thunk reads out of its buffer can be named
/// as that parameter.
///
/// The thunk receives one pointer: the owner's generic-argument buffer, laid
/// out as IRGen's `enumerateGenericSignatureRequirements` emits and the
/// runtime stores it — every key type parameter in signature order, then
/// every key witness table. `genericParameterKeyFlagsByDepth` records, per
/// depth, which parameters take a key argument, which is what maps the k-th
/// word back to a `(depth, index)`.
public struct AccessorThunkOwnerLayout: Sendable, Hashable {
    public let genericParameterKeyFlagsByDepth: [[Bool]]

    public init(genericParameterKeyFlagsByDepth: [[Bool]]) {
        self.genericParameterKeyFlagsByDepth = genericParameterKeyFlagsByDepth
    }

    /// No knowledge of the owner: every argument read is unnameable.
    public static let unknown = AccessorThunkOwnerLayout(genericParameterKeyFlagsByDepth: [])

    /// The layout a descriptor's generic context describes; `nil` — a
    /// non-generic owner — yields an empty layout.
    public init<Header>(genericContext: TargetGenericContext<Header>?) {
        guard let genericContext else {
            self.init(genericParameterKeyFlagsByDepth: [])
            return
        }
        // `parentParameters` is cumulative per generic ancestor, so each
        // depth's own parameters are the tail past the previous depth's
        // count; the innermost depth is `currentParameters`.
        var flagsByDepth: [[Bool]] = []
        var previousCount = 0
        for parentParameters in genericContext.parentParameters {
            flagsByDepth.append(parentParameters.dropFirst(previousCount).map(\.hasKeyArgument))
            previousCount = parentParameters.count
        }
        let ownParameters = genericContext.currentParameters
        if !ownParameters.isEmpty {
            flagsByDepth.append(ownParameters.map(\.hasKeyArgument))
        }
        self.init(genericParameterKeyFlagsByDepth: flagsByDepth)
    }

    /// The `(depth, index)` of the parameter the `keyArgumentIndex`-th word
    /// of the argument buffer carries, or `nil` when the index is past the
    /// type parameters (a witness table) or the layout is unknown.
    public func genericParameterPosition(ofKeyArgumentAt keyArgumentIndex: Int) -> (depth: Int, index: Int)? {
        var remaining = keyArgumentIndex
        for (depth, flags) in genericParameterKeyFlagsByDepth.enumerated() {
            for (index, hasKeyArgument) in flags.enumerated() where hasKeyArgument {
                if remaining == 0 { return (depth: depth, index: index) }
                remaining -= 1
            }
        }
        return nil
    }
}
