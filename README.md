# MacDown Remix

> Fork de mantenimiento de la comunidad — **lo mejor de varios mundos de MacDown, en uno.**

[MacDown](https://github.com/MacDownApp/macdown), el editor Markdown para macOS de
[Tzu-ping Chung](https://uranusjr.com) (MIT), lleva sin mantenerse desde 2023 y ya no
compila ni arranca en macOS / Apple Silicon modernos. **MacDown Remix** lo mantiene vivo
y reúne las mejores aportaciones dispersas por sus forks, evolucionándolo donde hace falta.

**De dónde bebe** (atribución completa en [`docs/CREDITS.md`](docs/CREDITS.md) y en la
ventana «Acerca de MacDown Remix» de la app):

| Pieza | Fuente |
|---|---|
| Base de código | [plateaukao/macdown](https://github.com/plateaukao/macdown) — el fork activo más reciente con la arquitectura Objective-C original |
| Motor de render | [cmark-gfm](https://github.com/github/cmark-gfm) (CommonMark + GFM de GitHub), integrado desde [SiggeMcKvack/macdown](https://github.com/SiggeMcKvack/macdown) — AST con posiciones de origen |
| Preview | Migración a **WKWebView** (WebKit moderno) con scroll sincronizado bidireccional |
| Anclas de TOC (estilo GitHub) | [Reza Ambler](https://github.com/RezaAmbler/macdown_arm) |
| Diagramas / modos | Mermaid v11, modos de vista rápidos (⌃⌘1/2/3), fixes de arranque para macOS moderno (comunidad) |

Respeta la **licencia MIT** y el **copyright original** (© 2014–2020 Tzu-ping Chung). No
sustituye ni suplanta al MacDown oficial: identidad propia (`net.omelas.macdown-remix`) y
releases propias.

> ⚠️ Trade-off del motor cmark-gfm: se pierden 3 extensiones de hoedown (resaltado `==`,
> superíndice `^`, subrayado `_`) a cambio del AST moderno que habilita el resto.

El proyecto rastrea periódicamente el ecosistema de forks (original y derivados) para no
perderse mejoras — ver [`docs/FORKS.md`](docs/FORKS.md) y `claude_tools/track_forks.sh`.

---

A continuación, el **README original de MacDown**:

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

