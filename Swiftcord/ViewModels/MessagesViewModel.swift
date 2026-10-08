//
//  MessagesViewModel.swift
//  Swiftcord
//
//  Created by Vincent Kwok on 9/8/22.
//

import SwiftUI
import DiscordKitCore

// TODO: Make this ViewModel follow best practices and actually function as a ViewModel
@MainActor class MessagesViewModel: ObservableObject {
	// For use in the UI - different from MessageReference in DiscordKit
	struct ReplyRef {
		let messageID: Snowflake
		let guildID: Snowflake
		let ping: Bool
		let authorID: Snowflake
		let authorUsername: String
	}

	@Published var reachedTop = false
	@Published var messages: [Message] = []
	@Published var attachments: [URL] = []
	@Published var showingInfoBar = false
	@Published var loadError = false
	@Published var infoBarData: InfoBarData?
	@Published var fetchMessagesTask: Task<(), Error>?
	@Published var newAttachmentErr: NewAttachmentError?
	@Published var replying: ReplyRef?
	@Published var dropOver = false
	@Published var highlightMsg: Snowflake?

	func addMessage(_ message: Message) {
		withAnimation {
			messages.insert(message, at: 0)
		}
	}

	func updateMessage(_ updated: PartialMessage) {
		if let updatedIdx = messages.firstIndex(identifiedBy: updated.id) {
			messages[updatedIdx] = messages[updatedIdx].mergingWithPartialMsg(updated)
		}
	}

	func deleteMessage(_ deleted: MessageDelete) {
		withAnimation { messages.removeAll(identifiedBy: deleted.id) }
	}
	func deleteMessageBulk(_ bulkDelete: MessageDeleteBulk) {
		withAnimation {
			for msgID in bulkDelete.id {
				messages.removeAll(identifiedBy: msgID)
			}
		}
	}
}

/// Draft state for the message composer.
///
/// Kept separate from ``MessagesViewModel`` and only observed by the composer field,
/// so typing re-renders the text box instead of the whole message history.
@MainActor final class ComposerModel: ObservableObject {
	@Published var text = ""
	/// When a typing indicator was last sent; not published since nothing displays it
	var lastSentTyping = Date.distantPast
}
