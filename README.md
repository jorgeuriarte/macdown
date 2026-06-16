# MacDown Remix

> A community maintenance fork — **the best of several MacDown worlds, in one.**

[MacDown](https://github.com/MacDownApp/macdown), the macOS Markdown editor by
[Tzu-ping Chung](https://uranusjr.com) (MIT), has been unmaintained since 2023 and no
longer builds or launches on modern macOS / Apple Silicon. **MacDown Remix** keeps it
alive and gathers the best contributions scattered across its forks, evolving it where
needed.

**Where it draws from** (full attribution in [`docs/CREDITS.md`](docs/CREDITS.md) and in
the app's "About MacDown Remix" window):

| Piece | Source |
|---|---|
| Codebase | [plateaukao/macdown](https://github.com/plateaukao/macdown) — the most recent active fork with the original Objective-C architecture |
| Render engine | [cmark-gfm](https://github.com/github/cmark-gfm) (GitHub's CommonMark + GFM), integrated from [SiggeMcKvack/macdown](https://github.com/SiggeMcKvack/macdown) — AST with source positions |
| Preview | Migration to **WKWebView** (modern WebKit) with two-way synced scrolling |
| GitHub-style TOC anchors | [Reza Ambler](https://github.com/RezaAmbler/macdown_arm) |
| Diagrams / modes | Mermaid v11, quick view modes (⌃⌘1/2/3), modern macOS launch fixes (community) |

It honors the **MIT license** and the **original copyright** (© 2014–2020 Tzu-ping Chung).
It does not replace or impersonate the official MacDown: it has its own identity
(`net.omelas.macdown-remix`) and its own releases.

> ⚠️ cmark-gfm engine trade-off: three hoedown extensions are lost (highlight `==`,
> superscript `^`, underline `_`) in exchange for the modern AST that enables everything else.

The project periodically tracks the fork ecosystem (the original and its derivatives) so
nothing good is missed — see [`docs/FORKS.md`](docs/FORKS.md) and
`claude_tools/track_forks.sh`.

---

Below is the **original MacDown README**:

# MacDown

[![](https://img.shields.io/github/release/MacDownApp/macdown.svg)](http://macdown.uranusjr.com/download/latest/)
![Total downloads](https://img.shields.io/github/downloads/MacDownApp/macdown/latest/total.svg)
[![Build Status](https://travis-ci.org/MacDownApp/macdown.svg?branch=master)](https://travis-ci.org/MacDownApp/macdown)


MacDown is an open source Markdown editor for OS X, released under the MIT License. The author stole the idea from [Chen Luo](https://twitter.com/chenluois)’s [Mou](http://mouapp.com) so that people can make crappy clones.

Visit the [project site](http://macdown.uranusjr.com/) for more information, or download [MacDown.app.zip](http://macdown.uranusjr.com/download/latest/) directly from the [latest releases](https://github.com/MacDownApp/macdown/releases/latest) page.

## Install

[Download](http://macdown.uranusjr.com/download/latest/), unzip, and drag the app to Applications folder. MacDown is also available through [Homebrew Cask](https://caskroom.github.io/):

    brew install --cask macdown

## Screenshot

![screenshot](assets/screenshot.png)

## License

MacDown is released under the terms of MIT License. You may find the content of the license [here](http://opensource.org/licenses/MIT), or inside the `LICENSE` directory.

You may find full text of licenses about third-party components in the `LICENSE` directory, or the **About MacDown** panel in the application.

The following editor themes and CSS files are extracted from [Mou](http://mouapp.com), courtesy of Chen Luo:

* Mou Fresh Air
* Mou Fresh Air+
* Mou Night
* Mou Night+
* Mou Paper
* Mou Paper+
* Tomorrow
* Tomorrow Blue
* Tomorrow+
* Writer
* Writer+
* Clearness
* Clearness Dark
* GitHub
* GitHub2

## Development

### Requirements

If you wish to build MacDown yourself, you will need the following components/tools:

* OS X SDK (10.14 or later)
* Git
* [Bundler](http://bundler.io)

> Note: Old versions of CocoaPods are not supported. Please use Bundler to execute CocoaPods, or make sure your CocoaPods is later than shown in `Gemfile.lock`.

> Note: The Command Line Tools (CLT) should be unnecessary. If you failed to compile without it, please install CLT with
>
>     xcode-select --install
>
> and report back.

An appropriate SDK should be bundled with Xcode 5 or later versions.

### Environment Setup

After cloning the repository, run the following commands inside the repository root (directory containing this `README.md` file):

    git submodule update --init
    bundle install
    bundle exec pod install
    make -C Dependency/peg-markdown-highlight

and open `MacDown.xcworkspace` in Xcode. The first command initialises the dependency submodule(s) used in MacDown; the second one installs dependencies managed by CocoaPods.

Refer to the official guides of Git and CocoaPods if you need more instructions. If you run into build issues later on, try running the following commands to update dependencies:

    git submodule update
    bundle exec pod install

### Translation

Please help translation on [Transifex](https://www.transifex.com/macdown/macdown/).

![Transifex translation percentage](https://www.transifex.com/projects/p/macdown/resource/macdownxliff/chart/image_png/)

## Discussion

[![Gitter](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/MacDownApp/macdown)

Join our [Gitter channel](https://gitter.im/MacDownApp/macdown) if you have any problems with MacDown. Any suggestions are welcomed, too!

You can also [file an issue directly](https://github.com/MacDownApp/macdown/issues/new) on GitHub if you prefer so. But please, **search first to make sure no-one has reported the same issue already** before opening one yourself. MacDown does not update in your computer immediately when we make changes, so something you experienced might be known, or even fixed in the development version.

MacDown depends a lot on other open source projects, such as [Hoedown](https://github.com/hoedown/hoedown) for Markdown-to-HTML rendering, [Prism](http://prismjs.com) for syntax highlighting (in code blocks), and [PEG Markdown Highlight](https://github.com/ali-rantakari/peg-markdown-highlight) for editor highlighting. If you find problems when using those particular features, you can also consider reporting them directly to upstream projects as well as to MacDown’s issue tracker. I will do what I can if you report it here, but sometimes it can be more beneficial to interact with them directly.

## Tipping

If you find MacDown suitable for your needs, please consider [giving me a tip through PayPal](http://macdown.uranusjr.com/faq/#donation). Or, if you prefer to buy me a drink *personally* instead, just [send me a tweet](https://twitter.com/uranusjr) when you visit [Taipei, Taiwan](http://en.wikipedia.org/wiki/Taipei), where I live. I look forward to meeting you!

