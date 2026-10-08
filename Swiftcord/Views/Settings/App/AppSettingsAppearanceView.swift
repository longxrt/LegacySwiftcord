//
//  AppSettingsAppearanceView.swift
//  Swiftcord
//
//  Created by Vincent Kwok on 5/6/22.
//

import SwiftUI

struct AppSettingsAppearanceView: View {
	@AppStorage(AppTheme.storageKey) private var selectedTheme = AppTheme.system.rawValue

	var body: some View {
		Section {
			Picker("settings.app.appearance.theme", selection: $selectedTheme) {
				ForEach(AppTheme.allCases) { theme in
					Text(theme.label).tag(theme.rawValue)
				}
			}.pickerStyle(.menu)

			if selectedTheme == AppTheme.oled.rawValue {
				Text("OLED Black uses pure black backgrounds throughout the app. On OLED and mini-LED displays, black pixels are switched off, which can save power and looks great in dark rooms.")
					.font(.callout)
					.foregroundColor(.secondary)
			}
			Text("A known bug causes rendering glitches when the theme is switched from a theme that isn't the current system theme, to the system theme. It seems to be due to SwiftUI itself, but I'm looking for workarounds.")
				.font(.callout)
				.foregroundColor(.secondary)
		}
	}
}
