# @unbound-app/loader-ios

Tweak to inject [Unbound](https://github.com/unbound-app/client) into Discord and perform various utility tasks.

## Installation

Builds can be found in the [Releases](https://github.com/unbound-app/loader-ios/releases/latest) tab.

### Jailbroken

- Add the apt repo to your package manager: <https://repo.unbound.rip>
- Install Unbound by downloading the appropriate Debian package (or by building your own, see [Building](#building)) and adding it to your package manager.

### Jailed

<a href="tbd"><img src="https://adriancastro.dev/0byxzkzdsauj.png" width="230"></a>
<a href="tbd"><img src="https://i.imgur.com/dsbDLK9.png" width="230"></a>
<a href="tbd"><img src="https://i.imgur.com/46qhEAv.png" width="230"></a>

> [!WARNING]
> Trying to use non-substrate tweak runtimes (such as TrollFools or LiveContainer's TweakLoader) will likely break functionality. Please always use the pre-patched ipa when sideloading.

- Download and install [Unbound.ipa](https://github.com/unbound-app/loader-ios/releases/latest/download/Unbound.ipa) using your preferred sideloading method.

## Building

> [!NOTE]
> Unless you plan on modifying the source code you should fork the repository and use the provided workflow to build the tweak/ipa.

<details>
<summary>Instructions</summary>

> These steps assume you use macOS.

1. Install Xcode from the App Store. If you've previously installed the `Command Line Utilities` package, you will need to run `sudo xcode-select -switch /Applications/Xcode.app/Contents/Developer` to make sure you're using the Xcode tools instead.

> If you want to revert the `xcode-select` change, run `sudo xcode-select -switch /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`

2. Install the required dependencies. You can do this by running `brew install make ldid` in your terminal. If you do not have brew installed, follow the instructions [here](https://brew.sh/).

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

## Contributors

[![Contributors](https://contrib.rocks/image?repo=unbound-app/loader-ios)](https://github.com/unbound-app/loader-ios/graphs/contributors)
