import SwiftUI

@main
@MainActor
struct MomBabyApp: App {
    @State private var environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
                // The approved T1 Figma boards currently define a light visual
                // system only. Keep this slice deterministic until dark tokens
                // receive their own design and contrast review.
                .preferredColorScheme(.light)
        }
    }
}
