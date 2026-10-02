package main

import (
	"os"
	"path/filepath"
	"slices"
	"testing"
)

func TestLibFFIConfigureDisablesGCCMultiOSDirectory(t *testing.T) {
	args := libFFIConfigureArgs("arm64")
	if !slices.Contains(args, "--disable-multi-os-directory") {
		t.Fatal("libffi configure must disable the GCC-only multi-os-directory probe")
	}
}

func TestLibFFIConfigurePlaceholdersAreRemovedBeforeMake(t *testing.T) {
	buildDirectory := t.TempDir()
	placeholderPaths := []string{
		"libffi.la",
		"src/prep_cif.lo",
		"src/aarch64/ffi.lo",
		"src/aarch64/sysv.lo",
	}
	for _, relativePath := range placeholderPaths {
		path := filepath.Join(buildDirectory, relativePath)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, nil, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if err := clearLibFFIConfigurePlaceholders(buildDirectory); err != nil {
		t.Fatal(err)
	}
	for _, relativePath := range placeholderPaths {
		if _, err := os.Stat(filepath.Join(buildDirectory, relativePath)); !os.IsNotExist(err) {
			t.Fatalf("configure placeholder %q still exists", relativePath)
		}
	}
}
