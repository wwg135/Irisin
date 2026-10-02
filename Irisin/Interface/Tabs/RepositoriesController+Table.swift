//
//  RepositoriesController+Table.swift
//  Irisin
//
//  Created by Lakr Aream on 2021/8/17.
//

import AptRepository
import UIKit
import SPIndicator

extension RepositoriesController: UITableViewDelegate {
    func url(at indexPath: IndexPath) -> URL? {
        guard case let .repository(url) = diffableDataSource.itemIdentifier(for: indexPath) else { return nil }
        return url
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        refreshControl.listDidScroll(scrollView)
    }

    func tableView(_: UITableView, shouldBeginMultipleSelectionInteractionAt _: IndexPath) -> Bool {
        true
    }

    func tableView(_: UITableView, didBeginMultipleSelectionInteractionAt _: IndexPath) {
        setEditing(true, animated: true)
    }

    func tableView(_: UITableView, didDeselectRowAt _: IndexPath) {
        updateSelectionItems()
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView.isEditing {
            updateSelectionItems()
            return
        }
        tableView.deselectRow(at: indexPath, animated: true)
        guard let value = url(at: indexPath),
              let repo = RepositoryCenter
              .default
              .obtainImmutableRepository(withUrl: value)
        else {
            return
        }
        present(next: RepositoryDetailController(withRepo: repo))
    }

    func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt index: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let url = url(at: index) else { return nil }
        let deleteItem = UIContextualAction(
            style: .destructive,
            title: String(localized: "Delete")
        ) { [weak self] _, _, completion in
            self?.delete([url])
            // the swipe's own transaction has to end for the row to slide out
            completion(true)
        }
        deleteItem.backgroundColor = .swipeDelete
        let reloadItem = UIContextualAction(
            style: .normal,
            title: String(localized: "Refresh")
        ) { [weak self] _, _, completion in
            self?.refreshRepository(url)
            completion(true)
        }
        reloadItem.backgroundColor = .swipeRefresh
        return UISwipeActionsConfiguration(actions: [reloadItem, deleteItem])
    }

    func tableView(
        _ tableView: UITableView,
        leadingSwipeActionsConfigurationForRowAt index: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let url = url(at: index) else { return nil }
        // Pin / Unpin action on right-swipe (leading)
        let isPinned = RepositoriesController.isPinned(url)
        let pinTitle = isPinned ? String(localized: "Unpin") : String(localized: "Pin")
        let pinItem = UIContextualAction(
            style: .normal,
            title: pinTitle
        ) { [weak self] _, _, completion in
            RepositoriesController.togglePinned(url)
            self?.reloadDataSource()
            SPIndicator.present(title: isPinned ? String(localized: "Unpinned") : String(localized: "Pinned"), preset: .done)
            completion(true)
        }
        // Use design token for swipe action background
        pinItem.backgroundColor = UIColor.buttonNormal

        let shareItem = UIContextualAction(
            style: .normal,
            title: String(localized: "Share")
        ) { [weak self] _, _, completion in
            completion(true)
            self?.share(url, from: tableView.cellForRow(at: index))
        }
        shareItem.backgroundColor = .swipeShare
        return UISwipeActionsConfiguration(actions: [pinItem, shareItem])
    }

    // MARK: - Section headers for card groups

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            // Only show "Pinned" when we actually have pinned items
            let pinnedCount = Self.pinnedRepositoryUrls().isEmpty ? 0 : diffableDataSource.snapshot().numberOfItems(inSection: 0)
            return pinnedCount > 0 ? String(localized: "Pinned") : nil
        case 1:
            // If there are no items in section 1 (and section 0 has items), don't show header
            let otherCount = diffableDataSource.snapshot().numberOfItems(inSection: 1)
            return otherCount > 0 ? String(localized: "Repositories") : nil
        default:
            return nil
        }
    }
}
