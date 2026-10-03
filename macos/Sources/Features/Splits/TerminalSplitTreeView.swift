import SwiftUI

/// A single operation within the split tree.
///
/// Rather than binding the split tree (which is immutable), any mutable operations are
/// exposed via this enum to the embedder to handle.
enum TerminalSplitOperation {
    case resize(Resize)
    case drop(Drop)

    /// Show a tab of a pane that holds several.
    case activate(Ghostty.SurfaceView)

    /// Close one tab of a pane that holds several.
    case closeTab(Ghostty.SurfaceView)

    struct Resize {
        let node: SplitTree<Ghostty.SurfaceView>.Node
        let ratio: Double
    }

    struct Drop {
        /// What a drop moves.
        enum Scope {
            /// Only the dragged surface.
            case surface
            /// Every split of the dragged surface's tab.
            case tab
        }

        /// The surface being dragged.
        let payload: Ghostty.SurfaceView

        /// Whether the drop moves just the payload or its whole tab.
        let scope: Scope

        /// The surface it was dragged onto
        let destination: Ghostty.SurfaceView

        /// The zone it was dropped to determine how to split the destination.
        let zone: TerminalSplitDropZone
    }
}

struct TerminalSplitTreeView: View {
    let tree: SplitTree<Ghostty.SurfaceView>
    let action: (TerminalSplitOperation) -> Void

    var body: some View {
        if let node = tree.zoomed ?? tree.root {
            TerminalSplitSubtreeView(
                node: node,
                isRoot: node == tree.root,
                action: action)
            // This is necessary because we can't rely on SwiftUI's implicit
            // structural identity to detect changes to this view. Due to
            // the tree structure of splits it could result in bad behaviors.
            // See: https://github.com/ghostty-org/ghostty/issues/7546
            .id(node.structuralIdentity)
        }
    }
}

private struct TerminalSplitSubtreeView: View {
    @EnvironmentObject var ghostty: Ghostty.App

    let node: SplitTree<Ghostty.SurfaceView>.Node
    var isRoot: Bool = false
    let action: (TerminalSplitOperation) -> Void

    var body: some View {
        switch node {
        case .leaf(let leafView):
            TerminalSplitLeaf(surfaceView: leafView, isSplit: !isRoot, action: action)

        case .stack(let stack):
            TerminalSplitStack(stack: stack, isSplit: !isRoot, action: action)

        case .split(let split):
            let splitViewDirection: SplitViewDirection = switch split.direction {
            case .horizontal: .horizontal
            case .vertical: .vertical
            }

            SplitView(
                splitViewDirection,
                .init(get: {
                    CGFloat(split.ratio)
                }, set: {
                    action(.resize(.init(node: node, ratio: $0)))
                }),
                dividerColor: ghostty.config.splitDividerColor,
                resizeIncrements: .init(width: 1, height: 1),
                left: {
                    TerminalSplitSubtreeView(node: split.left, action: action)
                },
                right: {
                    TerminalSplitSubtreeView(node: split.right, action: action)
                },
                onEqualize: {
                    guard let surface = node.leftmostLeaf().surface else { return }
                    ghostty.splitEqualize(surface: surface)
                }
            )
        }
    }
}

/// A pane that holds several tabs: a strip of tabs above the surface that is showing.
private struct TerminalSplitStack: View {
    let stack: SplitTree<Ghostty.SurfaceView>.Node.Stack
    let isSplit: Bool
    let action: (TerminalSplitOperation) -> Void

    var body: some View {
        VStack(spacing: 0) {
            TerminalPaneTabStrip(stack: stack, action: action)
            // A representable keeps the NSView it first made, so showing another tab needs a new
            // identity here to swap the surface in.
            TerminalSplitLeaf(surfaceView: stack.active, isSplit: isSplit, action: action)
                .id(stack.active.id)
        }
    }
}

/// The tabs of a pane that holds several surfaces. Click a tab to show it, or its close button to
/// close it.
private struct TerminalPaneTabStrip: View {
    @EnvironmentObject var ghostty: Ghostty.App

    let stack: SplitTree<Ghostty.SurfaceView>.Node.Stack
    let action: (TerminalSplitOperation) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(stack.views, id: \.id) { view in
                TerminalPaneTab(
                    surface: view,
                    isActive: view === stack.active,
                    activate: { action(.activate(view)) },
                    close: { action(.closeTab(view)) })
            }
            Spacer(minLength: 0)
        }
        .frame(height: 24)
        .background(ghostty.config.backgroundColor.opacity(0.6))
        .background(Color.black.opacity(0.25))
    }
}

private struct TerminalPaneTab: View {
    @EnvironmentObject var ghostty: Ghostty.App
    @ObservedObject var surface: Ghostty.SurfaceView

    let isActive: Bool
    let activate: () -> Void
    let close: () -> Void

