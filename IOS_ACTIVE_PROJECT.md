# iOS Active Project Guardrail

Canonical active iOS project:

- Project: `DragonCarrier/DragonCarrier.xcodeproj`
- Scheme: `TestInstall`
- Source root: `DragonCarrier/TestInstall`

Rules:

- Future Codex tasks must only edit files under `DragonCarrier/TestInstall` unless the prompt explicitly says otherwise.
- Do not edit `Dragon/` unless explicitly switching to the separate inactive `Dragon` project.
- Do not edit `Dragon.xcodeproj` unless explicitly switching to the separate inactive `Dragon` project.
- Do not use backup folders as source.
- Build command:

```bash
xcodebuild -project DragonCarrier/DragonCarrier.xcodeproj -scheme TestInstall -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```
