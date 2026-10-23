package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

func TestPublishLoaderReleaseSendsScopedRequest(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.Method == http.MethodGet {
			if request.URL.Path != "/api/v1/loader/updates" || request.URL.Query().Get("platform") != "ios" || request.URL.Query().Get("version") != "0.0.0" {
				t.Fatalf("unexpected latest loader request: %s %s", request.Method, request.URL.String())
			}
			fmt.Fprint(writer, `{"update":{"version":"1.0.0"}}`)
			return
		}
		if request.Method != http.MethodPost || request.URL.Path != "/api/v1/loader/releases" {
			t.Fatalf("unexpected loader release request: %s %s", request.Method, request.URL.Path)
		}
		if request.Header.Get("X-API-Key") != "ci-key" {
			t.Fatal("loader release request omitted its API key")
		}
		if request.Header.Get("Content-Type") != "application/json" {
			t.Fatal("loader release request omitted its JSON content type")
		}
		var body loaderReleasePublishRequest
		if err := json.NewDecoder(request.Body).Decode(&body); err != nil {
			t.Fatal(err)
		}
		if body.Platform != "ios" || body.Version != "1.0.1" || body.URL != "https://github.com/unbound-app/loader/releases/download/v352.0/Unbound.deb" {
			t.Fatalf("unexpected loader release body: %#v", body)
		}
		if body.Changelog == nil || *body.Changelog != "Added native bridge validation." {
			t.Fatalf("unexpected changelog: %#v", body.Changelog)
		}
		fmt.Fprint(writer, `{"platform":"ios","version":"1.0.1","url":"https://github.com/unbound-app/loader/releases/download/v352.0/Unbound.deb"}`)
	}))
	defer server.Close()

	published, err := publishLoaderRelease(context.Background(), loaderReleasePublishConfig{
		endpoint:  server.URL + "/api/v1/loader/releases",
		apiKey:    "ci-key",
		platform:  "ios",
		version:   "1.0.1",
		url:       "https://github.com/unbound-app/loader/releases/download/v352.0/Unbound.deb",
		changelog: "Added native bridge validation.",
	})
	if err != nil || !published {
		t.Fatalf("publish result = %t, error = %v", published, err)
	}
}

func TestPublishLoaderReleaseSkipsEqualSemverAndRejectsOlderSemver(t *testing.T) {
	for _, test := range []struct {
		name          string
		version       string
		latestVersion string
		wantPublished bool
		wantError     bool
	}{
		{name: "equal", version: "1.0.1", latestVersion: "1.0.1"},
		{name: "older", version: "1.0.0", latestVersion: "1.0.1", wantError: true},
		{name: "newer", version: "1.0.2", latestVersion: "1.0.1", wantPublished: true},
	} {
		t.Run(test.name, func(t *testing.T) {
			postCount := 0
			server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
				if request.Method == http.MethodGet {
					fmt.Fprintf(writer, `{"update":{"version":%q}}`, test.latestVersion)
					return
				}
				postCount++
				fmt.Fprintf(writer, `{"platform":"ios","version":%q,"url":"https://example.com/Unbound.deb"}`, test.version)
			}))
			defer server.Close()

			published, err := publishLoaderRelease(context.Background(), loaderReleasePublishConfig{
				endpoint: server.URL + "/api/v1/loader/releases",
				apiKey:   "ci-key",
				platform: "ios",
				version:  test.version,
				url:      "https://example.com/Unbound.deb",
			})
			if (err != nil) != test.wantError {
				t.Fatalf("unexpected publish error: %v", err)
			}
			if published != test.wantPublished {
				t.Fatalf("published = %t, want %t", published, test.wantPublished)
			}
			if test.wantError && !strings.Contains(err.Error(), "older than published") {
				t.Fatalf("unexpected older-version error: %v", err)
			}
			if postCount != map[bool]int{true: 1, false: 0}[test.wantPublished] {
				t.Fatalf("POST count = %d, want %t", postCount, test.wantPublished)
			}
		})
	}
}

func TestPublishLoaderReleaseRejectsMissingKeyAndInvalidPlatform(t *testing.T) {
	config := loaderReleasePublishConfig{
		endpoint: "https://unbound.rip/api/v1/loader/releases",
		platform: "ios",
		version:  "1.0.1",
		url:      "https://github.com/unbound-app/loader/releases/download/v352.0/Unbound.deb",
	}
	if _, err := publishLoaderRelease(context.Background(), config); err == nil || !strings.Contains(err.Error(), "UNBOUND_API_KEY") {
		t.Fatalf("expected a missing-key error, got %v", err)
	}

	config.apiKey = "ci-key"
	config.platform = "unknown"
	if _, err := publishLoaderRelease(context.Background(), config); err == nil || !strings.Contains(err.Error(), "platform") {
		t.Fatalf("expected an invalid-platform error, got %v", err)
	}
}

