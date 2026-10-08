//
//  AppDelegate.swift
//  Swiftcord
//
//  Created by Vincent on 4/14/22.
//

import Foundation
import AppKit
import SDWebImage

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        populateUserDefaults()
        setupURLCache()
        clearOldCache()

        // Disable tabbing (fixes #114)
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    /*func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
     /// Close the app when there are no more open windows
     /// This is mostly to fix bugs occuring when windows are
     /// reopened after all windows are closed
     return true
     }*/
}

private extension AppDelegate {
    func populateUserDefaults() {
        UserDefaults.standard.register(defaults: [
            "local.seenOnboarding": false
        ])
    }
}

private extension AppDelegate {
    /// Overwrite shared URLCache with a higher capacity one
    func setupURLCache() {
        /*let cachePath = (try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true))?.appendingPathComponent("sharedCache", isDirectory: false)
        if let cachePath {
            do {
                try FileManager.default.createDirectory(at: cachePath, withIntermediateDirectories: true)
            } catch {
                print("Create new cache dir fail! \(error)")
                return
            }
        }
        print("Cache path: \(cachePath)")*/
        // Images are cached by SDWebImage now; URLCache only holds API responses
        URLCache.shared = URLCache(
            memoryCapacity: 8 * 1024 * 1024,  // 8MB
            diskCapacity: 64 * 1024 * 1024, // 64MB
            diskPath: nil
        )

        // Bound SDWebImage's caches (by default the memory cache is unbounded)
        let imageCache = SDImageCache.shared.config
        imageCache.maxMemoryCost = 96 * 1024 * 1024 // 96MB of decoded images
        imageCache.maxDiskSize = 384 * 1024 * 1024 // 384MB
        imageCache.maxDiskAge = 7 * 24 * 60 * 60 // 1 week
    }

    // Remove cached files older than the specified number of hours
    func clearOldCache() {
        let hoursThreshold = 24

        do {
            if let directories = try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path) {
                for directory in directories {
                    let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(directory)
                    let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directoryURL.path)
                    if let creationDate = directoryAttributes[FileAttributeKey.creationDate] as? Date {
                        if let diff = Calendar.current.dateComponents([.hour], from: creationDate, to: Date()).hour, diff > hoursThreshold {
                            try FileManager.default.removeItem(at: directoryURL)
                        }
                    }
                }
            }
        } catch {
            print(error)
        }
    }
}
