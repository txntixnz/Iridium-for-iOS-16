# Iridium for iOS 16

Experimental source port targeting iOS 16.0. **No working iOS 16 IPA yet.**

This repository contains the port patch and a manual compiler workflow. Each run
fetches the exact upstream source revision matching the supplied source ZIP,
applies the patch, and runs separate Swift and native checks.

## Run the first compiler checks

1. Open **Actions** → **iOS 16 compiler checks**.
2. Select **Run workflow**, keep branch `main`, and confirm **Run workflow**.
3. Wait for both `swift` and `native` jobs to finish.
4. Download the diagnostic artifacts from the run page and share them for review.

A red job is useful: its logs identify remaining compatibility errors.
A green job establishes compilation only. It does not establish runtime linking,
JIT execution, shader execution, installation, or game compatibility.

## Reproducible source

- Upstream: https://github.com/intraducine/iridium
- Pinned source commit: `c5e759da30fd2547786ba7ea68657c611f6562c5`
- Source ZIP SHA-256: `b0c056c28e250b9dc16b68c49a15591efe8cb6f1438fb47e4f05687edf57006f`
- Port: `patches/ios16-checkpoint.patch` (source checkpoint 2)

The ZIP's Git archive comment identifies the pinned commit. The workflow verifies
that commit before applying the patch. It never follows a moving upstream branch.
The complete source and third-party licenses remain in the upstream checkout.
Original Iridium code is AGPL-3.0-only; mixed third-party licenses remain applicable.
See `LICENSE` and upstream `LICENSING.md`.

No automatic builds on push, signing credentials, game assets, or binary releases
are configured. See `PORT_STATUS.md` for current evidence and limitations.
