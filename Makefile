.PHONY: help build clean

help:
	@echo "Targets:"
	@echo "  make build    Build Hyper-OS image using Buildroot"
	@echo "  make clean    Remove build output"

build:
	./scripts/build.sh

clean:
	rm -rf out
