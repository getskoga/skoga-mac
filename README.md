# Skoga (macOS app)

Native SwiftUI implementation of the Skoga manager's cockpit — the desktop client for [skoga](https://github.com/getskoga/skoga). Today it ships with a mock daemon client carrying the design's seed data; once `skogad` exposes its JSON-RPC socket, the real client drops in behind the same `DaemonClient` protocol.

## Build

```bash
brew install xcodegen   # one-time
xcodegen generate       # writes Skoga.xcodeproj from project.yml
open Skoga.xcodeproj
```

Then build & run in Xcode (⌘R). Min deployment target: macOS 14 Sonoma.

## Fonts

The design specifies Geist, Geist Mono, and Newsreader. The build falls back to system fonts (SF Pro / SF Mono / New York) until the real fonts are bundled. To bundle them:

1. Drop `.otf` / `.ttf` files into `Skoga/App/Fonts/`
2. Regenerate (`xcodegen generate`) — `ATSApplicationFontsPath` auto-registers them
3. The token names in `Typography.swift` already match the family names

Geist is MIT-licensed; Newsreader is OFL.

## Layout

```
Skoga/
  App/          App entry, Info.plist, entitlements
  Design/       Color/typography/spacing tokens, OKLCH→sRGB
  Domain/       Agent, ConversationMessage, AgentStatus
  Data/         DaemonClient protocol + MockDaemonClient
  State/        AppState (ObservableObject)
  Chrome/       MainWindow, TitleBar, Sidebar
  Components/   PulseDot, StatusPill, ActivityBars, icons
  Cockpit/      Instrument strip
  Roster/       Cards view, filter rail
```

## Status

Vertical slice — design system + window chrome + Roster (cards layout). Conversation, Dispatch, Review, Telemetry, PR modal, and ⌘K command palette are next.
