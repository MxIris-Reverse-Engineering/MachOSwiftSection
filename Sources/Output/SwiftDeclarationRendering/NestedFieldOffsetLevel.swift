import Foundation
import FoundationToolbox

/// What the in-process nested field-offset walk reads about one metatype:
/// everything it prints for that metatype's rows and everything it needs to
/// go one level down, computed once per metatype (evolution proposal
/// `nested-field-offset-memoization`).
///
/// A level depends on the metatype alone — its descriptor, field offsets and
/// field records, and the names and metatypes those resolve to — never on
/// where in a tree the metatype is reached, so `String` under two different
/// fields shares one. Everything positional stays with the walk: the base
/// offset, the tree's ancestor column, the depth and the cycle guard.
///
/// `@unchecked Sendable`: a level is immutable once built, and the metatypes
/// it holds are runtime metadata, which lives as long as the process.
enum NestedFieldOffsetLevel: @unchecked Sendable {
    /// A struct's stored fields: one entry per field whose name could be read.
    case structFields([StructField])
    /// An enum's (or `Optional`'s) payload cases: one entry per case whose
    /// payload type resolved to a metatype.
    case enumPayloads([EnumPayload])
    /// A metatype the walk does not expand: neither a struct nor an enum, or
    /// one whose metadata could not be read.
    case notExpanded

    struct StructField {
        let fieldName: String
        let typeName: String
        let relativeOffset: Int
        /// The field's metatype, or `nil` when the walk does not descend.
        let childMetatype: Any.Type?
        /// Whether the row draws the closing branch. Counted over every field
        /// record, including one whose name could not be read and so has no
        /// entry — which is how the walk has always drawn it.
        let isLast: Bool
    }

    struct EnumPayload {
        let caseName: String
        let typeName: String
        let payloadMetatype: Any.Type
        /// Counted over every payload case, including one whose payload did
        /// not resolve and so has no entry.
        let isLast: Bool
        /// `false` for an `indirect` case: its payload is boxed, not laid out
        /// at the case's offset.
        let descends: Bool
    }
}

/// The process-wide memo of ``NestedFieldOffsetLevel``s, keyed by metatype.
///
/// A `static` store rather than a per-image `SharedCache`: a metatype is
/// unique in the process and outlives every image the host keeps loaded, and
/// one level serves every image that reaches the type. Its size is the
/// number of distinct metatypes the process expanded. A level is built
/// outside the lock and stored by whoever finishes first; two builders of one
/// metatype produce the same level, so the loser only wasted its build.
enum NestedFieldOffsetLevelMemo {
    private struct State {
        var levelsByMetatype: [ObjectIdentifier: NestedFieldOffsetLevel] = [:]
        /// Bumped by `removeAll()`, so a level whose build straddled it is
        /// returned to its caller but not stored.
        var generation = 0
    }

    @Mutex
    private static var state: State = State()

    /// Builds every level afresh and stores none, for the tests that compare
    /// the memoized expansion with an unmemoized one.
    @TaskLocal
    package static var isBypassed = false

    static func level(for metatype: Any.Type, building build: () -> NestedFieldOffsetLevel) -> NestedFieldOffsetLevel {
        if isBypassed {
            return build()
        }
        let metatypeIdentifier = ObjectIdentifier(metatype)
        let (memoizedLevel, generation) = _state.withLockUnchecked { state in
            (state.levelsByMetatype[metatypeIdentifier], state.generation)
        }
        if let memoizedLevel {
            return memoizedLevel
        }
        let builtLevel = build()
        return _state.withLockUnchecked { state in
            guard state.generation == generation else {
                return builtLevel
            }
            if let storedLevel = state.levelsByMetatype[metatypeIdentifier] {
                return storedLevel
            }
            state.levelsByMetatype[metatypeIdentifier] = builtLevel
            return builtLevel
        }
    }

    static func removeAll() {
        _state.withLockUnchecked { state in
            state.levelsByMetatype.removeAll()
            state.generation += 1
        }
    }
}

/// The process-wide memo of the in-process (`MachOImage`) field-layout
/// renderer.
public enum RuntimeFieldLayoutMemo {
    /// Forgets every memoized level of the nested field-offset expansion.
    ///
    /// A level records which field and payload types resolved when it was
    /// built. A type defined in an image the process had not loaded yet does
    /// not resolve, and the level keeps saying so after the image loads: the
    /// expansion stops where, rendered again, it would now descend. A host
    /// that loads images while it renders — RuntimeViewer, after each image
    /// it loads — calls this once after the load. Rendering never needs it
    /// otherwise.
    public static func removeAll() {
        NestedFieldOffsetLevelMemo.removeAll()
    }
}
