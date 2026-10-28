//
//  TabInterfaceController.swift
//  Irisin
//
//  Created by Lakr Aream on 2021/8/8.
//  Copyright © 2021 Lakr Aream. All rights reserved.
//

import UIKit

class TabInterfaceController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let dashboard = DashboardNavigator()
        let repositories = RepositoriesNavigator()
        let installed = InstalledNavigator()
        let search = SearchNavigator()

        if #available(iOS 18.0, *) {
            let searchTab = UISearchTab { _ in search }
            // iOS 26 set the search tab apart on its own; from iOS 27 that
            // place is the prominent tab's, and a search tab only takes it
            // unasked when it activates search by itself, which ours does not.
            //
            // Set through KVC, not `prominentTabIdentifier =`: the property
            // arrived in the iOS 27 SDK and the runners have Xcode 26, whose
            // SDK has no such symbol to compile against — `#available` guards
            // the call at run time, not the reference at build time. The name
            // is the property's own, so the effect is the same wherever this
            // was built. Put `prominentTabIdentifier = searchTab.identifier`
            // back the day the runner image ships Xcode 27.
            if #available(iOS 27.0, *) {
                setValue(searchTab.identifier, forKey: "prominentTabIdentifier")
            }
            tabs = [
                UITab(
                    title: dashboard.tabBarItem.title ?? "",
                    image: dashboard.tabBarItem.image,
                    identifier: "dashboard"
                ) { _ in dashboard },
                UITab(
                    title: repositories.tabBarItem.title ?? "",
                    image: repositories.tabBarItem.image,
                    identifier: "repositories"
                ) { _ in repositories },
                UITab(
                    title: installed.tabBarItem.title ?? "",
                    image: installed.tabBarItem.image,
                    identifier: "installed"
                ) { _ in installed },
                searchTab,
            ]
        } else {
            viewControllers = [dashboard, repositories, installed, search]
        }

        selectedIndex = 0
    }

    private var lastSelectedIndex: Int?
    private var tapCount = 0
    override func tabBar(_: UITabBar, didSelect _: UITabBarItem) {
        // Double tap to focus search or refresh repositories.
        if lastSelectedIndex == selectedIndex {
            tapCount += 1
            if tapCount >= 2 {
                lastSelectedIndex = nil
                let page = (selectedViewController as? UINavigationController)?.topViewController
                if let controller = page as? SearchController {
                    controller.searchController.searchBar.becomeFirstResponder()
                }
                if let controller = page as? InstalledController {
                    controller.searchController.searchBar.becomeFirstResponder()
                }
                if let controller = page as? RepositoriesController {
                    controller.refreshFromTab()
                }
            }
        } else {
            lastSelectedIndex = selectedIndex
            tapCount = 0
        }
    }
}
