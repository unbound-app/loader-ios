package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

const defaultLoaderReleaseEndpoint = "https://unbound.rip/api/v1/loader/releases"

type loaderReleasePublishConfig struct {
	endpoint  string
	apiKey    string
	platform  string
	version   string
	url       string
	changelog string
	client    *http.Client
}

type loaderReleasePublishRequest struct {
	Platform  string  `json:"platform"`
	Version   string  `json:"version"`
	URL       string  `json:"url"`
	Changelog *string `json:"changelog,omitempty"`
}

type loaderReleasePublishResponse struct {
	Platform string `json:"platform"`
	Version  string `json:"version"`
	URL      string `json:"url"`
}

func runPublishLoaderRelease(args []string) error {
	set := flag.NewFlagSet("publish-loader-release", flag.ContinueOnError)
	endpoint := set.String("api-url", defaultLoaderReleaseEndpoint, "loader release publication endpoint")
	platform := set.String("platform", "", "ios or android")
	version := set.String("version", "", "semantic loader version")
	releaseURL := set.String("url", "", "public release asset URL")
	changelog := set.String("changelog", "", "optional release changelog")
	if err := set.Parse(args); err != nil {
		return err
	}

	config := loaderReleasePublishConfig{
		endpoint:  *endpoint,
		apiKey:    os.Getenv("UNBOUND_LOADER_API_KEY"),
		platform:  *platform,
		version:   *version,
		url:       *releaseURL,
		changelog: *changelog,
		client:    &http.Client{Timeout: 30 * time.Second},
	}
	if err := publishLoaderRelease(context.Background(), config); err != nil {
		return err
	}

	fmt.Printf("Published %s loader release %s\n", config.platform, config.version)
	return nil
}

func publishLoaderRelease(ctx context.Context, config loaderReleasePublishConfig) error {
	if config.apiKey == "" {
		return errors.New("UNBOUND_LOADER_API_KEY is required")
	}
	if config.platform != "ios" && config.platform != "android" {
		return errors.New("loader release platform must be ios or android")
	}
	if config.version == "" {
		return errors.New("loader release version is required")
	}
	if err := validateHTTPURL(config.endpoint); err != nil {
		return fmt.Errorf("invalid loader release API URL: %w", err)
	}
	if err := validateHTTPURL(config.url); err != nil {
		return fmt.Errorf("invalid loader release asset URL: %w", err)
	}

	requestBody := loaderReleasePublishRequest{
		Platform: config.platform,
		Version:  config.version,
		URL:      config.url,
	}
	if config.changelog != "" {
		requestBody.Changelog = &config.changelog
	}
	encodedBody, err := json.Marshal(requestBody)
	if err != nil {
		return fmt.Errorf("encode loader release request: %w", err)
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, config.endpoint, bytes.NewReader(encodedBody))
	if err != nil {
		return fmt.Errorf("create loader release request: %w", err)
	}
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("User-Agent", "unbound-loader-release-publisher/1.0")
	request.Header.Set("X-API-Key", config.apiKey)

	client := config.client
	if client == nil {
		client = &http.Client{Timeout: 30 * time.Second}
	}
	response, err := client.Do(request)
	if err != nil {
		return fmt.Errorf("publish %s loader release %s: %w", config.platform, config.version, err)
	}
	defer response.Body.Close()
	responseBody, err := io.ReadAll(io.LimitReader(response.Body, 16*1024))
	if err != nil {
		return fmt.Errorf("read loader release API response: %w", err)
	}
	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {
		return fmt.Errorf("loader release API returned HTTP %d", response.StatusCode)
	}

	var published loaderReleasePublishResponse
	if err := json.Unmarshal(responseBody, &published); err != nil {
		return fmt.Errorf("decode loader release API response: %w", err)
	}
	if published.Platform != config.platform || published.Version != config.version || published.URL != config.url {
		return errors.New("loader release API response does not match the published release")
	}
	return nil
}

func validateHTTPURL(value string) error {
	parsed, err := url.Parse(value)
	if err != nil {
		return err
	}
	if (parsed.Scheme != "https" && parsed.Scheme != "http") || parsed.Host == "" || strings.Contains(value, " ") {
		return errors.New("expected an absolute HTTP(S) URL")
	}
	return nil
}
