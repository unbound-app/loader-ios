package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"
)

func TestNativeTypeEncodingsOnHost(t *testing.T) {
	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("could not locate test source")
	}
	root := filepath.Dir(filepath.Dir(filename))
	variants := [][]string{{}}
	if runtime.GOOS == "darwin" {
		variants = append(variants, []string{"-fsanitize=address,undefined"})
	}
	for index, flags := range variants {
		binary := filepath.Join(t.TempDir(), "native-type-encoding-test")
		arguments := append([]string{"-std=c++20"}, flags...)
		arguments = append(arguments, "-I"+filepath.Join(root, "headers"), filepath.Join(root, "sources", "NativeTypeEncoding.cpp"), filepath.Join(root, "tests", "native_type_encoding.cpp"), "-o", binary)
		compile := exec.Command("c++", arguments...)
		if output, err := compile.CombinedOutput(); err != nil {
			t.Fatalf("native type test compilation failed for variant %d: %v\n%s", index, err, output)
		}
		run := exec.Command(binary)
		run.Env = os.Environ()
		if output, err := run.CombinedOutput(); err != nil {
			t.Fatalf("native type test failed for variant %d: %v\n%s", index, err, output)
		}
	}
}

func TestNativeNumericValidationOnHost(t *testing.T) {
	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("could not locate test source")
	}
	root := filepath.Dir(filepath.Dir(filename))
	variants := [][]string{{}}
	if runtime.GOOS == "darwin" {
		variants = append(variants, []string{"-fsanitize=address,undefined"})
	}
	for index, flags := range variants {
		binary := filepath.Join(t.TempDir(), "native-numeric-validation-test")
		arguments := append([]string{"-std=c++20"}, flags...)
		arguments = append(arguments, "-I"+filepath.Join(root, "headers"), filepath.Join(root, "sources", "NativeNumericValidation.cpp"), filepath.Join(root, "tests", "native_numeric_validation.cpp"), "-o", binary)
		compile := exec.Command("c++", arguments...)
		if output, err := compile.CombinedOutput(); err != nil {
			t.Fatalf("native numeric test compilation failed for variant %d: %v\n%s", index, err, output)
		}
		run := exec.Command(binary)
		run.Env = os.Environ()
		if output, err := run.CombinedOutput(); err != nil {
			t.Fatalf("native numeric test failed for variant %d: %v\n%s", index, err, output)
		}
	}
}
