# Ecosistema de forks de MacDown

_Generado automáticamente por `claude_tools/track_forks.py` el 2026-06-13 10:47 UTC._

Este informe rastrea, para cada repo semilla (el MacDown original y las líneas evolucionadas), qué forks tienen commits propios y qué aportan. Regenéralo con `./claude_tools/track_forks.sh`.

## 🔔 Novedades desde la última ejecución

_Sin cambios respecto al snapshot anterior (o primera ejecución)._

## Resumen por seed

| Seed | Rama | Último push | Forks totales | Activos | Con commits propios |
|---|---|---|---:|---:|---:|
| `MacDownApp/macdown` | master | 2023-07-10 | 1146 | 52 | 32 |
| `plateaukao/macdown` | master | 2026-06-10 | 0 | 0 | 0 |
| `SiggeMcKvack/macdown` | master | 2026-03-26 | 0 | 0 | 0 |
| `nyimbi/macdown` | master | 2026-05-17 | 0 | 0 | 0 |
| `RezaAmbler/macdown_arm` | master | 2026-05-30 | 0 | 0 | 0 |
| `treehousetim/macdown` | master | 2026-04-09 | 0 | 0 | 0 |
| `duro/macdown` | master | 2026-06-05 | 0 | 0 | 0 |
| `xhu96/macdown` | master | 2026-06-04 | 0 | 0 | 0 |
| `Wirtzer/Markly` | markly | 2026-03-25 | 0 | 0 | 0 |
| `mfbergmann/macdown-swift` | master | 2026-06-08 | 0 | 0 | 0 |

## MacDownApp/macdown

Rama `master` · último push 2023-07-10 · ⭐9767 · 1146 forks

### Wirtzer/Markly — ahead 44, behind 0 (⭐4, push 2026-03-25)
- Add default view mode preference and toolbar view mode switcher
- Update README for MacDown v2
- Add project roadmap to README
- Add Phase 1 features: smart view modes, sidebar, and tabs
- Fix build: add missing MPGlobals.h import to MPDocument.m
- Add Phase 2 features: Focus mode, Typewriter mode, writing stats, DOCX export
- Add Phase 3: WikiLinks, Command Palette, prose tools, preview themes
- Fix Focus mode to use layout manager temporary attributes
- Add checkmarks for active toggle states in menus and command palette
- Make filler word highlighting a live toggle with counter
- Move Highlight Filler Words to top of command palette
- Fix filler word detection to use regex instead of NSLinguisticTagger
- Highlight filler words in both editor and preview panes
- Categorize weasel words with color-coded highlights per Amazon writing guide
- Make issue counter clickable with per-category breakdown
- Color-code dots in issue dropdown and improve readability
- Make issue counter readable with dark pill background and white text
- Fix WikiLinks: inject CSS into all themes and mark unsaved docs as missing
- Fix Graphviz and Mermaid checkboxes always being disabled
- Fix Graphviz and Mermaid checkbox layout — move to own row
- Fix Rendering preferences layout — Graphviz and Mermaid on own rows
- Fix Rendering prefs layout with proper auto-layout constraints
- Double Rendering preferences pane width to 810px
- Fix CSS checkbox overlap and mermaid init script
- Auto-enable syntax highlighting when Mermaid or Graphviz is turned on
- Always enable Mermaid, Graphviz, and syntax highlighting
- Rename app from ReadDown to Markly
- Rebrand help and README to Markly v1.0.0, remove CONTRIBUTING.md
- Rename all MacDown references in menus and UI to Markly
- Remove stale Contributing references from first launch and menu
- Remove open source language, reserve rights on new features
- Update deployment target to macOS 10.13 for modern Xcode compatibility
- Add LICENSE.md — All rights reserved for Markly additions
- Update README with Markly repo name and install instructions
- Rename MacDown/MacDownTests/macdown-cmd folders to Markly/MarklyTests/markly-cmd
- Remove contribute.md resource and showContributing method completely
- Rename MacDown.xcodeproj and MacDown.xcworkspace to Markly
- Fix toolbar crash on launch — out-of-bounds array access in toolbarDefaultItemIdentifiers
- Fix outline navigation — respond to single click instead of double click
- Update Mermaid to improve diagram rendering support
- Add DMG build script and entitlements for distribution
- Fix sidebar toggle and outline navigation in all view modes
- Add GitHub-based update checker, update About page for Markly
- Strip markdown formatting from update dialog release notes

