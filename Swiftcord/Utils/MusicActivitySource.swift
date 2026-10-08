//
//  MusicActivitySource.swift
//  Swiftcord
//

import AppKit
import os

/// A track currently playing in a supported music app
struct NowPlayingTrack: Equatable {
	enum Source: String, CaseIterable {
		case appleMusic = "Apple Music"
		case spotify = "Spotify"
		case cider = "Cider"

		/// User default key toggling this source
		var settingKey: String {
			switch self {
			case .appleMusic: return "activity.music.appleMusic"
			case .spotify: return "activity.music.spotify"
			case .cider: return "activity.music.cider"
			}
		}
	}

	let source: Source
	let title: String
	let artist: String
	let album: String
	/// When the track started, if known (lets Discord show elapsed/remaining time)
	let startedAt: Date?
	let duration: TimeInterval?
}

/// Watches Apple Music, Spotify and Cider for the currently playing track.
///
/// Apple Music and Spotify broadcast system-wide notifications on every playback
/// change, so they need no polling or permissions. Cider is polled through its local
/// RPC API, but only while Cider is actually running.
final class MusicActivitySource {
	private static let log = Logger(category: "MusicActivitySource")

	/// Called on the main thread when the playing track changes (`nil` when nothing plays)
	var onChange: ((NowPlayingTrack?) -> Void)?

	private var tracks: [NowPlayingTrack.Source: NowPlayingTrack] = [:]
	private var lastAppleMusicTrackID: String?
	private var observers: [NSObjectProtocol] = []
	private var workspaceObservers: [NSObjectProtocol] = []
	private var ciderTimer: Timer?
	private var lastPublished: NowPlayingTrack?

	/// Last Cider API problem, shown in Settings (e.g. a token is required)
	private(set) var ciderStatus: String?

	static let ciderTokenKey = "activity.cider.token"
	private static let ciderBaseURL = URL(string: "http://127.0.0.1:10767/api/v1/playback")!

