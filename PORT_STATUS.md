# Source checkpoint 2

Target: iPhone 13 Pro Max, iOS 16.0.

Implemented: guarded newer library carousel, an iOS 16/17 shelf, UI compatibility
controls and callbacks, iOS 16 Swift package declarations, and compiler probes.
Custom SwiftUI key interception remains unavailable on iOS 16; native UIKit
keyboard behavior is retained. Touch/controller behavior needs device QA.

The Swift probe archives app and Madeira adapter sources. Its header-only
MadeiraNative target supplies declarations only and MUST NOT be shipped as a
runtime. The native probe compiles 12 actual native C/Objective-C units with
availability diagnostics treated as errors, plus 3 helper shaders as Metal 3.0.
Neither probe builds an installable emulator.

Local validation before repository setup: 190 Python tests passed, 8 skipped;
source privacy and repository standards checks passed; patch application and
installer idempotence verified. Three tests use a fake toolchain to check probe
orchestration only. This local test suite does not establish Apple compilation or device compatibility.

Remaining: true Metal 3.0 DXBC backend, DXMT OS-version mapping, native dependency
rebuilds, appropriate iOS 16 JIT allocation/preparation, final link, package audit,
and physical-device testing. Production app minimums remain unchanged.

Run the manual compiler workflow next. Retain both diagnostic artifacts, even
when a job fails. Do not treat this checkpoint as a working iOS 16 release.

## Build instructions

Open Actions → iOS 16 compiler checks → Run workflow → main → Run workflow.
After a patch update, start a new run; re-running an old run uses its old source.
Both jobs retain diagnostic artifacts. A green result establishes compilation
only, not runtime linking, installation, JIT, shader execution, or game support.

## Source

The workflow checks out upstream commit
`c5e759da30fd2547786ba7ea68657c611f6562c5`, applies
`patches/ios16-checkpoint.patch`, then `patches/ios16-compiler-fixes.patch`.
The source ZIP SHA-256 is
`b0c056c28e250b9dc16b68c49a15591efe8cb6f1438fb47e4f05687edf57006f`.
Full upstream source and license notices remain in that checkout.

The follow-up patch addresses missing compile-only resources and newer Metal
API calls. iOS 16 uses the default GPU and existing BC software decoding;
local geometry pipelines needing iOS 17 object linking are refused explicitly.
No automatic builds, signing credentials, or IPA publishing are configured.

## Next stage: shader runtime build

The Swift and native checks passed on commit
`f093afe90ed5bab6f339a0c5cb8d021142151aef` (Actions run `36600101581`).
This proves the selected source compilation only.

Run **Actions → iOS 16 shader runtime build → Run workflow → main** next.
This separate manual job rebuilds digest-pinned LLVM 15.0.7 for iOS 16.0,
compiles all 15 AIR translator units plus 3 DXBC parser units, and links a
diagnostic dynamic library with undefined symbols treated as errors. Availability
warnings are errors. It retains logs and the link map, and publishes no binaries.
The first build can take substantially longer than the earlier compiler checks;
the timeout is three hours, not an estimate of completion time.

The helper shaders are built as Metal 3.0, but translated game shaders still
use the upstream Metal 3.1/3.2 output path. A successful diagnostic link does not
establish iOS 16 shader execution. Metal 3.0 output, OS capability selection,
remaining native libraries, JIT, full app linking, and device testing remain.
