# Repository Guidelines

## Project Structure & Module Organization

Monitor iOS is a native SwiftUI client for alert.huyab.click (Odoo cron
monitor). Tabs: Cron (per-instance upcoming/late crons, 30 s auto-refresh),
Instance (add/edit/duplicate/reorder instances, test mail) and Settings (alert
delay, account, logout).

It follows the shared SwiftUI template used by the `*-ios` repos (chia-keo-ios,
notes-ios, monitor-ios): zero dependencies (no SPM, no CocoaPods), one app
target plus one XCTest target, and the same `Auth.swift` / `API.swift` /
`LoginView.swift` / `make-ipa.sh` layout.

- **Auth** (`Auth.swift`, `LoginView.swift`): the shared SSO at
  `auth.huyab.click` only accepts https `redirect_uri` values inside
  `huyab.click`, so `ASWebAuthenticationSession` with a custom scheme cannot be
  used. `LoginView` opens a `WKWebView`; once it lands back on
  `alert.huyab.click`, `WKHTTPCookieStore` reads the HttpOnly `huyab_sso` cookie
  and the JWT is stored in the Keychain. `SsoToken` never verifies the signature
  (the server does); it only reads `exp` to know when to stop calling the API.
- **API** (`API.swift`): DTOs are a projection of `server/src/index.ts` in the
  monitor repo (D1 rows, snake_case keys decoded with `convertFromSnakeCase`).
  Declare only fields the app actually uses — Codable ignores unknown keys, so
  new server fields never break the app. `ApiClient` targets
  `https://alert.huyab.click` and authenticates with `Authorization: Bearer
  <jwt>`. Tests inject a `URLSession` with a fake `URLProtocol`; the app uses
  `URLSession.shared`.

Folder structure:

```text
Monitor/                    # App target sources (SwiftUI, iOS 16+)
  MonitorApp.swift          #   `@main` app entry + `RootTabs`; `AuthStore` picks login vs tabs
  Auth.swift                #   `SsoToken` (reads JWT `exp` only), `Keychain`, `SsoCookie`, `AuthStore`
  LoginView.swift           #   WKWebView SSO login via auth.huyab.click
  API.swift                 #   Decodable DTOs + `ApiClient` (URLSession, Bearer auth, snake_case decoding)
  CronsView.swift           #   Cron tab: instance picker, search, late-only filter
  ConfigsView.swift         #   Instance tab: list, `ConfigDraft`, `ConfigForm`
  SettingsView.swift        #   Alert threshold, account, logout
  Assets.xcassets/          #   AppIcon + AppIconPreview
MonitorTests/               # XCTest unit target (@testable import Monitor)
  ApiClientTests.swift      #   `ApiClient` against `StubProtocol` (method/header/body/errors)
  DecodingTests.swift       #   DTO decoding from server JSON fixtures
  LogicTests.swift          #   `SsoToken`, `Keychain`, `SsoCookie`, `AuthStore`, Odoo time parsing
  SmokeRenderTests.swift    #   Renders screens with `RouterProtocol` faking the server
Monitor.xcodeproj/          # Hand-maintained project, shared scheme `Monitor`
brand/                      # Logo/icon SVG sources + rendered PNGs (`rsvg-convert`, see README)
make-ipa.sh                 # Unsigned Release build -> build/Monitor.ipa (Sideloadly signs)
.github/workflows/test.yml  # CI: xcodebuild test + coverage on macos-15
.swiftlint.yml              # Optional local SwiftLint config (not in CI)
build/                      # Local derived data + .ipa output (gitignored)
```

The `.xcodeproj` uses classic groups (not synchronized folders): every new
`.swift` file must be registered in `project.pbxproj` (file reference, build
file, group and the target's Sources phase), otherwise it is silently not
compiled.

## Build, Test, and Development Commands

- `open Monitor.xcodeproj`: open in Xcode; Cmd-R runs on the simulator.
- `xcodebuild -project Monitor.xcodeproj -scheme Monitor -sdk iphonesimulator build`:
  simulator build.
- `xcodebuild test -project Monitor.xcodeproj -scheme Monitor -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 11' -derivedDataPath build/dd`:
  run the XCTest suite (pick any installed iPhone simulator; CI picks one at
  runtime).
- `./make-ipa.sh`: unsigned Release build packaged as `build/Monitor.ipa`; drag
  it into Sideloadly to sign with a free Apple ID (re-sign every 7 days; the
  Keychain token survives re-signing). Build log: `/tmp/monitor-build.log`.
- `swiftlint`: optional local lint using `.swiftlint.yml` (not run in CI).

Local toolchain is Xcode 15.4; CI runs on `macos-15`.

## Coding Style & Naming Conventions

Swift 5, SwiftUI, deployment target iOS 16.0, iPhone only. Use only system
frameworks (SwiftUI, Foundation and WebKit); do not add third-party
dependencies. Four-space indentation. Types and SwiftUI views in PascalCase
(`HomeView`, `ApiClient`), server DTOs mostly prefixed with `Api`. Code comments
are Vietnamese without diacritics; user-facing strings are Vietnamese with
diacritics. Keep business logic on the server; put pure, testable helpers in
free functions or small types beside the view that uses them. No magic
strings/numbers: name them as constants (e.g. `ApiClient.origin`, `ssoOrigin`,
`appHost`).

## Testing Guidelines

Tests use XCTest in `MonitorTests/` with `@testable import Monitor`. Never hit
the real network: `ApiClientTests` uses `StubProtocol` on a dedicated
`URLSession`, and `SmokeRenderTests` registers `RouterProtocol` globally so
views using `URLSession.shared` render offline. When adding an endpoint, add a
decoding fixture in `DecodingTests` and a request-shape test in
`ApiClientTests`. CI (`.github/workflows/test.yml`) runs `xcodebuild test` with
code coverage and must be green before merging.

Logic checks live only in XCTest (there is no DEBUG startup self-check). There is
no browser e2e: this is a native app with no web surface; `SmokeRenderTests`
is the closest equivalent.

## Commit & Pull Request Guidelines

Use concise Conventional Commits; existing history uses short Vietnamese
subjects without diacritics, e.g. `feat: logo kawaii cho app`, `chore: script
dong goi .ipa khong ky cho Sideloadly`. Pull requests should include a short
summary, `xcodebuild test` results, and simulator screenshots for visible UI
changes.

## Ecosystem

See the [huyab.click ecosystem map](https://github.com/nguyenhuy158/kit/blob/main/docs/ECOSYSTEM.md) for how all personal repos connect.

- Kit packages: none (Swift, zero dependencies; kit is pnpm-only).
- Talks to: `monitor` API at https://alert.huyab.click (`huyab_sso` cookie +
  `Authorization: Bearer`), `sso` at https://auth.huyab.click for WebView login.

## Agent-Specific Instructions

Keep responses short and focused. If a requirement is unclear, ask before making
assumptions. Intentionally not implemented (see README): stats tab, deleting
instances and per-instance `alert_enabled` toggles — the server has no endpoints
for the last two. Do not fake them client-side. When the server contract
changes, update the DTOs here and the server repo together. Do not commit
`build/`, `.ipa` files or `xcuserdata/`.
