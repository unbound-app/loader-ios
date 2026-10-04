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
		"native.fabric.mount",
		"native.debug.evaluations",
		"native.debug.environment",
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
		"dispatchBoolObjectObjectHook",
		"dispatchObjectCGRectHook",
		"dispatchCGSizeNoArgumentHook",
		"dispatchVoidObjectHook",
		"dispatchVoidNSUIntegerHook",
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
	if !strings.Contains(sourceText, `signature.arguments[2].name == "u64"`) {
		t.Fatal("native unsigned 64-bit argument hooks do not have a precompiled fallback")
	}
	if !strings.Contains(sourceText, "class NativeDataBuffer") ||
		!strings.Contains(sourceText, "[value isKindOfClass:[NSData class]]") {
		t.Fatal("native Objective-C data results are not converted to JavaScript byte arrays")
	}
	if !strings.Contains(sourceText, "static Value objcHandleResult(Runtime &runtime, id value)") ||
		!strings.Contains(sourceText, "return objcHandleResult(rt, [[cls alloc] init]);") {
		t.Fatal("native Objective-C allocation does not always return a native handle")
	}
	dataHandler := strings.Index(sourceText, `objc.setProperty(runtime, "data", makeFunction(`)
	if dataHandler < 0 {
		t.Fatal("native Objective-C data constructor is missing")
	}
	dataHandlerEnd := strings.Index(sourceText[dataHandler:], `objc.setProperty(runtime, "hook",`)
	if dataHandlerEnd < 0 ||
		!strings.Contains(sourceText[dataHandler:dataHandler+dataHandlerEnd], "return objcHandleResult(rt, data);") {
		t.Fatal("native Objective-C data constructor does not return an NSData handle")
	}
	if !strings.Contains(sourceText, "NATIVE_BRIDGE_ERROR") ||
		!strings.Contains(sourceText, "attachNativeErrorCode") {
		t.Fatal("native bridge exceptions are missing structured error codes")
	}
	rawFunctionHandler := strings.Index(sourceText, "Value (*handler)(Runtime &, const Value *, size_t)")
	if rawFunctionHandler < 0 ||
		!strings.Contains(sourceText[rawFunctionHandler:], "return makeFunction(name, argCount, runtime, wrappedHandler);") {
		t.Fatal("raw native bridge handlers bypass structured error wrapping")
	}
	if !strings.Contains(sourceText, `signature.result.name == "object" && signature.arguments.size() == 3`) {
		t.Fatal("native object-return hooks do not have a precompiled fallback")
	}
	if !strings.Contains(sourceText, `signature.result.name == "bool" || signature.result.name == "i8"`) ||
		!strings.Contains(sourceText, `signature.arguments.size() == 4`) {
		t.Fatal("native boolean hooks with two object arguments do not have a precompiled fallback")
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
	for _, installation := range []string{
		`bridge.setProperty(runtime, "debug", std::move(debug));`,
		`makeFunction("recordEvaluation", 1, runtime, recordEvaluation)`,
		`makeFunction("environment", 0, runtime, environment)`,
	} {
		if !strings.Contains(sourceText, installation) {
			t.Fatalf("native debug function %q is not installed on the bridge", installation)
		}
	}
	recordHandler := strings.Index(sourceText, "static Value recordEvaluation(Runtime &runtime")
	if recordHandler < 0 {
		t.Fatal("native evaluation record handler is missing")
	}
	recordHandlerEnd := strings.Index(sourceText[recordHandler:], "static Value environment(")
	if recordHandlerEnd < 0 ||
		!strings.Contains(sourceText[recordHandler:recordHandler+recordHandlerEnd], "catch (...)") ||
		!strings.Contains(sourceText[recordHandler:recordHandler+recordHandlerEnd], "return Value(false);") {
		t.Fatal("native evaluation records can throw into JavaScript on bad input")
	}
}
