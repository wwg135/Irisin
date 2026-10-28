//
//  PackageBannerView+Actions.swift
//  Irisin
//
//  Created by Lakr Aream on 2021/8/20.
//  Copyright © 2021 Lakr Aream. All rights reserved.
//

import AptRepository
import UIKit

extension PackageBannerView {
    /// The install button's menu, rebuilt from the package's eligible
    /// actions every time it opens. The navigation bar and a long press on a
    /// cell show the same one.
    var actionMenu: UIMenu {
        UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                guard let self, let host = parentViewController else { return completion([]) }
                completion(PackageMenu.menuElements(for: package, from: host))
            },
        ])
    }

    /// A tap runs the quick action; a long press opens the menu. A package built for
    /// another bootstrap only explains itself. The title
    /// dims the moment the tap lands and comes back once the action has run.
    @objc
    func performQuickAction() {
        // the page, taken now: the banner may leave it while the action runs
        guard let host = parentViewController else { return }
        guard package.isSupportedOnDevice || package.localFileURL != nil else {
            PackageMenu.presentUnsupportedArchitecture(of: package, from: host)
            return
        }
        guard let action = obtainQuickAction() else { return }
        button.titleLabel?.alpha = 0.5
        Task {
            await action.block(package, host, PopoverAnchor(button))
            button.titleLabel?.alpha = 1
        }
    }

    /// What a tap does: the first eligible action for a file or a package
    /// that is not installed, Update for one that is and has a newer
    /// version, Reinstall for one at the offered version. nil when the tap opens the menu instead.
    func obtainQuickAction() -> PackageMenu.Item? {
        let actions = PackageMenu.eligibleActions(for: package)
        guard package.localFileURL == nil,
              PackageCenter.default.obtainPackageInstallationInfo(with: package.identity) != nil
        else { return actions.first }
        return actions.first { $0.descriptor == .update }
            ?? actions.first { $0.descriptor == .reinstall }
    }
}
