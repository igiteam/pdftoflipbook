// ==UserScript==
// @name         Magazine Button Auto Click to Open PDF
// @namespace    http://tampermonkey.net/
// @version      2.0
// @description  Waits for token to be added to View Document button, then clicks it automatically with reload fallback
// @author       You
// @match        https://archive.gamehistory.org/item/*
// @icon         https://archive.gamehistory.org/favicon.ico
// @grant        GM_setValue
// @grant        GM_getValue
// @run-at       document-start
// ==/UserScript==

(function () {
  "use strict";

  let clicked = false;
  let debugLog = [];
  let reloadAttempted = false;

  // Get URL-specific storage keys
  function getStorageKeys() {
    const url = window.location.href;
    // Create a unique ID based on the URL path
    const urlId = url
      .replace(/https?:\/\/[^\/]+/, "")
      .replace(/[^a-zA-Z0-9]/g, "_");
    return {
      reloadAttempted: `reloadAttempted_${urlId}`,
      linkOpened: `linkOpened_${urlId}`,
      lastAttempt: `lastAttempt_${urlId}`,
      successCount: `successCount_${urlId}`,
    };
  }

  // Check if we're returning from a link click
  function isReturningFromLink() {
    const keys = getStorageKeys();
    const justOpenedLink = sessionStorage.getItem(
      `justOpenedMagazineLink_${window.location.pathname}`
    );
    if (justOpenedLink) {
      sessionStorage.removeItem(
        `justOpenedMagazineLink_${window.location.pathname}`
      );
      return true;
    }
    return false;
  }

  // Check if we've already succeeded for this magazine
  function hasSucceededBefore() {
    const keys = getStorageKeys();
    const succeeded = GM_getValue(keys.linkOpened, false);
    if (succeeded) {
      log(
        `This magazine was successfully opened before (success count: ${GM_getValue(
          keys.successCount,
          0
        )})`
      );
    }
    return succeeded;
  }

  function markSuccess() {
    const keys = getStorageKeys();
    GM_setValue(keys.linkOpened, true);
    const currentCount = GM_getValue(keys.successCount, 0);
    GM_setValue(keys.successCount, currentCount + 1);
    GM_setValue(keys.lastAttempt, Date.now());
    log(
      `✓ Marked as successful for this magazine (total successes: ${
        currentCount + 1
      })`
    );
  }

  function markReloadAttempted() {
    const keys = getStorageKeys();
    reloadAttempted = true;
    GM_setValue(keys.reloadAttempted, true);
    GM_setValue(keys.lastAttempt, Date.now());
    log(`Marked reload attempted for this magazine`);
  }

  function hasReloadAttempted() {
    const keys = getStorageKeys();
    return GM_getValue(keys.reloadAttempted, false);
  }

  function clearReloadAttempt() {
    const keys = getStorageKeys();
    GM_setValue(keys.reloadAttempted, false);
    log(`Cleared reload attempt flag for this magazine`);
  }

  function performReload() {
    const keys = getStorageKeys();
    const reloadCount = GM_getValue(`${keys.reloadAttempted}_count`, 0);

    if (reloadCount >= 2) {
      log(
        `⚠ Already reloaded ${reloadCount} times for this magazine, giving up`
      );
      return false;
    }

    log(`⟳ Automatic reload #${reloadCount + 1} for this magazine...`);
    GM_setValue(`${keys.reloadAttempted}_count`, reloadCount + 1);
    markReloadAttempted();

    // Store current timestamp to check after reload
    sessionStorage.setItem("reloadTimestamp", Date.now().toString());
    sessionStorage.setItem("reloadUrl", window.location.href);

    setTimeout(() => {
      location.reload();
    }, 500);

    return true;
  }

  function log(message) {
    const timestamp = new Date().toLocaleTimeString();
    const logMsg = `[${timestamp}] ${message}`;
    console.log(logMsg);
    debugLog.push(logMsg);

    // Store URL-specific logs
    const keys = getStorageKeys();
    const logs = GM_getValue(`${keys.reloadAttempted}_logs`, []);
    logs.push(logMsg);
    if (logs.length > 50) logs.shift();
    GM_setValue(`${keys.reloadAttempted}_logs`, logs);
  }

  function clickButton(button) {
    if (clicked) {
      log("Already clicked, skipping...");
      return;
    }

    log("✓ TOKEN DETECTED! Button is ready");
    log("✓ HREF: " + button.href);

    // Store that we're about to open a link for this specific magazine
    const path = window.location.pathname;
    sessionStorage.setItem(`justOpenedMagazineLink_${path}`, "true");
    sessionStorage.setItem(`openedLinkUrl_${path}`, button.href);
    sessionStorage.setItem(`openedAt_${path}`, Date.now().toString());

    log("✓ Clicking the View Document button...");

    // Try to open in new tab
    const newTab = window.open(button.href, "_blank");
    if (newTab) {
      log("✓ Opened in new tab");
      clicked = true;
      markSuccess();

      // Focus on new tab
      newTab.focus();
    } else {
      // Fallback to normal click
      log("⚠ Popup blocked, using normal click");
      button.click();
      clicked = true;
      markSuccess();
    }

    log("✓ Click executed!");
  }

  // Find button function with detailed logging
  function findButton() {
    const elements = document.querySelectorAll(
      'a, button, .mantine-Button-root, [role="button"]'
    );

    for (let el of elements) {
      const text = el.textContent ? el.textContent.trim() : "";
      if (text === "View Document") {
        return el;
      }
    }

    return null;
  }

  // Main function to watch for button and token
  function startWatching() {
    log("=== Magazine Button Auto Click Started ===");
    log(`URL: ${window.location.href}`);

    // Check if we've already succeeded for this magazine
    if (hasSucceededBefore()) {
      log("This magazine was already processed successfully. Skipping...");
      return;
    }

    // Check if we should attempt a reload
    if (!hasReloadAttempted() && !clicked) {
      log("First attempt for this magazine, checking for button...");
      let button = findButton();

      if (button && button.href && button.href.includes("token=")) {
        log("Button with token found immediately!");
        clickButton(button);
        return;
      } else if (button && !button.href.includes("token=")) {
        log("Button found but no token yet, will watch...");
      } else {
        log(
          "No button found or no token available. Will attempt reload if needed..."
        );
      }
    } else if (hasReloadAttempted() && !clicked) {
      log(
        "Already attempted reload for this magazine, now watching normally..."
      );
      clearReloadAttempt();
    }

    // Try to find button immediately
    let button = findButton();

    if (button) {
      log("Button exists on page load!");
      if (button.href && button.href.includes("token=")) {
        log("Token already present! Clicking immediately.");
        clickButton(button);
        return;
      } else {
        log("Button found but no token yet.");

        // If this is first attempt and no token, trigger reload
        if (!hasReloadAttempted() && !clicked) {
          log("No token found on first load, triggering automatic reload...");
          performReload();
          return;
        }

        log("Setting up watchers...");
        watchForToken(button);
      }
    } else {
      log("Button not found on initial check.");

      // If this is first attempt and no button, trigger reload
      if (!hasReloadAttempted() && !clicked) {
        log("Button not found on first load, triggering automatic reload...");
        performReload();
        return;
      }

      log("Setting up mutation observer...");
      setupMutationObserver();
    }
  }

  function setupMutationObserver() {
    const observer = new MutationObserver(function (mutations) {
      if (clicked) {
        observer.disconnect();
        return;
      }

      // Check for button appearance
      const button = findButton();
      if (button && !clicked) {
        observer.disconnect();

        // Watch this specific button for href changes
        watchForToken(button);

        // Also check immediately
        if (button.href && button.href.includes("token=")) {
          clickButton(button);
        }
      }
    });

    observer.observe(document.body, {
      childList: true,
      subtree: true,
    });

    // Timeout after 15 seconds
    setTimeout(() => {
      if (!clicked && !hasReloadAttempted()) {
        log("Timeout waiting for button, triggering reload...");
        observer.disconnect();
        performReload();
      }
    }, 15000);
  }

  function watchForToken(button) {
    log(`Watching for token on ${button.tagName} element...`);
    log(`Initial href: ${button.href || "undefined"}`);

    // Check if token appears via attribute change
    const observer = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        if (
          mutation.type === "attributes" &&
          mutation.attributeName === "href"
        ) {
          const newHref = button.href;
          log(`HREF changed to: ${newHref}`);

          if (newHref && newHref.includes("token=")) {
            log("✓ Token detected in href attribute!");
            observer.disconnect();
            clearInterval(interval);
            clickButton(button);
          }
        }
      });
    });

    observer.observe(button, {
      attributes: true,
      attributeFilter: ["href"],
    });

    // Also check periodically if the whole element gets replaced
    let checks = 0;
    const interval = setInterval(() => {
      checks++;
      if (clicked) {
        clearInterval(interval);
        observer.disconnect();
        return;
      }

      // Re-find the button in case it was replaced
      const currentButton = findButton();
      if (currentButton && currentButton !== button) {
        log(`Button element was replaced!`);
        clearInterval(interval);
        observer.disconnect();

        if (currentButton.href && currentButton.href.includes("token=")) {
          log("New button already has token!");
          clickButton(currentButton);
        } else {
          log("New button has no token yet, watching it instead");
          watchForToken(currentButton);
        }
      } else if (
        currentButton &&
        currentButton.href &&
        currentButton.href.includes("token=") &&
        !clicked
      ) {
        log("✓ Token detected during periodic check!");
        clearInterval(interval);
        observer.disconnect();
        clickButton(currentButton);
      }

      if (checks >= 20 && !clicked && !hasReloadAttempted()) {
        log(
          "TIMEOUT: Token never appeared after 20 seconds, triggering reload..."
        );
        clearInterval(interval);
        observer.disconnect();
        performReload();
      }
    }, 1000);

    log("Watchers active - waiting for token to be added to href...");
  }

  // Start the script
  if (document.readyState === "loading") {
    setTimeout(startWatching, 0);
  } else {
    startWatching();
  }
})();
