package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return
		}
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) == 0 {
		printUsage()
		return nil
	}
	switch args[0] {
	case "fetch":
		return runFetch(args[1:])
	case "ipa-info":
		return runIPAInfo(args[1:])
	case "attest":
		return runAttest(args[1:])
	case "build":
		return runBuild(args[1:])
	case "platform":
		return runPlatform(args[1:])
	case "validate":
		return runValidate(args[1:])
	case "deps":
		return runDependencies(args[1:])
	case "packages":
		return runPackages(args[1:])
	case "libffi-build":
		return runLibFFIBuild(args[1:])
	case "doctor":
		return runDoctor(args[1:])
	case "version":
		fmt.Println("tools dev")
		return nil
	case "help", "-h", "--help":
		printUsage()
		return nil
	default:
		return fmt.Errorf("unknown command %q", args[0])
	}
}

func printUsage() {
	fmt.Println("usage: go run ./tools <build|platform|validate|deps|packages|libffi-build|fetch|ipa-info|attest|doctor>")
	fmt.Println("       go run ./tools build <tweak|ipa|simulator|all> [flags]")
	fmt.Println("       go run ./tools platform <build|test> <ios|android> [flags]")
	fmt.Println("       go run ./tools validate [--root <path>]")
	fmt.Println("       go run ./tools deps [--root <path>]")
	fmt.Println("       go run ./tools packages <list|validate> [--root <path>]")
	fmt.Println("       go run ./tools libffi-build --archive <path> --include <path>")
	fmt.Println("       go run ./tools ipa-info --ipa <path>")
	fmt.Println("       go run ./tools attest <enabled|stage|sign|verify> [flags]")
}

func requireArgs(args []string, count int, usage string) error {
	if len(args) < count {
		return errors.New(usage)
	}
	return nil
}
