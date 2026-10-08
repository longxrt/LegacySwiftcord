//
//  UserAvatarView.swift
//  Swiftcord
//
//  Created by Vincent Kwok on 23/2/22.
//

import SwiftUI
import SDWebImageSwiftUI
import DiscordKitCore
import DiscordKit

struct ProfileKey: Hashable {
	let guildID: Snowflake?
	let userID: Snowflake
}

struct UserAvatarView: View {
    let user: User
    let guildID: Snowflake?
    let webhookID: Snowflake?
	var size: CGFloat = 40
	@State private var fullUser: User?
	@State private var member: Member?
    @State private var infoPresenting = false
	@State private var loadFullFailed = false
	@State private var loadingProfile = false
	@State private var fullProfilePresented = false

	@EnvironmentObject var ctx: ServerContext
	@EnvironmentObject var gateway: DiscordGateway
	@EnvironmentObject var state: UIState

	private static let profileCache = Cache<ProfileKey, (User, Member?)>()

    var body: some View {
		// _ = print("render!")
		let avatarURL = user.avatarURL(size: size == 40 ? 160 : Int(size)*2)
	    // This is actually crucial to resolve a SwiftUI bug preventing a required rerender when this property changes
		let _ = member // swiftlint:disable:this redundant_discardable_let

		Button {
			if user.id == gateway.cache.user?.id, fullUser == nil {
				fullUser = User(from: gateway.cache.user!)
			}

			if let (cUser, cMember) = Self.profileCache[ProfileKey(guildID: guildID, userID: user.id)] {
				member = cMember
				fullUser = cUser
			}

			infoPresenting.toggle()

			if let guildID = guildID, guildID != "@me" {
				gateway.requestPresence(id: guildID, memberID: user.id)
			}

			// Get user profile for a fuller User object and roles. In DMs there are no guild
			// roles, but the profile still has the banner and bio.
			let isGuild = guildID != nil && guildID != "@me"
			if fullUser == nil || (isGuild && member == nil), webhookID == nil, !loadingProfile {
				loadingProfile = true
				loadFullFailed = false
				Task {
					defer { loadingProfile = false }
					do {
						let profile = try await restAPI.getProfile(
							user: user.id,
							guildID: isGuild ? guildID : nil
						)
						member = profile.guild_member
						fullUser = profile.user
						Self.profileCache[ProfileKey(guildID: guildID, userID: user.id)] = (profile.user, profile.guild_member)
					} catch {
						loadFullFailed = true
					}
				}
			}
		} label: {
			BetterImageView(url: avatarURL)
				.frame(width: size, height: size)
				.clipShape(Circle())
		}
		.buttonStyle(.borderless)
		.sheet(isPresented: $fullProfilePresented) {
			FullUserProfileView(
				user: fullUser ?? user,
				guildID: guildID,
				guildRoles: ctx.roles
			) { id in state.selectedGuildID = id }
			.environmentObject(gateway)
		}
		.popover(isPresented: $infoPresenting, arrowEdge: .trailing) {
			MiniUserProfileView(
				user: fullUser ?? user,
				member: member,
				guildRoles: ctx.roles,
				isWebhook: webhookID != nil,
				loadError: loadFullFailed
			) {
				if loadingProfile {
					ProgressView("Loading full profile...")
						.progressViewStyle(.linear)
						.frame(maxWidth: .infinity)
						.tint(.blue)
				}

				Text(ctx.guild?.id.isDM == true ? "Discord Member Since" : "Member Since")
					.font(.headline)
					.textCase(.uppercase)
				HStack(spacing: 8) {
					Image("DiscordIcon").resizable().aspectRatio(contentMode: .fit).frame(width: 16)
					Text(user.id.createdAt?.formatted(.dateTime.day().month().year()) ?? "Unknown")

					if let guild = ctx.guild, !guild.id.isDM {
						Circle().fill(Color(nsColor: .separatorColor)).frame(width: 4, height: 4)

						if let iconURL = guild.properties.iconURL(size: 32), let url = URL(string: iconURL) {
							BetterImageView(url: url).frame(width: 16).clipShape(Circle())
						} else {
							Text("\(guild.properties.name)")
								.font(.caption)
								.fixedSize()
								.frame(width: 16, height: 16, alignment: .leading)
								.background(.gray.opacity(0.5))
								.clipShape(Circle())
						}
						Text(member?.joined_at.formatted(.dateTime.day().month().year()) ?? "Unknown")
					}
				}

				if guildID != "@me" {
					let guildRoles = ctx.roles
					let roles = guildRoles.filter {
						member?.roles.contains($0.id) ?? false
					}

					Text(
						member == nil && loadingProfile
						? "user.roles.loading"
						: (roles.isEmpty ? "user.roles.none" : (roles.count == 1 ? "user.roles.one" : "user.roles.many"))
					)
					.font(.headline)
					.textCase(.uppercase)
					.padding(.top, 6)
					if !roles.isEmpty {
						RoleTagCloud(roles: roles)
					}
				}

				Text("user.note")
					.font(.headline)
					.textCase(.uppercase)
					.padding(.top, 6)
				ProfileNoteField(userID: user.id)

				if webhookID == nil {
					Button {
						infoPresenting = false
						// Let the popover finish closing before presenting the sheet
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { fullProfilePresented = true }
					} label: {
						Label("View Full Profile", systemImage: "person.crop.rectangle")
							.frame(maxWidth: .infinity)
					}
					.controlSize(.large)
					.padding(.top, 6)
				}
			}
		}
	}

	/*static func == (lhs: UserAvatarView, rhs: UserAvatarView) -> Bool {
		lhs.user.id == rhs.user.id && lhs.profile?.user.id == rhs.profile?.user.id
	}*/
}
