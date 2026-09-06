# Cloom

Cloom is a local native macOS screen recorder with a configurable webcam overlay.

## Requirements

- macOS 15 or later
- Xcode 26.6 or compatible

## Build and test

```bash
xcodebuild test -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS'
xcodebuild build -project Cloom.xcodeproj -scheme Cloom -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Open `Cloom.xcodeproj` in Xcode for a signed local run that can request capture permissions.
