//
//  AppSettingsAdvancedView.swift
//  Swiftcord
//
//  Created by Vincent Kwok on 7/7/22.
//

import SwiftUI

struct AppSettingsAdvancedView: View {
    var body: some View {
		Section("Privacy") {
			Text("This build of Swiftcord doesn't collect analytics or send crash reports.")
				.frame(maxWidth: .infinity, alignment: .leading)
		}
    }
}
