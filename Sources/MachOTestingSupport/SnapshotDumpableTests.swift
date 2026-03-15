import Foundation
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftDump

@MainActor
package protocol SnapshotDumpableTests {}

extension SnapshotDumpableTests {
    package func collectDumpTypes<MachO: MachOSwiftSectionRepresentableWithCache>(
        for machO: MachO,
        options: DumpableTypeOptions = [.enum, .struct, .class],
        using configuration: DumperConfiguration? = nil
    ) async throws -> String {
        let typeContextDescriptors = try machO.swift.typeContextDescriptors
        var results: [String] = []
        for typeContextDescriptor in typeContextDescriptors {
            switch typeContextDescriptor {
            case .enum(let enumDescriptor):
                guard options.contains(.enum) else { continue }
                do {
                    let enumType = try Enum(descriptor: enumDescriptor, in: machO)
                    let output = try await enumType.dump(using: configuration ?? .demangleOptions(.test), in: machO).string
                    results.append(output)
                } catch {
                    results.append("Error: \(error)")
                }
            case .struct(let structDescriptor):
                guard options.contains(.struct) else { continue }
                do {
                    let structType = try Struct(descriptor: structDescriptor, in: machO)
                    let output = try await structType.dump(using: configuration ?? .demangleOptions(.test), in: machO).string
                    results.append(output)
                } catch {
                    results.append("Error: \(error)")
                }
            case .class(let classDescriptor):
                guard options.contains(.class) else { continue }
                do {
                    let classType = try Class(descriptor: classDescriptor, in: machO)
                    let output = try await classType.dump(using: configuration ?? .demangleOptions(.test), in: machO).string
                    results.append(output)
                } catch {
                    results.append("Error: \(error)")
                }
            }
        }
        return results.joined(separator: "\n")
    }

    package func collectDumpProtocols<MachO: MachOSwiftSectionRepresentableWithCache>(
        for machO: MachO
    ) async throws -> String {
        let protocolDescriptors = try machO.swift.protocolDescriptors
        var results: [String] = []
        for protocolDescriptor in protocolDescriptors {
            do {
                let output = try await Protocol(descriptor: protocolDescriptor, in: machO)
                    .dump(using: .demangleOptions(.test), in: machO).string
                results.append(output)
            } catch {
                results.append("Error: \(error)")
            }
        }
        return results.joined(separator: "\n")
    }

    package func collectDumpProtocolConformances<MachO: MachOSwiftSectionRepresentableWithCache>(
        for machO: MachO
    ) async throws -> String {
        let protocolConformanceDescriptors = try machO.swift.protocolConformanceDescriptors
        var results: [String] = []
        for protocolConformanceDescriptor in protocolConformanceDescriptors {
            do {
                let output = try await ProtocolConformance(descriptor: protocolConformanceDescriptor, in: machO)
                    .dump(using: .demangleOptions(.test), in: machO).string
                results.append(output)
            } catch {
                results.append("Error: \(error)")
            }
        }
        return results.joined(separator: "\n")
    }

    package func collectDumpAssociatedTypes<MachO: MachOSwiftSectionRepresentableWithCache>(
        for machO: MachO
    ) async throws -> String {
        let associatedTypeDescriptors = try machO.swift.associatedTypeDescriptors
        var results: [String] = []
        for associatedTypeDescriptor in associatedTypeDescriptors {
            do {
                let output = try await AssociatedType(descriptor: associatedTypeDescriptor, in: machO)
                    .dump(using: .demangleOptions(.test), in: machO).string
                results.append(output)
            } catch {
                results.append("Error: \(error)")
            }
        }
        return results.joined(separator: "\n")
    }
}
