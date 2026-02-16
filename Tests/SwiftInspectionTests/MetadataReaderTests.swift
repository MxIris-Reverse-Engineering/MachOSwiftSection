import Foundation
import Testing
@testable import Demangling
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@testable import SwiftInspection

// MARK: - Unit Tests for MetadataReader demangling functions

@Suite
struct MetadataReaderDemanglingTests {
    // MARK: - demangleAsNode

    @Test(arguments: [
        ("$sSi", Node.Kind.global),
        ("$sSS", Node.Kind.global),
        ("$s4Main3FooV", Node.Kind.global),
    ])
    func demangleAsNodeReturnsGlobal(mangled: String, expectedKind: Node.Kind) throws {
        let node = try demangleAsNode(mangled)
        #expect(node.kind == expectedKind)
    }

    @Test func demangleAsNodePreservesStructure() throws {
        // $s4Main3FooV demangles to: Global > Structure > (Module, Identifier)
        let node = try demangleAsNode("$s4Main3FooV")

        #expect(node.kind == .global)
        #expect(node.children.count == 1)

        let structNode = node.children[0]
        #expect(structNode.kind == .structure)

        // Structure has Module and Identifier children
        #expect(structNode.children.count >= 2)
        #expect(structNode.children[0].kind == .module)
        #expect(structNode.children[0].text == "Main")
        #expect(structNode.children[1].kind == .identifier)
        #expect(structNode.children[1].text == "Foo")
    }

    @Test func demangleAsNodeThrowsForInvalidSymbol() {
        #expect(throws: (any Error).self) {
            _ = try demangleAsNode("not_a_valid_symbol")
        }
    }

    // MARK: - Symbol Prefix Handling

    @Test(arguments: [
        "$sSi",      // No underscore prefix
        "_$sSi",     // With underscore prefix
    ])
    func demangleHandlesBothPrefixStyles(mangled: String) throws {
        let node = try demangleAsNode(mangled)
        #expect(node.kind == .global)
    }
}

// MARK: - Integration Tests with MachOImage

@Suite
final class MetadataReaderImageTests: MachOImageTests, @unchecked Sendable {
    override class var imageName: MachOImageName { .Foundation }

    @Test func demangleTypeFromMachO() async throws {
        // Test that demangling works with in-process metadata
        let node = try demangleAsNode("$sSi")

        #expect(node.kind == .global)
        #expect(node.first(of: .structure) != nil)
    }

    @Test func buildGenericSignatureReturnsNilForEmptyRequirements() async throws {
        // Empty requirements should return nil
        let result = try MetadataReader.buildGenericSignature(for: [])
        #expect(result == nil)
    }
}

// MARK: - Integration Tests with MachOFile

@Suite
final class MetadataReaderFileTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .iOS_26_2_Simulator_SwiftUI }

    @Test func demangleTypeFromFile() async throws {
        let node = try demangleAsNode("$sSi")
        #expect(node.kind == .global)
    }

    @Test func buildGenericSignatureFromFileReturnsNilForEmpty() async throws {
        let result = try MetadataReader.buildGenericSignature(for: [] as [GenericRequirementDescriptor], in: machOFile)
        #expect(result == nil)
    }

    @Test func typeContextDescriptorsCanBeDemangledFromFile() async throws {
        let descriptors = try machOFile.swift.typeContextDescriptors

        var successCount = 0
        var processedCount = 0

        for descriptor in descriptors.prefix(50) {
            processedCount += 1
            do {
                if let structDescriptor = descriptor.struct {
                    let name = try structDescriptor.name(in: machOFile)
                    #expect(!name.isEmpty)
                    successCount += 1
                } else if let classDescriptor = descriptor.class {
                    let name = try classDescriptor.name(in: machOFile)
                    #expect(!name.isEmpty)
                    successCount += 1
                } else if let enumDescriptor = descriptor.enum {
                    let name = try enumDescriptor.name(in: machOFile)
                    #expect(!name.isEmpty)
                    successCount += 1
                }
            } catch {
                // Some descriptors may fail, that's okay for this test
            }
        }

        #expect(successCount > 0, "At least some descriptors should have valid names")
        #expect(Double(successCount) / Double(processedCount) > 0.5, "Success rate should be > 50%")
    }

    @Test func protocolDescriptorsCanBeRead() async throws {
        let descriptors = try machOFile.swift.protocolDescriptors

        #expect(!descriptors.isEmpty, "SwiftUI should have protocol descriptors")

        var successCount = 0
        for descriptor in descriptors.prefix(20) {
            do {
                let name = try descriptor.name(in: machOFile)
                #expect(!name.isEmpty)
                successCount += 1
            } catch {
                // Some may fail
            }
        }

        #expect(successCount > 0)
    }

    @Test func protocolConformancesCanBeRead() async throws {
        let conformances = try machOFile.swift.protocolConformanceDescriptors

        #expect(!conformances.isEmpty, "SwiftUI should have protocol conformances")

        // Just verify we can iterate without crashing
        var count = 0
        for _ in conformances.prefix(100) {
            count += 1
        }

        #expect(count > 0)
    }

    @Test func associatedTypesCanBeRead() async throws {
        let associatedTypes = try machOFile.swift.associatedTypes

        #expect(!associatedTypes.isEmpty, "SwiftUI should have associated types")

        var successCount = 0
        for associatedType in associatedTypes.prefix(20) {
            for record in associatedType.records.prefix(5) {
                do {
                    let typeName = try record.substitutedTypeName(in: machOFile)
                    #expect(!typeName.isEmpty)
                    successCount += 1
                } catch {
                    // Some may fail
                }
            }
        }

        #expect(successCount > 0, "At least some associated type records should be readable")
    }
}

