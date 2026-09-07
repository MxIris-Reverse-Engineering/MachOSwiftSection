/// Helpers over the dylib load names recorded in `LC_LOAD_DYLIB`-family load
/// commands (`@rpath/Foo.framework/Versions/A/Foo`,
/// `/usr/lib/swift/libswiftCore.dylib`, …).
public enum DependencyLoadName {
    /// The bare image name a load name identifies: the last path component with
    /// its first extension component stripped (`Foo`, `libswiftCore`).
    ///
    /// This is deliberately the same rule `MachOImage(name:)` applies to the
    /// images dyld has mapped, so a load name normalized here can be handed
    /// straight to the in-process lookup — passing the un-normalized load name
    /// never matches, because dyld reports absolute paths and the lookup
    /// compares bare names. It is also the key every dependency set is
    /// deduplicated on: the same library is linked under different spellings
    /// by different images (`@rpath/…` by a sibling, an absolute path by a
    /// system framework), and only the bare name is stable across them.
    public static func bareImageName(of loadName: String) -> String {
        let lastPathComponent = loadName.components(separatedBy: "/").last ?? loadName
        return lastPathComponent.components(separatedBy: ".").first ?? lastPathComponent
    }
}
