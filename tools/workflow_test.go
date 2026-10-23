package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
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
	workflow, err := os.ReadFile(filepath.Join(root, ".github", "workflows", "ios.yml"))
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
	workflow, err := os.ReadFile(filepath.Join(root, ".github", "workflows", "ios.yml"))
	if err != nil {
		t.Fatal(err)
	}
	contents := string(workflow)
	for _, required := range []string{
		"for architecture in arm64 arm64e; do",
		"test -f \"$binary\"",
		"test -d \"$bundle\"",
		"dwarfdump --uuid \"$binary\"",
		"dwarfdump --uuid \"$bundle\"",
		"test \"$binary_uuid\" = \"$symbols_uuid\"",
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

func TestBuildWorkflowCoordinatesBothPlatforms(t *testing.T) {
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
		"uses: ./.github/workflows/android.yml",
		"uses: ./.github/workflows/ios.yml",
		"needs: resolve-source",
		"needs: [resolve-source, ios, android]",
		"ios_version: ${{ needs.resolve-source.outputs.version }}",
		"secrets: inherit",
		"value: ${{ jobs.android.outputs.module_filename }}",
		"value: ${{ jobs.android.outputs.patched_filename }}",
		"name: ios-simulator",
		"name: publish unified release",
	} {
		if !strings.Contains(contents, required) {
			t.Fatalf("build workflow is missing platform orchestration detail %q", required)
		}
	}
	androidStart := strings.Index(contents, "  android:\n")
	iosStart := strings.Index(contents, "  ios:\n")
	if androidStart < 0 || iosStart < 0 {
		t.Fatal("platform workflow calls could not be located")
	}
	androidJob := contents[androidStart:iosStart]
	if strings.Contains(androidJob, "needs: [resolve-source, ios]") || strings.Contains(androidJob, "needs: ios") {
		t.Fatal("Android and iOS builds must run in parallel after source resolution")
	}
	android, err := os.ReadFile(filepath.Join(root, ".github", "workflows", "android.yml"))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(android), "    push:") {
		t.Fatal("Android should be built through the cross-platform coordinator on push")
	}
	for _, required := range []string{
		"name=\"app.unbound.android.lsposed.apk\"",
		`if [[ "$IOS_VERSION" =~ ^([0-9]+)\.([0-9]+)(\.|_|$) ]]; then`,
		"candidate=\"${BASH_REMATCH[1]}$(printf '%03d' \"${BASH_REMATCH[2]}\")\"",
		"version=\"${version:-$latest_version}\"",
		"Unbound-Discord-${{ steps.discord.outputs.version }}.apks",
	} {
		if !strings.Contains(string(android), required) {
			t.Fatalf("Android workflow is missing matching version or artifact detail %q", required)
		}
	}
	remoteDeploy, err := os.ReadFile(filepath.Join(root, ".github", "workflows", "remote-deploy.yml"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(remoteDeploy), "release: true") {
		t.Fatal("dkrypt-scheduled builds must publish the combined iOS and Android release")
	}
}

func TestObtainiumConfigTracksTheRootedAndroidModule(t *testing.T) {
	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("could not locate test source")
	}
	root := filepath.Dir(filepath.Dir(filename))
	configBytes, err := os.ReadFile(filepath.Join(root, "obtainium.json"))
	if err != nil {
		t.Fatal(err)
	}
	var config struct {
		ID                 string `json:"id"`
		URL                string `json:"url"`
		AdditionalSettings string `json:"additionalSettings"`
	}
	if err := json.Unmarshal(configBytes, &config); err != nil {
		t.Fatal(err)
	}
	if config.ID != "app.unbound.android" || config.URL != "https://github.com/unbound-app/loader" {
		t.Fatalf("Obtainium config targets an unexpected app: %#v", config)
	}
	var settings struct {
		APKFilterRegEx string `json:"apkFilterRegEx"`
	}
	if err := json.Unmarshal([]byte(config.AdditionalSettings), &settings); err != nil {
		t.Fatal(err)
	}
	matches, err := regexp.MatchString(settings.APKFilterRegEx, "app.unbound.android.lsposed.apk")
	if err != nil {
		t.Fatal(err)
	}
	if !matches {
		t.Fatalf("Obtainium APK filter does not select the release module: %q", settings.APKFilterRegEx)
	}
	androidWorkflow, err := os.ReadFile(filepath.Join(root, ".github", "workflows", "android.yml"))
	if err != nil {
		t.Fatal(err)
	}
	for _, required := range []string{
		"name=\"app.unbound.android.lsposed.apk\"",
		"ANDROID_SIGNING_KEYSTORE_BASE64",
		"ANDROID_SIGNING_STORE_PASSWORD",
		"ANDROID_SIGNING_KEY_ALIAS",
		"ANDROID_SIGNING_KEY_PASSWORD",
		"Android release signing secrets are required for Obtainium-compatible updates",
	} {
		if !strings.Contains(string(androidWorkflow), required) {
			t.Fatalf("Android release workflow is missing Obtainium update support %q", required)
		}
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
