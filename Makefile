.PHONY: help build build-fedora-kde-x86_64 build-buildroot clean

help:
	@echo "Targets:"
	@echo "  make build                     Build Hyper-OS (Fedora KDE Plasma x86_64)"
	@echo "  make build-fedora-kde-x86_64  Same as 'make build'"
	@echo "  make build-buildroot          Legacy Buildroot profile build"
	@echo "  make clean                    Remove build output"

build: build-fedora-kde-x86_64

build-fedora-kde-x86_64:
	./scripts/build-fedora-kde.sh

build-buildroot:
	./scripts/build.sh

clean:
	rm -rf out
