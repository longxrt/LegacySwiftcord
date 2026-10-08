//
//  WrapperLottieView.swift
//  Swiftcord
//
//  Created by Vincent Kwok on 23/2/22.
//

import AppKit
import Lottie

// Needed to have proper size with `frame` modifier
public final class WrapperAnimationView: NSView {
	let animationView: Lottie.LottieAnimationView!
    let width: Double!
    let height: Double!

	private let visibility = WindowVisibilityTracker()
	/// Whether the owner wants the animation playing; it only renders while visible on screen
	private var wantsPlay = false
	private var completion: LottieCompletionBlock?

	init(animation: Lottie.LottieAnimation?, width: Double, height: Double) {
        self.width = width
        self.height = height

		let animationView = LottieAnimationView(animation: animation)
        animationView.contentMode = .scaleAspectFit
        // animationView.widthAnchor
        animationView.translatesAutoresizingMaskIntoConstraints = false
        self.animationView = animationView

        super.init(frame: .zero)

        addSubview(animationView)
        NSLayoutConstraint.activate([
            animationView.centerXAnchor.constraint(equalTo: centerXAnchor),
            animationView.centerYAnchor.constraint(equalTo: centerYAnchor),
            animationView.heightAnchor.constraint(equalToConstant: height),
            animationView.widthAnchor.constraint(equalToConstant: width)
        ])
		visibility.onChange = { [weak self] _ in self?.applyPlaybackState() }
    }

	public override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		visibility.track(window)
	}

	fileprivate func applyPlaybackState() {
		if wantsPlay && visibility.isVisible {
			if !animationView.isAnimationPlaying { animationView.play(completion: completion) }
		} else if animationView.isAnimationPlaying {
			animationView.pause()
		}
	}

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension WrapperAnimationView {
    var loopMode: LottieLoopMode {
        get { animationView.loopMode }
        set { animationView.loopMode = newValue }
    }

    func play(completion: LottieCompletionBlock?) {
		wantsPlay = true
		self.completion = completion
		applyPlaybackState()
    }

    func stop() {
		wantsPlay = false
		applyPlaybackState()
    }
}
