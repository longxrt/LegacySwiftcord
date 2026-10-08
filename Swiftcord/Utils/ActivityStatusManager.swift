//
//  ActivityStatusManager.swift
//  Swiftcord
//

import Foundation
import DiscordKit
import DiscordKitCore
import os

/// Shares the game you're playing and the music you're listening to as your Discord
/// activity status. Everything is opt-in and off by default.
final class ActivityStatusManager: ObservableObject {
	static let shared = ActivityStatusManager()

	enum Keys {
		static let enabled = "activity.enabled"
		static let games = "activity.games"
		static let music = "activity.music"
	}

	private static let log = Logger(category: "ActivityStatusManager")
	/// Wait for changes to settle (e.g. skipping through tracks) before sending
	private static let debounce: TimeInterval = 2
	/// Discord rate-limits presence updates, so never send more often than this
	private static let minimumInterval: TimeInterval = 12

	@Published private(set) var game: RunningGame?
	@Published private(set) var track: NowPlayingTrack?

	private weak var gateway: DiscordGateway?
	private let games = GameActivitySource()
	private let music = MusicActivitySource()
	private var readyHandler: EventDispatch<GatewayIncoming.Data>.HandlerIdentifier?
	private var pendingSend: DispatchWorkItem?
	private var lastSent = Date.distantPast
	private var lastSentActivities: [ActivityOutgoing]?

	private var defaults: UserDefaults { .standard }
	private var isEnabled: Bool { defaults.bool(forKey: Keys.enabled) }
	private var gamesEnabled: Bool { isEnabled && defaults.bool(forKey: Keys.games) }
	private var musicEnabled: Bool { isEnabled && defaults.bool(forKey: Keys.music) }

	/// Shown in Settings when Cider can't be reached or needs a token
	var ciderStatus: String? { music.ciderStatus }

	private init() {
		defaults.register(defaults: [
			Keys.enabled: false,
			Keys.games: true,
			Keys.music: true,
			NowPlayingTrack.Source.appleMusic.settingKey: true,
			NowPlayingTrack.Source.spotify.settingKey: true,
			NowPlayingTrack.Source.cider.settingKey: true
		])
		games.onChange = { [weak self] in self?.game = $0; self?.scheduleSend() }
		music.onChange = { [weak self] in self?.track = $0; self?.scheduleSend() }
	}

	func start(gateway: DiscordGateway) {
		self.gateway = gateway
		if readyHandler == nil {
			// A new gateway session starts without our activities; send them again
			readyHandler = gateway.onEvent.addHandler { [weak self] event in
				if case .userReady = event {
					self?.lastSentActivities = nil
					self?.scheduleSend()
				}
			}
		}
		settingsChanged()
	}

	/// Call after any activity setting changes
	func settingsChanged() {
		if gamesEnabled { games.start() } else { games.stop(); game = nil }
		if musicEnabled {
			music.start()
			music.settingsChanged()
		} else {
			music.stop()
			track = nil
		}
		scheduleSend()
	}

	/// The activities this manager currently contributes to the user's presence
	var activities: [ActivityOutgoing] {
		var result: [ActivityOutgoing] = []
		if gamesEnabled, let game {
			result.append(ActivityOutgoing(
				name: game.name,
				type: .game,
				timestamps: ActivityTimestamp(start: Int(game.startedAt.timeIntervalSince1970 * 1000)),
				application_id: game.applicationID
			))
		}
		if musicEnabled, let track {
			let start = track.startedAt
			let end = start.flatMap { start in track.duration.map { start.addingTimeInterval($0) } }
			result.append(ActivityOutgoing(
				name: track.source.rawValue,
				type: .listening,
				timestamps: start.map {
					ActivityTimestamp(
						start: Int($0.timeIntervalSince1970 * 1000),
						end: end.map { Int($0.timeIntervalSince1970 * 1000) }
					)
				},
				details: track.title,
				state: track.artist.isEmpty ? nil : "by \(track.artist)"
			))
		}
		return result
	}

	private func scheduleSend() {
		pendingSend?.cancel()
		let work = DispatchWorkItem { [weak self] in self?.send() }
		pendingSend = work
		let earliest = lastSent.addingTimeInterval(Self.minimumInterval)
		let delay = max(Self.debounce, earliest.timeIntervalSinceNow)
		DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
	}

	private func send() {
		pendingSend = nil
		guard let gateway, gateway.connected, let userID = gateway.cache.user?.id else { return }

		let managed = activities
		// Nothing to change (also avoids clearing activities we never set)
		if lastSentActivities == nil && managed.isEmpty { return }
		if let lastSentActivities, lastSentActivities.map(\.name) == managed.map(\.name),
		   lastSentActivities.map(\.details) == managed.map(\.details),
		   lastSentActivities.map(\.timestamps) == managed.map(\.timestamps) { return }

		let presence = gateway.presences[userID]
		// Keep the user's custom status; replace only games and music
		let custom = (presence?.activities ?? [])
			.filter { $0.type == .custom }
			.map(ActivityOutgoing.init(from:))
		gateway.send(
			.presenceUpdate,
			data: GatewayPresenceUpdate(since: 0, activities: custom + managed, status: presence?.status ?? .online, afk: false)
		)
		lastSent = Date()
		lastSentActivities = managed
		Self.log.debug("Sent activity update with \(managed.count, privacy: .public) activities")
	}
}
