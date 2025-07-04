import Testing
@testable import Demangle

@Suite
struct DemangleSwiftProjectDerivedTests {
    @Test func _$sBf32_() {
        let input = "$sBf32_"
        let output = "Builtin.FPIEEE32"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sBf64_() {
        let input = "$sBf64_"
        let output = "Builtin.FPIEEE64"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sBf80_() {
        let input = "$sBf80_"
        let output = "Builtin.FPIEEE80"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sBi32_() {
        let input = "$sBi32_"
        let output = "Builtin.Int32"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sBi8_Bv4_() {
        let input = "$sBi8_Bv4_"
        let output = "Builtin.Vec4xInt8"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sBf16_Bv4_() {
        let input = "$sBf16_Bv4_"
        let output = "Builtin.Vec4xFPIEEE16"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sBpBv4_() {
        let input = "$sBpBv4_"
        let output = "Builtin.Vec4xRawPointer"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T03foo3barC3basyAA3zimCAE_tFTo() {
        let input = "_T03foo3barC3basyAA3zimCAE_tFTo"
        let output = "@objc foo.bar.bas(zim: foo.zim) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T0SC3fooS2d_SdtFTO() {
        let input = "_T0SC3fooS2d_SdtFTO"
        let output = "@nonobjc __C_Synthesized.foo(Swift.Double, Swift.Double) -> Swift.Double"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s3foo3barC3bas3zimyAaEC_tFTo() {
        let input = "_$s3foo3barC3bas3zimyAaEC_tFTo"
        let output = "@objc foo.bar.bas(zim: foo.zim) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sSC3fooyS2d_SdtFTO() {
        let input = "_$sSC3fooyS2d_SdtFTO"
        let output = "@nonobjc __C_Synthesized.foo(Swift.Double, Swift.Double) -> Swift.Double"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$S3foo3barC3bas3zimyAaEC_tFTo() {
        let input = "_$S3foo3barC3bas3zimyAaEC_tFTo"
        let output = "@objc foo.bar.bas(zim: foo.zim) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$SSC3fooyS2d_SdtFTO() {
        let input = "_$SSC3fooyS2d_SdtFTO"
        let output = "@nonobjc __C_Synthesized.foo(Swift.Double, Swift.Double) -> Swift.Double"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sTAdot123() {
        let input = "_$sTA.123"
        let output = "partial apply forwarder with unmangled suffix \".123\""
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4main3fooyySiFyyXEfU_TAdot1() {
        let input = "$s4main3fooyySiFyyXEfU_TA.1"
        let output = "partial apply forwarder for closure #1 () -> () in main.foo(Swift.Int) -> () with unmangled suffix \".1\""
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4main8MyStructV3fooyyFAA1XV_Tg5dotfoo() {
        let input = "$s4main8MyStructV3fooyyFAA1XV_Tg5.foo"
        let output = "generic specialization <main.X> of main.MyStruct.foo() -> () with unmangled suffix \".foo\""
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func TtZZ() {
        let input = "_TtZZ"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TtB() {
        let input = "_TtB"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TtBSi() {
        let input = "_TtBSi"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TtBx() {
        let input = "_TtBx"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TtC() {
        let input = "_TtC"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TtT() {
        let input = "_TtT"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TtTSi() {
        let input = "_TtTSi"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TtQd_() {
        let input = "_TtQd_"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TtU__FQo_Si() {
        let input = "_TtU__FQo_Si"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TtU__FQD__Si() {
        let input = "_TtU__FQD__Si"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TtU___FQ_U____FQd0__T_() {
        let input = "_TtU___FQ_U____FQd0__T_"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TtU___FQ_U____FQd_1_T_() {
        let input = "_TtU___FQ_U____FQd_1_T_"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TtU___FQ_U____FQ2_T_() {
        let input = "_TtU___FQ_U____FQ2_T_"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func Tw() {
        let input = "_Tw"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TWa() {
        let input = "_TWa"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func Twal() {
        let input = "_Twal"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func T() {
        let input = "_T"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TTo() {
        let input = "_TTo"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TC() {
        let input = "_TC"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TM() {
        let input = "_TM"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TW() {
        let input = "_TW"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TWV() {
        let input = "_TWV"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TWo() {
        let input = "_TWo"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TWv() {
        let input = "_TWv"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TWvd() {
        let input = "_TWvd"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TWvi() {
        let input = "_TWvi"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TWvx() {
        let input = "_TWvx"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func T013call_protocol1CCAA1PA2aDP3fooSiyFTW() {
        let input = "_T013call_protocol1CCAA1PA2aDP3fooSiyFTW"
        let output = "protocol witness for call_protocol.P.foo() -> Swift.Int in conformance call_protocol.C : call_protocol.P in call_protocol"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func TTSgS() {
        let input = "_TTSgS"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TTSg5S() {
        let input = "_TTSg5S"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TTSgSi() {
        let input = "_TTSgSi"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TTSg5Si() {
        let input = "_TTSg5Si"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TTSgSi_() {
        let input = "_TTSgSi_"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TTSgSi__() {
        let input = "_TTSgSi__"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TTSgSiS_() {
        let input = "_TTSgSiS_"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TTSgSi__xyz() {
        let input = "_TTSgSi__xyz"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func T0S2SSbIxxxd_S2SSbIxiid_TRTA() {
        let input = "_T0S2SSbIxxxd_S2SSbIxiid_TRTA"
        let output = "partial apply forwarder for reabstraction thunk helper from @callee_owned (@owned Swift.String, @owned Swift.String) -> (@unowned Swift.Bool) to @callee_owned (@in Swift.String, @in Swift.String) -> (@unowned Swift.Bool)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T0SPyxGAAs5Error_pIxydzo_A2AsAB_pIxirzo_lTRTa() {
        let input = "_T0SPyxGAAs5Error_pIxydzo_A2AsAB_pIxirzo_lTRTa"
        let output = "partial apply ObjC forwarder for reabstraction thunk helper <A> from @callee_owned (@unowned Swift.UnsafePointer<A>) -> (@unowned Swift.UnsafePointer<A>, @error @owned Swift.Error) to @callee_owned (@in Swift.UnsafePointer<A>) -> (@out Swift.UnsafePointer<A>, @error @owned Swift.Error)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func TFE1a() {
        let input = "_TFE1a"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TTWOE5imojiCSo5Imoji14ImojiMatchRankS_9RankValueS_FS2_g9rankValueqq_Ss16RawRepresentable8RawValue() {
        let input = "_TTWOE5imojiCSo5Imoji14ImojiMatchRankS_9RankValueS_FS2_g9rankValueqq_Ss16RawRepresentable8RawValue"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func T0s17MutableCollectionP1asAARzs012RandomAccessB0RzsAA11SubSequences013BidirectionalB0PRpzsAdHRQlE06rotatecD05Indexs01_A9IndexablePQzAM15shiftingToStart_tFAJs01_J4BasePQzAQcfU_() {
        let input = "_T0s17MutableCollectionP1asAARzs012RandomAccessB0RzsAA11SubSequences013BidirectionalB0PRpzsAdHRQlE06rotatecD05Indexs01_A9IndexablePQzAM15shiftingToStart_tFAJs01_J4BasePQzAQcfU_"
        let output = "closure #1 (A.Swift._IndexableBase.Index) -> A.Swift._IndexableBase.Index in (extension in a):Swift.MutableCollection<A where A: Swift.MutableCollection, A: Swift.RandomAccessCollection, A.Swift.BidirectionalCollection.SubSequence: Swift.MutableCollection, A.Swift.BidirectionalCollection.SubSequence: Swift.RandomAccessCollection>.rotateRandomAccess(shiftingToStart: A.Swift._MutableIndexable.Index) -> A.Swift._MutableIndexable.Index"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$Ss17MutableCollectionP1asAARzs012RandomAccessB0RzsAA11SubSequences013BidirectionalB0PRpzsAdHRQlE06rotatecD015shiftingToStart5Indexs01_A9IndexablePQzAN_tFAKs01_M4BasePQzAQcfU_() {
        let input = "_$Ss17MutableCollectionP1asAARzs012RandomAccessB0RzsAA11SubSequences013BidirectionalB0PRpzsAdHRQlE06rotatecD015shiftingToStart5Indexs01_A9IndexablePQzAN_tFAKs01_M4BasePQzAQcfU_"
        let output = "closure #1 (A.Swift._IndexableBase.Index) -> A.Swift._IndexableBase.Index in (extension in a):Swift.MutableCollection<A where A: Swift.MutableCollection, A: Swift.RandomAccessCollection, A.Swift.BidirectionalCollection.SubSequence: Swift.MutableCollection, A.Swift.BidirectionalCollection.SubSequence: Swift.RandomAccessCollection>.rotateRandomAccess(shiftingToStart: A.Swift._MutableIndexable.Index) -> A.Swift._MutableIndexable.Index"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T03foo4_123ABTf3psbpsb_n() {
        let input = "_T03foo4_123ABTf3psbpsb_n"
        let output = "function signature specialization <Arg[0] = [Constant Propagated String : u8'123'], Arg[1] = [Constant Propagated String : u8'123']> of foo"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T04main5innerys5Int32Vz_yADctF25closure_with_box_argumentxz_Bi32__lXXTf1nc_n() {
        let input = "_T04main5innerys5Int32Vz_yADctF25closure_with_box_argumentxz_Bi32__lXXTf1nc_n"
        let output = "function signature specialization <Arg[1] = [Closure Propagated : closure_with_box_argument, Argument Types : [<A> { var A } <Builtin.Int32>]> of main.inner(inout Swift.Int32, (Swift.Int32) -> ()) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$S4main5inneryys5Int32Vz_yADctF25closure_with_box_argumentxz_Bi32__lXXTf1nc_n() {
        let input = "_$S4main5inneryys5Int32Vz_yADctF25closure_with_box_argumentxz_Bi32__lXXTf1nc_n"
        let output = "function signature specialization <Arg[1] = [Closure Propagated : closure_with_box_argument, Argument Types : [<A> { var A } <Builtin.Int32>]> of main.inner(inout Swift.Int32, (Swift.Int32) -> ()) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T03foo6testityyyc_yyctF1a1bTf3pfpf_n() {
        let input = "_T03foo6testityyyc_yyctF1a1bTf3pfpf_n"
        let output = "function signature specialization <Arg[0] = [Constant Propagated Function : a], Arg[1] = [Constant Propagated Function : b]> of foo.testit(() -> (), () -> ()) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$S3foo6testityyyyc_yyctF1a1bTf3pfpf_n() {
        let input = "_$S3foo6testityyyyc_yyctF1a1bTf3pfpf_n"
        let output = "function signature specialization <Arg[0] = [Constant Propagated Function : a], Arg[1] = [Constant Propagated Function : b]> of foo.testit(() -> (), () -> ()) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func SocketJoinOrLeaveMulticast() {
        let input = "_SocketJoinOrLeaveMulticast"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func T0s10DictionaryV3t17E6Index2V1loiSbAEyxq__G_AGtFZ() {
        let input = "_T0s10DictionaryV3t17E6Index2V1loiSbAEyxq__G_AGtFZ"
        let output = "static (extension in t17):Swift.Dictionary.Index2.< infix((extension in t17):[A : B].Index2, (extension in t17):[A : B].Index2) -> Swift.Bool"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T08mangling14varargsVsArrayySi3arrd_SS1ntF() {
        let input = "_T08mangling14varargsVsArrayySi3arrd_SS1ntF"
        let output = "mangling.varargsVsArray(arr: Swift.Int..., n: Swift.String) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T08mangling14varargsVsArrayySaySiG3arr_SS1ntF() {
        let input = "_T08mangling14varargsVsArrayySaySiG3arr_SS1ntF"
        let output = "mangling.varargsVsArray(arr: [Swift.Int], n: Swift.String) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T08mangling14varargsVsArrayySaySiG3arrd_SS1ntF() {
        let input = "_T08mangling14varargsVsArrayySaySiG3arrd_SS1ntF"
        let output = "mangling.varargsVsArray(arr: [Swift.Int]..., n: Swift.String) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T08mangling14varargsVsArrayySi3arrd_tF() {
        let input = "_T08mangling14varargsVsArrayySi3arrd_tF"
        let output = "mangling.varargsVsArray(arr: Swift.Int...) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T08mangling14varargsVsArrayySaySiG3arrd_tF() {
        let input = "_T08mangling14varargsVsArrayySaySiG3arrd_tF"
        let output = "mangling.varargsVsArray(arr: [Swift.Int]...) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$Ss10DictionaryV3t17E6Index2V1loiySbAEyxq__G_AGtFZ() {
        let input = "_$Ss10DictionaryV3t17E6Index2V1loiySbAEyxq__G_AGtFZ"
        let output = "static (extension in t17):Swift.Dictionary.Index2.< infix((extension in t17):[A : B].Index2, (extension in t17):[A : B].Index2) -> Swift.Bool"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$S8mangling14varargsVsArray3arr1nySid_SStF() {
        let input = "_$S8mangling14varargsVsArray3arr1nySid_SStF"
        let output = "mangling.varargsVsArray(arr: Swift.Int..., n: Swift.String) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$S8mangling14varargsVsArray3arr1nySaySiG_SStF() {
        let input = "_$S8mangling14varargsVsArray3arr1nySaySiG_SStF"
        let output = "mangling.varargsVsArray(arr: [Swift.Int], n: Swift.String) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$S8mangling14varargsVsArray3arr1nySaySiGd_SStF() {
        let input = "_$S8mangling14varargsVsArray3arr1nySaySiGd_SStF"
        let output = "mangling.varargsVsArray(arr: [Swift.Int]..., n: Swift.String) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$S8mangling14varargsVsArray3arrySid_tF() {
        let input = "_$S8mangling14varargsVsArray3arrySid_tF"
        let output = "mangling.varargsVsArray(arr: Swift.Int...) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$S8mangling14varargsVsArray3arrySaySiGd_tF() {
        let input = "_$S8mangling14varargsVsArray3arrySaySiGd_tF"
        let output = "mangling.varargsVsArray(arr: [Swift.Int]...) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T0s13_UnicodeViewsVss22RandomAccessCollectionRzs0A8EncodingR_11SubSequence_5IndexQZAFRtzsAcERpzAE_AEQZAIRSs15UnsignedInteger8Iterator_7ElementRPzAE_AlMQZANRS13EncodedScalar_AlMQY_AORSr0_lE13CharacterViewVyxq__G() {
        let input = "_T0s13_UnicodeViewsVss22RandomAccessCollectionRzs0A8EncodingR_11SubSequence_5IndexQZAFRtzsAcERpzAE_AEQZAIRSs15UnsignedInteger8Iterator_7ElementRPzAE_AlMQZANRS13EncodedScalar_AlMQY_AORSr0_lE13CharacterViewVyxq__G"
        let output = "(extension in Swift):Swift._UnicodeViews<A, B><A, B where A: Swift.RandomAccessCollection, B: Swift.UnicodeEncoding, A.Index == A.SubSequence.Index, A.SubSequence: Swift.RandomAccessCollection, A.SubSequence == A.SubSequence.SubSequence, A.Iterator.Element: Swift.UnsignedInteger, A.Iterator.Element == A.SubSequence.Iterator.Element, A.SubSequence.Iterator.Element == B.EncodedScalar.Iterator.Element>.CharacterView"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T010Foundation11MeasurementV12SimulatorKitSo9UnitAngleCRszlE11OrientationO2eeoiSbAcDEAGOyAF_G_AKtFZ() {
        let input = "_T010Foundation11MeasurementV12SimulatorKitSo9UnitAngleCRszlE11OrientationO2eeoiSbAcDEAGOyAF_G_AKtFZ"
        let output = "static (extension in SimulatorKit):Foundation.Measurement<A where A == __C.UnitAngle>.Orientation.== infix((extension in SimulatorKit):Foundation.Measurement<__C.UnitAngle>.Orientation, (extension in SimulatorKit):Foundation.Measurement<__C.UnitAngle>.Orientation) -> Swift.Bool"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$S10Foundation11MeasurementV12SimulatorKitSo9UnitAngleCRszlE11OrientationO2eeoiySbAcDEAGOyAF_G_AKtFZ() {
        let input = "_$S10Foundation11MeasurementV12SimulatorKitSo9UnitAngleCRszlE11OrientationO2eeoiySbAcDEAGOyAF_G_AKtFZ"
        let output = "static (extension in SimulatorKit):Foundation.Measurement<A where A == __C.UnitAngle>.Orientation.== infix((extension in SimulatorKit):Foundation.Measurement<__C.UnitAngle>.Orientation, (extension in SimulatorKit):Foundation.Measurement<__C.UnitAngle>.Orientation) -> Swift.Bool"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T04main1_yyF() {
        let input = "_T04main1_yyF"
        let output = "main._() -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T04test6testitSiyt_tF() {
        let input = "_T04test6testitSiyt_tF"
        let output = "test.testit(()) -> Swift.Int"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$S4test6testitySiyt_tF() {
        let input = "_$S4test6testitySiyt_tF"
        let output = "test.testit(()) -> Swift.Int"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T08_ElementQzSbs5Error_pIxxdzo_ABSbsAC_pIxidzo_s26RangeReplaceableCollectionRzABRLClTR() {
        let input = "_T08_ElementQzSbs5Error_pIxxdzo_ABSbsAC_pIxidzo_s26RangeReplaceableCollectionRzABRLClTR"
        let output = "reabstraction thunk helper <A where A: Swift.RangeReplaceableCollection, A._Element: AnyObject> from @callee_owned (@owned A._Element) -> (@unowned Swift.Bool, @error @owned Swift.Error) to @callee_owned (@in A._Element) -> (@unowned Swift.Bool, @error @owned Swift.Error)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T0Ix_IyB_Tr() {
        let input = "_T0Ix_IyB_Tr"
        let output = "reabstraction thunk from @callee_owned () -> () to @callee_unowned @convention(block) () -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T0Rml() {
        let input = "_T0Rml"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func T0Tk() {
        let input = "_T0Tk"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func T0A8() {
        let input = "_T0A8"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func T0s30ReversedRandomAccessCollectionVyxGTfq3nnpf_nTfq1cn_nTfq4x_n() {
        let input = "_T0s30ReversedRandomAccessCollectionVyxGTfq3nnpf_nTfq1cn_nTfq4x_n"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func T03abc6testitySiFTm() {
        let input = "_T03abc6testitySiFTm"
        let output = "merged abc.testit(Swift.Int) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T04main4TestCACSi1x_tc6_PRIV_Llfc() {
        let input = "_T04main4TestCACSi1x_tc6_PRIV_Llfc"
        let output = "main.Test.(in _PRIV_).init(x: Swift.Int) -> main.Test"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$S3abc6testityySiFTm() {
        let input = "_$S3abc6testityySiFTm"
        let output = "merged abc.testit(Swift.Int) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$S4main4TestC1xACSi_tc6_PRIV_Llfc() {
        let input = "_$S4main4TestC1xACSi_tc6_PRIV_Llfc"
        let output = "main.Test.(in _PRIV_).init(x: Swift.Int) -> main.Test"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T0SqWOydot17() {
        let input = "_T0SqWOy.17"
        let output = "outlined copy of Swift.Optional with unmangled suffix \".17\""
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T0SqWOC() {
        let input = "_T0SqWOC"
        let output = "outlined init with copy of Swift.Optional"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T0SqWOD() {
        let input = "_T0SqWOD"
        let output = "outlined assign with take of Swift.Optional"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T0SqWOF() {
        let input = "_T0SqWOF"
        let output = "outlined assign with copy of Swift.Optional"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T0SqWOH() {
        let input = "_T0SqWOH"
        let output = "outlined destroy of Swift.Optional"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T03nix6testitSaySiGyFTv_() {
        let input = "_T03nix6testitSaySiGyFTv_"
        let output = "outlined variable #0 of nix.testit() -> [Swift.Int]"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T03nix6testitSaySiGyFTv_r() {
        let input = "_T03nix6testitSaySiGyFTv_r"
        let output = "outlined read-only object #0 of nix.testit() -> [Swift.Int]"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T03nix6testitSaySiGyFTv0_() {
        let input = "_T03nix6testitSaySiGyFTv0_"
        let output = "outlined variable #1 of nix.testit() -> [Swift.Int]"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T0So11UITextFieldC4textSSSgvgToTepb_() {
        let input = "_T0So11UITextFieldC4textSSSgvgToTepb_"
        let output = "outlined bridged method (pb) of @objc __C.UITextField.text.getter : Swift.String?"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T0So11UITextFieldC4textSSSgvgToTeab_() {
        let input = "_T0So11UITextFieldC4textSSSgvgToTeab_"
        let output = "outlined bridged method (ab) of @objc __C.UITextField.text.getter : Swift.String?"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sSo5GizmoC11doSomethingyypSgSaySSGSgFToTembgnn_() {
        let input = "$sSo5GizmoC11doSomethingyypSgSaySSGSgFToTembgnn_"
        let output = "outlined bridged method (mbgnn) of @objc __C.Gizmo.doSomething([Swift.String]?) -> Any?"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T04test1SVyxGAA1RA2A1ZRzAA1Y2ZZRpzl1A_AhaGPWT() {
        let input = "_T04test1SVyxGAA1RA2A1ZRzAA1Y2ZZRpzl1A_AhaGPWT"
        let output = "associated type witness table accessor for A.ZZ : test.Y in <A where A: test.Z, A.ZZ: test.Y> test.S<A> : test.R in test"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T0s24_UnicodeScalarExceptions33_0E4228093681F6920F0AB2E48B4F1C69LLVACycfC() {
        let input = "_T0s24_UnicodeScalarExceptions33_0E4228093681F6920F0AB2E48B4F1C69LLVACycfC"
        let output = "Swift.(_UnicodeScalarExceptions in _0E4228093681F6920F0AB2E48B4F1C69).init() -> Swift.(_UnicodeScalarExceptions in _0E4228093681F6920F0AB2E48B4F1C69)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T0D() {
        let input = "_T0D"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func T0s18EnumeratedIteratorVyxGs8Sequencess0B8ProtocolRzlsADP5splitSay03SubC0QzGSi9maxSplits_Sb25omittingEmptySubsequencesSb7ElementQzKc14whereSeparatortKFTW() {
        let input = "_T0s18EnumeratedIteratorVyxGs8Sequencess0B8ProtocolRzlsADP5splitSay03SubC0QzGSi9maxSplits_Sb25omittingEmptySubsequencesSb7ElementQzKc14whereSeparatortKFTW"
        let output = "protocol witness for Swift.Sequence.split(maxSplits: Swift.Int, omittingEmptySubsequences: Swift.Bool, whereSeparator: (A.Element) throws -> Swift.Bool) throws -> [A.SubSequence] in conformance <A where A: Swift.IteratorProtocol> Swift.EnumeratedIterator<A> : Swift.Sequence in Swift"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T0s3SetVyxGs10CollectiotySivm() {
        let input = "_T0s3SetVyxGs10CollectiotySivm"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func S$s3SetVyxGs10CollectiotySivm() {
        let input = "_S$s3SetVyxGs10CollectiotySivm"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func T0s18ReversedCollectionVyxGs04LazyB8ProtocolfC() {
        let input = "_T0s18ReversedCollectionVyxGs04LazyB8ProtocolfC"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func S$s18ReversedCollectionVyxGs04LazyB8ProtocolfC() {
        let input = "_S$s18ReversedCollectionVyxGs04LazyB8ProtocolfC"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func T0iW() {
        let input = "_T0iW"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func S$iW() {
        let input = "_S$iW"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func T0s5print_9separator10terminatoryypfC() {
        let input = "_T0s5print_9separator10terminatoryypfC"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func S$s5print_9separator10terminatoryypfC() {
        let input = "_S$s5print_9separator10terminatoryypfC"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func T0So13GenericOptionas8HashableSCsACP9hashValueSivgTW() {
        let input = "_T0So13GenericOptionas8HashableSCsACP9hashValueSivgTW"
        let output = "protocol witness for Swift.Hashable.hashValue.getter : Swift.Int in conformance __C.GenericOption : Swift.Hashable in __C_Synthesized"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T0So11CrappyColorVs16RawRepresentableSCMA() {
        let input = "_T0So11CrappyColorVs16RawRepresentableSCMA"
        let output = "reflection metadata associated type descriptor __C.CrappyColor : Swift.RawRepresentable in __C_Synthesized"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$S28protocol_conformance_records15NativeValueTypeVAA8RuncibleAAMc() {
        let input = "$S28protocol_conformance_records15NativeValueTypeVAA8RuncibleAAMc"
        let output = "protocol conformance descriptor for protocol_conformance_records.NativeValueType : protocol_conformance_records.Runcible in protocol_conformance_records"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$ss6SimpleHr() {
        let input = "$ss6SimpleHr"
        let output = "protocol descriptor runtime record for Swift.Simple"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$ss5OtherVs6SimplesHc() {
        let input = "$ss5OtherVs6SimplesHc"
        let output = "protocol conformance descriptor runtime record for Swift.Other : Swift.Simple in Swift"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$ss5OtherVHn() {
        let input = "$ss5OtherVHn"
        let output = "nominal type descriptor runtime record for Swift.Other"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s18opaque_return_type3fooQryFQOHo() {
        let input = "$s18opaque_return_type3fooQryFQOHo"
        let output = "opaque type descriptor runtime record for <<opaque return type of opaque_return_type.foo() -> some>>"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$SSC9SomeErrorLeVD() {
        let input = "$SSC9SomeErrorLeVD"
        let output = "__C_Synthesized.related decl 'e' for SomeError"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s20mangling_retroactive5test0yyAA1ZVy12RetroactiveB1XVSiAE1YVAG0D1A1PAAyHCg_AiJ1QAAyHCg1_GF() {
        let input = "$s20mangling_retroactive5test0yyAA1ZVy12RetroactiveB1XVSiAE1YVAG0D1A1PAAyHCg_AiJ1QAAyHCg1_GF"
        let output = "mangling_retroactive.test0(mangling_retroactive.Z<RetroactiveB.X, Swift.Int, RetroactiveB.Y>) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s20mangling_retroactive5test0yyAA1ZVy12RetroactiveB1XVSiAE1YVAG0D1A1PHPyHCg_AiJ1QHPyHCg1_GF() {
        let input = "$s20mangling_retroactive5test0yyAA1ZVy12RetroactiveB1XVSiAE1YVAG0D1A1PHPyHCg_AiJ1QHPyHCg1_GF"
        let output = "mangling_retroactive.test0(mangling_retroactive.Z<RetroactiveB.X, Swift.Int, RetroactiveB.Y>) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s20mangling_retroactive5test0yyAA1ZVy12RetroactiveB1XVSiAE1YVAG0D1A1PHpyHCg_AiJ1QHpyHCg1_GF() {
        let input = "$s20mangling_retroactive5test0yyAA1ZVy12RetroactiveB1XVSiAE1YVAG0D1A1PHpyHCg_AiJ1QHpyHCg1_GF"
        let output = "mangling_retroactive.test0(mangling_retroactive.Z<RetroactiveB.X, Swift.Int, RetroactiveB.Y>) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func T0LiteralAByxGxd_tcfC() {
        let input = "_T0LiteralAByxGxd_tcfC"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func T0XZ() {
        let input = "_T0XZ"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TTSf() {
        let input = "_TTSf"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TtW0_j() {
        let input = "_TtW0_j"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TtW_4m3a3v() {
        let input = "_TtW_4m3a3v"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func TVGVGSS_2v0() {
        let input = "_TVGVGSS_2v0"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func _$SSD1BySSSBsg_G() {
        let input = "$SSD1BySSSBsg_G"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func _$S3BBBBf0602365061_() {
        let input = "_$S3BBBBf0602365061_"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func _$S3BBBBi0602365061_() {
        let input = "_$S3BBBBi0602365061_"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func _$S3BBBBv0602365061_() {
        let input = "_$S3BBBBv0602365061_"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func T0lxxxmmmTk() {
        let input = "_T0lxxxmmmTk"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func _$s3Bar3FooVAA5DrinkVyxGs5Error_pSeRzSERzlyShy4AbcdAHO6MemberVGALSeHPAKSeAAyHC_HCg_ALSEHPAKSEAAyHC_HCg0_Iseggozo_SgWOe() {
        let input = "$s3Bar3FooVAA5DrinkVyxGs5Error_pSeRzSERzlyShy4AbcdAHO6MemberVGALSeHPAKSeAAyHC_HCg_ALSEHPAKSEAAyHC_HCg0_Iseggozo_SgWOe"
        let output = "outlined consume of (@escaping @callee_guaranteed @substituted <A where A: Swift.Decodable, A: Swift.Encodable> (@guaranteed Bar.Foo) -> (@owned Bar.Drink<A>, @error @owned Swift.Error) for <Swift.Set<Abcd.Abcd.Member>>)?"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4Test5ProtoP8IteratorV10collectionAEy_qd__Gqd___tcfc() {
        let input = "$s4Test5ProtoP8IteratorV10collectionAEy_qd__Gqd___tcfc"
        let output = "Test.Proto.Iterator.init(collection: A1) -> Test.Proto.Iterator<A1>"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4test3fooV4blahyAA1SV1fQryFQOy_Qo_AHF() {
        let input = "$s4test3fooV4blahyAA1SV1fQryFQOy_Qo_AHF"
        let output = "test.foo.blah(<<opaque return type of test.S.f() -> some>>.0) -> <<opaque return type of test.S.f() -> some>>.0"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$S3nix8MystructV1xACyxGx_tcfc7MyaliasL_ayx__GD() {
        let input = "$S3nix8MystructV1xACyxGx_tcfc7MyaliasL_ayx__GD"
        let output = "Myalias #1 in nix.Mystruct<A>.init(x: A) -> nix.Mystruct<A>"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$S3nix7MyclassCfd7MyaliasL_ayx__GD() {
        let input = "$S3nix7MyclassCfd7MyaliasL_ayx__GD"
        let output = "Myalias #1 in nix.Myclass<A>.deinit"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$S3nix8MystructVyS2icig7MyaliasL_ayx__GD() {
        let input = "$S3nix8MystructVyS2icig7MyaliasL_ayx__GD"
        let output = "Myalias #1 in nix.Mystruct<A>.subscript.getter : (Swift.Int) -> Swift.Int"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$S3nix8MystructV1x1uACyxGx_qd__tclufc7MyaliasL_ayx_qd___GD() {
        let input = "$S3nix8MystructV1x1uACyxGx_qd__tclufc7MyaliasL_ayx_qd___GD"
        let output = "Myalias #1 in nix.Mystruct<A>.<A1>(x: A, u: A1) -> nix.Mystruct<A>"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$S3nix8MystructV6testit1xyx_tF7MyaliasL_ayx__GD() {
        let input = "$S3nix8MystructV6testit1xyx_tF7MyaliasL_ayx__GD"
        let output = "Myalias #1 in nix.Mystruct<A>.testit(x: A) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$S3nix8MystructV6testit1x1u1vyx_qd__qd_0_tr0_lF7MyaliasL_ayx_qd__qd_0__GD() {
        let input = "$S3nix8MystructV6testit1x1u1vyx_qd__qd_0_tr0_lF7MyaliasL_ayx_qd__qd_0__GD"
        let output = "Myalias #1 in nix.Mystruct<A>.testit<A1, B1>(x: A, u: A1, v: B1) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$S4blah8PatatinoaySiGD() {
        let input = "$S4blah8PatatinoaySiGD"
        let output = "blah.Patatino<Swift.Int>"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$SSiSHsWP() {
        let input = "$SSiSHsWP"
        let output = "protocol witness table for Swift.Int : Swift.Hashable in Swift"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$S7TestMod5OuterV3Fooayx_SiGD() {
        let input = "$S7TestMod5OuterV3Fooayx_SiGD"
        let output = "TestMod.Outer<A>.Foo<Swift.Int>"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$Ss17_VariantSetBufferO05CocoaC0ayx_GD() {
        let input = "$Ss17_VariantSetBufferO05CocoaC0ayx_GD"
        let output = "Swift._VariantSetBuffer<A>.CocoaBuffer"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$S2t21QP22ProtocolTypeAliasThingayAA4BlahV5SomeQa_GSgD() {
        let input = "$S2t21QP22ProtocolTypeAliasThingayAA4BlahV5SomeQa_GSgD"
        let output = "t2.Blah.SomeQ as t2.Q.ProtocolTypeAliasThing?"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s1A1gyyxlFx_qd__t_Ti5() {
        let input = "$s1A1gyyxlFx_qd__t_Ti5"
        let output = "inlined generic function <(A, A1)> of A.g<A>(A) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$S1T19protocol_resilience17ResilientProtocolPTl() {
        let input = "$S1T19protocol_resilience17ResilientProtocolPTl"
        let output = "associated type descriptor for protocol_resilience.ResilientProtocol.T"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$S18resilient_protocol21ResilientBaseProtocolTL() {
        let input = "$S18resilient_protocol21ResilientBaseProtocolTL"
        let output = "protocol requirements base descriptor for resilient_protocol.ResilientBaseProtocol"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$S1t1PP10AssocType2_AA1QTn() {
        let input = "$S1t1PP10AssocType2_AA1QTn"
        let output = "associated conformance descriptor for t.P.AssocType2: t.Q"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$S1t1PP10AssocType2_AA1QTN() {
        let input = "$S1t1PP10AssocType2_AA1QTN"
        let output = "default associated conformance accessor for t.P.AssocType2: t.Q"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4Test6testityyxlFAA8MystructV_TB5() {
        let input = "$s4Test6testityyxlFAA8MystructV_TB5"
        let output = "generic specialization <Test.Mystruct> of Test.testit<A>(A) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sSUss17FixedWidthIntegerRzrlEyxqd__cSzRd__lufCSu_SiTg5() {
        let input = "$sSUss17FixedWidthIntegerRzrlEyxqd__cSzRd__lufCSu_SiTg5"
        let output = "generic specialization <Swift.UInt, Swift.Int> of (extension in Swift):Swift.UnsignedInteger< where A: Swift.FixedWidthInteger>.init<A where A1: Swift.BinaryInteger>(A1) -> A"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4test7genFuncyyx_q_tr0_lFSi_SbTtt1g5() {
        let input = "$s4test7genFuncyyx_q_tr0_lFSi_SbTtt1g5"
        let output = "generic specialization <Swift.Int, Swift.Bool> of test.genFunc<A, B>(A, B) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sSD5IndexVy__GD() {
        let input = "$sSD5IndexVy__GD"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func _$s4test3StrCACycfC() {
        let input = "$s4test3StrCACycfC"
        let output = "test.Str.__allocating_init() -> test.Str"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s18keypaths_inlinable13KeypathStructV8computedSSvpACTKq() {
        let input = "$s18keypaths_inlinable13KeypathStructV8computedSSvpACTKq"
        let output = "key path getter for keypaths_inlinable.KeypathStruct.computed : Swift.String : keypaths_inlinable.KeypathStruct, serialized"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s3red4testyAA3ResOyxSayq_GAEs5ErrorAAq_sAFHD1__HCg_GADyxq_GsAFR_r0_lF() {
        let input = "$s3red4testyAA3ResOyxSayq_GAEs5ErrorAAq_sAFHD1__HCg_GADyxq_GsAFR_r0_lF"
        let output = "red.test<A, B where B: Swift.Error>(red.Res<A, B>) -> red.Res<A, [B]>"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s3red4testyAA7OurTypeOy4them05TheirD0Vy5AssocQzGAjE0F8ProtocolAAxAA0c7DerivedH0HD1_AA0c4BaseH0HI1_AieKHA2__HCg_GxmAaLRzlF() {
        let input = "$s3red4testyAA7OurTypeOy4them05TheirD0Vy5AssocQzGAjE0F8ProtocolAAxAA0c7DerivedH0HD1_AA0c4BaseH0HI1_AieKHA2__HCg_GxmAaLRzlF"
        let output = "red.test<A where A: red.OurDerivedProtocol>(A.Type) -> red.OurType<them.TheirType<A.Assoc>>"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s17property_wrappers10WithTuplesV9fractionsSd_S2dtvpfP() {
        let input = "$s17property_wrappers10WithTuplesV9fractionsSd_S2dtvpfP"
        let output = "property wrapper backing initializer of property_wrappers.WithTuples.fractions : (Swift.Double, Swift.Double, Swift.Double)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sSo17OS_dispatch_queueC4sync7executeyyyXE_tFTOTA() {
        let input = "$sSo17OS_dispatch_queueC4sync7executeyyyXE_tFTOTA"
        let output = "partial apply forwarder for @nonobjc __C.OS_dispatch_queue.sync(execute: () -> ()) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4main1gyySiXCvp() {
        let input = "$s4main1gyySiXCvp"
        let output = "main.g : @convention(c) (Swift.Int) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4main1gyySiXBvp() {
        let input = "$s4main1gyySiXBvp"
        let output = "main.g : @convention(block) (Swift.Int) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sxq_Ifgnr_D() {
        let input = "$sxq_Ifgnr_D"
        let output = "@differentiable(_forward) @callee_guaranteed (@in_guaranteed A) -> (@out B)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sxq_Irgnr_D() {
        let input = "$sxq_Irgnr_D"
        let output = "@differentiable(reverse) @callee_guaranteed (@in_guaranteed A) -> (@out B)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sxq_Idgnr_D() {
        let input = "$sxq_Idgnr_D"
        let output = "@differentiable @callee_guaranteed (@in_guaranteed A) -> (@out B)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sxq_Ilgnr_D() {
        let input = "$sxq_Ilgnr_D"
        let output = "@differentiable(_linear) @callee_guaranteed (@in_guaranteed A) -> (@out B)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sS3fIedgyywd_D() {
        let input = "$sS3fIedgyywd_D"
        let output = "@escaping @differentiable @callee_guaranteed (@unowned Swift.Float, @unowned @noDerivative Swift.Float) -> (@unowned Swift.Float)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sS5fIertyyywddw_D() {
        let input = "$sS5fIertyyywddw_D"
        let output = "@escaping @differentiable(reverse) @convention(thin) (@unowned Swift.Float, @unowned Swift.Float, @unowned @noDerivative Swift.Float) -> (@unowned Swift.Float, @unowned @noDerivative Swift.Float)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$syQo() {
        let input = "$syQo"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func _$s0059xxxxxxxxxxxxxxx_ttttttttBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBee() {
        let input = "$s0059xxxxxxxxxxxxxxx_ttttttttBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBee"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func _$sx1td_t() {
        let input = "$sx1td_t"
        let output = "(t: A...)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s7example1fyyYaF() {
        let input = "$s7example1fyyYaF"
        let output = "example.f() async -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s7example1fyyYaKF() {
        let input = "$s7example1fyyYaKF"
        let output = "example.f() async throws -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4main20receiveInstantiationyySo34__CxxTemplateInst12MagicWrapperIiEVzF() {
        let input = "$s4main20receiveInstantiationyySo34__CxxTemplateInst12MagicWrapperIiEVzF"
        let output = "main.receiveInstantiation(inout __C.__CxxTemplateInst12MagicWrapperIiE) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4main19returnInstantiationSo34__CxxTemplateInst12MagicWrapperIiEVyF() {
        let input = "$s4main19returnInstantiationSo34__CxxTemplateInst12MagicWrapperIiEVyF"
        let output = "main.returnInstantiation() -> __C.__CxxTemplateInst12MagicWrapperIiE"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4main6testityyYaFTu() {
        let input = "$s4main6testityyYaFTu"
        let output = "async function pointer to main.testit() async -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s13test_mangling3fooyS2f_S2ftFTJfUSSpSr() {
        let input = "$s13test_mangling3fooyS2f_S2ftFTJfUSSpSr"
        let output = "forward-mode derivative of test_mangling.foo(Swift.Float, Swift.Float, Swift.Float) -> Swift.Float with respect to parameters {1, 2} and results {0}"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s13test_mangling4foo21xq_x_t16_Differentiation14DifferentiableR_AA1P13TangentVectorRp_r0_lFAdERzAdER_AafGRpzAafHRQr0_lTJrSpSr() {
        let input = "$s13test_mangling4foo21xq_x_t16_Differentiation14DifferentiableR_AA1P13TangentVectorRp_r0_lFAdERzAdER_AafGRpzAafHRQr0_lTJrSpSr"
        let output = "reverse-mode derivative of test_mangling.foo2<A, B where B: _Differentiation.Differentiable, B.TangentVector: test_mangling.P>(x: A) -> B with respect to parameters {0} and results {0} with <A, B where A: _Differentiation.Differentiable, B: _Differentiation.Differentiable, A.TangentVector: test_mangling.P, B.TangentVector: test_mangling.P>"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s13test_mangling4foo21xq_x_t16_Differentiation14DifferentiableR_AA1P13TangentVectorRp_r0_lFAdERzAdER_AafGRpzAafHRQr0_lTJVrSpSr() {
        let input = "$s13test_mangling4foo21xq_x_t16_Differentiation14DifferentiableR_AA1P13TangentVectorRp_r0_lFAdERzAdER_AafGRpzAafHRQr0_lTJVrSpSr"
        let output = "vtable thunk for reverse-mode derivative of test_mangling.foo2<A, B where B: _Differentiation.Differentiable, B.TangentVector: test_mangling.P>(x: A) -> B with respect to parameters {0} and results {0} with <A, B where A: _Differentiation.Differentiable, B: _Differentiation.Differentiable, A.TangentVector: test_mangling.P, B.TangentVector: test_mangling.P>"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s13test_mangling3fooyS2f_xq_t16_Differentiation14DifferentiableR_r0_lFAcDRzAcDR_r0_lTJpUSSpSr() {
        let input = "$s13test_mangling3fooyS2f_xq_t16_Differentiation14DifferentiableR_r0_lFAcDRzAcDR_r0_lTJpUSSpSr"
        let output = "pullback of test_mangling.foo<A, B where B: _Differentiation.Differentiable>(Swift.Float, A, B) -> Swift.Float with respect to parameters {1, 2} and results {0} with <A, B where A: _Differentiation.Differentiable, B: _Differentiation.Differentiable>"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s13test_mangling4foo21xq_x_t16_Differentiation14DifferentiableR_AA1P13TangentVectorRp_r0_lFTSAdERzAdER_AafGRpzAafHRQr0_lTJrSpSr() {
        let input = "$s13test_mangling4foo21xq_x_t16_Differentiation14DifferentiableR_AA1P13TangentVectorRp_r0_lFTSAdERzAdER_AafGRpzAafHRQr0_lTJrSpSr"
        let output = "reverse-mode derivative of protocol self-conformance witness for test_mangling.foo2<A, B where B: _Differentiation.Differentiable, B.TangentVector: test_mangling.P>(x: A) -> B with respect to parameters {0} and results {0} with <A, B where A: _Differentiation.Differentiable, B: _Differentiation.Differentiable, A.TangentVector: test_mangling.P, B.TangentVector: test_mangling.P>"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s13test_mangling3fooyS2f_xq_t16_Differentiation14DifferentiableR_r0_lFAcDRzAcDR_r0_lTJpUSSpSrTj() {
        let input = "$s13test_mangling3fooyS2f_xq_t16_Differentiation14DifferentiableR_r0_lFAcDRzAcDR_r0_lTJpUSSpSrTj"
        let output = "dispatch thunk of pullback of test_mangling.foo<A, B where B: _Differentiation.Differentiable>(Swift.Float, A, B) -> Swift.Float with respect to parameters {1, 2} and results {0} with <A, B where A: _Differentiation.Differentiable, B: _Differentiation.Differentiable>"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s13test_mangling3fooyS2f_xq_t16_Differentiation14DifferentiableR_r0_lFAcDRzAcDR_r0_lTJpUSSpSrTq() {
        let input = "$s13test_mangling3fooyS2f_xq_t16_Differentiation14DifferentiableR_r0_lFAcDRzAcDR_r0_lTJpUSSpSrTq"
        let output = "method descriptor for pullback of test_mangling.foo<A, B where B: _Differentiation.Differentiable>(Swift.Float, A, B) -> Swift.Float with respect to parameters {1, 2} and results {0} with <A, B where A: _Differentiation.Differentiable, B: _Differentiation.Differentiable>"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s13TangentVector16_Differentiation14DifferentiablePQzAaDQy_SdAFIegnnnr_TJSdSSSpSrSUSP() {
        let input = "$s13TangentVector16_Differentiation14DifferentiablePQzAaDQy_SdAFIegnnnr_TJSdSSSpSrSUSP"
        let output = "autodiff subset parameters thunk for differential from @escaping @callee_guaranteed (@in_guaranteed A._Differentiation.Differentiable.TangentVector, @in_guaranteed B._Differentiation.Differentiable.TangentVector, @in_guaranteed Swift.Double) -> (@out B._Differentiation.Differentiable.TangentVector) with respect to parameters {0, 1, 2} and results {0} to parameters {0, 2}"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s13TangentVector16_Differentiation14DifferentiablePQy_AaDQzAESdIegnrrr_TJSpSSSpSrSUSP() {
        let input = "$s13TangentVector16_Differentiation14DifferentiablePQy_AaDQzAESdIegnrrr_TJSpSSSpSrSUSP"
        let output = "autodiff subset parameters thunk for pullback from @escaping @callee_guaranteed (@in_guaranteed B._Differentiation.Differentiable.TangentVector) -> (@out A._Differentiation.Differentiable.TangentVector, @out B._Differentiation.Differentiable.TangentVector, @out Swift.Double) with respect to parameters {0, 1, 2} and results {0} to parameters {0, 2}"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s39differentiation_subset_parameters_thunk19inoutIndirectCalleryq_x_q_q0_t16_Differentiation14DifferentiableRzAcDR_AcDR0_r1_lFxq_Sdq_xq_Sdr0_ly13TangentVectorAcDPQy_AeFQzIsegnrr_Iegnnnro_TJSrSSSpSrSUSP() {
        let input = "$s39differentiation_subset_parameters_thunk19inoutIndirectCalleryq_x_q_q0_t16_Differentiation14DifferentiableRzAcDR_AcDR0_r1_lFxq_Sdq_xq_Sdr0_ly13TangentVectorAcDPQy_AeFQzIsegnrr_Iegnnnro_TJSrSSSpSrSUSP"
        let output = "autodiff subset parameters thunk for reverse-mode derivative from differentiation_subset_parameters_thunk.inoutIndirectCaller<A, B, C where A: _Differentiation.Differentiable, B: _Differentiation.Differentiable, C: _Differentiation.Differentiable>(A, B, C) -> B with respect to parameters {0, 1, 2} and results {0} to parameters {0, 2} of type @escaping @callee_guaranteed (@in_guaranteed A, @in_guaranteed B, @in_guaranteed Swift.Double) -> (@out B, @owned @escaping @callee_guaranteed @substituted <A, B> (@in_guaranteed A) -> (@out B, @out Swift.Double) for <B._Differentiation.Differentiable.TangentVectorA._Differentiation.Differentiable.TangentVector>)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sS2f8mangling3FooV13TangentVectorVIegydd_SfAESfIegydd_TJOp() {
        let input = "$sS2f8mangling3FooV13TangentVectorVIegydd_SfAESfIegydd_TJOp"
        let output = "autodiff self-reordering reabstraction thunk for pullback from @escaping @callee_guaranteed (@unowned Swift.Float) -> (@unowned Swift.Float, @unowned mangling.Foo.TangentVector) to @escaping @callee_guaranteed (@unowned Swift.Float) -> (@unowned mangling.Foo.TangentVector, @unowned Swift.Float)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s13test_mangling3fooyS2f_S2ftFWJrSpSr() {
        let input = "$s13test_mangling3fooyS2f_S2ftFWJrSpSr"
        let output = "reverse-mode differentiability witness for test_mangling.foo(Swift.Float, Swift.Float, Swift.Float) -> Swift.Float with respect to parameters {0} and results {0}"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s13test_mangling3fooyS2f_xq_t16_Differentiation14DifferentiableR_r0_lFAcDRzAcDR_r0_lWJrUSSpSr() {
        let input = "$s13test_mangling3fooyS2f_xq_t16_Differentiation14DifferentiableR_r0_lFAcDRzAcDR_r0_lWJrUSSpSr"
        let output = "reverse-mode differentiability witness for test_mangling.foo<A, B where B: _Differentiation.Differentiable>(Swift.Float, A, B) -> Swift.Float with respect to parameters {1, 2} and results {0} with <A, B where A: _Differentiation.Differentiable, B: _Differentiation.Differentiable>"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s5async1hyyS2iYbXEF() {
        let input = "$s5async1hyyS2iYbXEF"
        let output = "async.h(@Sendable (Swift.Int) -> Swift.Int) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s5Actor02MyA0C17testAsyncFunctionyyYaKFTY0_() {
        let input = "$s5Actor02MyA0C17testAsyncFunctionyyYaKFTY0_"
        let output = "(1) suspend resume partial function for Actor.MyActor.testAsyncFunction() async throws -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s5Actor02MyA0C17testAsyncFunctionyyYaKFTQ1_() {
        let input = "$s5Actor02MyA0C17testAsyncFunctionyyYaKFTQ1_"
        let output = "(2) await resume partial function for Actor.MyActor.testAsyncFunction() async throws -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4diff1hyyS2iYjfXEF() {
        let input = "$s4diff1hyyS2iYjfXEF"
        let output = "diff.h(@differentiable(_forward) (Swift.Int) -> Swift.Int) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4diff1hyyS2iYjrXEF() {
        let input = "$s4diff1hyyS2iYjrXEF"
        let output = "diff.h(@differentiable(reverse) (Swift.Int) -> Swift.Int) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4diff1hyyS2iYjdXEF() {
        let input = "$s4diff1hyyS2iYjdXEF"
        let output = "diff.h(@differentiable (Swift.Int) -> Swift.Int) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4diff1hyyS2iYjlXEF() {
        let input = "$s4diff1hyyS2iYjlXEF"
        let output = "diff.h(@differentiable(_linear) (Swift.Int) -> Swift.Int) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4test3fooyyS2f_SfYkztYjrXEF() {
        let input = "$s4test3fooyyS2f_SfYkztYjrXEF"
        let output = "test.foo(@differentiable(reverse) (Swift.Float, inout @noDerivative Swift.Float) -> Swift.Float) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4test3fooyyS2f_SfYkntYjrXEF() {
        let input = "$s4test3fooyyS2f_SfYkntYjrXEF"
        let output = "test.foo(@differentiable(reverse) (Swift.Float, __owned @noDerivative Swift.Float) -> Swift.Float) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4test3fooyyS2f_SfYktYjrXEF() {
        let input = "$s4test3fooyyS2f_SfYktYjrXEF"
        let output = "test.foo(@differentiable(reverse) (Swift.Float, @noDerivative Swift.Float) -> Swift.Float) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4test3fooyyS2f_SfYktYaYbYjrXEF() {
        let input = "$s4test3fooyyS2f_SfYktYaYbYjrXEF"
        let output = "test.foo(@differentiable(reverse) @Sendable (Swift.Float, @noDerivative Swift.Float) async -> Swift.Float) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sScA() {
        let input = "$sScA"
        let output = "Swift.Actor"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sScGySiG() {
        let input = "$sScGySiG"
        let output = "Swift.TaskGroup<Swift.Int>"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4test10returnsOptyxycSgxyScMYccSglF() {
        let input = "$s4test10returnsOptyxycSgxyScMYccSglF"
        let output = "test.returnsOpt<A>((@Swift.MainActor () -> A)?) -> (() -> A)?"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sSvSgA3ASbIetCyyd_SgSbIetCyyyd_SgD() {
        let input = "$sSvSgA3ASbIetCyyd_SgSbIetCyyyd_SgD"
        let output = "(@escaping @convention(thin) @convention(c) (@unowned Swift.UnsafeMutableRawPointer?, @unowned Swift.UnsafeMutableRawPointer?, @unowned (@escaping @convention(thin) @convention(c) (@unowned Swift.UnsafeMutableRawPointer?, @unowned Swift.UnsafeMutableRawPointer?) -> (@unowned Swift.Bool))?) -> (@unowned Swift.Bool))?"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s1t10globalFuncyyAA7MyActorCYiF() {
        let input = "$s1t10globalFuncyyAA7MyActorCYiF"
        let output = "t.globalFunc(isolated t.MyActor) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sSIxip6foobarP() {
        let input = "$sSIxip6foobarP"
        let output = "foobar in Swift.DefaultIndices.subscript : A"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s13__lldb_expr_110$10016c2d8yXZ1B10$10016c2e0LLC() {
        let input = "$s13__lldb_expr_110$10016c2d8yXZ1B10$10016c2e0LLC"
        let output = "__lldb_expr_1.(unknown context at $10016c2d8).(B in $10016c2e0)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s__TJO() {
        let input = "$s__TJO"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func _$s6Foobar7Vector2VAASdRszlE10simdMatrix5scale6rotate9translateSo0C10_double3x3aACySdG_SdAJtFZ0D4TypeL_aySd__GD() {
        let input = "$s6Foobar7Vector2VAASdRszlE10simdMatrix5scale6rotate9translateSo0C10_double3x3aACySdG_SdAJtFZ0D4TypeL_aySd__GD"
        let output = "MatrixType #1 in static (extension in Foobar):Foobar.Vector2<Swift.Double><A where A == Swift.Double>.simdMatrix(scale: Foobar.Vector2<Swift.Double>, rotate: Swift.Double, translate: Foobar.Vector2<Swift.Double>) -> __C.simd_double3x3"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s17distributed_thunk2DAC1fyyFTE() {
        let input = "$s17distributed_thunk2DAC1fyyFTE"
        let output = "distributed thunk distributed_thunk.DA.f() -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s16distributed_test1XC7computeyS2iFTF() {
        let input = "$s16distributed_test1XC7computeyS2iFTF"
        let output = "distributed accessor for distributed_test.X.compute(Swift.Int) -> Swift.Int"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s27distributed_actor_accessors7MyActorC7simple2ySSSiFTETFHF() {
        let input = "$s27distributed_actor_accessors7MyActorC7simple2ySSSiFTETFHF"
        let output = "accessible function runtime record for distributed accessor for distributed thunk distributed_actor_accessors.MyActor.simple2(Swift.Int) -> Swift.String"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s1A3bar1aySSYt_tF() {
        let input = "$s1A3bar1aySSYt_tF"
        let output = "A.bar(a: _const Swift.String) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s1t1fyyFSiAA3StrVcs7KeyPathCyADSiGcfu_SiADcfu0_33_556644b740b1b333fecb81e55a7cce98ADSiTf3npk_n() {
        let input = "$s1t1fyyFSiAA3StrVcs7KeyPathCyADSiGcfu_SiADcfu0_33_556644b740b1b333fecb81e55a7cce98ADSiTf3npk_n"
        let output = "function signature specialization <Arg[1] = [Constant Propagated KeyPath : _556644b740b1b333fecb81e55a7cce98<t.Str,Swift.Int>]> of implicit closure #2 (t.Str) -> Swift.Int in implicit closure #1 (Swift.KeyPath<t.Str, Swift.Int>) -> (t.Str) -> Swift.Int in t.f() -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s21back_deploy_attribute0A12DeployedFuncyyFTwb() {
        let input = "$s21back_deploy_attribute0A12DeployedFuncyyFTwb"
        let output = "back deployment thunk for back_deploy_attribute.backDeployedFunc() -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s21back_deploy_attribute0A12DeployedFuncyyFTwB() {
        let input = "$s21back_deploy_attribute0A12DeployedFuncyyFTwB"
        let output = "back deployment fallback for back_deploy_attribute.backDeployedFunc() -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4test3fooyyAA1P_px1TRts_XPlF() {
        let input = "$s4test3fooyyAA1P_px1TRts_XPlF"
        let output = "test.foo<A>(any test.P<Self.T == A>) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4test3fooyyAA1P_pSS1TAaCPRts_Si1UAERtsXPF() {
        let input = "$s4test3fooyyAA1P_pSS1TAaCPRts_Si1UAERtsXPF"
        let output = "test.foo(any test.P<Self.test.P.T == Swift.String, Self.test.P.U == Swift.Int>) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4test3FooVAAyyAA1P_pF() {
        let input = "$s4test3FooVAAyyAA1P_pF"
        let output = "test.Foo.test(test.P) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sxxxIxzCXxxxesy() {
        let input = "$sxxxIxzCXxxxesy"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func _$Sxxx_x_xxIxzCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC$x() {
        let input = "$Sxxx_x_xxIxzCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC$x"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func _$sxIeghHr_xs5Error_pIegHrzo_s8SendableRzs5NeverORs_r0_lTRTATQ0_() {
        let input = "$sxIeghHr_xs5Error_pIegHrzo_s8SendableRzs5NeverORs_r0_lTRTATQ0_"
        let output = "(1) await resume partial function for partial apply forwarder for reabstraction thunk helper <A, B where A: Swift.Sendable, B == Swift.Never> from @escaping @callee_guaranteed @Sendable @async () -> (@out A) to @escaping @callee_guaranteed @async () -> (@out A, @error @owned Swift.Error)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sxIeghHr_xs5Error_pIegHrzo_s8SendableRzs5NeverORs_r0_lTRTQ0_() {
        let input = "$sxIeghHr_xs5Error_pIegHrzo_s8SendableRzs5NeverORs_r0_lTRTQ0_"
        let output = "(1) await resume partial function for reabstraction thunk helper <A, B where A: Swift.Sendable, B == Swift.Never> from @escaping @callee_guaranteed @Sendable @async () -> (@out A) to @escaping @callee_guaranteed @async () -> (@out A, @error @owned Swift.Error)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sxIeghHr_xs5Error_pIegHrzo_s8SendableRzs5NeverORs_r0_lTRTY0_() {
        let input = "$sxIeghHr_xs5Error_pIegHrzo_s8SendableRzs5NeverORs_r0_lTRTY0_"
        let output = "(1) suspend resume partial function for reabstraction thunk helper <A, B where A: Swift.Sendable, B == Swift.Never> from @escaping @callee_guaranteed @Sendable @async () -> (@out A) to @escaping @callee_guaranteed @async () -> (@out A, @error @owned Swift.Error)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sxIeghHr_xs5Error_pIegHrzo_s8SendableRzs5NeverORs_r0_lTRTY_() {
        let input = "$sxIeghHr_xs5Error_pIegHrzo_s8SendableRzs5NeverORs_r0_lTRTY_"
        let output = "(0) suspend resume partial function for reabstraction thunk helper <A, B where A: Swift.Sendable, B == Swift.Never> from @escaping @callee_guaranteed @Sendable @async () -> (@out A) to @escaping @callee_guaranteed @async () -> (@out A, @error @owned Swift.Error)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sxIeghHr_xs5Error_pIegHrzo_s8SendableRzs5NeverORs_r0_lTRTQ12_() {
        let input = "$sxIeghHr_xs5Error_pIegHrzo_s8SendableRzs5NeverORs_r0_lTRTQ12_"
        let output = "(13) await resume partial function for reabstraction thunk helper <A, B where A: Swift.Sendable, B == Swift.Never> from @escaping @callee_guaranteed @Sendable @async () -> (@out A) to @escaping @callee_guaranteed @async () -> (@out A, @error @owned Swift.Error)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s7Library3fooyyFTwS() {
        let input = "$s7Library3fooyyFTwS"
        let output = "#_hasSymbol query for Library.foo() -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s7Library5KlassCTwS() {
        let input = "$s7Library5KlassCTwS"
        let output = "#_hasSymbol query for Library.Klass"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s14swift_ide_test14myColorLiteral3red5green4blue5alphaAA0E0VSf_S3ftcfm() {
        let input = "$s14swift_ide_test14myColorLiteral3red5green4blue5alphaAA0E0VSf_S3ftcfm"
        let output = "swift_ide_test.myColorLiteral(red: Swift.Float, green: Swift.Float, blue: Swift.Float, alpha: Swift.Float) -> swift_ide_test.Color"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s14swift_ide_test10myFilenamexfm() {
        let input = "$s14swift_ide_test10myFilenamexfm"
        let output = "swift_ide_test.myFilename : A"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s9MacroUser13testStringify1a1bySi_SitF9stringifyfMf1_() {
        let input = "$s9MacroUser13testStringify1a1bySi_SitF9stringifyfMf1_"
        let output = "freestanding macro expansion #3 of stringify in MacroUser.testStringify(a: Swift.Int, b: Swift.Int) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s9MacroUser016testFreestandingA9ExpansionyyF4Foo3L_V23bitwidthNumberedStructsfMf_6methodfMu0_() {
        let input = "$s9MacroUser016testFreestandingA9ExpansionyyF4Foo3L_V23bitwidthNumberedStructsfMf_6methodfMu0_"
        let output = "unique name #2 of method in freestanding macro expansion #1 of bitwidthNumberedStructs in Foo3 #1 in MacroUser.testFreestandingMacroExpansion() -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func at__swiftmacro_1a13testStringifyAA1bySi_SitF9stringifyfMf_() {
        let input = "@__swiftmacro_1a13testStringifyAA1bySi_SitF9stringifyfMf_"
        let output = "freestanding macro expansion #1 of stringify in a.testStringify(a: Swift.Int, b: Swift.Int) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func at__swiftmacro_18macro_expand_peers1SV1f20addCompletionHandlerfMp_() {
        let input = "@__swiftmacro_18macro_expand_peers1SV1f20addCompletionHandlerfMp_"
        let output = "peer macro @addCompletionHandler expansion #1 of f in macro_expand_peers.S"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func at__swiftmacro_9MacroUser16MemberNotCoveredV33_4361AD9339943F52AE6186DD51E04E91Ll0dE0fMf0_() {
        let input = "@__swiftmacro_9MacroUser16MemberNotCoveredV33_4361AD9339943F52AE6186DD51E04E91Ll0dE0fMf0_"
        let output = "freestanding macro expansion #2 of NotCovered(in _4361AD9339943F52AE6186DD51E04E91) in MacroUser.MemberNotCovered"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sxSo8_NSRangeVRlzCRl_Cr0_llySo12ModelRequestCyxq_GIsPetWAlYl_TC() {
        let input = "$sxSo8_NSRangeVRlzCRl_Cr0_llySo12ModelRequestCyxq_GIsPetWAlYl_TC"
        let output = "coroutine continuation prototype for @escaping @convention(thin) @convention(witness_method) @yield_once <A, B where A: AnyObject, B: AnyObject> @substituted <A> (@inout A) -> (@yields @inout __C._NSRange) for <__C.ModelRequest<A, B>>"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$SyyySGSS_IIxxxxx____xsIyFSySIxx_atxIxx____xxI() {
        let input = "$SyyySGSS_IIxxxxx____xsIyFSySIxx_@xIxx____xxI"
        do {
            let demangled = try demangleAsNode(input).description
            Issue.record("Invalid input \(input) should throw an error, instead returned \(demangled)")
        } catch {}
    }

    @Test func _$s12typed_throws15rethrowConcreteyyAA7MyErrorOYKF() {
        let input = "$s12typed_throws15rethrowConcreteyyAA7MyErrorOYKF"
        let output = "typed_throws.rethrowConcrete() throws(typed_throws.MyError) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s3red3use2fnySiyYAXE_tF() {
        let input = "$s3red3use2fnySiyYAXE_tF"
        let output = "red.use(fn: @isolated(any) () -> Swift.Int) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4testAAyAA5KlassC_ACtACnYTF() {
        let input = "$s4testAAyAA5KlassC_ACtACnYTF"
        let output = "test.test(__owned test.Klass) -> sending (test.Klass, test.Klass)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s5test24testyyAA5KlassCnYuF() {
        let input = "$s5test24testyyAA5KlassCnYuF"
        let output = "test2.test(sending __owned test2.Klass) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s7ElementSTQzqd__s5Error_pIgnrzo_ABqd__sAC_pIegnrzr_SlRzr__lTR() {
        let input = "$s7ElementSTQzqd__s5Error_pIgnrzo_ABqd__sAC_pIegnrzr_SlRzr__lTR"
        let output = "reabstraction thunk helper <A><A1 where A: Swift.Collection> from @callee_guaranteed (@in_guaranteed A.Swift.Sequence.Element) -> (@out A1, @error @owned Swift.Error) to @escaping @callee_guaranteed (@in_guaranteed A.Swift.Sequence.Element) -> (@out A1, @error @out Swift.Error)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sS3fIedgyywTd_D() {
        let input = "$sS3fIedgyywTd_D"
        let output = "@escaping @differentiable @callee_guaranteed (@unowned Swift.Float, @unowned @noDerivative sending Swift.Float) -> (@unowned Swift.Float)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sS3fIedgyyTd_D() {
        let input = "$sS3fIedgyyTd_D"
        let output = "@escaping @differentiable @callee_guaranteed (@unowned Swift.Float, @unowned sending Swift.Float) -> (@unowned Swift.Float)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4testA2A5KlassCyYTF() {
        let input = "$s4testA2A5KlassCyYTF"
        let output = "test.test() -> sending test.Klass"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4main5KlassCACYTcMD() {
        let input = "$s4main5KlassCACYTcMD"
        let output = "demangling cache variable for type metadata for (main.Klass) -> sending main.Klass"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4null19transferAsyncResultAA16NonSendableKlassCyYaYTF() {
        let input = "$s4null19transferAsyncResultAA16NonSendableKlassCyYaYTF"
        let output = "null.transferAsyncResult() async -> sending null.NonSendableKlass"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4null16NonSendableKlassCIegHo_ACs5Error_pIegHTrzo_TR() {
        let input = "$s4null16NonSendableKlassCIegHo_ACs5Error_pIegHTrzo_TR"
        let output = "reabstraction thunk helper from @escaping @callee_guaranteed @async () -> (@owned null.NonSendableKlass) to @escaping @callee_guaranteed @async () -> sending (@out null.NonSendableKlass, @error @owned Swift.Error)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sSRyxG15Synchronization19AtomicRepresentableABRi_zrlMc() {
        let input = "$sSRyxG15Synchronization19AtomicRepresentableABRi_zrlMc"
        let output = "protocol conformance descriptor for < where A: ~Swift.Copyable> Swift.UnsafeBufferPointer<A> : Synchronization.AtomicRepresentable in Synchronization"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sSRyxG15Synchronization19AtomicRepresentableABRi0_zrlMc() {
        let input = "$sSRyxG15Synchronization19AtomicRepresentableABRi0_zrlMc"
        let output = "protocol conformance descriptor for < where A: ~Swift.Escapable> Swift.UnsafeBufferPointer<A> : Synchronization.AtomicRepresentable in Synchronization"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sSRyxG15Synchronization19AtomicRepresentableABRi1_zrlMc() {
        let input = "$sSRyxG15Synchronization19AtomicRepresentableABRi1_zrlMc"
        let output = "protocol conformance descriptor for < where A: ~Swift.<bit 2>> Swift.UnsafeBufferPointer<A> : Synchronization.AtomicRepresentable in Synchronization"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s23variadic_generic_opaque2G2VyAA2S1V_AA2S2VQPGAA1PHPAeA1QHPyHC_AgaJHPyHCHX_HC() {
        let input = "$s23variadic_generic_opaque2G2VyAA2S1V_AA2S2VQPGAA1PHPAeA1QHPyHC_AgaJHPyHCHX_HC"
        let output = "concrete protocol conformance variadic_generic_opaque.G2<Pack{variadic_generic_opaque.S1, variadic_generic_opaque.S2}> to protocol conformance ref (type's module) variadic_generic_opaque.P with conditional requirements: (pack protocol conformance (concrete protocol conformance variadic_generic_opaque.S1 to protocol conformance ref (type's module) variadic_generic_opaque.Q, concrete protocol conformance variadic_generic_opaque.S2 to protocol conformance ref (type's module) variadic_generic_opaque.Q))"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s9MacroUser0023macro_expandswift_elFCffMX436_4_23bitwidthNumberedStructsfMf_() {
        let input = "$s9MacroUser0023macro_expandswift_elFCffMX436_4_23bitwidthNumberedStructsfMf_"
        let output = "freestanding macro expansion #1 of bitwidthNumberedStructs in module MacroUser file macro_expand.swift line 437 column 5"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$sxq_IyXd_D() {
        let input = "$sxq_IyXd_D"
        let output = "@callee_unowned (@in_cxx A) -> (@unowned B)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s2hi1SV1iSivx() {
        let input = "$s2hi1SV1iSivx"
        let output = "hi.S.i.modify2 : Swift.Int"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s2hi1SV1iSivy() {
        let input = "$s2hi1SV1iSivy"
        let output = "hi.S.i.read2 : Swift.Int"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s2hi1SVIetMIy_TC() {
        let input = "$s2hi1SVIetMIy_TC"
        let output = "coroutine continuation prototype for @escaping @convention(thin) @convention(method) @yield_once_2 (@unowned hi.S) -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4mainAAyyycAA1CCFTTI() {
        let input = "$s4mainAAyyycAA1CCFTTI"
        let output = "identity thunk of main.main(main.C) -> () -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4mainAAyyycAA1CCFTTH() {
        let input = "$s4mainAAyyycAA1CCFTTH"
        let output = "hop to main actor thunk of main.main(main.C) -> () -> ()"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s4main4SlabVy$1_SiG() {
        let input = "$s4main4SlabVy$1_SiG"
        let output = "main.Slab<2, Swift.Int>"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s$n3_SSBV() {
        let input = "$s$n3_SSBV"
        let output = "Builtin.FixedArray<-4, Swift.String>"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s3red7MyActorC3runyxxyYaKACYcYTXEYaKlFZ() {
        let input = "$s3red7MyActorC3runyxxyYaKACYcYTXEYaKlFZ"
        let output = "static red.MyActor.run<A>(@red.MyActor () async throws -> sending A) async throws -> A"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s3red7MyActorC3runyxxyYaKYAYTXEYaKlFZ() {
        let input = "$s3red7MyActorC3runyxxyYaKYAYTXEYaKlFZ"
        let output = "static red.MyActor.run<A>(@isolated(any) () async throws -> sending A) async throws -> A"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s7ToolKit10TypedValueOACs5Error_pIgHTnTrzo_A2CsAD_pIegHiTrzr_TR() {
        let input = "$s7ToolKit10TypedValueOACs5Error_pIgHTnTrzo_A2CsAD_pIegHiTrzr_TR"
        let output = "reabstraction thunk helper from @callee_guaranteed @async (@in_guaranteed sending ToolKit.TypedValue) -> sending (@out ToolKit.TypedValue, @error @owned Swift.Error) to @escaping @callee_guaranteed @async (@in sending ToolKit.TypedValue) -> (@out ToolKit.TypedValue, @error @out Swift.Error)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }

    @Test func _$s16sending_mangling16NonSendableKlassCACIegTiTr_A2CIegTxTo_TR() {
        let input = "$s16sending_mangling16NonSendableKlassCACIegTiTr_A2CIegTxTo_TR"
        let output = "reabstraction thunk helper from @escaping @callee_guaranteed (@in sending sending_mangling.NonSendableKlass) -> sending (@out sending_mangling.NonSendableKlass) to @escaping @callee_guaranteed (@owned sending sending_mangling.NonSendableKlass) -> sending (@owned sending_mangling.NonSendableKlass)"
        do {
            let parsed = try demangleAsNode(input)
            let result = parsed.print(using: .default.union(.synthesizeSugarOnTypes))
            #expect(result == output, "Failed to demangle \(input).\nGot\n    \(result)\nexpected\n    \(output)")
        } catch {
            Issue.record("Failed to demangle \(input). Got \(error), expected \(output)")
        }
    }
}
