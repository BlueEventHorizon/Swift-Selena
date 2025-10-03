import XCTest

class UserViewModelTests: XCTestCase {
    var viewModel: UserViewModel!

    override func setUp() {
        super.setUp()
        viewModel = UserViewModel()
    }

    func testInitialState() {
        XCTAssertEqual(viewModel.username, "")
        XCTAssertEqual(viewModel.email, "")
    }

    func testUpdateUsername() {
        viewModel.username = "John"
        XCTAssertEqual(viewModel.username, "John")
    }

    func testValidation() {
        XCTAssertFalse(viewModel.isValid)
        viewModel.username = "John"
        viewModel.email = "john@example.com"
        XCTAssertTrue(viewModel.isValid)
    }
}

class NetworkManagerTests: XCTestCase {
    func testFetchData() {
        // Test implementation
    }

    func testErrorHandling() {
        // Test implementation
    }
}
