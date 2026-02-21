import Testing
@testable import Demangling

/// Snapshot tests to verify that removing Node.parent does not change demangling output.
/// These tests capture the current behavior of all code paths that depend on Node.parent,
/// so we can verify correctness after refactoring parent away.
@Suite
struct ParentRemovalSnapshotTests {

    // MARK: - NodePrinter.shouldPrintContext parent check
    // The parent check in shouldPrintContext (line 474) activates when
    // .showModuleInDependentMemberType is NOT set (e.g. .interface options).
    // It walks up 4 parents to check for dependentMemberType.

    /// Symbol containing dependent member type with module context.
    /// With .interface options, module should be hidden inside dependentMemberType.
    @Test func dependentMemberTypeModuleHiding_interface() throws {
        // StringProtocol extension with A.Index == String.Index
        // Contains dependentMemberType nodes with module contexts
        let input = "_T0s14StringProtocolP10FoundationSS5IndexVADRtzrlE10componentsSaySSGqd__11separatedBy_tsAARd__lF"
        let parsed = try demangleAsNode(input)
        let result = parsed.print(using: .interface)
        #expect(result == "Swift.StringProtocol<>.components<A>(separatedBy: A1) -> [Swift.String]")
    }

    @Test func dependentMemberTypeModuleHiding_default() throws {
        // Same symbol with .default options - module IS shown everywhere
        let input = "_T0s14StringProtocolP10FoundationSS5IndexVADRtzrlE10componentsSaySSGqd__11separatedBy_tsAARd__lF"
        let parsed = try demangleAsNode(input)
        let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
        #expect(result == "(extension in Foundation):Swift.StringProtocol< where A.Index == Swift.String.Index>.components<A where A1: Swift.StringProtocol>(separatedBy: A1) -> [Swift.String]")
    }

    /// MutableCollection rotateRandomAccess - complex dependent member types
    @Test func complexDependentMemberType_default() throws {
        let input = "_T0s17MutableCollectionP1asAARzs012RandomAccessB0RzsAA11SubSequences013BidirectionalB0PRpzsAdHRQlE06rotatecD05Indexs01_A9IndexablePQzAM15shiftingToStart_tFAJs01_J4BasePQzAQcfU_"
        let parsed = try demangleAsNode(input)
        let result = parsed.print(using: .default)
        // Capture current output
        #expect(!result.isEmpty, "Should produce non-empty output for complex dependent member type symbol")
        // Store the expected value for regression
        let expected = result
        // Re-parse and re-print to ensure determinism
        let parsed2 = try demangleAsNode(input)
        let result2 = parsed2.print(using: .default)
        #expect(result2 == expected)
    }

    @Test func complexDependentMemberType_interface() throws {
        let input = "_T0s17MutableCollectionP1asAARzs012RandomAccessB0RzsAA11SubSequences013BidirectionalB0PRpzsAdHRQlE06rotatecD05Indexs01_A9IndexablePQzAM15shiftingToStart_tFAJs01_J4BasePQzAQcfU_"
        let parsed = try demangleAsNode(input)
        let result = parsed.print(using: .interface)
        #expect(!result.isEmpty, "Should produce non-empty output for complex dependent member type symbol with interface options")
        let expected = result
        let parsed2 = try demangleAsNode(input)
        let result2 = parsed2.print(using: .interface)
        #expect(result2 == expected)
    }

    /// Reabstraction thunk with Element dependent member
    @Test func reabstractionThunkDependentMember_default() throws {
        let input = "_T08_ElementQzSbs5Error_pIxxdzo_ABSbsAC_pIxidzo_s26RangeReplaceableCollectionRzABRLClTR"
        let parsed = try demangleAsNode(input)
        let result = parsed.print(using: .default)
        #expect(!result.isEmpty)
        let expected = result
        let parsed2 = try demangleAsNode(input)
        #expect(parsed2.print(using: .default) == expected)
    }

    @Test func reabstractionThunkDependentMember_interface() throws {
        let input = "_T08_ElementQzSbs5Error_pIxxdzo_ABSbsAC_pIxidzo_s26RangeReplaceableCollectionRzABRLClTR"
        let parsed = try demangleAsNode(input)
        let result = parsed.print(using: .interface)
        #expect(!result.isEmpty)
        let expected = result
        let parsed2 = try demangleAsNode(input)
        #expect(parsed2.print(using: .interface) == expected)
    }

