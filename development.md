# Kalvian Roots Development Guide

This file describes the current local build, test, and development workflow for
the Kalvian Roots checkout.

## Current Branch Model

- `main` is the active development branch for this personal project.
- Use a feature branch only when the user asks for one or the change is risky
  enough to need isolation.
- Before committing, run `git status -sb` and stage only the files that belong
  to the requested change.

## Local Xcode Setup

Open the project:

```bash
open "Kalvian Roots.xcodeproj"
```

The project uses Swift package dependencies configured in Xcode, including
SwiftNIO and SwiftLog. Do not re-add these manually unless package resolution is
actually broken.

If Xcode beta is installed at `/Applications/Xcode-beta.app`, command-line
builds can be run with:

```bash
DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer" xcodebuild test -project "Kalvian Roots.xcodeproj" -scheme "Kalvian Roots"
```

To make Xcode beta the selected command-line developer directory:

```bash
sudo xcode-select -s /Applications/Xcode-beta.app/Contents/Developer
xcodebuild -license accept
xcodebuild -version
```

## App Data

The canonical roots file is local:

```text
~/Documents/JuuretKälviällä.roots
```

The durable family network cache is local Application Support data:

```text
~/Library/Application Support/Kalvian Roots/Cache/families.json
```

Do not reintroduce iCloud/ubiquity, CoreData, CloudKit, or temporary-directory
cache fallback behavior unless that design is explicitly requested.

## AI Configuration

The current AI parser uses hosted DeepSeek through `AIParsingService`.

Configure the API key in the app's AI Settings screen. The key is stored
locally for personal use.

## FamilySearch Workflow

FamilySearch extraction is manual or user-triggered.

Use the workflow in:

```text
Docs/familysearch-bookmarklet.md
```

The generated bookmarklet comes from `FamilySearchDOMService.makeBookmarklet()`.
Do not maintain a second hand-written bookmarklet.

## Validation

Preferred checks for documentation-only changes:

```bash
git diff --check
```

Preferred checks for Swift source changes:

```bash
DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer" xcodebuild test -project "Kalvian Roots.xcodeproj" -scheme "Kalvian Roots"
git diff --check
```

When the full Xcode test suite is blocked by an unrelated stale test or local
toolchain issue, run the most relevant targeted checks and report the exact
blocker instead of silently skipping validation.

## Test Locations

- App tests: `Kalvian RootsTests`
- UI tests: `Kalvian RootsUITests`
- Swift package tests: `KalvianRootsCore/Tests`

New comparison, parsing, or citation logic should include focused tests in the
appropriate target.

## Useful Inspection Commands

```bash
git status -sb
rg --files -g '*.swift'
rg --files -g '*.md'
rg -n "PersonCandidate|PersonIdentity|FamilyComparisonResult"
```

Use `rg` before adding new logic so existing parsing, extraction, comparison,
and citation helpers are reused instead of duplicated.
