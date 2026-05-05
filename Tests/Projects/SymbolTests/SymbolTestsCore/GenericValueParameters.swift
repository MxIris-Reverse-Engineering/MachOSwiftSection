// Generic types with integer-value parameters (Swift 6.1+).
//
// Value-generic types use `<let N: Int>` to bind compile-time integer
// values to the generic context. The Swift compiler emits an extra
// `GenericValueHeader` followed by one `GenericValueDescriptor` per
// declared value parameter on the generic context's metadata layout
// (the `GenericContextDescriptorFlags.hasValues` bit is set).
//
// Phase B7 introduces this fixture to give the Suites
// `GenericValueDescriptorTests` and `GenericValueHeaderTests` a live
// runtime carrier. The descriptor is reached via a struct
// `FixedSizeArray<let N: Int, T>` declared inside
// `GenericValueFixtures` — the value parameter `N` produces the
// `GenericValueDescriptor`, and the surrounding generic context
// produces the trailing `GenericValueHeader`.

@available(macOS 26.0, *)
public enum GenericValueFixtures {
    public struct FixedSizeArray<let N: Int, T> {
        public init() {}
    }
}
