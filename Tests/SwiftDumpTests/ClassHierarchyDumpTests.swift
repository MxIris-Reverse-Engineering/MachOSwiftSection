import Foundation
import Testing
import MachOKit
@_spi(Internals) import MachOSymbols
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
@testable import MachOTestingSupport
import Dependencies
@_spi(Core) import MachOObjCSection
@testable import SwiftInspection

#if os(macOS)
import AppKit
#elseif os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif
import SwiftUI

@Suite(.serialized)
final class ClassHierarchyDumpTests: MachOImageTests, DumpableTests, @unchecked Sendable {
    override class var imageName: MachOImageName { .AppKit }

    @Test
    func dump() async throws {
        let machO = machOImage
        for type in try machO.swift.typeContextDescriptors {
            switch type {
            case .class(let classDescriptor):
                try print(ClassHierarchyDumper.dump(for: classDescriptor, in: machO))
            default:
                break
            }
        }
    }
}
