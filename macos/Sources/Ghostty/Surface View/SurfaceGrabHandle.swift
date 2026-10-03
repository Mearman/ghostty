import SwiftUI

extension Ghostty {
    /// A grab handle overlay at the top of the surface for dragging a surface.
    struct SurfaceGrabHandle: View {
        // Size of the actual drag handle; the hover reveal region is larger.
        private static let handleSize = CGSize(width: 80, height: 12)

        // Reveal the handle anywhere within the top % of the pane height.
        private static let hoverHeightFactor: CGFloat = 0.2

        @ObservedObject var surfaceView: SurfaceView
        let dragHandle: Ghostty.Config.DragHandle

        @State private var isHovering: Bool = false
        @State private var isDragging: Bool = false

        /// Bumped when this surface's window becomes key, which is when its tab group may have
        /// changed (a tab was added, closed or selected). Reading it in `hasDropTarget` makes the
        /// grip re-evaluate then, since a window's tab group is not observable.
        @State private var windowChangeCount: Int = 0

        private var handleVisible: Bool {
            switch dragHandle {
            case .always:
                return true
            case .never:
                return false
            case .auto:
                break
            }
            // Handle should always be visible in non-fullscreen
            guard let window = surfaceView.window else { return true }
            guard window.styleMask.contains(.fullScreen) else { return true }

            // If fullscreen, only show the handle if we have splits
            guard let controller = window.windowController as? BaseTerminalController else { return false }
            return controller.surfaceTree.isSplit
        }

        private var ellipsisVisible: Bool {
            switch dragHandle {
            case .always:
                return true
            case .never:
                return false
            case .auto:
                break
            }
            // If the cursor isn't visible, never show the handle
            guard surfaceView.cursorVisible else { return false }
            // If we're hovering or actively dragging, always visible
            if isHovering || isDragging { return true }
            // Keep a dim grip showing while there is somewhere to drop, so the handle can be found.
            if hasDropTarget { return true }

            // Require our mouse location to be within the top area of the
            // surface.
            guard let mouseLocation = surfaceView.mouseLocationInSurface else { return false }
            return Self.isInHoverRegion(mouseLocation, in: surfaceView.bounds)
        }

        /// Whether another split or tab exists to drop this surface onto.
        private var hasDropTarget: Bool {
            _ = windowChangeCount
            guard let window = surfaceView.window else { return false }
            if (window.tabGroup?.windows.count ?? 1) > 1 { return true }
            guard let controller = window.windowController as? BaseTerminalController else { return false }
            return controller.surfaceTree.isSplit
        }

        var body: some View {
            if handleVisible {
                ZStack {
                    SurfaceDragSource(
                        surfaceView: surfaceView,
                        isDragging: $isDragging,
                        isHovering: $isHovering
                    )
                    .frame(width: Self.handleSize.width, height: Self.handleSize.height)
                    .contentShape(Rectangle())

                    if ellipsisVisible {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.primary.opacity(isHovering ? 0.8 : 0.3))
                            .offset(y: -3)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                    windowChangeCount += 1
                }
            }
        }

        /// The full-width hover band that reveals the drag handle.
        private static func hoverRect(in bounds: CGRect) -> CGRect {
            guard !bounds.isEmpty else { return .zero }

            let hoverHeight = min(bounds.height, max(handleSize.height, bounds.height * hoverHeightFactor))
            return CGRect(
                x: bounds.minX,
                y: bounds.maxY - hoverHeight,
                width: bounds.width,
                height: hoverHeight
            )
        }

        /// Returns true when the pointer is inside the top hover band.
        private static func isInHoverRegion(_ point: CGPoint, in bounds: CGRect) -> Bool {
            hoverRect(in: bounds).contains(point)
        }
    }
}
