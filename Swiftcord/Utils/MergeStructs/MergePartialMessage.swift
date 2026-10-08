//
//  MergePartialMessage.swift
//  Swiftcord
//
//  Created by Vincent Kwok on 5/3/22.
//
//  Merges a PartialMessage and Message
//  Fields from PartialMessage are favored

import Foundation
import DiscordKitCore

extension Message {
	// Fields are merged into typed locals first; a single initializer call with
	// 30+ `??` expressions is too slow for the Swift type checker.
	func mergingWithPartialMsg(_ partial: PartialMessage) -> Message {
		let author: User = partial.author ?? self.author
		let member: Member? = partial.member ?? self.member
		let content: String = partial.content ?? self.content
		let editedTimestamp: Date? = partial.edited_timestamp ?? self.edited_timestamp
		let tts: Bool = partial.tts ?? self.tts
		let mentionEveryone: Bool = partial.mention_everyone ?? self.mention_everyone
		let mentions: [User] = partial.mentions ?? self.mentions
		let mentionRoles: [Snowflake] = partial.mention_roles ?? self.mention_roles
		let mentionChannels: [ChannelMention]? = partial.mention_channels ?? self.mention_channels
		let attachments: [Attachment] = partial.attachments ?? self.attachments
		let embeds: [Embed] = partial.embeds ?? self.embeds
		let reactions: [Reaction]? = partial.reactions ?? self.reactions
		let pinned: Bool = partial.pinned ?? self.pinned
		let activity: MessageActivity? = partial.activity ?? self.activity
		let application: Application? = partial.application ?? self.application
		let applicationID: Snowflake? = partial.application_id ?? self.application_id
		let snapshots: [MessageSnapshot]? = partial.message_snapshots ?? self.message_snapshots
		let flags: Int? = partial.flags ?? self.flags
		let referenced: Message? = partial.referenced_message ?? self.referenced_message
		let interaction: MessageInteraction? = partial.interaction ?? self.interaction
		let thread: Channel? = partial.thread ?? self.thread
		let components: [MessageComponent]? = partial.components ?? self.components
		let stickerItems: [StickerItem]? = partial.sticker_items ?? self.sticker_items
		let stickers: [Sticker]? = partial.stickers ?? self.stickers
		let call: CallMessageComponent? = partial.call ?? self.call
		let poll: Poll? = partial.poll ?? self.poll

		return Message(
			id: id,
			channel_id: channel_id,
			guild_id: guild_id,
			author: author,
			member: member,
			content: content,
			timestamp: timestamp,
			edited_timestamp: editedTimestamp,
			nonce: nonce,
			tts: tts,
			mention_everyone: mentionEveryone,
			mentions: mentions,
			mention_roles: mentionRoles,
			mention_channels: mentionChannels,
			attachments: attachments,
			embeds: embeds,
			reactions: reactions,
			pinned: pinned,
			webhook_id: webhook_id,
			type: type,
			activity: activity,
			application: application,
			application_id: applicationID,
			message_reference: message_reference,
			message_snapshots: snapshots,
			flags: flags,
			referenced_message: referenced,
			interaction: interaction,
			thread: thread,
			components: components,
			sticker_items: stickerItems,
			stickers: stickers,
			call: call,
			poll: poll
		)
    }
}
