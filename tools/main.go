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
	case "attest":
		return runAttest(args[1:])
	case "build":
		return runBuild(args[1:])
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
	fmt.Println("usage: go run ./tools <build|fetch|attest|doctor>")
	fmt.Println("       go run ./tools build <tweak|ipa|simulator|all> [flags]")
	fmt.Println("       go run ./tools attest <enabled|stage|sign|verify> [flags]")
}

func requireArgs(args []string, count int, usage string) error {
	if len(args) < count {
		return errors.New(usage)
	}
	return nil
}
