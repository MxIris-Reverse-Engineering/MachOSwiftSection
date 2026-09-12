/// `SwiftThunkAnalysis` — recovering a kind-9 accessor-function symbolic
/// reference's answer without running the thunk.
///
/// Evolution proposal `offline-opaque-accessor-thunk-resolution`.
///
/// ## Why this is a target of its own
///
/// When a mangled name would use a feature the deployment target's runtime
/// demangler does not know — or, in SwiftUI's case, when an opaque result type
/// is *availability-conditional* (SE-0360, `if #available` returning different
/// types) — IRGen does not embed a type name at all. It embeds `0x09` plus a
/// relative pointer to a metadata accessor thunk, and the runtime calls that
/// function instead of demangling. Offline that leaves a raw address where a
/// type belongs.
///
/// Reading the answer back means decoding the thunk's instructions, which
/// needs a disassembler. That is the only thing in this package that does, so
/// it is a target of its own rather than part of the rendering layer: the
/// engine stays out of every module that does not read thunks.
///
/// ## Direction of the dependency
///
/// `SwiftDeclarationRendering` depends on this target and calls
/// ``AccessorThunkReader`` directly from its kind-9 rewriter; this target
/// knows nothing about the rendering layer. The first landing ran the
/// dependency the other way, behind an opt-in trait; the decision log of
/// evolution proposal `offline-opaque-accessor-thunk-resolution` records why
/// that was dropped.
