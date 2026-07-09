import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum BespokeAppMetadata {
    static let marketingName = "BespokeDua"
    static let websiteURL = URL(string: "https://www.bespokedua.com")!
    static let aboutURL = URL(string: "https://www.bespokedua.com")!
    static let feedbackEmail = "bespokedua@gmail.com"
    static let appStoreURL = URL(string: "https://apps.apple.com/gb/app/bespoke-dua/id6761731591")!
    static let instagramURL = URL(string: "https://www.instagram.com/bespoke_dua/")!
    static let tiktokURL = URL(string: "https://www.tiktok.com/@bespokedua")!

    static var supportMailURL: URL? {
        mailtoURL(subject: "BespokeDua Support")
    }

    static var featureRequestMailURL: URL? {
        mailtoURL(subject: "BespokeDua Feature Request")
    }

    static func reportDuaFeedPostMailURL(postId: String, preview: String) -> URL? {
        mailtoURL(
            subject: "BespokeDua Feed Report",
            body: """
            I would like to report the following feed post:

            Post ID: \(postId)

            Preview:
            \(preview)
            """
        )
    }

    static func mailtoURL(subject: String, body: String = "") -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackEmail
        var queryItems = [URLQueryItem(name: "subject", value: subject)]
        if !body.isEmpty {
            queryItems.append(URLQueryItem(name: "body", value: body))
        }
        components.queryItems = queryItems
        return components.url
    }

    /// Opens a `mailto:` link in the user's mail app, or copies the contact address when no mail app is available (e.g. Simulator).
    @MainActor
    @discardableResult
    static func openEmail(url: URL?, openURL: ((URL) -> Void)? = nil) -> Bool {
        guard let url else { return false }
        #if canImport(UIKit)
        if url.scheme?.lowercased() == "mailto" {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:]) { success in
                    if !success {
                        UIPasteboard.general.string = feedbackEmail
                    }
                }
            } else {
                UIPasteboard.general.string = feedbackEmail
            }
            return true
        }
        #endif
        if let openURL {
            openURL(url)
            return true
        }
        #if canImport(UIKit)
        UIApplication.shared.open(url, options: [:]) { success in
            if !success, url.scheme?.lowercased() == "mailto" {
                UIPasteboard.general.string = feedbackEmail
            }
        }
        return true
        #else
        return false
        #endif
    }

    @MainActor
    @discardableResult
    static func openSupportEmail(openURL: ((URL) -> Void)? = nil) -> Bool {
        openEmail(url: supportMailURL, openURL: openURL)
    }

    @MainActor
    @discardableResult
    static func openFeatureRequestEmail(openURL: ((URL) -> Void)? = nil) -> Bool {
        openEmail(url: featureRequestMailURL, openURL: openURL)
    }

    static var shareText: String {
        "Discover personalised duas with \(marketingName). Download the app: \(appStoreURL.absoluteString)"
    }

    static var versionString: String {
        "Version \(shortVersionString)"
    }

    static var shortVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    #if canImport(UIKit)
    static var appIcon: UIImage? {
        guard
            let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let files = primary["CFBundleIconFiles"] as? [String],
            let iconName = files.last
        else { return nil }
        return UIImage(named: iconName)
    }
    #endif
}
