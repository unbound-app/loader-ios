package main

import (
	"slices"
	"testing"
)

func TestLibFFIConfigureDisablesGCCMultiOSDirectory(t *testing.T) {
	args := libFFIConfigureArgs("arm64")
	if !slices.Contains(args, "--disable-multi-os-directory") {
		t.Fatal("libffi configure must disable the GCC-only multi-os-directory probe")
	}
}
