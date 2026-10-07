module github.com/mparrett/let-go-wasmgc/host/wazero

go 1.25.0

require github.com/tetratelabs/wazero v1.12.0

require golang.org/x/sys v0.44.0 // indirect

replace github.com/tetratelabs/wazero => github.com/mparrett/wazero v1.12.1-0.20261007203338-5993dc27a3c4
