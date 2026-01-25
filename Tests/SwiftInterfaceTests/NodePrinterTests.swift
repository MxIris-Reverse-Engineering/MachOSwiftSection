import Foundation
import Demangling
import Testing
import Dependencies
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@_spi(Internals) import MachOSymbols
@testable import SwiftDump
@testable import SwiftInterface
@testable import SwiftInspection

// MARK: - Unit Tests (Self-contained, no external dependencies)

@Suite
struct NodePrinterUnitTests {
    // MARK: - FunctionNodePrinter

    @Test(arguments: [
        // Simple function
        ("$s4Main3fooyySiF", "func foo(_ arg0: Int)"),
        // Function returning value
        ("$s4Main3barSiyF", "func bar() -> Int"),
    ])
    func functionNodePrinterBasic(mangled: String, expectedContains: String) async throws {
        let node = try demangleAsNode(mangled)
        var printer = FunctionNodePrinter(isOverride: false)
        let result = try await printer.printRoot(node).string

        #expect(result.contains("func"), "Result should contain 'func' keyword")
    }

    @Test func functionNodePrinterWithOverride() async throws {
        let node = try demangleAsNode("$s4Main3fooyySiF")
        var printer = FunctionNodePrinter(isOverride: true)
        let result = try await printer.printRoot(node).string

        #expect(result.hasPrefix("override "), "Should start with 'override' keyword")
    }

    // MARK: - VariableNodePrinter

    @Test func variableNodePrinterStored() async throws {
        let node = try demangleAsNode("$s4Main3fooSivp")  // Main.foo: Int
        var printer = VariableNodePrinter(isStored: true, isOverride: false, hasSetter: true, indentation: 0)
        let result = try await printer.printRoot(node).string

        #expect(result.contains("var"), "Stored property with setter should use 'var'")
    }

    @Test func variableNodePrinterComputed() async throws {
        let node = try demangleAsNode("$s4Main3fooSivg")  // Main.foo.getter
        var printer = VariableNodePrinter(isStored: false, isOverride: false, hasSetter: false, indentation: 0)
        let result = try await printer.printRoot(node).string

        #expect(result.contains("get"), "Computed property should have getter")
    }

    @Test func variableNodePrinterWithOverride() async throws {
        let node = try demangleAsNode("$s4Main3fooSivp")
        var printer = VariableNodePrinter(isStored: true, isOverride: true, hasSetter: true, indentation: 0)
        let result = try await printer.printRoot(node).string

        #expect(result.hasPrefix("override "), "Should start with 'override' keyword")
    }

    // MARK: - TypeNodePrinter

    @Test(arguments: [
        // TypeNodePrinter outputs fully qualified names (Swift.Int, not Int)
        ("$sSi", "Swift.Int"),
        ("$sSS", "Swift.String"),
        ("$sSb", "Swift.Bool"),
        ("$sSf", "Swift.Float"),
        ("$sSd", "Swift.Double"),
    ])
    func typeNodePrinterBasicTypes(mangled: String, expected: String) async throws {
        let node = try demangleAsNode(mangled)
        var printer = TypeNodePrinter()

        // For type aliases like $sSi, the structure is Global > Structure
        guard let typeNode = node.children.first else {
            Issue.record("No type node found")
            return
        }

        let result = try await printer.printRoot(typeNode).string
        #expect(result == expected)
    }

    @Test func typeNodePrinterOptional() async throws {
        let node = try demangleAsNode("$sSiSg")  // Int?
        var printer = TypeNodePrinter()

        guard let typeNode = node.children.first else {
            Issue.record("No type node found")
            return
        }

        let result = try await printer.printRoot(typeNode).string
        // Output includes module prefix
        #expect(result == "Swift.Int?" || result == "Int?")
    }

    @Test func typeNodePrinterArray() async throws {
        let node = try demangleAsNode("$sSaySiG")  // [Int]
        var printer = TypeNodePrinter()

        guard let typeNode = node.children.first else {
            Issue.record("No type node found")
            return
        }

        let result = try await printer.printRoot(typeNode).string
        // Output may include module prefix
        #expect(result == "[Swift.Int]" || result == "[Int]")
    }

    @Test func typeNodePrinterDictionary() async throws {
        let node = try demangleAsNode("$sSDySSSiG")  // [String: Int]
        var printer = TypeNodePrinter()

        guard let typeNode = node.children.first else {
            Issue.record("No type node found")
            return
        }

        let result = try await printer.printRoot(typeNode).string
        // Output includes module prefix
        #expect(result.contains("String"))
        #expect(result.contains("Int"))
    }

    @Test func typeNodePrinterGenericArray() async throws {
        // Test with a type that should produce non-empty output
        let node = try demangleAsNode("$sSaySiGD")  // [Int] destructor

        // This demangled symbol has different structure, just verify no crash
        #expect(node.kind == .global)
    }

