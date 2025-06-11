import Foundation
import MachOKit
import MachOSwiftSection
import MachOMacro
import Semantic

extension AssociatedType: Dumpable {
    @MachOImageGenerator
    @StringBuilder
    public func dump(using options: DemangleOptions, in machOFile: MachOFile) throws -> String {
        try "extension \(MetadataReader.demangleSymbol(for: conformingTypeName, in: machOFile).print(using: options)): \(MetadataReader.demangleSymbol(for: protocolTypeName, in: machOFile).print(using: options)) {"
        for (offset, record) in records.offsetEnumerated() {
            BreakLine()

            Indent(level: 1)

            try "typealias \(record.name(in: machOFile)) = \(MetadataReader.demangleSymbol(for: record.substitutedTypeName(in: machOFile), in: machOFile).print(using: options))"

            if offset.isEnd {
                BreakLine()
            }
        }

        "}"
    }

    @MachOImageGenerator
    @SemanticStringBuilder
    public func dump(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        Keyword(.extension)
        
        Space()
        
        try Type(MetadataReader.demangleSymbol(for: conformingTypeName, in: machOFile).print(using: options))
        
        Standard(":")
        
        Space()
        
        try Type(MetadataReader.demangleSymbol(for: protocolTypeName, in: machOFile).print(using: options))
        
        Space()
        
        Standard("{")
        
        for (offset, record) in records.offsetEnumerated() {
            BreakLine()

            Indent(level: 1)

            Keyword(.typealias)

            Space()

            try Type(record.name(in: machOFile))

            Space()

            Standard("=")

            try Type(MetadataReader.demangleSymbol(for: record.substitutedTypeName(in: machOFile), in: machOFile).print(using: options))

            if offset.isEnd {
                BreakLine()
            }
        }

        Standard("}")
    }
}

extension Keyword {
    enum Swift {
        case `associatedtype`
        case `extension`
        case `typealias`
        case `class`
        case `struct`
        case `enum`
    }
    
    init(_ keyword: Swift) {
        switch keyword {
        case .associatedtype:
            self.init("associatedtype")
        case .extension:
            self.init("extension")
        case .typealias:
            self.init("typealias")
        case .class:
            self.init("class")
        case .struct:
            self.init("struct")
        case .enum:
            self.init("enum")
        }
    }
}
