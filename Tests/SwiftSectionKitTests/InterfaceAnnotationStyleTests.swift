import Testing
import SwiftSectionKit

/// The rule a host colors an annotated interface by. `swift-section` used to
/// keep it private to two `emit` functions; it is public now so that every
/// host colors alike, and so it can be pinned here.
@Suite
struct InterfaceAnnotationStyleTests {
    @Test("An inline diff reads its lines by their +/- prefix")
    func inlineDiff() {
        let text = """
         struct Kept {
        +    var added: Int
        -    var removed: Int
        """
        #expect(InterfaceAnnotationStyle.diff(isUnifiedDiff: false).lineKinds(of: text) == [.plain, .added, .removed])
    }

    /// In a unified diff the first two lines are `--- old` / `+++ new` file
    /// headers. Told apart by position, a content line that happens to begin
    /// with `++` or `--` is never mistaken for one.
    @Test("A unified diff's headers are told apart by position, not prefix")
    func unifiedDiffHeaders() {
        let text = """
        --- old.dylib
        +++ new.dylib
        @@ -1,2 +1,2 @@
        ++counter
        --counter
        """
        #expect(InterfaceAnnotationStyle.diff(isUnifiedDiff: true).lineKinds(of: text) == [.header, .header, .header, .added, .removed])
    }

    @Test("An inline diff has no headers, whatever its first lines say")
    func inlineDiffHasNoHeaders() {
        #expect(InterfaceAnnotationStyle.diff(isUnifiedDiff: false).lineKinds(of: "--- old\n@@ hunk") == [.removed, .plain])
    }

    @Test("An evolution interface reads each line by its lifecycle annotation")
    func evolutionAnnotations() {
        let text = """
        // Legend: [added in v2] …
        public struct Removed {} // [removed in 2.0]
        public struct Modified {} // [modified in 2.0]
        public struct Added {} // [added in 2.0]
        public struct Unchanged {}
        """
        #expect(InterfaceAnnotationStyle.evolution.lineKinds(of: text) == [.header, .removed, .modified, .added, .plain])
    }

    /// `ABIEvolutionRequest.AvailabilityAttributes`: the legend gains a line,
    /// and an attribute line above a declaration carries no annotation of its
    /// own, so the declaration line below it is the one colored.
    @Test("@available attribute lines stay plain; their legend line is a header")
    func evolutionAvailabilityAttributes() {
        let text = """
        // @available(iOS, …) attributes are axis-resolution facts: …
        @available(iOS, introduced: 18.0)
        public struct Added {} // [○●] added in 18.0
            @available(iOS, introduced: 17.0, obsoleted: 18.0)
            public var removed: Int // [●○] removed in 18.0
        """
        #expect(InterfaceAnnotationStyle.evolution.lineKinds(of: text) == [.header, .plain, .added, .plain, .removed])
    }

    @Test("A declaration whose name mentions a lifecycle word stays plain")
    func evolutionClassifiesByAnnotationOnly() {
        #expect(InterfaceAnnotationStyle.evolution.lineKinds(of: "public func removedInLegacyMode()") == [.plain])
    }

    @Test("Empty lines are kept, one kind per line")
    func emptyLinesAreKept() {
        #expect(InterfaceAnnotationStyle.diff(isUnifiedDiff: false).lineKinds(of: "+a\n\n-b\n") == [.added, .plain, .removed, .plain])
    }
}
