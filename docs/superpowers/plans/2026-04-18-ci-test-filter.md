# CI Test Filter and macOS 26 Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restrict CI test runs to five `SymbolTestsCore`-based test classes and bump both workflows to macOS 26 + Xcode 26.4.

**Architecture:** Pure CI configuration change. No source-code edits. Apply a `--filter` regex to `swift test` in `.github/workflows/macOS.yml`, and bump the runner image and Xcode version in both `macOS.yml` and `release.yml`. Verify the regex selects exactly the intended five test classes, then commit each workflow change separately.

**Tech Stack:** GitHub Actions, `xcodebuild`, SwiftPM `swift test --filter`.

**Spec:** `docs/superpowers/specs/2026-04-18-ci-test-filter-design.md`

---

## File Structure

| File | Change |
|---|---|
| `.github/workflows/macOS.yml` | Modify `matrix.os`, `matrix.xcode-version`, and the two `swift test` invocations (add `--filter`) |
| `.github/workflows/release.yml` | Modify `runs-on` and the `Setup Xcode` `xcode-version` |

No new files. No source files touched.

---

## Task 1: Verify the `--filter` regex locally

**Files:** none modified. Verification only.

**Goal:** Confirm the proposed regex matches exactly the five target test classes and nothing else:

- `SwiftDumpTests.SymbolTestsCoreDumpSnapshotTests`
- `SwiftInterfaceTests.SymbolTestsCoreInterfaceSnapshotTests`
- `SwiftDumpTests.SymbolTestsCoreCoverageInvariantTests`
- `SwiftInterfaceTests.STCoreE2ETests`
- `SwiftInterfaceTests.STCoreTests`

The proposed regex is:

```
\.(SymbolTestsCoreDumpSnapshotTests|SymbolTestsCoreInterfaceSnapshotTests|SymbolTestsCoreCoverageInvariantTests|STCoreE2ETests|STCoreTests)(/|$)
```

Note on tooling: in the current Swift toolchain, `swift test --list-tests` is deprecated and `swift test list` does not accept `--filter`. We therefore enumerate every test ID with `swift test list`, then apply the regex with local `grep -E` to simulate what SwiftPM's `--filter` will admit at CI time.

- [ ] **Step 1: Confirm the SymbolTestsCore fixture framework exists**

Run:

```
ls Tests/Projects/SymbolTests/DerivedData/SymbolTests/Build/Products/Release/SymbolTestsCore.framework/Versions/A/SymbolTestsCore
```

Expected: the path lists. If it does not, build it once before continuing:

```
xcodebuild \
  -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj \
  -scheme SymbolTestsCore \
  -configuration Release \
  -derivedDataPath Tests/Projects/SymbolTests/DerivedData \
  -destination 'generic/platform=macOS' \
  build
```

- [ ] **Step 2: Enumerate every test ID**

Run from repo root (allow up to 10 minutes — SwiftPM may build the entire test target graph on first run):

```
swift test list 2>&1 | tee /tmp/macho-all-tests.txt
```

Expected: the file ends with hundreds of lines of the form `<TargetName>.<ClassName>/<methodName>` (plus some build-progress noise lines that the later grep ignores).

- [ ] **Step 3: Apply the proposed regex and capture matches**

Run:

```
grep -E '\.(SymbolTestsCoreDumpSnapshotTests|SymbolTestsCoreInterfaceSnapshotTests|SymbolTestsCoreCoverageInvariantTests|STCoreE2ETests|STCoreTests)(/|$)' /tmp/macho-all-tests.txt | tee /tmp/macho-filter-check.txt | wc -l
```

Expected: a non-zero count. Each line in `/tmp/macho-filter-check.txt` should be a fully qualified test ID whose class component is one of the five targets above.

- [ ] **Step 4: Confirm `STCoreE2ETests` and `STCoreTests` are both present and distinct**

Run:

