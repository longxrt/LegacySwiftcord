//
//  Channel+.swift
//  Swiftcord
//
//  Created by royal on 14/05/2022.
//

import DiscordKitCore

extension Channel {
	func label(_ users: [Snowflake: User] = [:]) -> String? {
		name ?? recipient_ids?
			.compactMap { users[$0]?.displayName }
			.joined(separator: ", ")
	}
}

extension Channel {
	/// Computes the current user's permissions in this channel, following Discord's order:
	/// @everyone overwrite, then all role overwrites combined (denies first, then allows,
	/// so an allow on any role wins), then the member-specific overwrite.
	func computedPermissions(
		guildID: Snowflake,
		member: Member, basePerms: Permissions,
		userID: Snowflake? = nil
	) -> Permissions {
		if basePerms.contains(.administrator) {
			return .all
		}
		var permission = basePerms
		guard let overwrites = permission_overwrites, !overwrites.isEmpty else { return permission }

		if let everyoneOverwrite = overwrites.first(where: { $0.id == guildID }) {
			permission.applyOverwrite(everyoneOverwrite)
		}

		var roleAllow = Permissions(), roleDeny = Permissions()
		for overwrite in overwrites where overwrite.type == .role
			&& overwrite.id != guildID && member.roles.contains(overwrite.id) {
			roleAllow.formUnion(overwrite.allow)
			roleDeny.formUnion(overwrite.deny)
		}
		permission.remove(roleDeny)
		permission.formUnion(roleAllow)

		if let userID = userID ?? member.user?.id ?? member.user_id,
		   let memberOverwrite = overwrites.first(where: { $0.type == .member && $0.id == userID }) {
			permission.applyOverwrite(memberOverwrite)
		}
		return permission
	}

	/// Channel types whose message history can be loaded and shown in the messages view
	var hasMessageHistory: Bool {
		switch type {
		case .text, .news, .dm, .groupDM, .voice, .stageVoice, .newsThread, .publicThread, .privateThread:
			return true
		default:
			return false
		}
	}
}
