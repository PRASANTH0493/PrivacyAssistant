//
//  ViewController.swift
//  SaforaPrivacy
//
//  Reference integration of PrivacyAssistant: Start, Stop and a result label.
//

import UIKit

@MainActor
final class ViewController: UIViewController {

    private lazy var privacy = PrivacyAssistant(hostView: view)
    private let resultLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        var start = UIButton.Configuration.filled()
        start.title = "Start"
        var stop = UIButton.Configuration.tinted()
        stop.title = "Stop"

        resultLabel.text = "Detection is off"
        resultLabel.font = .preferredFont(forTextStyle: .headline)
        resultLabel.adjustsFontForContentSizeCategory = true
        resultLabel.textAlignment = .center
        resultLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [
            UIButton(configuration: start, primaryAction: UIAction { [weak self] _ in
                Task {
                    guard let self else { return }
                    if await self.privacy.start() == false {
                        self.resultLabel.text = "Could not start. Check camera access."
                    }
                }
            }),
            UIButton(configuration: stop, primaryAction: UIAction { [weak self] _ in
                Task { await self?.privacy.stop() }
            }),
            resultLabel
        ])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20)
        ])

        privacy.onFaceCountChange = { [weak self] count in
            switch count {
            case nil: self?.resultLabel.text = "Detection is off"
            case 0?: self?.resultLabel.text = "No face in view"
            case 1?: self?.resultLabel.text = "No second face looking at your screen"
            case let count?: self?.resultLabel.text = "Second face looking at your screen (\(count) faces)"
            }
        }
    }
}
