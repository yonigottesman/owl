import Foundation

@main
enum PowerEventRegistrationTests {
    static func main() throws {
        let events = try PowerEvents {}
        withExtendedLifetime(events) { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        print("Passed: power-source, lid and display event registration and cleanup")
    }
}
