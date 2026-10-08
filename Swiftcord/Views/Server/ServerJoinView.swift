//
//  ServerJoinView.swift
//  Swiftcord
//
//  Created by Vincent Kwok on 9/7/22.
//

import SwiftUI

struct ServerJoinView: View {
    @Binding var presented: Bool

    @State private var invite = ""
    @State private var loading = false
    @State private var error: LocalizedStringKey?

    private func join() async {
        guard !invite.isEmpty else {
            withAnimation { error = "server.join.fieldHeader.invalid" }
            return
        }

        let id = invite.split(separator: "/").last!
        let resolvedInvite = try? await restAPI.resolveInvite(inviteID: String(id), inputValue: invite)

        guard let resolvedInvite = resolvedInvite else {
            withAnimation { error = "server.join.fieldHeader.notFound" }
            return
        }
        print(resolvedInvite)
        withAnimation { error = nil }
    }

    var body: some View {
        DialogView(
            title: "server.join.title",
            description: "server.join.caption"
        ) { // swiftlint:disable:this vertical_parameter_alignment_on_call
            Button { presented = false } label: {
                Text("action.close")
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                Task {
                    withAnimation { loading = true }
                    await join()
                    withAnimation { loading = false }
                }
            } label: {
                if loading {
                    ProgressView().progressViewStyle(.circular).controlSize(.mini)
                } else {
                    Text("server.join.action")
                }
            }
            .buttonStyle(FlatButtonStyle())
            .disabled(loading)
        } content: {
            Group {
                if let error = error {
                    Text(error).foregroundColor(.red)
                } else {
                    Text("server.join.fieldHeader")
                }
            }.textCase(.uppercase).font(.headline).opacity(0.75)

            TextField("https://discord.gg/hTKzmak", text: $invite) {
                Task {
                    withAnimation { loading = true }
                    await join()
                    withAnimation { loading = false }
                }
            }
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)
            .padding(.bottom, 8)

            Text("server.join.egHeader").textCase(.uppercase).font(.headline).opacity(0.75)
            Text(verbatim: """
                hTKzmak
                https://discord.gg/hTKzmak
                https://discord.gg/cool-people
                """
            )
        }
    }
}
