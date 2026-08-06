.PHONY: build build-native deps gen analyze test test-live run clean

SDK_ROOT := $(shell cd ../.. && pwd)
export ZERODEV_SDK_ROOT := $(SDK_ROOT)

# Build the native Zig library (ReleaseFast)
build-native:
	cd ../.. && zig build -Doptimize=ReleaseFast

# Resolve pub dependencies
deps:
	dart pub get

# Regenerate the FFI bindings from ../../include/aa.h (needs libclang)
gen: deps
	dart run ffigen

# Static analysis
analyze: deps
	dart analyze

# Build native lib, resolve deps, and analyze
build: build-native deps analyze

# Run the offline unit tests
test: build-native deps
	dart test

# Run the live E2E test against ZeroDev Sepolia
test-live: build-native deps
	dart test --tags live

# Run the example
run: build-native deps
	dart run example/zerodev_aa_example.dart

# Clean
clean:
	rm -rf .dart_tool
