//
//  PackageMenu+Installed.swift
//  Irisin
//

import AptRepository
import AptResolver
import UIKit

/// What the Installed page asks for without opening a package: a swipe on a
/// row and the bar of a selection. Both are the package menu's own actions,
/// decided by the same eligibility and run by the same blocks.
extension PackageMenu {
    /// What a swipe offers, from the trailing edge in: an installed package
    /// is removed, and updated or reinstalled when a repository has the
    /// version for it.
    static let swipeDescriptors: [Action] = [.remove, .update, .reinstall]

    /// `eligible` narrowed to what a swipe offers, in the swipe's order.
    static func swipeOrder(of eligible: [Action]) -> [Action] {
        swipeDescriptors.filter(eligible.contains)
    }

    /// The swipe actions of a dpkg row, with the package each one is made
    /// with: the one the package page's button would use.
    static func swipeActions(forInstalled row: Package) -> (package: Package, actions: [Item]) {
        let package = requestPackage(for: row)
        let eligible = eligibleActions(for: package)
        let actions = swipeOrder(of: eligible.map(\.descriptor)).compactMap { descriptor in
            eligible.first { $0.descriptor == descriptor }
        }
        return (package, actions)
    }

    /// The update of a dpkg row as a request, nil when the menu would not
    /// offer Update: no newer version or a blocked update. A commercial
    /// package is left out too: its download
    /// link is the vendor's answer to one purchase check, made on its own
    /// page. This is the batch path and it skips `keeps(_:from:)`: that
    /// alert talks about one package with its page one tap away, and a
    /// selection gets the candidate the Updates page would take.
    static func updateRequest(forInstalled row: Package) -> ResolutionAction? {
        let package = requestPackage(for: row)
        guard package.isSupportedOnDevice, !package.isCommercial,
              eligibleActions(for: package).contains(where: { $0.descriptor == .update }),
              let version = package.latestVersion,
              let selected = PackageCenter.default.trim(package: package, toVersion: version)
        else { return nil }
        return .install(selected)
    }

    /// What Remove on a selection asks for, and the rows it cannot speak
    /// for. A row the menu offers Remove for is removed.
    static func removal(
        ofInstalled rows: [Package]
    ) -> (actions: [ResolutionAction], leftOut: [Package]) {
        var removes: [ResolutionAction] = []
        var leftOut: [Package] = []
        for row in rows {
            let offered = eligibleActions(for: requestPackage(for: row)).map(\.descriptor)
            if offered.contains(.remove) {
                removes.append(.remove(row.identity))
            } else {
                leftOut.append(row)
            }
        }
        return (removes, leftOut)
    }

    /// Whether `removal(ofInstalled:)` has a request for these rows, asked
    /// at every change of a selection: it stops at the first row that says
    /// yes, where the request itself reads every row.
    static func canRemove(anyOfInstalled rows: [Package]) -> Bool {
        rows.contains { eligibleActions(for: requestPackage(for: $0)).contains { $0.descriptor == .remove } }
    }
}
