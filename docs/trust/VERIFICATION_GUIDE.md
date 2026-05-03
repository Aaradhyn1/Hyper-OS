# Hyper OS Verification Guide

## Run system check
```bash
hyperos-check.sh
```

## Expected output style
- `✔` for successful checks
- `⚠` for warnings (non-fatal)
- `❌` for failed checks requiring action

## Log locations
- Main validation log: `/var/log/hyperos/validation.log`
- First-boot marker: `/var/lib/hyperos/firstboot-validation.done`
