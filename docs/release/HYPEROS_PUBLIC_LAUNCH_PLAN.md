# Hyper OS Public Launch Plan

## A. Release Plan

### Versioning
- Format: `Hyper OS YYYY.R` (example: `Hyper OS 2026.1`)
- Build metadata: ISO filename includes date + git short SHA.

### Launch phases
1. **Internal Alpha** (2 weeks)
   - Scope: boot/install regressions, packaging sanity, updater reliability.
2. **Public Beta 1** (first public release)
   - Recommended first public label: **beta**, not stable.
3. **Public Beta 2 / RC** (2-4 weeks)
   - Focus: installer reliability, GPU/gaming compatibility fixes.
4. **Stable 2026.1** only after exit criteria pass.

### Exit criteria to leave beta
- No critical installer/bootloader bug open for 14 days.
- Verified boot success on Intel/AMD/NVIDIA test matrix.
- Cloud profile updater and offline fallback verified.

## B. Pre-Launch Checklist

### Boot matrix
- [ ] QEMU (UEFI + BIOS) boots live session.
- [ ] VirtualBox (UEFI + BIOS) boots live session.
- [ ] Real hardware boot test (at least 3 systems).

### Installer matrix
- [ ] Calamares completes guided install.
- [ ] UEFI bootloader installed and boots.
- [ ] BIOS bootloader installed and boots.
- [ ] Installed system reaches graphical login.

### GPU + desktop
- [ ] Intel iGPU boots and runs compositor-free Openbox session.
- [ ] AMD GPU boots and supports Vulkan apps.
- [ ] NVIDIA GPU boots; proprietary driver path documented.

### Gaming stack
- [ ] Steam starts and logs in.
- [ ] Proton title launches (at least 5 titles from top list).
- [ ] `hyperos-game-launch` applies profile env vars.
- [ ] `hyperos-profile-update` offline fallback verified.

### Reliability/security
- [ ] No default plaintext passwords.
- [ ] Autologin disabled by default.
- [ ] `hyperos-profile-update.timer` enabled and logs cleanly.

## C. Distribution

### Hosting
1. **Primary:** GitHub Releases (simple and trusted).
2. **Optional mirror:** object storage/CDN for bandwidth.

### Release artifacts
- `hyperos-2026.1-beta1-x86_64.iso`
- `hyperos-2026.1-beta1-x86_64.iso.sha256`
- `RELEASE_NOTES.md`
- `KNOWN_ISSUES.md`

## D. Website

Minimal launch website pages:
1. **Homepage**
   - tagline, release status (Beta), key features, clear caveats.
2. **Download**
   - ISO links, checksum, verification instructions.
3. **Features**
   - gaming optimization, installer, cloud profiles (with limits).
4. **System Requirements**
   - CPU, RAM, storage, GPU notes.

## E. Documentation

Required launch docs:
- Installation guide (USB creation + UEFI/BIOS notes).
- Troubleshooting guide (boot, Wi-Fi, NVIDIA, installer failures).
- Gaming quickstart (Steam, Proton, profile launcher, updater).
- Known limitations (anti-cheat/DRM compatibility caveats).

## F. Community Setup

### GitHub structure
- `hyper-os/iso` (build scripts, profile, docs)
- `hyper-os/profiles` (cloud JSON feed)
- `hyper-os/website` (landing + docs site)

### Issue templates
- Bug report
- Hardware compatibility report
- Feature request
- Game compatibility report

## G. Risks

Top launch risks and mitigations:
1. **Installer failures on specific hardware**
   - Mitigation: pre-launch hardware matrix + fallback CLI recovery docs.
2. **NVIDIA regressions**
   - Mitigation: pin tested driver branch in release notes.
3. **Cloud profile feed outage**
   - Mitigation: offline cache default + updater non-fatal behavior.
4. **User expectation mismatch on anti-cheat titles**
   - Mitigation: explicit compatibility disclaimers on download page.

## H. Next Steps

Post-launch (first 60 days):
1. Weekly bug triage and hotfix window.
2. Publish refreshed compatibility list every 2 weeks.
3. Ship new ISO monthly during beta, rolling package updates in between.
4. Promote to stable only after two consecutive low-regression beta cycles.