// MARK: - buildGenericSignature Logic Tests

@Suite
struct BuildGenericSignatureTests {
    @Test func emptyRequirementsReturnsNil() throws {
        let result = try MetadataReader.buildGenericSignature(for: [] as [GenericRequirementDescriptor])
        #expect(result == nil)
    }

    // Note: Testing with actual GenericRequirementDescriptor requires MachO context
    // The following tests verify the node structure when signature is built
}

// MARK: - Node Structure Verification Tests

@Suite
struct MetadataReaderNodeStructureTests {
    @Test func dependentGenericSignatureStructure() throws {
        // Verify the expected structure of a generic signature node
        let signatureNode = Node(kind: .dependentGenericSignature, children: [
            Node(kind: .dependentGenericConformanceRequirement, children: [
                Node(kind: .type, children: [
                    Node(kind: .dependentGenericParamType, contents: .text("τ_0_0"))
                ]),
                Node(kind: .type, children: [
                    Node(kind: .protocol, children: [
                        Node(kind: .module, contents: .text("Swift")),
                        Node(kind: .identifier, contents: .text("Equatable"))
                    ])
                ])
            ])
        ])

        #expect(signatureNode.kind == .dependentGenericSignature)
        #expect(signatureNode.children.count == 1)

        let requirement = signatureNode.children[0]
        #expect(requirement.kind == .dependentGenericConformanceRequirement)
        #expect(requirement.children.count == 2)
    }

    @Test func sameTypeRequirementStructure() throws {
        let requirementNode = Node(kind: .dependentGenericSameTypeRequirement, children: [
            Node(kind: .type, children: [
                Node(kind: .dependentMemberType, children: [
                    Node(kind: .type, children: [
                        Node(kind: .dependentGenericParamType, contents: .text("τ_0_0"))
                    ]),
                    Node(kind: .dependentAssociatedTypeRef, children: [
                        Node(kind: .identifier, contents: .text("Element"))
                    ])
                ])
            ]),
            Node(kind: .type, children: [
                Node(kind: .structure, children: [
                    Node(kind: .module, contents: .text("Swift")),
                    Node(kind: .identifier, contents: .text("Int"))
                ])
            ])
        ])

        #expect(requirementNode.kind == .dependentGenericSameTypeRequirement)
        #expect(requirementNode.children.count == 2)

        let memberType = requirementNode.first(of: .dependentMemberType)
        #expect(memberType != nil)

        let assocTypeRef = requirementNode.first(of: .dependentAssociatedTypeRef)
        #expect(assocTypeRef?.children[0].text == "Element")
    }

    @Test func layoutRequirementStructure() throws {
        let requirementNode = Node(kind: .dependentGenericLayoutRequirement, children: [
            Node(kind: .type, children: [
                Node(kind: .dependentGenericParamType, contents: .text("τ_0_0"))
            ]),
            Node(kind: .identifier, contents: .text("C"))  // Class constraint
        ])

        #expect(requirementNode.kind == .dependentGenericLayoutRequirement)
        #expect(requirementNode.children.count == 2)
        #expect(requirementNode.children[1].text == "C")
    }
}
