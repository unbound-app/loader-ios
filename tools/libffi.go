package main

import (
	"bytes"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func runLibFFIBuild(args []string) error {
	set := flag.NewFlagSet("libffi-build", flag.ContinueOnError)
	root := set.String("root", ".", "repository root")
	archive := set.String("archive", "", "output static archive")
	include := set.String("include", "", "output include directory")
	if err := set.Parse(args); err != nil {
		return err
	}
	if *archive == "" || *include == "" {
		return errors.New("usage: libffi-build --archive <path> --include <path>")
	}
	rootPath, err := filepath.Abs(*root)
	if err != nil {
		return err
	}
	archivePath, err := filepath.Abs(*archive)
	if err != nil {
		return err
	}
	includePath, err := filepath.Abs(*include)
	if err != nil {
		return err
	}
	sourcePath := filepath.Join(rootPath, "vendor", "libffi")
	if _, err := os.Stat(filepath.Join(sourcePath, ".git")); err != nil {
		return fmt.Errorf("libffi submodule is unavailable: %w", err)
	}
	buildPath, err := os.MkdirTemp("", "unbound-libffi-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(buildPath)
	archiveBytes, err := commandOutput(rootPath, "git", "-C", sourcePath, "archive", "--format=tar", "HEAD")
	if err != nil {
		return err
	}
	if err := runCommand(buildPath, bytes.NewReader(archiveBytes), io.Discard, os.Stderr, "tar", "-x", "-C", buildPath); err != nil {
		return err
	}
	if err := runCommand(buildPath, nil, os.Stdout, os.Stderr, "autoreconf", "-i", "-f", "-v"); err != nil {
		return err
	}
	buildMachine, err := commandOutput(buildPath, "uname", "-m")
	if err != nil {
		return err
	}
	for _, arch := range []string{"arm64", "arm64e"} {
		if err := buildLibFFIArch(buildPath, strings.TrimSpace(string(buildMachine)), arch); err != nil {
			return err
		}
	}
	if err := os.MkdirAll(filepath.Join(buildPath, "include"), 0o755); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(archivePath), 0o755); err != nil {
		return err
	}
	if err := os.MkdirAll(includePath, 0o755); err != nil {
		return err
	}
	arm64Archive := filepath.Join(buildPath, "build_iphoneos-arm64", ".libs", "libffi.a")
	arm64eArchive := filepath.Join(buildPath, "build_iphoneos-arm64e", ".libs", "libffi.a")
	if err := runCommand(buildPath, nil, os.Stdout, os.Stderr, "xcrun", "lipo", "-create", arm64Archive, arm64eArchive, "-output", archivePath); err != nil {
		return err
	}
	for _, name := range []string{"ffi.h", "ffitarget.h", "fficonfig.h"} {
		source := filepath.Join(buildPath, "build_iphoneos-arm64", "include", name)
		if name == "fficonfig.h" {
			source = filepath.Join(buildPath, "build_iphoneos-arm64", name)
		}
		if err := copyFile(source, filepath.Join(includePath, name)); err != nil {
			return err
		}
	}
	return nil
}

func buildLibFFIArch(root, buildMachine, arch string) error {
	buildDirectory := filepath.Join(root, "build_iphoneos-"+arch)
	if err := os.MkdirAll(buildDirectory, 0o755); err != nil {
		return err
	}
	configure := exec.Command("../configure", "--host=arm64-apple-ios", "--build="+buildMachine+"-apple-darwin")
	configure.Dir = buildDirectory
	configure.Env = append(os.Environ(),
		"CC=xcrun -sdk iphoneos clang -target arm64-apple-ios",
		"LD=xcrun -sdk iphoneos ld -target arm64-apple-ios",
		"CFLAGS=-miphoneos-version-min=7.0 -fembed-bitcode -arch "+arch,
	)
	configure.Stdout = os.Stdout
	configure.Stderr = os.Stderr
	if err := configure.Run(); err != nil {
		return fmt.Errorf("configure %s failed: %w", arch, err)
	}
	return runCommand(root, nil, os.Stdout, os.Stderr, "make", "-C", buildDirectory, "-j4", "libffi.la")
}

func commandOutput(dir, name string, args ...string) ([]byte, error) {
	command := exec.Command(name, args...)
	command.Dir = dir
	output, err := command.Output()
	if err != nil {
		return nil, fmt.Errorf("%s failed: %w", name, err)
	}
	return output, nil
}

func runCommand(dir string, stdin io.Reader, stdout, stderr io.Writer, name string, args ...string) error {
	command := exec.Command(name, args...)
	command.Dir = dir
	command.Stdin = stdin
	command.Stdout = stdout
	command.Stderr = stderr
	if err := command.Run(); err != nil {
		return fmt.Errorf("%s failed: %w", name, err)
	}
	return nil
}

func copyFile(source, destination string) error {
	input, err := os.Open(source)
	if err != nil {
		return err
	}
	defer input.Close()
	output, err := os.Create(destination)
	if err != nil {
		return err
	}
	if _, err := io.Copy(output, input); err != nil {
		output.Close()
		return err
	}
	return output.Close()
}
