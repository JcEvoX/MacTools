import Foundation

@MainActor
final class UserDefaultsDisplayDisableStateStore: DisplayDisableStateStoring {
    private enum Constants {
        static let key = "DisplayBrightness.DisplayDisableRecoverySnapshot"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var snapshot: DisplayDisableRecoverySnapshot? {
        get {
            guard let data = userDefaults.data(forKey: Constants.key) else {
                return nil
            }

            return try? JSONDecoder().decode(DisplayDisableRecoverySnapshot.self, from: data)
        }
        set {
            guard let newValue else {
                userDefaults.removeObject(forKey: Constants.key)
                return
            }

            if let data = try? JSONEncoder().encode(newValue) {
                userDefaults.set(data, forKey: Constants.key)
            }
        }
    }
}
