# Hyper OS Troubleshooting

## No GPU detected
- Check `lspci | grep -Ei 'VGA|3D|Display'`
- Confirm firmware/driver packages are installed.

## Vulkan not working
- Run `vulkaninfo --summary`
- Reinstall Vulkan driver packages for your GPU.

## Game not launching
- Test raw launch without wrapper.
- Verify profile syntax in `/etc/hyperos/game-profiles/`.
- Check logs: `journalctl -u hyperos-gamed -n 100 --no-pager`