```
grep -E '\.STCoreE2ETests/' /tmp/macho-filter-check.txt | head -3
grep -E '\.STCoreTests/' /tmp/macho-filter-check.txt | head -3
```

Expected: Both commands return at least one line each (the `(/|$)` anchor in the regex correctly distinguishes `STCoreTests` from `STCoreE2ETests`).

- [ ] **Step 5: Confirm no environment-dependent classes leak through**

Run:

```
grep -E '\.(DyldCache|XcodeMachOFile|MachOImage)' /tmp/macho-filter-check.txt || echo "no env-dependent classes matched"
```

Expected output: `no env-dependent classes matched`.

- [ ] **Step 6: Confirm the unique class set is exactly the five expected**

Run:

```
awk -F'/' '{print $1}' /tmp/macho-filter-check.txt | sort -u
```

Expected output (exactly these five lines, possibly in a different sort order — they will sort alphabetically):

```
SwiftDumpTests.SymbolTestsCoreCoverageInvariantTests
SwiftDumpTests.SymbolTestsCoreDumpSnapshotTests
SwiftInterfaceTests.STCoreE2ETests
SwiftInterfaceTests.STCoreTests
SwiftInterfaceTests.SymbolTestsCoreInterfaceSnapshotTests
```

If any other class name appears, **stop**: the regex is admitting something it should not. Report and let the controller decide.

If a name from the expected set is missing, **stop**: the regex is too restrictive. Report.

- [ ] **Step 7: No commit — verification only**

Optionally `rm /tmp/macho-all-tests.txt /tmp/macho-filter-check.txt` to clean up.

---

## Task 2: Update `.github/workflows/macOS.yml` — runner, Xcode version, and `--filter`

**Files:**
- Modify: `.github/workflows/macOS.yml` (4 textual changes; exact line numbers may shift)

**Goal:** Bump `macos-15` → `macos-26`, `"16.3"` → `"26.4"`, and add `--filter` to both `swift test` invocations. Leave the existing `Resolve SPM dependencies`, `Cache SymbolTests DerivedData`, `Build SymbolTestsCore fixture`, and `Upload xcodebuild logs on failure` steps untouched.

- [ ] **Step 1: Bump the matrix runner image**

Apply this edit:

```
old_string:
        os: [macos-15]
new_string:
        os: [macos-26]
```

- [ ] **Step 2: Bump the Xcode version**

Apply this edit:

```
old_string:
        xcode-version: ["16.3"]
new_string:
        xcode-version: ["26.4"]
```

- [ ] **Step 3: Add `--filter` to the Debug `swift test` step**

Apply this edit:

```
old_string:
      - name: Build and run tests in debug mode
        run: |
          swift test \
            -c debug \
            --build-path .build-test-debug
new_string:
      - name: Build and run tests in debug mode
        run: |
          swift test \
            -c debug \
            --build-path .build-test-debug \
            --filter '\.(SymbolTestsCoreDumpSnapshotTests|SymbolTestsCoreInterfaceSnapshotTests|SymbolTestsCoreCoverageInvariantTests|STCoreE2ETests|STCoreTests)(/|$)'
```

- [ ] **Step 4: Add `--filter` to the Release `swift test` step**

Apply this edit:

```
old_string:
      - name: Build and run tests in release mode
        run: |
          swift test \
            -c release \
            --build-path .build-test-release
new_string:
      - name: Build and run tests in release mode
        run: |
          swift test \
            -c release \
            --build-path .build-test-release \
            --filter '\.(SymbolTestsCoreDumpSnapshotTests|SymbolTestsCoreInterfaceSnapshotTests|SymbolTestsCoreCoverageInvariantTests|STCoreE2ETests|STCoreTests)(/|$)'
```

- [ ] **Step 5: Visually inspect the diff**

Run:

```
git diff .github/workflows/macOS.yml
```

Expected: Exactly the four textual changes above. No reflowing of unrelated lines, no accidental whitespace changes elsewhere.

