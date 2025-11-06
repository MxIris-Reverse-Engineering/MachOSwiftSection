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
final class ClassHierarchyDumpTests: MachOImageTests, DumpableTests, @unchecked Sendable {
    
    override class var imageName: MachOImageName { .AppKit }
    
    @Test
    func dump() async throws {
        let machO = machOImage
        for type in try machO.swift.types {
            switch type {
            case .class(let `class`):
                var classes: [String] = try [`class`.descriptor.name(in: machO)]
                try await perform(`class`, classes: &classes)
                print(classes)
            default:
                continue
            }
        }
    }
    
    private func perform(_ `class`: `Class`, classes: inout [String]) async throws {
        let machO = machOImage
        if let resilientSuperclass = `class`.resilientSuperclass, let kind = `class`.resilientSuperclassReferenceKind {
            let typeReference = try resilientSuperclass.superclassResolvedTypeReference(for: kind, in: machO)
            switch typeReference {
            case .directTypeDescriptor(let contextDescriptorWrapper):
                switch contextDescriptorWrapper {
                case .type(let typeContextDescriptorWrapper):
                    switch typeContextDescriptorWrapper {
                    case .class(let classDescription):
                        try classes.append(classDescription.name(in: machO))
                        try await perform(Class(descriptor: classDescription, in: machO), classes: &classes)
                    default:
                        return
                    }
                default:
                    return
                }
            case .indirectTypeDescriptor(let symbolOrElement):
                switch symbolOrElement {
                case .element(let element):
                    switch element {
                    case .type(let typeContextDescriptorWrapper):
                        switch typeContextDescriptorWrapper {
                        case .class(let classDescription):
                            try classes.append(classDescription.name(in: machO))
                            try await perform(Class(descriptor: classDescription, in: machO), classes: &classes)
                        default:
                            return
                        }
                    default:
                        return
                    }
                case .symbol(let symbol):
                    try classes.append(symbol.demangledNode.print(using: .interfaceType))
                default:
                    return
                }
            case .directObjCClassName(let string):
                if let string {
                    classes.append(string)
                }
            case .indirectObjCClass(let symbolOrElement):
                switch symbolOrElement {
                case .element(let element):
                    if let classDescription = try element.descriptor.resolve(in: machO) {
                        try classes.append(classDescription.name(in: machO))
                        try await perform(Class(descriptor: classDescription, in: machO), classes: &classes)
                    }
                default:
                    return
                }
            }
        }
    }
    
}
