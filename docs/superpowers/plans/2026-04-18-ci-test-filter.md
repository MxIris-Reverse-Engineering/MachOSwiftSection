# CI Test Filter and macOS 26.2 Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restrict CI test runs to four `SymbolTestsCore` fixture test classes and bump both workflows to macOS 26.2 + Xcode 26.2.

**Architecture:** Pure CI configuration change. No source-code edits. Apply a `--filter` regex to `swift test` in `.github/workflows/macOS.yml`, and bump the runner image and Xcode version in both `macOS.yml` and `release.yml`. Verify the regex selects exactly the intended four test classes, then commit each workflow change separately.

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

**Goal:** Confirm the proposed regex matches exactly the four target test classes — `MachOFileDumpSnapshotTests`, `MachOFileInterfaceSnapshotTests`, `STCoreE2ETests`, `STCoreTests` — and nothing else.

- [ ] **Step 1: List every test method that matches the proposed regex**

Run from repo root:

```
swift test --list-tests --filter '\.(MachOFileDumpSnapshotTests|MachOFileInterfaceSnapshotTests|STCoreE2ETests|STCoreTests)(/|$)' 2>&1 | tee /tmp/macho-filter-check.txt
```

Expected: A non-empty list containing only fully qualified test IDs whose
class component is one of:

- `SwiftDumpTests.MachOFileDumpSnapshotTests`
- `SwiftInterfaceTests.MachOFileInterfaceSnapshotTests`
- `SwiftInterfaceTests.STCoreE2ETests`
- `SwiftInterfaceTests.STCoreTests`

If the build step inside `swift test --list-tests` fails because
`SymbolTestsCore.framework` is missing, run the existing fixture build
first:

```
xcodebuild \
  -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj \
  -scheme SymbolTestsCore \
  -configuration Release \
  -derivedDataPath Tests/Projects/SymbolTests/DerivedData \
  -destination 'generic/platform=macOS' \
  build
```

Then re-run the `--list-tests` command.

- [ ] **Step 2: Confirm `STCoreE2ETests` and `STCoreTests` are both present and distinct**

Run:

```
grep -E '\.STCoreE2ETests/' /tmp/macho-filter-check.txt | head -3
grep -E '\.STCoreTests/' /tmp/macho-filter-check.txt | head -3
```

Expected: Both commands return at least one line each (i.e. the `\b`-style
`(/|$)` anchor in the regex correctly distinguishes `STCoreTests` from
`STCoreE2ETests`).

- [ ] **Step 3: Confirm no environment-dependent classes leak through**

Run:

```
grep -E '\.(DyldCache|XcodeMachOFile|MachOImage)' /tmp/macho-filter-check.txt || echo "no env-dependent classes matched"
```

Expected output: `no env-dependent classes matched` (i.e. `grep` finds
nothing).

- [ ] **Step 4: Confirm no other test classes (e.g. unit tests in `MachOSwiftSectionTests`, `MachOSymbolsTests`, `TypeIndexingTests`) leak through**

Run:

```
awk -F'/' '{print $1}' /tmp/macho-filter-check.txt | sort -u
```

Expected: Output contains only the four fully qualified class names listed
in Step 1, with no extras.

If anything other than the four expected classes appears, **stop**: the
regex is wrong, fix it before continuing. If only the four expected
classes appear, proceed.

- [ ] **Step 5: No commit — verification only**

Delete `/tmp/macho-filter-check.txt` (optional, just cleanup).

---

## Task 2: Update `.github/workflows/macOS.yml` — runner, Xcode version, and `--filter`

**Files:**
- Modify: `.github/workflows/macOS.yml` (lines 18, 19, 65-66, 71-72 — exact line numbers may shift; the changes are textual)

