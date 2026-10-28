import SwiftUI

@main
struct UnteamsApp: App {
  var body: some Scene {
    WindowGroup {
      TeamsView()
        .ignoresSafeArea(.container, edges: .bottom)
    }
  }
}
