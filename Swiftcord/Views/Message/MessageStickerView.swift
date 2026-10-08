//
//  MessageStickerView.swift
//  Swiftcord
//
//  Created by Vincent Kwok on 23/2/22.
//

import SwiftUI
import Lottie
import DiscordKitCore
import DiscordKit
import CachedAsyncImage

struct StickerPackView: View {
	let pack: StickerPack
	@Binding var packPresenting: Bool
	@State private var stickerHovered: Int?
	@State private var listHovered: Bool = false
	private var bannerURL: URL? { pack.bannerAsset?.url(with: .webp, size: 1024) }

	@ViewBuilder private var banner: some View {
		if let bannerURL {
			CachedAsyncImage(url: bannerURL) { image in
				image.resizable().scaledToFill()
			} placeholder: {
				ProgressView().progressViewStyle(.circular)
			}
			.frame(height: 100)
		}
	}

	private var rowCount: Int { (pack.stickers.count + 2) / 3 }

	private func sticker(at index: Int) -> some View {
		let sticker = pack.stickers[index]
		return StickerItemView(
			sticker: StickerItem(id: sticker.id, name: sticker.name, format_type: sticker.format_type),
			size: 95, play: .onHover
		)
			.onHover { stickerHovered = $0 ? index : nil }
			.scaleEffect(stickerHovered == index ? 1.1 : 1.0)
			.opacity(stickerHovered == index ? 1 : 0.5)
	}

	private var stickerGrid: some View {
		List {
			ForEach(0..<rowCount, id: \.self) { row in
				HStack {
					ForEach(row * 3..<min(row * 3 + 3, pack.stickers.count), id: \.self) { index in
						sticker(at: index)
					}
				}.frame(maxWidth: .infinity)
			}
		}
	}

	var body: some View {
		VStack {
			banner
			VStack {
				HStack(spacing: 15) {
					// Back button
					Button {
						packPresenting = false
					} label: {Image(systemName: "arrow.left")}
						.controlSize(.large)
					Text(pack.name).font(.title).fontWeight(.bold)
					Spacer()
					Text("􀐅 x\(pack.stickers.count)")
						.font(.system(size: 16))
						.opacity(0.7)
				}
				Divider()
				Text(pack.description)
					.fixedSize(horizontal: false, vertical: true)
					.frame(maxWidth: .infinity, alignment: .leading)
				stickerGrid
				.frame(height: 320)
				.onHover {listHovered = $0}
				if listHovered {
					Text(stickerHovered == nil ? "" : pack.stickers[stickerHovered!].name)
						.frame(height: 30)
						.font(.title3)
						.transition(.opacity)
				} else {
					HStack {
						Image("NitroSubscriber")
						Text("You need a Nitro subscription to send stickers from this pack.")
							.fixedSize(horizontal: false, vertical: true)
							.frame(height: 30)
					}
					.transition(.opacity)
				}

			}.padding(14)
			.animation(Animation.easeOut(duration: 0.1), value: stickerHovered)
			.animation(Animation.linear(duration: 0.1), value: listHovered)
		}
		.frame(width: 360)
	}
}

struct CustomButtonStyle: ButtonStyle {
	func makeBody(configuration: Self.Configuration) -> some View {
		configuration.label
			.background(Color.blue)
			.cornerRadius(10.0)
			.padding()
			.contentShape(Rectangle())
	}
}

struct MessageStickerView: View {
	let sticker: StickerItem
	@State private var infoShow = false
	@State private var error = false
	@State private var fullSticker: Sticker?
	@State public var packPresenting = false
	@State private var fullStickerPack: StickerPack?

	private func loadStickerPack() async -> StickerPack? {
		guard let stickerPacks: [StickerPack] = try? await restAPI.listNitroStickerPacks() else {return nil}
		for pack in stickerPacks where pack.id == fullSticker!.pack_id {
			return pack
		}
		return nil
	}

	var body: some View {
		Button {
			if fullSticker == nil {
				Task {
					fullSticker = try await restAPI.getSticker(sticker.id)
				}
			}
			infoShow.toggle()
			packPresenting = false

		} label: {
			StickerItemView(sticker: sticker, size: 160, play: .useDefault)
				.frame(width: 160, height: 160)
		}
		.buttonStyle(.borderless)
		.popover(isPresented: $infoShow, arrowEdge: .trailing) {
			if packPresenting {
				if let fullStickerPack = fullStickerPack {
					StickerPackView(pack: fullStickerPack, packPresenting: $packPresenting)
				}
			} else {
				VStack(alignment: .leading, spacing: 14) {
					if let fullSticker = fullSticker {
						StickerItemView(sticker: sticker, size: 240, play: .always)
						Divider()
						Text(fullSticker.name).font(.title2).fontWeight(.bold)
						if let description = fullSticker.description {
							Text(description).padding(.top, -8)
						}
						if sticker.format_type == .aPNG {
							Text("Sorry, aPNG stickers can't be played (yet)").font(.footnote)
						}
						if fullSticker.pack_id != nil {
							Button {
								Task {
									fullStickerPack = await loadStickerPack()
										packPresenting = true
								}
							} label: {
								Label("View Sticker Pack", systemImage: "square.on.square")
									.frame(maxWidth: .infinity)
							}
							.buttonStyle(FlatButtonStyle())
							.controlSize(.small)
						}
					} else {
						Text("Loading sticker...").font(.headline)
						ProgressView()
							.progressViewStyle(.linear)
							.frame(width: 240)
							.tint(.blue)
					}
				}
				.padding(14)
				.frame(width: 268)
			}
		}
	}
}

struct StickerView_Previews: PreviewProvider {
	static var previews: some View {
		// MessageStickerView(sticker: StickerItem(id: ))
		EmptyView()
	}
}
