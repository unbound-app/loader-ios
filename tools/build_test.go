package main

import (
	"io"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestProvisionSimforgeUsesBuiltProduct(t *testing.T) {
	root := t.TempDir()
	product := filepath.Join(root, ".tools-cache", "simforge-"+simforgeCommit, "derived-data", "Build", "Products", "Release", "simforge")
	calls := []string{}
	runner := func(work, name string, args []string, env []string, stdout, stderr io.Writer) error {
		calls = append(calls, name)
		if name == "git" && len(args) > 0 && args[0] == "clone" {
			return os.MkdirAll(args[2], 0o755)
		}
		if name == "xcodebuild" {
			if err := os.MkdirAll(filepath.Dir(product), 0o755); err != nil {
				return err
			}
			if err := os.WriteFile(product, []byte("simforge"), 0o644); err != nil {
				return err
			}
			return os.Chmod(product, 0o755)
		}
		return nil
	}

	got, err := provisionSimforge(root, runner)
	if err != nil {
		t.Fatal(err)
	}
	if got != product {
		t.Fatalf("unexpected simforge path: %s", got)
	}
	if !reflect.DeepEqual(calls, []string{"git", "git", "xcodebuild"}) {
		t.Fatalf("unexpected provisioning commands: %#v", calls)
	}
}

func TestZipDirectoryRunsFromPayload(t *testing.T) {
	payload := filepath.Join(t.TempDir(), "Payload")
	output := filepath.Join(t.TempDir(), "simulator.zip")
	var gotRoot string
	var gotName string
	var gotArgs []string
	runner := func(root, name string, args []string, env []string, stdout, stderr io.Writer) error {
		gotRoot = root
		gotName = name
		gotArgs = append([]string(nil), args...)
		return nil
	}

	if err := zipDirectory(payload, output, runner, t.TempDir()); err != nil {
		t.Fatal(err)
	}
	if gotRoot != payload {
		t.Fatalf("unexpected zip working directory: %s", gotRoot)
	}
	if gotName != "zip" {
		t.Fatalf("unexpected zip command: %s", gotName)
	}
	expected := []string{"-q", "-r", output, "Discord.app"}
	if !reflect.DeepEqual(gotArgs, expected) {
		t.Fatalf("unexpected zip arguments: %#v", gotArgs)
	}
}
