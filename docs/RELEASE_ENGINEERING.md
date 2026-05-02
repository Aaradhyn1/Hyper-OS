# Hyper OS Release Engineering

## Versioning Strategy
- Release version format: `YYYY.MM.DD` (UTC).
- Build identifier: `YYYY.MM.DD-<git-short-sha>`.
- `SOURCE_DATE_EPOCH` defaults to latest commit timestamp.

Version metadata is embedded in:
- `/etc/hyper-release`
- `/etc/motd`

## Build Pipeline
1. `scripts/release/build-release.sh`
   - copies `hyperos/` profile into an isolated work directory
   - injects release metadata
   - runs `mkarchiso`
   - writes checksum + `build-meta.json`
2. `scripts/release/validate-iso.sh`
   - verifies checksum (if present)
   - checks UEFI El Torito boot records
   - validates embedded `/etc/hyper-release`
   - performs QEMU UEFI smoke boot

## Update Reliability Strategy
- Track rolling Arch repos by default.
- Run nightly CI builds to catch breakages early.
- Keep package list minimal and explicit.
- Gate release publication on successful validation scripts.

## Artifact Layout

```text
releases/
  YYYY.MM.DD/
    hyperos-<version>-x86_64.iso
    hyperos-<version>-x86_64.iso.sha256
    build-meta.json
    logs/
      build-<version>-<sha>.log
  latest -> YYYY.MM.DD
```

## CI Integration
- GitHub Actions workflow: `.github/workflows/release.yml`
- Builds in Arch Linux container with official packages only.
- Uploads `releases/**` as workflow artifacts.
