// Relays content-script messages to the native handler (SafariWebExtensionHandler), which
// knows whether the user has Spamurai Pro and records skipped ads in the app's stats.
browser.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (!message || (message.type !== "status" && message.type !== "adSkipped")) return false;
  browser.runtime
    .sendNativeMessage("com.raycentral.spamurai", message)
    .then((reply) => sendResponse(reply || {}))
    .catch(() => sendResponse({ pro: false }));
  return true; // keep the channel open for the async reply
});
