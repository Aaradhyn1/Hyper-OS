# Hyper OS Authenticity and Integrity

## Verify ISO checksum
```bash
sha256sum -c hyperos-<version>.iso.sha256
```

## Verify local system state
```bash
hyperos-check.sh
```

## Validate cloud profile updates
```bash
sudo systemctl start hyperos-profile-update.service
sudo journalctl -u hyperos-profile-update.service -n 50 --no-pager
```
