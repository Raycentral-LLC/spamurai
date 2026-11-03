import SafariServices

/// Native side of the YouTube extension: answers "status" (is Pro on?) and counts skipped ads.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any]

        var reply: [String: Any] = ["pro": SharedStore.isPro]
        if message?["type"] as? String == "adSkipped", SharedStore.isPro {
            reply["skippedToday"] = YouTubeStats.recordSkip()
        }

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: reply]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
