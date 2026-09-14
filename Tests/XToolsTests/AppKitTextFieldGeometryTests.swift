import AppKit
@testable import XTools
import Testing

struct AppKitTextFieldGeometryTests {
    @Test @MainActor func contentInsetsKeepTextCenteredInsideTokenAndWideFieldBounds() {
        let insets = IndexTextFieldContentInsets(leading: 11, trailing: 11)

        let tokenBounds = NSRect(x: 0, y: 0, width: 54, height: 30)
        let tokenFrame = IndexTextFieldContentGeometry.textFrame(
            in: tokenBounds,
            insets: insets,
            lineHeight: 15
        )
        expectRect(tokenFrame, equals: NSRect(x: 11, y: 7.5, width: 32, height: 15))

        let wideBounds = NSRect(x: 0, y: 0, width: 892, height: 38)
        let wideFrame = IndexTextFieldContentGeometry.textFrame(
            in: wideBounds,
            insets: insets,
            lineHeight: 15
        )
        expectRect(wideFrame, equals: NSRect(x: 11, y: 11.5, width: 870, height: 15))
    }

    @Test @MainActor func narrowFieldsClampContentWidthWithoutChangingControlBounds() {
        let bounds = NSRect(x: 0, y: 0, width: 36, height: 30)
        let frame = IndexTextFieldContentGeometry.textFrame(
            in: bounds,
            insets: IndexTextFieldContentInsets(leading: 11, trailing: 11),
            lineHeight: 15
        )

        expectRect(frame, equals: NSRect(x: 11, y: 7.5, width: 14, height: 15))

        let overInsetFrame = IndexTextFieldContentGeometry.textFrame(
            in: bounds,
            insets: IndexTextFieldContentInsets(leading: 24, trailing: 24),
            lineHeight: 15
        )
        #expect(overInsetFrame.width == 0)
        #expect(overInsetFrame.midX == bounds.midX)
    }

    @Test @MainActor func plainAndSecureCellsUseTheSameContentGeometry() {
        let bounds = NSRect(x: 0, y: 0, width: 200, height: 38)
        let insets = IndexTextFieldContentInsets(leading: 11, trailing: 42)
        let plain = IndexPaddedTextFieldCell(textCell: "plain")
        let secure = IndexPaddedSecureTextFieldCell(textCell: "secure")

        configure(plain, insets: insets)
        configure(secure, insets: insets)

        expectRect(plain.textFrame(forBounds: bounds), equals: secure.textFrame(forBounds: bounds))
    }

    @Test @MainActor func paddedFieldsReceiveHitsAcrossTheirCompleteVisibleBounds() {
        let bounds = NSRect(x: 0, y: 0, width: 54, height: 30)
        let plain = IndexPaddedTextField(frame: bounds)
        let secure = IndexPaddedSecureTextField(frame: bounds)

        plain.contentInsets = IndexTextFieldContentInsets(leading: 11, trailing: 11)
        secure.contentInsets = IndexTextFieldContentInsets(leading: 11, trailing: 11)

        #expect(plain.cell is IndexPaddedTextFieldCell)
        #expect(secure.cell is IndexPaddedSecureTextFieldCell)

        for point in [
            NSPoint(x: 0.5, y: 0.5),
            NSPoint(x: 53.5, y: 0.5),
            NSPoint(x: 0.5, y: 29.5),
            NSPoint(x: 53.5, y: 29.5),
            NSPoint(x: 27, y: 15),
        ] {
            #expect(plain.hitTest(point) === plain)
            #expect(secure.hitTest(point) === secure)
        }
    }

    @Test @MainActor func fieldInsetsCanChangeAfterCreation() throws {
        let field = IndexPaddedTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 38))
        field.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        field.isBordered = false
        field.isBezeled = false
        let cell = try #require(field.cell as? IndexPaddedTextFieldCell)

        field.contentInsets = IndexTextFieldContentInsets(leading: 11, trailing: 11)
        expectRect(cell.textFrame(forBounds: field.bounds), equals: NSRect(x: 11, y: 11.5, width: 178, height: 15))

        field.contentInsets = IndexTextFieldContentInsets(leading: 11, trailing: 52)
        expectRect(cell.textFrame(forBounds: field.bounds), equals: NSRect(x: 11, y: 11.5, width: 137, height: 15))
    }

    @Test @MainActor func fieldEditorUsesTheSameInsetAndVerticalFrameAsTheCell() throws {
        _ = NSApplication.shared
        let field = IndexPaddedTextField(frame: NSRect(x: 0, y: 0, width: 54, height: 30))
        field.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        field.isBordered = false
        field.isBezeled = false
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.contentInsets = IndexTextFieldContentInsets(leading: 11, trailing: 20)
        field.stringValue = "1"

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(field)

        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor())
        let cell = try #require(field.cell as? IndexPaddedTextFieldCell)
        expectRect(editor.frame, equals: cell.textFrame(forBounds: field.bounds))
    }

    @Test @MainActor func controlledSegmentFieldReusesFullBoundsGeometryAndItsCustomEditor() throws {
        _ = NSApplication.shared
        let bounds = NSRect(x: 0, y: 0, width: 440, height: 38)
        let field = IndexControlledSegmentNSTextField(frame: bounds)
        field.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        field.isBordered = false
        field.isBezeled = false
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.contentInsets = IndexTextFieldContentInsets(leading: 11, trailing: 82)
        field.stringValue = "2026-07-15"

        let cell = try #require(field.cell as? IndexControlledSegmentTextFieldCell)
        expectRect(cell.textFrame(forBounds: bounds), equals: NSRect(x: 11, y: 11.5, width: 347, height: 15))

        for point in [
            NSPoint(x: 0.5, y: 0.5),
            NSPoint(x: 439.5, y: 0.5),
            NSPoint(x: 0.5, y: 37.5),
            NSPoint(x: 439.5, y: 37.5),
        ] {
            #expect(field.hitTest(point) === field)
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(field)

        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? IndexControlledSegmentFieldEditor)
        expectRect(editor.frame, equals: cell.textFrame(forBounds: field.bounds))
    }

    @MainActor
    private func configure(_ cell: NSTextFieldCell, insets: IndexTextFieldContentInsets) {
        cell.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        cell.isBordered = false
        cell.isBezeled = false
        (cell as? any IndexTextFieldContentInsetConfiguring)?.contentInsets = insets
    }

    private func expectRect(_ actual: NSRect, equals expected: NSRect) {
        #expect(abs(actual.minX - expected.minX) < 0.001)
        #expect(abs(actual.minY - expected.minY) < 0.001)
        #expect(abs(actual.width - expected.width) < 0.001)
        #expect(abs(actual.height - expected.height) < 0.001)
    }
}
