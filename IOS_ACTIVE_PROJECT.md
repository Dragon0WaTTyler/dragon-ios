# Dragon iOS — Active Project Guardrail

This repo has one canonical active iOS project.

## Canonical iOS project

- Repo: `/Users/dragonsmac/Desktop/Dragon-iOS/Dragon`
- Xcode project: `/Users/dragonsmac/Desktop/Dragon-iOS/Dragon/DragonCarrier/DragonCarrier.xcodeproj`
- Scheme: `TestInstall`
- Source root: `/Users/dragonsmac/Desktop/Dragon-iOS/Dragon/DragonCarrier/TestInstall`

## Allowed edit root

For normal code tasks, only edit files under:

```text
/Users/dragonsmac/Desktop/Dragon-iOS/Dragon/DragonCarrier/TestInstall
```

Documentation-only guardrail tasks may edit this file:

```text
/Users/dragonsmac/Desktop/Dragon-iOS/Dragon/IOS_ACTIVE_PROJECT.md
```

## Do not touch

Do not edit:

```text
/Users/dragonsmac/Desktop/_ARCHIVE_DO_NOT_USE_Dragon-iOS-TV
/Users/dragonsmac/Desktop/Dragon-iOS/Dragon/Dragon
/Users/dragonsmac/Desktop/Dragon-iOS/Dragon/Dragon.xcodeproj
```

Do not edit any `project.pbxproj` unless explicitly approved.

## Required pre-edit checks

Before any code edit, run:

```bash
pwd
git rev-parse --show-toplevel
git branch --show-current
git status --short
```

Stop if the repo root is not:

```text
/Users/dragonsmac/Desktop/Dragon-iOS/Dragon
```

## Build command

Use this build command for iOS verification:

```bash
xcodebuild -project DragonCarrier/DragonCarrier.xcodeproj \
  -scheme TestInstall \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  build
```

## Xcode rule

Open only:

```text
/Users/dragonsmac/Desktop/Dragon-iOS/Dragon/DragonCarrier/DragonCarrier.xcodeproj
```

Do not open:

```text
/Users/dragonsmac/Desktop/Dragon-iOS/Dragon/Dragon.xcodeproj
/Users/dragonsmac/Desktop/_ARCHIVE_DO_NOT_USE_Dragon-iOS-TV
```

## Codex instruction

Every future Codex task for Dragon iOS must start by reading this file and obeying it.

Use this line in future prompts:

```text
Read IOS_ACTIVE_PROJECT.md first and obey it.
```
