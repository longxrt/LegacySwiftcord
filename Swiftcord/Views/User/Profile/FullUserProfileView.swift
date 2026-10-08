//
//  FullUserProfileView.swift
//  Swiftcord
//

import SwiftUI
import SDWebImageSwiftUI
import DiscordKit
import DiscordKitCore

/// Role chips (color dot + name), shared by the profile popover and the full profile
struct RoleTagCloud: View {
	let roles: [Role]

	var body: some View {
		TagCloudView(
			content: roles.map { role in
				HStack(spacing: 6) {
					Circle()
						.fill(Color(hex: role.color))
						.frame(width: 14, height: 14)
						.padding(.leading, 6)
					Text(role.name)
						.font(.system(size: 12))
						.padding(.trailing, 8)
				}
				.frame(height: 24)
				.background(.gray.opacity(0.2))
				.cornerRadius(7)
			}
		).padding(-2)
	}
}

/// Discord-style expanded profile: banner, badges, about me, roles, connections,
/// and mutual servers and friends
struct FullUserProfileView: View {
	let user: User
	let guildID: Snowflake?
	let guildRoles: [Role]
	/// Opens a server, e.g. from the mutual servers list
	let onOpenGuild: (Snowflake) -> Void

	@EnvironmentObject private var gateway: DiscordGateway
	@Environment(\.dismiss) private var dismiss
	@Environment(\.isOLED) private var isOLED
	@Environment(\.openURL) private var openURL

	@State private var profile: UserProfile?
	@State private var loadFailed = false
	@State private var tab: Tab = .about

	private enum Tab: Hashable { case about, servers, friends }

	private var isGuild: Bool { guildID != nil && guildID != "@me" }
	/// Mutual servers/friends don't apply to your own profile
	private var isSelf: Bool { user.id == gateway.cache.user?.id }
	private var shownUser: User { profile?.user ?? user }
	private var member: Member? { profile?.guild_member }

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			header
			if isSelf {
				Spacer().frame(height: 12)
			} else {
			Picker("", selection: $tab) {
				Text("About").tag(Tab.about)
				Text("Mutual Servers\(countLabel(profile?.mutual_guilds?.count))").tag(Tab.servers)
				Text("Mutual Friends\(countLabel(profile?.mutual_friends?.count ?? profile?.mutual_friends_count))").tag(Tab.friends)
			}
			.pickerStyle(.segmented)
			.labelsHidden()
			.padding(.horizontal, 20)
			.padding(.vertical, 12)
			}

			Divider()

			ScrollView {
				VStack(alignment: .leading, spacing: 16) {
					switch tab {
					case .about: aboutTab
					case .servers: serversTab
					case .friends: friendsTab
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(20)
			}
		}
		.frame(width: 600, height: 620)
		.themedBackground(Color(nsColor: .windowBackgroundColor))
		.overlay(alignment: .topTrailing) {
			Button { dismiss() } label: {
				Image(systemName: "xmark.circle.fill")
					.font(.system(size: 20))
					.symbolRenderingMode(.hierarchical)
			}
			.buttonStyle(.plain)
			.keyboardShortcut(.cancelAction)
			.padding(12)
			.help("Close")
		}
		.task { await loadProfile() }
	}

	// MARK: - Header

	private var bannerColor: Color {
		let accent = profile?.user_profile?.accent_color ?? shownUser.accent_color
		return accent.map { Color(hex: $0) } ?? Color.gray.opacity(0.35)
	}

	@ViewBuilder private var banner: some View {
		if let banner = shownUser.bannerAsset {
			let url = banner.url(with: .webp, size: 1024)
			if url.isAnimatable {
				AnimatedImageView(url: url.modifyingPathExtension("gif"))
			} else {
				WebImage(url: url) { $0.resizable().scaledToFill() } placeholder: { bannerColor }
			}
		} else {
			bannerColor
		}
	}

