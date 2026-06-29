# Cap — Phase 0 Setup

This folder has real Swift source, not a mockup — but it was written without access to Xcode, so treat the first build as a verification pass, not a rubber stamp.

## What's actually in Phase 0

Working, real integrations: the chat UI wired to Apple's on-device Foundation Models framework with Cap's persona baked into the system instructions; Apple Calendar read via EventKit; Canvas REST API integration for courses, assignments, and syllabus text, authenticated with your personal access token; a local, encrypted, on-device task list with in-app quick capture.

Not in Phase 0, by design: voice, Apple Calendar write-back, Google/Outlook accounts, location, proactive notifications. Those are Phases 1–3 from the roadmap doc. Quick capture is in-app only for now — hooking it to the iOS Share Sheet or a Siri Shortcut needs an extra Xcode target and is a fast follow once this compiles and runs.

## The one thing to verify first

`CapApp/Services/FoundationModelsService.swift` calls `LanguageModelSession`, `.respond(to:)`, `.content`, and `SystemLanguageModel.default.availability`. This framework shipped at WWDC25 and Apple kept extending it through WWDC26 (pluggable model providers), so the exact API surface may have shifted since the documentation this was written against. Before touching anything else: open that one file in Xcode and let autocomplete/the compiler tell you if any names changed. Everything else in this scaffold (EventKit, Canvas, Keychain, local storage, SwiftUI views) uses stable, long-standing APIs and should compile as-is.

## Requirements

A Mac running Xcode 26 or newer. To actually test the on-device model and EventKit, an Apple Intelligence-enabled iPhone (15 Pro or newer) running iOS 26+, plus a (free or paid) Apple Developer account to install on your own device. Simulator support for Foundation Models specifically is worth double-checking in Xcode's release notes — historically these on-device-intelligence features have been real-hardware-only, though that may have changed; don't burn time debugging "the model won't respond" before confirming you're on a real device.

## Option A — Manual Xcode project (no extra tools)

1. Xcode → File → New → Project → iOS → App. Interface: SwiftUI. Language: Swift. Uncheck Core Data/Tests, you don't need them yet.
2. Name it `Cap`, set a bundle identifier (e.g. `com.yourname.cap`), pick your team.
3. Set the deployment target to iOS 26.0 in the project's General tab.
4. Delete the default `ContentView.swift` and `CapApp.swift` Xcode generated — you're replacing them with the ones here.
5. Drag the entire `CapApp` folder (Models, Services, ViewModels, Views, plus the two root `.swift` files) from this directory into the Xcode project navigator. When prompted, choose "Copy items if needed" off (they're already where you want them) and make sure the **Cap** target checkbox is checked.
6. Project navigator → select the project → target **Cap** → **Info** tab → add two rows: `NSCalendarsFullAccessUsageDescription` and `NSCalendarsUsageDescription`, both set to something like "Cap reads your calendar to tell you what's coming up."
7. **Signing & Capabilities** → select your team so it can install to a real device.
8. Plug in your iPhone, select it as the run destination, hit Run.

## Option B — XcodeGen (faster, regenerates cleanly)

If you have or can install [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`):

```
cd /path/to/Cap
xcodegen generate
open Cap.xcodeproj
```

`project.yml` in this folder already declares the target, deployment target, and the two calendar usage-description strings. You'll still need to set your Team ID in Signing & Capabilities (or uncomment the `DEVELOPMENT_TEAM` line in `project.yml` first) before running on a device.

## Option C — GitHub Actions + Sideloadly (no Mac needed at all)

Worth naming the actual mechanism honestly: the iPhone can't compile Swift itself — there's no on-device compiler, no JIT for native code on iOS. What this option actually does is move the "needs a Mac" step into the cloud (GitHub's macOS runners, which come with Xcode preinstalled) and move the "needs Xcode" install step to a re-signing tool on your Windows machine instead.

1. Push this folder to a GitHub repo (delete the empty `.git` folder already in here first — a sandboxed attempt to set one up got blocked by file permissions and left an inert skeleton behind — then run `git init`, `git add -A`, `git commit -m "Phase 0"`, create a repo on github.com, and `git push`).
2. `.github/workflows/build-ipa.yml` is already in this folder. On every push to `main`, it spins up a macOS runner, installs XcodeGen, generates the Xcode project, and runs `xcodebuild` with code signing disabled — producing an unsigned `Cap.ipa`, uploaded as a downloadable workflow artifact. This is also where you debug the Foundation Models API names flagged above, with zero Mac required: push, open the failed Actions run, read the compiler error in the log, fix the Swift file, push again.
3. Download the `Cap-unsigned` artifact (a zip containing `Cap.ipa`) from the Actions run page onto your Windows machine.
4. Install [Sideloadly](https://sideloadly.io/) on Windows, plug your iPhone in via cable, drag `Cap.ipa` in, sign in with a free Apple ID, hit Start. On the phone: Settings → General → VPN & Device Management → trust the developer profile.
5. Free Apple ID signatures expire after 7 days — re-run Sideloadly with the same `.ipa` to refresh, or install [AltServer](https://altstore.io/) on the Windows machine to auto-refresh over Wi-Fi when your phone's on the same network. Free accounts also cap you at 3 sideloaded apps at once across all apps — only relevant if you're sideloading other things too.

If you'd rather skip the cable entirely going forward: a paid Apple Developer Program account ($99/year) lets the same CI pipeline upload straight to TestFlight instead of producing an unsigned `.ipa` — updates then show up as a tap-to-install in the TestFlight app, no USB, no 7-day expiry (90-day build validity, refreshed automatically every time CI uploads a new one). That needs signing certs and an App Store Connect API key added as GitHub secrets, which isn't set up here since it requires your own Apple Developer account — say the word if you go that route and want the workflow extended.

Borrowing your friend's Mac is still the fastest way to fix anything gnarlier than a one-line API rename, or to use Xcode's UI/debugger directly — keep it as the fallback, not necessarily the first move.

## First run checklist

Get a Canvas personal access token: in Canvas, go to Account → Settings → Approved Integrations → New Access Token. Run the app, go to the Today tab once to trigger the calendar permission prompt, then go to Settings and enter your Canvas domain (just the domain, e.g. `yourschool.instructure.com`, no `https://`) and the token. Switch to the Cap tab and ask it something like "what's due this week" — it should pull from both Calendar and Canvas automatically.

## What leaves the device, concretely

Canvas API calls go straight to your school's own Canvas domain, authenticated with your token — nothing routes through a third party. The Foundation Models calls never leave the phone at all. There is no analytics SDK, no crash reporter, no ad framework anywhere in this scaffold. The Canvas token and domain are stored in Keychain with `ThisDeviceOnly` accessibility, which explicitly opts them out of iCloud Keychain sync.