### duro/macdown — ahead 19, behind 0 (⭐0, push 2026-06-05)
- Add opensFilesInPreviewOnly preference
- Add MPShouldOpenFileInPreviewOnly decision helper
- Add MPHasSavedSplitStateForAutosaveName probe
- Add 'Show only the preview when opening files' preference checkbox
- Open files in preview-only mode on first open when enabled
- Fix out-of-bounds toolbar index read that crashed launch on modern Xcode
- Fix Behavior box layout so the preview-only checkbox doesn't overlap
- Use Expanded toolbar style so prefs panes stay left-aligned & visible on modern SDK
- Commit local build-setup edits for a build-ready checkout
- Size preferences window to each pane's Auto Layout fitting height
- Let the Editor Behavior box self-size instead of clipping at 175pt
- Anchor the Markdown preferences pane so it self-sizes
- Let the Editor Behavior box resize its content so the pane self-sizes
- Add pure helpers for preferred window size (clamp + should-apply)
- Add preferred-window-size preferences (toggle + width/height)
- Open new document windows at the preferred size when set
- Add capture action + refresh for preferred window size
- Add preferred-window-size controls to General preferences
- Clamp preferred size to main screen when window has no screen yet

### lucy-jane/macdown — ahead 18, behind 0 (⭐0, push 2023-11-20)
- Bump minimatch from 3.0.4 to 3.0.8 in /Tools/GitHub-style-generator
- Bump travis from 1.10.0 to 1.11.1
- Bump semver and node-sass in /Tools/GitHub-style-generator
- Bump scss-tokenizer and node-sass in /Tools/GitHub-style-generator
- Merge pull request #12 from lucy-jane/dependabot/npm_and_yarn/Tools/GitHub-style-generator/scss-tokenizer-and-node-sass-0.4.3
- Merge pull request #10 from lucy-jane/dependabot/npm_and_yarn/Tools/GitHub-style-generator/semver-and-node-sass-7.5.4
- Bump addressable from 2.7.0 to 2.8.4
- Bump cocoapods-downloader from 1.4.0 to 1.6.3
- Merge pull request #14 from lucy-jane/dependabot/bundler/cocoapods-downloader-1.6.3
- Bump tzinfo from 1.2.9 to 1.2.11
- Merge pull request #15 from lucy-jane/dependabot/bundler/tzinfo-1.2.11
- Merge pull request #13 from lucy-jane/dependabot/bundler/addressable-2.8.4
- Merge pull request #7 from lucy-jane/dependabot/bundler/travis-1.11.1
- Merge pull request #3 from lucy-jane/dependabot/npm_and_yarn/Tools/GitHub-style-generator/minimatch-3.0.8
- Bump cocoapods from 1.10.1 to 1.12.1
- Merge pull request #1 from lucy-jane/dependabot/bundler/cocoapods-1.12.1
- travis update
- Create objective-c-xcode.yml

### aseelye/macdown — ahead 17, behind 0 (⭐0, push 2026-01-13)
- Disable autosave-in-place; fix heading/list rendering
- Improve rendering stability and cleanup
- close program on window close
- Add GitHub Actions CI
- CI: generate pmh_parser.c
- update deploy targets to 10.15+
-   Remove Sparkle; refactor document + rendering
- add audit working doc
- Unsafe toolbar action invocation (wrong IMP signature)
- Fixing  is a “god object” (multi-responsibility + oversized)
- Fix Observer lifecycle safety (KVO/notifications) / F-003
- Preference naming debt (misspellings + aliases leak into core logic) / F-004
- Editor view state persistence via KVO/KVC (leaky layering) / F-005
- Renderer flags ownership is split between preferences and renderer / F-006
- Style inconsistencies in touched files (Allman vs K&R) / F-007
- Confusing selector name valueForKey:fromQueryItems: / F-008
- URL scheme handler has unfinished feature (line/column ignored) / F-009

### nyimbi/macdown — ahead 12, behind 0 (⭐0, push 2026-05-17)
- Refresh clean documents after external file edits
- Unify export customization options
- Add DOCX and PPTX export backends
- Print PDF exports from customized HTML
- Add styled export presets and cover pages
- Polish DOCX cover and body rendering
- Harden PPTX packages for native renderers
- Use the system CocoaPods toolchain
- Let business documents compose reusable Markdown sources
- Reduce document-window clutter with native tab groups
- Refresh master documents when included files change
- Keep the business improvement list implementation-bound