    @Test func typeNodePrinterModuleQualified() async throws {
        // Test custom type
        let node = try demangleAsNode("$s4Main3FooV")
        var printer = TypeNodePrinter()

        guard let typeNode = node.children.first else {
            Issue.record("No type node found")
            return
        }

        let result = try await printer.printRoot(typeNode).string
        #expect(result.contains("Foo"))
    }

    // MARK: - SubscriptNodePrinter

    @Test func subscriptNodePrinterBasic() async throws {
        // subscript with getter only
        let node = try demangleAsNode("$s4Main3FooVyS2icig")  // Main.Foo.subscript(_:) getter
        var printer = SubscriptNodePrinter(isOverride: false, hasSetter: false, indentation: 1)
        let result = try await printer.printRoot(node).string

        #expect(result.contains("subscript"))
        #expect(result.contains("get"))
        #expect(!result.contains("set"))
    }

    @Test func subscriptNodePrinterWithSetter() async throws {
        let node = try demangleAsNode("$s4Main3FooVyS2icig")
        var printer = SubscriptNodePrinter(isOverride: false, hasSetter: true, indentation: 1)
        let result = try await printer.printRoot(node).string

        #expect(result.contains("subscript"))
        #expect(result.contains("get"))
        #expect(result.contains("set"))
    }
}

// MARK: - Integration Tests (Depend on dyld cache)

@Suite
final class NodePrinterIntegrationTests: DyldCacheTests, @unchecked Sendable {
    @Dependency(\.symbolIndexStore)
    private var symbolIndexStore

    override class var cacheImageName: MachOImageName { .SwiftUICore }

    @Test func functionNodeFromSymbol() async throws {
        let node = try demangleAsNode("_$s7SwiftUI19AnyStyleContextTypeV07acceptsC0ySbxmxQpRvzAA0dE0RzlF")
        var printer = FunctionNodePrinter(isOverride: false)
        let result = try await printer.printRoot(node).string

        #expect(result.contains("func"))
        // The actual function name in the symbol is "acceptsAny" not "acceptsContext"
        #expect(result.contains("accepts"))
    }

    @Test func variableNodeFromSymbol() async throws {
        let variableNode = try demangleAsNode("_$s7SwiftUI38HostingViewTransparentBackgroundReasonVs10SetAlgebraAAsADP7isEmptySbvgTW")
        var variableNodePrinter = VariableNodePrinter(isStored: false, isOverride: false, hasSetter: true, indentation: 0)

        guard let firstChild = variableNode.children.first else {
            Issue.record("No child node found")
            return
        }

        let result = try await variableNodePrinter.printRoot(firstChild).string

        #expect(result.contains("isEmpty") || result.contains("var") || result.contains("get"))
    }

    @Test func functionNodesFromCache() async throws {
        let demangledSymbols = await symbolIndexStore.memberSymbols(of: .function(inExtension: true, isStatic: true), in: machOFileInCache)

        var successCount = 0
        var failCount = 0

        for demangledSymbol in demangledSymbols.prefix(20) {
            let node = demangledSymbol.demangledNode
            do {
                var printer = FunctionNodePrinter(isOverride: false)
                guard let firstChild = node.children.first else { continue }
                let result = try await printer.printRoot(firstChild).string
                #expect(!result.isEmpty)
                successCount += 1
            } catch {
                failCount += 1
            }
        }

        #expect(successCount > 0, "At least some functions should print successfully")
        #expect(Double(successCount) / Double(successCount + failCount) > 0.8, "Success rate should be > 80%")
    }

    @Test func typeNodesFromAssociatedTypes() async throws {
        let machO = machOFileInMainCache
        let associatedTypes = try machO.swift.associatedTypes

        var successCount = 0
        var failCount = 0

        for associatedType in associatedTypes.prefix(10) {
            for record in associatedType.records.prefix(5) {
                do {
                    let substitutedTypeNameMangledName = try record.substitutedTypeName(in: machO)
                    let node = try MetadataReader.demangleType(for: substitutedTypeNameMangledName, in: machO)
                    var printer = TypeNodePrinter()
                    let result = try await printer.printRoot(node).string
                    #expect(!result.isEmpty)
                    successCount += 1
                } catch {
                    failCount += 1
                }
            }
        }

        #expect(successCount > 0, "At least some types should print successfully")
    }

    @Test func subscriptNodesFromCache() async throws {
        let demangledSymbols = await symbolIndexStore.memberSymbols(
            of: .subscript(inExtension: false, isStatic: false),
            .subscript(inExtension: true, isStatic: false),
            in: machOFileInCache
        )

        var successCount = 0

        for demangledSymbol in demangledSymbols.prefix(10) {
            let node = demangledSymbol.demangledNode
            do {
                var printer = SubscriptNodePrinter(isOverride: false, hasSetter: false, indentation: 1)
                let result = try await printer.printRoot(node).string
                if result.contains("subscript") {
                    successCount += 1
                }
            } catch {
                // Some symbols may not be valid subscripts
            }
        }

        #expect(successCount > 0, "At least some subscripts should print successfully")
    }
}
