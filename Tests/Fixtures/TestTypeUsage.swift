import Foundation
import SwiftUI

// 型定義
struct User {
    let id: Int
    let name: String
}

class UserViewModel {
    var currentUser: User?  // Variable usage
    var users: [User] = []  // Array usage

    func getUser() -> User {  // ReturnType usage
        return User(id: 1, name: "John")
    }

    func updateUser(_ user: User) {  // Parameter usage
        self.currentUser = user
    }

    func processUsers(_ users: [User]) -> [User] {  // Parameter and ReturnType
        return users.filter { $0.id > 0 }
    }
}

// SwiftUI View with type usage
struct UserListView: View {
    @State private var users: [User] = []  // Property usage
    @StateObject private var viewModel: UserViewModel = UserViewModel()

    var body: some View {
        List(users, id: \.id) { user in  // Variable usage in closure
            Text(user.name)
        }
    }
}

// Function with type usage
func fetchUser(id: Int) -> User? {  // ReturnType usage
    return User(id: id, name: "Test")
}

func saveUser(_ user: User) {  // Parameter usage
    print("Saving user: \(user.name)")
}
