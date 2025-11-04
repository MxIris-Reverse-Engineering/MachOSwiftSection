import Foundation
import Testing
import MachOKit
@_spi(Internals) import MachOSymbols
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
@testable import MachOTestingSupport
import Dependencies

#if os(macOS)
import AppKit
#elseif os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif
import SwiftUI

@Suite(.serialized)
final class MachOImageDumpTests: MachOImageTests, DumpableTests, @unchecked Sendable {
    
    override class var imageName: MachOImageName { .AppKit }
}

extension MachOImageDumpTests {
    @Test func typesInImage() async throws {
        try await dumpTypes(for: machOImage)
    }

    @Test func protocolsInImage() async throws {
        try await dumpProtocols(for: machOImage)
    }

    @Test func protocolConformancesInImage() async throws {
        try await dumpProtocolConformances(for: machOImage)
    }

    @Test func associatedTypesInImage() async throws {
        try await dumpAssociatedTypes(for: machOImage)
    }
    
    @Test func symbols() async throws {
        
        @Dependency(\.symbolIndexStore)
        var symbolIndexStore
        
        let symbols = await symbolIndexStore.allSymbols(in: machOImage)
        for symbol in symbols {
            print(symbol.offset, symbol.name)
        }
    }
}
