import Foundation
import Testing
@testable import Demangle
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import Dependencies

@Suite
final class DyldCacheSymbolRemangleTests: DyldCacheSymbolTests {
    @MainActor
    @Test func debugNestedGeneric() throws {
        // Test nested generic type with wrong order
        let testSymbol = "_$s7SwiftUI22ScrollBehaviorModifier33_B8A1805B47C89D6545C6C966F85D8BC6LLV16LayoutRoleFilterVyx_G14AttributeGraph4RuleAahIP12initialValue0W0QzSgvgZTW"
        print("\n========== DEBUG NESTED GENERIC ==========")
        print("Original symbol: \(testSymbol)")

        let node = try demangleAsNode(testSymbol)
        print("\nNode tree (first 100 lines):")
        let desc = node.description
        let lines = desc.split(separator: "\n")
        for (i, line) in lines.prefix(100).enumerated() {
            print("\(i): \(line)")
        }

        let remangledString = try remangleThrows(node)
        print("\nRemangled: \(remangledString)")
        print("Original:  \(testSymbol)")
        print("Match: \(remangledString == testSymbol)")

        // Find the difference
        if remangledString != testSymbol {
            let minLen = min(testSymbol.count, remangledString.count)
            for i in 0 ..< minLen {
                let origIdx = testSymbol.index(testSymbol.startIndex, offsetBy: i)
                let remIdx = remangledString.index(remangledString.startIndex, offsetBy: i)
                if testSymbol[origIdx] != remangledString[remIdx] {
                    print("\nFirst diff at position \(i):")
                    let start = max(0, i - 15)
                    let end = min(minLen, i + 15)
                    let origStartIdx = testSymbol.index(testSymbol.startIndex, offsetBy: start)
                    let origEndIdx = testSymbol.index(testSymbol.startIndex, offsetBy: end)
                    let remStartIdx = remangledString.index(remangledString.startIndex, offsetBy: start)
                    let remEndIdx = remangledString.index(remangledString.startIndex, offsetBy: end)
                    print("  Original:  ...\(testSymbol[origStartIdx ..< origEndIdx])...")
                    print("  Remangled: ...\(remangledString[remStartIdx ..< remEndIdx])...")
                    break
                }
            }
        }
        print("==========================================\n")
    }

    @MainActor
    @Test func debugTupleLabels() throws {
        // Test symbol with tuple label ordering issue
        let testSymbol = "_$s7SwiftUI24PlatformItemListFlagsSetVs0G7AlgebraAAsADP6insertySb8inserted_7ElementQz17memberAfterInserttAInFTW"
        print("\n========== DEBUG TUPLE LABELS ==========")
        print("Original symbol: \(testSymbol)")

        let node = try demangleAsNode(testSymbol)
        print("\nNode tree:")
        print(node.description)

        // Find the Tuple node and examine its structure
        func findTuple(_ n: Node) -> Node? {
            if n.kind == .tuple {
                return n
            }
            for child in n.children {
                if let found = findTuple(child) {
                    return found
                }
            }
            return nil
        }

        if let tuple = findTuple(node) {
            print("\n=== Tuple Details ===")
            print("Children count: \(tuple.children.count)")
            for (i, child) in tuple.children.enumerated() {
                print("Child \(i): kind=\(child.kind), children=\(child.children.count)")
                if child.kind == .tupleElement {
                    for (j, grandchild) in child.children.enumerated() {
                        print("  [\(j)] \(grandchild.kind) - \(grandchild.text ?? "no text")")
                    }
                }
            }
            print("=====================\n")
        }

        let remangledString = try remangleThrows(node)
        print("\nRemangled: \(remangledString)")
        print("Original:  \(testSymbol)")
        print("Match: \(remangledString == testSymbol)")
        print("========================================\n")
    }

