# Kernel acceptance gates

Each gate has a command and a pass rule. Run the commands from the repo root unless a line says otherwise.

| # | Gate | Command | Pass rule |
|---|---|---|---|
| G1 | Tests pass on macOS | `cd Packages/Kernel && swift test` | exit 0; the test count is reported |
| G2 | Tests pass on Linux | `docker info`, then `docker run --rm -v "$PWD":/w -w /w/Packages/Kernel swift:<newest> swift test` | exit 0. If the Docker daemon is not running, the gate stays open with that reason. Docker is never started by the agent |
| G3 | Every property and every ported case catches its planted break | `cd Packages/Kernel && swift test` | each has two tests: one on the kernel code, and `…CatchesPlantedBreak` that runs the same check on a wrong implementation inside `withKnownIssue`. Swift Testing fails it if the check does not fail. The rule is that every `…CatchesPlantedBreak` test passes; the count of known issues changes per run and is not a gate |
| G3b | Mutations of the kernel code are caught | the review 1 mutation runner, adapted to this code (`mutate2.py`), over a copy of the package | every mutation is caught, or is shown to be equivalent. G3 alone shows that each check can see one written break; G3b shows that the tests guard the kernel itself |
| G4 | No Apple-only frameworks | `grep -rE --exclude-dir=.build "import (CryptoKit\|AppKit\|SwiftUI\|GRDB)" Packages/Kernel` | no output. `.build/` holds dependency checkouts: swift-crypto re-exports CryptoKit on Apple platforms and uses BoringSSL on Linux |
| G5 | Lint | `xcrun swift-format lint -r --configuration .swift-format Packages/Kernel` | no output |
| G6 | Every source file names its origin | `grep -L "^// Source: " Packages/Kernel/Sources/*/*.swift Packages/Kernel/Sources/Kernel/*/*.swift` | no output |
| G7 | ADR drafts | files exist: `worktrace/adr/ADR-002-hlc.md`, `ADR-003-canonical-bytes.md`, `ADR-009-label-model.md` | each has context, options with file:line evidence, decision, what would reverse it |
| G8 | Nothing else changed | `git status --porcelain` | only `Packages/Kernel/` is new; no existing package, app file or store is changed |
| G9 | Cost grows with new events only | `cd Packages/Kernel && swift run -c release KernelBenchmark` | insert, then `view` and `head`, at 100k events: at most 20 ms per step (research 47 §4) |

## Status, 2026-11-22, after review 1 (dev runs on macOS 26, Swift 6.4.2)
- G1 pass: 162 tests in 20 suites; 20 of 20 repeated runs green.
- G2 open: the Docker daemon runs, but pulling `swift:6.4` failed with "no space left on device" (2.1 GiB free on the
  host disk). Needs about 5 GB free, then the G2 command. Nothing was pruned.
- G3 pass: 21 properties and 11 ported cases, 32 planted breaks, each caught.
- G3b pass: 62 of 62 mutations caught (the 53 of review 1, 13 with patch text moved to the new code, plus 9 new).
- G4, G5, G6 pass: no output. G7 drafted (draft 2). G8: only `Packages/Kernel/` is new.
- G9 pass: median 0.055 ms per step at 100k events (1 stream or 20 streams). If the caller still holds the previous
  view, the next insert copies that stream's chain: median 3.8 ms with one 100k stream, 0.47 ms with 20 streams.

## Invariants the tests guard (research 47 and K5 numbering)
- Label: L1 homomorphism, L2 monotone derivation, L3 antitone in grants, L4 roster narrowing, L5 model independence,
  L6 release only by owners (with a minimum of real releases), L7 fail closed; join is commutative, associative and
  idempotent (T1); a grant not signed by the source's owner changes nothing; a part nobody reads absorbs every join;
  a join never widens; one equality for every name (NFC, UTF-8 bytes).
- Clock: strictly rising stamps on send and receive; carry on counter overflow; a remote stamp more than 5 minutes
  ahead of the wall clock is quarantined and does not move the clock, for stamps and for events (`admit`); total
  order (hlc, device, numeric seq, label, id).
- Canonical bytes: RFC 8785 output byte for byte on the vectors without floats, and on `structures` with its one
  float written as the integer it denotes; floats, duplicate keys, lone surrogates, integers outside the I-JSON range
  and extra framed parts are refused; U+2028, U+2029 and U+007F stay raw.
- Event: a changed byte is refused (I1); a known device cannot sign in another device's stream; a wrong backlink, a
  non-rising hlc and a bad signature are refused; every position with two signed events is fork evidence, behind gaps
  and earlier forks too; any delivery order gives the same view (I2); the view is kept up to date on insert.
