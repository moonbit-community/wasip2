# WASI Preview 2 bindings for MoonBit

## ABI compatibility

This package uses generated inline wasm helpers to pass MoonBit strings, bytes,
and arrays across component-model ABI boundaries. MoonBit changed the ABI layout
for these values so the data pointer no longer needs the old 8-byte offset.
This is a breaking change for generated bindings that use inline wasm, but it is
not something the MoonBit compiler can detect at the type level.

Use this package with a MoonBit toolchain that has the updated ABI layout, and
regenerate dependent bindings with a matching `wit-bindgen moonbit` version. If
old generated bindings or an older toolchain are mixed with this package,
programs may still compile but fail at runtime with corrupted strings/bytes or
traps.
