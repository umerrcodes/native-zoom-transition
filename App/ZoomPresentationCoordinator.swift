import SwiftUI
import UIKit
import OSLog
import Combine

/// One owner per gallery screen. Rows register images, never modal controllers.
@MainActor
final class ZoomPresentationCoordinator: NSObject, ObservableObject, UIAdaptivePresentationControllerDelegate {
    let objectWillChange = ObservableObjectPublisher()
    enum Phase: String { case idle, presenting, presented, dismissing }

    // These storage objects are accessed only by the main-actor coordinator.
    // They don't need isolated destruction (which also keeps cleanup compatible
    // with older Swift concurrency runtimes).
    nonisolated private final class Session {
        let id = UUID()
        let sourceID: String
        let source: UIImageView
        let controller: PreviewController
        var closeRequested = false
        var nextPreview: (item: PreviewItem, sampleValues: [SampleValue]?, sourceID: String)?

        init(sourceID: String, source: UIImageView, controller: PreviewController) {
            self.sourceID = sourceID
            self.source = source
            self.controller = controller
        }
    }

    private enum State {
        case idle
        case presenting(Session)
        case presented(Session)
        case dismissing(Session)

        var session: Session? {
            switch self {
            case .idle: nil
            case let .presenting(session), let .presented(session), let .dismissing(session): session
            }
        }

        var phase: Phase {
            switch self {
            case .idle: .idle
            case .presenting: .presenting
            case .presented: .presented
            case .dismissing: .dismissing
            }
        }
    }

