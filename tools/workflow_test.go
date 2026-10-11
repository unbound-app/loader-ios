package main

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestBuildWorkflowInstallsAutotoolsBeforeTweakBuild(t *testing.T) {
	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("could not locate test source")
	}
	root := filepath.Dir(filepath.Dir(filename))
	workflow, err := os.ReadFile(filepath.Join(root, ".github", "workflows", "build.yml"))
	if err != nil {
		t.Fatal(err)
	}
	buildTweakStart := strings.Index(string(workflow), "  build-tweak:\n")
	resolveSourceStart := strings.Index(string(workflow), "  resolve-source-ipa:\n")
	if buildTweakStart < 0 || resolveSourceStart <= buildTweakStart {
		t.Fatal("build-tweak job could not be located")
	}
	buildTweak := string(workflow[buildTweakStart:resolveSourceStart])
	installAutotools := strings.Index(buildTweak, "- name: install Autotools")
	verifyAutotools := strings.Index(buildTweak, "- name: verify Autotools")
	buildPackage := strings.Index(buildTweak, "- name: build package")
	if installAutotools < 0 || verifyAutotools <= installAutotools || buildPackage <= verifyAutotools {
		t.Fatal("the tweak build must install and verify Autotools before building the package")
	}
	installStep := buildTweak[installAutotools:verifyAutotools]
	for _, prerequisite := range []string{
		"brew install autoconf automake libtool",
		"brew --prefix autoconf",
		"brew --prefix automake",
		"brew --prefix libtool",
	} {
		if !strings.Contains(installStep, prerequisite) {
			t.Fatalf("Autotools installation is missing %q", prerequisite)
		}
	}
	verifyStep := buildTweak[verifyAutotools:buildPackage]
	for _, tool := range []string{"autoreconf", "automake", "aclocal", "glibtoolize"} {
		if !strings.Contains(verifyStep, "command -v "+tool) {
			t.Fatalf("Autotools verification is missing %q", tool)
		}
	}
}

func TestBuildWorkflowArchivesMatchingTweakSymbols(t *testing.T) {
	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("could not locate test source")
	}
	root := filepath.Dir(filepath.Dir(filename))
	workflow, err := os.ReadFile(filepath.Join(root, ".github", "workflows", "build.yml"))
	if err != nil {
		t.Fatal(err)
	}
	contents := string(workflow)
	for _, required := range []string{
		"find .theos/obj -type d -name 'Unbound.dylib.dSYM'",
		"dwarfdump --uuid \"$bundle\" >> symbols/uuids.txt",
		"git rev-parse HEAD > symbols/commit.txt",
		"name: tweak symbols",
		"path: symbols/",
	} {
		if !strings.Contains(contents, required) {
			t.Fatalf("build workflow is missing symbol metadata %q", required)
		}
	}
}

func TestBuildWorkflowAllowsManualIPAInput(t *testing.T) {
	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("could not locate test source")
	}
	root := filepath.Dir(filepath.Dir(filename))
	workflow, err := os.ReadFile(filepath.Join(root, ".github", "workflows", "build.yml"))
	if err != nil {
		t.Fatal(err)
	}
	contents := string(workflow)
	dispatchStart := strings.Index(contents, "  workflow_dispatch:\n")
	workflowCallStart := strings.Index(contents, "  workflow_call:\n")
	if dispatchStart < 0 || workflowCallStart <= dispatchStart {
		t.Fatal("workflow_dispatch input section could not be located")
	}
	dispatchInputs := contents[dispatchStart:workflowCallStart]
	if !strings.Contains(dispatchInputs, "      ipa_url:\n") {
		t.Fatal("manual builds must accept an IPA URL to avoid triggering a device decrypt")
	}
	if strings.Contains(contents, "--extensions") {
		t.Fatal("build workflow must not choose whether to include extensions")
	}
}

func TestPullRequestWorkflowUsesPinnedCleanDiscordIPA(t *testing.T) {
	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("could not locate test source")
	}
	root := filepath.Dir(filepath.Dir(filename))
	workflow, err := os.ReadFile(filepath.Join(root, ".github", "workflows", "ci.yml"))
	if err != nil {
		t.Fatal(err)
	}
	contents := string(workflow)
	for _, required := range []string{
		"https://raw.githubusercontent.com/Tulugaak/Discord-205.0-IPA/4eec98e61e20d0720c091d42c4a762710b32e8c5/com.hammerandchisel.discord_861573261.ipa",
		"release: false",
	} {
		if !strings.Contains(contents, required) {
			t.Fatalf("pull request workflow is missing %q", required)
		}
	}
	for _, retired := range []string{"ipa.aspy.dev", "files.catbox.moe/pk80qh.ipa"} {
		if strings.Contains(contents, retired) {
			t.Fatalf("pull request workflow still references retired IPA source %q", retired)
		}
	}
}

func TestPullRequestWorkflowChecksPinnedSupportedDiscordFixtures(t *testing.T) {
	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("could not locate test source")
	}
	root := filepath.Dir(filepath.Dir(filename))
	workflow, err := os.ReadFile(filepath.Join(root, ".github", "workflows", "ci.yml"))
	if err != nil {
		t.Fatal(err)
	}
	contents := string(workflow)
	for _, required := range []string{
		"version: ['347.0', '341.0']",
		"name: rootless package",
		"--bundle-id com.hammerandchisel.discord",
		"--version \"$DISCORD_VERSION\"",
		"needs.compatibility-source.outputs.available == 'true'",
		"link/package checks, not Discord device-runtime validation",
	} {
		if !strings.Contains(contents, required) {
			t.Fatalf("pull request workflow is missing compatibility check %q", required)
		}
	}
	if strings.Contains(contents, "--extensions") {
		t.Fatal("pull request workflow must not choose whether to include extensions")
	}
}

func TestDependabotAutomergeWaitsForSuccessfulBuild(t *testing.T) {
	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("could not locate test source")
	}
	root := filepath.Dir(filepath.Dir(filename))
	workflow, err := os.ReadFile(filepath.Join(root, ".github", "workflows", "dependabot-automerge.yml"))
	if err != nil {
		t.Fatal(err)
	}
	contents := string(workflow)
	for _, required := range []string{
		"name: Auto-merge Dependabot",
		"- Pull Request Build",
		"if: github.event.workflow_run.conclusion == 'success'",
		"pull-requests: write",
		"contents: write",
		"dependabot[bot]",
		".head.sha",
		".head_sha",
		"gh pr merge \"$PR_NUMBER\" --auto --squash",
	} {
		if !strings.Contains(contents, required) {
			t.Fatalf("Dependabot auto-merge workflow is missing %q", required)
		}
	}
	if strings.Contains(contents, "actions/checkout") {
		t.Fatal("Dependabot auto-merge workflow must not check out pull request code")
	}
}
