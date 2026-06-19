# Dragon Codex Rules

## Active iPhone App

The active iPhone app is:

- Project: DragonCarrier/DragonCarrier.xcodeproj
- Scheme: TestInstall
- Source root: DragonCarrier/TestInstall

## Donor Tree

Dragon/ is donor/reference only.
Do not edit Dragon/ unless the user explicitly asks for donor-tree work.

## Required Preflight

Before editing iPhone code, run:

- git status --short --branch
- xcodebuild -list -project DragonCarrier/DragonCarrier.xcodeproj

Then confirm:

Active iPhone source confirmed: DragonCarrier/TestInstall

## Required Scope Check

Before reporting completion, run:

git diff --name-only

No files outside the allowed scope may be changed.

## Commit Rule

Never use:

git add .

Only stage explicit files requested by the task.
