//
//  GameActivitySource.swift
//  Swiftcord
//

import AppKit
import DiscordKitCore
import os

/// A game detected as running
struct RunningGame: Equatable {
	let name: String
	/// Discord application ID, when the game is in Discord's detectable list (shows its icon)
	let applicationID: Snowflake?
	let startedAt: Date
	let processID: pid_t
}

/// Detects running games without polling, by reacting to app launches and quits.
///
/// An app counts as a game if its Info.plist category is a games category, or if it
/// matches Discord's list of detectable games (which the official client also uses).
final class GameActivitySource {
	private static let log = Logger(category: "GameActivitySource")

	/// Called on the main thread when the detected game changes (`nil` when none)
	var onChange: ((RunningGame?) -> Void)?

	private var observers: [NSObjectProtocol] = []
	private var games: [pid_t: RunningGame] = [:]
	private var current: RunningGame?
	private let detectable = DetectableApplications()

	func start() {
		guard observers.isEmpty else { return }
		let center = NSWorkspace.shared.notificationCenter
		observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
			guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
			self?.consider(app, launchedNow: true)
		})
		observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
			guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
			self?.games[app.processIdentifier] = nil
			self?.publish()
		})

		detectable.load { [weak self] in
			// Re-scan once Discord's list is available, to pick up games without a games category
			self?.scanRunningApps()
		}
		scanRunningApps()
	}

	func stop() {
		observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
		observers = []
		games = [:]
		current = nil
	}

	private func scanRunningApps() {
		for app in NSWorkspace.shared.runningApplications {
			consider(app, launchedNow: false)
		}
	}

	private func consider(_ app: NSRunningApplication, launchedNow: Bool) {
		guard app.activationPolicy == .regular,
			  app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
			  games[app.processIdentifier] == nil,
			  let name = app.localizedName else { return }

		let category = Self.category(of: app)
		let isGamesCategory = category?.hasSuffix("games") ?? false
		// Only match by name when the app doesn't declare a non-game category, to avoid
		// mistaking e.g. a productivity app for a game that shares its name
		let match = detectable.match(app: app, allowNameMatch: category == nil || isGamesCategory)
		guard match != nil || isGamesCategory else { return }

		games[app.processIdentifier] = RunningGame(
			name: match?.name ?? name,
			applicationID: match?.id,
			startedAt: app.launchDate ?? Date(),
			processID: app.processIdentifier
		)
		publish()
	}

	/// The app's Info.plist category, e.g. `public.app-category.games` or
	/// `public.app-category.action-games` for games
	private static func category(of app: NSRunningApplication) -> String? {
		guard let url = app.bundleURL else { return nil }
		return Bundle(url: url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
	}

	private func publish() {
		// Show the most recently started game
		let newest = games.values.max { $0.startedAt < $1.startedAt }
		guard newest != current else { return }
		current = newest
		onChange?(newest)
	}
}

/// Discord's list of detectable applications, cached on disk and refreshed weekly
private final class DetectableApplications {
	struct Application: Decodable {
		struct Executable: Decodable {
			let os: String
			let name: String
		}
		let id: Snowflake
		let name: String
		let executables: [Executable]?
		let aliases: [String]?
	}

	typealias Entry = (id: Snowflake, name: String)

	private static let log = Logger(category: "DetectableApplications")
	private static let url = URL(string: "https://discord.com/api/v9/applications/detectable")!
	private static let maxAge: TimeInterval = 7 * 24 * 60 * 60

	/// Lowercased macOS executable path suffixes → application
	private var byExecutable: [String: Entry] = [:]
	/// Lowercased names and aliases → application
	private var byName: [String: Entry] = [:]

	private static var cacheURL: URL? {
		FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
			.appendingPathComponent("detectable-applications.json")
	}

	/// Loads the cached list (downloading it if missing or older than a week) off the
	/// main thread, then calls `completion` on the main thread once it's indexed
	func load(completion: @escaping () -> Void) {
		DispatchQueue.global(qos: .utility).async {
			var data: Data?
			var isFresh = false
			if let cacheURL = Self.cacheURL, let cached = try? Data(contentsOf: cacheURL) {
				data = cached
				let modified = (try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
				isFresh = modified.map { Date().timeIntervalSince($0) < Self.maxAge } ?? false
			}
			if let data { self.index(data, completion: completion) }
			guard !isFresh else { return }

			URLSession.shared.dataTask(with: URLRequest(url: Self.url, timeoutInterval: 30)) { downloaded, response, _ in
				guard let downloaded, (response as? HTTPURLResponse)?.statusCode == 200 else {
					Self.log.warning("Couldn't download detectable applications")
					return
				}
				if let cacheURL = Self.cacheURL { try? downloaded.write(to: cacheURL, options: .atomic) }
				self.index(downloaded, completion: completion)
			}.resume()
		}
	}

	/// Decodes on the calling (background) thread and swaps the index in on the main thread
	private func index(_ data: Data, completion: @escaping () -> Void) {
		guard let apps = try? JSONDecoder().decode([Application].self, from: data) else { return }
		var executables: [String: Entry] = [:]
		var names: [String: Entry] = [:]
		for app in apps {
			let entry = (id: app.id, name: app.name)
			names[app.name.lowercased()] = entry
			app.aliases?.forEach { names[$0.lowercased()] = entry }
			for exe in app.executables ?? [] where exe.os == "darwin" {
				executables[exe.name.lowercased()] = entry
			}
		}
		DispatchQueue.main.async {
			self.byExecutable = executables
			self.byName = names
			completion()
		}
	}

	/// Call on the main thread
	func match(app: NSRunningApplication, allowNameMatch: Bool) -> Entry? {
		// Discord lists macOS executables as path suffixes, e.g. "hades.app" or "game.app/contents/macos/game"
		if let path = (app.executableURL ?? app.bundleURL)?.path.lowercased() {
			for (exe, entry) in byExecutable where path.hasSuffix(exe) { return entry }
		}
		if let bundleName = app.bundleURL?.lastPathComponent.lowercased(), let entry = byExecutable[bundleName] {
			return entry
		}
		if allowNameMatch, let name = app.localizedName?.lowercased() { return byName[name] }
		return nil
	}
}
