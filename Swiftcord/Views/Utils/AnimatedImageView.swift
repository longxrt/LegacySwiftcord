//
//  AnimatedImageView.swift
//  Swiftcord
//

import SwiftUI
import SDWebImage

/// Displays a remote animated image (GIF, APNG, animated WebP) using SDWebImage.
///
/// Images are downloaded, cached on disk and in memory, and decoded off the main
/// thread. Frames only advance while the view is in a window that's visible on
/// screen, and decoded frames are released whenever playback stops.
final class AnimatedImageNSView: NSView {
	private let imageView = SDAnimatedImageView()
	private let visibility = WindowVisibilityTracker()
	private var loadedURL: URL?

	/// Whether the owner wants the image to animate
	var isAnimating = true {
		didSet { applyAnimationState() }
	}
	/// Return to the first frame when stopped (e.g. server icons that animate on hover)
	var resetWhenStopped = false {
		didSet { imageView.resetFrameIndexWhenStopped = resetWhenStopped }
	}

	init() {
		super.init(frame: .zero)
		imageView.autoPlayAnimatedImage = false
		imageView.imageScaling = .scaleProportionallyUpOrDown
		// Free decoded frames while paused instead of holding them in memory
		imageView.clearBufferWhenStopped = true
		visibility.onChange = { [weak self] _ in self?.applyAnimationState() }
		addSubview(imageView)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func load(_ url: URL) {
		guard url != loadedURL else { return }
		loadedURL = url
		imageView.sd_setImage(with: url, placeholderImage: nil, options: [.retryFailed]) { [weak self] _, _, _, _ in
			self?.applyAnimationState()
		}
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		visibility.track(window)
	}

	override func layout() {
		super.layout()
		imageView.frame = bounds
	}

	private func applyAnimationState() {
		// On macOS, SDAnimatedImageView's playback is driven by NSImageView.animates
		let shouldAnimate = isAnimating && visibility.isVisible
		if imageView.animates != shouldAnimate { imageView.animates = shouldAnimate }
	}
}

struct AnimatedImageView: NSViewRepresentable {
	let url: URL
	var animating = true
	var resetWhenNotAnimating = false

	func makeNSView(context: Context) -> AnimatedImageNSView {
		let view = AnimatedImageNSView()
		updateNSView(view, context: context)
		return view
	}

	func updateNSView(_ view: AnimatedImageNSView, context: Context) {
		view.resetWhenStopped = resetWhenNotAnimating
		view.isAnimating = animating
		view.load(url)
	}
}
