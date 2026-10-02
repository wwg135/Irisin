//
//  RepositoryTableCell.swift
//  Irisin
//
//  Created by Lakr Aream on 2020/4/19.
//  Copyright © 2020 Lakr Aream. All rights reserved.
//

import SnapKit
import UIKit

class RepositoryTableCell: UITableViewCell {
    let coordinatedCell = RepositoryRow()

    private let updateFill = RepositoryUpdateFill()

    /// Container that provides the card background for each row.
    private let cardBackground = UIView()

    /// Padding around the repository row's content inside the card.
    var contentInsets: UIEdgeInsets = .zero {
        didSet {
            coordinatedCell.snp.remakeConstraints { x in
                x.edges.equalToSuperview().inset(contentInsets)
            }
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        // A selection style of none also stops the editing checkmark from
        // filling in; keep the style and blank the highlight instead.
        selectionStyle = .default
        selectedBackgroundView = UIView()
        multipleSelectionBackgroundView = UIView()
        backgroundColor = .clear

        // Card background sits inside contentView and holds the row contents.
        contentView.addSubview(cardBackground)
        cardBackground.snp.makeConstraints { x in
            // match inset grouped spacing a bit tighter
            x.edges.equalToSuperview().inset(UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 12))
        }
        cardBackground.backgroundColor = UIColor.secondarySystemGroupedBackground
        cardBackground.layer.cornerRadius = 12
        cardBackground.clipsToBounds = true
        cardBackground.layer.borderWidth = 1
        cardBackground.layer.borderColor = UIColor.separator.withAlphaComponent(0.08).cgColor

        // The update fill and the coordinated cell live inside the card.
        cardBackground.addSubview(updateFill)
        cardBackground.addSubview(coordinatedCell)
        updateFill.snp.makeConstraints { x in
            x.edges.equalToSuperview()
        }
        coordinatedCell.snp.makeConstraints { x in
            x.edges.equalToSuperview().inset(contentInsets)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func setRepository(withUrl: URL) {
        coordinatedCell.setRepository(withUrl: withUrl)
        updateFill.url = withUrl
    }

    func setNoRepoAvailable() {
        coordinatedCell.setNoRepoAvailable()
        updateFill.url = nil
    }
}
