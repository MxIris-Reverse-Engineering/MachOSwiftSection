import Foundation
import SymbolTestsHelper

// Fixtures producing classes that carry an `ObjCResilientClassStubInfo`
// trailing record on their class context descriptor.
//
// The Swift compiler emits the stub when:
//   - ObjC interop is enabled (always true on Apple platforms here),
//   - the class is non-generic,
//   - and the class's metadata strategy is `Resilient` or `Singleton`
//     (i.e., the metadata requires runtime relocation/initialization
//     because the parent class's layout cannot be statically computed).
//
// Cross-module inheritance from a class declared in another module built
// with `BUILD_LIBRARY_FOR_DISTRIBUTION = YES` triggers the resilient
// metadata strategy, so the simplest carrier is a Swift class inheriting
// a parent declared in `SymbolTestsHelper`.
//
// `ResilientObjCStubChild` is a fresh subclass dedicated to this Suite
// (so its descriptor offset is stable independent of any vTable/method
// changes on existing fixtures).

public enum ObjCResilientStubFixtures {
    /// Cross-module subclass of `SymbolTestsHelper.Object`. The compiler
    /// emits an `ObjCResilientClassStubInfo` trailing record on the
    /// descriptor; the corresponding Mach-O symbols are
    /// `<mangled>CMt` (full ObjC resilient class stub) and
    /// `<mangled>CMU` (ObjC metadata update function).
    public class ResilientObjCStubChild: Object {
        public var stubField: Int = 0
    }
}
