import Foundation
import SwiftUI

// Class with superclass and protocol
class ViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 10
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        return UITableViewCell()
    }
}

// ViewModel conforming to ObservableObject
class UserViewModel: ObservableObject {
    @Published var username: String = ""
    @Published var email: String = ""
}

// Struct conforming to multiple protocols
struct User: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var age: Int
}

// Enum with raw value
enum Status: String, Codable {
    case active
    case inactive
    case pending
}

// SwiftUI View
struct ContentView: View {
    var body: some View {
        Text("Hello")
    }
}

// Actor
actor DataManager: Sendable {
    var data: [String] = []

    func addData(_ item: String) {
        data.append(item)
    }
}
