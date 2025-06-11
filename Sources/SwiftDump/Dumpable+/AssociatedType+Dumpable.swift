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
        
        try MetadataReader.demangleSymbol(for: conformingTypeName, in: machOFile).printSemantic(using: options).map {
            if $0.type == .typeName {
                return TypeDeclaration($0.string)
            } else {
                return $0
            }
        }
        
        Standard(":")
        
        Space()
        
        try MetadataReader.demangleSymbol(for: protocolTypeName, in: machOFile).printSemantic(using: options)
        
        Space()
        
        Standard("{")
        
        for (offset, record) in records.offsetEnumerated() {
            BreakLine()

            Indent(level: 1)

            Keyword(.typealias)

            Space()

            try TypeName(record.name(in: machOFile))

            Space()

            Standard("=")

            Space()
            
            try MetadataReader.demangleSymbol(for: record.substitutedTypeName(in: machOFile), in: machOFile).printSemantic(using: options)

            if offset.isEnd {
                BreakLine()
            }
        }

        Standard("}")
    }
}

extension Keyword {
    enum Swift: String {
        case `associatedtype`
        case `extension`
        case `typealias`
        case `class`
        case `struct`
        case `enum`
        case `lazy`
        case `weak`
        case `override`
        case `static`
        case `dynamic`
        case `func`
        case `case`
        case `let`
        case `var`
        case `where`
        case `indirect`
        case `protocol`
    }
    
    init(_ keyword: Swift) {
        self.init(keyword.rawValue)
    }
}
