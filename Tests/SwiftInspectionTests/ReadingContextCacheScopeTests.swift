import Foundation
import Testing
import MachOKit
import Demangling
@_spi(Internals) import MachOCaches
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport
@testable @_spi(Internals) import SwiftInspection

/// A `ReadingContext` declares where memo caches may file what they compute
/// from it (evolution proposal `reading-context-migration`). These tests pin
/// the contract the demangle memo relies on: an image keys the same entries
/// whether it is reached through its reader or through a context over it —
/// so `removeCache(for:)` still drops them — and a context that declares no
/// identity is never memoized at all.
///
/// Holds `ExclusiveImageAccess(.SymbolTestsHelper)` because it asserts on
/// that image's demangle memo, whole-process state that
/// `PerImageCacheEvictionTests` clears and rebuilds as well.
@Suite(.serialized, ExclusiveImageAccess(.SymbolTestsHelper))
final class ReadingContextCacheScopeTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsHelper }

    private func someTypeDescriptor() throws -> TypeContextDescriptorWrapper {
        try #require(machOFile.swift.typeContextDescriptors.first)
    }

    @Test func aMachOContextKeysItsImageTheWayItsReaderDoes() throws {
        guard case .image(let identifier) = machOFile.context.cacheScope else {
            Issue.record("a Mach-O context declared \(machOFile.context.cacheScope) instead of its image")
            return
        }
        let keyThroughReader = SharedCacheKey(machOFile)
        let keyThroughContext = SharedCacheKey(imageIdentifier: identifier)
        #expect(keyThroughReader == keyThroughContext)
        #expect(keyThroughReader.hashValue == keyThroughContext.hashValue)
    }

    @Test func aDemangleThroughAMachOContextFillsTheImagesMemo() throws {
        let descriptor = try someTypeDescriptor()
        SymbolicDemangler.removeCache(for: machOFile)
        try #require(!SymbolicDemangler.cacheExists(for: machOFile))

        _ = try SymbolicDemangler.demangleContext(for: .type(descriptor), in: machOFile.context)
        #expect(SymbolicDemangler.cacheExists(for: machOFile))

        SymbolicDemangler.removeCache(for: machOFile)
        #expect(!SymbolicDemangler.cacheExists(for: machOFile))
    }

    @Test func aContextWithoutIdentityIsNeverMemoized() throws {
        let descriptor = try someTypeDescriptor()
        SymbolicDemangler.removeCache(for: machOFile)
        try #require(!SymbolicDemangler.cacheExists(for: machOFile))

        let demangledThroughAnonymousContext = try SymbolicDemangler.demangleContext(for: .type(descriptor), in: ContextWithoutCacheScope(wrapped: machOFile.context))
        #expect(!SymbolicDemangler.cacheExists(for: machOFile))

        let demangledThroughMachOContext = try SymbolicDemangler.demangleContext(for: .type(descriptor), in: machOFile.context)
        #expect(demangledThroughAnonymousContext.print(using: .default) == demangledThroughMachOContext.print(using: .default))
        SymbolicDemangler.removeCache(for: machOFile)
    }
}

/// Reads exactly what a Mach-O context reads but declares no cache scope, the
/// way a third-party conformer that knows nothing of the caches would.
private struct ContextWithoutCacheScope: ReadingContext {
    typealias Runtime = RuntimeTarget64
    typealias Address = Int

    let wrapped: MachOContext<MachOFile>

    func readElement<T>(at address: Int) throws -> T {
        try wrapped.readElement(at: address)
    }

    func readElements<T>(at address: Int, numberOfElements: Int) throws -> [T] {
        try wrapped.readElements(at: address, numberOfElements: numberOfElements)
    }

    func readWrapperElement<T: LocatableLayoutWrapper>(at address: Int) throws -> T {
        try wrapped.readWrapperElement(at: address)
    }

    func readWrapperElements<T: LocatableLayoutWrapper>(at address: Int, numberOfElements: Int) throws -> [T] {
        try wrapped.readWrapperElements(at: address, numberOfElements: numberOfElements)
    }

    func readString(at address: Int) throws -> String {
        try wrapped.readString(at: address)
    }

    func advanceAddress(_ address: Int, by offset: Int) -> Int {
        wrapped.advanceAddress(address, by: offset)
    }

    func advanceAddress<T>(_ address: Int, of type: T.Type) -> Int {
        wrapped.advanceAddress(address, of: type)
    }

    func addressFromOffset(_ offset: Int) throws -> Int {
        wrapped.addressFromOffset(offset)
    }

    func addressFromVirtualAddress(_ virtualAddress: UInt64) throws -> Int {
        wrapped.addressFromVirtualAddress(virtualAddress)
    }

    func offsetFromAddress(_ address: Int) throws -> Int {
        wrapped.offsetFromAddress(address)
    }

    var bindRebaseResolver: (any MachOBindRebaseResolving)? {
        wrapped.bindRebaseResolver
    }
}
