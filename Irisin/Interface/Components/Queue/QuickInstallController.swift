//
//  QuickInstallController.swift
//  Irisin
//

import AptRepository
import AptResolver
import AlertController
import Combine
import Dog
import UIKit

private final class ProgressIndicator: UIView {
    private let bar = UIProgressView(progressViewStyle: .default).then {
        $0.progressTintColor = .buttonNormal
    }

    private let percentageLabel = UILabel().then {
        $0.font = .monospacedDigit(.caption)
        $0.textColor = .textSubtitle
        $0.textAlignment = .center
    }

    private var fraction: Float = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(bar)
        addSubview(percentageLabel)
        bar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 2),
        ])
        setProgress(0, animated: false)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 30)
    }

    var progressTintColor: UIColor {
        get { bar.progressTintColor }
        set { bar.progressTintColor = newValue }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        percentageLabel.sizeToFit()
        let labelWidth = percentageLabel.bounds.width
        let center = bounds.width * CGFloat(fraction)
        let x = min(max(center - labelWidth / 2, 0), max(bounds.width - labelWidth, 0))
        percentageLabel.frame = CGRect(x: x, y: 0, width: labelWidth, height: bounds.height - 2)
    }

    func setProgress(_ progress: Float, animated: Bool) {
        let next = min(max(progress, 0), 1)
        let percent = NumberFormatter.localizedString(from: NSNumber(value: next), number: .percent)
        guard animated, next > fraction, window != nil else {
            fraction = next
            percentageLabel.text = percent
            bar.moveProgress(to: next)
            setNeedsLayout()
            return
        }

        layoutIfNeeded()
        fraction = next
        percentageLabel.text = percent
        setNeedsLayout()
        UIView.animateProgress {
            self.layoutIfNeeded()
        }
        bar.moveProgress(to: next)
    }
}

/// An install, update or removal asked for anywhere in the app, done in a
/// popup centered over the page: the files download with a bar, then the
/// transaction runs with a bar of its own, then the button says Done. A
/// package built for another bootstrap is patched between the download and
/// installation steps. `PackageQueue` still solves and validates the plan;
/// a change this popup cannot take is not started, and `start` explains why.
final class QuickInstallController: UIViewController {
    private enum Phase {
        case downloading, preparing, installing
        case finished(OperationMonitor.Ending)
        case failed(String)
    }

    private var plan: ResolutionPlan
    private let packageName: String
    private var phase = Phase.downloading
    private var work: Task<Void, Never>?
    private var monitor: OperationMonitor?
    private var subscriptions = Set<AnyCancellable>()
    private let noticesLabel = UILabel().then {
        $0.font = .caption
        $0.textColor = .textSubtitle
        $0.numberOfLines = 0
    }

    private let nameLabel = UILabel().then {
        $0.font = .title
        $0.textColor = .textTitle
        $0.textAlignment = .center
        $0.numberOfLines = 0
    }

    private let statusLabel = UILabel().then {
        $0.font = .body
        $0.textColor = .textSubtitle
        $0.textAlignment = .center
        $0.numberOfLines = 0
    }

    private let progressIndicator = ProgressIndicator()

    private lazy var primaryButton = UIButton(type: .system).then {
        $0.addAction(UIAction { [weak self] _ in self?.primaryTapped() }, for: .touchUpInside)
    }

    private lazy var logButton = UIButton(type: .system).then {
        var configuration = UIButton.Configuration.plain()
        configuration.title = String(localized: "View Full Log")
        $0.configuration = configuration
        $0.isHidden = true
        $0.addAction(UIAction { [weak self] _ in self?.showLog() }, for: .touchUpInside)
    }

    private let card = UIView().then {
        $0.backgroundColor = .groupedBackground
        $0.layer.cornerRadius = 20
        $0.layer.cornerCurve = .continuous
    }

