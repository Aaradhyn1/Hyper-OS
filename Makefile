.PHONY: help build build-hyperos-iso clean

help:
	@echo "Targets:"
	@echo "  make build              Build Hyper OS v0.1 Debian minimal ISO (x86_64, GRUB BIOS, systemd)"
	@echo "  make build-hyperos-iso  Same as 'make build'"
	@echo "  make clean              Remove build artifacts (build/, rootfs/, iso/)"

build: build-hyperos-iso

build-hyperos-iso:
	./scripts/build-hyperos-iso.sh

clean:
	rm -rf build rootfs iso hyperos.iso
