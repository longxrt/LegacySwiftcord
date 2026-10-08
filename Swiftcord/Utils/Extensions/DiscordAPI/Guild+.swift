//
//  Guild+.swift
//  Swiftcord
//
//  Created by royal on 14/05/2022.
//

import DiscordKitCore

extension Guild {
	var isDMChannel: Bool { id == "@me" }
}

extension Guild {
	func iconURL(size: Int = 240) -> String? {
		iconAsset?.url(with: .webp, size: size).absoluteString
	}
}

extension PreloadedGuild {
	/// Channels that decoded successfully. Individual channels that fail to decode are skipped.
	var channelList: [Channel] {
		channels.compactMap { try? $0.result.get() }
	}
}
