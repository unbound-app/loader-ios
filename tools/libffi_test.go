package main

import (
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"
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

func TestLibFFIMakeDoesNotRerunConfigureOnCoarseTimestampFilesystems(t *testing.T) {
	args := libFFIMakeArgs()
	if !slices.Contains(args, "-o") || !slices.Contains(args, "config.status") || slices.Contains(args, "-C") {
		t.Fatal("libffi make must not rerun config.status after placeholders are cleared")
	}
}

func TestLibFFIBuildLockSerializesConcurrentBuilds(t *testing.T) {
	lockPath := filepath.Join(t.TempDir(), "libffi-build.lock")
	releaseFirst, err := acquireLibFFIBuildLock(lockPath)
	if err != nil {
		t.Fatal(err)
	}

	type lockResult struct {
		release func()
		err     error
	}
	secondResult := make(chan lockResult, 1)
	started := make(chan struct{})
	go func() {
		close(started)
		release, err := acquireLibFFIBuildLock(lockPath)
		secondResult <- lockResult{release: release, err: err}
	}()
	<-started

	select {
	case result := <-secondResult:
		if result.release != nil {
			result.release()
		}
		releaseFirst()
		t.Fatalf("second build acquired the lock before the first released it: %v", result.err)
	case <-time.After(200 * time.Millisecond):
	}

	releaseFirst()
	select {
	case result := <-secondResult:
		if result.err != nil {
			t.Fatal(result.err)
		}
		result.release()
	case <-time.After(2 * time.Second):
		t.Fatal("second build did not acquire the lock after it was released")
	}
}
