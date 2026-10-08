//
//  Theme.swift
//  Swiftcord
//

import SwiftUI
import AppKit

/// The user-selectable app theme, persisted under the `theme` user default.
enum AppTheme: String, CaseIterable, Identifiable {
	case system, light, dark, oled

	static let storageKey = "theme"

	var id: String { rawValue }

	var label: String {
		switch self {
		case .system: return "System"
		case .light: return "Light"
		case .dark: return "Dark"
		case .oled: return "OLED Black"
		}
	}

	var colorScheme: ColorScheme? {
		switch self {
		case .system: return nil
		case .light: return .light
		case .dark, .oled: return .dark
		}
	}
}

/// Colors used by the OLED theme. Pure black for large areas so pixels on OLED
/// and mini-LED displays can turn off, with slightly lifted surfaces for
/// raised elements (input box, footer, cards) so they stay distinguishable.
enum OLEDPalette {
	static let background = Color.black
	static let surface = Color(white: 0.05)
	static let elevated = Color(white: 0.09)
	static let border = Color(white: 0.16)
}

private struct OLEDThemeKey: EnvironmentKey {
	static let defaultValue = false
}

extension EnvironmentValues {
	/// Whether the OLED Black theme is active
	var isOLED: Bool {
		get { self[OLEDThemeKey.self] }
		set { self[OLEDThemeKey.self] = newValue }
	}
}

extension View {
	/// Applies the selected theme to a window's content: color scheme, the
	/// `isOLED` environment value, and the window's own background color.
	func appTheme(_ theme: AppTheme) -> some View {
		self
			.preferredColorScheme(theme.colorScheme)
			.environment(\.isOLED, theme == .oled)
			.background(WindowBackgroundSetter(isOLED: theme == .oled))
	}

	/// Uses `oled` as the background in the OLED theme, otherwise `standard`.
	func themedBackground<Standard: ShapeStyle>(
		_ standard: Standard,
		oled: Color = OLEDPalette.background
	) -> some View {
		modifier(ThemedBackground(standard: standard, oled: oled))
	}
}

private struct ThemedBackground<Standard: ShapeStyle>: ViewModifier {
	let standard: Standard
	let oled: Color
	@Environment(\.isOLED) private var isOLED

	func body(content: Content) -> some View {
		// A single background with a type-erased style keeps view identity stable when switching themes
		content.background(isOLED ? AnyShapeStyle(oled) : AnyShapeStyle(standard))
	}
}

/// Sets the hosting window's background so no gray shows through translucent
/// areas (titlebar, sidebar, gaps between views) in the OLED theme.
private struct WindowBackgroundSetter: NSViewRepresentable {
	let isOLED: Bool

	func makeNSView(context: Context) -> NSView { WindowObservingView() }

	func updateNSView(_ nsView: NSView, context: Context) {
		guard let view = nsView as? WindowObservingView else { return }
		view.isOLED = isOLED
		view.apply()
	}

	final class WindowObservingView: NSView {
		var isOLED = false

		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			apply()
		}

		func apply() {
			guard let window else { return }
			window.backgroundColor = isOLED ? .black : .windowBackgroundColor
		}
	}
}
