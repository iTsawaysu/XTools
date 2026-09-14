import AppKit
import XToolsCore
import QuartzCore
import SwiftUI

struct IndexEmojiCollectionSnapshot: Equatable {
    struct Item: Equatable, Identifiable {
        let id: String
        let glyph: String
        let helpText: String
    }

    struct Section: Equatable, Identifiable {
        let id: String
        let groupTitle: String?
        let subsectionTitle: String?
        let startsGroup: Bool
        let items: [Item]
    }

    let sections: [Section]

    var isSectioned: Bool {
        sections.count > 1 || sections.first?.subsectionTitle != nil
    }

    static func flat(entries: [EmojiEntry], tone: Unicode.Scalar?) -> Self {
        IndexEmojiCollectionSnapshot(sections: [
            Section(
                id: "flat",
                groupTitle: nil,
                subsectionTitle: nil,
                startsGroup: false,
                items: entries.map { entry in
                    let glyph = EmojiCatalog.apply(tone: tone, to: entry)
                    return Item(
                        id: entry.base,
                        glyph: glyph,
                        helpText: entry.helpText(for: glyph)
                    )
                }
            )
        ])
    }

    static func sectioned(sections: [EmojiSection], tone: Unicode.Scalar?) -> Self {
        var projected: [Section] = []
        for section in sections {
            for (subsectionIndex, subsection) in section.subsections.enumerated() {
                projected.append(
                    Section(
                        id: "\(section.name)/\(subsection.name)/\(subsectionIndex)",
                        groupTitle: subsectionIndex == 0 ? section.name : nil,
                        subsectionTitle: subsection.name,
                        startsGroup: subsectionIndex == 0,
                        items: subsection.entries.enumerated().map { index, entry in
                            let glyph = EmojiCatalog.apply(tone: tone, to: entry)
                            return Item(
                                id: "\(section.name)/\(subsection.name)/\(index)/\(entry.base)",
                                glyph: glyph,
                                helpText: entry.helpText(for: glyph)
                            )
                        }
                    )
                )
            }
        }
        return IndexEmojiCollectionSnapshot(sections: projected)
    }
}