	func start() {
		guard observers.isEmpty else { return }
		let distributed = DistributedNotificationCenter.default()
		observers.append(distributed.addObserver(
			forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main
		) { [weak self] in self?.handleAppleMusic($0.userInfo) })
		observers.append(distributed.addObserver(
			forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main
		) { [weak self] in self?.handleSpotify($0.userInfo) })

		// Only poll Cider while it's running
		let workspace = NSWorkspace.shared.notificationCenter
		for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
			workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
				self?.updateCiderPolling()
			})
		}
		updateCiderPolling()
	}

	func stop() {
		observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
		workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
		observers = []
		workspaceObservers = []
		ciderTimer?.invalidate()
		ciderTimer = nil
		tracks = [:]
		lastPublished = nil
	}

	/// Re-evaluates which sources are enabled and republishes
	func settingsChanged() {
		updateCiderPolling()
		publish()
	}

	// MARK: - Apple Music & Spotify

	private func handleAppleMusic(_ info: [AnyHashable: Any]?) {
		guard let info, info["Player State"] as? String == "Playing",
			  let title = info["Name"] as? String else {
			set(nil, for: .appleMusic)
			return
		}
		// Apple Music doesn't report the playback position. A new track starts at 0, so
		// only then do we know the start time; when resuming mid-track, omit timestamps.
		let trackID = (info["PersistentID"] as? NSNumber)?.stringValue ?? info["Persistent ID"].map { "\($0)" }
		let isNewTrack = trackID != lastAppleMusicTrackID
		lastAppleMusicTrackID = trackID
		let duration = (info["Total Time"] as? NSNumber).map { $0.doubleValue / 1000 }
		let previous = tracks[.appleMusic]
		set(NowPlayingTrack(
			source: .appleMusic,
			title: title,
			artist: info["Artist"] as? String ?? "",
			album: info["Album"] as? String ?? "",
			startedAt: isNewTrack ? Date() : previous?.startedAt,
			duration: duration
		), for: .appleMusic)
	}

	private func handleSpotify(_ info: [AnyHashable: Any]?) {
		guard let info, info["Player State"] as? String == "Playing",
			  let title = info["Name"] as? String else {
			set(nil, for: .spotify)
			return
		}
		let position = (info["Playback Position"] as? NSNumber)?.doubleValue ?? 0
		set(NowPlayingTrack(
			source: .spotify,
			title: title,
			artist: info["Artist"] as? String ?? "",
			album: info["Album"] as? String ?? "",
			startedAt: Date().addingTimeInterval(-position),
			duration: (info["Duration"] as? NSNumber).map { $0.doubleValue / 1000 }
		), for: .spotify)
	}

	// MARK: - Cider

	private var ciderIsRunning: Bool {
		NSWorkspace.shared.runningApplications.contains {
			$0.localizedName == "Cider" || ($0.bundleIdentifier?.lowercased().contains("cider") ?? false)
		}
	}

	private func updateCiderPolling() {
		let shouldPoll = UserDefaults.standard.bool(forKey: NowPlayingTrack.Source.cider.settingKey) && ciderIsRunning
		if shouldPoll, ciderTimer == nil {
			let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.pollCider() }
			timer.tolerance = 1 // Let macOS coalesce wakeups
			RunLoop.main.add(timer, forMode: .common)
			ciderTimer = timer
			pollCider()
		} else if !shouldPoll, let timer = ciderTimer {
			timer.invalidate()
			ciderTimer = nil
			set(nil, for: .cider)
		}
	}

	private struct CiderNowPlayingResponse: Decodable {
		struct Info: Decodable {
			let name: String?
			let artistName: String?
			let albumName: String?
			let durationInMillis: Double?
			let currentPlaybackTime: Double?
		}
		let info: Info?
	}

	private struct CiderIsPlayingResponse: Decodable {
		let is_playing: Bool?
	}

	private func ciderRequest(_ path: String) -> URLRequest {
		var request = URLRequest(url: Self.ciderBaseURL.appendingPathComponent(path), timeoutInterval: 3)
		if let token = Keychain.load(key: Self.ciderTokenKey), !token.isEmpty {
			// Cider versions differ on the header name
			request.setValue(token, forHTTPHeaderField: "apptoken")
			request.setValue(token, forHTTPHeaderField: "apitoken")
		}
		return request
	}

	private func pollCider() {
		Task { [weak self] in
			guard let self else { return }
			let track = await self.fetchCiderTrack()
			await MainActor.run { self.set(track, for: .cider) }
		}
	}

	private func fetchCiderTrack() async -> NowPlayingTrack? {
		do {
			let (playingData, playingResponse) = try await URLSession.shared.data(for: ciderRequest("is-playing"))
			if let http = playingResponse as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 403 {
				await setCiderStatus("Cider rejected the request. Add the API token from Cider's Settings → Connectivity, or turn off its token requirement.")
				return nil
			}
			guard (try? JSONDecoder().decode(CiderIsPlayingResponse.self, from: playingData))?.is_playing == true else {
				await setCiderStatus(nil)
				return nil
			}
			let (data, _) = try await URLSession.shared.data(for: ciderRequest("now-playing"))
			guard let info = try JSONDecoder().decode(CiderNowPlayingResponse.self, from: data).info,
				  let title = info.name else { return nil }
			await setCiderStatus(nil)
			return NowPlayingTrack(
				source: .cider,
				title: title,
				artist: info.artistName ?? "",
				album: info.albumName ?? "",
				startedAt: Date().addingTimeInterval(-(info.currentPlaybackTime ?? 0)),
				duration: info.durationInMillis.map { $0 / 1000 }
			)
		} catch {
			await setCiderStatus("Couldn't reach Cider. Make sure its RPC server is enabled in Settings → Connectivity.")
			return nil
		}
	}

	@MainActor private func setCiderStatus(_ status: String?) {
		ciderStatus = status
	}

	// MARK: - Publishing

	private func set(_ track: NowPlayingTrack?, for source: NowPlayingTrack.Source) {
		tracks[source] = track
		publish()
	}

	private func publish() {
		// Prefer the first enabled, playing source in a fixed order
		let enabled = NowPlayingTrack.Source.allCases.filter { UserDefaults.standard.bool(forKey: $0.settingKey) }
		let current = enabled.lazy.compactMap { self.tracks[$0] }.first

		if current == lastPublished { return }
		// Positions reported while polling drift slightly; ignore small start-time jitter
		if let current, let last = lastPublished, current.source == last.source,
		   current.title == last.title, current.artist == last.artist,
		   let start = current.startedAt, let lastStart = last.startedAt, abs(start.timeIntervalSince(lastStart)) < 3 {
			return
		}
		lastPublished = current
		onChange?(current)
	}
}
