//
//  AppSettingsActivityView.swift
//  Swiftcord
//

import SwiftUI

struct AppSettingsActivityView: View {
	@ObservedObject private var manager = ActivityStatusManager.shared

	@AppStorage(ActivityStatusManager.Keys.enabled) private var enabled = false
	@AppStorage(ActivityStatusManager.Keys.games) private var games = true
	@AppStorage(ActivityStatusManager.Keys.music) private var music = true
	@AppStorage(NowPlayingTrack.Source.appleMusic.settingKey) private var appleMusic = true
	@AppStorage(NowPlayingTrack.Source.spotify.settingKey) private var spotify = true
	@AppStorage(NowPlayingTrack.Source.cider.settingKey) private var cider = true

	@State private var ciderToken = Keychain.load(key: MusicActivitySource.ciderTokenKey) ?? ""

	var body: some View {
		Section {
			Toggle("Share my activity status", isOn: $enabled)
			Text("Shows what you're playing or listening to on your profile, like the official Discord app. Nothing is shared unless this is on.")
				.font(.callout)
				.foregroundColor(.secondary)
		}

		Section("Games") {
			Toggle("Show games I'm playing", isOn: $games)
			Text("Detects games from their app category and from Discord's list of detectable games. Works when apps launch or quit, without polling.")
				.font(.callout)
				.foregroundColor(.secondary)
		}
		.disabled(!enabled)

		Section("Music") {
			Toggle("Show music I'm listening to", isOn: $music)
			Group {
				Toggle("Apple Music", isOn: $appleMusic)
				Toggle("Spotify", isOn: $spotify)
				Toggle("Cider", isOn: $cider)
				if cider {
					SecureField("Cider API token (optional)", text: $ciderToken)
						.onSubmit(saveCiderToken)
					Text("Cider must have its RPC server enabled under Settings → Connectivity. If it requires an API token, generate one there and paste it here. Cider is only checked while it's running.")
						.font(.callout)
						.foregroundColor(.secondary)
					if let status = manager.ciderStatus {
						Label(status, systemImage: "exclamationmark.triangle")
							.font(.callout)
							.foregroundColor(.orange)
					}
				}
			}
			.disabled(!music)
			.padding(.leading, 16)
		}
		.disabled(!enabled)

		Section("Currently sharing") {
			if !enabled {
				Text("Activity sharing is off").foregroundColor(.secondary)
			} else if manager.game == nil && manager.track == nil {
				Text("Nothing right now").foregroundColor(.secondary)
			}
			if enabled, games, let game = manager.game {
				Label("Playing \(game.name)", systemImage: "gamecontroller")
			}
			if enabled, music, let track = manager.track {
				Label(
					"Listening to \(track.title)\(track.artist.isEmpty ? "" : " by \(track.artist)") on \(track.source.rawValue)",
					systemImage: "music.note"
				)
			}
		}
		.onChange(of: enabled) { _ in manager.settingsChanged() }
		.onChange(of: games) { _ in manager.settingsChanged() }
		.onChange(of: music) { _ in manager.settingsChanged() }
		.onChange(of: appleMusic) { _ in manager.settingsChanged() }
		.onChange(of: spotify) { _ in manager.settingsChanged() }
		.onChange(of: cider) { _ in manager.settingsChanged() }
		.onDisappear(perform: saveCiderToken)
	}

	private func saveCiderToken() {
		let token = ciderToken.trimmingCharacters(in: .whitespacesAndNewlines)
		if token.isEmpty {
			Keychain.remove(key: MusicActivitySource.ciderTokenKey)
		} else {
			// Local-only token; don't sync it to iCloud Keychain
			Keychain.save(key: MusicActivitySource.ciderTokenKey, data: Data(token.utf8), canSync: false)
		}
		manager.settingsChanged()
	}
}
