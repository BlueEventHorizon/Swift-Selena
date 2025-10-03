import Foundation
import UIKit

// Base class
class ViewController: UIViewController {
    var data: [String] = []
}

// Extension with protocol conformance
extension ViewController: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return data.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell()
        cell.textLabel?.text = data[indexPath.row]
        return cell
    }
}

// Extension without protocol (category)
extension ViewController {
    func setupUI() {
        view.backgroundColor = .white
        title = "My View"
    }

    func loadData() {
        data = ["Item 1", "Item 2", "Item 3"]
    }
}

// Extension on standard type
extension String {
    var isValidEmail: Bool {
        return contains("@")
    }

    func trimmed() -> String {
        return trimmingCharacters(in: .whitespaces)
    }
}

// Extension with computed property
extension Array where Element == Int {
    var sum: Int {
        return reduce(0, +)
    }
}