**Goal:** Bump `macos-15` → `macos-26`, `"16.3"` → `"26.2"`, and add `--filter` to both `swift test` invocations. Leave the existing `Resolve SPM dependencies`, `Cache SymbolTests DerivedData`, `Build SymbolTestsCore fixture`, and `Upload xcodebuild logs on failure` steps untouched.

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
        xcode-version: ["26.2"]
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
            --filter '\.(MachOFileDumpSnapshotTests|MachOFileInterfaceSnapshotTests|STCoreE2ETests|STCoreTests)(/|$)'
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
            --filter '\.(MachOFileDumpSnapshotTests|MachOFileInterfaceSnapshotTests|STCoreE2ETests|STCoreTests)(/|$)'
```

- [ ] **Step 5: Visually inspect the diff**

Run:

```
git diff .github/workflows/macOS.yml
```

Expected: Exactly the four textual changes above. No reflowing of unrelated
lines, no accidental whitespace changes elsewhere.

- [ ] **Step 6: Validate YAML parses**

Run (Python is preinstalled on macOS):

```
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/macOS.yml'))" && echo "yaml OK"
```

Expected output: `yaml OK`. If parsing fails, fix the indentation or
quoting before continuing.

- [ ] **Step 7: Commit**

```
git add .github/workflows/macOS.yml
git commit -m "$(cat <<'EOF'
ci(macOS): pin to macos-26 + Xcode 26.2 and filter to fixture tests

Restrict swift test runs to the four SymbolTestsCore-based test classes
(MachOFileDumpSnapshotTests, MachOFileInterfaceSnapshotTests,
STCoreE2ETests, STCoreTests) so the CI runner only executes tests that
do not depend on a developer-machine environment.

Spec: docs/superpowers/specs/2026-04-18-ci-test-filter-design.md
EOF
)"
```

---

## Task 3: Update `.github/workflows/release.yml` — runner and Xcode version

**Files:**
- Modify: `.github/workflows/release.yml:14, 23`

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
          xcode-version: "26.2"
```

- [ ] **Step 3: Visually inspect the diff**

Run:

```
git diff .github/workflows/release.yml
```

Expected: Exactly two changed lines (`macos-15` → `macos-26`,
`"16.3"` → `"26.2"`). Nothing else.

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

Expected: Three commits on `chore/ci-only-fixture-tests`:

1. `Add CI test filter and macOS 26.2 upgrade spec`
2. `ci(macOS): pin to macos-26 + Xcode 26.2 and filter to fixture tests`
3. `ci(release): bump runner to macos-26 + Xcode 26.2`

(The order of 2 and 3 may differ depending on task ordering; the spec
commit is required to be first.)

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
- Restrict `swift test` runs in `.github/workflows/macOS.yml` to the four
  `SymbolTestsCore`-based test classes (`MachOFileDumpSnapshotTests`,
  `MachOFileInterfaceSnapshotTests`, `STCoreE2ETests`, `STCoreTests`).
  Other tests depend on developer-machine resources (Xcode frameworks,
  iOS Simulator runtimes, dyld shared cache) that don't exist on the CI
  runner.
- Bump both `macOS.yml` and `release.yml` to `macos-26` + Xcode `26.2`.

## Test plan
- [ ] CI run on this PR completes the `Build SymbolTestsCore fixture` step.
- [ ] `Build and run tests in debug mode` and `Build and run tests in release mode` each report exactly the four whitelisted test classes (visible in the test log).
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

If a step fails, do **not** patch it blindly. Read the failure log,
identify root cause, and decide whether the fix belongs in this PR
(adjust filter regex, fix YAML) or is a separate concern (real test
breakage on macOS 26.2). For test breakage, file a follow-up issue
rather than disabling the failing test in this PR.

---

## Self-Review Notes

- **Spec coverage:** Filter regex (Tasks 1, 2), env upgrade for `macOS.yml` (Task 2), env upgrade for `release.yml` (Task 3). Fixture build is already in place — explicitly noted in the spec, no task needed.
- **No placeholders:** Every textual edit is given as a concrete `old_string`/`new_string` pair; the regex is identical across all uses.
- **Type consistency:** The four test class names are spelled identically in Tasks 1, 2, and the PR body. The `--filter` regex is byte-identical in Steps 3 and 4 of Task 2 and in Task 1 verification.
