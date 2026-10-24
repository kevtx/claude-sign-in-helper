import SwiftUI

/// Where each of the four sign-in steps stands, derived from the model.
struct SignInFlow {
    enum Status { case upcoming, current, done, skipped, attention }
    let statuses: [Status]
    /// The step being shown.
    let focus: Int

    init(_ model: HelperModel) {
        var statuses: [Status]
        switch model.stage {
        case .welcome: statuses = [.current, .upcoming, .upcoming, .upcoming]
        case .closeDesktop: statuses = [.attention, .upcoming, .upcoming, .upcoming]
        case .ready: statuses = [.done, .current, .upcoming, .upcoming]
        case .existing: statuses = [.done, .skipped, .current, .skipped]
        case .imported: statuses = model.claudeOpened ? [.done, .done, .done, .current] : [.done, .done, .current, .upcoming]
        case .verified: statuses = [.done, .done, .done, .done]
        case .unconfirmed: statuses = [.done, .done, .done, .attention]
        }
        let focus = model.stage == .verified ? 3 : statuses.firstIndex { $0 == .current || $0 == .attention } ?? 0
        if model.problem != nil && !model.busy { statuses[focus] = .attention }
        self.statuses = statuses
        self.focus = focus
    }
}

/// The whole sign-in flow on one small screen: where you are, what it means, and the next step.
struct SignInView: View {
    @ObservedObject var model: HelperModel
    let requestImport: () -> Void

    private struct Action {
        let title: String
        let run: () -> Void
    }

    var body: some View {
        VStack(spacing: 0) {
            BrandMark(size: 44)
            StepDots(flow: SignInFlow(model)).padding(.top, 22)
            Text(headline).font(.serif(22)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 14)
                .accessibilityAddTraits(.isHeader)
            Text(message).font(.ui(13)).foregroundStyle(Palette.text2).multilineTextAlignment(.center).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            actions.padding(.top, 24)
        }
        .frame(maxWidth: 330)
        .animation(.easeInOut(duration: 0.2), value: model.stage)
        .animation(.easeInOut(duration: 0.2), value: model.claudeOpened)
    }

    // MARK: Words

    private var headline: String {
        if let problem = model.problem, !model.busy { return localized(problem.title) }
        switch model.stage {
        case .welcome: return String(localized: "Bring your Safari sign-in to Claude Desktop")
        case .closeDesktop: return String(localized: "Quit Claude Desktop first")
        case .ready: return String(localized: "Ready to import")
        case .existing: return String(localized: "Claude Desktop already has a sign-in")
        case .imported: return model.claudeOpened ? String(localized: "Confirm the sign-in") : String(localized: "Sign-in imported")
        case .verified: return String(localized: "Sign-in confirmed")
        case .unconfirmed: return String(localized: "Not confirmed yet")
        }
    }

    private var message: String {
        if let problem = model.problem, !model.busy {
            return problem.needsDiskAccess
                ? String(localized: "Turn on Claude Sign-In Helper in System Settings → Privacy & Security → Full Disk Access, then quit and reopen it.")
                : localized(problem.detail)
        }
        switch model.stage {
        case .welcome:
            return String(localized: "Make sure Claude works in Safari, then quit Claude Desktop with ⌘Q.")
        case .closeDesktop:
            return String(localized: "It’s still running. Press ⌘Q in Claude Desktop (closing its window isn’t enough), then check again.")
        case .ready:
            let desktop = model.desktopVersion.isEmpty ? "Claude Desktop" : "Claude Desktop " + model.desktopVersion
            return String(localized: "Found \(desktop) and your Safari sign-in. A backup is saved before anything changes.")
        case .existing:
            return String(localized: "There’s nothing to import. Its saved sign-in is left as it is.")
        case .imported:
            return model.claudeOpened
                ? String(localized: "Once Claude Desktop has loaded, check that it reported a successful sign-in.")
                : String(localized: "Open Claude Desktop so it can finish signing in, then confirm it here.")
        case .verified:
            return String(localized: "Claude Desktop reported a successful sign-in. Check that it shows the account you expect.")
        case .unconfirmed:
            return String(localized: "Claude may still be loading. If it asks you to sign in, sign out of Claude in Safari and back in, then import again.")
        }
    }

    // MARK: Actions

    @ViewBuilder private var actions: some View {
        if model.busy {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(localized(model.progress)).font(.ui(12.5)).foregroundStyle(Palette.text3)
            }
            .frame(height: 34)
            .accessibilityElement(children: .combine)
        } else {
            VStack(spacing: 6) {
                Button(primary.title, action: primary.run)
                    .buttonStyle(ClayButtonStyle(minWidth: 200)).keyboardShortcut(.defaultAction)
                let links = self.links
                if !links.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(links.indices, id: \.self) { index in
                            Button(links[index].title, action: links[index].run).buttonStyle(LinkButtonStyle())
                        }
                    }
                }
                if model.stage == .welcome && model.problem == nil {
                    Text("Checking only reads. Nothing leaves this Mac.").font(.ui(11.5)).foregroundStyle(Palette.text3)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                }
            }
        }
    }

    private var primary: Action {
        if let problem = model.problem, problem.needsDiskAccess {
            return Action(title: String(localized: "Open Full Disk Access")) { model.openAccessSettings() }
        }
        switch model.stage {
        case .welcome: return Action(title: model.problem == nil ? String(localized: "Check this Mac") : String(localized: "Check again")) { model.check() }
        case .closeDesktop: return Action(title: String(localized: "Check again")) { model.check() }
        case .ready: return Action(title: String(localized: "Import sign-in…"), run: requestImport)
        case .existing, .verified: return Action(title: String(localized: "Open Claude")) { model.openClaude() }
        case .imported:
            return model.claudeOpened ? Action(title: String(localized: "Verify sign-in")) { model.verify() } : Action(title: String(localized: "Open Claude")) { model.openClaude() }
        case .unconfirmed: return Action(title: String(localized: "Verify again")) { model.verify() }
        }
    }

    private var links: [Action] {
        if let problem = model.problem, problem.needsDiskAccess {
            return [Action(title: String(localized: "Show app in Finder")) { model.revealApp() }, Action(title: String(localized: "Check again")) { model.check() }]
        }
        switch model.stage {
        case .ready, .existing: return [Action(title: String(localized: "Check again")) { model.check() }]
        case .imported:
            return [model.claudeOpened ? Action(title: String(localized: "Open Claude")) { model.openClaude() } : Action(title: String(localized: "Verify sign-in")) { model.verify() }]
        case .unconfirmed: return [Action(title: String(localized: "Open Claude")) { model.openClaude() }]
        default: return []
        }
    }
}

/// Four small segments; the current step is the long one.
struct StepDots: View {
    let flow: SignInFlow

    var body: some View {
        HStack(spacing: 6) {
            ForEach(flow.statuses.indices, id: \.self) { index in
                Capsule().fill(color(flow.statuses[index]))
                    .frame(width: index == flow.focus ? 22 : 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(flow.focus + 1) of 4")
    }

    private func color(_ status: SignInFlow.Status) -> Color {
        switch status {
        case .done, .current: return Palette.accent
        case .attention: return Palette.warning
        case .upcoming, .skipped: return Palette.border
        }
    }
}
