package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestFetchIPACacheHit(t *testing.T) {
	data := []byte("test ipa bytes")
	digest := sha256.Sum256(data)
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.Method == http.MethodPost {
			_ = json.NewEncoder(writer).Encode(map[string]any{"status": "done", "cacheHit": true, "channel": "appstore", "resolvedVersion": "342.0", "artifact": map[string]any{"id": "artifact-1", "fileUrl": "/file", "sizeBytes": len(data), "sha256": hex.EncodeToString(digest[:])}})
			return
		}
		_, _ = writer.Write(data)
	}))
	defer server.Close()
	path := filepath.Join(t.TempDir(), "discord.ipa")
	result, err := fetchIPA(server.URL, "com.example.discord", "342", "secret", path, 1)
	if err != nil {
		t.Fatal(err)
	}
	if result["cache_hit"] != "true" || result["version"] != "342.0" {
		t.Fatalf("unexpected result: %#v", result)
	}
	actual, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(actual) != string(data) {
		t.Fatalf("unexpected artifact: %q", actual)
	}
}

func TestFetchIPAQueuedRunningDone(t *testing.T) {
	data := []byte("queued ipa")
	digest := sha256.Sum256(data)
	statuses := []map[string]any{
		{"status": "queued", "statusUrl": "/status"},
		{"status": "running", "progress": "installing", "statusUrl": "/status"},
		{"status": "done", "channel": "testflight", "versionLabel": "342.0_1", "artifact": map[string]any{"fileUrl": "/file", "sizeBytes": len(data), "sha256": hex.EncodeToString(digest[:])}},
	}
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.Method == http.MethodPost {
			_ = json.NewEncoder(writer).Encode(statuses[0])
			statuses = statuses[1:]
			return
		}
		if request.URL.Path == "/status" {
			_ = json.NewEncoder(writer).Encode(statuses[0])
			statuses = statuses[1:]
			return
		}
		_, _ = writer.Write(data)
	}))
	defer server.Close()
	path := filepath.Join(t.TempDir(), "discord.ipa")
	result, err := fetchIPAWith(server.URL, "com.example.discord", "342", "secret", path, time.Minute, func(time.Duration) {}, time.Now)
	if err != nil {
		t.Fatal(err)
	}
	if result["is_testflight"] != "true" || result["version"] != "342.0_1" {
		t.Fatalf("unexpected result: %#v", result)
	}
}

func TestFetchIPAChecksumMismatchRemovesOutput(t *testing.T) {
	data := []byte("test ipa bytes")
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.Method == http.MethodPost {
			_ = json.NewEncoder(writer).Encode(map[string]any{"status": "done", "artifact": map[string]any{"fileUrl": "/file", "sizeBytes": len(data), "sha256": "0000000000000000000000000000000000000000000000000000000000000000"}})
			return
		}
		_, _ = writer.Write(data)
	}))
	defer server.Close()
	path := filepath.Join(t.TempDir(), "discord.ipa")
	if _, err := fetchIPA(server.URL, "com.example.discord", "342", "secret", path, 1); err == nil {
		t.Fatal("expected checksum error")
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("output exists after failed download: %v", err)
	}
}
