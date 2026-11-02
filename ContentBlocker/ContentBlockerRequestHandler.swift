import Foundation

/// Shared by every content-blocker target; `SPListName` in each target's Info.plist selects the list.
final class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let name = Bundle.main.object(forInfoDictionaryKey: "SPListName") as? String ?? "ads"
        let list = BlockerList(rawValue: name) ?? .ads
        let url = SharedStore.downloadedListURL(list)
            ?? Bundle.main.url(forResource: list.rawValue, withExtension: "json")

        let item = NSExtensionItem()
        if let url, let provider = NSItemProvider(contentsOf: url) {
            item.attachments = [provider]
        }
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}