	private var header: some View {
		VStack(alignment: .leading, spacing: 0) {
			banner
				.frame(maxWidth: .infinity, minHeight: 180, maxHeight: 180)
				.clipped()

			HStack(alignment: .bottom, spacing: 16) {
				AvatarWithPresence(
					avatarURL: shownUser.avatarURL(size: 256),
					presence: gateway.presences[user.id]?.status ?? .offline,
					animate: true
				)
				.controlSize(.large)
				.padding(6)
				.background(Circle().fill(isOLED ? OLEDPalette.background : Color(nsColor: .windowBackgroundColor)))

				Spacer()

				if let badges = profile?.badges, !badges.isEmpty {
					HStack(spacing: 4) {
						ForEach(badges) { badge in
							WebImage(url: badge.iconAsset.url()) { $0.resizable().scaledToFit() } placeholder: { EmptyView() }
								.frame(width: 22, height: 22)
								.help(badge.description)
								.onTapGesture { if let link = badge.link.flatMap(URL.init) { openURL(link) } }
						}
					}
					.padding(6)
					.background(RoundedRectangle(cornerRadius: 8).fill(.gray.opacity(0.2)))
					.padding(.bottom, 12)
				}
			}
			.padding(.horizontal, 16)
			.padding(.top, -70)

			VStack(alignment: .leading, spacing: 2) {
				Text(member?.nick ?? shownUser.displayName)
					.font(.title)
					.fontWeight(.bold)
					.textSelection(.enabled)
				HStack(spacing: 6) {
					Text(verbatim: shownUser.discriminator == "0" ? shownUser.username : "\(shownUser.username)#\(shownUser.discriminator)")
						.textSelection(.enabled)
					if let pronouns = profile?.guild_member_profile?.pronouns ?? profile?.user_profile?.pronouns, !pronouns.isEmpty {
						Text("•")
						Text(pronouns)
					}
				}
				.foregroundColor(.secondary)
			}
			.padding(.horizontal, 20)
			.padding(.top, 4)
		}
	}

	// MARK: - Tabs

	@ViewBuilder private var aboutTab: some View {
		if profile == nil && !loadFailed {
			ProgressView().frame(maxWidth: .infinity)
		}
		if loadFailed {
			Label("Couldn't load the full profile.", systemImage: "exclamationmark.triangle")
				.foregroundColor(.secondary)
		}

		if let bio = profile?.user_profile?.bio ?? shownUser.bio, !bio.isEmpty {
			section("About Me") { Text(markdown: bio).textSelection(.enabled) }
		}

		section("Member Since") {
			HStack(spacing: 8) {
				Image("DiscordIcon").resizable().aspectRatio(contentMode: .fit).frame(width: 16)
				Text(user.id.createdAt?.formatted(.dateTime.day().month().year()) ?? "Unknown")
				if isGuild, let joined = member?.joined_at, joined != .distantPast {
					Circle().fill(Color(nsColor: .separatorColor)).frame(width: 4, height: 4)
					if let guildID, let iconURL = gateway.cache.guilds[guildID]?.properties.iconURL(size: 32), let url = URL(string: iconURL) {
						BetterImageView(url: url).frame(width: 16, height: 16).clipShape(Circle())
					}
					Text(joined.formatted(.dateTime.day().month().year()))
				}
			}
		}

		if isGuild, let member {
			let roles = guildRoles.filter { member.roles.contains($0.id) }
			section(roles.isEmpty ? "No Roles" : (roles.count == 1 ? "Role" : "Roles")) {
				if !roles.isEmpty { RoleTagCloud(roles: roles) }
			}
		}

		if let connections = profile?.connected_accounts, !connections.isEmpty {
			section("Connections") {
				LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
					ForEach(connections, id: \.id) { connection in
						ConnectionRow(connection: connection)
					}
				}
			}
		}

