import Foundation
import Demangle
import Testing
import MachOSymbols
@testable import MachOSwiftSection
@testable import SwiftInterface
@testable import MachOTestingSupport
import Dependencies
@_spi(Internal) import MachOSymbols

@Suite
final class NodePrinterTests: DyldCacheTests, @unchecked Sendable {
    @Dependency(\.symbolIndexStore)
    private var symbolIndexStore

    override class var cacheImageName: MachOImageName { .SwiftUICore }

    @Test func functionNode() async throws {
        let node = try demangleAsNode("_$s7SwiftUI19AnyStyleContextTypeV07acceptsC0ySbxmxQpRvzAA0dE0RzlF")
        var printer = FunctionNodePrinter(isOverride: false)
        try printer.printRoot(node).string.print()
    }

    @Test func variableNode() async throws {
        let variableNode = try demangleAsNode("_$s7SwiftUI38HostingViewTransparentBackgroundReasonVs10SetAlgebraAAsADP7isEmptySbvgTW")
        var variableNodePrinter = VariableNodePrinter(isStored: false, hasSetter: true, indentation: 0)
        try variableNodePrinter.printRoot(#require(variableNode.children.first)).string.print()
    }

    @Test func functionNodes() throws {
        let demangledSymbols = symbolIndexStore.memberSymbols(of: .function(inExtension: true, isStatic: true), in: machOFileInCache)

        for demangledSymbol in demangledSymbols {
            let node = demangledSymbol.demangledNode
            do {
                var printer = FunctionNodePrinter(isOverride: false)
                print("Mangled  : \(demangledSymbol.symbol.name)")
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
    
    @Test func subscriptNodes() async throws {
        let demangledSymbols = symbolIndexStore.memberSymbols(
            of: .subscript(inExtension: false, isStatic: false),
                .subscript(inExtension: true, isStatic: false),
                .subscript(inExtension: false, isStatic: true),
                .subscript(inExtension: true, isStatic: true),
            in: machOFileInCache
        )

        for demangledSymbol in demangledSymbols {
            let node = demangledSymbol.demangledNode
            do {
                var printer = SubscriptNodePrinter(hasSetter: false, indentation: 1)
                print("Mangled  : \(demangledSymbol.symbol.name)")
                print("Demangled: \(node.print(using: .interface))")
                try print("Interface: \(printer.printRoot(node).string)")
            } catch {
                print("Error printing node: \(node.print(using: .default))")
            }
            print("--------------------")
        }
    }
}
