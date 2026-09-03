# Does the fork build and run on Xcode 26.6 today

Research note for issue [#2](https://github.com/vladyslav-tmf/HSTracker/issues/2).

Date: 2026-09-03. Repo state: `master`, upstream `76c411fc` (2026-09-01) plus two of our own commits that add only `.gitignore` and `docs/agents/`.

**Status: resolved.** This note began as investigation-only. It was then re-verified end to end by actually building and launching the app, and every prediction in it has since been settled by observation. Sections marked *Predicted* in the first pass are now marked *Verified* or *Corrected*, with the evidence inline. Three changes were applied, two of them one line each; they are listed in §2.

---

## 1. Question

Issue #2 asks whether this fresh fork of `HearthSim/HSTracker` builds and launches as it stands, on this machine, today. The project declares `MACOSX_DEPLOYMENT_TARGET = 10.14` and `SWIFT_VERSION = 5.0`, while the toolchain here is Xcode 26.6 (17F113) with the Swift 6.3.3 compiler against the macOS 26.5 SDK, on an Apple M4 running macOS 26.5.2. The ticket wants five things measured: whether `xcodebuild` produces a running `HSTracker.app` unchanged; what the Carthage step and `downloaded-frameworks` need and whether the prebuilt binaries still link; whether the vendored Mono runtime and the `HSTracker-Bridging-Header.h` path survive; what `DEVELOPMENT_TEAM = RL7C49LAMC` does when it belongs to upstream and not to us, and what the local-signing path is instead; and whether the built app can attach to Hearthstone, which lives on an external SSD here rather than in `/Applications`. The answer wanted is a list of what breaks with the smallest fix for each, not a wholesale modernisation.

---

## 2. Verdict

**No, not unchanged. Yes, after three changes, two of which are one line each.** Both halves are verified by observation, not predicted.

Unchanged, `xcodebuild` fails with exit code 65 at **build-description creation, before a single build task runs**:

```
/Users/vladislavtimofeev/VScodeProjects/HearthSim/HSTracker/HSTracker.xcodeproj: error: No signing certificate "Developer ID Application" found: No "Developer ID Application" signing certificate matching team ID "RL7C49LAMC" with a private key was found. (in target 'HSTracker' from project 'HSTracker')
** BUILD FAILED **
```

With the three changes below applied, the same command exits 0 and the app launches, loads its database, attaches to Hearthstone on the external SSD, and completes a BobsBuddy simulation:

```
xcodebuild -project HSTracker.xcodeproj -scheme HSTracker -configuration Debug build
```

**The three changes, in the order a build hits them:**

| # | Change | Where | Repo diff | Merge cost |
| --- | --- | --- | --- | --- |
| 1 | Swap release signing for ad-hoc | `Config.xcconfig:12-18` | 4 lines, never committed | Zero, pre-authorised by `CONTRIBUTING.md:44` |
| 2 | `brew install wget` | this machine | none | Zero |
| 3 | `NET_VERSION=net7.0` → `net8.0`, and add `System.Runtime.Intrinsics.dll` to `ASSEMBLIES` | `project.pbxproj:7164` (`Embed Mono`) | 2 tokens on one line | Small, unavoidable, see §3.3 |

Nothing else was touched. In particular `MACOSX_DEPLOYMENT_TARGET` was **not** raised, per the ticket.

**Confidence, split by finding, after re-verification:**

| Finding | Status |
| --- | --- |
| Signing failure is the first failure | **Verified** — observed build output above |
| `wget` absent | **Verified** — `which wget` → not found |
| Download phases fail without `wget` | **Verified** — after `brew install wget` all three phases ran and populated `downloaded-frameworks/` |
| Homebrew's `/opt/homebrew/bin` is not on the Run Script `PATH` | **Corrected** — it is, for `xcodebuild` launched from a login shell; see §3.2 |
| `Embed Mono` `net7.0`/`net8.0` mismatch | **Verified** — the exact `cp … No such file or directory` failure predicted in §3.3 |
| `System.Runtime.Intrinsics.dll` missing from `ASSEMBLIES` | **Verified** — crashed the app at launch; see §3.3 |
| `MACOSX_DEPLOYMENT_TARGET = 10.14` is fine | **Verified** — 1817 Swift files compiled, zero `error:` lines in a 20488-line build log |
| `-ld_classic` still works (warning only) | **Verified** — the app links and runs |
| Carthage is entirely dead in this project | **Verified** — zero references in the project file |
| `HSTrackerTests` cannot build | **Verified** — links a framework absent from this machine; untouched, `build` does not reach it |
| All 20 SPM dependencies compile under Swift 6.3.3, Realm included | **Verified** — now also under `xcodebuild`, not just `swift build` |
| App compiles, links and launches | **Verified** — see §4 |
| App attaches to Hearthstone on the SSD | **Verified** — HearthMirror read the live game; see §3.9 |

The external corroboration from the first pass held up: upstream release **3.6.7** (2026-08-28) ships a universal binary with `sdk 26.2`, `minos 10.14`/`11.0` ([release](https://github.com/HearthSim/HSTracker/releases/tag/3.6.7)). Upstream builds this exact configuration on Xcode 26. What broke here was local environment, credentials, and one stale version string — not the language, the SDK, or the deployment target.

---

## 3. What breaks, and the smallest fix for each

Ordered by the sequence in which a build actually hits them.

### 3.1 Code signing: `DEVELOPMENT_TEAM` belongs to HearthSim, and this machine has no certificates

**What breaks.** `Config.xcconfig:13-14` sets `CODE_SIGN_IDENTITY = Developer ID Application` and `DEVELOPMENT_TEAM = RL7C49LAMC`. That xcconfig is the `baseConfigurationReference` for both the app's Debug and Release configurations (`HSTracker.xcodeproj/project.pbxproj:9632`, `:9695`), and neither target configuration overrides those two keys, so they apply. `CODE_SIGNING_REQUIRED = YES` and `CODE_SIGN_STYLE = Manual`. This machine reports `0 valid identities found` from `security find-identity -v -p codesigning`, and RL7C49LAMC is HearthSim's team, not ours.

**Evidence.** The verbatim build error in §2. Apple documents the mechanism: `CODE_SIGN_IDENTITY` is "the name … of a valid code-signing certificate in a keychain within your keychain path. A missing or invalid certificate will cause a build error" ([Build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference)). Developer ID certificates additionally require a paid membership ([membership comparison](https://developer.apple.com/support/compare-memberships/)), and Apple DTS advises against using Developer ID for day-to-day development at all: "use an Apple Development signing identity for development" ([forums 815248](https://developer.apple.com/forums/thread/815248)).

**Smallest fix.** Swap the comments in `Config.xcconfig`, exactly as upstream's own `CONTRIBUTING.md:41-44` instructs. Comment out lines 13-14, uncomment lines 17-18:

```
//CODE_SIGN_IDENTITY = Developer ID Application
//DEVELOPMENT_TEAM = RL7C49LAMC
CODE_SIGN_IDENTITY = -
DEVELOPMENT_TEAM =
```

`CODE_SIGN_IDENTITY = -` is ad-hoc signing, which Apple calls "Sign to Run Locally" in Xcode ([TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)). No Apple Developer account of any kind is needed.

**Applied and verified.** The edit was made and the build proceeded past build-description creation on the next run. The build log carries `note: Disabling hardened runtime with ad-hoc codesigning. (in target 'HSTracker')` and `_DEVELOPMENT_TEAM_IS_EMPTY=YES`. The resulting bundle:

```
$ codesign -dv HSTracker.app
Identifier=net.hearthsim.hstracker
Format=app bundle with Mach-O thin (arm64)
CodeDirectory v=20400 size=464 flags=0x2(adhoc) hashes=4+7 location=embedded
Signature=adhoc
TeamIdentifier=not set
Sealed Resources version=2 rules=13 files=589
```

Note `Mach-O thin (arm64)`: a plain `xcodebuild build` on this machine produces a single-slice binary, not the universal one upstream ships. That is `ONLY_ACTIVE_ARCH` in Debug and is expected, but it means the x86_64 half of the build has not been exercised here.

**The hardened-runtime worry in the next paragraph did not materialise.** `--deep` plus ad-hoc signing produced a bundle that launches and runs. Leave `OTHER_CODE_SIGN_FLAGS` alone.

**Merge cost.** Effectively zero, and this is the rare case where upstream has pre-authorised the divergence: `CONTRIBUTING.md:44` says "Do not submit changes to `Config.xcconfig` on pull requests. The file is meant to make life simple when developing and running locally." The file has not been touched since 2020. Keep the edit local and never commit it; if it ever does conflict, it is four lines.

**Does ad-hoc signing cost us the entitlements?** No, and this matters because `HSTracker.entitlements:9-10` carries `com.apple.security.cs.debugger`, which the app needs to read Hearthstone's memory (§3.8). Apple's TN3125 lists the unrestricted entitlements — the ones needing no provisioning profile — and explicitly includes "Those used to configure the Hardened Runtime", which is the family `com.apple.security.cs.debugger` belongs to ([TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles), [Configuring the hardened runtime](https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime)). What ad-hoc signing does cost is a stable designated requirement, which shows up as TCC and keychain prompts recurring after every rebuild ([TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements); Quinn, [forums 751658](https://developer.apple.com/forums/thread/751658)). That is an annoyance, not a blocker.

**Related, not a blocker.** `OTHER_CODE_SIGN_FLAGS = --deep` (`project.pbxproj:9676`, `:9739`). Apple DTS is unambiguous that this is wrong: `--deep` "applies the same code signing options to every code item that it signs, something that's not appropriate in general… On macOS this may cause the trusted execution system to block your program from running entirely" ([forums 129980, "`--deep` Considered Harmful"](https://developer.apple.com/forums/thread/129980)). For an app that embeds a .NET runtime with many nested dylibs, `--deep` stamps the debugger entitlement onto every one of them. Leave it alone for now — it is upstream's setting and it evidently ships — but if hardened-runtime launch failures appear, this is the first suspect.

---

### 3.2 `wget` is not installed, and three build phases depend on it

**What breaks.** The HSTracker target's first three build phases are Run Scripts that populate `downloaded-frameworks/`, and every one of them shells out to `wget` (`project.pbxproj:6828-6841` for the ordering; `:7184`, `:7255`, `:7139` for the scripts):

| Phase | Fetches | Failure mode without `wget` |
| --- | --- | --- |
| `Download Mono` (`:7166-7186`) | Two NuGet packages, then `lipo -create`s them into `mono/universal` | No `set -e`; the two `wget` and two `unzip` calls fail quietly, then `lipo` fails on missing inputs and its non-zero status ends the phase |
| `Download BobsBuddy and HearthDb` (`:7235-7256`) | `libs.hearthsim.net/hdt/{HearthDb,BobsBuddy}.zip` | `set -e`, dies on the first `wget` |
| `Download HearthMirror` (`:7121-7140`) | `libs.hearthsim.net/hstracker/$SHA1/HearthMirror.framework{,.dSYM}.zip` | `set -e` inside the version-mismatch branch, dies on the first `wget` |

`downloaded-frameworks/` is gitignored (`.gitignore:6`, `:27`) and does not exist in the working tree. Without it, `FRAMEWORK_SEARCH_PATHS` has no `HearthMirror.framework` to link or embed, `HEADER_SEARCH_PATHS` has no `mono-2.0` headers, so every `#include <mono/…>` in the bridging header fails and no Swift file in the target can compile.

Note the diagnostic will be misleading: `Download Mono` reports a `lipo` error about missing input files, not "wget: command not found", because the missing-command failures scroll past without stopping the script.

**Evidence.** `which wget` → not found on this machine; `curl` and `unzip` are present. macOS has never shipped `wget`. Upstream hit exactly this and documented it in [PR #1411, "Use curl instead of wget"](https://github.com/HearthSim/HSTracker/pull/1411): "wget is not included in recent versions of macOS so the current build fails with a `wget: command not found` error. Using wget via Homebrew is not an ideal solution because Homebrew by default installs to `/opt/homebrew` on Apple Silicon Macs, which is not in Xcode's list of allowed paths to access when building." That PR was **closed unmerged** in May 2026 over an unsigned CLA, so the `wget` calls are still in master today.

**Smallest fix.** `brew install wget`. One command, zero repo diff, zero merge cost.

**Caveat resolved: `brew install wget` alone is sufficient, for `xcodebuild` from a terminal.** PR #1411's second sentence warned that Homebrew installs to `/opt/homebrew/bin` on Apple Silicon and that this may not be on the Run Script `PATH`. Observed here: `wget` landed at `/opt/homebrew/bin/wget`, `/opt/homebrew/bin` is on the login shell `PATH`, and a Run Script phase inherits the environment of the process that launched the build. All three download phases then ran and populated `downloaded-frameworks/`, which is how every later finding in this note became observable.

**Scope of that result.** It holds for `xcodebuild` started from a login shell. It says nothing about Xcode.app launched from Finder or the Dock, which inherits launchd's `PATH` rather than the shell's, and that is the case PR #1411 was actually describing. If a GUI Xcode build fails here with `wget: command not found`, the next-smallest fix is a symlink into a directory already on that `PATH` (`sudo ln -s /opt/homebrew/bin/wget /usr/local/bin/wget`), still with zero repo diff. Only if that fails is it worth porting PR #1411's `curl` change into the fork, and that buys a permanent three-line divergence in `project.pbxproj` re-paid at every upstream merge — so it is the last resort, not the first.

---

### 3.3 `Embed Mono` copies from `net7.0`, but the pinned runtime is `8.0.29` and only ships `net8.0`

**What breaks.** `HSTracker/mono-version.txt` contains `8.0.29`. The `Embed Mono` phase (`project.pbxproj:7141-7165`) hardcodes `NET_VERSION=net7.0` and, under `set -e`, runs:

```sh
MONO_LOCATION=$SRCROOT/downloaded-frameworks/mono/runtimes/${arch}/lib/${NET_VERSION}
...
for assembly in $ASSEMBLIES; do cp ${MONO_LOCATION}/$assembly "${RES_LOCATION}"; done
```

The `Microsoft.NETCore.App.Runtime.Mono.osx-{x64,arm64}` 8.0.29 packages ship `runtimes/osx-*/lib/net8.0` and no `net7.0` directory. On a **fresh clone**, that `cp` has no source path and `set -e` fails the build. On a machine with a **stale** `downloaded-frameworks` the old `net7.0` tree is still there, because `Download Mono` unzips with `unzip -n` and never deletes — which is exactly why upstream's own machines keep building and never see this.

**Evidence.** `mono-version.txt` was bumped `7.0.20` → `8.0.29` on 2026-08-06 in [commit d70efe05](https://github.com/HearthSim/HSTracker/commit/d70efe058) ("Fix crash with trinkets selection") without touching `NET_VERSION`. The package layout is confirmed on NuGet: [`Microsoft.NETCore.App.Runtime.Mono.osx-x64` 8.0.29](https://www.nuget.org/packages/Microsoft.NETCore.App.Runtime.Mono.osx-x64/8.0.29) and [`osx-arm64` 8.0.29](https://www.nuget.org/packages/Microsoft.NETCore.App.Runtime.Mono.osx-arm64/8.0.29), both published 2026-07-14 alongside [.NET 8.0.29](https://github.com/dotnet/core/blob/main/release-notes/8.0/8.0.29/8.0.29.md). An outside contributor reported the downstream symptom in [PR #1431](https://github.com/HearthSim/HSTracker/pull/1431) (2026-08-25, built and tested on Xcode 26.6 / macOS 26.6, closed same day with no comments): "The Embed Mono script phase still targeted `net7.0` and omitted `System.Runtime.Intrinsics.dll`: the Bob's Buddy self-test threw `FileNotFoundException` at launch, and the exception-unwrapping code then hit `fatalError("Member InnerException not found")`, crash-looping the app."

Note the two failure shapes. A fresh clone should fail at **build** time. A tree with stale downloads builds and then **crashes at launch**. PR #1431 saw the second. We were the first, and then we saw the second as well — they are not alternatives, they are two stages of the same net7 → net8 migration.

**Confirmed, both stages.**

*Stage one, build time.* With signing fixed and `wget` installed, the build reached `Embed Mono` and died there, and nowhere else. Exit 65, and in the whole 20488-line log not one line matching `error:` — the sole failure was:

```
+ MONO_LOCATION=.../downloaded-frameworks/mono/runtimes/osx-arm64/lib/net7.0
+ cp .../runtimes/osx-arm64/lib/net7.0/mscorlib.dll '.../HSTracker.app/Contents/Resources/Managed/arm64'
cp: .../downloaded-frameworks/mono/runtimes/osx-arm64/lib/net7.0/mscorlib.dll: No such file or directory
Command PhaseScriptExecution failed with a nonzero exit code
** BUILD FAILED **
The following build commands failed:
	PhaseScriptExecution Embed\ Mono …
```

Exactly as predicted. Confirmed on disk: `runtimes/osx-arm64/lib/` and `runtimes/osx-x64/lib/` each contain `net8.0` and nothing else, alongside `mono-8.0.29-arm64.zip` and `mono-8.0.29-x64.zip`. Changing `NET_VERSION` to `net8.0` made the next build exit 0, staging 35 assemblies per architecture.

*Stage two, launch time.* The app then started, loaded 35775 cards, initialised the runtime (`Loading mono version 8.0.29.0`, `Loaded BobsBuddy version 1.70.0.0`), attached to Hearthstone — and died about 700 ms later:

```
HSTracker/MonoHelper.swift:525: Fatal error: Unsupported exception
```

That message is the symptom, not the cause. `MonoHelper.testSimulation()` unwraps the exception from the simulation and calls `fatalError` on any type it does not recognise, discarding the exception itself. Instrumenting that branch to log `MonoHelper.toString(obj:)` before the `fatalError` printed the cause:

```
System.IO.FileNotFoundException: Could not load file or assembly
'System.Runtime.Intrinsics, Version=8.0.0.0, Culture=neutral, PublicKeyToken=cc7b13ffcd2ddd51'
   at System.Linq.Enumerable.Max(IEnumerable`1 source)
   at BobsBuddy.Simulation.Simulator.ResetPlayerStateAndUnbuffCloningGallery(PlayerState, CloningGallery)
   at BobsBuddy.Simulation.Simulator.SetupFightCached(Input)
   at BobsBuddy.Simulation.Simulator.SimulateFight(Input)
```

`System.Runtime.Intrinsics.dll` ships in both 8.0.29 packages but is absent from the `ASSEMBLIES` list, which was written for net7.0. Under .NET 8 `Enumerable.Max` is vectorised and pulls it in, so BobsBuddy cannot run a single simulation without it. **This is not a defect of the test harness — it is the Battlegrounds simulator, the app's headline feature, being broken.** The harness merely surfaces it on every launch.

**Smallest fix.** Two tokens on one line, `project.pbxproj:7164`: `NET_VERSION=net7.0` → `net8.0`, and `System.Runtime.Intrinsics.dll` inserted into `ASSEMBLIES` after `System.Runtime.InteropServices.dll`. Nothing in `MonoHelper.swift` or `AppDelegate.swift` was changed. After the fix:

```
MonoHelper.testSimulation():538 - testSimulation result is 0 0,827 0,173 0 0,827 3,308
```

**Why the crash is unconditional, which matters for anyone shipping this.** `AppDelegate.swift:322-331` calls `MonoHelper.testSimulation()` on a background queue at the end of `loadSplashscreen()`, guarded by `#if !HSTTEST` — the test-target flag — and **not** by `#if DEBUG`. So the developer scratch harness, with its hardcoded murlocs and trinket, runs in Release builds too, and its `fatalError` is a live crash path for end users. Upstream's own machines do not see it because their stale `net7.0` tree keeps the old assembly set. Worth a separate ticket; it is upstream's bug, not ours, and #2 does not ask us to fix it.

**Merge cost.** Small but real, and unavoidable — this one cannot be fixed outside the repo. It is a single token inside a shell-script blob in the project file. Script-phase blobs are one-line strings in `project.pbxproj`, so any upstream edit to that same phase is a guaranteed conflict, but the resolution is trivial and obvious. Watch for upstream fixing this themselves, at which point the divergence disappears.

**Two more staleness items in the same script, both currently harmless.** `MONO_VERSION=6.0.8` is set and never used, and two `install_name_tool` lines referencing a classic `/Library/Frameworks/Mono.framework` are commented out. Leave both.

---

### 3.4 The `HSTrackerTests` target cannot build at all

**What breaks.** Two independent problems, neither of which affects the app target:

1. The test target links `Mono.framework` at `../../../Library/Frameworks/Mono.framework`, i.e. a **system-installed classic Mono** (`project.pbxproj:3262` for the file reference, `:4105` for the link entry). `ls /Library/Frameworks/Mono.framework` on this machine: no such file or directory. Classic Mono is not what the app uses any more — the app uses the .NET 8 MonoVM from `downloaded-frameworks` — so this reference is a leftover from before the CoreCLR switch.
2. Its `HEADER_SEARCH_PATHS` points at `downloaded-frameworks/mono/runtimes/**ios-arm**/native/include/mono-2.0` (`project.pbxproj:9756-9789`, `:9790-9823`). `Download Mono` only ever fetches `osx-x64` and `osx-arm64`. That path can never exist.

**Evidence.** Repo lines cited above plus the negative `ls`. The test target also has no script phases of its own, so nothing populates anything for it.

**Smallest fix.** Do nothing. `xcodebuild build` targets the app and does not touch this. Only `xcodebuild test` trips it, and running the test suite is not what issue #2 asks. If tests are wanted later, that is its own ticket — the honest fix is to drop the `Mono.framework` link and correct the header path, which is a genuine upstream bug worth reporting rather than carrying.

**Merge cost.** Zero, because the fix is to not make one.

---

### 3.5 `-ld_classic` works today and is deleted in Xcode 27

**What breaks.** Nothing yet. `OTHER_LDFLAGS = ("$(inherited)", "-ld_classic")` on the app target in both configurations (`project.pbxproj:9677-9680`, `:9740-9743`), added 2023-11-06 in the Xcode 15 era.

**Evidence.** Probed directly on this toolchain:

```
$ xcrun swiftc -target arm64-apple-macos10.14 -swift-version 5 -Xlinker -ld_classic probe.swift -o probe2
ld: warning: -ld_classic is deprecated and will be removed in a future release
```

It links, the binary runs. A warning per link, nothing more. Apple's paper trail: Xcode 15 introduced the new linker and said the classic one "will be removed in a future release" ([Xcode 15 notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-15-release-notes)); Xcode 16 formally deprecated the flag ([Xcode 16 notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-16-release-notes)); the Xcode 26 notes do not mention the linker at all; and **Xcode 27 removes it** — "The ld64 linker has been removed and the `-ld_classic` option is no longer supported. (165165518)" ([Xcode 27 beta notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes)). Apple DTS on the timing: "Reverting to ld64 is a reasonable short-term workaround, but you don't want to rely on that in the medium-to-long term because it won't be around forever" ([forums 781538](https://developer.apple.com/forums/thread/781538)).

**Smallest fix.** None now. Do not touch it as part of #2 — it costs one warning and removing it risks re-exposing whatever linker problem made upstream add it in 2023, which nobody has documented. Record it as a dated fuse: **the day this machine moves to Xcode 27, the build stops.** At that point the fix is to delete the flag and find out what breaks, and it will be upstream's problem too, so it is worth waiting for upstream to solve it.

**Merge cost.** Zero while we leave it alone.

---

### 3.6 Non-issue: `MACOSX_DEPLOYMENT_TARGET = 10.14` is fine on Xcode 26.6

This was the ticket's central worry. It is unfounded.

**Verified directly on this toolchain.** Both slices compile and link cleanly with no diagnostics:

| Probe | Result |
| --- | --- |
| `swiftc -target x86_64-apple-macos10.14 -swift-version 5` | Links, `LC_BUILD_VERSION` `minos 10.14`, `sdk 26.5`, runs |
| `swiftc -target arm64-apple-macos10.14 -swift-version 5` | Links, `minos` silently clamped to `11.0` (arm64 macOS has no earlier version), `sdk 26.5`, runs |

The macOS 26.5 SDK's own `SDKSettings.plist` gives `SupportedTargets.macosx.MinimumDeploymentTarget = 10.13` and `RecommendedDeploymentTarget = 11.0`, so 10.14 sits above the enforced floor. `xcodebuild -showBuildSettings` confirms `MACOSX_DEPLOYMENT_TARGET = 10.14` is passed through unchanged, with `RECOMMENDED_MACOSX_DEPLOYMENT_TARGET = 11.0` alongside it — a recommendation, not a constraint. Below the floor it is still only a warning, and the exact text is:

```
warning: The macOS deployment target 'MACOSX_DEPLOYMENT_TARGET' is set to 10.9, but the range of supported deployment target versions is 10.13 to 26.5.99. (in target 'HSTracker' from project 'HSTracker')
```

**One nuance worth recording.** Apple's published [Xcode support table](https://developer.apple.com/support/xcode/) lists Xcode 26.6 as supporting "macOS 11-26.5". So 10.14 is below Apple's *documented* support range while being above the SDK's *enforced* floor. That is undocumented-but-working territory. It is not breaking anything, and upstream ships `minos 10.14` binaries built on Xcode 26, so this is a theoretical exposure only.

**Do not change this.** Per the ticket, raising the deployment target belongs to a later ticket. Nothing in #2 requires it.

**Related prediction, unverified.** The project-level `MACOSX_DEPLOYMENT_TARGET` is `10.12` (`project.pbxproj:9520-9577`, `:9578-9629`), below the 10.13 floor. Both real targets override it (10.14 for the app, 11.0 for tests), so it is inert for them, but Swift Package targets may inherit it and emit the warning above once per package. Expect noise, not errors. Not confirmed, because no normal-configuration build has got that far.

---

### 3.7 Non-issue: there is no Carthage step, and `downloaded-frameworks` is not Carthage output

The ticket asks "what the Carthage step and `downloaded-frameworks` need". The answer to the first half is that **there is no Carthage step**, and the two things are unrelated.

**Evidence.**

- No `Cartfile` and no `Cartfile.resolved` exist. They were deleted in commit `acb917a4`, "Move dependencies to SPM instead of Carthage", on **2021-01-25**.
- `project.pbxproj` contains **zero** occurrences of "carthage", case-insensitive. No `carthage copy-frameworks` phase, no `Carthage/Build` file reference, no Carthage entry in any search path. The `Recovered References` group where removed Carthage frameworks normally accumulate exists and is empty (`project.pbxproj:4698-4704`).
- Carthage is not installed on this machine (`which carthage` → not found), which is fine, because nothing calls it.
- Dependencies are now 21 Swift Package Manager pins, resolved successfully here by `xcodebuild -list` (`HSTracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`).

The only surviving `carthage` strings in the repo are dead: `fastlane/Fastfile:86` and `:108-112` (the `ci` and `release` lanes, which would fail at the `carthage` action if anyone ran them), and `scripts/hstracker_release.rb:69-70`, which sits inside a `=begin … =end` comment block. `.travis.yml` is likewise dead — it pins `osx_image: xcode11`, calls `brew upgrade carthage`, and travis-ci.org has been shut down for years, though `README.md:2` still shows its badge.

`downloaded-frameworks/` is produced entirely by the three `wget` script phases described in §3.2. It is not a package-manager directory.

**Do the prebuilt binaries still link?** Nothing about them blocks it:

- **HearthMirror.framework** is a classic versioned fat framework (not an xcframework), `lipo -info` → `x86_64 arm64`, `LC_BUILD_VERSION` `minos 10.14` / `11.0` with **`sdk 14.5`**. Linking a framework built against an older SDK into an app built against a newer one is normal and supported. It is pinned by git SHA1 in `HSTracker/HearthMirror-version.txt` (`fd2813513cf4a470c56d681bd434b2faa4d68291`, artifact last modified 2026-08-31) and fetched from `https://libs.hearthsim.net/hstracker/$SHA1/`. The source repo `github.com/HearthSim/HearthMirror` returns 404 — it is closed source, which is why the download phase exists at all ([issue #1114](https://github.com/HearthSim/HSTracker/issues/1114)).
- **The .NET 8 Mono runtime** ships `libcoreclr.dylib` and `libSystem.Native.dylib` per architecture, which `Download Mono` `lipo`s into `mono/universal`. Only `libcoreclr.dylib` is actually linked (`project.pbxproj:3339`, `:4077`).

**Smallest fix.** None for the build. Separately, `fastlane/Fastfile`, `scripts/hstracker_release.rb` and `.travis.yml` are dead weight that will mislead the next person; deleting them is a legitimate cleanup but belongs to its own ticket, and every deletion is a merge cost, so it is not free.

---

### 3.8 Non-issue for the build, open question for the run: the bridging header and the Mono runtime

**The bridging header survives.** `HSTracker/HSTracker-Bridging-Header.h` imports, in order: `<Sparkle/Sparkle.h>` (now an SPM product, not Carthage), the in-tree `GlowFilter.h` and `FileUtils.h`, `<HearthMirror/HearthMirror.h>` and `<HearthMirror/security.h>` from the downloaded framework, and nine `<mono/…>` headers including `<mono/jit/mono-private-unstable.h>`. `SWIFT_OBJC_BRIDGING_HEADER = HSTracker/HSTracker-Bridging-Header.h` in both configurations. Nothing in the header is toolchain-sensitive; it resolves or fails purely on whether `downloaded-frameworks` exists. Header lookup is arch-correct: `HEADER_SEARCH_PATHS` has `[arch=arm64]` and `[arch=x86_64]` variants pointing at `runtimes/osx-arm64/…` and `runtimes/osx-x64/…` respectively (`project.pbxproj:9640-9672`).

**"Vendored Mono" is a misnomer worth correcting.** Nothing is vendored — the tree contains no Mono binaries at all. `HSTracker/mono-version.txt` = `8.0.29` selects the **.NET 8 Mono runtime** from NuGet, not classic Mono. The version history makes the lineage plain: `6.0.8` (2022) → `7.0.5`/`7.0.10`/`7.0.14`/`7.0.15`/`7.0.16`/`7.0.20` → `8.0.29` (2026-08-06). These are .NET major versions. Confirming details: `mono-private-unstable.h` exists in [dotnet/runtime](https://github.com/dotnet/runtime/blob/release/8.0/src/native/public/mono/jit/mono-private-unstable.h) and returns 404 in classic `mono/mono`; and `MonoHelper.load()` (`HSTracker/Mono/MonoHelper.swift:303-386`) calls `monovm_initialize` with `TRUSTED_PLATFORM_ASSEMBLIES` and checks for `System.Private.CoreLib.dll` — CoreCLR APIs, not classic Mono ones.

macOS 26 is a supported OS for .NET 8 on both Arm64 and x64 ([supported-os.md](https://github.com/dotnet/core/blob/main/release-notes/8.0/supported-os.md)), and the JIT entitlement the app already carries is exactly what Microsoft documents as required: "For apps not published as Native AOT, the `com.apple.security.cs.allow-jit` entitlement is required" ([Deploying .NET apps on macOS](https://learn.microsoft.com/en-us/dotnet/core/deploying/macos)).

**One dated fact to record, no action now.** .NET 8 reaches end of support on **2026-11-10** ([.NET support policy](https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core)), roughly ten weeks out. Also, `8.0.29` is no longer the newest 8.0.x — `8.0.30` shipped 2026-08-11. Neither affects whether the build works; both belong to a future ticket, and bumping the pin is upstream's call.

---

### 3.9 The external SSD is a non-problem for finding Hearthstone, and the real attach risk is elsewhere

**The install path is configurable and requires no code change.**

- `Settings.hearthstonePath` defaults to `/Applications/Hearthstone` and is backed by the UserDefaults key `hearthstone_log_path` (`HSTracker/Core/Settings.swift:180-181`, `:617`).
- Both the first-run wizard (`HSTracker/UIs/Preferences/InitialConfiguration.swift:75-91`) and Preferences → Game (`HSTracker/UIs/Preferences/GamePreferences.swift:62-84`) open an `NSOpenPanel` filtered to `Hearthstone.app` and store its parent directory. Pointing the app at `/Volumes/ESD310C Transcend SSD/Hearthstone` is a few clicks.
- When the path is wrong, `GamePreferences.viewWillAppear` (`:34-47`) puts up a critical alert, "Can't find Hearthstone, please select Hearthstone.app", and enables the picker. It degrades to a prompt, not a crash.
- `CoreManager.validatedHearthstonePath` (`HSTracker/Logging/CoreManager.swift:119-123`) simply checks that `<path>/Hearthstone.app` exists. Verified present: `/Volumes/ESD310C Transcend SSD/Hearthstone/Hearthstone.app`.

**And that setting barely matters at runtime**, which is the more useful finding. Everything the tracker actually needs is located without reference to the install path:

- **The game process** is found by bundle identifier, not path: `unity.Blizzard Entertainment.Hearthstone` via `NSWorkspace.shared.runningApplications` (`CoreManager.swift:500-503`).
- **`log.config`** is at a fixed, install-independent location: `~/Library/Preferences/Blizzard/Hearthstone/log.config` (`CoreManager.swift:491-494`). `CoreManager.setup()` (`:137-265`) creates or repairs it there. Verified present on this machine.
- **The log directory** is read out of the running game's memory, not derived from any path: `MirrorHelper.getLogSessionDir()` (`CoreManager.swift:290`, `HSTracker/HearthMirror/MirrorHelper.swift:429-435`), and that result is what `LogReaderManager` is constructed with (`CoreManager.swift:297`).

So the SSD location is, at worst, one dialog on first run.

**The real risk is `task_for_pid`, and it is unresolved.** Before constructing the mirror, `MirrorHelper.initMirror` (`MirrorHelper.swift:37-63`) calls `acquireTaskportRight()` from `<HearthMirror/security.h>`. That is the `task_for_pid` path, and it is what `com.apple.security.cs.debugger` exists for. Apple's documentation for that entitlement states:

> "even with the debugging tool entitlement, a debugger can't get the task ports of processes that don't have the Get task allow entitlement… When a non-root user runs an app with the debugging tool entitlement, the system presents an authorization dialog asking for a system administrator's credentials. If authorization succeeds, the debugger receives a 10-hour session before authorization expires."
> — [Debugging Tool Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.debugger)

Two observed facts bear on this. First, ad-hoc signing does **not** strip the entitlement (§3.1), so the local-signing path is not what would break the attach. Second, the Hearthstone install on the SSD is signed by team `G847MC6JZ5` with `flags=0x0(none)` and carries **no entitlements at all** — no hardened runtime, and no `get-task-allow`. That is the permissive third-party case historically, but by the letter of Apple's documentation it lacks `get-task-allow`, so Apple's guarantee does not cover it. Apple DTS is also explicit that non-developer-tool use of `task_for_pid` is on borrowed time: "If you use it for anything else, it's likely that your use case will be blocked by the current security policy but, if not, it may well be blocked by future changes to that policy" ([forums 734461](https://developer.apple.com/forums/thread/734461)). No macOS 26 change to `task_for_pid` or the debugger entitlement is documented in the [macOS 26 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-26-release-notes).

**Verified: it attaches.** The ad-hoc-signed local build read the live game running from the external SSD:

```
Game.set():1775 - has Valid Mirror Deck: 17 cards
```

That value comes through `MirrorHelper`, so `acquireTaskportRight()` succeeded and `task_for_pid` was granted against a Hearthstone installed outside `/Applications`. `acquireTaskportRight() failed!` appears zero times in the app log across every run. The rest of the chain also came up clean, with no path configuration touched: `client.config is up-to-date`, all six zones `valid ? true`, `Missing zones : []`. Whether an administrator-password dialog appeared on screen was not captured — the log records no failure either way, and the ten-hour session in Apple's documentation still applies.

**One loose end.** In the same startup, `LogReader.init()` logged `Init reader for power at path /Power.log`, i.e. an empty base directory, because the readers are constructed before `MirrorHelper.getLogSessionDir()` has a value. Later runs do log `Starting log reader` with a real path, so this appears to be ordering rather than breakage, but it was not chased down and is not covered by #2.

**One more runtime gate to be aware of.** `CoreManager.internalStartTracking` (`CoreManager.swift:275-288`) refuses to start on Apple Silicon if Hearthstone is running as x86_64 under Rosetta, showing a critical alert and returning. On this M4 the SSD install must be the native arm64 build, or the tracker will not start regardless of everything above.

---

### 3.10 Non-issue: Swift 5 language mode and the dependency graph

**Swift 5 mode is fully supported on this toolchain.** Apple's [Xcode support table](https://developer.apple.com/support/xcode/) lists Xcode 26.6 with compiler Swift 6.3 and language modes "Swift 6, Swift 5, Swift 4.2, Swift 4". `EFFECTIVE_SWIFT_VERSION = 5` here. Reviewing swiftlang's own changelogs, the [Swift 6.2 CHANGELOG](https://github.com/swiftlang/swift/blob/swift-6.2-RELEASE/CHANGELOG.md) contains no entry that turns a Swift-5-mode warning into an error, the concurrency defaults (`NonisolatedNonsendingByDefault`, `ApproachableConcurrency`) are opt-in features this project does not enable, and existential `any` was downgraded to a warning in Swift 6.1 "until a future language mode". The [Swift 6.3 CHANGELOG](https://github.com/swiftlang/swift/blob/swift-6.3-RELEASE/CHANGELOG.md) has no 6.3 section at all. The one language-mode-independent source break to watch for is Swift 6.2's change to availability diagnostics, which can surface as `error: ambiguous use of …` in old code.

**The dependency graph compiles.** This is the most useful by-product of the second build run. With signing disabled, `xcodebuild` got past build-description creation and into the SPM graph, emitting 31 Swift compile/emit-module tasks across it. Realm, realm-core (`RealmCore`, `Bid`), Sparkle, Sentry, Mixpanel, PromiseKit, OAuthSwift, BigInt, FMDB, Gzip, SwiftyBeaver, Preferences, CustomToolTip, AppMover, swift-atomics and TextAttributes all appear in the log as scheduled targets, for both `arm64` and `x86_64`. **The only failures in the entire run were five availability errors in `TextAttributes`, all of the form:**

```
TextAttributes.swift:591:20: error: 'URL' is only available in macOS 10.10 or newer
```

Those are a pure artifact of that run's injected `MACOSX_DEPLOYMENT_TARGET=10.9` override and **cannot occur at the project's real 10.14 target**. Nothing else errored. In particular the pinned Realm 10.32.3 / realm-core 12.11.0 — the most obvious candidate for a modern-clang C++ breakage — produced no errors before the run stopped.

**Caveat, now lifted.** That run halted on the first failure, so not every target finished, and it was evidence of a healthy graph rather than proof. The second pass supplied the proof: a full Debug `xcodebuild` of the real project, at the real 10.14 target with signing in place, completed with exit 0 and no `error:` line attributed to any package target.

**Corroborated independently.** A probe SwiftPM package pinned to all 20 dependencies at their exact resolved tags and revisions, with `platforms: [.macOS(.v10_14)]`, was built with `swift build` on this same toolchain: **exit 0, zero errors**, binary links and runs. Realm was built separately at `realm-swift v10.32.3` + `realm-core 12.11.0` — also **exit 0**, producing 178 objects for `RealmCore`, 61 for `Realm`, 52 for `RealmSwift`. So the graph does not merely start compiling, it completes. (Caveat on this probe: `swift build`, not `xcodebuild`, so any Xcode-only flags this project sets were not applied.)

The Realm result deserves a note, because Realm 10.32.3 *looks* like the obvious casualty and is not. Realm's own CHANGELOG at that tag declares `Xcode: 13.1-14.1`, twelve Xcode majors ago. The known Xcode 26 Realm breakages are `std::is_pod` specialization failures in vendored **s2geometry** ([realm-swift #8823](https://github.com/realm/realm-swift/issues/8823), [realm-core #8095](https://github.com/realm/realm-core/issues/8095), both still open) and an ARC `array_cookie` error in `RLMCollection.mm` ([#8769](https://github.com/realm/realm-swift/issues/8769)). Neither can occur here: `src/external` at [realm-core v12.11.0](https://github.com/realm/realm-core/tree/v12.11.0/src/external) contains no `s2` directory at all, and the offending `RLMCollection.mm` code was written after 2022. Being *old* is what saves this pin. Worth knowing for later: the next Realm on the upgrade path, 10.54.6, is itself broken by clang-2100, so the escape hatch is a jump to 20.0.4+.

**Smallest fix.** None.

---

### 3.11 Not build breakage, but worth recording: two dependency pins carry real risk

Neither of these stops the build. Both were found while verifying §3.10 and would be dishonest to omit.

**Sparkle 2.6.4 is missing security fixes.** Sparkle 2.7.2 and 2.7.3 (2025-09-08/09) are described by the project as ["Important security fixes for local exploits"](https://github.com/sparkle-project/Sparkle/releases/tag/2.7.2). The pin here is 2.6.4, from 2024-06-30, which predates them. This is not a build concern at all — at 2.6.4 Sparkle's `Package.swift` is a single `.binaryTarget` pointing at a prebuilt zip, so the compiler and SDK never touch it — it is a shipped-software concern. Its updater UI also predates macOS Tahoe; [2.8.0](https://github.com/sparkle-project/Sparkle/releases/tag/2.8.0) added "macOS Tahoe support". Upgrading is a one-line version bump in `project.pbxproj` and a drop-in binary swap, but it is upstream's pin to move and belongs to its own ticket.

**`CustomToolTip` is pinned to a branch, not a version.** `Package.resolved` records `"branch": "main"` with revision `e712cfd` for [fmoraes74/CustomToolTip](https://github.com/fmoraes74/CustomToolTip), a single-author repository. A branch pin means a force-push upstream can silently change what this project builds. It is also the only dependency in the graph whose declared platform floor is `.macOS(.v10_14)` — exactly the app's target, so it is the pin that would break first if the deployment target were ever *lowered*. No package in the graph declares a floor above 10.14, so no "requires macOS 10.15 or newer" diagnostic is possible.

**Two more, informational only, all compiling cleanly:** `Thomvis/BrightFutures 8.0.1` is [archived and read-only](https://github.com/Thomvis/BrightFutures) (pulled in via Erik), and `PromiseKit 6.13.3` has a `swift-tools-version:4.0` manifest, making it the only package still compiled in `-swift-version 4` mode — fine today, broken the day swiftc drops mode 4.

---

## 4. What the build and the run settled

Every open question from the first pass, answered by observation. Four `xcodebuild` runs and three launches; see §5 for what they were.

| Question from the first pass | Answer |
| --- | --- |
| Do the three download phases succeed, and does Homebrew `wget` resolve on the Run Script `PATH`? | **Yes**, from a login shell. All three ran and populated `downloaded-frameworks/`. GUI-Xcode case untested, see §3.2 |
| Does `Embed Mono` fail on `net7.0`? | **Yes**, exactly the predicted `cp … No such file or directory`, and it was the only failure in the run |
| Do the 1817 HSTracker Swift files compile under Swift 6.3.3 in Swift 5 mode at a 10.14 target? | **Yes.** Zero `error:` lines in the entire 20488-line log. Two warnings only, both about script phases lacking declared outputs (`Swiftlint`, `Update version`) |
| Does the dependency graph compile under `xcodebuild`, not just `swift build`? | **Yes.** No package target errored, Realm 10.32.3 included |
| Does the app link against `HearthMirror.framework` and `libcoreclr.dylib` with `-ld_classic`? | **Yes.** Both are in `Contents/Frameworks` of the built bundle and the app runs |
| Do the 70 `.xib` files compile? | **Yes.** The build reached completion; no `ibtool` diagnostics |
| Does the ad-hoc-signed app launch under hardened runtime with `--deep`? | **Yes.** Hardened runtime is disabled automatically under ad-hoc signing (§3.1) |
| Does `monovm_initialize` succeed, or hit the PR #1431 crash? | Runtime **initialises** (`Loading mono version 8.0.29.0`, `Loaded BobsBuddy version 1.70.0.0`). The PR #1431 crash **did** occur, root cause `System.Runtime.Intrinsics.dll`; fixed, see §3.3 |
| Does `acquireTaskportRight()` succeed against Hearthstone on the SSD? | **Yes.** `has Valid Mirror Deck: 17 cards`; no `acquireTaskportRight() failed!` anywhere in the log |
| Does `MirrorHelper.getLogSessionDir()` return a non-empty path? | **Partly.** Readers are first constructed with an empty base (`/Power.log`), later runs log a real path. Ordering quirk, see §3.9 |
| Does the arm64 Rosetta guard trip? | **No.** The SSD install is the native arm64 build |

**Still open, and deliberately not chased under #2:**

- The GUI-Xcode `PATH` case for `wget` (§3.2).
- The `x86_64` slice: Debug builds `ONLY_ACTIVE_ARCH`, so only `arm64` has been exercised (§3.1).
- `HSTrackerTests` still cannot build (§3.4). `xcodebuild build` does not reach it.
- The `Init reader … at path /Power.log` ordering quirk (§3.9).
- The unconditional `testSimulation()` call and its `fatalError` crash path in Release (§3.3).
- Whether the tracker actually follows a live match end to end. Attaching is verified; playing a game through it is not.

---

## 5. Methodology note and disclosures

### Second pass — fixes applied and verified

The three changes in §2 were applied and the result was measured. Four builds and three launches, in order:

| Run | Command | Outcome |
| --- | --- | --- |
| Build 1 | `xcodebuild … -scheme HSTracker -configuration Debug build` | Exit 65. All Swift compiled, download phases ran, died only at `Embed Mono` on `net7.0` |
| Build 2 | same, after `NET_VERSION=net8.0` | Exit 0. Bundle complete: ad-hoc signed, 35 assemblies per arch, `CardDefs.bin` 50 MB |
| Launch 1 | run the bundle's binary directly | Started, attached to Hearthstone, crashed at `MonoHelper.swift:525` |
| Build 3 + Launch 2 | same, with a temporary `[DEBUG-a4f2]` log in the `fatalError` branch | Printed the `System.Runtime.Intrinsics` `FileNotFoundException` |
| Build 4 + Launch 3 | same, instrumentation removed, `System.Runtime.Intrinsics.dll` added to `ASSEMBLIES` | Exit 0, no crash, simulation completed |

The `[DEBUG-a4f2]` instrumentation was temporary and has been removed; `MonoHelper.swift` is byte-identical to upstream. Builds wrote to this machine's relocated DerivedData at `/Volumes/ESD310C Transcend SSD/Xcode-DerivedData/`; logs are at `/tmp/hstracker-build{1..4}.log` and `/tmp/hstracker-run{,2,3}.log`.

**Repo state after this pass:** `Config.xcconfig` and `HSTracker.xcodeproj/project.pbxproj` are modified, plus this untracked note. Nothing else. `Config.xcconfig` must never be committed to a PR (`CONTRIBUTING.md:44`).

### First pass — read-only investigation, and one disclosure

The first pass was scoped as read-only, and that was honoured for the repository itself: `git status --porcelain` was empty and no file in the repo was modified.

However, **two `xcodebuild build` runs were executed** by a research subagent, exceeding the read-only brief. They are disclosed here because their output was the strongest evidence in the first draft of this note and the reader should know its provenance:

- **Run 1**, no overrides, real repo: produced the verbatim signing error in §2. Wrote only to `/tmp/hsb/`.
- **Run 2**, with `CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= MACOSX_DEPLOYMENT_TARGET=10.9`: produced the dependency-graph evidence in §3.10. Wrote only to `/tmp/hsb4/`.

Both used `SYMROOT`/`OBJROOT` overrides pointing at `/tmp`. Package checkouts landed in this machine's relocated DerivedData at `/Volumes/ESD310C Transcend SSD/Xcode-DerivedData/HSTracker-acoqezryzjhjmcetmstcvfxgyjxr/`. Logs are at `/tmp/xcb.log` and `/tmp/xcb109.log`. The agent's initial summary described run 1 as "a full xcodebuild build"; on challenge it corrected this to "died at build-description creation, before ANY task ran", which is the characterisation used throughout this note.

Toolchain probes (`swiftc` at various targets, `-ld_classic`, `ibtool` on `LanguageChooser.xib`, `otool`, `lipo`, `codesign -d`) were inspection-only and wrote nothing outside `/tmp` and the scratchpad.

---

## 6. Sources

### Apple

| URL | Used for |
| --- | --- |
| https://developer.apple.com/support/xcode/ | Xcode 26.6 documented deployment-target range (macOS 11-26.5), Swift 6.3 compiler, supported language modes including Swift 5 (§3.6, §3.10) |
| https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes | Confirming Xcode 26 documents no deployment-target floor and no linker change (§3.5, §3.6) |
| https://developer.apple.com/documentation/xcode-release-notes/xcode-15-release-notes | New linker introduced, classic linker "will be removed in a future release" (§3.5) |
| https://developer.apple.com/documentation/xcode-release-notes/xcode-16-release-notes | Formal deprecation of `-ld_classic` (§3.5) |
| https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes | `-ld_classic` removed in Xcode 27 — the dated fuse (§3.5) |
| https://developer.apple.com/forums/thread/781538 | Apple DTS on the `-ld_classic` migration timeline (§3.5) |
| https://developer.apple.com/documentation/macos-release-notes/macos-26-release-notes | No `task_for_pid` / hardened-runtime / signing changes in macOS 26 (§3.9) |
| https://developer.apple.com/documentation/xcode/build-settings-reference | `CODE_SIGN_IDENTITY` and `CODE_SIGN_STYLE` semantics; missing certificate causes a build error (§3.1) |
| https://developer.apple.com/forums/thread/815248 | Apple DTS: do not use Developer ID for daily development; the "No certificate for team" failure shape (§3.1) |
| https://developer.apple.com/support/compare-memberships/ | Developer ID requires paid membership; free Personal Team limits (§3.1) |
| https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements | "Sign to Run Locally" is ad-hoc signing; no stable designated requirement (§3.1) |
| https://developer.apple.com/forums/thread/751658 | Ad-hoc drawbacks: no restricted entitlements, TCC instability (§3.1) |
| https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles | Hardened-runtime entitlements are unrestricted — ad-hoc keeps `cs.debugger` (§3.1, §3.9) |
| https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime | `com.apple.security.cs.debugger` is a hardened-runtime exception (§3.1) |
| https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.debugger | `get-task-allow` requirement, admin authorization dialog, 10-hour session (§3.9) |
| https://developer.apple.com/forums/thread/734461 | Apple DTS: non-developer-tool `task_for_pid` likely to be blocked (§3.9) |
| https://developer.apple.com/forums/thread/129980 | "`--deep` Considered Harmful" (§3.1) |

### swift.org / swiftlang

| URL | Used for |
| --- | --- |
| https://github.com/swiftlang/swift/blob/swift-6.2-RELEASE/CHANGELOG.md | No Swift-5-mode error escalations in 6.2; existential `any` still a warning; availability-diagnostics source break (§3.10) |
| https://github.com/swiftlang/swift/blob/swift-6.3-RELEASE/CHANGELOG.md | No Swift 6.3 section; nothing new breaks Swift 5 mode (§3.10) |

### Dependencies

| URL | Used for |
| --- | --- |
| https://github.com/realm/realm-swift/releases/tag/v10.32.3 | Pin date 2022-11-11 and its declared `Xcode: 13.1-14.1` support window (§3.10) |
| https://github.com/realm/realm-core/tree/v12.11.0/src/external | No `s2` directory at this tag — why the Xcode 26 `is_pod` failure cannot occur here (§3.10) |
| https://github.com/realm/realm-swift/issues/8823 | Open: `std::is_pod` specialization rejected in s2geometry on Xcode 26.4 (§3.10) |
| https://github.com/realm/realm-core/issues/8095 | Open: same root cause in realm-core (§3.10) |
| https://github.com/realm/realm-swift/issues/8769 | Closed: ARC `array_cookie` error in `RLMCollection.mm` under the 26 SDK (§3.10) |
| https://github.com/sparkle-project/Sparkle/releases/tag/2.7.2 | "Important security fixes for local exploits" — the pin at 2.6.4 predates these (§3.11) |
| https://github.com/sparkle-project/Sparkle/releases/tag/2.8.0 | macOS Tahoe support added after the pinned version (§3.11) |
| https://github.com/fmoraes74/CustomToolTip | The branch-pinned, single-author dependency; only `.macOS(.v10_14)` floor in the graph (§3.11) |
| https://github.com/Thomvis/BrightFutures | Archived and read-only (§3.11) |
| https://github.com/mxcl/PromiseKit/blob/6.13.3/Package.swift | `swift-tools-version:4.0` — the last package compiled in Swift 4 mode (§3.11) |

### Upstream HearthSim/HSTracker

| URL | Used for |
| --- | --- |
| https://github.com/HearthSim/HSTracker/releases/tag/3.6.7 | Newest release 2026-08-28; its binary is universal, SDK 26.2, minos 10.14/11.0 — proof the config builds on Xcode 26 (§2) |
| https://github.com/HearthSim/HSTracker/pull/1411 | "Use curl instead of wget" — `wget` absent from macOS, Homebrew `/opt/homebrew` PATH problem; closed unmerged (§3.2) |
| https://github.com/HearthSim/HSTracker/pull/1431 | Mono 8.0.29 / `net7.0` mismatch and the resulting launch crash; built on Xcode 26.6; closed unmerged (§3.3) |
| https://github.com/HearthSim/HSTracker/commit/d70efe058 | The 2026-08-06 bump of `mono-version.txt` 7.0.20 → 8.0.29 without touching `NET_VERSION` (§3.3) |
| https://github.com/HearthSim/HSTracker/pull/1361 | Apple Silicon arm64 support, merged 2025-08-12; origin of the `lipo` universal step (§3.7) |
| https://github.com/HearthSim/HSTracker/issues/1390 | Universal build request; resolved in 3.5.9 (§3.7) |
| https://github.com/HearthSim/HSTracker/issues/1114 | Why the HearthMirror download phase exists — contributors have no repo access (§3.7) |
| https://github.com/HearthSim/HSTracker/issues/1436 | Open: `abort()` in `mono_thread_detach` on 3.6.7 — current Mono instability upstream (§3.8) |
| https://github.com/HearthSim/HSTracker/blob/master/.github/workflows/asia-release.yml | The only CI workflow; publishes an existing asset, does not build (§3.7) |

### .NET / Microsoft

| URL | Used for |
| --- | --- |
| https://www.nuget.org/packages/Microsoft.NETCore.App.Runtime.Mono.osx-x64/8.0.29 | Confirms 8.0.29 exists, published 2026-07-14, and its `lib/net8.0` layout (§3.3) |
| https://www.nuget.org/packages/Microsoft.NETCore.App.Runtime.Mono.osx-arm64/8.0.29 | Same for the arm64 half needed by the `lipo` step (§3.3) |
| https://github.com/dotnet/core/blob/main/release-notes/8.0/8.0.29/8.0.29.md | .NET 8.0.29 release, 2026-07-14 (§3.3) |
| https://github.com/dotnet/runtime/blob/release/8.0/src/native/public/mono/jit/mono-private-unstable.h | `mono-private-unstable.h` is a dotnet/runtime file, absent from classic Mono (§3.8) |
| https://github.com/dotnet/core/blob/main/release-notes/8.0/supported-os.md | macOS 26 is supported by .NET 8 on Arm64 and x64 (§3.8) |
| https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core | .NET 8 end of support 2026-11-10; 8.0.30 is newer than the pin (§3.8) |
| https://learn.microsoft.com/en-us/dotnet/core/deploying/macos | `allow-jit` required for non-AOT; `cs.debugger` for attaching; ad-hoc re-signing after `lipo` (§3.8) |

### This repository

`Config.xcconfig:13-14,17-18` · `CONTRIBUTING.md:41-44` · `.gitignore:6,27` · `.swiftlint.yml` · `.travis.yml` · `README.md:2` · `HSTracker/mono-version.txt` · `HSTracker/BobsBuddy-version.txt` · `HSTracker/HSTracker-Bridging-Header.h` · `HSTracker/HSTracker.entitlements:9-10` · `HSTracker/Info.plist:42-43` · `HSTracker/Core/Settings.swift:180-181,617` · `HSTracker/Logging/CoreManager.swift:119-123,137-265,275-288,290,297,491-494,500-503` · `HSTracker/Logging/LogReaderManager.swift:68-87` · `HSTracker/Logging/LogReader.swift:28-43` · `HSTracker/HearthMirror/MirrorHelper.swift:37-63,429-435` · `HSTracker/Mono/MonoHelper.swift:303-386` · `HSTracker/UIs/Preferences/GamePreferences.swift:34-47,62-84` · `HSTracker/UIs/Preferences/InitialConfiguration.swift:75-91` · `HSTracker/Resources/Managed/.gitignore` · `fastlane/Fastfile:86,108-119` · `scripts/bootstrap.sh` · `scripts/compile_hslog.sh` · `scripts/hstracker_release.rb:66-129` · `HSTracker.xcodeproj/project.pbxproj:3262,3339,4077,4105,4698-4704,6828-6841,7121-7140,7141-7165,7166-7186,7235-7256,9520-9629,9630-9692,9693-9755,9756-9823` · `HSTracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` · commits `acb917a4` (2021-01-25, Carthage removal) and `2561b20b` (2023-11-06, `-ld_classic` added)