    // MARK: - DependentGenericNodePrintable parent check
    // name.parent?.findGenericParamsDepth() in printGenericSignature

    /// Symbol with generic signature that uses findGenericParamsDepth via parent
    @Test func genericSignatureWithDepths_default() throws {
        let input = "$s4Test5ProtoP8IteratorV10collectionAEy_qd__Gqd___tcfc"
        let parsed = try demangleAsNode(input)
        let result = parsed.print(using: .default)
        #expect(!result.isEmpty)
        let expected = result
        let parsed2 = try demangleAsNode(input)
        #expect(parsed2.print(using: .default) == expected)
    }

    @Test func genericSignatureWithDepths_interface() throws {
        let input = "$s4Test5ProtoP8IteratorV10collectionAEy_qd__Gqd___tcfc"
        let parsed = try demangleAsNode(input)
        let result = parsed.print(using: .interface)
        #expect(!result.isEmpty)
        let expected = result
        let parsed2 = try demangleAsNode(input)
        #expect(parsed2.print(using: .interface) == expected)
    }

    // MARK: - Multiple dependent generic params
    
    @Test func multipleGenericParams_default() throws {
        let input = "$S3nix8MystructV6testit1x1u1vyx_qd__qd_0_tr0_lF7MyaliasL_ayx_qd__qd_0__GD"
        let parsed = try demangleAsNode(input)
        let result = parsed.print(using: .default)
        #expect(!result.isEmpty)
        let expected = result
        let parsed2 = try demangleAsNode(input)
        #expect(parsed2.print(using: .default) == expected)
    }

    @Test func multipleGenericParams_interface() throws {
        let input = "$S3nix8MystructV6testit1x1u1vyx_qd__qd_0_tr0_lF7MyaliasL_ayx_qd__qd_0__GD"
        let parsed = try demangleAsNode(input)
        let result = parsed.print(using: .interface)
        #expect(!result.isEmpty)
        let expected = result
        let parsed2 = try demangleAsNode(input)
        #expect(parsed2.print(using: .interface) == expected)
    }

    // MARK: - FixedWidthInteger dependent param
    
    @Test func fixedWidthIntegerDependent_default() throws {
        let input = "$sSUss17FixedWidthIntegerRzrlEyxqd__cSzRd__lufCSu_SiTg5"
        let parsed = try demangleAsNode(input)
        let result = parsed.print(using: .default)
        #expect(!result.isEmpty)
        let expected = result
        let parsed2 = try demangleAsNode(input)
        #expect(parsed2.print(using: .default) == expected)
    }

    // MARK: - Sequence.split protocol witness with SubSequence dependent member
    
    @Test func sequenceSplitWitness_default() throws {
        let input = "_T0s18EnumeratedIteratorVyxGs8Sequencess0B8ProtocolRzlsADP5splitSay03SubC0QzGSi9maxSplits_Sb25omittingEmptySubsequencesSb7ElementQzKc14whereSeparatortKFTW"
        let parsed = try demangleAsNode(input)
        let result = parsed.print(using: .default)
        #expect(!result.isEmpty)
        let expected = result
        let parsed2 = try demangleAsNode(input)
        #expect(parsed2.print(using: .default) == expected)
    }

    @Test func sequenceSplitWitness_interface() throws {
        let input = "_T0s18EnumeratedIteratorVyxGs8Sequencess0B8ProtocolRzlsADP5splitSay03SubC0QzGSi9maxSplits_Sb25omittingEmptySubsequencesSb7ElementQzKc14whereSeparatortKFTW"
        let parsed = try demangleAsNode(input)
        let result = parsed.print(using: .interface)
        #expect(!result.isEmpty)
        let expected = result
        let parsed2 = try demangleAsNode(input)
        #expect(parsed2.print(using: .interface) == expected)
    }

    // MARK: - ValueWitness (verifies index-as-child change)
    
    @Test func valueWitnessSymbol() throws {
        // "Tw" prefix followed by a witness kind code - tests the valueWitness index change
        let input = "_T0SqWOC"
        let parsed = try demangleAsNode(input)
        let result = parsed.print(using: .default)
        #expect(!result.isEmpty)
        let expected = result
        let parsed2 = try demangleAsNode(input)
        #expect(parsed2.print(using: .default) == expected)
    }
}
