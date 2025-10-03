import SwiftUI

struct ContentView: View {
    @State private var counter: Int = 0
    @State private var isPresented: Bool = false
    @Binding var username: String
    @ObservedObject var viewModel: ViewModel
    @StateObject private var manager = DataManager()
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("isDarkMode") var isDarkMode: Bool = false

    var body: some View {
        VStack {
            Text("Counter: \(counter)")
            Button("Increment") {
                counter += 1
            }
        }
    }
}

class ViewModel: ObservableObject {
    @Published var items: [String] = []
    @Published var isLoading: Bool = false
}