		section("Note") {
			ProfileNoteField(userID: user.id)
		}
	}

	@ViewBuilder private var serversTab: some View {
		if let guilds = profile?.mutual_guilds {
			if guilds.isEmpty {
				Text("No servers in common").foregroundColor(.secondary)
			}
			ForEach(guilds, id: \.id) { mutual in
				let guild = gateway.cache.guilds[mutual.id]
				Button {
					dismiss()
					onOpenGuild(mutual.id)
				} label: {
					HStack(spacing: 12) {
						if let iconURL = guild?.properties.iconURL(size: 80), let url = URL(string: iconURL) {
							BetterImageView(url: url).frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 10))
						} else {
							RoundedRectangle(cornerRadius: 10).fill(.gray.opacity(0.3)).frame(width: 40, height: 40)
								.overlay(Text(String(guild?.properties.name.prefix(1) ?? "?")).font(.headline))
						}
						VStack(alignment: .leading, spacing: 2) {
							Text(guild?.properties.name ?? "Unknown server").font(.headline)
							if let nick = mutual.nick { Text(nick).foregroundColor(.secondary) }
						}
						Spacer()
						Image(systemName: "chevron.right").foregroundColor(.secondary)
					}
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
			}
		} else {
			placeholder
		}
	}

	@ViewBuilder private var friendsTab: some View {
		if let friends = profile?.mutual_friends {
			if friends.isEmpty {
				Text("No friends in common").foregroundColor(.secondary)
			}
			ForEach(friends, id: \.id) { friend in
				HStack(spacing: 12) {
					BetterImageView(url: friend.avatarURL(size: 80)).frame(width: 40, height: 40).clipShape(Circle())
					VStack(alignment: .leading, spacing: 2) {
						Text(friend.displayName).font(.headline)
						Text(verbatim: friend.username).foregroundColor(.secondary)
					}
				}
			}
		} else if let count = profile?.mutual_friends_count {
			Text("\(count) friends in common")
		} else {
			placeholder
		}
	}

	@ViewBuilder private var placeholder: some View {
		if loadFailed {
			Text("Couldn't load the full profile.").foregroundColor(.secondary)
		} else {
			ProgressView().frame(maxWidth: .infinity)
		}
	}

	// MARK: - Helpers

	private func countLabel(_ count: Int?) -> String {
		count.map { " (\($0))" } ?? ""
	}

	private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(title).font(.headline).textCase(.uppercase).foregroundColor(.secondary)
			content()
		}
	}

	private func loadProfile() async {
		do {
			profile = try await restAPI.getProfile(
				user: user.id,
				mutualGuilds: !isSelf,
				mutualFriends: isSelf ? nil : true,
				guildID: isGuild ? guildID : nil
			)
		} catch {
			loadFailed = true
		}
	}
}

/// A connected account (GitHub, Steam, …) with a link to it where one can be built
private struct ConnectionRow: View {
	let connection: Connection
	@Environment(\.openURL) private var openURL

	private var serviceName: String {
		switch connection.type {
		case .battleNet: return "Battle.net"
		case .leagueOfLegends: return "League of Legends"
		case .playstation: return "PlayStation"
		case .youtube: return "YouTube"
		case .github: return "GitHub"
		case .twitter: return "X"
		default: return connection.type.rawValue.capitalized
		}
	}

	private var url: URL? {
		switch connection.type {
		case .github: return URL(string: "https://github.com/\(connection.name)")
		case .twitch: return URL(string: "https://twitch.tv/\(connection.name)")
		case .reddit: return URL(string: "https://reddit.com/user/\(connection.name)")
		case .twitter: return URL(string: "https://x.com/\(connection.name)")
		case .steam: return URL(string: "https://steamcommunity.com/profiles/\(connection.id)")
		case .youtube: return URL(string: "https://youtube.com/channel/\(connection.id)")
		case .spotify: return URL(string: "https://open.spotify.com/user/\(connection.id)")
		default: return nil
		}
	}

	var body: some View {
		HStack(spacing: 8) {
			VStack(alignment: .leading, spacing: 1) {
				HStack(spacing: 4) {
					Text(connection.name).fontWeight(.medium).lineLimit(1)
					if connection.verified {
						Image(systemName: "checkmark.seal.fill").foregroundColor(.accentColor).font(.caption)
					}
				}
				Text(serviceName).font(.caption).foregroundColor(.secondary)
			}
			Spacer(minLength: 0)
			if let url {
				Button { openURL(url) } label: { Image(systemName: "arrow.up.right.square") }
					.buttonStyle(.plain)
					.help("Open on \(serviceName)")
			}
		}
		.padding(10)
		.background(RoundedRectangle(cornerRadius: 8).fill(.gray.opacity(0.15)))
	}
}

/// A private, locally stored note about a user
struct ProfileNoteField: View {
	let userID: Snowflake
	@State private var note = ""

	var body: some View {
		// Notes are stored locally for now, but eventually will be synced with the Discord API
		TextField("Add a note to this user (only visible to you)", text: $note)
			.textFieldStyle(.roundedBorder)
			.onChange(of: note) { _ in
				if note.isEmpty {
					UserDefaults.standard.removeObject(forKey: "notes.\(userID)")
				} else {
					UserDefaults.standard.set(note, forKey: "notes.\(userID)")
				}
			}
			.onAppear {
				note = UserDefaults.standard.string(forKey: "notes.\(userID)") ?? ""
			}
	}
}
