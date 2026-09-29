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
orchestration only. No Xcode or device results are claimed here.

Remaining: true Metal 3.0 DXBC backend, DXMT OS-version mapping, native dependency
rebuilds, appropriate iOS 16 JIT allocation/preparation, final link, package audit,
and physical-device testing. Production app minimums remain unchanged.

Run the manual compiler workflow next. Retain both diagnostic artifacts, even
when a job fails. Do not treat this checkpoint as a working iOS 16 release.
