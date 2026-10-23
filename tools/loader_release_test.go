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
		if body.Changelog == nil || *body.Changelog != "Discord 352.0 includes loader fixes." {
			t.Fatalf("unexpected changelog: %#v", body.Changelog)
		}
		fmt.Fprint(writer, `{"platform":"ios","version":"1.0.1","url":"https://github.com/unbound-app/loader/releases/download/v352.0/Unbound.deb"}`)
	}))
	defer server.Close()

	err := publishLoaderRelease(context.Background(), loaderReleasePublishConfig{
		endpoint:  server.URL + "/api/v1/loader/releases",
		apiKey:    "ci-key",
		platform:  "ios",
		version:   "1.0.1",
		url:       "https://github.com/unbound-app/loader/releases/download/v352.0/Unbound.deb",
		changelog: "Discord 352.0 includes loader fixes.",
	})
	if err != nil {
		t.Fatal(err)
	}
}

func TestPublishLoaderReleaseRejectsMissingKeyAndInvalidPlatform(t *testing.T) {
	config := loaderReleasePublishConfig{
		endpoint: "https://unbound.rip/api/v1/loader/releases",
		platform: "ios",
		version:  "1.0.1",
		url:      "https://github.com/unbound-app/loader/releases/download/v352.0/Unbound.deb",
	}
	if err := publishLoaderRelease(context.Background(), config); err == nil || !strings.Contains(err.Error(), "UNBOUND_API_KEY") {
		t.Fatalf("expected a missing-key error, got %v", err)
	}

	config.apiKey = "ci-key"
	config.platform = "unknown"
	if err := publishLoaderRelease(context.Background(), config); err == nil || !strings.Contains(err.Error(), "platform") {
		t.Fatalf("expected an invalid-platform error, got %v", err)
	}
}

func TestPublishLoaderReleaseReadsChangelogFile(t *testing.T) {
	temporary := t.TempDir()
	changelogPath := temporary + "/changelog.md"
	if err := os.WriteFile(changelogPath, []byte("  Discord 352.0 updated the client.\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		var body loaderReleasePublishRequest
		if err := json.NewDecoder(request.Body).Decode(&body); err != nil {
			t.Fatal(err)
		}
		if body.Changelog == nil || *body.Changelog != "Discord 352.0 updated the client." {
			t.Fatalf("unexpected changelog: %#v", body.Changelog)
		}
		fmt.Fprint(writer, `{"platform":"ios","version":"1.0.1","url":"https://github.com/unbound-app/loader/releases/download/v352.0/Unbound.deb"}`)
	}))
	defer server.Close()
	t.Setenv("UNBOUND_API_KEY", "ci-key")

	if err := runPublishLoaderRelease([]string{
		"--api-url", server.URL,
		"--platform", "ios",
		"--version", "1.0.1",
		"--url", "https://github.com/unbound-app/loader/releases/download/v352.0/Unbound.deb",
		"--changelog-file", changelogPath,
	}); err != nil {
		t.Fatal(err)
	}
}

func TestPublishLoaderReleaseRejectsAPIError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		writer.WriteHeader(http.StatusForbidden)
	}))
	defer server.Close()

	err := publishLoaderRelease(context.Background(), loaderReleasePublishConfig{
		endpoint: server.URL,
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
	if err := publishLoaderRelease(context.Background(), config); err == nil || !strings.Contains(err.Error(), "API URL") {
		t.Fatalf("expected invalid API URL error, got %v", err)
	}

	config.endpoint = "https://unbound.rip/api/v1/loader/releases"
	config.url = "file:///loader.deb"
	if err := publishLoaderRelease(context.Background(), config); err == nil || !strings.Contains(err.Error(), "asset URL") {
		t.Fatalf("expected invalid asset URL error, got %v", err)
	}
}
