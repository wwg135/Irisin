*** Begin Patch
*** Update File: Irisin/Interface/Tabs/RepositoriesController.swift
@@
-    private func applySnapshot(animatingDifferences: Bool) {
-        var snapshot = NSDiffableDataSourceSnapshot<Int, Row>()
-
-        // Cached order from data source
-        let urls = dataSourceCache
-
-        snapshot.appendSections([0])
-        snapshot.appendItems(urls.map { Row.repository($0) }, toSection: 0)
-
-        diffableDataSource.apply(snapshot, animatingDifferences: animatingDifferences)
-    }
+    private func applySnapshot(animatingDifferences: Bool) {
+        var snapshot = NSDiffableDataSourceSnapshot<Int, Row>()
+
+        // 全部仓库 URL（按照当前缓存顺序）
+        let allUrls = dataSourceCache
+
+        // 使用用户偏好的置顶列表做归一化比较
+        let pinnedSet = Set(Self.pinnedRepositoryUrls())
+
+        // 拆分为置顶和非置顶集合（保持 dataSourceCache 中的相对顺序）
+        let pinnedUrls = allUrls.filter { pinnedSet.contains(Self.normalizedRepositoryString($0)) }
+        let otherUrls = allUrls.filter { !pinnedSet.contains(Self.normalizedRepositoryString($0)) }
+
+        // 使用已有的排序逻辑对每一组内部排序（如果需要的话）
+        let pinnedOrdered = Self.orderedRepositoryUrls(pinnedUrls)
+        let othersOrdered = Self.orderedRepositoryUrls(otherUrls)
+
+        // 如果有置顶项，则先添加置顶分区（0），再添加其他分区（1）。如果没有置顶，则只添加其他分区（1）。
+        var sections: [Int] = []
+        if !pinnedOrdered.isEmpty {
+            sections.append(0)
+        }
+        sections.append(1)
+        snapshot.appendSections(sections)
+
+        if !pinnedOrdered.isEmpty {
+            let pinnedItems = pinnedOrdered.map { Row.repository($0) }
+            snapshot.appendItems(pinnedItems, toSection: 0)
+        }
+
+        let othersItems = othersOrdered.map { Row.repository($0) }
+        snapshot.appendItems(othersItems, toSection: 1)
+
+        diffableDataSource.apply(snapshot, animatingDifferences: animatingDifferences)
+    }
*** End Patch
