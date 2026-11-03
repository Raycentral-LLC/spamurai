// Spamurai for YouTube in Safari.
// Video ads: the player gets an "ad-showing" class; we mute, jump to the end and press Skip,
// rather than blocking requests (which YouTube detects). Ad slots in feeds are hidden by
// youtube.css, scoped to html.spamurai-yt so nothing changes until Pro is confirmed.
(() => {
  let enabled = false;
  let inAd = false;
  let userMuted = false;
  let userRate = 1;
  let lastReport = 0;

  const SKIP_BUTTONS = [
    ".ytp-skip-ad-button",
    ".ytp-ad-skip-button",
    ".ytp-ad-skip-button-modern",
    ".ytp-ad-skip-button-slot button",
    ".ytm-skip-ad-button",
    "button[class*='skip-ad']",
  ].join(",");

  function setEnabled(on) {
    enabled = on;
    document.documentElement.classList.toggle("spamurai-yt", on);
  }

  browser.runtime
    .sendMessage({ type: "status" })
    .then((reply) => setEnabled(Boolean(reply && reply.pro)))
    .catch(() => setEnabled(false));

  function tick() {
    if (!enabled) return;
    const player = document.querySelector(".html5-video-player, #movie_player");
    const video = player ? player.querySelector("video") : document.querySelector("video");
    const adShowing = Boolean(
      player && (player.classList.contains("ad-showing") || player.classList.contains("ad-interrupting"))
    );

    if (adShowing && video) {
      if (!inAd) {
        inAd = true;
        userMuted = video.muted;
        userRate = video.playbackRate === 16 ? 1 : video.playbackRate;
        report();
      }
      video.muted = true;
      video.playbackRate = 16;
      if (Number.isFinite(video.duration) && video.duration > 0 && video.currentTime < video.duration - 0.1) {
        video.currentTime = video.duration;
      }
      const skip = document.querySelector(SKIP_BUTTONS);
      if (skip) skip.click();
    } else if (inAd && video) {
      inAd = false;
      video.muted = userMuted;
      video.playbackRate = userRate;
    }

    document.querySelectorAll(".ytp-ad-overlay-close-button, .ytp-ad-overlay-close-container").forEach((b) => b.click());
  }

  // One count per ad break, not per frame.
  function report() {
    const now = Date.now();
    if (now - lastReport < 4000) return;
    lastReport = now;
    browser.runtime.sendMessage({ type: "adSkipped" }).catch(() => {});
  }

  const start = () => {
    new MutationObserver(tick).observe(document.documentElement, {
      subtree: true,
      childList: true,
      attributes: true,
      attributeFilter: ["class"],
    });
    setInterval(tick, 250);
  };
  if (document.documentElement) start();
  else document.addEventListener("DOMContentLoaded", start, { once: true });
})();
