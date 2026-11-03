import Foundation
import Testing
import MachOKit
import SwiftDeclarationRendering
@_spi(Support) @testable import SwiftPrinting
@testable import MachOTestingSupport
import MachOFixtureSupport

/// `updateConfiguration(_:)` keeps the memoized static field-layout provider
/// while the provider's inputs stay the same, and rebuilds it when they
/// change.
///
/// RuntimeViewer hands the printer its configuration before every interface
/// print, usually unchanged. Each call used to discard the provider, so an
/// offline (`MachOFile`) print with a layout comment on rebuilt the static
/// layout calculator — over the default resolution a new dependency closure,
/// a new walk over every image of the dyld caches searched, and a dependency
/// type index started from scratch — for every interface it printed.
///
/// The provider depends on two things only: whether any configuration flag
/// asks for one, and `staticLayoutDependencyResolution`. A change to either
/// still rebuilds it, which is what the reset was added for.
@Suite
final class StaticFieldLayoutProviderReuseTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    /// A configuration asking for field offsets, laid out over the fixture
    /// alone so that building a provider stays cheap.
    private static func fieldOffsetConfiguration() -> SwiftDeclarationPrintConfiguration {
        var configuration = SwiftDeclarationPrintConfiguration()
        configuration.printFieldOffset = true
        configuration.staticLayoutDependencyResolution = .singleImage
        return configuration
    }

    @Test func anEqualConfigurationKeepsTheProvider() throws {
        let configuration = Self.fieldOffsetConfiguration()
        let printer = SwiftDeclarationPrinter(configuration: configuration, in: machOFile)
        let provider = try #require(printer.staticFieldLayoutProvider() as? MachOFileStaticFieldLayoutProvider)

        printer.updateConfiguration(configuration)

        let providerAfterUpdate = try #require(printer.staticFieldLayoutProvider() as? MachOFileStaticFieldLayoutProvider)
        #expect(providerAfterUpdate === provider)
    }

    /// Any layout flag needs the same provider: turning a second one on, or
    /// changing a flag the provider does not read, keeps it.
    @Test func aChangeThatStillNeedsAProviderKeepsIt() throws {
        var configuration = Self.fieldOffsetConfiguration()
        let printer = SwiftDeclarationPrinter(configuration: configuration, in: machOFile)
        let provider = try #require(printer.staticFieldLayoutProvider() as? MachOFileStaticFieldLayoutProvider)

        configuration.printTypeLayout = true
        configuration.printEnumLayout = true
        configuration.printMemberAddress = true
        printer.updateConfiguration(configuration)
        let providerAfterMoreFlags = try #require(printer.staticFieldLayoutProvider() as? MachOFileStaticFieldLayoutProvider)
        #expect(providerAfterMoreFlags === provider)

        configuration.printFieldOffset = false
        printer.updateConfiguration(configuration)
        let providerAfterDroppingTheFirstFlag = try #require(printer.staticFieldLayoutProvider() as? MachOFileStaticFieldLayoutProvider)
        #expect(providerAfterDroppingTheFirstFlag === provider)
    }

    /// The guarantee the reset was added for: a change that turns the need
    /// off, turns it back on, or changes the resolution reaches the provider.
    @Test func aChangeOfTheProvidersInputsRebuildsIt() throws {
        var configuration = Self.fieldOffsetConfiguration()
        let printer = SwiftDeclarationPrinter(configuration: configuration, in: machOFile)
        let firstProvider = try #require(printer.staticFieldLayoutProvider() as? MachOFileStaticFieldLayoutProvider)

        configuration.printFieldOffset = false
        printer.updateConfiguration(configuration)
        #expect(printer.staticFieldLayoutProvider() == nil, "no flag needs a provider")

        configuration.printFieldOffset = true
        printer.updateConfiguration(configuration)
        let secondProvider = try #require(printer.staticFieldLayoutProvider() as? MachOFileStaticFieldLayoutProvider)
        #expect(secondProvider !== firstProvider)

        configuration.staticLayoutDependencyResolution = .dependencyClosure(searchPaths: [])
        printer.updateConfiguration(configuration)
        let thirdProvider = try #require(printer.staticFieldLayoutProvider() as? MachOFileStaticFieldLayoutProvider)
        #expect(thirdProvider !== secondProvider, "a new resolution builds a new provider")

        printer.updateConfiguration(configuration)
        #expect(printer.staticFieldLayoutProvider() as? MachOFileStaticFieldLayoutProvider === thirdProvider)
    }

    /// A marked print needs every layout comment's content, so it needs a
    /// provider with every layout flag off.
    @Test func markingOptionalContentNeedsAProvider() throws {
        var configuration = SwiftDeclarationPrintConfiguration()
        configuration.staticLayoutDependencyResolution = .singleImage
        let printer = SwiftDeclarationPrinter(configuration: configuration, in: machOFile)
        #expect(printer.staticFieldLayoutProvider() == nil)

        configuration.marksOptionalContent = true
        printer.updateConfiguration(configuration)
        let provider = try #require(printer.staticFieldLayoutProvider() as? MachOFileStaticFieldLayoutProvider)

        configuration.printFieldOffset = true
        printer.updateConfiguration(configuration)
        #expect(printer.staticFieldLayoutProvider() as? MachOFileStaticFieldLayoutProvider === provider)
    }
}