### tikkal/macdown-arm64 — ahead 12, behind 0 (⭐11, push 2025-08-20)
- Update build deps, and build for Mac silicon (arm64)
- add venv
- test commit
- add aider
- Merge branch 'master' of github.com:tikkal/macdown
- comment for aider
- Build for Arm64 on MacOS Silicon. Exclude x86 Builds.  (#1)
- cleanup (#2)
- Update contribute.md
- Update README.md
- Update links to arm64 release
- Update for arm64 links

### RezaAmbler/macdown_arm — ahead 10, behind 0 (⭐0, push 2026-05-30)
- Enable native arm64 (Apple Silicon) build
- Add font zoom and Light/Dark/Sepia view modes
- Fix crash when clicking segmented toolbar groups
- Make font zoom also scale the rendered preview
- Make in-document TOC heading links work
- Add Sparkle auto-update feed pointing at this fork's GitHub releases
- Add release.sh to automate signed arm64 GitHub releases
- release.sh: stamp version deterministically from git
- Release 0.8.0
- Release 0.8.1

### mfbergmann/macdown-swift — ahead 10, behind 0 (⭐0, push 2026-06-08)
- Port MacDown to Swift with cross-platform macOS/iOS support
- Make SwiftPM macOS/iOS app targets build and run
- Add macOS .app packaging, signing, and release pipeline
- Fix entitlements parse error during codesign
- Add live editor syntax highlighting and coordinate default themes
- New app icon: Markdown M-down mark with a Swift-orange arrow
- Auto-detect Developer ID in build-app.sh for turnkey local signing
- Only auto-publish releases from CI when signing secrets are present
- Merge pull request #1 from mfbergmann/claude/port-macdown-swift-fIBgJ
- Add ROADMAP.md with prioritized feature plan

### treehousetim/macdown — ahead 9, behind 0 (⭐1, push 2026-04-09)
- Fix infinite loop / hang on launch from out-of-bounds array reads in toolbar setup
- Reload document automatically when the file changes on disk
- Regenerate Podfile.lock and Pods build phase against CocoaPods 1.16.2
- Add Quick Look Preview Extension target so .md files preview from Finder
- Prep treehousetim release: Developer ID signing, strip Sparkle, rebrand help
- Add custom About window with fork attribution and bundled licenses
- Bump version.txt to 1.0.1 for post-release dev builds
- Drop git-driven Update Build Number, hardcode version in source plist
- Add Tools/release.sh for one-command release builds

### SiggeMcKvack/macdown — ahead 9, behind 0 (⭐0, push 2026-03-26)
- Build arm64-only, bump minimum to macOS 11.0, update Sparkle to 2.x
- Update dependencies and fix preferences layout
- Replace hoedown with cmark-gfm for Markdown rendering
- Switch to official github/cmark-gfm repository
- Refresh GitHub styles and add GitHub Dark theme
- Add GitLab light and dark themes
- Bump version to 0.8
- Bump version.txt to 0.8.1
- Fix out-of-bounds array access in toolbarDefaultItemIdentifiers:

### jowtron/macdown — ahead 8, behind 0 (⭐0, push 2026-01-14)
- Fix black box rendering when hiding editor/preview pane
- Fix CI: use macos-14 and skip Bundler
- Use macos-13 with Xcode 14.3 for libarclite compatibility
- Prevent build cancellation with concurrency settings
- Use macos-latest with deployment target 10.13 to avoid libarclite
- Fix submodule initialization
- Add parser generation step
- Build universal binary for Intel and Apple Silicon Macs

### jamesalfei/macdown — ahead 8, behind 0 (⭐0, push 2025-06-11)
- Bump hosted-git-info
- Merge pull request #26 from jamesalfei/dependabot/npm_and_yarn/Tools/GitHub-style-generator/npm_and_yarn-683b1b7287
- Bump minimatch (#27)
- Bump path-parse (#25)
- Bump qs in /Tools/GitHub-style-generator in the npm_and_yarn group (#23)
- Bump tar in /Tools/GitHub-style-generator in the npm_and_yarn group (#22)
- Bump the npm_and_yarn group (#21)
- Bump node-sass (#20)

### xhu96/macdown — ahead 6, behind 0 (⭐0, push 2026-06-04)
- Modernize MacDown for Apple Silicon and macOS 11+
- Clarify fork maintenance status
- Remove stale translation badge
- Add Albanian localization
- Document fork changes and fix rendering preferences layout
- Remove stale terminal preferences outlets

### plateaukao/macdown — ahead 6, behind 0 (⭐0, push 2026-06-10)
- Render mermaid diagrams: upgrade to mermaid v11
- Merge pull request #1 from plateaukao/mermaid-v11-rendering
- Add default-layout preference and fix preferences window UI
- Merge pull request #2 from plateaukao/default-layout-pref
- Hide formatting toolbar items in preview-only mode; add table borders to themes
- Theme mermaid diagrams for dark preview styles

### djpadz/macdown — ahead 3, behind 0 (⭐0, push 2026-06-01)
- Getting it to build on macOS 26.
- Fixed a bounding error and removed Sparkle
- Some cleanup and using node 14 for GitHub-style-generator

### shingu-m/macdown — ahead 3, behind 0 (⭐0, push 2026-02-28)
- fix: correct Open Recent list on macOS Tahoe
- fix: restore preferences window layout on macOS Tahoe
- fix: prevent out-of-bounds crash in toolbar on macOS Tahoe

### David-Talaga/macdown — ahead 3, behind 0 (⭐0, push 2025-07-16)
- Recompiled with Xcode Version 16.4 (16F6)
- Updated dependencies for New Compilation
- Updated for Apple Silicon

### lisanet/macdown — ahead 3, behind 0 (⭐0, push 2025-06-24)
- update sparkle
- fix: bad access on Apple Silicon due to different calling convention
- Merge pull request #1 from gnattu/master

### realid/macdown — ahead 2, behind 0 (⭐0, push 2026-05-06)
- Modernize macOS build and fix release startup
- Refresh README for forked macOS arm64 builds

### rtbforge/macdown — ahead 2, behind 0 (⭐0, push 2026-04-30)
- Minor updates to get working in 2026
- Rewrite Plan

### alicela1n/macdown — ahead 2, behind 0 (⭐0, push 2026-01-19)
- Fix some compiler warnings
- MacDown/Code/Application/MPToolbarController.m: The macOS SDK should calculate MaxSize automatically now

### daviejaneway/Smacdown — ahead 2, behind 0 (⭐0, push 2024-10-25)
- fix: Upgrade macOS deployment target to 12.0 and get the project running
- feature: Port JJPluralForm to Swift in a local SPM module & integrate back into app code

### johnchlorophyll/macdown — ahead 1, behind 0 (⭐0, push 2026-05-26)
- Fix infinite loop in MPToolbarController toolbarDefaultItemIdentifiers

### zhanglan332/mydown — ahead 1, behind 0 (⭐0, push 2026-05-26)
- Add local startup script and Ruby/CocoaPods compatibility fixes

### liyoro/macdown — ahead 1, behind 0 (⭐0, push 2026-05-17)
- 适配 macOS Tahoe 26.5

### igorschlum/macdown — ahead 1, behind 0 (⭐0, push 2026-02-11)
- Restore OpenRecent

### dsandor/macdown — ahead 1, behind 0 (⭐0, push 2025-12-25)
- refactored to build

### fisher158163/macdown — ahead 1, behind 0 (⭐1, push 2025-10-31)
- Updated the App icon

### emsspree/macdown — ahead 1, behind 0 (⭐0, push 2025-04-13)
- remove broken LPROJs

### Ulziikh/macdown — ahead 1, behind 0 (⭐0, push 2025-03-04)
- markdown-Ulziikhishig.md

### trailblazr/macdown — ahead 1, behind 0 (⭐0, push 2025-01-29)
- Made the whole thing compile again in Apple M1, fixing the RECENT documents bug.

### RandyMcMillan/macdown — ahead 1, behind 0 (⭐0, push 2023-11-18)
- GNUmakefile

## plateaukao/macdown

Rama `master` · último push 2026-06-10 · ⭐0 · 0 forks

_Ningún fork con commits propios detectado._

## SiggeMcKvack/macdown

Rama `master` · último push 2026-03-26 · ⭐0 · 0 forks

_Ningún fork con commits propios detectado._

## nyimbi/macdown

Rama `master` · último push 2026-05-17 · ⭐0 · 0 forks

_Ningún fork con commits propios detectado._

## RezaAmbler/macdown_arm

Rama `master` · último push 2026-05-30 · ⭐0 · 0 forks

_Ningún fork con commits propios detectado._

## treehousetim/macdown

Rama `master` · último push 2026-04-09 · ⭐1 · 0 forks

_Ningún fork con commits propios detectado._

## duro/macdown

Rama `master` · último push 2026-06-05 · ⭐0 · 0 forks

_Ningún fork con commits propios detectado._

## xhu96/macdown

Rama `master` · último push 2026-06-04 · ⭐0 · 0 forks

_Ningún fork con commits propios detectado._

## Wirtzer/Markly

Rama `markly` · último push 2026-03-25 · ⭐4 · 0 forks

_Ningún fork con commits propios detectado._

## mfbergmann/macdown-swift

Rama `master` · último push 2026-06-08 · ⭐0 · 0 forks

_Ningún fork con commits propios detectado._

