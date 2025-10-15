import Foundation
import Demangle
import Testing
import MachOSymbols
@testable import MachOSwiftSection
@testable import SwiftInterface
@testable import MachOTestingSupport
import Dependencies
@_spi(Internals) import MachOSymbols

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
        var variableNodePrinter = VariableNodePrinter(isStored: false, isOverride: false, hasSetter: true, indentation: 0)
        try variableNodePrinter.printRoot(#require(variableNode.children.first)).string.print()
    }

    @Test func functionNodes() throws {
        let demangledSymbols = symbolIndexStore.memberSymbols(of: .function(inExtension: true, isStatic: true), in: machOFileInCache)

        for demangledSymbol in demangledSymbols {
            let node = demangledSymbol.demangledNode
            do {
                var printer = FunctionNodePrinter(isOverride: false)
                "Mangled  : \(demangledSymbol.symbol.name)".print()
                "Demangled: \(node.print(using: .interface))".print()
                try "Interface: \(printer.printRoot(#require(node.children.first)).string)".print()
            } catch {
                "Error printing node: \(node.print(using: .default))".print()
            }
            "--------------------".print()
        }
    }

    @Test func typeNodes() async throws {
        let machO = machOFileInMainCache
        let associatedTypes = try machO.swift.associatedTypes
        for associatedType in associatedTypes {
            for record in associatedType.records {
                let substitutedTypeNameMangledName = try record.substitutedTypeName(in: machO)
                let node = try MetadataReader.demangleType(for: substitutedTypeNameMangledName, in: machO)
                do {
                    var printer = TypeNodePrinter()
                    "Demangled: \(node.print(using: .interface))".print()
                    try "Interface: \(printer.printRoot(node).string)".print()
                    "Node: \(node)".print()
                } catch {
                    "Error printing node: \(node.print(using: .default))".print()
                }
                "--------------------".print()
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
                var printer = SubscriptNodePrinter(isOverride: false, hasSetter: false, indentation: 1)
                "Mangled  : \(demangledSymbol.symbol.name)".print()
                "Demangled: \(node.print(using: .interface))".print()
                try "Interface: \(printer.printRoot(node).string)".print()
            } catch {
                "Error printing node: \(node.print(using: .default))".print()
            }
            "--------------------".print()
        }
    }
}
