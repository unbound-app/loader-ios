# @unbound-app/loader-ios

[![Build Unbound](https://github.com/unbound-app/loader-ios/actions/workflows/build.yml/badge.svg)](https://github.com/unbound-app/loader-ios/actions/workflows/build.yml)

Tweak to inject [Unbound](https://github.com/unbound-app/client) into Discord and perform various utility tasks.

## Installation

Builds can be found in the [Releases](https://github.com/unbound-app/loader-ios/releases/latest) tab.

### Jailbroken

- Either add the apt repo to your package manager: <https://repo.unbound.rip>
- Or install Unbound by downloading the appropriate Debian package (or by building your own, see [Building](#building)) and adding it to your package manager.

### Jailed

<a href="https://tinyurl.com/unbound-feather"><img src="https://adriancastro.dev/0byxzkzdsauj.png" width="230"></a>
<a href="https://tinyurl.com/unbound-trollstore"><img src="https://i.imgur.com/dsbDLK9.png" width="230"></a>
<a href="https://tinyurl.com/unbound-sidestore"><img src="https://adriancastro.dev/basmxxk8sj3k.png" width="230"></a>

> [!WARNING]
> Trying to use non-ellekit tweak runtimes will likely break functionality. Ideally always use the pre-patched ipa when sideloading.

- Either add the altsource to your on-device sideloading tool: <https://repo.unbound.rip/app-repo.json>
- Or download and install [Unbound.ipa](https://github.com/unbound-app/loader-ios/releases/latest/download/Unbound.ipa) using your preferred sideloading method.

## Building

> [!NOTE]
> Unless you plan on modifying source code you should fork this repository and use the provided workflow.

<details>
<summary>Instructions</summary>

> These steps assume you use macOS.

1. Install Xcode from the App Store. If you've previously installed the `Command Line Utilities` package, you will need to run `sudo xcode-select -switch /Applications/Xcode.app/Contents/Developer` to make sure you're using the Xcode tools instead.

> If you want to revert the `xcode-select` change, run `sudo xcode-select -switch /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`

2. Install the required dependencies. You can do this by running `brew install make ldid` in your terminal. If you do not have brew installed, follow the instructions at the [Homebrew installation page](https://brew.sh/).

3. Setup your gnu make path:

```bash
export PATH="$(brew --prefix make)/libexec/gnubin:$PATH"
```

4. Setup [theos](https://theos.dev/docs/installation-macos) by running the script provided by theos.

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"
```

If you've already installed theos, you can run `$THEOS/bin/update-theos` to make sure it's up to date.

5. Clone this repository via `git clone git@github.com:unbound-app/loader-ios.git` and `cd` into it.

6. To build, you can run `make package`.

The resulting `.deb` file will be in the `packages` folder.

</details>

## Live reload (HMR)

When working on the [JavaScript client](https://github.com/unbound-app/client) you can have the
app reload automatically whenever you rebuild the bundle, instead of relaunching by hand.

1. Run the client's dev server (`bun scripts/dev` in the client repo). It serves the bundle and a
   Server-Sent Events stream at `/__hot`.
2. In Unbound's settings, set:
   - `loader.update.url` to your dev server's bundle URL, e.g. `http://<your-LAN-ip>:3000/unbound.bundle`
   - `loader.update.hmr` to `true`
3. Launch Discord. The loader connects to `<origin>/__hot`; when you edit a file and the dev
   server rebuilds, the app re-fetches the bundle and reloads automatically.

`loader.update.hmr` is off by default, so this never runs for normal users. The HMR endpoint is
derived from `loader.update.url`'s origin — no separate setting needed.

## Contributors

[![Contributors](https://contrib.rocks/image?repo=unbound-app/loader-ios)](https://github.com/unbound-app/loader-ios/graphs/contributors)
