@_spi(Support) @testable import SwiftSpecialization
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
import Foundation
import Testing
import MachOKit
import Demangling
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
import MachOTestingSupport

/// A host type with no conformance any indexed image records.
private struct HostUnmarked {
    var value: Int
}

/// A host class outside every fixture hierarchy.
private final class HostUnrelatedClass {}

/// `GenericSpecializer`'s offline execution on a `MachOFile` (evolution
/// proposal `offline-generic-specialization`): the request, the binding and
/// name a specialization produces, and `staticPreflight`'s two kinds of
/// outcome — an error for a requirement provably violated, a warning for one
/// a file cannot settle.
@Suite(.serialized)
struct OfflineSpecializationTests {
    private static let moduleName = GenericSpecializationFixture.moduleName

    private func offlineRequest(forTypeNamed typeName: String) async throws -> (specializer: GenericSpecializer<MachOFile>, request: SpecializationRequest) {
        let indexer = try await GenericSpecializationFixtureIndexers.shared.offline()
        let definition = try GenericSpecializationFixtureIndexers.typeDefinition(named: typeName, in: indexer)
        let specializer = GenericSpecializer(indexer: indexer)
        return (specializer, try specializer.makeRequest(for: definition.typeContextDescriptorWrapper))
    }

    private func candidate(named typeName: String, in request: SpecializationRequest, parameter parameterName: String) throws -> SpecializationRequest.Candidate {
        let parameter = try #require(request.parameters.first { $0.name == parameterName })
        return try #require(parameter.candidates.first { $0.typeName.declaredNameForTesting == typeName }, "\(parameterName) offers no candidate named \(typeName)")
    }

    // MARK: - Requests

    /// Read from a file, a requirement on a protocol another image declares
    /// lands on the bind the loader would resolve (`$sSHMp`). The request used
    /// to drop it: `InnerElement` offered every type, and no witness table
    /// was counted.
    @Test("an offline request keeps a requirement on another image's protocol")
    func offlineRequestKeepsCrossImageProtocolRequirement() async throws {
        let (_, request) = try await offlineRequest(forTypeNamed: "Inner")

        let innerParameter = try #require(request.parameters.last)
        let protocolNames = innerParameter.requirements.compactMap { requirement -> String? in
            guard case .protocol(let info) = requirement else { return nil }
            return info.protocolName.name
        }
        #expect(protocolNames == ["Swift.Hashable"])
        #expect(innerParameter.candidates.contains { $0.typeName.name == "Swift.String" })
        #expect(!innerParameter.candidates.contains { $0.typeName.declaredNameForTesting == "FixtureUnmarked" })
    }

    // MARK: - Results

    @Test("an offline specialization binds every depth and names the instantiation")
    func offlineSpecializationBindsEveryDepth() async throws {
        let (specializer, request) = try await offlineRequest(forTypeNamed: "Inner")

        let result = try specializer.specialize(request, with: ["A": .metatype(Int.self), "A1": .metatype(String.self)])

        #expect(result.typeName.name(using: .default) == "\(Self.moduleName).DepthOuter<Swift.Int>.Middle.Inner<Swift.String>")
        #expect(result.binding.argumentsByDepth.map { $0.map { $0.print(using: .default) } } == [["Swift.Int"], ["Swift.String"]])
        #expect(result.resolvedArguments.map(\.parameterName) == ["A", "A1"])
    }

    @Test("a candidate argument stands for the candidate's name")
    func candidateArgument() async throws {
        let (specializer, request) = try await offlineRequest(forTypeNamed: "ProtocolBound")
        let marked = try candidate(named: "FixtureMarked", in: request, parameter: "A")

        let result = try specializer.specialize(request, with: ["A": .candidate(marked)])

        #expect(result.typeName.name(using: .default) == "\(Self.moduleName).ProtocolBound<\(Self.moduleName).FixtureMarked>")
    }

