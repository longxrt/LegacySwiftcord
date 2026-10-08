//
//  WindowVisibility.swift
//  Swiftcord
//

import AppKit

/// Tracks whether an `NSView`'s window is actually visible on screen.
///
/// macOS marks a window as occluded when it's minimized, the app is hidden, it's on
/// another Space, it's fully covered by other windows, or the display is asleep or
/// locked. Animated content uses this to stop drawing (and waking the CPU/GPU)
/// when nobody can see it.
final class WindowVisibilityTracker {
	private(set) var isVisible = false
	/// Called on the main thread whenever ``isVisible`` changes
	var onChange: ((Bool) -> Void)?

	private var observer: NSObjectProtocol?

	/// Starts tracking `window`; pass `nil` when the view leaves its window.
	func track(_ window: NSWindow?) {
		if let observer { NotificationCenter.default.removeObserver(observer) }
		observer = nil

		guard let window else {
			update(false)
			return
		}
		observer = NotificationCenter.default.addObserver(
			forName: NSWindow.didChangeOcclusionStateNotification,
			object: window,
			queue: .main
		) { [weak self, weak window] _ in
			self?.update(window?.occlusionState.contains(.visible) ?? false)
		}
		update(window.occlusionState.contains(.visible))
	}

	private func update(_ visible: Bool) {
		guard visible != isVisible else { return }
		isVisible = visible
		onChange?(visible)
	}

	deinit {
		if let observer { NotificationCenter.default.removeObserver(observer) }
	}
}
