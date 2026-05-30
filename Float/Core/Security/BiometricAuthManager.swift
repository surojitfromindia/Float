import Combine
import Foundation
import LocalAuthentication

@MainActor
final class BiometricAuthManager: ObservableObject {
    @Published var isUnlocked = false
    @Published var lastErrorMessage: String?

    func canAuthenticate() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(
            .deviceOwnerAuthentication,
            error: &error
        )
    }

    func authenticate(reason: String = "Unlock Float") async -> Bool {
        let context = LAContext()
        lastErrorMessage = nil
        var error: NSError?
        guard
            context.canEvaluatePolicy(
                .deviceOwnerAuthentication,
                error: &error
            )
        else {
            lastErrorMessage = error?.localizedDescription
            return false
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            isUnlocked = success
            return success
        } catch {
            isUnlocked = false
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func lock() {
        isUnlocked = false
    }

    func unlock() {
        isUnlocked = true
        lastErrorMessage = nil
    }
}