    @Test("a bound-generic argument is specialized offline in turn")
    func boundGenericArgument() async throws {
        let (specializer, request) = try await offlineRequest(forTypeNamed: "PairBox")
        let referenceBox = try candidate(named: "ReferenceBox", in: request, parameter: "A")

        let result = try specializer.specialize(request, with: [
            "A": .boundGeneric(baseCandidate: referenceBox, innerArguments: ["A": .metatype(Int.self)]),
            "B": .metatype(String.self),
        ])

        #expect(result.typeName.name(using: .default) == "\(Self.moduleName).PairBox<\(Self.moduleName).ReferenceBox<Swift.Int>, Swift.String>")
        let innerResult = try #require(result.argument(for: "A")?.innerResult)
        #expect(innerResult.typeName.name(using: .default) == "\(Self.moduleName).ReferenceBox<Swift.Int>")
    }

    @Test("a generic candidate throws the runtime path's typed error")
    func genericCandidateThrows() async throws {
        let (specializer, request) = try await offlineRequest(forTypeNamed: "PairBox")
        let referenceBox = try candidate(named: "ReferenceBox", in: request, parameter: "A")

        #expect {
            try specializer.specialize(request, with: ["A": .candidate(referenceBox), "B": .metatype(Int.self)])
        } throws: { error in
            guard case GenericSpecializer<MachOFile>.SpecializerError.candidateRequiresNestedSpecialization = error else { return false }
            return true
        }
    }

    @Test("a missing argument fails the static validation")
    func missingArgumentThrows() async throws {
        let (specializer, request) = try await offlineRequest(forTypeNamed: "PairBox")

        #expect(throws: GenericSpecializer<MachOFile>.SpecializerError.self) {
            try specializer.specialize(request, with: ["A": .metatype(Int.self)])
        }
    }

    // MARK: - Preflight: errors

    @Test("AnyObject given a value type is an error")
    func anyObjectGivenValueTypeIsAnError() async throws {
        let (specializer, request) = try await offlineRequest(forTypeNamed: "ClassBound")

        let validation = specializer.staticPreflight(selection: ["A": .metatype(Int.self)], for: request)

        #expect(!validation.isValid)
        guard case .layoutRequirementNotSatisfied(let parameterName, _, _)? = validation.errors.first else {
            Issue.record("expected a layout error, got \(validation.errors)")
            return
        }
        #expect(parameterName == "A")
    }

    @Test("AnyObject given a class passes")
    func anyObjectGivenClassPasses() async throws {
        let (specializer, request) = try await offlineRequest(forTypeNamed: "ClassBound")
        let subclass = try candidate(named: "ConstraintSubclass", in: request, parameter: "A")

        let validation = specializer.staticPreflight(selection: ["A": .candidate(subclass)], for: request)

        #expect(validation.isValid, "\(validation.errors)")
    }

    @Test("a class the indexer knows outside the base class's subtree is an error")
    func classOutsideTheSubtreeIsAnError() async throws {
        let (specializer, request) = try await offlineRequest(forTypeNamed: "BaseClassBound")
        let unrelated = try #require(
            try await GenericSpecializationFixtureIndexers.shared.offline().allTypeDefinitions.values.first { $0.typeName.declaredNameForTesting == "ConstraintUnrelated" }
        )

        let validation = specializer.staticPreflight(
            selection: ["A": .candidate(.init(typeName: unrelated.typeName, source: .image(GenericSpecializationFixture.moduleName)))],
            for: request
        )

        #expect(!validation.isValid)
        #expect(validation.errors.contains { if case .baseClassRequirementNotSatisfied = $0 { return true } else { return false } })
    }

    @Test("a subclass of the base class passes")
    func subclassPasses() async throws {
        let (specializer, request) = try await offlineRequest(forTypeNamed: "BaseClassBound")
        let subclass = try candidate(named: "ConstraintSubclass", in: request, parameter: "A")

        let validation = specializer.staticPreflight(selection: ["A": .candidate(subclass)], for: request)

        #expect(validation.isValid, "\(validation.errors)")
        #expect(validation.warnings.isEmpty, "\(validation.warnings)")
    }

    @Test("a host class whose superclass chain misses the base class is an error")
    func hostClassOutsideTheSubtreeIsAnError() async throws {
        let (specializer, request) = try await offlineRequest(forTypeNamed: "BaseClassBound")

        let validation = specializer.staticPreflight(selection: ["A": .metatype(HostUnrelatedClass.self)], for: request)

        #expect(validation.errors.contains { if case .baseClassRequirementNotSatisfied = $0 { return true } else { return false } })
    }

    @Test("a same-type requirement on a member the argument contradicts is an error")
    func contradictedSameTypeIsAnError() async throws {
        let (specializer, request) = try await offlineRequest(forTypeNamed: "ElementSameType")

        let validation = specializer.staticPreflight(selection: ["A": .metatype([String].self)], for: request)

        #expect(!validation.isValid)
        guard case .sameTypeRequirementNotSatisfied(let parameterName, let expectedType, let actualType)? = validation.errors.first else {
            Issue.record("expected a same-type error, got \(validation.errors)")
            return
        }
        #expect(parameterName == "A.Element")
        #expect(expectedType == "Swift.Int")
        #expect(actualType == "Swift.String")
    }

    @Test("a same-type requirement on a member the argument satisfies passes")
    func satisfiedSameTypePasses() async throws {
        let (specializer, request) = try await offlineRequest(forTypeNamed: "ElementSameType")

        let validation = specializer.staticPreflight(selection: ["A": .metatype([Int].self)], for: request)

        #expect(validation.isValid, "\(validation.errors)")
        #expect(validation.warnings.isEmpty, "\(validation.warnings)")
    }

    // MARK: - Preflight: warnings

    @Test("a conformance the indexed images record passes without a warning")
    func recordedConformancePasses() async throws {
        let (specializer, request) = try await offlineRequest(forTypeNamed: "ProtocolBound")
        let marked = try candidate(named: "FixtureMarked", in: request, parameter: "A")

        let validation = specializer.staticPreflight(selection: ["A": .candidate(marked)], for: request)

        #expect(validation.isValid)
        #expect(validation.warnings.isEmpty, "\(validation.warnings)")
    }

    @Test("a conformance no indexed image records is a warning, not an error")
    func unrecordedConformanceIsAWarning() async throws {
        let (specializer, request) = try await offlineRequest(forTypeNamed: "ProtocolBound")

        let validation = specializer.staticPreflight(selection: ["A": .metatype(HostUnmarked.self)], for: request)

        #expect(validation.isValid)
        guard case .conformanceCheckFailed(let parameterName, let protocolName, _)? = validation.warnings.first else {
            Issue.record("expected a conformance warning, got \(validation.warnings)")
            return
        }
        #expect(parameterName == "A")
        #expect(protocolName == "\(Self.moduleName).FixtureMarker")
    }

    @Test("a member conformance is checked through the projected member")
    func memberConformanceIsCheckedThroughTheProjection() async throws {
        let (specializer, request) = try await offlineRequest(forTypeNamed: "ElementHashable")

        let satisfied = specializer.staticPreflight(selection: ["A": .metatype([Int].self)], for: request)
        let unproven = specializer.staticPreflight(selection: ["A": .metatype([HostUnmarked].self)], for: request)

        #expect(satisfied.isValid && satisfied.warnings.isEmpty, "\(satisfied.warnings)")
        #expect(unproven.isValid)
        #expect(unproven.warnings.contains { if case .conformanceCheckFailed(let parameterName, _, _) = $0 { return parameterName == "A.Element" } else { return false } }, "\(unproven.warnings)")
    }

    @Test("violations stop the specialization")
    func violationsStopTheSpecialization() async throws {
        let (specializer, request) = try await offlineRequest(forTypeNamed: "ClassBound")

        #expect(throws: GenericSpecializer<MachOFile>.SpecializerError.self) {
            try specializer.specialize(request, with: ["A": .metatype(Int.self)])
        }
    }
}
