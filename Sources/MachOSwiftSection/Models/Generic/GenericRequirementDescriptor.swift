import Foundation
import MachOKit
import MachOSwiftSectionMacro

public struct GenericRequirementDescriptor: LocatableLayoutWrapper {
    public struct Layout {
        public let flags: GenericRequirementFlags
        public let param: RelativeDirectPointer<MangledName>
        public let content: RelativeOffset
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension GenericRequirementDescriptor: Dumpable {
    @MachOImageGenerator
    @StringBuilder
    public func dump(using options: SymbolPrintOptions, in machOFile: MachOFile) throws -> String {
        try MetadataReader.demangleType(for: try paramManagedName(in: machOFile), in: machOFile, using: options)
        if layout.flags.kind == .sameType {
            " == "
        } else {
            ": "
        }
        switch try resolvedContent(in: machOFile) {
        case .type(let mangledName):
            try MetadataReader.demangleType(for: mangledName, in: machOFile, using: options)
        case .protocol(let resolvableElement):
            switch resolvableElement {
            case .symbol(let unsolvedSymbol):
                try MetadataReader.demangleType(for: unsolvedSymbol, in: machOFile, using: options)
            case .element(let element):
                switch element {
                case .objc(let objc):
                    try objc.mangledName(in: machOFile)
                case .swift(let protocolDescriptor):
                    try protocolDescriptor.fullname(in: machOFile)
                }
            }
        case .layout(let genericRequirementLayoutKind):
            switch genericRequirementLayoutKind {
            case .class:
                "AnyObject"
            }
        case .conformance/*(let protocolConformanceDescriptor)*/:
            ""
        case .invertedProtocols(let invertedProtocols):
            if invertedProtocols.protocols.hasCopyable, invertedProtocols.protocols.hasEscapable {
                "Copyable, Escapable"
            } else if invertedProtocols.protocols.hasCopyable || invertedProtocols.protocols.hasEscapable {
                if invertedProtocols.protocols.hasCopyable {
                    "Copyable"
                } else {
                    "~Copyable"
                }
                if invertedProtocols.protocols.hasEscapable {
                    "Escapable"
                } else {
                    "~Escapable"
                }
            } else {
                "~Copyable, ~Escapable"
            }
        }
    }
}

@MachOImageAllMembersGenerator
extension GenericRequirementDescriptor {
    //@MachOImageGenerator
    func paramManagedName(in machOFile: MachOFile) throws -> MangledName {
        return try layout.param.resolve(from: offset(of: \.param), in: machOFile)
    }

    //@MachOImageGenerator
    func type(in machOFile: MachOFile) throws -> MangledName {
        return try RelativeDirectPointer<MangledName>(relativeOffset: layout.content).resolve(from: offset(of: \.content), in: machOFile)
    }

    var content: GenericRequirementContent {
        switch layout.flags.kind {
        case .protocol:
            let ptr = RelativeIndirectableRawPointerIntPair<Bool>(relativeOffsetPlusIndirectAndInt: layout.content)
            if ptr.value {
                return .protocol(.objcPointer(.init(relativeOffsetPlusIndirectAndInt: layout.content)))
            } else {
                return .protocol(.swiftPointer(.init(relativeOffsetPlusIndirectAndInt: layout.content)))
            }
        case .sameType,
             .baseClass,
             .sameShape:
            return .type(.init(relativeOffset: layout.content))
        case .sameConformance:
            return .conformance(.init(relativeOffsetPlusIndirect: layout.content))
        case .invertedProtocols:
            var value = layout.content
            return .invertedProtocols(withUnsafeBytes(of: &value) {
                $0.load(as: GenericRequirementContent.InvertedProtocols.self)
            })
        case .layout:
            return .layout(.init(rawValue: layout.content.cast())!)
        }
    }

    //@MachOImageGenerator
    func resolvedContent(in machOFile: MachOFile) throws -> ResolvedGenericRequirementContent {
        let offset = offset(of: \.content)
        switch content {
        case .type(let relativeDirectPointer):
            return try .type(relativeDirectPointer.resolve(from: offset, in: machOFile))
        case .protocol(let relativeProtocolDescriptorPointer):
            return try .protocol(relativeProtocolDescriptorPointer.resolve(from: offset, in: machOFile))
        case .layout(let genericRequirementLayoutKind):
            return .layout(genericRequirementLayoutKind)
        case .conformance(let relativeIndirectablePointer):
            return try .conformance(relativeIndirectablePointer.resolve(from: offset, in: machOFile))
        case .invertedProtocols(let invertedProtocols):
            return .invertedProtocols(invertedProtocols)
        }
    }
}
