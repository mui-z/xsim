# Repository Guidelines

## 必ず発言、途中の思考などは日本語ですること

## Project Structure & Modules
- Sources: `Sources/XSim` (entry), `Sources/XSimCLI` (app code)
  - Commands: CLI subcommands (`ListCommand.swift`, `StartCommand.swift`, ...)
  - Services: simctl integration (`SimulatorService.swift`)
  - Models: domain types and errors
- Tests: `Tests/XSimCLITests` (XCTest integration tests)
- Build config: `Package.swift`; formatting via `Makefile` target

## Build, Test, Run
- Build: `swift build` — builds all targets.
- Run CLI: `swift run xsim list` (e.g., `swift run xsim start "iPhone 15"`).
- Tests: `swift test` — runs XCTest; requires Xcode + `xcrun simctl` available.
- Format: `make format` — runs SwiftFormat across the repo.

## Coding Style & Naming
- Use Swift API Design Guidelines.
  - Types/Enums/Protocols: UpperCamelCase (`SimulatorService`).
  - Methods/Vars/func params: lowerCamelCase (`startSimulator`).
  - Files: One primary type per file; name matches type when reasonable.
- Indentation: 4 spaces; keep lines concise; prefer explicit access control.
- Formatting: Always run `make format` before pushing.

## Testing Guidelines
- Framework: XCTest; tests live under `Tests/XSimCLITests`.
- Style: Name tests descriptively (e.g., `testStartSimulatorWithValidDevice`).
- Scope: Prefer unit tests for Models; Services/Commands may be integration-style.
- Environment: Tests call `simctl`; ensure Xcode CLT installed and simulators available.

## Commit & Pull Requests
- Commits: Prefer Conventional Commits (`feat:`, `fix:`, `chore:`). Keep messages imperative and scoped.
- PRs: Include
  - What/Why summary and linked issues
  - CLI examples (e.g., output of `swift run xsim list`)
  - Risk/impact and manual test notes

## Environment & Tips
- Requires macOS 10.15+, Xcode CLT, and accessible `xcrun simctl`.
- When touching CLI behavior, update `README.md` examples if output changes.
- Keep Commands thin; put simctl logic in `SimulatorService` and domain in Models.
