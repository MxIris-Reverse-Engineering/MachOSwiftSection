import Foundation
import Testing
import MachOKit
import MachOSwiftSection
import Demangling
@testable import CrossReferenceAnalysis

/// The names a function gets when the symbol table has none: the export
/// trie, the Objective-C method lists, the Swift metadata. Each source is
/// checked against the symbols where both exist. The images are picked for
/// what macOS 27.2 strips from them — SiriAppIntents' symbol table, Matter's
/// method symbols — so an update that strips them differently moves them.
@Suite(.enabled(if: SharedAnalyzer.analyzer != nil, "needs an arm64 process with a dyld shared cache"))
struct FallbackNamingTests {
    private var analyzer: CrossReferenceAnalyzer { SharedAnalyzer.analyzer! }

    private func imageIndex(endingWith suffix: String) throws -> Int {
        try #require(analyzer.imagePaths.firstIndex { $0.hasSuffix(suffix) }, "no image ending with \(suffix)")
    }

    /// SiriAppIntents' symbol table holds two entries; its export trie names
    /// tens of thousands of its functions. Every exported function start is
    /// named by its export.
    @Test func exportTrieNamesWhatTheSymbolTableDoesNot() throws {
        let siriAppIntents = try imageIndex(endingWith: "/SiriAppIntents.framework/Versions/A/SiriAppIntents")
        let table = analyzer.functionTable(ofImageAt: siriAppIntents)
        let exports = analyzer.images[siriAppIntents].exportedSymbols.compactMap { symbol -> (UInt64, String)? in
            guard let offset = symbol.offset else { return nil }
            let address = UInt64(bitPattern: Int64(bitPattern: table.headerAddress) &+ Int64(offset))
            return (address >= table.textStart && address < table.textEnd) ? (address, symbol.name) : nil
        }
        #expect(exports.count > 1000)
        var checked = 0
        for (address, name) in exports.prefix(300) {
            let function = try #require(analyzer.function(containing: CodeLocation(imageIndex: siriAppIntents, address: address)))
            guard function.location.address == address else { continue }
            checked += 1
            let names = [function.name].compactMap { name -> String? in
                if case .symbol(let symbol)? = name { return symbol }
                return nil
            } + function.foldedSymbolNames
            #expect(names.contains(name), "\(name) at 0x\(String(address, radix: 16)) named \(String(describing: function.name))")
        }
        #expect(checked > 200)
    }

    /// Where AppKit's symbol table names a method `-[Class(Category) sel]`,
    /// the method lists name the same address `-[Class sel]`.
    @Test func methodListsAgreeWithMethodSymbols() throws {
        let appKit = try imageIndex(endingWith: "/AppKit.framework/Versions/C/AppKit")
        let table = analyzer.functionTable(ofImageAt: appKit)
        let methods = table.fallbackNames.objectiveCMethods()
        #expect(methods.count > 50000)
        var compared = 0
        var agreeing = 0
        for index in table.starts.indices {
            guard let name = table.primaryName(ofFunctionAt: index), name[1] == 0x5B, name[0] == 0x2D || name[0] == 0x2B,
                  let method = methods[table.starts[index]]
            else { continue }
            compared += 1
            let symbol = String(cString: name)
            if symbol == Self.withoutCategory("\(method.isClassMethod ? "+" : "-")[\(method.className) \(method.selector)]") ||
                Self.withoutCategory(symbol) == "\(method.isClassMethod ? "+" : "-")[\(method.className) \(method.selector)]" {
                agreeing += 1
            }
        }
        #expect(compared > 50000)
        #expect(Double(agreeing) / Double(max(compared, 1)) > 0.999, "\(agreeing) of \(compared) agree")
    }

    /// An image whose Objective-C methods carry no symbols gets them named
    /// from the method lists.
    @Test func methodListsNameUnsymbolizedMethods() throws {
        let matter = try imageIndex(endingWith: "/Matter.framework/Versions/A/Matter")
        let methodNames = analyzer.functions(inImageAt: matter).filter {
            if case .objectiveCMethod? = $0.name { return true }
            return false
        }
        #expect(methodNames.count > 10000)
    }

    /// Where SwiftUICore's symbol table names a metadata accessor, a
    /// singleton completion function or a vtable implementation, the name
    /// rebuilt from the metadata is the same symbol.
    @Test func swiftMetadataNamesMatchTheirSymbols() throws {
        let swiftUICore = try imageIndex(endingWith: "/SwiftUICore.framework/Versions/A/SwiftUICore")
        let table = analyzer.functionTable(ofImageAt: swiftUICore)
        var compared = 0
        var agreeing = 0
        var mismatches: [String] = []
        for index in table.starts.indices {
            guard let name = table.primaryName(ofFunctionAt: index),
                  let rebuilt = table.fallbackNames.swiftName(at: table.starts[index])
            else { continue }
            compared += 1
            let symbol = String(cString: name)
            let folded = table.foldedNames[table.starts[index]]?.map { String(cString: $0) } ?? []
            if ([symbol] + folded).contains("_" + rebuilt) {
                agreeing += 1
            } else if mismatches.count < 5 {
                mismatches.append("\(symbol) vs \(rebuilt)")
            }
        }
        #expect(compared > 5000)
        #expect(Double(agreeing) / Double(max(compared, 1)) > 0.99, "\(agreeing) of \(compared) agree; e.g. \(mismatches)")
    }

    /// In a Swift image with no symbol table to speak of, every type's
    /// metadata accessor is named: a public type's by the export trie, any
    /// other's rebuilt from its descriptor — and a rebuilt name demangles to
    /// a metadata accessor.
    @Test func everyAccessorOfAnUnsymbolizedImageIsNamed() throws {
        let siriAppIntents = try imageIndex(endingWith: "/SiriAppIntents.framework/Versions/A/SiriAppIntents")
        let functions = analyzer.functions(inImageAt: siriAppIntents)
        let rebuiltAccessorNames = functions.compactMap { function -> String? in
            guard case .swiftMetadata(let mangledName)? = function.name, mangledName.hasSuffix("Ma") else { return nil }
            return mangledName
        }
        let exportedAccessorCount = functions.filter {
            guard case .symbol(let symbol)? = $0.name else { return false }
            return symbol.hasPrefix("_$s") && symbol.hasSuffix("Ma")
        }.count
        let typeCount = try analyzer.images[siriAppIntents].swift.typeContextDescriptors.count
        #expect(rebuiltAccessorNames.count > 100)
        #expect(
            exportedAccessorCount + rebuiltAccessorNames.count >= typeCount * 9 / 10,
            "\(exportedAccessorCount) exported and \(rebuiltAccessorNames.count) rebuilt accessor names for \(typeCount) types"
        )
        for mangledName in rebuiltAccessorNames.prefix(200) {
            let node = try demangleAsNode(mangledName)
            #expect(node.children.first?.kind == .typeMetadataAccessFunction, "\(mangledName)")
        }
    }

    private static func withoutCategory(_ methodName: String) -> String {
        guard let open = methodName.firstIndex(of: "("), let close = methodName.firstIndex(of: ")"), open < close else { return methodName }
        return String(methodName[..<open] + methodName[methodName.index(after: close)...])
    }
}
