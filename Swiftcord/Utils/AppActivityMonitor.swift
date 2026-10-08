//
//  AppActivityMonitor.swift
//  Swiftcord
//

import AppKit
import DiscordKit
import SDWebImage
import os

/// Adjusts how eagerly the app does background work based on whether it's frontmost
/// or visible at all, and releases memory caches when macOS reports memory pressure.
final class AppActivityMonitor {
	static let shared = AppActivityMonitor()

	private static let log = Logger(category: "AppActivityMonitor")

	private weak var gateway: DiscordGateway?
	private var observers: [NSObjectProtocol] = []
	private var memoryPressureSource: DispatchSourceMemoryPressure?

	private init() {}

	/// Starts monitoring; safe to call more than once
	func start(gateway: DiscordGateway) {
		self.gateway = gateway
		guard observers.isEmpty else { update(); return }

		let center = NotificationCenter.default
		for name in [
			NSApplication.didBecomeActiveNotification,
			NSApplication.didResignActiveNotification,
			NSApplication.didChangeOcclusionStateNotification,
			NSApplication.didHideNotification,
			NSApplication.didUnhideNotification
		] {
			observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
				self?.update()
			})
		}

		let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
		source.setEventHandler { [weak self] in self?.releaseMemory() }
		source.resume()
		memoryPressureSource = source

		update()
	}

	private func update() {
		let app = NSApplication.shared
		let visible = !app.isHidden && app.occlusionState.contains(.visible)

		// Presence changes from other users are cosmetic; batch them more aggressively
		// when nobody is looking. Lowering the interval flushes pending updates.
		let interval: TimeInterval
		if app.isActive {
			interval = 1
		} else if visible {
			interval = 5
		} else {
			interval = 60
		}
		if gateway?.presenceUpdateInterval != interval {
			gateway?.presenceUpdateInterval = interval
		}
	}

	private func releaseMemory() {
		Self.log.info("Memory pressure: releasing in-memory image caches")
		SDImageCache.shared.clearMemory()
		// Drop only the in-memory part of URLCache; the disk cache stays intact
		let capacity = URLCache.shared.memoryCapacity
		URLCache.shared.memoryCapacity = 0
		URLCache.shared.memoryCapacity = capacity
	}
}
