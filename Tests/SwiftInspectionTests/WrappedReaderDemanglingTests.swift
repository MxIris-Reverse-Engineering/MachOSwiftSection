import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import Demangling
@_spi(Internals) import SwiftInspection
import MachOTestingSupport
import MachOFixtureSupport

/// A host's wrapper around an in-process `MachOImage` — MachOKitUI's
/// `MachOImageSource` — demangling the image's names.
///
/// SwiftUI's associated-type witnesses reach the opaque types of SwiftUICore.
/// Read through the image, such a reference is recorded as the descriptor's
/// absolute address. Read through a wrapper the library did not recognize as
/// in-process, it was recorded as an offset from SwiftUI's header. Where
/// SwiftUICore lies below SwiftUI — the dyld shared cache's layout from macOS 27
/// on; macOS 15 and 26 map it above — that offset is negative, and converting it
/// to `UInt64` trapped (`Fatal error: Negative value is not representable`).
///
/// Both tests run their body in a child process, so a trap fails the test rather
/// than ending the run.
@Suite
struct WrappedReaderDemanglingTests {
    @Test("a wrapper that declares the image it wraps demangles every witness exactly like the image")
    func declaredWrapperDemanglesLikeItsImage() async {
        await #expect(processExitsWith: .success) {
            exit(Self.compareDeclaredWrapperWithItsImage())
        }
    }

    @Test(
        "a wrapper that does not declare what it wraps reads a lower image's opaque type without trapping",
        .enabled(if: swiftUICoreIsMappedBelowSwiftUI, "SwiftUI reaches an opaque type in a lower image only where the cache maps SwiftUICore below it (macOS 27 on)")
    )
    func undeclaredWrapperDoesNotTrap() async {
        await #expect(processExitsWith: .success) {
            exit(Self.demangleThroughUndeclaredWrapper())
        }
    }
}

extension WrappedReaderDemanglingTests {
    /// Whether this process's dyld shared cache maps SwiftUICore below SwiftUI,
    /// read off the cache's own image list so that nothing is loaded to answer it.
    private static var swiftUICoreIsMappedBelowSwiftUI: Bool {
        guard let cache = DyldCacheLoaded.current, let imageEntries = cache.imageInfos else { return false }
        func headerAddress(ofImageAt path: String) -> UInt64? {
            imageEntries.first { $0.path(in: cache) == path }?.layout.address
        }
        guard let swiftUICoreAddress = headerAddress(ofImageAt: "/System/Library/Frameworks/SwiftUICore.framework/Versions/A/SwiftUICore"),
              let swiftUIAddress = headerAddress(ofImageAt: "/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI")
        else { return false }
        return swiftUICoreAddress < swiftUIAddress
    }

    /// SwiftUI mapped into this process, or `nil` when it cannot be loaded.
    private static func loadedSwiftUI() -> MachOImage? {
        _ = dlopen("/System/Library/Frameworks/SwiftUI.framework/SwiftUI", RTLD_LAZY)
        return MachOImage(named: .SwiftUI)
    }

    /// Every associated-type witness SwiftUI records, as a mangled name.
    private static func witnessTypeNames(in image: MachOImage) -> [MangledName] {
        guard let associatedTypes = try? image.swift.associatedTypes else { return [] }
        return associatedTypes.flatMap { associatedType in
            associatedType.records.compactMap { record in
                try? record.substitutedTypeName(in: image.context)
            }
        }
    }

    /// `EXIT_SUCCESS` when the wrapper's tree equals the image's for every
    /// witness, and at least one of them refers to an opaque type — the node an
    /// unrecognized wrapper recorded as an offset instead of an address. Whether
    /// any of those lies below SwiftUI depends on the host's cache layout, which
    /// makes it the other test's precondition rather than this one's.
    private static func compareDeclaredWrapperWithItsImage() -> Int32 {
        guard let image = loadedSwiftUI() else { return EXIT_FAILURE }
        let wrapper = ForwardingMachOReader<MachOImage, DeclaredWrapper>(image)
        var opaqueReferenceCount = 0
        for name in witnessTypeNames(in: image) {
            let imageNode = try? SymbolicDemangler.demangleTypeUncached(for: name, in: image.context)
            let wrapperNode = try? SymbolicDemangler.demangleTypeUncached(for: name, in: wrapper.context)
            guard imageNode == wrapperNode else { return EXIT_FAILURE }
            opaqueReferenceCount += (imageNode?.all(of: .opaqueTypeDescriptorSymbolicReference) ?? []).count
        }
        return opaqueReferenceCount > 0 ? EXIT_SUCCESS : EXIT_FAILURE
    }

    /// `EXIT_SUCCESS` when at least one witness, read through the image, refers
    /// to an opaque type below SwiftUI — the reference that trapped — and
    /// demangling every witness through the undeclared wrapper returns.
    private static func demangleThroughUndeclaredWrapper() -> Int32 {
        guard let image = loadedSwiftUI() else { return EXIT_FAILURE }
        let names = witnessTypeNames(in: image)
        let imageStartAddress = UInt64(UInt(bitPattern: image.ptr))
        var referencesBelowTheImage = 0
        for name in names {
            let imageNode = try? SymbolicDemangler.demangleTypeUncached(for: name, in: image.context)
            let opaqueReferences = imageNode?.all(of: .opaqueTypeDescriptorSymbolicReference) ?? []
            referencesBelowTheImage += opaqueReferences.filter { ($0.index ?? .max) < imageStartAddress }.count
        }
        guard referencesBelowTheImage > 0 else { return EXIT_FAILURE }
        let wrapper = ForwardingMachOReader<MachOImage, UndeclaredWrapper>(image)
        for name in names {
            _ = try? SymbolicDemangler.demangleTypeUncached(for: name, in: wrapper.context)
        }
        return EXIT_SUCCESS
    }
}