struct IndexEmojiCollectionView: NSViewRepresentable {
    let snapshot: IndexEmojiCollectionSnapshot
    let scrollResetIdentity: String
    let reduceMotion: Bool
    let onCopy: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCopy: onCopy)
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeScrollView()
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(
            scrollView: scrollView,
            snapshot: snapshot,
            scrollResetIdentity: scrollResetIdentity,
            reduceMotion: reduceMotion,
            onCopy: onCopy
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource {
        private let collectionView = IndexEmojiCollectionDocumentView()
        private let layout = NSCollectionViewFlowLayout()
        private let flowLayoutDelegate = IndexEmojiCollectionFlowLayoutDelegate()
        private let pointerLocationProvider: IndexEmojiCollectionPointerLocationProvider
        private var currentSnapshot: IndexEmojiCollectionSnapshot?
        private var lastScrollResetIdentity: String?
        private var hoveredIndexPath: IndexPath?
        private var reduceMotion = false
        private var onCopy: @MainActor (String) -> Void

        init(
            onCopy: @escaping @MainActor (String) -> Void,
            pointerLocationProvider: @escaping IndexEmojiCollectionPointerLocationProvider = {
                $0.currentPointerLocation
            }
        ) {
            self.onCopy = onCopy
            self.pointerLocationProvider = pointerLocationProvider
            super.init()
            collectionView.onPointerLocationChange = { [weak self] point in
                self?.updatePointerLocation(point, animated: true)
            }
        }

        func makeScrollView() -> NSScrollView {
            layout.itemSize = NSSize(width: 46, height: 46)
            layout.minimumInteritemSpacing = 4
            layout.minimumLineSpacing = 4
            layout.sectionInset = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
            layout.headerReferenceSize = .zero
            layout.estimatedItemSize = .zero

            collectionView.collectionViewLayout = layout
            collectionView.dataSource = self
            collectionView.backgroundColors = [.clear]
            collectionView.isSelectable = false
            collectionView.register(
                IndexEmojiCollectionItem.self,
                forItemWithIdentifier: IndexEmojiCollectionItem.identifier
            )
            collectionView.register(
                IndexEmojiCollectionHeader.self,
                forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                withIdentifier: IndexEmojiCollectionHeader.identifier
            )

            let scrollView = IndexEmojiCollectionScrollView()
            scrollView.drawsBackground = false
            scrollView.contentView.drawsBackground = false
            scrollView.hasHorizontalScroller = false
            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = true
            scrollView.scrollerStyle = .overlay
            scrollView.horizontalScrollElasticity = .none
            scrollView.verticalScrollElasticity = .automatic
            scrollView.documentView = collectionView
            collectionView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
            scrollView.onViewportSizeChange = { [weak self, weak scrollView] in
                guard let self, let scrollView else { return }
                self.resizeCollectionView(in: scrollView)
                self.reconcilePointerLocation(animated: false)
            }
            scrollView.onViewportBoundsChange = { [weak self] in
                self?.reconcilePointerLocation(animated: true)
            }

            return scrollView
        }

        func update(
            scrollView: NSScrollView,
            snapshot: IndexEmojiCollectionSnapshot,
            scrollResetIdentity: String,
            reduceMotion: Bool,
            onCopy: @escaping @MainActor (String) -> Void
        ) {
            let motionChanged = self.reduceMotion != reduceMotion
            self.reduceMotion = reduceMotion
            self.onCopy = onCopy
            let changed = currentSnapshot != snapshot
            let shouldResetScroll = lastScrollResetIdentity != nil
                && lastScrollResetIdentity != scrollResetIdentity
            if changed {
                setHoveredIndexPath(nil, animated: false)
            }
            currentSnapshot = snapshot
            lastScrollResetIdentity = scrollResetIdentity
            configureLayout(for: snapshot)

            if changed || motionChanged {
                collectionView.reloadData()
                collectionView.collectionViewLayout?.invalidateLayout()
            }
            resizeCollectionView(in: scrollView)
            if shouldResetScroll, scrollView.contentView.bounds.minY > 0 {
                scrollView.contentView.scroll(to: .zero)
            }
            reconcilePointerLocation(animated: false)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func configureLayout(for snapshot: IndexEmojiCollectionSnapshot) {
            if snapshot.isSectioned {
                flowLayoutDelegate.snapshot = snapshot
                collectionView.delegate = flowLayoutDelegate
            } else {
                flowLayoutDelegate.snapshot = nil
                collectionView.delegate = nil
            }
        }

        private func resizeCollectionView(in scrollView: NSScrollView) {
            let viewportSize = scrollView.contentSize
            guard viewportSize.width > 0, viewportSize.height > 0 else { return }

            if abs(collectionView.frame.width - viewportSize.width) > 0.5 {
                collectionView.setFrameSize(
                    NSSize(width: viewportSize.width, height: max(collectionView.frame.height, viewportSize.height))
                )
                layout.invalidateLayout()
            }
            collectionView.layoutSubtreeIfNeeded()
            let contentHeight = layout.collectionViewContentSize.height
            collectionView.setFrameSize(
                NSSize(width: viewportSize.width, height: max(viewportSize.height, contentHeight))
            )
        }

        func debugUpdatePointerLocation(_ point: NSPoint?) {
            updatePointerLocation(point, animated: false)
        }

        var debugHoveredIndexPath: IndexPath? {
            hoveredIndexPath
        }

        var debugVisibleHoveredItemCount: Int {
            collectionView.visibleItems().compactMap { $0 as? IndexEmojiCollectionItem }
                .filter(\.isHovering)
                .count
        }

        private func updatePointerLocation(_ point: NSPoint?, animated: Bool) {
            let nextIndexPath = point.flatMap { collectionView.indexPathForItem(at: $0) }
            setHoveredIndexPath(nextIndexPath, animated: animated)
        }

        private func reconcilePointerLocation(animated: Bool) {
            updatePointerLocation(pointerLocationProvider(collectionView), animated: animated)
        }

        private func setHoveredIndexPath(_ nextIndexPath: IndexPath?, animated: Bool) {
            guard hoveredIndexPath != nextIndexPath else { return }

            if let hoveredIndexPath,
               let item = collectionView.item(at: hoveredIndexPath) as? IndexEmojiCollectionItem {
                item.setHovering(false, animated: animated)
            }
            hoveredIndexPath = nextIndexPath
            if let nextIndexPath,
               let item = collectionView.item(at: nextIndexPath) as? IndexEmojiCollectionItem {
                item.setHovering(true, animated: animated)
            }
        }

        func numberOfSections(in collectionView: NSCollectionView) -> Int {
            currentSnapshot?.sections.count ?? 0
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            numberOfItemsInSection section: Int
        ) -> Int {
            currentSnapshot?.sections[safe: section]?.items.count ?? 0
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            itemForRepresentedObjectAt indexPath: IndexPath
        ) -> NSCollectionViewItem {
            let item = collectionView.makeItem(
                withIdentifier: IndexEmojiCollectionItem.identifier,
                for: indexPath
            ) as! IndexEmojiCollectionItem
            if let model = currentSnapshot?.sections[safe: indexPath.section]?.items[safe: indexPath.item] {
                item.configure(
                    model: model,
                    isHovering: hoveredIndexPath == indexPath,
                    reduceMotion: reduceMotion,
                    onCopy: onCopy
                )
            }
            return item
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
            at indexPath: IndexPath
        ) -> NSView {
            let header = collectionView.makeSupplementaryView(
                ofKind: kind,
                withIdentifier: IndexEmojiCollectionHeader.identifier,
                for: indexPath
            ) as! IndexEmojiCollectionHeader
            if let section = currentSnapshot?.sections[safe: indexPath.section] {
                let isFirstSection = indexPath.section == 0
                header.configure(
                    groupTitle: section.groupTitle,
                    subsectionTitle: section.subsectionTitle,
                    topSpacing: IndexEmojiCollectionMetrics.headerTopSpacing(
                        for: section,
                        isFirstSection: isFirstSection
                    )
                )
            }
            return header
        }
    }
}

typealias IndexEmojiCollectionPointerLocationProvider = @MainActor (
    IndexEmojiCollectionDocumentView
) -> NSPoint?

@MainActor
final class IndexEmojiCollectionDocumentView: NSCollectionView {
    var onPointerLocationChange: ((NSPoint?) -> Void)?
    private var pointerTrackingArea: NSTrackingArea?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onPointerLocationChange?(currentPointerLocation)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        pointerTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        publishPointerLocation(from: event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        publishPointerLocation(from: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onPointerLocationChange?(nil)
    }

    var currentPointerLocation: NSPoint? {
        guard let window, window.isKeyWindow else { return nil }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return visibleRect.contains(point) ? point : nil
    }

    private func publishPointerLocation(from event: NSEvent) {
        onPointerLocationChange?(convert(event.locationInWindow, from: nil))
    }
}

@MainActor
private final class IndexEmojiCollectionFlowLayoutDelegate: NSObject, NSCollectionViewDelegateFlowLayout {
    var snapshot: IndexEmojiCollectionSnapshot?

    func collectionView(
        _ collectionView: NSCollectionView,
        layout collectionViewLayout: NSCollectionViewLayout,
        referenceSizeForHeaderInSection section: Int
    ) -> NSSize {
        guard let section = snapshot?.sections[safe: section] else { return .zero }

        return NSSize(
            width: 0,
            height: IndexEmojiCollectionMetrics.headerHeight(
                for: section,
                isFirstSection: section.id == snapshot?.sections.first?.id
            )
        )
    }
}

private enum IndexEmojiCollectionMetrics {
    static let groupTitleHeight: CGFloat = 17
    static let subsectionTitleHeight: CGFloat = 14
    static let groupToSubsectionSpacing: CGFloat = 10
    static let subsectionToGridSpacing: CGFloat = 6
    static let subsectionSpacing: CGFloat = 10
    static let groupSpacing: CGFloat = 16

    static func headerTopSpacing(
        for section: IndexEmojiCollectionSnapshot.Section,
        isFirstSection: Bool
    ) -> CGFloat {
        if section.groupTitle != nil {
            return section.startsGroup && !isFirstSection ? groupSpacing : 0
        }
        return subsectionSpacing
    }

    static func headerHeight(
        for section: IndexEmojiCollectionSnapshot.Section,
        isFirstSection: Bool
    ) -> CGFloat {
        headerTopSpacing(for: section, isFirstSection: isFirstSection)
            + (section.groupTitle == nil ? 0 : groupTitleHeight + groupToSubsectionSpacing)
            + (section.subsectionTitle == nil ? 0 : subsectionTitleHeight + subsectionToGridSpacing)
    }
}

@MainActor
private final class IndexEmojiCollectionScrollView: NSScrollView {
    var onViewportSizeChange: (() -> Void)?
    var onViewportBoundsChange: (() -> Void)?
    private var previousViewportSize = NSSize.zero

    override func layout() {
        super.layout()
        let viewportSize = contentSize
        guard viewportSize != previousViewportSize else { return }
        previousViewportSize = viewportSize
        onViewportSizeChange?()
    }

    override func reflectScrolledClipView(_ cView: NSClipView) {
        super.reflectScrolledClipView(cView)
        onViewportBoundsChange?()
    }
}

@MainActor
private final class IndexEmojiCollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("IndexEmojiCollectionItem")
    private let emojiButton = IndexEmojiCollectionButton()

    override func loadView() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(emojiButton)
        emojiButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            emojiButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            emojiButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            emojiButton.topAnchor.constraint(equalTo: container.topAnchor),
            emojiButton.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        view = container
    }

    func configure(
        model: IndexEmojiCollectionSnapshot.Item,
        isHovering: Bool,
        reduceMotion: Bool,
        onCopy: @escaping @MainActor (String) -> Void
    ) {
        emojiButton.configure(
            glyph: model.glyph,
            helpText: model.helpText,
            isHovering: isHovering,
            reduceMotion: reduceMotion,
            onCopy: onCopy
        )
    }

    var isHovering: Bool {
        emojiButton.isHovering
    }

    func setHovering(_ isHovering: Bool, animated: Bool) {
        emojiButton.setHovering(isHovering, animated: animated)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        emojiButton.reset()
    }
}

