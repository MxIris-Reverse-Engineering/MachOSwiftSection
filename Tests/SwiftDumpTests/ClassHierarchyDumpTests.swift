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
        for type in try machO.swift.types {
            switch type {
            case .class(let `class`):
                var classes: [String] = []
                if let metadataAccessor = try `class`.descriptor.metadataAccessor(in: machO), !`class`.descriptor.flags.isGeneric {
                    let metadata = try metadataAccessor.perform(request: .init(state: .complete, isBlocking: false)).value.resolve(in: machO)
                    switch metadata {
                    case .class(let classMetadataObjCInterop):
                        try print(`class`.descriptor.name(in: machO))
                        try perform(classMetadata: classMetadataObjCInterop, classDescriptor: `class`.descriptor, classes: &classes)
                        print(classes)
                    default:
                        break
                    }
                }
            default:
                break
            }
        }
    }

    private func perform(objcClass: ObjCClass64, classes: inout [String]) throws {
        let machO = machOImage
        if let superclass = objcClass.superClass(in: machO)?.1 {
            if let name = superclass.info(in: machO)?.name {
                classes.append(name)
                try perform(objcClass: superclass, classes: &classes)
            }
        }
    }
    
    private func perform(classMetadata: ClassMetadataObjCInterop, classDescriptor: ClassDescriptor, classes: inout [String]) throws {
        let machO = machOImage

        try classes.append(classDescriptor.name(in: machO))
        if let superclassMetadata = try classMetadata.superclass(in: machO) {
            if superclassMetadata.isPureObjC {
                let objcClass = try ObjCClass64.resolve(from: superclassMetadata.offset, in: machO)
                if let name = objcClass.info(in: machO)?.name {
                    classes.append(name)
                }
                try perform(objcClass: objcClass, classes: &classes)
            } else if let superclassDescriptor = try superclassMetadata.descriptor(in: machO) {
                try perform(classMetadata: superclassMetadata, classDescriptor: superclassDescriptor, classes: &classes)
            }
        }
    }
}

extension ObjCClass64: @retroactive Equatable {
    public static func == (lhs: ObjCClass64, rhs: ObjCClass64) -> Bool {
        lhs.offset == rhs.offset && lhs.layout == rhs.layout
    }
}
extension ObjCClass64: LocatableLayoutWrapper, Resolvable, @unchecked @retroactive Sendable {}

extension ObjCClass64.Layout: @retroactive Equatable {
    public static func == (lhs: ObjCClass64.Layout, rhs: ObjCClass64.Layout) -> Bool {
        lhs.isa == rhs.isa &&
        lhs.superclass == rhs.superclass &&
        lhs.methodCacheBuckets == rhs.methodCacheBuckets &&
        lhs.methodCacheProperties == rhs.methodCacheProperties &&
        lhs.swiftClassFlags == rhs.swiftClassFlags
    }
}
extension ObjCClass64.Layout: LayoutProtocol, @unchecked @retroactive Sendable {}
