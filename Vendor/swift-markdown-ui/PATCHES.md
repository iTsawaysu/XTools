# Local patches

This directory vendors MarkdownUI for XTools. Keep these compatibility patches
when refreshing the upstream source:

- Qualify parser-facing `Document` references as `CommonMark.Document`. Newer
  macOS SDKs also export `SwiftUI.Document`, so an unqualified name is
  ambiguous. The root package currently documents this integration patch.
- Import `cmark_gfm` and `cmark_gfm_extensions` normally in
  `MarkdownParser.swift`. They are direct target dependencies and no cmark type
  appears in MarkdownUI's public declarations. `@_implementationOnly` requires
  unsupported experimental checking in this non-library-evolution package and
  conflicts with the private stored `cmark_node_type` values.
- Import `SwiftUI` explicitly in `FontPropertiesAttribute.swift`, which directly
  uses `SwiftUIAttributes` and SwiftUI attributed-string scopes.
- Do not declare `Theme` as `Sendable`. It stores `TextStyle` existentials and
  `BlockStyle` view-building closures that do not provide a Sendable contract.
  XTools uses themes through SwiftUI's UI-isolated environment; claiming
  cross-isolation safety would be incorrect.
- Keep every `BlockStyle` view-building closure `@MainActor` from the public
  initializer through stored type erasure and `makeBody`. The 18 `Theme` block
  builders, `View.markdownBlockStyle` overloads, and their deprecated forwarding
  overloads must preserve the same closure isolation. SwiftUI block rendering
  executes on the main actor; accepting a nonisolated escaping closure loses
  that contract and triggers Swift 6 isolated-conformance diagnostics when a
  theme builder uses UI-isolated modifiers. This does not make `Theme` or its
  synchronous text-style builders actor-isolated.

The vendored package remains on Swift tools 5.6. These patches do not enable
experimental compiler features, suppress diagnostics, or use unchecked
concurrency conformances. Keep the vendored package's macOS 12 declaration and
the root app's macOS 13 minimum unchanged; table rendering has its existing
macOS 13 availability guard.