@MainActor
private final class IndexEmojiCollectionButton: NSButton {
    private(set) var isHovering = false
    private var reduceMotion = false
    private var onCopy: (@MainActor (String) -> Void)?

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            updateAppearance(animated: true)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAppearance()
    }

    private func configureAppearance() {
        setButtonType(.momentaryPushIn)
        isBordered = false
        bezelStyle = .regularSquare
        alignment = .center
        font = .systemFont(ofSize: 24)
        focusRingType = .default
        target = self
        action = #selector(handlePress)
        wantsLayer = true
        layer?.cornerRadius = ToolMetrics.CornerRadius.field
        layer?.cornerCurve = .continuous
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    func configure(
        glyph: String,
        helpText: String,
        isHovering: Bool,
        reduceMotion: Bool,
        onCopy: @escaping @MainActor (String) -> Void
    ) {
        title = glyph
        toolTip = helpText
        setAccessibilityRole(.button)
        setAccessibilityLabel(glyph)
        setAccessibilityHelp("按下以复制字符")
        self.isHovering = isHovering
        self.reduceMotion = reduceMotion
        self.onCopy = onCopy
        updateAppearance(animated: false)
    }

    func reset() {
        title = ""
        toolTip = nil
        setAccessibilityLabel(nil)
        setAccessibilityHelp(nil)
        onCopy = nil
        isHovering = false
        isHighlighted = false
        updateAppearance(animated: false)
    }

    func setHovering(_ isHovering: Bool, animated: Bool) {
        guard self.isHovering != isHovering else { return }
        self.isHovering = isHovering
        updateAppearance(animated: animated)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance(animated: false)
    }

    @objc private func handlePress() {
        onCopy?(title)
    }

    private func updateAppearance(animated: Bool) {
        let shouldAnimate = animated && !reduceMotion
        CATransaction.begin()
        CATransaction.setAnimationDuration(shouldAnimate ? ToolMotion.Duration.micro : 0)
        // 与 ToolMotion.Curve.smoothOut 同一条曲线(经 AppKit 桥)。
        let smooth = ToolMotion.Curve.smoothOutControlPoints
        CATransaction.setAnimationTimingFunction(
            CAMediaTimingFunction(
                controlPoints: Float(smooth.x1), Float(smooth.y1), Float(smooth.x2), Float(smooth.y2)
            )
        )
        let fillColor: NSColor = isHighlighted ? NSColor(ToolTheme.activeFill) : (
            isHovering ? NSColor(ToolTheme.hoverFill) : .clear
        )
        layer?.backgroundColor = fillColor.cgColor
        layer?.borderColor = (
            isHovering ? NSColor(ToolTheme.strongBorder) : .clear
        ).cgColor
        layer?.borderWidth = 0.5
        layer?.setAffineTransform(
            CGAffineTransform(
                scaleX: isHighlighted ? ToolMotion.Scale.pressed : 1,
                y: isHighlighted ? ToolMotion.Scale.pressed : 1
            )
        )
        CATransaction.commit()
    }
}

