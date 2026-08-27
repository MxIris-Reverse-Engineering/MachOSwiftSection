import CoreMedia

// `CMTime` is declared under `#pragma pack(push, 4)` in the CoreMedia
// headers: its aggregate alignment is 4 while a structural accumulation of
// the Swift-visible field records produces natural alignment 8 — with
// identical per-field offsets (0/8/12/16) and identical size/stride (24).
// Referencing it as a stored field emits the `__C.CMTime` foreign struct
// descriptor plus its `__swift5_builtin` whole-type record into this binary,
// giving `SwiftLayoutTests` a pack-pragma'd foreign struct whose field
// offsets are derivable even though the aggregate alignment disagrees with
// the structural accumulation (issue #116: the foreign-struct guard degraded
// every field on any size/stride/alignment mismatch).

public struct ForeignPackedTimeContainer {
    public var startTime: CMTime
    public var elapsedSeconds: Double

    public init(startTime: CMTime, elapsedSeconds: Double) {
        self.startTime = startTime
        self.elapsedSeconds = elapsedSeconds
    }
}
