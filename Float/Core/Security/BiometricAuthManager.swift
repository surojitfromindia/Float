import Foundation
import LocalAuthentication
import Combine

@MainActor
final class BiometricAuthManager: ObservableObject {
    @Published var isUnlocked = true
    @Published var lastErrorMessage: String?

    func canAuthenticate() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func authenticate(reason: String = "Unlock Float") async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            lastErrorMessage = error?.localizedDescription
            return false
        }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            isUnlocked = success
            return success
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func lock() {
        isUnlocked = false
    }
}