func TestPublishLoaderReleaseReadsChangelogFile(t *testing.T) {
	temporary := t.TempDir()
	changelogPath := temporary + "/changelog.md"
	if err := os.WriteFile(changelogPath, []byte("  Improved native plugin reliability.\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.Method == http.MethodGet {
			fmt.Fprint(writer, `{"update":null}`)
			return
		}
		var body loaderReleasePublishRequest
		if err := json.NewDecoder(request.Body).Decode(&body); err != nil {
			t.Fatal(err)
		}
		if body.Changelog == nil || *body.Changelog != "Improved native plugin reliability." {
			t.Fatalf("unexpected changelog: %#v", body.Changelog)
		}
		fmt.Fprint(writer, `{"platform":"ios","version":"1.0.1","url":"https://github.com/unbound-app/loader/releases/download/v352.0/Unbound.deb"}`)
	}))
	defer server.Close()
	t.Setenv("UNBOUND_API_KEY", "ci-key")

	if err := runPublishLoaderRelease([]string{
		"--api-url", server.URL + "/api/v1/loader/releases",
		"--platform", "ios",
		"--version", "1.0.1",
		"--url", "https://github.com/unbound-app/loader/releases/download/v352.0/Unbound.deb",
		"--changelog-file", changelogPath,
	}); err != nil {
		t.Fatal(err)
	}
}

func TestPublishLoaderReleasesPreflightsBothPlatforms(t *testing.T) {
	for _, test := range []struct {
		name          string
		version       string
		latest        map[string]string
		wantPublished []string
		wantSkipped   string
	}{
		{
			name:    "stale candidate skips both platforms",
			version: "1.0.2",
			latest: map[string]string{
				"ios":     "1.0.3",
				"android": "1.0.1",
			},
			wantSkipped: "ios",
		},
		{
			name:    "equal platform is skipped while older platform catches up",
			version: "1.0.2",
			latest: map[string]string{
				"ios":     "1.0.2",
				"android": "1.0.1",
			},
			wantPublished: []string{"android"},
		},
		{
			name:    "new version is published to both platforms",
			version: "1.0.2",
			latest: map[string]string{
				"ios":     "1.0.1",
				"android": "1.0.1",
			},
			wantPublished: []string{"ios", "android"},
		},
	} {
		t.Run(test.name, func(t *testing.T) {
			postCounts := map[string]int{}
			server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
				if request.Method == http.MethodGet {
					platform := request.URL.Query().Get("platform")
					latest, exists := test.latest[platform]
					if !exists {
						fmt.Fprint(writer, `{"update":null}`)
						return
					}
					fmt.Fprintf(writer, `{"update":{"version":%q}}`, latest)
					return
				}
				var body loaderReleasePublishRequest
				if err := json.NewDecoder(request.Body).Decode(&body); err != nil {
					t.Fatal(err)
				}
				postCounts[body.Platform]++
				fmt.Fprintf(writer, `{"platform":%q,"version":%q,"url":%q}`, body.Platform, test.version, body.URL)
			}))
			defer server.Close()

			result, err := publishLoaderReleases(context.Background(), loaderReleaseBatchConfig{
				endpoint:   server.URL + "/api/v1/loader/releases",
				apiKey:     "ci-key",
				version:    test.version,
				iosURL:     "https://example.com/Unbound.ipa",
				androidURL: "https://example.com/Unbound.apk",
				changelog:  "Improved native plugin reliability.",
			})
			if err != nil {
				t.Fatal(err)
			}
			if result.skippedPlatform != test.wantSkipped {
				t.Fatalf("skipped platform = %q, want %q", result.skippedPlatform, test.wantSkipped)
			}
			if strings.Join(result.published, ",") != strings.Join(test.wantPublished, ",") {
				t.Fatalf("published = %v, want %v", result.published, test.wantPublished)
			}
			for _, platform := range []string{"ios", "android"} {
				want := 0
				for _, published := range test.wantPublished {
					if published == platform {
						want = 1
					}
				}
				if postCounts[platform] != want {
					t.Fatalf("%s POST count = %d, want %d", platform, postCounts[platform], want)
				}
			}
		})
	}
}

func TestPublishLoaderReleaseRejectsAPIError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		writer.WriteHeader(http.StatusForbidden)
	}))
	defer server.Close()

	_, err := publishLoaderRelease(context.Background(), loaderReleasePublishConfig{
		endpoint: server.URL + "/api/v1/loader/releases",
		apiKey:   "ci-key",
		platform: "android",
		version:  "1.0.1",
		url:      "https://github.com/unbound-app/loader/releases/download/v352.0/Unbound.apk",
	})
	if err == nil || !strings.Contains(err.Error(), "HTTP 403") {
		t.Fatalf("expected API authorization failure, got %v", err)
	}
}

func TestPublishLoaderReleaseValidatesURLs(t *testing.T) {
	config := loaderReleasePublishConfig{
		endpoint: "ftp://unbound.rip/api/v1/loader/releases",
		apiKey:   "ci-key",
		platform: "ios",
		version:  "1.0.1",
		url:      "https://github.com/unbound-app/loader/releases/download/v352.0/Unbound.deb",
	}
	if _, err := publishLoaderRelease(context.Background(), config); err == nil || !strings.Contains(err.Error(), "API URL") {
		t.Fatalf("expected invalid API URL error, got %v", err)
	}

	config.endpoint = "https://unbound.rip/api/v1/loader/releases"
	config.url = "file:///loader.deb"
	if _, err := publishLoaderRelease(context.Background(), config); err == nil || !strings.Contains(err.Error(), "asset URL") {
		t.Fatalf("expected invalid asset URL error, got %v", err)
	}
}
