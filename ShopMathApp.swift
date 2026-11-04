import SwiftUI
import UIKit

@main
struct ShopMathApp: App {
    @StateObject private var lumber = LumberStore()

    init() {
        UnitSwitcher.prepare()
        CursorToEnd.install()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(lumber)
        }
    }
}

struct ContentView: View {
    @AppStorage("app_tab") private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            CleatView()
                .tabItem { Label("Cleats", systemImage: "square.split.diagonal") }
                .tag(0)
            BoardFeetView()
                .tabItem { Label("Board Feet", systemImage: "cube") }
                .tag(1)
            FractionCalcView()
                .tabItem { Label("Fractions", systemImage: "plus.forwardslash.minus") }
                .tag(2)
            AnglesView()
                .tabItem { Label("Angles", systemImage: "angle") }
                .tag(3)
            EndGrainView()
                .tabItem { Label("End Grain", systemImage: "square.grid.3x3") }
                .tag(4)
        }
    }
}

/// Puts the cursor after the text whenever a field starts editing, so tapping a number lets you
/// backspace or add to it right away instead of landing in front of it.
enum CursorToEnd {
    private static var observer: NSObjectProtocol?

    static func install() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UITextField.textDidBeginEditingNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let field = note.object as? UITextField else { return }
            // UIKit places the cursor at the tap point after this notification, so move it on
            // the next pass of the main queue.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let end = field.endOfDocument
                    field.selectedTextRange = field.textRange(from: end, to: end)
                }
            }
        }
    }
}
