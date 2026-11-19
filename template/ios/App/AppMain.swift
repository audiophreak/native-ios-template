import AppCore
import SwiftUI

@main
struct StarterApp: App {
    @State private var model: AppModel?
    @State private var configurationProblem: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if let model {
                    RootView(model: model)
                } else if let configurationProblem {
                    ContentUnavailableView("The app is not configured", systemImage: "gearshape.trianglebadge.exclamationmark", description: Text(configurationProblem))
                } else {
                    ProgressView()
                }
            }
            .task {
                guard model == nil else { return }
                do {
                    model = AppModel(environment: try .live())
                } catch {
                    configurationProblem = "Check APIScheme and APIHost in ios/Config/*.xcconfig."
                }
            }
        }
    }
}
