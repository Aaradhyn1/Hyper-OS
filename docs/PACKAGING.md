# Hyper OS Packaging and Repository

## Repository layout

```text
repo/
  x86_64/
    *.pkg.tar.zst
    *.pkg.tar.zst.sig
    hyperos.db -> hyperos.db.tar.gz
    hyperos.db.tar.gz
    hyperos.files -> hyperos.files.tar.gz
    hyperos.files.tar.gz
```

## Build flow
1. Build packages:
   - `scripts/repo/build-packages.sh`
2. Publish/update repo metadata:
   - `scripts/repo/publish-repo.sh`
3. Include `repo/x86_64` in ISO build via `scripts/release/build-release.sh`.

## Signing model
- Sign packages and repository metadata with maintainer GPG key.
- Use:
  - `SIGN_REPO=1`
  - `GPG_KEY_ID=<key-id>`
- Pacman trust comes from importing the Hyper OS public key into keyring.

## pacman integration
`hyperos/pacman.conf` includes:

```ini
[hyperos]
SigLevel = Required DatabaseOptional
Server = file:///run/archiso/bootmnt/repo/x86_64
```

For installed systems, replace `Server` with HTTPS mirror endpoint.

## Update compatibility strategy
- Keep first-party packages small and overlay-style.
- Avoid replacing Arch base packages unless required.
- Build nightly against latest Arch repos.
- Gate repo publication on package build + ISO validation success.