- [ ] **Step 6: Validate YAML parses**

Run (Python is preinstalled on macOS):

```
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/macOS.yml'))" && echo "yaml OK"
```

Expected output: `yaml OK`. If parsing fails, fix the indentation or quoting before continuing.

- [ ] **Step 7: Commit**

```
git add .github/workflows/macOS.yml
git commit -m "$(cat <<'EOF'
ci(macOS): pin to macos-26 + Xcode 26.2 and filter to fixture tests

Restrict swift test runs to the five SymbolTestsCore-based test classes
(SymbolTestsCoreDumpSnapshotTests, SymbolTestsCoreInterfaceSnapshotTests,
SymbolTestsCoreCoverageInvariantTests, STCoreE2ETests, STCoreTests) so
the CI runner only executes tests that do not depend on a developer-
machine environment.

Spec: docs/superpowers/specs/2026-04-18-ci-test-filter-design.md
EOF
)"
```

---

## Task 3: Update `.github/workflows/release.yml` — runner and Xcode version

**Files:**
- Modify: `.github/workflows/release.yml` (2 textual changes)

**Goal:** Match the runner and Xcode version of the test workflow. No other changes.

- [ ] **Step 1: Bump the runner image**

Apply this edit:

```
old_string:
    runs-on: macos-15
new_string:
    runs-on: macos-26
```

- [ ] **Step 2: Bump the Xcode version**

Apply this edit:

```
old_string:
          xcode-version: "16.3"
new_string:
          xcode-version: "26.4"
```

- [ ] **Step 3: Visually inspect the diff**

Run:

```
git diff .github/workflows/release.yml
```

Expected: Exactly two changed lines (`macos-15` → `macos-26`, `"16.3"` → `"26.4"`). Nothing else.

- [ ] **Step 4: Validate YAML parses**

Run:

```
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml'))" && echo "yaml OK"
```

Expected output: `yaml OK`.

- [ ] **Step 5: Commit**

```
git add .github/workflows/release.yml
git commit -m "$(cat <<'EOF'
ci(release): bump runner to macos-26 + Xcode 26.2

Aligns the release workflow with the macOS test workflow.
EOF
)"
```

---

## Task 4: Push branch and open PR

**Files:** none modified.

**Goal:** Get the changes onto a remote branch and open a PR so CI runs end-to-end on a real `macos-26` runner.

- [ ] **Step 1: Confirm branch identity and commit list**

Run:

```
git log --oneline origin/main..HEAD
```

Expected: At least four commits on `chore/ci-only-fixture-tests`:

1. `Add CI test filter and macOS 26.2 upgrade spec` (initial spec)
2. `Refine CI filter spec to current state and add implementation plan` (spec correction + plan)
3. `ci(macOS): pin to macos-26 + Xcode 26.2 and filter to fixture tests`
4. `ci(release): bump runner to macos-26 + Xcode 26.2`

Plus possibly an extra spec/plan correction commit (e.g. the regex update from four to five classes once that landed).

- [ ] **Step 2: Push the branch**

Run:

```
git push -u origin chore/ci-only-fixture-tests
```

- [ ] **Step 3: Open the PR**

Run:

```
gh pr create --title "ci: filter to SymbolTestsCore fixture tests + bump to macOS 26.2" --body "$(cat <<'EOF'
## Summary
- Restrict `swift test` runs in `.github/workflows/macOS.yml` to the five
  `SymbolTestsCore`-based test classes (`SymbolTestsCoreDumpSnapshotTests`,
  `SymbolTestsCoreInterfaceSnapshotTests`,
  `SymbolTestsCoreCoverageInvariantTests`, `STCoreE2ETests`, `STCoreTests`).
  Other tests depend on developer-machine resources (Xcode frameworks,
  iOS Simulator runtimes, dyld shared cache) that don't exist on the CI
  runner.
- Bump both `macOS.yml` and `release.yml` to `macos-26` + Xcode `26.2`.

## Test plan
- [ ] CI run on this PR completes the `Build SymbolTestsCore fixture` step.
- [ ] `Build and run tests in debug mode` and `Build and run tests in release mode` each report exactly the five whitelisted test classes (visible in the test log).
- [ ] No `DyldCache*`, `Xcode*`, `MachOImage*`, or non-snapshot `*DumpTests` classes appear in the test log.

Spec: `docs/superpowers/specs/2026-04-18-ci-test-filter-design.md`
EOF
)"
```

