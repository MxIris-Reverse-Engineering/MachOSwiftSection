import Foundation
import Demangle
import Testing
import MachOSymbols
@testable import MachOSwiftSection
@testable import SwiftInterface
@testable import MachOTestingSupport

@Suite
final class NodePrinterTests: DyldCacheTests {
    
    override class var cacheImageName: MachOImageName { .SwiftUICore }
    
    @Test func functionNode() async throws {
        let node = try demangleAsNode("_$s7SwiftUI19NSViewRepresentableP14_layoutOptionsyAA013_PlatformViewd6LayoutF0V0C4TypeQzFZ")
        var printer = FunctionNodePrinter()
        try printer.printRoot(node.children.first!).string.print()
    }

    @Test func variableNode() async throws {
        let variableNode = try demangleAsNode("_$s7SwiftUI38HostingViewTransparentBackgroundReasonVs10SetAlgebraAAsADP7isEmptySbvgTW")
        var variableNodePrinter = VariableNodePrinter(hasSetter: true, indentation: 0)
        try variableNodePrinter.printRoot(#require(variableNode.children.first)).string.print()
    }

    @Test func functionNodes() throws {
        let demangledSymbols = SymbolIndexStore.shared.memberSymbols(of: .staticFunctionInExtension, in: machOFileInCache)

        for demangledSymbol in demangledSymbols {
            let node = demangledSymbol.demangledNode
            do {
                var printer = FunctionNodePrinter()
                print("Mangled  : \(demangledSymbol.symbol.stringValue)")
                print("Demangled: \(node.print(using: .interface))")
                try print("Interface: \(printer.printRoot(#require(node.children.first)).string)")
            } catch {
                print("Error printing node: \(node.print(using: .default))")
            }
            print("--------------------")
        }
    }
    
    @Test func typeNodes() async throws {
        let machO = machOFileInMainCache
        let associatedTypes = try machO.swift.associatedTypes
        for associatedType in associatedTypes {
            for record in associatedType.records {
                let substitutedTypeNameMangledName = try record.substitutedTypeName(in: machO)
                let node = try MetadataReader.demangle(for: substitutedTypeNameMangledName, in: machO)
                do {
                    var printer = TypeNodePrinter()
                    print("Demangled: \(node.print(using: .interface))")
                    try print("Interface: \(printer.printRoot(node).string)")
                    print("Node: \(node)")
                } catch {
                    print("Error printing node: \(node.print(using: .default))")
                }
                print("--------------------")
            }
        }
    }
}
