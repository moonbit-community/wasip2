run target=("debug"): (build target)
    wasmtime run -S http=y -S p3=y -W component-model=y -W component-model-async=y target/cli.wasm

build target=("debug"):
    @echo 'Building targeting {{ target }}'
    moon build --target wasm --{{ target }}
    wasm-tools component embed --encoding utf16 wit target/wasm/{{ target }}/build/gen/gen.wasm -o target/cli.core.wasm
    wasm-tools component new target/cli.core.wasm -o target/cli.wasm

regenerate:
    @echo 'Regenerating bindings'
    wkg wit fetch
    wit-bindgen moonbit wit --derive-eq --derive-show --derive-error
    rm -r world
    moon fmt
    moon info

clean:
    @echo 'Cleaning project'
    moon clean