@MainActor
private final class IndexEmojiCollectionHeader: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("IndexEmojiCollectionHeader")

    private let groupLabel = NSTextField(labelWithString: "")
    private let subsectionLabel = NSTextField(labelWithString: "")
    private var topSpacing: CGFloat = 0

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        groupLabel.font = ToolTypography.AppKitMirror.bodyMedium()
        subsectionLabel.font = ToolTypography.AppKitMirror.caption()
        groupLabel.textColor = NSColor(ToolTheme.textPrimary)
        subsectionLabel.textColor = NSColor(ToolTheme.textSecondary)
        addSubview(groupLabel)
        addSubview(subsectionLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(groupTitle: String?, subsectionTitle: String?, topSpacing: CGFloat) {
        groupLabel.stringValue = groupTitle ?? ""
        subsectionLabel.stringValue = subsectionTitle ?? ""
        groupLabel.isHidden = groupTitle == nil
        subsectionLabel.isHidden = subsectionTitle == nil
        self.topSpacing = topSpacing
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let leftInset: CGFloat = 0
        let groupHeight: CGFloat = groupLabel.isHidden ? 0 : IndexEmojiCollectionMetrics.groupTitleHeight
        let groupSpacing: CGFloat = groupLabel.isHidden ? 0 : IndexEmojiCollectionMetrics.groupToSubsectionSpacing
        let subsectionHeight: CGFloat = subsectionLabel.isHidden ? 0 : IndexEmojiCollectionMetrics.subsectionTitleHeight
        groupLabel.frame = NSRect(x: leftInset, y: topSpacing, width: bounds.width, height: groupHeight)
        subsectionLabel.frame = NSRect(
            x: leftInset,
            y: topSpacing + groupHeight + groupSpacing,
            width: bounds.width,
            height: subsectionHeight
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