    @MainActor
    @Test func debugExtraC() throws {
        // Test symbol with extra 'c' issue
        let testSymbol = "_$ss8RangeSetV7SwiftUISxRzSZ6StrideRpzrlE6insertyyxF"
        print("\n========== DEBUG EXTRA 'c' ISSUE ==========")
        print("Original symbol: \(testSymbol)")

        let node = try demangleAsNode(testSymbol)
        print("\nNode tree:")
        print(node.description)

        // Find the ArgumentTuple node and examine its structure
        func findArgumentTuple(_ n: Node) -> Node? {
            if n.kind == .argumentTuple {
                return n
            }
            for child in n.children {
                if let found = findArgumentTuple(child) {
                    return found
                }
            }
            return nil
        }

        if let argTuple = findArgumentTuple(node) {
            print("\n=== ArgumentTuple Details ===")
            print("Index: \(argTuple.index.map { String($0) } ?? "nil")")
            print("Children count: \(argTuple.children.count)")
            if argTuple.children.count > 0 {
                let child0 = argTuple.children[0]
                print("Child 0 kind: \(child0.kind)")
                print("Child 0 children count: \(child0.children.count)")
                if child0.children.count > 0 {
                    let grandchild = child0.children[0]
                    print("Grandchild kind: \(grandchild.kind)")
                    print("Grandchild children count: \(grandchild.children.count)")
                }
            }
            print("=============================\n")
        }

        let remangledString = try remangleThrows(node)
        print("\nRemangled: \(remangledString)")
        print("Original:  \(testSymbol)")
        print("Match: \(remangledString == testSymbol)")

        if remangledString != testSymbol {
            print("\nFinding difference...")
            let minLen = min(testSymbol.count, remangledString.count)
            for i in 0 ..< minLen {
                let origIdx = testSymbol.index(testSymbol.startIndex, offsetBy: i)
                let remIdx = remangledString.index(remangledString.startIndex, offsetBy: i)
                if testSymbol[origIdx] != remangledString[remIdx] {
                    print("First difference at position \(i):")
                    let start = max(0, i - 10)
                    let end = min(minLen, i + 10)
                    let origStartIdx = testSymbol.index(testSymbol.startIndex, offsetBy: start)
                    let origEndIdx = testSymbol.index(testSymbol.startIndex, offsetBy: end)
                    let remStartIdx = remangledString.index(remangledString.startIndex, offsetBy: start)
                    let remEndIdx = remangledString.index(remangledString.startIndex, offsetBy: end)
                    print("  Original:  ...\(testSymbol[origStartIdx ..< origEndIdx])...")
                    print("  Remangled: ...\(remangledString[remStartIdx ..< remEndIdx])...")
                    break
                }
            }
        }
        print("========================================\n")
    }

    @MainActor
    @Test func debugSubstitution() throws {
        // Test symbol with substitution - `s0G7Algebra` means SetAlgebra was previously seen
        let testSymbol = "_$s7SwiftUI24PlatformItemListFlagsSetVs0G7AlgebraAAsADPxycfCTW"
        print("\n========== DEBUG SUBSTITUTION ==========")
        print("Original symbol: \(testSymbol)")
        print("")
        print("Key: s0G7Algebra")
        print("- '0G' is substitution index 6 (AA=0, AB=1, AC=2, AD=3, AE=4, AF=5, AG=6)")
        print("- This means SetAlgebra appeared earlier and should use subst reference")
        print("")

        let node = try demangleAsNode(testSymbol)

        // Count how many times Protocol nodes appear with SetAlgebra
        var setAlgebraCount = 0
        func countSetAlgebra(_ n: Node) {
            if n.kind == .protocol {
                if n.children.count >= 2, n.children[1].kind == .identifier, n.children[1].text == "SetAlgebra" {
                    setAlgebraCount += 1
                    print("Found SetAlgebra protocol at depth, count: \(setAlgebraCount)")
                }
            }
            for child in n.children {
                countSetAlgebra(child)
            }
        }
        countSetAlgebra(node)
        print("Total SetAlgebra occurrences: \(setAlgebraCount)")
        print("")

        let remangledString = try remangleThrows(node)
        print("Remangled: \(remangledString)")
        print("Original:  \(testSymbol)")
        print("Match: \(remangledString == testSymbol)")
        print("========================================\n")
    }

