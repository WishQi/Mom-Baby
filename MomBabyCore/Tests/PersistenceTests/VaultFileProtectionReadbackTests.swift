import Foundation
import Testing

@testable import Persistence

@Suite("Vault file protection readback")
struct VaultFileProtectionReadbackTests {
    @Test("Complete protection is always accepted")
    func completeIsAccepted() {
        #expect(
            VaultFileProtectionReadback
                .protection(.complete)
                .isAcceptable(permitsMissingValue: false)
        )
        #expect(
            VaultFileProtectionReadback
                .protection(.complete)
                .isAcceptable(permitsMissingValue: true)
        )
    }

    @Test("Missing readback is accepted only for the simulator policy")
    func missingValueIsSimulatorOnly() {
        #expect(
            !VaultFileProtectionReadback.missing
                .isAcceptable(permitsMissingValue: false)
        )
        #expect(
            VaultFileProtectionReadback.missing
                .isAcceptable(permitsMissingValue: true)
        )
    }

    @Test(
        "Explicit weaker protection classes remain blocked",
        arguments: [
            FileProtectionType.none,
            .completeUnlessOpen,
            .completeUntilFirstUserAuthentication,
        ]
    )
    func weakerProtectionRemainsBlocked(_ protection: FileProtectionType) {
        #expect(
            !VaultFileProtectionReadback
                .protection(protection)
                .isAcceptable(permitsMissingValue: false)
        )
        #expect(
            !VaultFileProtectionReadback
                .protection(protection)
                .isAcceptable(permitsMissingValue: true)
        )
    }

    @Test("Non-missing unrecognized readback remains blocked")
    func invalidValueRemainsBlocked() {
        let readback = VaultFileProtectionReadback(
            attribute: NSNumber(value: 1)
        )

        #expect(readback == .invalid)
        #expect(!readback.isAcceptable(permitsMissingValue: false))
        #expect(!readback.isAcceptable(permitsMissingValue: true))
    }

    @Test("Foundation string readback is parsed without weakening policy")
    func stringReadbackIsParsed() {
        let complete = VaultFileProtectionReadback(
            attribute: FileProtectionType.complete.rawValue
        )
        let unknown = VaultFileProtectionReadback(
            attribute: "UnknownProtectionClass"
        )

        #expect(complete == .protection(.complete))
        #expect(complete.isAcceptable(permitsMissingValue: false))
        #expect(
            !unknown.isAcceptable(permitsMissingValue: true)
        )
    }
}
