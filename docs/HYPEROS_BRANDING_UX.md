# Hyper OS Branding + UX Integration

## A. Brand Identity

- **Name:** Hyper OS
- **Tagline:** Speed, Focus, Victory
- **Design philosophy:** minimal, fast, futuristic, gaming-focused

### Palette

- Primary: `#6EC1FF`
- Accent: `#8B5CF6`
- Background: `#0F1117`
- Surface: `#1B1E24`
- Text: `#F5F7FA`
- Muted text: `#A6ADBB`

### Typography

- UI/System: DejaVu Sans (already lightweight and widely available)
- Terminal: monospace default with colored prompt accents

### Icon direction

- Flat, high-contrast dark icon theme (`Papirus-Dark`)

## B. Boot Customization

- Keep kernel parameters user-friendly: `quiet splash` for live entries.
- Maintain BIOS/UEFI reliability checks in build scripts and use a clean boot menu naming style.
- Keep timeout low and avoid verbose default output for end users.

## C. LightDM Theme

- Use minimal dark greeter with Hyper OS wallpaper.
- Centered login, host/clock/session/power indicators only.

Config file:
- `/etc/lightdm/lightdm-gtk-greeter.conf.d/30-hyperos.conf`

## D. Openbox Setup

- Single desktop default for focus.
- Autostart essentials only: wallpaper, tint2, network applet, desktop manager.
- Low-overhead panel (`tint2`) aligned with palette.

Config files:
- `/etc/xdg/openbox/autostart`
- `/etc/skel/.config/openbox/rc.xml`
- `/etc/skel/.config/openbox/autostart`
- `/etc/skel/.config/tint2/tint2rc`

## E. Calamares Branding

- Keep installer slides short and product-focused.
- Ensure wording matches identity and gaming proposition.

Branding files:
- `configs/calamares/branding/branding.desc`
- `configs/calamares/branding/show.qml`

## F. Terminal Identity

- Lightweight prompt branding via `/etc/profile.d/hyperos-prompt.sh`.
- `fastfetch` installed for quick branded system summary.

## G. Package Structure

Proposed packaging split for maintainability:

- `hyperos-theme`
  - Openbox/tint2 configs
  - LightDM greeter config
  - terminal prompt profile
- `hyperos-branding`
  - identity metadata
  - logos and installer strings
- `hyperos-wallpapers`
  - SVG/WEBP wallpapers only (lightweight assets)

Reference package manifests are staged in:
- `configs/branding/packages/`

## H. Future Improvements

- Optional subtle boot/login animations (disabled by default)
- Wayland-ready theme variants
- Per-GPU dynamic accenting in gaming UI