    @MainActor
    @Test func debugSingleSymbol() throws {
        let testSymbol = "_$s7SwiftUI24PlatformItemListFlagsSetVs0G7AlgebraAAsADPxycfCTW"
        print("\n========== DEBUG SINGLE SYMBOL ==========")
        print("Original symbol: \(testSymbol)")

        let node = try demangleAsNode(testSymbol)
        print("\nNode tree:")
        print(node.description)

        let remangledString = try remangleThrows(node)
        print("\nRemangled: \(remangledString)")
        print("Original:  \(testSymbol)")
        print("Match: \(remangledString == testSymbol)")

        if remangledString != testSymbol {
            print("\nFinding difference...")
            let minLen = min(testSymbol.count, remangledString.count)
            for i in 0 ..< minLen {
                let origIdx = testSymbol.index(testSymbol.startIndex, offsetBy: i)
                let remIdx = remangledString.index(remangledString.startIndex, offsetBy: i)
                if testSymbol[origIdx] != remangledString[remIdx] {
                    print("First difference at position \(i):")
                    let start = max(0, i - 10)
                    let end = min(minLen, i + 10)
                    let origStartIdx = testSymbol.index(testSymbol.startIndex, offsetBy: start)
                    let origEndIdx = testSymbol.index(testSymbol.startIndex, offsetBy: end)
                    let remStartIdx = remangledString.index(remangledString.startIndex, offsetBy: start)
                    let remEndIdx = remangledString.index(remangledString.startIndex, offsetBy: end)
                    print("  Original:  ...\(testSymbol[origStartIdx ..< origEndIdx])...")
                    print("  Remangled: ...\(remangledString[remStartIdx ..< remEndIdx])...")
                    break
                }
            }
        }
        print("========================================\n")
    }

    @MainActor
    @Test func debugAssociatedType() throws {
        // Test associated type reference - x5ValueQa vs 0I0Qz
        let testSymbol = "_$s7SwiftUI30AccessibilityRelationshipScopeCAA11PropertyKeyA2aDP12defaultValue0I0QzvgZTW"
        print("\n========== DEBUG ASSOCIATED TYPE ==========")
        print("Original symbol: \(testSymbol)")
        print("Expected pattern: 0I0Qz (DependentAssociatedTypeRef with substitution)")
        print("")

        let node = try demangleAsNode(testSymbol)
        print("Full node tree:")
        print(node.description)
        print("")

        print("Searching for DependentAssociatedTypeRef and related nodes:")
        func findAssocTypeRef(_ n: Node, depth: Int = 0, path: String = "") {
            let indent = String(repeating: "  ", count: depth)
            let currentPath = path + "/" + n.kind.description

            if n.kind == .dependentAssociatedTypeRef || n.kind == .dependentMemberType {
                print("\(indent)Found \(n.kind):")
                print("\(indent)  Path: \(currentPath)")
                print("\(indent)  Children: \(n.children.count)")
                for (i, child) in n.children.enumerated() {
                    print("\(indent)    [\(i)] \(child.kind) - \(child.text ?? "nil") - index: \(child.index.map { String($0) } ?? "nil")")
                }
            }
            for child in n.children {
                findAssocTypeRef(child, depth: depth + 1, path: currentPath)
            }
        }
        findAssocTypeRef(node)

        let remangledString = try remangleThrows(node)
        print("\nRemangled: \(remangledString)")
        print("Original:  \(testSymbol)")
        print("Match: \(remangledString == testSymbol)")
        print("==========================================\n")
    }

    @MainActor
    @Test func symbols() throws {
        let allSwiftSymbols = try symbols(for: .SwiftUI, .SwiftUICore)
        "Total Swift Symbols: \(allSwiftSymbols.count)".print()
        for symbol in allSwiftSymbols {
            let swiftStdlibDemangledName = stdlib_demangleName(symbol.stringValue)
            do {
                let node = try demangleAsNode(symbol.stringValue)
                let swiftSectionDemanlgedName = node.print()
                #expect(swiftStdlibDemangledName == swiftSectionDemanlgedName, "\(symbol.stringValue)")
                let remangledString = try remangleThrows(node)
                #expect(remangledString == symbol.stringValue)
            } catch {
                symbol.stringValue.print()
                if symbol.stringValue != swiftStdlibDemangledName {
                    Issue.record(error)
                }
            }
        }
    }
}
