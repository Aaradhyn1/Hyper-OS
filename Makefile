.PHONY: help build clean

help:
	@echo "Targets:"
	@echo "  make build  Build Hyper OS v0.1 ISO via ./build.sh"
	@echo "  make clean  Remove build artifacts and output ISO"

build:
	./build.sh

clean:
	rm -rf build rootfs iso hyperos.iso
