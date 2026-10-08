//
//  MessagesView+.swift
//  Swiftcord
//
//  Created by Vincent Kwok on 31/5/22.
//

import Foundation
import DiscordKit
import DiscordKitCore
import os

private let messagesLog = Logger(category: "MessagesView")

internal extension MessagesView {
	func fetchMoreMessages() {
		guard let channel = ctx.channel else { return }
		if let oldTask = viewModel.fetchMessagesTask {
			oldTask.cancel()
			viewModel.fetchMessagesTask = nil
		}

		if viewModel.loadError { viewModel.showingInfoBar = false }
		viewModel.loadError = false

		viewModel.fetchMessagesTask = Task {
			let lastMsg = viewModel.messages.last?.id

			let newMessages: [DecodeThrowable<Message>]
			do {
				newMessages = try await restAPI.getChannelMsgs(id: channel.id, before: lastMsg)
			} catch {
				try Task.checkCancellation() // Check if the task is cancelled before continuing
				messagesLog.error("Failed to load messages for channel \(channel.id, privacy: .public) (type \(channel.type.rawValue, privacy: .public)): \(String(describing: error), privacy: .public)")

				viewModel.fetchMessagesTask = nil
				viewModel.loadError = true
				viewModel.showingInfoBar = true
				viewModel.infoBarData = InfoBarData(
					message: "**Messages failed to load**",
					buttonLabel: "Try again",
					color: .red,
					buttonIcon: "arrow.clockwise"
				) { fetchMoreMessages() }
				state.loadingState = .messageLoad
				return
			}
			state.loadingState = .messageLoad
			try Task.checkCancellation()
			// Never mix in messages from a channel the user has since left
			guard ctx.channel?.id == channel.id else { return }

			viewModel.reachedTop = newMessages.count < 50
			// Skip individual messages that failed to decode instead of dropping the whole page
			viewModel.messages.append(contentsOf: newMessages.compactMap { try? $0.result.get() })
			viewModel.fetchMessagesTask = nil
		}
	}

	func sendMessage(with message: String, attachments: [URL]) {
		// Capture the destination now; the user may switch channels before the request runs
		guard let channelID = ctx.channel?.id else { return }
		composer.lastSentTyping = .distantPast
		composer.text = ""
		viewModel.showingInfoBar = false

		// Create message reference if neccessary
		let replying = viewModel.replying
		viewModel.replying = nil
		let reference = replying.map {
			MessageReference(message_id: $0.messageID, guild_id: $0.guildID.isDM ? nil : $0.guildID)
		}
		let allowedMentions = replying.map {
			AllowedMentions(parse: [.user, .role, .everyone], replied_user: $0.ping)
		}

		// Workaround for some race condition, no idea why clearing the message immediately doesn't
		// successfully clear it
		DispatchQueue.main.async { composer.text = "" }

		Task {
			do {
				_ = try await restAPI.createChannelMsg(
					message: NewMessage(
						content: message,
						allowed_mentions: allowedMentions,
						message_reference: reference,
						attachments: attachments.isEmpty ? nil : attachments.enumerated()
							.map { (idx, attachment) in
								NewAttachment(
									id: String(idx),
									filename: (try? attachment.resourceValues(forKeys: [URLResourceKey.nameKey]).name) ?? UUID().uuidString
								)
							}
					),
					attachments: attachments,
					id: channelID
				)
			} catch {
				viewModel.showingInfoBar = true
				viewModel.infoBarData = InfoBarData(
					message: "Could not send message",
					buttonLabel: "Try again",
					color: .red,
					buttonIcon: "arrow.clockwise",
					clickHandler: { sendMessage(with: message, attachments: attachments) }
				)
			}
		}
	}

	func preAttachChecks(for attachment: URL) -> Bool {
		guard let size = try? attachment.resourceValues(forKeys: [URLResourceKey.fileSizeKey]).fileSize, size < 8*1024*1024 else {
			viewModel.newAttachmentErr = NewAttachmentError(
				title: "Your files are too powerful",
				message: "The max file size is 8MB."
			)
			return false
		}
		guard viewModel.attachments.count < 10 else {
			viewModel.newAttachmentErr = NewAttachmentError(
				title: "Too many uploads!",
				message: "You can only upload 10 files at a time!"
			)
			return false
		}
		return true
	}
}
