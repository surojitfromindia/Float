import Combine
import Foundation
import LocalAuthentication

@MainActor
final class BiometricAuthManager: ObservableObject {
    @Published var isUnlocked = false
    @Published var lastErrorMessage: String?
    @Published private(set) var isAuthenticating = false

    func canAuthenticate() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(
            .deviceOwnerAuthentication,
            error: &error
        )
    }

    func authenticate(reason: String = "Unlock Float") async -> Bool {
        guard !isAuthenticating else { return false }
        let context = LAContext()
        isAuthenticating = true
        defer { isAuthenticating = false }
        lastErrorMessage = nil
        var error: NSError?
        guard
            context.canEvaluatePolicy(
                .deviceOwnerAuthentication,
                error: &error
            )
        else {
            lastErrorMessage =
                error?.localizedDescription
                ?? "Device authentication is not available on this device."
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
            if let laError = error as? LAError {
                switch laError.code {
                case .userCancel, .appCancel, .systemCancel:
                    lastErrorMessage = "Unlock was cancelled."
                case .biometryNotAvailable:
                    lastErrorMessage = "Biometric authentication is not available."
                case .biometryNotEnrolled:
                    lastErrorMessage = "Set up Face ID, Touch ID, or a device passcode to use lock."
                default:
                    lastErrorMessage = laError.localizedDescription
                }
            } else {
                lastErrorMessage = error.localizedDescription
            }
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
