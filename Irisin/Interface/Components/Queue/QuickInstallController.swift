//
//  QuickInstallController.swift
//  Irisin
//

import AptRepository
import AptResolver
import Combine
import Dog
import UIKit

/// An install or update asked for on the package's page, done in a sheet
/// over that page: the files download with a bar, then the transaction runs
/// with a bar of its own, then the button says Done. A package built for
/// another bootstrap is patched between the two, as Patch on the queue page
/// would, and what that adds to the plan (the compat layer) downloads too.
/// The change is still the queue's (`PackageQueue` solves, commits and starts the downloads), so
/// everything the queue checks is checked; the sheet only takes the steps
/// the queue page and the change sheet would have asked the user for.
/// A change that is more than the one package (other queued work, a removal,
/// a notice) is not taken here: `start` answers false and the change sheet
/// shows it.
final class QuickInstallController: UIViewController {
    private enum Phase {
        case downloading, preparing, installing
        case finished(OperationMonitor.Ending)
        case failed(String)
    }

    private var plan: ResolutionPlan
    private let packageName: String
    private weak var host: UIViewController?
    private var phase = Phase.downloading
    private var work: Task<Void, Never>?
    private var monitor: OperationMonitor?
    private var subscriptions = Set<AnyCancellable>()

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

    private let progressView = UIProgressView(progressViewStyle: .default).then {
        $0.progressTintColor = .buttonNormal
    }

    private lazy var primaryButton = UIButton(type: .system).then {
        $0.addAction(UIAction { [weak self] _ in self?.primaryTapped() }, for: .touchUpInside)
    }

    private lazy var queueButton = UIButton(type: .system).then {
        var configuration = UIButton.Configuration.plain()
        configuration.title = String(localized: "Open Queue")
        $0.configuration = configuration
        $0.isHidden = true
        $0.addAction(UIAction { [weak self] _ in self?.openQueue() }, for: .touchUpInside)
    }

    private init(plan: ResolutionPlan, packageName: String, host: UIViewController) {
        self.plan = plan
        self.packageName = packageName
        self.host = host
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Use start(_:from:)")
    }

    // MARK: - Entry

    /// Commits the change and presents the sheet. False when the change is
    /// not this sheet's to take, with the queue as it was.
    static func start(_ actions: [ResolutionAction], from host: UIViewController) async -> Bool {
        let queue = PackageQueue.shared
        guard !Installer.shared.inProcessingQueue, queue.cleanup.isEmpty, queue.blocked == nil,
              Set(queue.actions.map(\.identity)).isSubset(of: Set(actions.map(\.identity))),
              case let .success(proposal) = await queue.propose(actions),
              proposal.notices.isEmpty, proposal.cleanup.isEmpty,
              Set(proposal.actions.map(\.identity)) == Set(actions.map(\.identity)),
              let plan = proposal.plan, plan.remove.isEmpty, !plan.recoveryMode,
              !plan.install.isEmpty, QueueInstallChecks.hasDpkg(plan),
              await queue.currency(of: proposal) == .current,
              queue.commit(proposal),
              let first = actions.first,
              let package = plan.install.first(where: { $0.identity == first.identity }) ?? plan.install.first
        else { return false }
        queue.quickInstallActive = true
        let controller = QuickInstallController(
            plan: plan,
            packageName: PackageCenter.default.name(of: package),
            host: host
        )
        host.present(UINavigationController.halfSheet(root: controller), animated: true)
        return true
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        isModalInPresentation = true
        navigationController?.isModalInPresentation = true
        navigationController?.navigationBar.prefersLargeTitles = false
        nameLabel.text = packageName
        let stack = UIStackView(arrangedSubviews: [nameLabel, statusLabel, progressView, primaryButton, queueButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16
        view.addSubview(stack)
        stack.snp.makeConstraints { x in
            x.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(24)
            x.centerY.equalTo(view.safeAreaLayoutGuide).offset(-20)
        }
        primaryButton.snp.makeConstraints { $0.height.equalTo(48) }
        apply(.downloading)
        work = Task { [weak self] in await self?.run() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || navigationController?.isBeingDismissed == true else { return }
        release()
    }

    private func release() {
        work?.cancel()
        PackageQueue.shared.quickInstallActive = false
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
                let failure = await QueueController.awaitDownloads(of: pending, in: current.id) { [weak self] in
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
        guard await OperationConfirmation.confirm() else {
            return close()
        }
        guard !Task.isCancelled else { return }
        let payload = await Installer.shared.createOperationPayload(plan: plan)
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
                self?.progressView.setProgress(progress.fraction, animated: true)
            }
            .store(in: &subscriptions)
        // not tied to the task: a dismissed sheet leaves the helper running
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
        progressView.setProgress(fraction, animated: true)
        let percent = NumberFormatter.localizedString(from: NSNumber(value: fraction), number: .percent)
        statusLabel.text = String(localized: "Downloading…") + " " + percent
    }

    // MARK: - Presentation

    private func apply(_ next: Phase) {
        phase = next
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .large
        queueButton.isHidden = true
        navigationItem.leftBarButtonItem = nil
        switch next {
        case .downloading:
            title = String(localized: "Downloading…")
            statusLabel.text = String(localized: "Downloading…")
            progressView.isHidden = false
            progressView.setProgress(0, animated: false)
            configuration = .tinted()
            configuration.title = String(localized: "Cancel")
        case .preparing:
            title = String(localized: "Preparing…")
            statusLabel.text = String(localized: "Preparing…")
            progressView.setProgress(0, animated: false)
            configuration.title = String(localized: "Installing…")
            primaryButton.isEnabled = false
        case .installing:
            title = String(localized: "Installing…")
            statusLabel.text = String(localized: "Installing…")
            progressView.isHidden = false
            configuration.title = String(localized: "Installing…")
            primaryButton.isEnabled = false
        case let .finished(ending):
            title = String(localized: "Completed")
            statusLabel.text = String(localized: "Operation completed.")
            progressView.isHidden = false
            progressView.setProgress(1, animated: true)
            progressView.progressTintColor = .operationSucceeded
            configuration.baseBackgroundColor = .operationSucceeded
            configuration.title = ending == .reloadHomeScreen
                ? String(localized: "Reload Home Screen")
                : String(localized: "Done")
            primaryButton.isEnabled = true
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Operation completed."))
        case let .failed(reason):
            title = String(localized: "Failed")
            statusLabel.text = reason
            progressView.isHidden = true
            configuration.baseBackgroundColor = .operationFailed
            configuration.title = String(localized: "Done")
            primaryButton.isEnabled = true
            queueButton.isHidden = false
            if let monitor {
                navigationItem.leftBarButtonItem = UIBarButtonItem(
                    title: String(localized: "View Full Log"),
                    primaryAction: UIAction { [weak self] _ in
                        self?.navigationController?.pushViewController(
                            OperationLogController(monitor: monitor), animated: true
                        )
                    }
                )
            }
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
        case .finished, .failed:
            close()
        case .preparing, .installing:
            break
        }
    }

    private func openQueue() {
        let host = host
        dismiss(animated: true) {
            host.flatMap(InterfaceHostController.enclosing)?.openQueue()
        }
    }

    private func close() {
        (navigationController ?? self).dismiss(animated: true)
    }
}
