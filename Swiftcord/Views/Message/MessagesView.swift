//
//  MessagesView.swift
//  Swiftcord
//
//  Created by Vincent Kwok on 23/2/22.
//

import SwiftUI
import DiscordKit
import DiscordKitCore
import CachedAsyncImage
import Introspect
import Combine

extension View {
    public func flip() -> some View {
        self
            .rotationEffect(.radians(.pi))
            .scaleEffect(x: -1, y: 1, anchor: .center)
    }
}

extension View {
    @ViewBuilder public func removeSeparator() -> some View {
        if #available(macOS 13.0, *) {
            self.listRowSeparator(.hidden).listSectionSeparator(.hidden)
        } else {
            self
        }
    }
}

struct NewAttachmentError: Identifiable {
    var id: String { title + message }
    let title: String
    let message: String
}

struct HeaderChannelIcon: View {
    let iconName: String
    let background: Color
    let iconSize: CGFloat
    let size: CGFloat

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: iconSize))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(background)
            .clipShape(Circle())
    }
}

struct MessagesViewHeader: View {
    let chl: Channel?

    @EnvironmentObject var gateway: DiscordGateway

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if chl?.type == .dm {
                if let rID = chl?.recipient_ids?.first,
                   let url = gateway.cache.users[rID]?.avatarURL(size: 160) { // swiftlint:disable:this indentation_width
                    BetterImageView(url: url)
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                }
            } else if chl?.type == .groupDM {
                HeaderChannelIcon(
                    iconName: "person.2.fill",
                    background: .red,
                    iconSize: 30,
                    size: 80
                )
            } else {
                HeaderChannelIcon(
                    iconName: "number",
                    background: .init(nsColor: .unemphasizedSelectedContentBackgroundColor),
                    iconSize: 44,
                    size: 68
                )
            }

            Text(
                chl?.type == .dm || chl?.type == .groupDM
                ? "\(chl?.label(gateway.cache.users) ?? "")"
                : "server.channel.title \(chl?.label() ?? "")"
            )
            .font(.largeTitle)
            .fontWeight(.heavy)

            Text(
                chl?.type == .dm
                ? "dm.header \(chl?.label(gateway.cache.users) ?? "")"
                : chl?.type == .groupDM
                ? "dm.group.header \(chl?.label(gateway.cache.users) ?? "")"
                : "server.channel.header \(chl?.name ?? "") \(chl?.topic ?? "")"
            ).opacity(0.7)
        }
        .padding(.top, 16)
    }
}

struct DayDividerView: View {
    let date: Date

    var body: some View {
        HStack(spacing: 4) {
            HorizontalDividerView().frame(maxWidth: .infinity)
            Text(date, style: .date)
                .font(.system(size: 12))
                .fontWeight(.medium)
                .opacity(0.7)
            HorizontalDividerView().frame(maxWidth: .infinity)
        }
        .padding(.top, 16)
    }
}

struct UnreadDivider: View {
    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(.red).frame(height: 1).frame(maxWidth: .infinity)
            Text("New")
                .textCase(.uppercase).font(.headline)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(.red))
                .foregroundColor(.white)
        }.padding(.vertical, 4)
    }
}

/// The message text field. It's the only view observing the composer, so keystrokes
/// re-render just this field rather than the message history.
private struct ComposerField: View {
    @ObservedObject var composer: ComposerModel
    let channelID: Snowflake
    let placeholder: LocalizedStringKey
    @Binding var attachments: [URL]
    @Binding var replying: MessagesViewModel.ReplyRef?
    let onSend: (String, [URL]) -> Void
    let preAttach: (URL) -> Bool

    var body: some View {
        MessageInputView(
            placeholder: placeholder,
            message: $composer.text, attachments: $attachments, replying: $replying,
            onSend: onSend,
            preAttach: preAttach
        )
        .onChange(of: composer.text) { oldText, newText in
            // Send a typing indicator at most once every 8s while the draft is growing
            guard newText.count > oldText.count,
                  Date().timeIntervalSince(composer.lastSentTyping) > 8 else { return }
            composer.lastSentTyping = Date()
            Task { _ = try? await restAPI.typingStart(id: channelID) }
        }
    }
}

struct MessagesView: View {
    @EnvironmentObject var gateway: DiscordGateway
    @EnvironmentObject var state: UIState
    @EnvironmentObject var ctx: ServerContext

    @StateObject var viewModel = MessagesViewModel()
    // Held without observing it, so typing doesn't re-render this view (see ComposerField)
    @State var composer = ComposerModel()

    @State private var messageInputHeight: CGFloat = 0

