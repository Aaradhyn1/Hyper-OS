# Hyper OS Post-Install Setup

## Driver checks
- Intel/AMD: ensure `mesa` + `vulkan` packages are present.
- NVIDIA: install the recommended proprietary driver branch from release notes.

## Gaming setup
1. Start Steam and sign in.
2. Enable Proton for all titles in Steam settings.
3. Use launcher wrapper for profiles:
   - `hyperos-game-launch --profile steam-default -- %command%`
4. Run cloud profile update:
   - `sudo hyperos-profile-update`
