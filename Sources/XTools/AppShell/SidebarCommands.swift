import SwiftUI
import XToolsDesign

enum SidebarTogglePresentation: Equatable {
    case show
    case hide

    var title: String {
        switch self {
        case .show:
            return "显示侧边栏"
        case .hide:
            return "隐藏侧边栏"
        }
    }

    var help: String {
        "\(title)（⌘B）"
    }

    static let accessibilityHint = "键盘快捷键 Command-B"
}

struct SidebarMenuCommands: Commands {
    @FocusedObject private var navigation: ShellNavigationModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some Commands {
        CommandGroup(before: .sidebar) {
            Button(navigation?.sidebarTogglePresentation.title ?? SidebarTogglePresentation.show.title) {
                navigation?.toggleSidebar(reduceMotion: reduceMotion)
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(navigation == nil)
        }
    }
}

struct CommandPaletteMenuCommands: Commands {
    @FocusedObject private var navigation: ShellNavigationModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("命令面板…") {
                withToolAnimation(ToolMotion.Preset.modal, reduceMotion: reduceMotion) {
                    navigation?.toggleCommandPalette()
                }
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(navigation == nil)
        }
    }
}

