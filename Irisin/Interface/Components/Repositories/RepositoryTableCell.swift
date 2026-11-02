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

    /// The card Lightweight Mode draws each row on; the official list has none.
    private let cardBackground = UIView()

    /// Whether the row sits on a card, which is Lightweight Mode's list.
    var usesCard = false {
        didSet {
            guard usesCard != oldValue else { return }
            applyCard()
        }
    }

    /// Padding around the repository row.
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
        contentView.addSubview(cardBackground)
        cardBackground.addSubview(updateFill)
        cardBackground.addSubview(coordinatedCell)
        cardBackground.layer.cornerRadius = 12
        cardBackground.clipsToBounds = true
        cardBackground.layer.borderColor = UIColor.separator.withAlphaComponent(0.08).cgColor
        updateFill.snp.makeConstraints { x in
            x.edges.equalToSuperview()
        }
        coordinatedCell.snp.makeConstraints { x in
            x.edges.equalToSuperview()
        }
        applyCard()
    }

    private func applyCard() {
        cardBackground.snp.remakeConstraints { x in
            x.edges.equalToSuperview().inset(usesCard ? UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 12) : .zero)
        }
        cardBackground.backgroundColor = usesCard ? .cardBackground : .clear
        cardBackground.layer.cornerRadius = usesCard ? 12 : 0
        cardBackground.layer.borderWidth = usesCard ? 1 : 0
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