    private init(plan: ResolutionPlan, packageName: String, notices: [String]) {
        self.plan = plan
        self.packageName = packageName
        super.init(nibName: nil, bundle: nil)
        noticesLabel.text = notices.joined(separator: "\n")
        noticesLabel.isHidden = notices.isEmpty
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Use start(_:from:)")
    }

    // MARK: - Entry

    /// Commits the change and presents the popup. Nil on success; otherwise
    /// the reason the change is not this popup's to take, with the queue as
    /// it was.
    static func start(
        _ actions: [ResolutionAction],
        notices: [String] = [],
        from host: UIViewController
    ) async -> String? {
        let queue = PackageQueue.shared
        let generic = String(localized: "Unable to prepare this operation. Try again.")
        guard !Installer.shared.inProcessingQueue, queue.cleanup.isEmpty, queue.blocked == nil,
              Set(queue.actions.map(\.identity)).isSubset(of: Set(actions.map(\.identity)))
        else { return generic }
        let proposal: PackageQueue.Proposal
        switch await queue.propose(actions, notices: notices) {
        case let .success(solved): proposal = solved
        case let .failure(failure): return failure.message
        }
        guard proposal.cleanup.isEmpty,
              Set(proposal.actions.map(\.identity)) == Set(actions.map(\.identity)),
              let plan = proposal.plan, !plan.recoveryMode,
              !plan.install.isEmpty || !plan.remove.isEmpty,
              let first = actions.first,
              let package = plan.install.first(where: { $0.identity == first.identity })
              ?? plan.remove.first(where: { $0.identity == first.identity })
              ?? plan.install.first ?? plan.remove.first
        else { return generic }
        guard await queue.currency(of: proposal) == .current, queue.commit(proposal) else {
            return generic
        }
        let controller = QuickInstallController(
            plan: plan,
            packageName: PackageCenter.default.name(of: package),
            notices: proposal.notices
        )
        host.present(controller, animated: true)
        return nil
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .popupScrim
        nameLabel.text = packageName
        let stack = UIStackView(arrangedSubviews: [
            nameLabel, statusLabel, noticesLabel, progressIndicator, primaryButton, logButton,
        ])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16
        view.addSubview(card)
        card.addSubview(stack)
        card.snp.makeConstraints { x in
            x.center.equalTo(view.safeAreaLayoutGuide)
            x.leading.greaterThanOrEqualTo(view.safeAreaLayoutGuide).offset(24)
            x.trailing.lessThanOrEqualTo(view.safeAreaLayoutGuide).offset(-24)
            x.width.equalTo(360).priority(750)
        }
        stack.snp.makeConstraints { $0.edges.equalToSuperview().inset(24) }
        primaryButton.snp.makeConstraints { $0.height.equalTo(48) }
        apply(plan.install.contains { $0.localFileURL == nil } ? .downloading : .preparing)
        work = Task { [weak self] in await self?.run() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed else { return }
        release()
    }

    private func release() {
        work?.cancel()
    }

    // MARK: - Steps

    private func run() async {
        // Patch may change the plan, and what it adds is downloaded in turn
        for _ in 0 ..< 4 {
            guard let current = PackageQueue.shared.plan, PackageQueue.shared.blocked == nil else {
                return apply(.failed(PackageQueue.shared.blocked ?? String(localized: "Unable to prepare this operation. Try again.")))
            }
            plan = current
            let pending = current.install.filter { $0.localFileURL == nil }
            if !pending.isEmpty {
                apply(.downloading)
                let failure = await Downloads.shared.awaitFiles(of: pending, in: current.id) { [weak self] in
                    self?.showDownloadProgress(of: pending)
                }
                guard !Task.isCancelled else { return }
                if let failure {
                    Dog.shared.join("QuickInstall", "download failed: \(failure)", level: .error)
                    return apply(.failed(failure))
                }
                // a plan that replaced this one is looked at again
                guard PackageQueue.shared.plan?.id == current.id else { continue }
            }
            guard !PackageQueue.shared.unpatched.isEmpty else { break }
            apply(.preparing)
            if case let .failure(reason) = await PackageQueue.shared.patch() {
                return apply(.failed(reason.message))
            }
            guard !Task.isCancelled else { return }
        }
        guard let plan = PackageQueue.shared.plan, PackageQueue.shared.unpatched.isEmpty,
              plan.install.allSatisfy({ $0.localFileURL != nil || Downloads.shared.status(for: $0.obtainDownloadLink())?.file != nil })
        else {
            return apply(.failed(String(localized: "Unable to prepare this operation. Try again.")))
        }
        self.plan = plan
        apply(.preparing)
        var bootstrapInstall = false
        if !QueueInstallChecks.hasDpkg(plan) {
            switch await askWithoutDpkg(offersBootstrap: plan.allowsBootstrapInstall) {
            case .cancel:
                PackageQueue.shared.clear()
                return close()
            case .bootstrapInstall:
                bootstrapInstall = true
            case .installAnyway:
                let names = await QueueInstallChecks.packagesRunningScripts(in: plan)
                if !names.isEmpty, !(await warnAboutScripts(names)) {
                    PackageQueue.shared.clear()
                    return close()
                }
            }
        }
        guard await OperationConfirmation.confirm() else {
            PackageQueue.shared.clear()
            return close()
        }
        guard !Task.isCancelled else { return }
        let payload = await Installer.shared.createOperationPayload(plan: plan, bootstrapInstall: bootstrapInstall)
        guard !Task.isCancelled else { return }
        guard let payload, !payload.transaction.stages.isEmpty else {
            let report = PackageActionReport.shared.allAvailable()
            return apply(.failed(report.isEmpty
                ? String(localized: "Unable to prepare this operation. Try again.")
                : report))
        }
        let monitor = Installer.shared.beginOperation(operation: payload)
        self.monitor = monitor
        apply(.installing)
        monitor.$progress
            .compactMap(\.self)
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] progress in
                self?.progressIndicator.setProgress(progress.fraction, animated: true)
            }
            .store(in: &subscriptions)
        // not tied to the task: dismissing the popup leaves the helper running
        switch await monitor.finished {
        case .succeeded:
            apply(.finished(monitor.ending))
        case let .failed(reason):
            apply(.failed(reason))
        }
    }

    private func showDownloadProgress(of packages: [Package]) {
        guard case .downloading = phase else { return }
        let statuses = packages.compactMap { Downloads.shared.status(for: $0.obtainDownloadLink()) }
        let total = statuses.reduce(Int64(0)) { $0 + $1.totalBytes }
        let done = statuses.reduce(Int64(0)) { $0 + ($1.file != nil ? max($1.completedBytes, $1.totalBytes) : $1.completedBytes) }
        let fraction = total > 0 ? Float(min(Double(done) / Double(total), 1)) : 0
        progressIndicator.setProgress(fraction, animated: true)
    }

    // MARK: - Presentation

    private func apply(_ next: Phase) {
        phase = next
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .large
        logButton.isHidden = true
        switch next {
        case .downloading:
            statusLabel.text = String(localized: "Downloading…")
            progressIndicator.isHidden = false
            progressIndicator.progressTintColor = .buttonNormal
            progressIndicator.setProgress(0, animated: false)
            configuration = .tinted()
            configuration.title = String(localized: "Cancel")
        case .preparing:
            statusLabel.text = String(localized: "Preparing…")
            progressIndicator.isHidden = true
            progressIndicator.progressTintColor = .buttonNormal
            progressIndicator.setProgress(0, animated: false)
            configuration.title = busyTitle
            primaryButton.isEnabled = false
        case .installing:
            statusLabel.text = busyTitle
            progressIndicator.isHidden = false
            progressIndicator.progressTintColor = .buttonNormal
            progressIndicator.setProgress(0, animated: false)
            configuration.title = busyTitle
            primaryButton.isEnabled = false
        case let .finished(ending):
            statusLabel.text = String(localized: "Operation completed.")
            progressIndicator.isHidden = false
            progressIndicator.progressTintColor = .operationSucceeded
            progressIndicator.setProgress(1, animated: true)
            configuration.baseBackgroundColor = .operationSucceeded
            configuration.title = ending == .reloadHomeScreen
                ? String(localized: "Reload Home Screen")
                : String(localized: "Done")
            primaryButton.isEnabled = true
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Operation completed."))
        case let .failed(reason):
            statusLabel.text = reason
            progressIndicator.isHidden = true
            configuration.baseBackgroundColor = .operationFailed
            configuration.title = String(localized: "Done")
            primaryButton.isEnabled = true
            logButton.isHidden = monitor == nil
        }
        primaryButton.configuration = configuration
    }

    private func primaryTapped() {
        switch phase {
        case .downloading:
            // takes the change back: nothing was installed
            work?.cancel()
            PackageQueue.shared.clear()
            release()
            close()
        case .finished(.reloadHomeScreen):
            dismiss(animated: true) {
                UIApplication.prepareForExitAndSuspend()
                Task { await PrivilegedBackend.run(.respring) }
            }
        case .finished(.updateApp):
            OwnRegistration.finishUpdate(from: self, registering: monitor?.operation.transaction.installsSelf ?? false)
        case .finished:
            close()
        case .failed:
            // nothing keeps a queue: the change that failed is dropped
            PackageQueue.shared.clear()
            close()
        case .preparing, .installing:
            break
        }
    }

    private func showLog() {
        guard let monitor else { return }
        present(UINavigationController(rootViewController: OperationLogController(monitor: monitor)), animated: true)
    }

    private func askWithoutDpkg(offersBootstrap: Bool) async -> QueueInstallChecks.DpkgAnswer {
        guard presentedViewController == nil, view.window != nil else { return .cancel }
        var message = String(localized: "dpkg is not installed on this system, so the tools the packages' scripts need may be missing.")
        if offersBootstrap {
            message += "\n\n" + String(localized: "Bootstrap Install places every package's files before any script runs.")
        }
        return await withCheckedContinuation { continuation in
            let alert = AlertViewController(
                title: String.LocalizationValue(String(localized: "dpkg Is Not Installed")),
                message: String.LocalizationValue(message)
            ) { context in
                if offersBootstrap {
                    context.addAction(title: "Bootstrap Install", attribute: .accent) {
                        context.dispose { continuation.resume(returning: .bootstrapInstall) }
                    }
                }
                context.addAction(title: "Install Anyway") {
                    context.dispose { continuation.resume(returning: .installAnyway) }
                }
                context.addAction(title: "Cancel") {
                    context.dispose { continuation.resume(returning: .cancel) }
                }
            }
            present(alert, animated: true)
        }
    }

    private func warnAboutScripts(_ names: [String]) async -> Bool {
        guard presentedViewController == nil, view.window != nil else { return false }
        let list = ListFormatter.localizedString(byJoining: names)
        let message = String.LocalizationValue(
            String(localized: "These packages run scripts that this system may not be able to run: \(list). The installation is likely to fail.")
        )
        return await withCheckedContinuation { continuation in
            let alert = AlertViewController(title: "Installation Likely to Fail", message: message) { context in
                context.addAction(title: "Cancel") {
                    context.dispose { continuation.resume(returning: false) }
                }
                context.addAction(title: "Install Anyway", attribute: .accent) {
                    context.dispose { continuation.resume(returning: true) }
                }
            }
            present(alert, animated: true)
        }
    }

    private func close() {
        dismiss(animated: true)
    }

    private var busyTitle: String {
        plan.install.isEmpty ? String(localized: "Removing…") : String(localized: "Installing…")
    }
}
