import Foundation
import UIKit

// Base class
class Animal {
    var name: String = ""
}

// Subclass 1
class Dog: Animal {
    var breed: String = ""
}

// Subclass 2
class Cat: Animal {
    var color: String = ""
}

// Subclass of subclass
class Poodle: Dog {
    var size: String = ""
}

// Protocol
protocol Flyable {
    func fly()
}

// Protocol conforming types
class Bird: Animal, Flyable {
    func fly() {
        print("Flying")
    }
}

class Airplane: Flyable {
    func fly() {
        print("Flying")
    }
}

// Multiple inheritance levels
class ViewController: UIViewController {

}

class CustomViewController: ViewController {

}

class SpecialViewController: CustomViewController {

}
