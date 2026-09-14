@testable import XTools
import Testing

struct SidebarCommandTests {
    @Test @MainActor func titleAndToggleTrackVisibleAndHiddenStates() {
        let viewModel = RootViewModel()

        #expect(viewModel.sidebarTogglePresentation == .hide)
        #expect(viewModel.sidebarTogglePresentation.title == "隐藏侧边栏")
        #expect(viewModel.sidebarTogglePresentation.help == "隐藏侧边栏（⌘B）")
        viewModel.toggleSidebar(reduceMotion: true)
        #expect(viewModel.sidebarVisibility == .hidden)
        #expect(viewModel.sidebarTogglePresentation == .show)
        #expect(viewModel.sidebarTogglePresentation.title == "显示侧边栏")
        #expect(viewModel.sidebarTogglePresentation.help == "显示侧边栏（⌘B）")

        viewModel.toggleSidebar(reduceMotion: true)
        #expect(viewModel.sidebarVisibility == .visible)
        #expect(viewModel.sidebarTogglePresentation == .hide)
    }
}
