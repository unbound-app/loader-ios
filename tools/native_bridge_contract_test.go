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
		"dispatchObjectObjectHook",
		"dispatchObjectCGRectHook",
		"dispatchCGSizeNoArgumentHook",
		"dispatchVoidObjectHook",
		"dispatchVoidObjectObjectHook",
		"replaceObjectArgument",
		"instanceTarget",
		"isExecutableAddress",
		"invokeHookOriginal",
		"prepareFFICif",
		"valueToData",
		"structResult",
		"objc_setAssociatedObject",
		"BigInt::fromInt64",
		"BigInt::fromUint64",
	} {
		if !strings.Contains(sourceText, symbol) {
			t.Fatalf("native hook symbol %q is missing from the loader", symbol)
		}
	}
	if !strings.Contains(sourceText, "Native hook closure is unavailable on this device") {
		t.Fatal("native hook closure fail-closed diagnostic is missing from the loader")
	}
	if !strings.Contains(sourceText, `signature.result.name == "object" && signature.arguments.size() == 3`) {
		t.Fatal("native object-return hooks do not have a precompiled fallback")
	}
	if !strings.Contains(sourceText, `signature.arguments[2].name == "struct:CGRect"`) {
		t.Fatal("native object-return CGRect hooks do not have a precompiled fallback")
	}
	rectEncoding := strings.Index(sourceText, `if (value.find("CGRect")`)
	pointEncoding := strings.Index(sourceText, `if (value.find("CGPoint")`)
	if rectEncoding < 0 || pointEncoding < 0 || rectEncoding > pointEncoding {
		t.Fatal("native type parsing must recognize CGRect before its nested CGPoint encoding")
	}
	if !strings.Contains(sourceText, `signature.result.name != "struct:CGSize"`) ||
		!strings.Contains(sourceText, `signature.arguments.size() == 2`) {
		t.Fatal("native no-argument CGSize hooks do not have a precompiled fallback")
	}
	if !strings.Contains(sourceText, "Native hook original() cannot cross runtime threads") {
		t.Fatal("native hook original thread safety diagnostic is missing from the loader")
	}
	if strings.Contains(sourceText, "originalRequested") {
		t.Fatal("native hook original invocation still uses deferred return semantics")
	}
	if !strings.Contains(sourceText, "state->instanceTarget == object") {
		t.Fatal("native hook instance targets are not filtered before JavaScript dispatch")
	}
	if !strings.Contains(sourceText, "method_getImplementation(method) == dispatcher->original") {
		t.Fatal("native hook dispatchers are not restored when their original IMP is current")
	}
	if strings.Contains(sourceText, "method_setImplementation") {
		t.Fatal("native hook dispatchers bypass the shared hook framework")
	}
	if !strings.Contains(sourceText, "MSHookMessageEx(cls, selector, (IMP) dispatcher->code, &dispatcher->original)") {
		t.Fatal("native hook dispatchers are not installed through the shared hook framework")
	}
	if !strings.Contains(sourceText, "MSHookMessageEx(dispatcher->cls, dispatcher->selector,") {
		t.Fatal("native hook dispatchers are not restored through the shared hook framework")
	}
	if !strings.Contains(sourceText, "current == (IMP) dispatcher->code || current == dispatcher->original") {
		t.Fatal("native hook dispatchers are not retained while external IMPs may chain through them")
	}
	registration := strings.Index(sourceText, "dispatcher = iterator->second;")
	if registration < 0 {
		t.Fatal("native hook registration branch is missing")
	}
	registrationEnd := strings.Index(sourceText[registration:], "auto state = std::make_shared<HookState>();")
	if registrationEnd < 0 {
		t.Fatal("native hook registration branch is missing")
	}
	if strings.Contains(sourceText[registration:registration+registrationEnd], "dispatcher->original = method_getImplementation(method)") {
		t.Fatal("native hook registration can wrap an external IMP that already chains through its dispatcher")
	}
	if !strings.Contains(sourceText, "gFFICifs") {
		t.Fatal("native FFI call interface cache is missing from the loader")
	}
}