    // Gateway
    @State private var evtID: EventDispatch.HandlerIdentifier?
    // @State private var scrollSinkCancellable: AnyCancellable?

    // static let scrollPublisher = PassthroughSubject<Snowflake, Never>()

    private var loadingSkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<10) { _ in
                LoFiMessageView().padding(.vertical, 8)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @_transparent @_optimize(speed) @ViewBuilder
    func cell(for msg: Message, shrunk: Bool) -> some View {
        MessageView(
            message: msg,
            shrunk: shrunk,
            // Discord sends the replied-to message along with replies; only fall back to
            // scanning loaded history (O(n) per cell) when it's missing
            quotedMsg: msg.message_reference.flatMap { ref in
                msg.referenced_message ?? viewModel.messages.first { $0.id == ref.message_id }
            },
            onQuoteClick: { id in
                // withAnimation { proxy.scrollTo(id, anchor: .center) }
                viewModel.highlightMsg = id
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if viewModel.highlightMsg == id { viewModel.highlightMsg = nil }
                }
            },
            replying: $viewModel.replying,
            highlightMsgId: $viewModel.highlightMsg
        )
        .equatable()
        .listRowBackground(msg.mentions(gateway.cache.user?.id) ? Color.orange.opacity(0.1) : .clear)
    }

    private var history: some View {
        ForEach(Array(viewModel.messages.enumerated()), id: \.1.id) { (idx, msg) in
            let isLastItem = idx == viewModel.messages.count-1
            let shrunk = !isLastItem && msg.messageIsShrunk(prev: viewModel.messages[idx+1])

            cell(for: msg, shrunk: shrunk)

            if !isLastItem, let channelID = ctx.channel?.id {
                let newMsg = gateway.readState[channelID]?.ackMessageID == viewModel.messages[idx+1].id

                if newMsg { UnreadDivider() }
                if !shrunk && !newMsg {
                    Spacer(minLength: 16 - MessageView.lineSpacing / 2)
                }
            }

            if isLastItem && viewModel.reachedTop || !isLastItem && !msg.timestamp.isSameDay(as: viewModel.messages[idx+1].timestamp) {
                DayDividerView(date: msg.timestamp)
            }
        }
        .zeroRowInsets()
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var historyList: some View {
        ScrollViewReader { proxy in
            List {
                Spacer(minLength: max(messageInputHeight-44-7, 0) + (viewModel.showingInfoBar ? 24 : 0)).zeroRowInsets()

                history.flip().removeSeparator()

                if viewModel.reachedTop {
                    MessagesViewHeader(chl: ctx.channel).zeroRowInsets().removeSeparator().flip()
                } else {
                    loadingSkeleton
                        .zeroRowInsets()
                        .flip()
                        .removeSeparator()
                        .onAppear { if viewModel.fetchMessagesTask == nil { fetchMoreMessages() } }
                        .onDisappear {
                            if let loadTask = viewModel.fetchMessagesTask {
                                loadTask.cancel()
                                viewModel.fetchMessagesTask = nil
                            }
                        }
                }

                Spacer(minLength: 52).zeroRowInsets() // Ensure content is fully visible and not hidden behind toolbar when scrolled to the top
            }
            .introspectTableView { tableView in
                tableView.backgroundColor = .clear
                tableView.enclosingScrollView!.drawsBackground = false
                tableView.enclosingScrollView!.rotate(byDegrees: 180)
                tableView.enclosingScrollView!.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 52, right: 0)
            }
            .environment(\.defaultMinListRowHeight, 1) // By SwiftUI's logic, 0 is negative so we use 1 instead
            .scaleEffect(x: -1, y: 1, anchor: .center)
            .background(.clear)
            .frame(maxHeight: .infinity)
            .padding(.bottom, 24 + 7) // Ensure List doesn't go below text input field (and its border radius)
        }
    }

    @ViewBuilder
    private func inputContainer(channel: Channel) -> some View {
        ZStack(alignment: .topLeading) {
            MessageInfoBarView(isShown: $viewModel.showingInfoBar, state: $viewModel.infoBarData)

            let hasSendPermission: Bool = {
                guard let guildID = ctx.guild?.id else { return false }
                guard !guildID.isDM else { return true }
                guard let member = ctx.member else { return false }
                return channel.computedPermissions(
                    guildID: guildID, member: member, basePerms: ctx.basePermissions,
                    userID: gateway.cache.user?.id
                )
                .contains(.sendMessages)
            }()

            ComposerField(
                composer: composer,
                channelID: channel.id,
                placeholder: hasSendPermission ?
                (channel.type == .dm
                 ? "dm.composeMsg.hint \(channel.label(gateway.cache.users) ?? "")"
                 : (channel.type == .groupDM
                    ? "dm.group.composeMsg.hint \(channel.label(gateway.cache.users) ?? "")"
                    : "server.composeMsg.hint \(channel.label(gateway.cache.users) ?? "")"
                   )
                )
                : "You do not have permission to send messages in this channel.",
                attachments: $viewModel.attachments, replying: $viewModel.replying,
                onSend: sendMessage,
                preAttach: preAttachChecks
            )
            .disabled(!hasSendPermission)
            .onAppear { composer.text = "" }
            .overlay {
                let typingMembers = ctx.typingStarted[channel.id]?
                    .map { $0.member?.nick ?? $0.member?.user?.displayName ?? "" } ?? []

                if !typingMembers.isEmpty {
                    HStack {
                        // The dimensions are quite arbitrary
                        // FIXME: The animation broke, will have to fix it
                        LottieView(name: "typing-animation", play: .constant(true), width: 160, height: 160)
                            .lottieLoopMode(.loop)
                            .frame(width: 32, height: 24)
                        Group {
                            Text(
                                typingMembers.count <= 2
                                ? typingMembers.joined(separator: " and ")
                                : "Several people"
                            ).fontWeight(.semibold)
                            + Text(" \(typingMembers.count == 1 ? "is" : "are") typing...")
                        }.padding(.leading, -4)
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
            .heightReader($messageInputHeight)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            historyList
            if let channel = ctx.channel {
                inputContainer(channel: channel)
            }
        }
        // Blur the area behind the toolbar so the content doesn't show thru
        .safeAreaInset(edge: .top) {
            VStack {
                Divider().frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .themedBackground(.ultraThinMaterial)
        }
        .frame(minWidth: 525, minHeight: 500)
        .themedBackground(Color.clear)
        // .blur(radius: viewModel.dropOver ? 8 : 0)
        .overlay {
            if viewModel.dropOver {
                ZStack {
                    VStack(spacing: 24) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 64))
                            .foregroundColor(.accentColor)
                        Text("Drop file to add attachment").font(.largeTitle)
                    }
                    Rectangle()
                        .stroke(style: StrokeStyle(lineWidth: 10, lineCap: .round, dash: [25, 20]))
                        .opacity(0.75)
                }
                .padding(24)
                .background(.thickMaterial)
            }
        }
        .animation(.easeOut(duration: 0.2), value: viewModel.dropOver)
        .onDrop(of: [.fileURL], isTargeted: $viewModel.dropOver) { providers -> Bool in
            print("Drop: \(providers)")
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { itemURL, err in
                    if let itemURL = itemURL, preAttachChecks(for: itemURL) {
                        viewModel.attachments.append(itemURL)
                    }
                }
            }
            return true
        }
        .onChange(of: ctx.channel) { channel in
            guard let channel = channel else { return }
            viewModel.messages = []
            // Prevent deadlocked and wrong message situations
            fetchMoreMessages()
            viewModel.loadError = false
            viewModel.reachedTop = false
            composer.lastSentTyping = .distantPast

        }
        .onChange(of: state.loadingState) { loadingState in
            if loadingState == .gatewayConn {
                guard viewModel.fetchMessagesTask == nil else { return }
                viewModel.messages = []
                fetchMoreMessages()
            }
        }
        .onDisappear {
            // Remove gateway event handler to prevent memory leaks
            guard let handlerID = evtID else { return }
            _ = gateway.onEvent.removeHandler(handler: handlerID)
        }
        .onAppear {
            fetchMoreMessages()

            evtID = gateway.onEvent.addHandler { evt in
                switch evt {
                case .messageCreate(let msg):
                    if msg.channel_id == ctx.channel?.id {
                        viewModel.addMessage(msg)
                    }
                    guard msg.webhook_id == nil else { break }
                    // Remove typing status after user sent a message
                    ctx.typingStarted[msg.channel_id]?.removeAll { $0.user_id == msg.author.id }
                case .messageUpdate(let newMsg):
                    guard newMsg.channel_id == ctx.channel?.id else { break }
                    viewModel.updateMessage(newMsg)
                case .messageDelete(let delMsg):
                    guard delMsg.channel_id == ctx.channel?.id else { break }
                    viewModel.deleteMessage(delMsg)
                case .messageDeleteBulk(let delMsgs):
                    guard delMsgs.channel_id == ctx.channel?.id else { break }
                    viewModel.deleteMessageBulk(delMsgs)
                default: break
                }
            }
        }
        .alert(item: $viewModel.newAttachmentErr) { err in
            Alert(
                title: Text(err.title),
                message: Text(err.message),
                dismissButton: .cancel(Text("Got It!"))
            )
        }
    }
}
