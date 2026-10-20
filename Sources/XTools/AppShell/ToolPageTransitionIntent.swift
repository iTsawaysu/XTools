import XToolsDesign

/// How the page stage should choreograph the next arrival. The intent is
/// derived from the navigation cause, not chosen by individual pages.
enum ToolPageTransitionIntent: Equatable {
    /// Adjacent switch inside the same category, keyboard jumps and returns.
    case depth
    /// Cross-category move or a deep link: the two pages swap on one axis.
    case sharedAxis
    /// Command-palette launch: the incoming page expands from the trigger.
    case originBloom

    static func resolved(
        previousCategory: ToolCategoryID?,
        nextCategory: ToolCategoryID?
    ) -> ToolPageTransitionIntent {
        guard let previousCategory, let nextCategory, previousCategory != nextCategory else {
            return .depth
        }
        return .sharedAxis
    }
}
