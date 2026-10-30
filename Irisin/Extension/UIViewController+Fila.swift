//
//  UIViewController+Fila.swift
//  Irisin
//

import AptRepository
import UIKit

extension UIViewController {
    /// Where Fila comes from, and its identity there.
    private static let filaRepository = URL(string: "https://apt.owngoal.dev")!
    private static let filaIdentity = "wiki.qaq.fila"

    /// Opens the folder at `path` in Fila.
    func openInFila(path: String) {
        fila(host: "open", path: path)
    }

    /// Shows `path` selected in its folder in Fila.
    func revealInFila(path: String) {
        fila(host: "reveal", path: path)
    }

    /// Filza's filza://view/<path> (it has no reveal, so it opens the path),
    /// else the fila:// link from the README. With neither installed the
    /// sheet says so and offers the way to Fila: the OwnGoal Studio
    /// repository when it is not added yet, the package once it is. Filza
    /// is not ours to point anywhere.
    private func fila(host: String, path: String) {
        var filza = URLComponents()
        filza.scheme = "filza"
        filza.host = "view"
        filza.path = path
        if let url = filza.url, UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return
        }

        var components = URLComponents()
        components.scheme = "fila"
        components.host = host
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        if let url = components.url, UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return
        }

        let repository = RepositoryCenter.default.repositories.values
            .first { $0.url.host == Self.filaRepository.host }
        presentConfirmation(
            title: "Install Fila or Filza",
            message: "Neither Fila nor Filza is installed. Fila opens folders and files on this device and comes from the OwnGoal Studio repository.",
            confirmTitle: repository == nil ? "Add Repository" : "Install Fila"
        ) { [weak self] in
            guard let repository else {
                self?.present(
                    RepositoryAddController.sheet(initialInput: Self.filaRepository.absoluteString),
                    animated: true
                )
                return
            }
            // a repository added but not refreshed yet has no package to show
            if let package = PackageCenter.default.obtainPackage(with: Self.filaIdentity, in: repository.url) {
                self?.present(next: PackageController(package: package))
            } else {
                self?.present(next: RepositoryDetailController(withRepo: repository))
            }
        }
    }
}
