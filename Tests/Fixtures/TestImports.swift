import Foundation
import SwiftUI
import Combine
import UIKit

class MyViewController: UIViewController {
    var cancellables = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()
    }
}

struct MyView: View {
    @State private var text: String = ""

    var body: some View {
        Text(text)
    }
}
