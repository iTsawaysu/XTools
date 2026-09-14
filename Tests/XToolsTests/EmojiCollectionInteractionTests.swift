import AppKit
@testable import XTools
import XToolsCore
import Testing

struct EmojiCollectionInteractionTests {
    @Test @MainActor func collectionOwnsOnePointerAreaInsteadOfTrackingEveryVisibleCell() throws {
        let coordinator = IndexEmojiCollectionView.Coordinator(onCopy: { _ in })
        let scrollView = coordinator.makeScrollView()
        scrollView.frame = NSRect(x: 0, y: 0, width: 900, height: 420)
        let entries = Array(EmojiCatalog.allEntries.prefix(200))

        coordinator.update(
            scrollView: scrollView,
            snapshot: .flat(entries: entries, tone: nil),
            scrollResetIdentity: "baseline",
            reduceMotion: false,
            onCopy: { _ in }
        )
        scrollView.layoutSubtreeIfNeeded()

        let collectionView = try #require(scrollView.documentView as? NSCollectionView)
        collectionView.updateTrackingAreas()
        collectionView.layoutSubtreeIfNeeded()

        let collectionPointerAreas = collectionView.trackingAreas.filter(Self.isPointerArea)
        let cellPointerAreas = collectionView.visibleItems().flatMap { item in
            Self.descendants(of: item.view).flatMap(\.trackingAreas)
        }.filter(Self.isPointerArea)

        #expect(collectionPointerAreas.count == 1)
        #expect(cellPointerAreas.isEmpty)
    }

    @Test @MainActor func pointerChangesKeepExactlyOneVisibleItemHovered() throws {
        let fixture = try Self.makeFixture()
        let firstPath = IndexPath(item: 0, section: 0)
        let secondPath = IndexPath(item: 1, section: 0)
        let firstPoint = try Self.center(of: firstPath, in: fixture.collectionView)
        let secondPoint = try Self.center(of: secondPath, in: fixture.collectionView)

        fixture.coordinator.debugUpdatePointerLocation(firstPoint)
        #expect(fixture.coordinator.debugHoveredIndexPath == firstPath)
        #expect(fixture.coordinator.debugVisibleHoveredItemCount == 1)

        fixture.coordinator.debugUpdatePointerLocation(secondPoint)
        #expect(fixture.coordinator.debugHoveredIndexPath == secondPath)
        #expect(fixture.coordinator.debugVisibleHoveredItemCount == 1)

        fixture.coordinator.debugUpdatePointerLocation(nil)
        #expect(fixture.coordinator.debugHoveredIndexPath == nil)
        #expect(fixture.coordinator.debugVisibleHoveredItemCount == 0)
    }

    @Test @MainActor func scrollReflectionReconcilesHoverToLatestPointerLocation() throws {
        let pointer = EmojiCollectionPointerLocationBox()
        let fixture = try Self.makeFixture(pointer: pointer)
        let beforePath = IndexPath(item: 0, section: 0)
        let afterPath = IndexPath(item: 36, section: 0)

        pointer.point = try Self.center(of: beforePath, in: fixture.collectionView)
        fixture.scrollView.reflectScrolledClipView(fixture.scrollView.contentView)
        #expect(fixture.coordinator.debugHoveredIndexPath == beforePath)
        #expect(fixture.coordinator.debugVisibleHoveredItemCount == 1)

        pointer.point = try Self.center(of: afterPath, in: fixture.collectionView)
        fixture.scrollView.reflectScrolledClipView(fixture.scrollView.contentView)
        #expect(fixture.coordinator.debugHoveredIndexPath == afterPath)
        #expect(fixture.coordinator.debugVisibleHoveredItemCount == 1)

        pointer.point = nil
        fixture.scrollView.reflectScrolledClipView(fixture.scrollView.contentView)
        #expect(fixture.coordinator.debugHoveredIndexPath == nil)
        #expect(fixture.coordinator.debugVisibleHoveredItemCount == 0)
    }

    @Test @MainActor func differentCategoryResetsScrolledViewportAcrossSnapshotShapes() throws {
        let smileGroup = try #require(EmojiCatalog.groups.first { $0.name == "笑脸与情感" })
        let specialGroup = try #require(
            EmojiCatalog.groups.first { $0.name == EmojiCatalog.specialSymbolGroupName }
        )
        let peopleGroup = try #require(EmojiCatalog.groups.first { $0.name == "人物与身体" })
        let fixture = try Self.makeFixture(
            snapshot: .flat(entries: smileGroup.entries, tone: nil),
            scrollResetIdentity: smileGroup.name
        )

