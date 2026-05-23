//
//  SSVersionChecker.swift
//  Jiggler
//
//  Originally created in Objective-C by Ben Haller in 2003.
//  Ported to Swift as a mixed-mode pilot; behaviour and public API are unchanged
//  so the Objective-C call sites in AppDelegate.m work without modification.
//

import Foundation
import Cocoa

@objc(SSVersionChecker)
final class SSVersionChecker: NSObject {

	// MARK: - Public API (Objective-C compatible)

	@objc class func sharedVersionChecker() -> SSVersionChecker { _shared }

	@objc func askUserAboutAutomaticVersionCheck() {
		let appName = bundleName

		let alert = NSAlert()
		alert.alertStyle = .critical
		alert.messageText = Self.localized("Version Check")
		let template = Self.localized("Version Check offer panel text")
		alert.informativeText = String(format: template, appName, appName)
		alert.addButton(withTitle: Self.localized("Yes button", table: "Base"))
		alert.addButton(withTitle: Self.localized("No button", table: "Base"))

		let response = alert.runModal()
		UserDefaults.standard.set(response == .alertFirstButtonReturn ? "YES" : "NO",
								   forKey: Self.enabledDefaultsKey)
	}

	@objc func shouldDoAutomaticVersionCheckAskIfNecessary(_ ask: Bool) -> Bool {
		let defaults = UserDefaults.standard
		var doCheck = defaults.string(forKey: Self.enabledDefaultsKey)

		if doCheck == nil && ask {
			askUserAboutAutomaticVersionCheck()
			doCheck = defaults.string(forKey: Self.enabledDefaultsKey)
		}

		return doCheck == "YES"
	}

	@objc(checkForNewVersionUserRequested:)
	func checkForNewVersion(userRequested: Bool) {
		let appVersion = self.appVersion
		let bundleName = self.bundleName

		let config = URLSessionConfiguration.ephemeral
		config.requestCachePolicy = .reloadIgnoringLocalCacheData
		let session = URLSession(configuration: config)

		let task = session.dataTask(with: Self.releasesURL) { data, response, error in
			DispatchQueue.main.async {
				self.handleResponse(data: data,
									response: response,
									error: error,
									userRequested: userRequested,
									appVersion: appVersion,
									bundleName: bundleName)
			}
		}
		task.resume()
	}

	// MARK: - Response handling

	private func handleResponse(data: Data?,
								response: URLResponse?,
								error: Error?,
								userRequested: Bool,
								appVersion: String,
								bundleName: String) {
		let status = (response as? HTTPURLResponse)?.statusCode ?? -1

		// HTTP 404 → no releases published yet.  From the user's POV the
		// app is already on the latest version, so treat it as up to date.
		if status == 404 {
			if userRequested {
				Self.showUpToDate(name: bundleName, version: appVersion)
			}
			return
		}

		guard error == nil, let data = data, status == 200 else {
			if userRequested {
				Self.showError(messageKey: "Version Check network unavailable error (short version)")
			}
			return
		}

		guard let release = try? JSONDecoder().decode(Release.self, from: data),
			  let remoteTag = release.tagName else {
			if userRequested {
				Self.showError(messageKey: "Version Check info unavailable error")
			}
			return
		}

		let remoteVersion = (remoteTag.hasPrefix("v") || remoteTag.hasPrefix("V"))
			? String(remoteTag.dropFirst())
			: remoteTag

		if Self.compare(local: appVersion, remote: remoteTag) == .orderedAscending {
			let alert = NSAlert()
			alert.alertStyle = .warning
			alert.messageText = Self.localized("Version Check")
			let template = Self.localized("Version Check new version available")
			alert.informativeText = String(format: template, bundleName, remoteVersion, appVersion)
			alert.addButton(withTitle: Self.localized("Yes button", table: "Base"))
			alert.addButton(withTitle: Self.localized("No button", table: "Base"))

			if alert.runModal() == .alertFirstButtonReturn,
			   let urlString = release.htmlURL,
			   let url = URL(string: urlString) {
				NSWorkspace.shared.open(url)
			}
		} else if userRequested {
			Self.showUpToDate(name: bundleName, version: appVersion)
		}
	}

	// MARK: - Static helpers

	private static let _shared = SSVersionChecker()
	private static let enabledDefaultsKey = "DoVersionCheck"

	// GitHub Releases endpoint for this fork.  HTTP 404 when no releases exist
	// (treated as "up to date" — there is nothing newer).
	private static let releasesURL = URL(string: "https://api.github.com/repos/timokox/Jiggler/releases/latest")!

	private struct Release: Decodable {
		let tagName: String?
		let htmlURL: String?

		enum CodingKeys: String, CodingKey {
			case tagName = "tag_name"
			case htmlURL = "html_url"
		}
	}

	private static func localized(_ key: String, table: String = "VersionCheck") -> String {
		NSLocalizedString(key, tableName: table, bundle: .main, value: key, comment: "")
	}

	private static func showUpToDate(name: String, version: String) {
		let alert = NSAlert()
		alert.alertStyle = .informational
		alert.messageText = localized("Version Check")
		alert.informativeText = String(format: localized("Version Check up to date"), name, version)
		alert.addButton(withTitle: localized("OK button", table: "Base"))
		alert.runModal()
	}

	private static func showError(messageKey: String) {
		let alert = NSAlert()
		alert.alertStyle = .critical
		alert.messageText = localized("Version Check")
		alert.informativeText = localized(messageKey)
		alert.addButton(withTitle: localized("OK button", table: "Base"))
		alert.runModal()
	}

	/// Compare two dotted version strings ("1.10.2" vs "v1.10") numerically.
	/// Non-numeric trailing parts (e.g. "1.10b1") scan as 0 — close enough for
	/// "is there a newer version?"; release notes carry any finer nuance.
	private static func compare(local: String, remote: String) -> ComparisonResult {
		func components(_ version: String) -> [Int] {
			var v = version
			if v.hasPrefix("v") || v.hasPrefix("V") { v.removeFirst() }
			return v.split(separator: ".").map { part in
				Int(part.prefix(while: { $0.isNumber })) ?? 0
			}
		}

		let l = components(local)
		let r = components(remote)
		let n = max(l.count, r.count)

		for i in 0..<n {
			let lv = i < l.count ? l[i] : 0
			let rv = i < r.count ? r[i] : 0
			if rv > lv { return .orderedAscending }
			if rv < lv { return .orderedDescending }
		}
		return .orderedSame
	}

	// MARK: - Bundle info

	private var appVersion: String {
		Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
	}

	private var bundleName: String {
		Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? "Jiggler"
	}
}
