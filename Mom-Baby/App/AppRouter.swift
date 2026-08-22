import Observation

enum AppRoute: Hashable, Sendable {
    case newRecord
    case history
    case settings
}

@MainActor
@Observable
final class AppRouter {
    var path: [AppRoute]

    init(path: [AppRoute] = []) {
        self.path = path
    }

    func navigate(to route: AppRoute) {
        path.append(route)
    }

    func returnToRoot() {
        path.removeAll()
    }
}