        Self.scrollDown(fixture.scrollView)
        fixture.coordinator.update(
            scrollView: fixture.scrollView,
            snapshot: .sectioned(sections: specialGroup.sections, tone: nil),
            scrollResetIdentity: specialGroup.name,
            reduceMotion: false,
            onCopy: { _ in }
        )
        #expect(fixture.scrollView.contentView.bounds.minY == 0)

        Self.scrollDown(fixture.scrollView)
        fixture.coordinator.update(
            scrollView: fixture.scrollView,
            snapshot: .flat(entries: peopleGroup.entries, tone: nil),
            scrollResetIdentity: peopleGroup.name,
            reduceMotion: false,
            onCopy: { _ in }
        )
        #expect(fixture.scrollView.contentView.bounds.minY == 0)
    }

    @Test @MainActor func sameCategorySnapshotUpdatePreservesScrollPosition() throws {
        let peopleGroup = try #require(EmojiCatalog.groups.first { $0.name == "人物与身体" })
        let fixture = try Self.makeFixture(
            snapshot: .flat(entries: peopleGroup.entries, tone: nil),
            scrollResetIdentity: peopleGroup.name
        )
        Self.scrollDown(fixture.scrollView)
        let initialOffset = fixture.scrollView.contentView.bounds.minY
        let tone = try #require(EmojiCatalog.skinTones.dropFirst().first?.scalar)

        fixture.coordinator.update(
            scrollView: fixture.scrollView,
            snapshot: .flat(entries: peopleGroup.entries, tone: tone),
            scrollResetIdentity: peopleGroup.name,
            reduceMotion: false,
            onCopy: { _ in }
        )

        #expect(abs(fixture.scrollView.contentView.bounds.minY - initialOffset) < 0.5)
    }

    private static func isPointerArea(_ area: NSTrackingArea) -> Bool {
        area.options.contains(.mouseEnteredAndExited)
            && area.options.contains(.activeInKeyWindow)
            && area.options.contains(.inVisibleRect)
    }

    @MainActor
    private static func descendants(of view: NSView) -> [NSView] {
        view.subviews.reduce(into: [view]) { result, subview in
            result.append(contentsOf: descendants(of: subview))
        }
    }

    @MainActor
    private static func makeFixture(
        pointer: EmojiCollectionPointerLocationBox? = nil,
        snapshot: IndexEmojiCollectionSnapshot = .flat(
            entries: Array(EmojiCatalog.allEntries.prefix(200)),
            tone: nil
        ),
        scrollResetIdentity: String = "baseline"
    ) throws -> (
        coordinator: IndexEmojiCollectionView.Coordinator,
        scrollView: NSScrollView,
        collectionView: NSCollectionView
    ) {
        let coordinator = IndexEmojiCollectionView.Coordinator(
            onCopy: { _ in },
            pointerLocationProvider: { _ in pointer?.point }
        )
        let scrollView = coordinator.makeScrollView()
        scrollView.frame = NSRect(x: 0, y: 0, width: 900, height: 420)
        scrollView.layoutSubtreeIfNeeded()
        coordinator.update(
            scrollView: scrollView,
            snapshot: snapshot,
            scrollResetIdentity: scrollResetIdentity,
            reduceMotion: false,
            onCopy: { _ in }
        )
        scrollView.layoutSubtreeIfNeeded()
        let collectionView = try #require(scrollView.documentView as? NSCollectionView)
        collectionView.layoutSubtreeIfNeeded()
        return (coordinator, scrollView, collectionView)
    }

    @MainActor
    private static func scrollDown(_ scrollView: NSScrollView) {
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 120))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        #expect(scrollView.contentView.bounds.minY > 0)
    }

    @MainActor
    private static func center(of indexPath: IndexPath, in collectionView: NSCollectionView) throws -> NSPoint {
        let attributes = try #require(
            collectionView.collectionViewLayout?.layoutAttributesForItem(at: indexPath)
        )
        return NSPoint(x: attributes.frame.midX, y: attributes.frame.midY)
    }
}

@MainActor
private final class EmojiCollectionPointerLocationBox {
    var point: NSPoint?
}