    nonisolated private final class Source {
        weak var view: UIImageView?
        init(_ view: UIImageView) { self.view = view }
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NativeZoomDemo", category: "ZoomPresentation")
    private weak var host: UIViewController?
    private var sources: [String: Source] = [:]
    private var state: State = .idle
    var phase: Phase { state.phase }

    func attach(host: UIViewController) {
        self.host = host
    }

    func detach(host: UIViewController) {
        guard self.host === host else { return }
        self.host = nil
        state.session?.nextPreview = nil
        dismiss()
    }

    func register(_ source: UIImageView, id: String) {
        sources[id] = Source(source)
    }

    func unregister(_ source: UIImageView, id: String) {
        if sources[id]?.view === source { sources[id] = nil }
    }

    func open(item: PreviewItem, sampleValues: [SampleValue]?, sourceID: String) {
        if case let .dismissing(session) = state {
            // UIKit can return touches before the closing zoom finishes. Keep
            // the latest row tap without starting a competing presentation.
            session.nextPreview = (item, sampleValues, sourceID)
            return
        }
        // Reject before changing any state or touching source visibility.
        guard case .idle = state,
              let host, presenterIsReady(host),
              let source = sources[sourceID]?.view, source.window != nil else { return }

        let scrollState = PreviewScrollState()
        let screen = PreviewScreen(
            item: item,
            sampleValues: sampleValues,
            onScrollAtTopChange: { scrollState.isAtTop = $0 }
        ) { [weak self] in
            self?.dismiss()
        }
        let controller = PreviewController(rootView: screen)
        // UIKit owns touch routing while the modal covers the gallery and as it
        // zooms back. An extra root-level shield would block its early handoff.
        let session = Session(sourceID: sourceID, source: source, controller: controller)
        controller.presentationOwner = self
        controller.modalPresentationStyle = .fullScreen
        controller.modalPresentationCapturesStatusBarAppearance = true
        controller.overrideUserInterfaceStyle = .dark
        controller.view.backgroundColor = UIColor(DemoStyle.backgroundBottom)

        let options = UIViewController.Transition.ZoomOptions()
        options.dimmingVisualEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        options.interactiveDismissShouldBegin = { [weak self, weak controller] context in
            guard let self, let controller,
                  self.state.session?.controller === controller else { return false }
            // Don't start another native animator during opening or a spring-back.
            return self.phase == .presented && scrollState.allowsDismissal(
                velocity: context.velocity,
                systemWouldBegin: context.willBegin
            )
        }
        controller.preferredTransition = .zoom(options: options) { [weak self, weak source] _ in
            // Resolve the current source by identity, including after row reuse.
            let currentSource = self?.sources[sourceID]?.view ?? source
            return currentSource?.superview == nil ? nil : currentSource
        }

        setState(.presenting(session))
        host.present(controller, animated: true) { [weak self, weak controller] in
            guard let self, let controller, self.state.session === session else { return }
            if controller.presentingViewController == nil {
                self.finish(session, reason: "presentation failed")
            } else if self.phase == .presenting {
                self.didAppear(controller)
            }
        }
        controller.presentationController?.delegate = self
        if controller.presentingViewController == nil {
            // UIKit doesn't call the completion for every rejected presentation.
            finish(session, reason: "presentation rejected")
        }
    }

    func dismiss() {
        guard let session = state.session else { return }
        guard case .presented = state else {
            // X during opening or an interactive cancellation is serviced once
            // that transition settles, without starting a competing dismissal.
            session.closeRequested = true
            return
        }
        setState(.dismissing(session))
        session.controller.dismiss(animated: true) { [weak self] in
            self?.finish(session, reason: "close completed")
        }
    }

    fileprivate func didAppear(_ controller: PreviewController) {
        guard let session = state.session, session.controller === controller else { return }
        // An interactive cancellation keeps this preview open.
        session.nextPreview = nil
        setState(.presented(session))
        if session.closeRequested {
            session.closeRequested = false
            DispatchQueue.main.async { [weak self] in
                guard let self, self.state.session === session else { return }
                self.dismiss()
            }
        }
    }

    fileprivate func willDismiss(_ controller: PreviewController) {
        guard let session = state.session, session.controller === controller else { return }
        setState(.dismissing(session))
        guard let transition = controller.transitionCoordinator else { return }
        transition.notifyWhenInteractionChanges { [weak self] context in
            self?.logger.debug("Interactive release; cancelled=\(context.isCancelled)")
            // The finger lifting isn't completion: retain the session through
            // the remainder of the native dismissal or cancellation spring.
        }
        transition.animate(alongsideTransition: nil) { [weak self] context in
            guard let self, self.state.session === session else { return }
            if context.isCancelled {
                self.restoreSource(session)
                self.didAppear(controller)
            } else {
                self.finishWhenDetached(session)
            }
        }
    }

    fileprivate func didDisappear(_ controller: PreviewController) {
        guard let session = state.session, session.controller === controller else { return }
        // Backstop only. Transition completion and presentation delegates own
        // normal cleanup; disappearance alone doesn't mean dismissal succeeded.
        finishWhenDetached(session)
    }

    private func finishWhenDetached(_ session: Session) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.state.session === session,
                  session.controller.presentingViewController == nil else { return }
            self.finish(session, reason: "dismissal completed")
        }
    }

    func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
        guard let controller = presentationController.presentedViewController as? PreviewController else { return }
        willDismiss(controller)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard let session = state.session,
              session.controller === presentationController.presentedViewController else { return }
        finish(session, reason: "interactive dismissal completed")
    }

    private func restoreSource(_ session: Session) {
        // UIKit owns hiding while zooming. Always repair both an original and
        // a replacement registered source after a completed/failed transition.
        for source in [session.source, sources[session.sourceID]?.view].compactMap({ $0 }) {
            source.isHidden = false
            source.alpha = 1
        }
    }

    private func finish(_ session: Session, reason: String) {
        guard state.session === session else { return }
        // Keep modal ownership until dismissal completes. UIKit independently
        // controls when the underlying screen can receive touches again.
        restoreSource(session)
        session.controller.presentationOwner = nil
        session.controller.presentationController?.delegate = nil
        setState(.idle)
        logger.debug("PreviewItem presentation ended: \(reason, privacy: .public)")
        if let next = session.nextPreview {
            DispatchQueue.main.async { [weak self] in
                // Revalidate the presenter and source after UIKit's cleanup.
                // Navigation away or a new modal should discard this request.
                guard let self, case .idle = self.state else { return }
                self.open(
                    item: next.item,
                    sampleValues: next.sampleValues,
                    sourceID: next.sourceID
                )
            }
        }
    }

    private func presenterIsReady(_ host: UIViewController) -> Bool {
        guard host.viewIfLoaded?.window != nil else { return false }
        // Full-screen presentation may be forwarded to an ancestor. These
        // checks gate a new preview, never input on the underlying screen.
        var presenter: UIViewController? = host
        while let controller = presenter {
            guard controller.presentedViewController == nil,
                  !controller.isBeingPresented, !controller.isBeingDismissed,
                  controller.transitionCoordinator == nil else { return false }
            presenter = controller.parent
        }
        return true
    }

    private func setState(_ state: State) {
        guard self.state.phase != state.phase || self.state.session !== state.session else { return }
        objectWillChange.send()
        self.state = state
        logger.debug("PreviewItem presentation phase: \(state.phase.rawValue, privacy: .public)")
    }
}

