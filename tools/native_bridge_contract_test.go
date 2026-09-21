package main

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestNativeBridgeContractIsSynchronized(t *testing.T) {
	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("could not locate test source")
	}
	root := filepath.Dir(filepath.Dir(filename))
	header, err := os.ReadFile(filepath.Join(root, "headers", "NativePluginBridge.h"))
	if err != nil {
		t.Fatal(err)
	}
	source, err := os.ReadFile(filepath.Join(root, "sources", "NativePluginBridge.mm"))
	if err != nil {
		t.Fatal(err)
	}
	headerText := string(header)
	sourceText := string(source)
	if !strings.Contains(headerText, `kNativePluginApiVersion = "1.0.0"`) {
		t.Fatal("native plugin API version is not v1")
	}
	if !strings.Contains(headerText, `kNativePluginAbiVersion = "1.0.0"`) {
		t.Fatal("native plugin ABI version is not v1")
	}
	for _, capability := range []string{
		"native.objc.classes",
		"native.objc.invoke",
		"native.objc.ivars",
		"native.objc.associations",
		"native.objc.hooks",
		"native.ffi.symbols",
		"native.ffi.call",
	} {
		if !strings.Contains(sourceText, `"`+capability+`"`) {
			t.Fatalf("native capability %q is missing from the loader", capability)
		}
	}
	for _, symbol := range []string{
		"ffi_closure_alloc",
		"ffi_prep_closure_loc",
		"dispatchFFIHook",
		"dispatchVoidHook",
		"isExecutableAddress",
		"invokeHookOriginal",
	} {
		if !strings.Contains(sourceText, symbol) {
			t.Fatalf("native hook symbol %q is missing from the loader", symbol)
		}
	}
	if !strings.Contains(sourceText, "Native hook closure is unavailable on this device") {
		t.Fatal("native hook closure fail-closed diagnostic is missing from the loader")
	}
}