    @State private var isDragging: Bool = false
    @State private var isHovering: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            // The title is the tab's body: a click shows the tab and a drag moves it.
            Text(surface.title.isEmpty ? "Terminal" : surface.title)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(isActive ? .primary : .secondary)
                .frame(maxHeight: .infinity)
                .overlay {
                    Ghostty.SurfaceDragSource(
                        surfaceView: surface,
                        isDragging: $isDragging,
                        isHovering: $isHovering,
                        onClick: activate)
                }

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isActive || isHovering ? 1 : 0)
            .accessibilityLabel("Close tab")
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: 200, maxHeight: .infinity)
        .background(isActive ? ghostty.config.backgroundColor : Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

private struct TerminalSplitLeaf: View {
    let surfaceView: Ghostty.SurfaceView
    let isSplit: Bool
    let action: (TerminalSplitOperation) -> Void

    @State private var dropState: DropState = .idle
    @State private var isSelfDragging: Bool = false

    var body: some View {
        GeometryReader { geometry in
            Ghostty.InspectableSurface(
                surfaceView: surfaceView,
                isSplit: isSplit)
            .background {
                // If we're dragging ourself, we hide the entire drop zone. This makes
                // it so that a released drop animates back to its source properly
                // so it is a proper invalid drop zone.
                if !isSelfDragging {
                    Color.clear
                        .onDrop(of: [.ghosttySurfaceId], delegate: SplitDropDelegate(
                            dropState: $dropState,
                            viewSize: geometry.size,
                            destinationSurface: surfaceView,
                            action: action
                        ))
                }
            }
            .overlay {
                if !isSelfDragging, case .dropping(let zone) = dropState {
                    zone.overlay(in: geometry)
                        .allowsHitTesting(false)
                }
            }
            .onPreferenceChange(Ghostty.DraggingSurfaceKey.self) { value in
                isSelfDragging = value == surfaceView.id
                if isSelfDragging {
                    dropState = .idle
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Terminal pane")
        }
    }

    private enum DropState: Equatable {
        case idle
        case dropping(TerminalSplitDropZone)
    }

    private struct SplitDropDelegate: DropDelegate {
        @Binding var dropState: DropState
        let viewSize: CGSize
        let destinationSurface: Ghostty.SurfaceView
        let action: (TerminalSplitOperation) -> Void

        func validateDrop(info: DropInfo) -> Bool {
            info.hasItemsConforming(to: [.ghosttySurfaceId])
        }

        func dropEntered(info: DropInfo) {
            dropState = .dropping(.calculate(at: info.location, in: viewSize))
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            // For some reason dropUpdated is sent after performDrop is called
            // and we don't want to reset our drop zone to show it so we have
            // to guard on the state here.
            guard case .dropping = dropState else { return DropProposal(operation: .forbidden) }
            dropState = .dropping(.calculate(at: info.location, in: viewSize))
            return DropProposal(operation: .move)
        }

        func dropExited(info: DropInfo) {
            dropState = .idle
        }

        func performDrop(info: DropInfo) -> Bool {
            let zone = TerminalSplitDropZone.calculate(at: info.location, in: viewSize)
            let scope: TerminalSplitOperation.Drop.Scope = info.hasItemsConforming(to: [.ghosttyTabDrag]) ? .tab : .surface
            dropState = .idle

            // Load the dropped surface asynchronously using Transferable
            let providers = info.itemProviders(for: [.ghosttySurfaceId])
            guard let provider = providers.first else { return false }

            // Capture action before the async closure
            _ = provider.loadTransferable(type: Ghostty.SurfaceView.self) { [weak destinationSurface] result in
                switch result {
                case .success(let sourceSurface):
                    DispatchQueue.main.async {
                        // Dropping a surface on itself is for the controller to judge: it is a
                        // no-op unless the surface is a tab of a stack being split out.
                        guard let destinationSurface else { return }
                        action(.drop(.init(
                            payload: sourceSurface,
                            scope: scope,
                            destination: destinationSurface,
                            zone: zone)))
                    }

                case .failure:
                    break
                }
            }

            return true
        }
    }
}

enum TerminalSplitDropZone: String, Equatable {
    case top
    case bottom
    case left
    case right

    /// The middle of the pane: dropping here adds the surface as a tab of the pane rather than
    /// splitting it.
    case center

    /// How far in from every edge, as a fraction of the pane's width and height, the center zone
    /// begins. A quarter leaves the centre half of each dimension for adding a tab, and the
    /// outer quarter on each side for splitting.
    static let centerInset: Double = 0.25

    /// Determines which drop zone the cursor is in based on proximity to edges.
    ///
    /// Divides the view into four triangular regions by drawing diagonals from
    /// corner to corner. The drop zone is determined by which edge the cursor
    /// is closest to, creating natural triangular hit regions for each side. A cursor
    /// farther than `centerInset` from every edge is in the center zone instead.
    static func calculate(at point: CGPoint, in size: CGSize) -> TerminalSplitDropZone {
        let relX = point.x / size.width
        let relY = point.y / size.height

        let distToLeft = relX
        let distToRight = 1 - relX
        let distToTop = relY
        let distToBottom = 1 - relY

        let minDist = min(distToLeft, distToRight, distToTop, distToBottom)

        if minDist >= centerInset { return .center }
        if minDist == distToLeft { return .left }
        if minDist == distToRight { return .right }
        if minDist == distToTop { return .top }
        return .bottom
    }

    @ViewBuilder
    func overlay(in geometry: GeometryProxy) -> some View {
        let overlayColor = Color.accentColor.opacity(0.3)

        switch self {
        case .center:
            Rectangle()
                .fill(overlayColor)
        case .top:
            VStack(spacing: 0) {
                Rectangle()
                    .fill(overlayColor)
                    .frame(height: geometry.size.height / 2)
                Spacer()
            }
        case .bottom:
            VStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(overlayColor)
                    .frame(height: geometry.size.height / 2)
            }
        case .left:
            HStack(spacing: 0) {
                Rectangle()
                    .fill(overlayColor)
                    .frame(width: geometry.size.width / 2)
                Spacer()
            }
        case .right:
            HStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(overlayColor)
                    .frame(width: geometry.size.width / 2)
            }
        }
    }
}
