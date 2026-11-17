# Known limitations of the base-image matrix

Every image in `test/images.txt` passes with ocx 0.6.8. Nothing is treated as an expected failure.

- **wolfi, ocx glibc detection.** The runtime contract expected `ocx` to misdetect glibc on
  `cgr.dev/chainguard/wolfi-base` and to need `--platform linux/<arch>+libc.glibc`. With ocx 0.6.8,
  `ocx add ocx.sh/jqlang/jq:1.8` and `ocx exec -- jq --version` work without it (musl and glibc
  builds exist for jq, so the pull succeeds either way). A package published for glibc only could still
  need the flag; the test does not cover that.
- **bare `busybox:musl`.** No package manager and no CA bundle, so a network install cannot work.
  The `busybox` entry runs on `ocx-test/busybox-ca:local` (`test/images/busybox-ca/Dockerfile`); the
  same run asserts that the feature on the bare image fails with `missing: ca-bundle ... set the
  caBundle option to a PEM file in the image`.
- **archlinux** is published for amd64 only; arm64 hosts skip it (`skipped: not published for arm64`).
