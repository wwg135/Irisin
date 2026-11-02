//
//  QueueMode.swift
//  Irisin
//

import Foundation

nonisolated extension Notification.Name {
    static let QueueModeChanged = Notification.Name("wiki.qaq.QueueModeChanged")
}

/// How a request for a package is carried out. Off, the queue: a change
/// joins the queue, which downloads, waits and runs on Execute, with its
/// page, tab and bar. On, Lightweight Mode: the change runs at once in a
/// popup, and repositories can be pinned to the top of their list.
@MainActor
enum QueueMode {
    private static let store = Stored(key: "package.lightweightMode", defaultValue: false)

    static var isLightweight: Bool {
        get { store.wrappedValue }
        set {
            guard newValue != store.wrappedValue else { return }
            store.wrappedValue = newValue
            // the popup takes a change only into an empty queue
            if newValue, !Installer.shared.inProcessingQueue {
                PackageQueue.shared.clear()
            }
            NotificationCenter.default.post(name: .QueueModeChanged, object: nil)
        }
    }
}
