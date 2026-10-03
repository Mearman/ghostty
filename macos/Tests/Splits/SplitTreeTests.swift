import AppKit
import Testing
@testable import Ghostty

class MockView: NSView, Codable, Identifiable {
    let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    enum CodingKeys: CodingKey { case id }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        super.init(frame: .zero)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
    }
}

struct SplitTreeTests {
    /// Creates a two-view horizontal split tree (view1 | view2).
    static func makeHorizontalSplit() throws -> (SplitTree<MockView>, MockView, MockView) {
        let view1 = MockView()
        let view2 = MockView()
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: .right)
        return (tree, view1, view2)
    }

    /// Creates a two-view horizontal split tree (view1 | view2).
    private func makeHorizontalSplit() throws -> (SplitTree<MockView>, MockView, MockView) {
        try Self.makeHorizontalSplit()
    }

    // MARK: - Empty and Non-Empty

    @Test func emptyTreeIsEmpty() {
        let tree = SplitTree<MockView>()
        #expect(tree.isEmpty)
    }

    @Test func nonEmptyTreeIsNotEmpty() {
        let view1 = MockView()
        let tree = SplitTree<MockView>(view: view1)
        #expect(!tree.isEmpty)
    }

    @Test func isNotSplit() {
        let view1 = MockView()
        let tree = SplitTree<MockView>(view: view1)
        #expect(!tree.isSplit)
    }

    @Test func isSplit() throws {
        let (tree, _, _) = try makeHorizontalSplit()
        #expect(tree.isSplit)
    }

    // MARK: - Contains and Find

    @Test func treeContainsView() {
        let view = MockView()
        let tree = SplitTree<MockView>(view: view)
        #expect(tree.contains(.leaf(view: view)))
    }

    @Test func treeDoesNotContainView() {
        let view = MockView()
        let tree = SplitTree<MockView>()
        #expect(!tree.contains(.leaf(view: view)))
    }

    @Test func findsInsertedView() throws {
        let (tree, view1, _) = try makeHorizontalSplit()
        #expect((tree.find(id: view1.id) != nil))
    }

    @Test func doesNotFindUninsertedView() {
        let view1 = MockView()
        let view2 = MockView()
        let tree = SplitTree<MockView>(view: view1)
        #expect((tree.find(id: view2.id) == nil))
    }

    // MARK: - Removing and Replacing

    @Test func treeDoesNotContainRemovedView() throws {
        var (tree, view1, view2) = try makeHorizontalSplit()
        tree = tree.removing(.leaf(view: view1))
        #expect(!tree.contains(.leaf(view: view1)))
        #expect(tree.contains(.leaf(view: view2)))
    }

    @Test func removingNonexistentNodeLeavesTreeUnchanged() {
        let view1 = MockView()
        let view2 = MockView()
        let tree = SplitTree<MockView>(view: view1)
        let result = tree.removing(.leaf(view: view2))
        #expect(result.contains(.leaf(view: view1)))
        #expect(!result.isEmpty)
    }

    @Test func replacingViewShouldRemoveAndInsertView() throws {
        let view1 = MockView()
        let view2 = MockView()
        let view3 = MockView()
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: .right)
        #expect(tree.contains(.leaf(view: view2)))
        let result = try tree.replacing(node: .leaf(view: view2), with: .leaf(view: view3))
        #expect(result.contains(.leaf(view: view1)))
        #expect(!result.contains(.leaf(view: view2)))
        #expect(result.contains(.leaf(view: view3)))
    }

    @Test func replacingViewWithItselfShouldBeAValidOperation() throws {
        let (tree, view1, view2) = try makeHorizontalSplit()
        let result = try tree.replacing(node: .leaf(view: view2), with: .leaf(view: view2))
        #expect(result.contains(.leaf(view: view1)))
        #expect(result.contains(.leaf(view: view2)))
    }

    // MARK: - Inserting Subtrees

    @Test func insertingSubtreeToTheRightKeepsItsStructureAfterTheTarget() throws {
        let (moving, view2, view3) = try Self.makeHorizontalSplit()
        let view1 = MockView()
        let tree = SplitTree<MockView>(view: view1)

        let result = try tree.inserting(node: #require(moving.root), at: view1, direction: .right)

        #expect(Array(result) == [view1, view2, view3])
        guard case .split(let outer) = result.root, case .split(let inner) = outer.right else {
            Issue.record("expected the subtree to stay a split on the right of the target")
            return
        }
        #expect(outer.direction == .horizontal)
        #expect(inner.left == .leaf(view: view2))
        #expect(inner.right == .leaf(view: view3))
    }

    @Test func insertingSubtreeToTheLeftPlacesItBeforeTheTarget() throws {
        let (moving, view2, view3) = try Self.makeHorizontalSplit()
        let view1 = MockView()
        let tree = SplitTree<MockView>(view: view1)

        let result = try tree.inserting(node: #require(moving.root), at: view1, direction: .left)

        #expect(Array(result) == [view2, view3, view1])
    }

    @Test func insertingSubtreeVerticallyUsesAVerticalSplit() throws {
        let (moving, _, _) = try Self.makeHorizontalSplit()
        let view1 = MockView()
        let tree = SplitTree<MockView>(view: view1)

        let result = try tree.inserting(node: #require(moving.root), at: view1, direction: .down)

        guard case .split(let outer) = result.root else {
            Issue.record("expected a split root")
            return
        }
        #expect(outer.direction == .vertical)
    }

    @Test func insertingSubtreeAtMissingViewThrows() throws {
        let (moving, _, _) = try Self.makeHorizontalSplit()
        let tree = SplitTree<MockView>(view: MockView())

        do {
            _ = try tree.inserting(node: #require(moving.root), at: MockView(), direction: .right)
            Issue.record("expected viewNotFound")
        } catch let error as SplitTree<MockView>.SplitError {
            #expect(error == .viewNotFound)
        }
    }

    @Test func insertingSubtreeResetsZoom() throws {
        let (moving, _, _) = try Self.makeHorizontalSplit()
        let (zoomedTree, view1, _) = try Self.makeHorizontalSplit()
        let zoomed = SplitTree<MockView>(root: zoomedTree.root, zoomed: zoomedTree.root?.node(view: view1))

        let result = try zoomed.inserting(node: #require(moving.root), at: view1, direction: .right)

        #expect(result.zoomed == nil)
    }

    // MARK: - Stacks

    /// Builds (view1 | view2) and stacks `view3` onto view1, so the left pane holds view1 and
    /// view3 with view3 showing.
    private func makeStackedSplit() throws -> StackedSplit {
        let (tree, view1, view2) = try makeHorizontalSplit()
        let view3 = MockView()
        return StackedSplit(tree: try tree.stacking([view3], onto: view1), view1: view1, view2: view2, view3: view3)
    }

    private struct StackedSplit {
        let tree: SplitTree<MockView>
        let view1: MockView
        let view2: MockView
        let view3: MockView
    }

    private func stack(of view: MockView, in tree: SplitTree<MockView>) -> SplitTree<MockView>.Node.Stack? {
        if case .stack(let stack) = tree.root?.node(view: view) { stack } else { nil }
    }

    @Test func stackingAddsATabToThePaneAndKeepsTheSplit() throws {
        let fixture = try makeStackedSplit()
        let tree = fixture.tree
        let view1 = fixture.view1
        let view2 = fixture.view2
        let view3 = fixture.view3

        #expect(tree.isSplit)
        #expect(Array(tree) == [view1, view3, view2])
        let stack = try #require(stack(of: view3, in: tree))
        #expect(stack.views == [view1, view3])
        #expect(stack.active === view3)
        // The other pane is untouched.
        #expect(tree.root?.node(view: view2) == .leaf(view: view2))
    }

    @Test func stackingPlacesNewTabsAfterTheShowingOne() throws {
        let fixture = try makeStackedSplit()
        let tree = fixture.tree
        let view1 = fixture.view1
        let view3 = fixture.view3
        let view4 = MockView()

        let result = try tree.stacking([view4], onto: view1)

        let stack = try #require(stack(of: view4, in: result))
        #expect(stack.views == [view1, view3, view4])
        #expect(stack.active === view4)
    }

    @Test func stackingSeveralTabsKeepsTheirOrderAndShowsTheFirst() throws {
        let (tree, view1, _) = try makeHorizontalSplit()
        let view3 = MockView()
        let view4 = MockView()

        let result = try tree.stacking([view3, view4], onto: view1)

        let stack = try #require(stack(of: view1, in: result))
        #expect(stack.views == [view1, view3, view4])
        #expect(stack.active === view3)
    }

    @Test func stackingOntoAMissingViewThrows() throws {
        let (tree, _, _) = try makeHorizontalSplit()

        #expect(throws: (any Error).self) {
            _ = try tree.stacking([MockView()], onto: MockView())
        }
    }

    @Test func nodeForAViewInAStackIsTheWholePane() throws {
        let fixture = try makeStackedSplit()
        let tree = fixture.tree
        let view1 = fixture.view1
        let view3 = fixture.view3

        let forView1 = try #require(tree.root?.node(view: view1))
        let forView3 = try #require(tree.root?.node(view: view3))

        #expect(forView1 == forView3)
        #expect(tree.contains(forView1))
        #expect(tree.find(id: view1.id) == forView1)
    }

    @Test func activatingChangesTheShowingTabOnly() throws {
        let fixture = try makeStackedSplit()
        let tree = fixture.tree
        let view1 = fixture.view1
        let view3 = fixture.view3

        let result = try tree.activating(view: view1)

        let stack = try #require(stack(of: view1, in: result))
        #expect(stack.active === view1)
        #expect(stack.views == [view1, view3])
        #expect(Array(result) == Array(tree))
    }

    @Test func activatingALeafOrTheShowingTabLeavesTheTreeUnchanged() throws {
        let fixture = try makeStackedSplit()
        let tree = fixture.tree
        let view2 = fixture.view2
        let view3 = fixture.view3

        #expect(try tree.activating(view: view2).root == tree.root)
        #expect(try tree.activating(view: view3).root == tree.root)
    }

    @Test func removingAViewFromAStackKeepsTheOthers() throws {
        let fixture = try makeStackedSplit()
        let tree = fixture.tree
        let view1 = fixture.view1
        let view3 = fixture.view3
        let view4 = MockView()
        let three = try tree.stacking([view4], onto: view1)

        let result = three.removing(view: view3)

        let stack = try #require(stack(of: view4, in: result))
        #expect(stack.views == [view1, view4])
        #expect(stack.active === view4)
    }

    @Test func removingTheShowingTabShowsTheOneThatTakesItsPlace() throws {
        let fixture = try makeStackedSplit()
        let tree = fixture.tree
        let view1 = fixture.view1
        let view3 = fixture.view3
        let view4 = MockView()
        // Tabs are view1, view3, view4 with view4 showing. Show view3 and remove it.
        let three = try tree.stacking([view4], onto: view1).activating(view: view3)

        let result = three.removing(view: view3)

        let stack = try #require(stack(of: view4, in: result))
        #expect(stack.views == [view1, view4])
        #expect(stack.active === view4)
    }

    @Test func removingAnInactiveTabKeepsTheShowingOne() throws {
        let fixture = try makeStackedSplit()
        let tree = fixture.tree
        let view1 = fixture.view1
        let view3 = fixture.view3

        let result = tree.removing(view: view1)

        // One tab is left, so the pane is a plain leaf again.
        #expect(result.root?.node(view: view3) == .leaf(view: view3))
        #expect(!result.contains(view1))
    }

    @Test func removingTheLastTabOfAStackLeavesALeaf() throws {
        let fixture = try makeStackedSplit()
        let tree = fixture.tree
        let view1 = fixture.view1
        let view2 = fixture.view2
        let view3 = fixture.view3

        let result = tree.removing(view: view3)

        #expect(result.root?.node(view: view1) == .leaf(view: view1))
        #expect(Array(result) == [view1, view2])
    }

    @Test func removingALoneViewRemovesItsPane() throws {
        let fixture = try makeStackedSplit()
        let tree = fixture.tree
        let view1 = fixture.view1
        let view2 = fixture.view2
        let view3 = fixture.view3

        let result = tree.removing(view: view2)

        #expect(Array(result) == [view1, view3])
        #expect(!result.isSplit)
    }

    @Test func removingTheStackNodeRemovesEveryTab() throws {
        let fixture = try makeStackedSplit()
        let tree = fixture.tree
        let view1 = fixture.view1
        let view2 = fixture.view2
        let view3 = fixture.view3
        let node = try #require(tree.root?.node(view: view1))

        let result = tree.removing(node)

        #expect(Array(result) == [view2])
        #expect(!result.contains(view1) && !result.contains(view3))
    }

    @Test func insertingAtAViewInAStackKeepsTheStackWhole() throws {
        let fixture = try makeStackedSplit()
        let tree = fixture.tree
        let view1 = fixture.view1
        let view3 = fixture.view3
        let view4 = MockView()

        let result = try tree.inserting(view: view4, at: view3, direction: .down)

        let stack = try #require(stack(of: view1, in: result))
        #expect(stack.views == [view1, view3])
        #expect(result.contains(view4))
    }

    @Test func focusNextAndPreviousVisitEveryTabIncludingHiddenOnes() throws {
        let fixture = try makeStackedSplit()
        let tree = fixture.tree
        let view1 = fixture.view1
        let view2 = fixture.view2
        let view3 = fixture.view3
        let node = try #require(tree.root?.node(view: view3))

        // Leaves in order are view1, view3, view2 and view3 is showing.
        #expect(tree.focusTarget(for: .next, from: node) === view2)
        #expect(tree.focusTarget(for: .previous, from: node) === view1)
    }

    @Test func spatialFocusTreatsAStackAsOnePane() throws {
        let fixture = try makeStackedSplit()
        let tree = fixture.tree
        let view2 = fixture.view2
        let view3 = fixture.view3
        let node = try #require(tree.root?.node(view: view2))

        // Moving left from view2 lands on the stack's showing tab.
        #expect(tree.focusTarget(for: .spatial(.left), from: node) === view3)
    }

    @Test func equalizedTreatsAStackAsOnePane() throws {
        let fixture = try makeStackedSplit()
        let tree = fixture.tree

        let result = tree.equalized()

        guard case .split(let split) = result.root else {
            Issue.record("expected a split root")
            return
        }
        #expect(split.ratio == 0.5)
    }

    @Test func zoomFollowsAPaneWhoseTabChanges() throws {
        let fixture = try makeStackedSplit()
        let tree = fixture.tree
        let view1 = fixture.view1
        let view3 = fixture.view3
        let zoomed = SplitTree<MockView>(root: tree.root, zoomed: tree.root)

        let result = try zoomed.activating(view: view1)

        let zoomedNode = try #require(result.zoomed)
        guard case .split = zoomedNode else {
            Issue.record("the zoomed node should still be the split")
            return
        }
        let stack = try #require(stack(of: view3, in: .init(root: zoomedNode, zoomed: nil)))
        #expect(stack.active === view1)
    }

    @Test func structuralIdentityIgnoresTheShowingTabButNotMembership() throws {
        let fixture = try makeStackedSplit()
        let tree = fixture.tree
        let view1 = fixture.view1
        let view3 = fixture.view3
        let switched = try tree.activating(view: view1)
        let view4 = MockView()
        let grown = try tree.stacking([view4], onto: view1)

        #expect(tree.structuralIdentity == switched.structuralIdentity)
        #expect(tree.structuralIdentity != grown.structuralIdentity)
        #expect(tree.structuralIdentity.hashValue == switched.structuralIdentity.hashValue)
        _ = view3
    }

    @Test func encodingAndDecodingPreservesAStack() throws {
        let fixture = try makeStackedSplit()
        let tree = fixture.tree
        let view1 = fixture.view1
        let view3 = fixture.view3
        let data = try JSONEncoder().encode(tree)

        let decoded = try JSONDecoder().decode(SplitTree<MockView>.self, from: data)

        // Decoding makes new view instances, so find the pane by id.
        guard case .stack(let stack) = decoded.find(id: view3.id) else {
            Issue.record("expected the decoded pane to be a stack")
            return
        }
        #expect(stack.views.map(\.id) == [view1.id, view3.id])
        #expect(stack.active.id == view3.id)
    }

    @Test func aVersionOneTreeStillDecodes() throws {
        let (tree, view1, view2) = try makeHorizontalSplit()
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(tree)) as? [String: Any])
        object["version"] = 1
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(SplitTree<MockView>.self, from: data)

        #expect(decoded.map(\.id) == [view1.id, view2.id])
    }

    // MARK: - Focus Target

    @Test func focusTargetOnEmptyTreeReturnsNil() {
        let tree = SplitTree<MockView>()
        let view = MockView()
        let target = tree.focusTarget(for: .next, from: .leaf(view: view))
        #expect(target == nil)
    }

    @Test func focusTargetShouldFindNextFocusedNode() throws {
        let (tree, view1, view2) = try makeHorizontalSplit()
        let target = tree.focusTarget(for: .next, from: .leaf(view: view1))
        #expect(target === view2)
    }

    @Test func focusTargetShouldFindItselfWhenOnlyView() throws {
        let view1 = MockView()
        let tree = SplitTree<MockView>(view: view1)

        let target = tree.focusTarget(for: .next, from: .leaf(view: view1))
        #expect(target === view1)
    }

    // When there's no next view, wraps around to the first
    @Test func focusTargetShouldHandleWrappingForNextNode() throws {
        let (tree, view1, view2) = try makeHorizontalSplit()
        let target = tree.focusTarget(for: .next, from: .leaf(view: view2))
        #expect(target === view1)
    }

    @Test func focusTargetShouldFindPreviousFocusedNode() throws {
        let (tree, view1, view2) = try makeHorizontalSplit()
        let target = tree.focusTarget(for: .previous, from: .leaf(view: view2))
        #expect(target === view1)
    }

    @Test func focusTargetShouldFindSpatialFocusedNode() throws {
        let (tree, view1, view2) = try makeHorizontalSplit()
        let target = tree.focusTarget(for: .spatial(.left), from: .leaf(view: view2))
        #expect(target === view1)
    }

    // MARK: - Equalized

    @Test func equalizedAdjustsRatioByLeafCount() throws {
        let view1 = MockView()
        let view2 = MockView()
        let view3 = MockView()
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: .right)
        tree = try tree.inserting(view: view3, at: view2, direction: .right)

        guard case .split(let before) = tree.root else {
            Issue.record("unexpected node type")
            return
        }
        #expect(abs(before.ratio - 0.5) < 0.001)

        let equalized = tree.equalized()

        if case .split(let s) = equalized.root {
            #expect(abs(s.ratio - 1.0/3.0) < 0.001)
        }
    }

    // MARK: - Resizing

    @Test(arguments: [
        // (resizeDirection, insertDirection, bounds, pixels, expectedRatio)
        (SplitTree<MockView>.Spatial.Direction.right, SplitTree<MockView>.NewDirection.right,
         CGRect(x: 0, y: 0, width: 1000, height: 500), UInt16(100), 0.6),
        (.left, .right,
         CGRect(x: 0, y: 0, width: 1000, height: 500), UInt16(50), 0.45),
        (.down, .down,
         CGRect(x: 0, y: 0, width: 500, height: 1000), UInt16(200), 0.7),
        (.up, .down,
         CGRect(x: 0, y: 0, width: 500, height: 1000), UInt16(50), 0.45),
    ])
    func resizingAdjustsRatio(
        resizeDirection: SplitTree<MockView>.Spatial.Direction,
        insertDirection: SplitTree<MockView>.NewDirection,
        bounds: CGRect,
        pixels: UInt16,
        expectedRatio: Double
    ) throws {
        let view1 = MockView()
        let view2 = MockView()
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: insertDirection)

        let resized = try tree.resizing(node: .leaf(view: view1), by: pixels, in: resizeDirection, with: bounds)

        guard case .split(let s) = resized.root else {
            Issue.record("unexpected node type")
            return
        }
        #expect(abs(s.ratio - expectedRatio) < 0.001)
    }

    // MARK: - Codable

    @Test func encodingAndDecodingPreservesTree() throws {
        let (tree, view1, view2) = try makeHorizontalSplit()
        let data = try JSONEncoder().encode(tree)
        let decoded = try JSONDecoder().decode(SplitTree<MockView>.self, from: data)
        #expect(decoded.find(id: view1.id) != nil)
        #expect(decoded.find(id: view2.id) != nil)
        #expect(decoded.isSplit)
    }

    @Test func encodingAndDecodingPreservesZoomedPath() throws {
        let (tree, _, view2) = try makeHorizontalSplit()
        let treeWithZoomed = SplitTree<MockView>(root: tree.root, zoomed: .leaf(view: view2))

        let data = try JSONEncoder().encode(treeWithZoomed)
        let decoded = try JSONDecoder().decode(SplitTree<MockView>.self, from: data)

        #expect(decoded.zoomed != nil)
        if case .leaf(let zoomedView) = decoded.zoomed! {
            #expect(zoomedView.id == view2.id)
        } else {
            Issue.record("unexpected node type")
        }
    }

    // MARK: - Collection Conformance

    @Test func treeIteratesLeavesInOrder() throws {
        let view1 = MockView()
        let view2 = MockView()
        let view3 = MockView()
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: .right)
        tree = try tree.inserting(view: view3, at: view2, direction: .right)

        #expect(tree.startIndex == 0)
        #expect(tree.endIndex == 3)
        #expect(tree.index(after: 0) == 1)

        #expect(tree[0] === view1)
        #expect(tree[1] === view2)
        #expect(tree[2] === view3)

        var ids: [UUID] = []
        for view in tree {
            ids.append(view.id)
        }
        #expect(ids == [view1.id, view2.id, view3.id])
    }

    @Test func emptyTreeCollectionProperties() {
        let tree = SplitTree<MockView>()

        #expect(tree.startIndex == 0)
        #expect(tree.endIndex == 0)

        var count = 0
        for _ in tree {
            count += 1
        }
        #expect(count == 0)
    }

    // MARK: - Structural Identity

    @Test func structuralIdentityIsReflexive() throws {
        let (tree, _, _) = try makeHorizontalSplit()
        #expect(tree.structuralIdentity == tree.structuralIdentity)
    }

    @Test func structuralIdentityComparesShapeNotRatio() throws {
        let (tree, view1, _) = try makeHorizontalSplit()

        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let resized = try tree.resizing(node: .leaf(view: view1), by: 100, in: .right, with: bounds)
        #expect(tree.structuralIdentity == resized.structuralIdentity)
    }

    @Test func structuralIdentityForDifferentStructures() throws {
        let view1 = MockView()
        let view2 = MockView()
        let view3 = MockView()
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: .right)

        let expanded = try tree.inserting(view: view3, at: view2, direction: .down)
        #expect(tree.structuralIdentity != expanded.structuralIdentity)
    }

    @Test func structuralIdentityIdentifiesDifferentOrdersShapes() throws {
        let (tree, _, _) = try makeHorizontalSplit()

        let (otherTree, _, _) = try makeHorizontalSplit()
        #expect(tree.structuralIdentity != otherTree.structuralIdentity)
    }

    // MARK: - View Bounds

    @Test func viewBoundsReturnsLeafViewSize() {
        let view1 = MockView()
        view1.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
        let tree = SplitTree<MockView>(view: view1)

        let bounds = tree.viewBounds()
        #expect(bounds.width == 500)
        #expect(bounds.height == 300)
    }

    @Test func viewBoundsReturnsZeroForEmptyTree() {
        let tree = SplitTree<MockView>()
        let bounds = tree.viewBounds()

        #expect(bounds.width == 0)
        #expect(bounds.height == 0)
    }

    @Test func viewBoundsHorizontalSplit() throws {
        let view1 = MockView()
        let view2 = MockView()
        view1.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        view2.frame = NSRect(x: 0, y: 0, width: 200, height: 500)
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: .right)

        let bounds = tree.viewBounds()
        #expect(bounds.width == 600)
        #expect(bounds.height == 500)
    }

    @Test func viewBoundsVerticalSplit() throws {
        let view1 = MockView()
        let view2 = MockView()
        view1.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        view2.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: .down)

        let bounds = tree.viewBounds()
        #expect(bounds.width == 500)
        #expect(bounds.height == 600)
    }

    // MARK: - Node

    @Test func nodeFindsLeaf() {
        let view1 = MockView()
        let tree = SplitTree<MockView>(view: view1)

        let node = tree.root?.node(view: view1)
        #expect(node != nil)
        #expect(node == .leaf(view: view1))
    }

    @Test func nodeFindsLeavesInSplitTree() throws {
        let (tree, view1, view2) = try makeHorizontalSplit()

        #expect(tree.root?.node(view: view1) == .leaf(view: view1))
        #expect(tree.root?.node(view: view2) == .leaf(view: view2))
    }

    @Test func nodeReturnsNilForMissingView() {
        let view1 = MockView()
        let view2 = MockView()

        let tree = SplitTree<MockView>(view: view1)
        #expect(tree.root?.node(view: view2) == nil)
    }

    @Test func resizingUpdatesRatio() throws {
        let (tree, _, _) = try makeHorizontalSplit()

        guard case .split(let s) = tree.root else {
            Issue.record("unexpected node type")
            return
        }

        let resized = SplitTree<MockView>.Node.split(s).resizing(to: 0.7)
        guard case .split(let resizedSplit) = resized else {
            Issue.record("unexpected node type")
            return
        }
        #expect(abs(resizedSplit.ratio - 0.7) < 0.001)
    }

    @Test func resizingLeavesLeafUnchanged() {
        let view1 = MockView()
        let tree = SplitTree<MockView>(view: view1)

        guard let root = tree.root else {
            Issue.record("expected non-empty tree")
            return
        }
        let resized = root.resizing(to: 0.7)
        #expect(resized == root)
    }

    // MARK: - Spatial

    @Test(arguments: [
        (SplitTree<MockView>.Spatial.Direction.left, SplitTree<MockView>.NewDirection.right),
        (.right, .right),
        (.up, .down),
        (.down, .down),
    ])
    func doesBorderEdge(
        side: SplitTree<MockView>.Spatial.Direction,
        insertDirection: SplitTree<MockView>.NewDirection
    ) throws {
        let view1 = MockView()
        let view2 = MockView()
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: insertDirection)

        let spatial = tree.root!.spatial(within: CGSize(width: 1000, height: 500))

        // view1 borders left/up; view2 borders right/down
        let (borderView, nonBorderView): (MockView, MockView) =
            (side == .right || side == .down) ? (view2, view1) : (view1, view2)
        #expect(spatial.doesBorder(side: side, from: .leaf(view: borderView)))
        #expect(!spatial.doesBorder(side: side, from: .leaf(view: nonBorderView)))
    }

    // MARK: - Calculate View Bounds

    @Test func calculatesViewBoundsForSingleLeaf() {
        let view1 = MockView()
        let tree = SplitTree<MockView>(view: view1)

        guard let root = tree.root else {
            Issue.record("expected non-empty tree")
            return
        }

        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let result = root.calculateViewBounds(in: bounds)
        #expect(result.count == 1)
        #expect(result[0].view === view1)
        #expect(result[0].bounds == bounds)
    }

    @Test func calculatesViewBoundsHorizontalSplit() throws {
        let (tree, view1, view2) = try makeHorizontalSplit()

        guard let root = tree.root else {
            Issue.record("expected non-empty tree")
            return
        }

        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let result = root.calculateViewBounds(in: bounds)
        #expect(result.count == 2)

        let leftBounds = result.first { $0.view === view1 }!.bounds
        let rightBounds = result.first { $0.view === view2 }!.bounds
        #expect(leftBounds == CGRect(x: 0, y: 0, width: 500, height: 500))
        #expect(rightBounds == CGRect(x: 500, y: 0, width: 500, height: 500))
    }

    @Test func calculatesViewBoundsVerticalSplit() throws {
        let view1 = MockView()
        let view2 = MockView()
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: .down)

        guard let root = tree.root else {
            Issue.record("expected non-empty tree")
            return
        }

        let bounds = CGRect(x: 0, y: 0, width: 500, height: 1000)
        let result = root.calculateViewBounds(in: bounds)
        #expect(result.count == 2)

        let topBounds = result.first { $0.view === view1 }!.bounds
        let bottomBounds = result.first { $0.view === view2 }!.bounds
        #expect(topBounds == CGRect(x: 0, y: 500, width: 500, height: 500))
        #expect(bottomBounds == CGRect(x: 0, y: 0, width: 500, height: 500))
    }

    @Test func calculateViewBoundsCustomRatio() throws {
        let (tree, view1, view2) = try makeHorizontalSplit()

        guard case .split(let s) = tree.root else {
            Issue.record("unexpected node type")
            return
        }

        let resizedRoot = SplitTree<MockView>.Node.split(s).resizing(to: 0.3)
        let container = CGRect(x: 0, y: 0, width: 1000, height: 400)
        let result = resizedRoot.calculateViewBounds(in: container)
        #expect(result.count == 2)

        let leftBounds = result.first { $0.view === view1 }!.bounds
        let rightBounds = result.first { $0.view === view2 }!.bounds
        #expect(leftBounds.width == 300)   // 0.3 * 1000
        #expect(rightBounds.width == 700)   // 0.7 * 1000
        #expect(rightBounds.minX == 300)
    }

    @Test func calculateViewBoundsGrid() throws {
        let view1 = MockView()
        let view2 = MockView()
        let view3 = MockView()
        let view4 = MockView()
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: .right)
        tree = try tree.inserting(view: view3, at: view1, direction: .down)
        tree = try tree.inserting(view: view4, at: view2, direction: .down)
        guard let root = tree.root else {
            Issue.record("expected non-empty tree")
            return
        }
        let container = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let result = root.calculateViewBounds(in: container)
        #expect(result.count == 4)

        let b1 = result.first { $0.view === view1 }!.bounds
        let b2 = result.first { $0.view === view2 }!.bounds
        let b3 = result.first { $0.view === view3 }!.bounds
        let b4 = result.first { $0.view === view4 }!.bounds
        #expect(b1 == CGRect(x: 0, y: 400, width: 500, height: 400))   // top-left
        #expect(b2 == CGRect(x: 500, y: 400, width: 500, height: 400)) // top-right
        #expect(b3 == CGRect(x: 0, y: 0, width: 500, height: 400))     // bottom-left
        #expect(b4 == CGRect(x: 500, y: 0, width: 500, height: 400))   // bottom-right
    }

    @Test(arguments: [
        (SplitTree<MockView>.Spatial.Direction.right, SplitTree<MockView>.NewDirection.right),
        (.left, .right),
        (.down, .down),
        (.up, .down),
    ])
    func slotsFromNode(
        direction: SplitTree<MockView>.Spatial.Direction,
        insertDirection: SplitTree<MockView>.NewDirection
    ) throws {
        let view1 = MockView()
        let view2 = MockView()
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: insertDirection)

        let spatial = tree.root!.spatial(within: CGSize(width: 1000, height: 500))

        // look from view1 toward view2 for right/down, from view2 toward view1 for left/up
        let (fromView, expectedView): (MockView, MockView) =
            (direction == .right || direction == .down) ? (view1, view2) : (view2, view1)
        let slots = spatial.slots(in: direction, from: .leaf(view: fromView))
        #expect(slots.count == 1)
        #expect(slots[0].node == .leaf(view: expectedView))
    }

    @Test func slotsGridFromTopLeft() throws {
        let view1 = MockView()
        let view2 = MockView()
        let view3 = MockView()
        let view4 = MockView()
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: .right)
        tree = try tree.inserting(view: view3, at: view1, direction: .down)
        tree = try tree.inserting(view: view4, at: view2, direction: .down)
        let spatial = tree.root!.spatial(within: CGSize(width: 1000, height: 800))
        let rightSlots = spatial.slots(in: .right, from: .leaf(view: view1))
        let downSlots = spatial.slots(in: .down, from: .leaf(view: view1))
        // slots() returns both split nodes and leaves; split nodes can tie on distance
        #expect(rightSlots.contains { $0.node == .leaf(view: view2) })
        #expect(downSlots.contains { $0.node == .leaf(view: view3) })
    }

    @Test func slotsGridFromBottomRight() throws {
        let view1 = MockView()
        let view2 = MockView()
        let view3 = MockView()
        let view4 = MockView()
        var tree = SplitTree<MockView>(view: view1)
        tree = try tree.inserting(view: view2, at: view1, direction: .right)
        tree = try tree.inserting(view: view3, at: view1, direction: .down)
        tree = try tree.inserting(view: view4, at: view2, direction: .down)
        let spatial = tree.root!.spatial(within: CGSize(width: 1000, height: 800))
        let leftSlots = spatial.slots(in: .left, from: .leaf(view: view4))
        let upSlots = spatial.slots(in: .up, from: .leaf(view: view4))
        #expect(leftSlots.contains { $0.node == .leaf(view: view3) })
        #expect(upSlots.contains { $0.node == .leaf(view: view2) })
    }

    @Test func slotsReturnsEmptyWhenNoNodesInDirection() throws {
        let (tree, view1, view2) = try makeHorizontalSplit()

        let spatial = tree.root!.spatial(within: CGSize(width: 1000, height: 500))
        #expect(spatial.slots(in: .left, from: .leaf(view: view1)).isEmpty)
        #expect(spatial.slots(in: .right, from: .leaf(view: view2)).isEmpty)
        #expect(spatial.slots(in: .up, from: .leaf(view: view1)).isEmpty)
        #expect(spatial.slots(in: .down, from: .leaf(view: view2)).isEmpty)
    }

    // Set/Dictionary usage is the only path that exercises StructuralIdentity.hash(into:)
    @Test func structuralIdentityHashableBehavior() throws {
        let (tree, _, _) = try makeHorizontalSplit()
        let id = tree.structuralIdentity

        #expect(id == id)

        var seen: Set<SplitTree<MockView>.StructuralIdentity> = []
        seen.insert(id)
        seen.insert(id)
        #expect(seen.count == 1)

        var cache: [SplitTree<MockView>.StructuralIdentity: String] = [:]
        cache[id] = "two-pane"
        #expect(cache[id] == "two-pane")
    }

    @Test func nodeStructuralIdentityInSet() throws {
        let (tree, _, _) = try makeHorizontalSplit()

        guard case .split(let s) = tree.root else {
            Issue.record("unexpected node type")
            return
        }

        var nodeIds: Set<SplitTree<MockView>.Node.StructuralIdentity> = []
        nodeIds.insert(tree.root!.structuralIdentity)
        nodeIds.insert(s.left.structuralIdentity)
        nodeIds.insert(s.right.structuralIdentity)
        #expect(nodeIds.count == 3)
    }

    @Test func nodeStructuralIdentityDistinguishesLeaves() throws {
        let (tree, _, _) = try makeHorizontalSplit()

        guard case .split(let s) = tree.root else {
            Issue.record("unexpected node type")
            return
        }

        var nodeIds: Set<SplitTree<MockView>.Node.StructuralIdentity> = []
        nodeIds.insert(s.left.structuralIdentity)
        nodeIds.insert(s.right.structuralIdentity)
        #expect(nodeIds.count == 2)
    }
}