- [ ] **Step 4: Watch the CI run**

Use the URL printed by `gh pr create`, or:

```
gh pr checks --watch
```

Expected: Both Debug and Release `swift test` steps pass.

If a step fails, do **not** patch it blindly. Read the failure log, identify root cause, and decide whether the fix belongs in this PR (adjust filter regex, fix YAML) or is a separate concern (real test breakage on macOS 26.2). For test breakage, file a follow-up issue rather than disabling the failing test in this PR.

---

## Self-Review Notes

- **Spec coverage:** Filter regex (Tasks 1, 2), env upgrade for `macOS.yml` (Task 2), env upgrade for `release.yml` (Task 3). Fixture build is already in place — explicitly noted in the spec, no task needed.
- **No placeholders:** Every textual edit is given as a concrete `old_string`/`new_string` pair; the regex is identical across all uses.
- **Type consistency:** The five test class names are spelled identically in Tasks 1, 2, the commit message, and the PR body. The `--filter` regex is byte-identical in Steps 3 and 4 of Task 2, in Task 1 verification, and in the spec's "Filter test runs" section.

---

## Implementation Outcome (2026-04-18, after CI feedback)

The Task 1-4 commits above landed as planned and pushed to PR #65, but
the first CI runs surfaced four issues that needed unplanned follow-up
fixes. All resolved on the same branch, all included in PR #65.

| # | Issue | Fix | Commit |
|---|---|---|---|
| 1 | `xcodebuild` failed on missing developer certificate (team `D5Q73692VW`) | Pass `CODE_SIGNING_ALLOWED=NO` build setting to `xcodebuild` | `84e695a` |
| 2 | `generic/platform=macOS` produced a universal slice; the x86_64 `.swiftinterface` failed verification (CLAUDE.md notes the project is ARM-only) | Add `ARCHS=arm64` (and `SWIFT_VERIFY_EMITTED_MODULE_INTERFACE=NO`, which turned out not to suppress the Xcode-26 explicit-module verifier) | `cdb84a4` |
| 3 | Swift 6.2.3 in Xcode 26.2 emits a `.swiftinterface` containing `nonisolated(nonsending)` then refuses to verify its own output (compiler bug) | Bump CI Xcode pin from `26.2` to `26.4` (Swift 6.3 fixed it) | `715e330` |
| 4 | `swift-demangling 0.1.0` (the remote pin) lacks `DemangleOptions.removeReferenceStoragePrefix`, breaking SwiftDump compilation in CI | Bump `Package.swift` pin from `0.1.0` to `0.1.1` (newly published) | `783656d` |
| 5 | `xcodebuild` on the CI runner emits the fixture at `DerivedData/Build/Products/Release/`, but `MachOFileName.SymbolTestsCore` reads it from `DerivedData/SymbolTests/Build/Products/Release/` (the layout xcodebuild produces locally) | Add a `Normalize SymbolTestsCore fixture path` step that finds the produced framework and symlinks it to the expected path | `90219b1` |

CI on the macos-26 runner with Xcode 26.4 finishes in ~15 minutes and
runs exactly the five whitelisted suites in both Debug and Release
configs. No environment-dependent classes leak through.

The `macos-26` runner had Xcode 26.4 preinstalled, so no further
setup-xcode workaround was needed. The `macOS` workflow had been in
`disabled_manually` state on origin (since 2025-10-20); it was
re-enabled during Task 4 to allow the new run to fire.
