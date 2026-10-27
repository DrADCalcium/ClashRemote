#if os(Windows)
import Foundation
import SwiftOpenUI
import CWindowsPlatform

// Narrow bridges for platform APIs; view hierarchies remain in the original Swift files.
extension Font {
    typealias Weight = FontWeight
    typealias Design = FontDesign
    typealias TextStyle = Font
    func monospacedDigit() -> Font { .system(size: pointSize, design: .monospaced) }
}
extension State {
    init(initialValue: Value) { self.init(wrappedValue: initialValue) }
}

struct NSImage {
    let url: URL
    init?(contentsOf url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        self.url = url
    }
}
extension Image { init(nsImage: NSImage) { self.init(filePath: nsImage.url.path) } }

@propertyWrapper
struct AppStorage<Value: RawRepresentable>: AnyStateStorageProvider where Value.RawValue == String {
    @State private var value: Value
    private let key: String
    init(wrappedValue: Value, _ key: String) {
        self.key = key
        self._value = State(initialValue: UserDefaults.standard.string(forKey: key).flatMap(Value.init(rawValue:)) ?? wrappedValue)
    }
    var wrappedValue: Value {
        get { value }
        nonmutating set { value = newValue; UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
    var anyStorage: AnyStateStorage { _value.anyStorage }
    var projectedValue: Binding<Value> { Binding(get: { wrappedValue }, set: { wrappedValue = $0 }) }
}

struct WindowPreferences: View {
    let alwaysOnTop: Bool
    var rememberFrame: Bool? = nil
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onAppear { cr_window_topmost(alwaysOnTop ? 1 : 0) }
            .onChange(of: alwaysOnTop) { _, value in cr_window_topmost(value ? 1 : 0) }
    }
}
#endif

import Foundation
#if canImport(AppKit)
import AppKit
#endif
enum PlatformBrowser {
    static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #elseif os(Windows)
        cr_open_url(url.absoluteString)
        #endif
    }
}
