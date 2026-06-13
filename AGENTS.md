# Repository Guidelines

## Project Structure & Module Organization

This is a SwiftUI iOS app with a widget extension. Main app code is in `Float/`: feature screens in `Features/`, app shell/state in `App/`, reusable UI/platform helpers in `Core/`, domain logic in `Domain/`, and SwiftData/backup/seed code in `Data/`. Widget code lives in `FloatWidgets/`. Assets are in `Float/Assets.xcassets/`; strings are in `Localizable.xcstrings`.

## Build, Test, and Development Commands

- `xcodebuild -list -project Float.xcodeproj`: lists available targets, configurations, and schemes.
- `xcodebuild -project Float.xcodeproj -scheme Float -destination 'platform=iOS Simulator,name=iPhone 16' build`: builds the app scheme for Simulator.
- `xcodebuild -project Float.xcodeproj -scheme FloatWidgets -destination 'platform=iOS Simulator,name=iPhone 16' build`: builds the widget extension.
- `xcodebuild -project Float.xcodeproj -scheme Float -destination 'platform=iOS Simulator,name=iPhone 16' test`: runs tests once a test target is added.

Use Xcode or Simulator for validation involving widgets, entitlements, Spotlight, notifications, app intents, or SwiftUI previews.

## Coding Style & Naming Conventions

Use existing Swift conventions: 4-space indentation, `PascalCase` types, `camelCase` members, and concise enum namespaces for pure helpers such as `RatioSplitCalculator`. Keep feature-specific UI inside `Float/Features/<Feature>/`; move reusable pieces to `Float/Core/Components/`. Prefer role suffixes already used here: `Item`, `Service`, `Repository`, `UseCase`, and `View`.

## Design Patterns & UI Rules

Route top-level flows through `MainTabView`, `NavigationStack`, and `AppState`; keep feature state local with `@State`, `@Query`, and targeted sheet item bindings where possible. Use `appState.themePalette`, `FloatTheme` radius constants, `.tint(...)`, `.floatBackground()`, and shared glass helpers instead of ad hoc colors or surfaces. Prefer `GlassCard`, `GlassButton`, `FloatIconBadge`, `SectionHeader`, `SummaryMetricTile`, `EmptyStateView`, and `FloatingAddButton` before creating new chrome. Format all money with `MoneyFormatter` and `.moneyStyle(...)`. New controls, icons, charts, and interaction states must match existing theme, tint, spacing, and accessibility patterns.

## Testing Guidelines

No test target is currently present. When adding tests, create app-aligned XCTest targets mirroring source ownership, for example `FloatTests/Domain/UseCases/RatioSplitCalculatorTests.swift`. Name tests after behavior, such as `testSplitsRemainderAcrossLeadingRatios()`. Prioritize pure domain logic, persistence edge cases, and date/money calculations.

## Commit & Pull Request Guidelines

Recent commits use short descriptive messages, often lowercase, such as `additional themes` and `filter sheet design update`. Keep commits focused. Pull requests should include a summary, testing performed, issue/context, and screenshots or recordings for UI changes. Call out schema, entitlement, localization, widget, or notification changes.

## Agent-Specific Instructions

Do not modify `DerivedData/` or user-local Xcode state. Check `git status` before editing and preserve unrelated work. Add every new hard-coded user-facing string to `Localizable.xcstrings` immediately; use `LocalizedStringResource` or `String(localized:)` for UI text.