/// Shared only by one preview's scroll callback and its native zoom options.
/// Updating this state never redraws the gallery or its transition source.
nonisolated final class PreviewScrollState {
    // Keep access on the main actor without requiring isolated destruction.
    @MainActor var isAtTop = true

    @MainActor
    func allowsDismissal(velocity: CGVector, systemWouldBegin: Bool) -> Bool {
        guard systemWouldBegin else { return false }
        if abs(velocity.dy) > abs(velocity.dx) {
            // Upward drags reveal details; downward drags return to the top
            // before a new pull can dismiss. UIKit still owns the animation.
            return isAtTop && velocity.dy > 0
        }
        // Preserve UIKit's decision for horizontal and non-directional gestures.
        return true
    }
}

/// Native zoom callbacks feed the same coordinator as the SwiftUI X button.
fileprivate final class PreviewController: UIHostingController<PreviewScreen> {
    weak var presentationOwner: ZoomPresentationCoordinator?
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentationOwner?.didAppear(self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed { presentationOwner?.willDismiss(self) }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        presentationOwner?.didDisappear(self)
    }
}

struct ZoomPresentationHost: UIViewControllerRepresentable {
    let presentation: ZoomPresentationCoordinator

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        presentation.attach(host: controller)
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    func makeCoordinator() -> ZoomPresentationCoordinator { presentation }

    static func dismantleUIViewController(_ controller: UIViewController, coordinator: ZoomPresentationCoordinator) {
        coordinator.detach(host: controller)
    }
}

/// The displayed image is also the native zoom source; no duplicated thumbnail
/// or SwiftUI visibility flag needs to be synchronized with UIKit.
struct ZoomSourceView: UIViewRepresentable {
    @ObservedObject var imageLoader: ImageLoader
    let sourceID: String
    let presentation: ZoomPresentationCoordinator

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.clipsToBounds = true
        view.layer.cornerRadius = 8
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.accessibilityIdentifier = sourceID
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        presentation.register(view, id: sourceID)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        if let image = imageLoader.image {
            view.image = image
            view.contentMode = .scaleAspectFit
        } else {
            view.image = UIImage(systemName: "photo", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24))
            view.contentMode = .center
            view.tintColor = UIColor(DemoStyle.textSecondary)
        }
    }

    func makeCoordinator() -> ZoomPresentationCoordinator { presentation }

    static func dismantleUIView(_ view: UIImageView, coordinator: ZoomPresentationCoordinator) {
        // Match by object identity so a retiring row can't unregister its replacement.
        // Source IDs are stored on the view for this lifecycle callback.
        if let id = view.accessibilityIdentifier { coordinator.unregister(view, id: id) }
    }
}
