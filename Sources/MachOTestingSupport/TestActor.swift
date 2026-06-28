import Foundation

@globalActor
public actor TestActor {
    public static let shared = TestActor()
}
