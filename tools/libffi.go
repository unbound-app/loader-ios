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
)

const libFFIPython = `import collections
import runpy
import subprocess

module = runpy.run_path('generate-darwin-source-and-headers.py')
headers = collections.defaultdict(set)
module['copy_files']('src', 'darwin_common/src', pattern='*.c')
module['copy_files']('include', 'darwin_common/include', pattern='*.h')

for arch in ('arm64', 'arm64e'):
    platform = type(f'ios_device_{arch}_platform', (module['ios_device_arm64_platform'],), {})
    platform.arch = arch
    platform.target = f'{arch}-apple-ios'
    platform.directory = f'darwin_ios_{arch}'
    if arch == 'arm64e':
        platform.target = 'arm64-apple-ios'
        platform.version_min = f'{platform.version_min} -arch arm64e'
    module['copy_src_platform_files'](platform)
    module['build_target'](platform, headers)
    subprocess.check_call(['make', '-C', f'build_iphoneos-{arch}', '-j4', 'libffi.la'])
`

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
	if err := runCommand(buildPath, nil, os.Stdout, os.Stderr, "python3", "-c", libFFIPython); err != nil {
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
