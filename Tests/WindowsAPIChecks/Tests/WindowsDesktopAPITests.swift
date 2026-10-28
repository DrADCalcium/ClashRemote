import XCTest
import Foundation
import SwiftOpenUI
import BackendWin32
import CDesktopCompatibility
import WinSDK

final class WindowsDesktopAPITests: XCTestCase {
    private var parent: HWND!
    private var context: RenderContext!
    override func setUp() {
        super.setUp()
        let instance = GetModuleHandleW(nil)!
        parent = "STATIC".withCString(encodedAs: UTF16.self) {
            CreateWindowExW(0, $0, nil, DWORD(WS_OVERLAPPEDWINDOW), 0, 0, 800, 600, nil, nil, instance, nil)
        }
        XCTAssertNotNil(parent)
        context = RenderContext(parent: parent, hInstance: instance)
    }
    override func tearDown() { if let parent { DestroyWindow(parent) }; super.tearDown() }
    private func allChildren(_ window: HWND) -> [HWND] {
        var result: [HWND] = []; var child = GetWindow(window, UINT(GW_CHILD))
        while let next = child { result.append(next); result += allChildren(next); child = GetWindow(next, UINT(GW_HWNDNEXT)) }
        return result
    }
    private func text(_ window: HWND) -> String {
        var buffer = [WCHAR](repeating: 0, count: 512)
        let count = GetWindowTextW(window, &buffer, Int32(buffer.count))
        return String(decoding: buffer.prefix(Int(count)), as: UTF16.self)
    }
    private func accessible(_ window: HWND, field: Int32) -> String {
        var buffer = [UInt16](repeating: 0, count: 512)
        XCTAssertGreaterThanOrEqual(soui_accessibility_read_string(UnsafeMutableRawPointer(window), field, &buffer, buffer.count), 0)
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF16.self)
    }

    func testQuadraticCurveConversionAndClosedPathPoint() {
        var path = Path(); path.move(to: .zero)
        path.addQuadCurve(to: CGPoint(x: 30, y: 0), control: CGPoint(x: 15, y: 30))
        guard case .curve(let end, let c1, let c2) = path.elements.last else { return XCTFail("Expected cubic Bezier") }
        XCTAssertEqual(end, CGPoint(x: 30, y: 0))
        XCTAssertEqual(c1, CGPoint(x: 10, y: 20)); XCTAssertEqual(c2, CGPoint(x: 20, y: 20))
        path.closeSubpath(); XCTAssertEqual(path.currentPoint, .zero)
    }
    func testPathHitTestingHonorsHolesAndCurves() {
        var path = Path(CGRect(x: 0, y: 0, width: 100, height: 100))
        path.move(to: CGPoint(x: 20, y: 20)); path.addLine(to: CGPoint(x: 20, y: 80))
        path.addLine(to: CGPoint(x: 80, y: 80)); path.addLine(to: CGPoint(x: 80, y: 20)); path.closeSubpath()
        XCTAssertTrue(path.contains(CGPoint(x: 10, y: 10)))
        XCTAssertFalse(path.contains(CGPoint(x: 50, y: 50)))
        XCTAssertFalse(path.contains(CGPoint(x: 101, y: 50)))
        let circle = Circle().path(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertTrue(circle.contains(CGPoint(x: 50, y: 50)))
        XCTAssertFalse(circle.contains(CGPoint(x: 1, y: 1)))
    }
    func testAnyLayoutChangesNativeOrientation() throws {
        let horizontal = try XCTUnwrap(winRenderView(AnyLayout(HStackLayout(spacing: 12)) { Text("A"); Text("B") }, in: context))
        let vertical = try XCTUnwrap(winRenderView(AnyLayout(VStackLayout(spacing: 12)) { Text("A"); Text("B") }, in: context))
        let hs = allChildren(horizontal).filter { text($0) == "A" || text($0) == "B" }
        let vs = allChildren(vertical).filter { text($0) == "A" || text($0) == "B" }
        XCTAssertEqual(hs.count, 2); XCTAssertEqual(vs.count, 2)
        var a = RECT(), b = RECT(); GetWindowRect(hs[0], &a); GetWindowRect(hs[1], &b)
        XCTAssertGreaterThan(b.left, a.left)
        GetWindowRect(vs[0], &a); GetWindowRect(vs[1], &b); XCTAssertGreaterThan(b.top, a.top)
    }
    func testAdaptiveGridReflowsOnResize() throws {
        let grid = LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 250), spacing: 10)], spacing: 10) {
            Text("A").frame(height: 30); Text("B").frame(height: 30); Text("C").frame(height: 30)
        }
        XCTAssertEqual(grid.columnCount(availableWidth: 600), 3)
        XCTAssertEqual(grid.columnCount(availableWidth: 400), 2)
        let hwnd = try XCTUnwrap(winRenderView(grid, in: context))
        SetWindowPos(hwnd, nil, 0, 0, 600, 100, UINT(SWP_NOZORDER))
        let texts = allChildren(hwnd).filter { ["A", "B", "C"].contains(text($0)) }
        XCTAssertEqual(texts.count, 3)
        var first = RECT(), last = RECT(); GetWindowRect(texts[0], &first); GetWindowRect(texts[2], &last)
        XCTAssertEqual(first.top, last.top)
        SetWindowPos(hwnd, nil, 0, 0, 400, 100, UINT(SWP_NOZORDER))
        GetWindowRect(texts[2], &last); XCTAssertGreaterThan(last.top, first.top)
    }
    func testAccessibilityAnnotationsPreserveVisualText() throws {
        let view = Text("Visual title").accessibilityLabel("Spoken title").accessibilityValue("42").accessibilityHint("Help text")
        let hwnd = try XCTUnwrap(winRenderView(view, in: context))
        XCTAssertEqual(text(hwnd), "Visual title")
        XCTAssertEqual(accessible(hwnd, field: 0), "Spoken title")
        XCTAssertEqual(accessible(hwnd, field: 1), "42")
        XCTAssertEqual(accessible(hwnd, field: 2), "Help text")
    }
    func testHoverCallbacksDoNotRepeatUntilMouseLeaves() throws {
        var values: [Bool] = []
        let hwnd = try XCTUnwrap(winRenderView(Text("Hover").onHover { values.append($0) }, in: context))
        _ = SendMessageW(hwnd, UINT(WM_MOUSEMOVE), 0, 0)
        _ = SendMessageW(hwnd, UINT(WM_MOUSEMOVE), 0, 0)
        _ = SendMessageW(hwnd, UINT(WM_MOUSELEAVE), 0, 0)
        XCTAssertEqual(values, [true, false])
    }
    private struct TestStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View { Text(configuration.isPressed ? "Pressed" : "Normal") }
    }
    func testButtonStyleTracksKeyboardPressAndFiresOnce() throws {
        var count = 0
        let root = try XCTUnwrap(winRenderView(Button("Action") { count += 1 }.buttonStyle(TestStyle()), in: context))
        let descendants = [root] + allChildren(root)
        let normal = try XCTUnwrap(descendants.first { text($0) == "Normal" })
        let pressed = try XCTUnwrap(descendants.first { text($0) == "Pressed" })
        func visible(_ window: HWND) -> Bool { GetWindowLongW(window, GWL_STYLE) & WS_VISIBLE != 0 }
        XCTAssertTrue(visible(normal)); XCTAssertFalse(visible(pressed))
        _ = SendMessageW(root, UINT(WM_KEYDOWN), WPARAM(VK_SPACE), 0)
        XCTAssertFalse(visible(normal)); XCTAssertTrue(visible(pressed))
        _ = SendMessageW(root, UINT(WM_KEYUP), WPARAM(VK_SPACE), 0)
        XCTAssertEqual(count, 1)
        XCTAssertTrue(visible(normal)); XCTAssertFalse(visible(pressed))
    }
    func testMultilineAndPasswordFieldsUseNativeEditStyles() throws {
        var value = "hello"
        let binding = Binding(get: { value }, set: { value = $0 })
        let multiline = try XCTUnwrap(winRenderView(TextField("Notes", text: binding, axis: .vertical).lineLimit(3...6), in: context))
        XCTAssertNotEqual(GetWindowLongW(multiline, GWL_STYLE) & ES_MULTILINE, 0)
        let password = try XCTUnwrap(winRenderView(TextField("Secret", text: binding).textContentType(.password), in: context))
        XCTAssertNotEqual(GetWindowLongW(password, GWL_STYLE) & ES_PASSWORD, 0)
    }
    func testMinimumScaleFactorShrinksAndRestoresNativeFont() throws {
        let view = Text("A fairly long text label").font(.system(size: 20)).minimumScaleFactor(0.5)
        let hwnd = try XCTUnwrap(winRenderView(view, in: context))
        func height() -> Int32 {
            let font = HFONT(bitPattern: Int(SendMessageW(hwnd, UINT(WM_GETFONT), 0, 0)))
            var description = LOGFONTW()
            _ = GetObjectW(font, Int32(MemoryLayout<LOGFONTW>.size), &description)
            return abs(description.lfHeight)
        }
        SetWindowPos(hwnd, nil, 0, 0, 1000, 30, UINT(SWP_NOZORDER))
        let original = height()
        SetWindowPos(hwnd, nil, 0, 0, 40, 30, UINT(SWP_NOZORDER))
        let shrunk = height()
        XCTAssertLessThan(shrunk, original)
        XCTAssertGreaterThanOrEqual(shrunk, original / 2)
        SetWindowPos(hwnd, nil, 0, 0, 1000, 30, UINT(SWP_NOZORDER))
        XCTAssertEqual(height(), original)
    }
    func testBalancedSplitKeepsDetailVisibleWhenNarrow() throws {
        let split = NavigationSplitView(sidebarWidth: 250) { Text("Side") } detail: { Text("Detail") }
            .navigationSplitViewStyle(.balanced)
        let hwnd = try XCTUnwrap(winRenderView(split, in: context))
        SetWindowPos(hwnd, nil, 0, 0, 300, 200, UINT(SWP_NOZORDER))
        let side = try XCTUnwrap(allChildren(hwnd).first { text($0) == "Side" })
        var rect = RECT(); GetWindowRect(side, &rect)
        XCTAssertGreaterThan(rect.right-rect.left, 0)
        XCTAssertLessThanOrEqual(rect.right-rect.left, 150)
    }

}
