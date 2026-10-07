module github.com/mparrett/let-go-wasmgc/host/wazero

go 1.25.0

require github.com/tetratelabs/wazero v1.12.0

require golang.org/x/sys v0.44.0 // indirect

replace github.com/tetratelabs/wazero => github.com/nooga/wazero v1.12.1-0.20261006144638-ea5288e57679
