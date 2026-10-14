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
/// SwiftUI's associated-type witnesses reach the opaque types of SwiftUICore,
/// which the dyld shared cache places below SwiftUI. Read through the image, such
/// a reference is recorded as the descriptor's absolute address. Read through a
/// wrapper the library did not recognize as in-process, it was recorded as an
/// offset from SwiftUI's header — negative — and converting that to `UInt64`
/// trapped (`Fatal error: Negative value is not representable`).
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

    @Test("a wrapper that does not declare what it wraps reads a lower image's opaque type without trapping")
    func undeclaredWrapperDoesNotTrap() async {
        await #expect(processExitsWith: .success) {
            exit(Self.demangleThroughUndeclaredWrapper())
        }
    }
}

extension WrappedReaderDemanglingTests {
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
    /// witness, and at least one of them refers to an opaque type below SwiftUI —
    /// the reference this suite exists for.
    private static func compareDeclaredWrapperWithItsImage() -> Int32 {
        guard let image = loadedSwiftUI() else { return EXIT_FAILURE }
        let wrapper = ForwardingMachOReader<MachOImage, DeclaredWrapper>(image)
        let imageStartAddress = UInt64(UInt(bitPattern: image.ptr))
        var referencesBelowTheImage = 0
        for name in witnessTypeNames(in: image) {
            let imageNode = try? SymbolicDemangler.demangleTypeUncached(for: name, in: image.context)
            let wrapperNode = try? SymbolicDemangler.demangleTypeUncached(for: name, in: wrapper.context)
            guard imageNode == wrapperNode else { return EXIT_FAILURE }
            let opaqueReferences = imageNode?.all(of: .opaqueTypeDescriptorSymbolicReference) ?? []
            referencesBelowTheImage += opaqueReferences.filter { ($0.index ?? .max) < imageStartAddress }.count
        }
        return referencesBelowTheImage > 0 ? EXIT_SUCCESS : EXIT_FAILURE
    }

    private static func demangleThroughUndeclaredWrapper() -> Int32 {
        guard let image = loadedSwiftUI() else { return EXIT_FAILURE }
        let wrapper = ForwardingMachOReader<MachOImage, UndeclaredWrapper>(image)
        for name in witnessTypeNames(in: image) {
            _ = try? SymbolicDemangler.demangleTypeUncached(for: name, in: wrapper.context)
        }
        return EXIT_SUCCESS
    }
}
