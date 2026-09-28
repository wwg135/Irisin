*** Begin Patch
*** Update File: Irisin/Interface/Components/Repositories/RepositoryRow.swift
@@
     private var subscriptions = Set<AnyCancellable>()
+
+    // 监听来自控制器的置顶变更通知用键名
+    private static let pinnedChangedNotification = Notification.Name("irisinRepositoryPinnedChanged")
@@
     private func setIcon(_ image: UIImage?, of url: URL?) {
@@
     }
+
+    // 辅助：判断当前仓库是否已置顶（使用控制器的归一化方法）
+    private func isPinned() -> Bool {
+        guard let repoUrl else { return false }
+        return RepositoriesController.pinnedRepositoryUrls().contains(RepositoriesController.normalizedRepositoryString(repoUrl))
+    }
+
+    // 在构建长按菜单 / 上下文菜单时添加置顶项
+    private func pinActionIfNeeded() -> UIAction? {
+        guard let repoUrl else { return nil }
+
+        let pinned = isPinned()
+        let title = pinned ? String(localized: "取消置顶") : String(localized: "置顶")
+        let image = UIImage(named: "arrowUpCircle24Filled") ?? UIImage()
+
+        return UIAction(title: title, image: image) { _ in
+            RepositoriesController.togglePinned(repoUrl)
+            NotificationCenter.default.post(name: Self.pinnedChangedNotification, object: repoUrl)
+        }
+    }
*** End Patch
