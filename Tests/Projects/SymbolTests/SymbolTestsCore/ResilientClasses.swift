import SymbolTestsHelper

// Fixtures producing classes with resilient superclass references and
// resilient bounds (i.e., the compiler defers metadata bounds computation
// to runtime because the parent class's layout may change).
//
// `BUILD_LIBRARY_FOR_DISTRIBUTION = YES` is already enabled in both
// SymbolTestsCore.xcodeproj and SymbolTestsHelper. Crucially, the
// resilient parent (`SymbolTestsHelper.ResilientBase`) lives in a
// DIFFERENT module: only then does the child's layout become unknown
// to the compiler at this side, which forces the child's class context
// descriptor to carry a `ResilientSuperclass` trailing record (and
// makes its metadata bounds runtime-loaded — i.e., a
// `StoredClassMetadataBounds` lookup is needed).

public enum ResilientClassFixtures {
    /// Subclass referring to the resilient parent in another module.
    /// Triggers a ResilientSuperclass record in the class context
    /// descriptor and forces the metadata bounds to be runtime-loaded
    /// (`StoredClassMetadataBounds`).
    public class ResilientChild: ResilientBase {
        public override init() { super.init() }
        public var extraField: Int = 0
    }
}
