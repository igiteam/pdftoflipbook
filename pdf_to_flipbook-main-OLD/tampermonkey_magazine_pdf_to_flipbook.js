// ==UserScript==
// @name         Magazine Scraper - Turn.js Flip Book Creator
// @namespace    http://tampermonkey.net/
// @version      36.0
// @description  Capture magazine pages - Save images and HTML with auto-scrape toggle
// @match        https://archive.gamehistory.org/item/*/pdf*
// @grant        GM_download
// @grant        GM_notification
// @icon         https://archive.gamehistory.org/favicon.ico
// ==/UserScript==

(function () {
  ("use strict");

  let isScraping = false;
  let autoScrapeEnabled = true;
  let autoScrapeInterval = null;
  let currentPageBeingProcessed = 0;
  let pageData = new Map();
  let failedPagesList = [];
  let autoSaveCompleted = false;
  let customTitle = getTitleFromPage();
  let totalPages = 0;
  let manualRetryActive = false;
  let scrapeCompleted = false;

  function getTotalPagesFromViewer() {
    const selectors = [
      "#numPages",
      ".numPages",
      '[data-l10n-id="pdfjs-of-pages"]',
      ".toolbarLabel",
      "#pageCount",
      ".pageCount",
      // Add selector for the specific HTML structure you have
      ".mantine-focus-never.vghf-type-meta",
      ".mantine-Text-root",
    ];

    for (const selector of selectors) {
      const element = document.querySelector(selector);
      if (element) {
        const text = element.innerText || element.textContent;
        const match = text.match(/(\d+)/);
        if (match) {
          const pages = parseInt(match[1]);
          if (pages > 0) {
            return pages;
          }
        }
      }
    }

    return 0;
  }

  // Add this function after the variable declarations
  function checkForLoadErrorAndReload() {
    // Selector for the error message
    const errorSelectors = [
      ".mantine-focus-never.vghf-type-section-title",
      ".mantine-Text-root:contains('There was an issue loading this document')",
      "[class*='mantine']:contains('issue loading')",
    ];

    // Check for the error message by text content
    const allElements = document.querySelectorAll(
      ".mantine-focus-never.vghf-type-section-title, .mantine-Text-root"
    );
    for (const el of allElements) {
      if (
        el.textContent &&
        el.textContent.includes("There was an issue loading this document")
      ) {
        console.log("[Auto-Reload] Error detected - reloading page...");

        if (typeof GM_notification !== "undefined") {
          GM_notification({
            title: "Magazine Scraper",
            text: "⚠️ Document load error detected - reloading page...",
            timeout: 3000,
          });
        }

        // Reload the page
        setTimeout(() => {
          window.location.reload();
        }, 1000);
        return true;
      }
    }
    return false;
  }

  // Add this function to start the error monitoring
  function startErrorMonitoring() {
    // Check every 2 seconds for the error message
    setInterval(() => {
      checkForLoadErrorAndReload();
    }, 2000);
  }

  // START the error monitoring immediately
  startErrorMonitoring();

  function setupAutoScrapeWatcher() {
    if (autoScrapeInterval) clearInterval(autoScrapeInterval);

    autoScrapeInterval = setInterval(() => {
      if (autoScrapeEnabled && !isScraping && !scrapeCompleted) {
        const pages = document.querySelectorAll(".page");
        const canvas = document.querySelector("canvas");
        const detectedPages = getTotalPagesFromViewer();

        if ((pages.length > 0 || detectedPages > 0) && canvas) {
          console.log("[Auto-Scrape] PDF viewer detected, starting scrape...");
          updateStatus(
            "🤖 Auto-scrape triggered: Starting automatic capture..."
          );
          startScraping();
        } else {
          updateStatus(
            "🤖 Auto-scrape enabled: Waiting for PDF viewer to load..."
          );
        }
      }
    }, 2000);
  }

  function createUI() {
    const existing = document.getElementById("magazine-scraper");
    if (existing) existing.remove();

    totalPages = getTotalPagesFromViewer();

    if (totalPages === 0) {
      const pageElements = document.querySelectorAll(".page");
      if (pageElements.length > 0) {
        totalPages = pageElements.length;
      }
    }

    const container = document.createElement("div");
    container.id = "magazine-scraper";
    container.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            background: white;
            border: 2px solid #333;
            border-radius: 8px;
            padding: 15px;
            z-index: 9999;
            font-family: Arial, sans-serif;
            min-width: 320px;
            max-width: 360px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.3);
            max-height: 90vh;
            overflow-y: auto;
        `;

    container.innerHTML = `
            <h3 style="margin-top: 0; color: #333; margin-bottom: 10px;">📖 Magazine Flip Book Creator</h3>

            <div style="margin-bottom: 15px; padding: 10px; background: #e8f5e9; border-radius: 4px; border: 2px solid #4CAF50;">
                <div style="display: flex; align-items: center; justify-content: space-between;">
                    <label style="font-weight: bold; color: #2e7d32;">🤖 Auto-Scrape Mode:</label>
                    <label class="switch" style="position: relative; display: inline-block; width: 50px; height: 24px;">
                        <input type="checkbox" id="auto-scrape-toggle" style="opacity: 0; width: 0; height: 0;">
                        <span class="slider" style="position: absolute; cursor: pointer; top: 0; left: 0; right: 0; bottom: 0; background-color: #ccc; transition: .3s; border-radius: 24px;"></span>
                    </label>
                </div>
                <small style="display: block; color: #555; margin-top: 5px;">When ON, automatically starts scraping as soon as PDF loads</small>
                <div id="auto-status" style="font-size: 11px; color: #2e7d32; margin-top: 5px; font-weight: bold;"></div>
            </div>

            <div style="margin-bottom: 10px;">
                <label style="font-weight: bold;">📄 Title:</label>
                <input type="text" id="custom-title" value="${customTitle}" style="width: 100%; padding: 5px; margin-top: 5px; border: 1px solid #ccc; border-radius: 4px; box-sizing: border-box;">
                <small style="display: block; color: #666; margin-top: 3px;">Used for image and HTML filenames</small>
            </div>
            <div style="margin-bottom: 10px; padding: 5px; background: #e8f4f8; border-radius: 4px;">
                <span style="font-size: 12px;">📊 Detected pages: <strong id="detected-pages">${
                  totalPages || "?"
                }</strong></span>
            </div>
            <div style="margin-bottom: 10px;">
                <label>Start Page: <input type="number" id="start-page" value="1" min="1" style="width: 60px;"></label>
                <label>End Page: <input type="number" id="end-page" value="${
                  totalPages || 102
                }" min="1" style="width: 60px;"></label>
            </div>
            <div style="margin-bottom: 10px;">
                <label>Page Delay (ms): <input type="number" id="page-delay" value="5000" min="2000" style="width: 80px;"></label>
                <small style="display: block; color: #666;">Time to wait per page</small>
            </div>
            <div style="margin-bottom: 10px;">
                <label>Retry Failed Pages: <input type="number" id="retry-count" value="3" min="1" max="5" style="width: 60px;"></label>
                <small style="display: block; color: #666;">Number of retry attempts for failed pages</small>
            </div>

            <div style="margin-bottom: 15px; padding: 10px; background: #f0f0f0; border-radius: 4px; border: 1px solid #ccc;">
                <label style="font-weight: bold; display: block; margin-bottom: 8px;">🎯 Download Specific Page:</label>
                <div style="display: flex; gap: 8px; align-items: center;">
                    <input type="number" id="specific-page" value="1" min="1" max="${
                      totalPages || 999
                    }" style="width: 80px; padding: 6px; border: 1px solid #ccc; border-radius: 4px;">
                    <button id="download-page-btn" style="background: #2196F3; color: white; border: none; padding: 6px 12px; cursor: pointer; border-radius: 4px;">📸 Capture & Save</button>
                </div>
                <small style="display: block; color: #666; margin-top: 5px;">Capture a single page and save as PNG</small>
            </div>

            <div style="margin-bottom: 10px;">
                <label>
                    <input type="checkbox" id="save-images" checked style="margin-right: 5px;">
                    Save individual PNG images
                </label>
            </div>
            <div style="margin-bottom: 10px;">
                <label>
                    <input type="checkbox" id="auto-save" checked style="margin-right: 5px;">
                    Auto-save HTML when complete
                </label>
            </div>
            <button id="start-scrape" style="background: #4CAF50; color: white; border: none; padding: 10px; cursor: pointer; width: 100%; margin-bottom: 5px; border-radius: 4px;">▶ Start Scraping</button>
            <button id="stop-scrape" style="background: #f44336; color: white; border: none; padding: 10px; cursor: pointer; width: 100%; margin-bottom: 5px; display: none; border-radius: 4px;">⏹ Stop</button>
            <div id="failed-section" style="display: none; margin-top: 10px; border-top: 2px solid #f44336; padding-top: 10px;">
                <h4 style="margin: 0 0 10px 0; color: #f44336;">❌ Failed Pages - Manual Retry</h4>
                <div id="failed-buttons" style="display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 10px;"></div>
                <button id="retry-all-failed" style="background: #ff9800; color: white; border: none; padding: 8px; cursor: pointer; width: 100%; border-radius: 4px; margin-bottom: 5px;">🔄 Retry All Failed Pages</button>
                <button id="clear-failed" style="background: #999; color: white; border: none; padding: 8px; cursor: pointer; width: 100%; border-radius: 4px;">🗑 Clear Failed List</button>
            </div>
            <div style="margin-bottom: 10px;">
                <label>📸 Image Quality:</label>
                <select id="image-quality" style="width: 100%; margin-top: 5px;">
                    <option value="0.92" selected>High Quality (JPEG 92%, ~2-5MB per page)</option>
                    <option value="0.85">Good Quality (JPEG 85%, ~1-3MB per page)</option>
                    <option value="0.75">Balanced (JPEG 75%, ~0.8-2MB per page)</option>
                    <option value="1.0">Lossless (PNG, 20-80MB per page - NOT RECOMMENDED)</option>
                </select>
                <small style="display: block; color: #666;">JPEG 92% looks identical to PNG but 10x smaller</small>
            </div>
            <div style="margin-bottom: 10px; padding: 8px; background: #fff3e0; border-radius: 4px;">
                <label>
                    <input type="checkbox" id="web-optimized" checked style="margin-right: 5px;">
                    🌐 Web Optimized (resize to 1200px width max)
                </label>
                <small style="display: block; color: #666;">Reduces file size by 50-70% with minimal quality loss</small>
            </div>
            <div id="thumbnails" style="margin-top: 10px; max-height: 300px; overflow-y: auto; border-top: 1px solid #ccc; padding-top: 10px;"></div>
            <div id="scraper-status" style="margin-top: 10px; font-size: 11px; color: #666;"></div>
            <div id="scraper-progress" style="margin-top: 5px; height: 24px; background: #f0f0f0; border-radius: 4px; overflow: hidden; display: none;">
                <div id="progress-bar" style="height: 100%; background: #4CAF50; width: 0%; transition: width 0.3s;"></div>
            </div>
        `;

    document.body.appendChild(container);

    const style = document.createElement("style");
    style.textContent = `
        .switch .slider:before {
            position: absolute;
            content: "";
            height: 18px;
            width: 18px;
            left: 3px;
            bottom: 3px;
            background-color: white;
            transition: .3s;
            border-radius: 50%;
        }
        .switch input:checked + .slider {
            background-color: #4CAF50;
        }
        .switch input:checked + .slider:before {
            transform: translateX(26px);
        }
    `;
    document.head.appendChild(style);

    const autoToggle = document.getElementById("auto-scrape-toggle");
    if (autoToggle) {
      // Load saved state
      const savedAutoState = localStorage.getItem("magazine_auto_scrape");
      if (savedAutoState !== null) {
        autoScrapeEnabled = savedAutoState === "true";
        autoToggle.checked = autoScrapeEnabled;
      } else {
        autoScrapeEnabled = true;
        autoToggle.checked = true;
      }
      // ========== ADD THIS BLOCK RIGHT HERE ==========
      // Start the auto-scrape watcher immediately if enabled
      if (autoScrapeEnabled && !autoScrapeInterval) {
        // Check if PDF is already loaded
        const pages = document.querySelectorAll(".page");
        const canvas = document.querySelector("canvas");
        if (
          (pages.length > 0 || getTotalPagesFromViewer() > 0) &&
          canvas &&
          !isScraping &&
          !scrapeCompleted
        ) {
          console.log(
            "[Auto-Scrape] PDF already loaded on UI creation, starting scrape..."
          );
          setTimeout(() => startScraping(), 1000);
        } else {
          console.log("[Auto-Scrape] Starting watcher for PDF load...");
          setupAutoScrapeWatcher();
        }
      }
      autoToggle.addEventListener("change", function (e) {
        autoScrapeEnabled = this.checked;
        localStorage.setItem("magazine_auto_scrape", autoScrapeEnabled); // ADD THIS LINE

        const autoStatus = document.getElementById("auto-status");

        if (autoScrapeEnabled) {
          scrapeCompleted = false;
          autoStatus.innerHTML = "🟢 ACTIVE - Will start when PDF loads";
          autoStatus.style.color = "#2e7d32";
          updateStatus(
            "🤖 Auto-scrape ENABLED - scraping will start automatically when PDF is ready"
          );

          const pages = document.querySelectorAll(".page");
          const canvas = document.querySelector("canvas");
          if (
            (pages.length > 0 || getTotalPagesFromViewer() > 0) &&
            canvas &&
            !isScraping &&
            !scrapeCompleted
          ) {
            updateStatus("🤖 PDF already loaded, starting scrape now...");
            startScraping();
          } else {
            if (!autoScrapeInterval) {
              setupAutoScrapeWatcher();
            }
          }
        } else {
          autoStatus.innerHTML = "🔴 OFF - Manual mode only";
          autoStatus.style.color = "#d32f2f";
          updateStatus(
            "🤖 Auto-scrape DISABLED - use Start button for manual scraping"
          );

          if (autoScrapeInterval) {
            clearInterval(autoScrapeInterval);
            autoScrapeInterval = null;
          }

          if (isScraping) {
            stopScraping();
          }
        }
      });

      const autoStatus = document.getElementById("auto-status");
      if (autoStatus) {
        autoStatus.innerHTML = "";
        autoStatus.style.color = "#666";
      }
    }

    document.getElementById("start-scrape").addEventListener("click", () => {
      if (autoScrapeEnabled) {
        const autoToggle = document.getElementById("auto-scrape-toggle");
        if (autoToggle) autoToggle.checked = false;
        autoScrapeEnabled = false;
        const autoStatus = document.getElementById("auto-status");
        if (autoStatus) {
          autoStatus.innerHTML = "🔴 OFF - Manual mode only";
          autoStatus.style.color = "#d32f2f";
        }
        if (autoScrapeInterval) {
          clearInterval(autoScrapeInterval);
          autoScrapeInterval = null;
        }
      }
      startScraping();
    });

    document
      .getElementById("stop-scrape")
      .addEventListener("click", stopScraping);

    document
      .getElementById("download-page-btn")
      .addEventListener("click", downloadSpecificPage);

    const titleInput = document.getElementById("custom-title");
    if (titleInput) {
      titleInput.addEventListener("change", function () {
        customTitle = this.value
          .replace(/[<>:"/\\|?*]/g, "")
          .replace(/\s+/g, "_");
        if (!customTitle) customTitle = "magazine";
        this.value = customTitle;
        updateStatus("📝 Title updated: " + customTitle);
      });
    }

    if (totalPages === 0) {
      const checkPagesInterval = setInterval(() => {
        const newTotal = getTotalPagesFromViewer();
        if (newTotal > 0) {
          clearInterval(checkPagesInterval);
          totalPages = newTotal;
          const detectedSpan = document.getElementById("detected-pages");
          const endInput = document.getElementById("end-page");
          const specificPageInput = document.getElementById("specific-page");
          if (detectedSpan) detectedSpan.textContent = totalPages;
          if (endInput && endInput.value === "102") endInput.value = totalPages;
          if (specificPageInput) specificPageInput.max = totalPages;
          updateStatus("📊 Updated: Found " + totalPages + " total pages");
        }
      }, 2000);

      setTimeout(() => clearInterval(checkPagesInterval), 15000);
    }
  }

  function getTitleFromPage() {
    const titleElement = document.querySelector(
      ".page-module__gMr9Pq__item-pdf-page__title-text"
    );
    if (titleElement) {
      let title = titleElement.textContent.trim();
      title = title.replace(/[<>:"/\\|?*]/g, "");
      title = title.replace(/\s+/g, "_");
      if (title.length > 100) {
        title = title.substring(0, 100);
      }
      return title;
    }
    return "Video_Game_History_Foundation_Library";
  }

  async function downloadSpecificPage() {
    const pageNum = parseInt(document.getElementById("specific-page").value);
    const title = getCustomTitle();
    const pageDelay = parseInt(document.getElementById("page-delay").value);

    if (isNaN(pageNum) || pageNum < 1) {
      updateStatus("⚠️ Please enter a valid page number");
      return;
    }

    updateStatus("🎯 Capturing page " + pageNum + "...");

    try {
      const imageData = await captureSinglePageManual(
        pageNum,
        pageDelay,
        1,
        2,
        true
      );

      if (imageData) {
        await saveImageAsPNG(imageData, pageNum, title);

        if (!pageData.has(pageNum)) {
          pageData.set(pageNum, true);
          addThumbnail(imageData, pageNum);
        }

        updateStatus(
          "✅ Page " +
            pageNum +
            " captured and saved as " +
            title +
            "_page_" +
            pageNum +
            ".png"
        );

        if (typeof GM_notification !== "undefined") {
          GM_notification({
            title: "Magazine Scraper",
            text:
              "Saved page " +
              pageNum +
              " as " +
              title +
              "_page_" +
              pageNum +
              ".png",
            timeout: 3000,
          });
        }
      } else {
        updateStatus("❌ Failed to capture page " + pageNum);
      }
    } catch (e) {
      updateStatus("❌ Error capturing page " + pageNum + ": " + e.message);
    }
  }

  function updateFailedSection() {
    const failedSection = document.getElementById("failed-section");
    const failedButtons = document.getElementById("failed-buttons");

    if (!failedSection || !failedButtons) return;

    if (failedPagesList.length > 0) {
      failedSection.style.display = "block";
      failedButtons.innerHTML = "";

      const sortedFailed = [...failedPagesList].sort((a, b) => a - b);

      for (const page of sortedFailed) {
        const button = document.createElement("button");
        button.textContent = "Page " + page;
        button.style.cssText = `
                    background: #f44336;
                    color: white;
                    border: none;
                    padding: 5px 10px;
                    cursor: pointer;
                    border-radius: 4px;
                    font-size: 12px;
                `;
        button.onclick = () => manualRetrySinglePage(page);
        failedButtons.appendChild(button);
      }

      const retryAllBtn = document.getElementById("retry-all-failed");
      const clearFailedBtn = document.getElementById("clear-failed");

      if (retryAllBtn) {
        retryAllBtn.onclick = () => manualRetryAllPages();
      }
      if (clearFailedBtn) {
        clearFailedBtn.onclick = () => {
          failedPagesList = [];
          updateFailedSection();
          updateStatus("✅ Failed pages list cleared");
        };
      }
    } else {
      failedSection.style.display = "none";
    }
  }

  async function manualRetrySinglePage(pageNum) {
    if (manualRetryActive) {
      updateStatus("⚠️ Please wait, a retry is already in progress");
      return;
    }

    manualRetryActive = true;
    updateStatus("🔧 Manually retrying page " + pageNum + "...");

    const pageDelay = parseInt(document.getElementById("page-delay").value);
    const title = getCustomTitle();

    try {
      const imageData = await captureSinglePageManual(
        pageNum,
        pageDelay + 3000,
        1,
        3,
        true
      );

      if (imageData) {
        const sortedPages = Array.from(pageData.keys()).sort((a, b) => a - b);
        let insertIndex = sortedPages.findIndex((p) => p > pageNum);
        if (insertIndex === -1) insertIndex = pageData.size;

        pageData.set(pageNum, imageData);
        addThumbnail(imageData, pageNum);

        failedPagesList = failedPagesList.filter((p) => p !== pageNum);
        updateFailedSection();

        const saveImages =
          document.getElementById("save-images")?.checked || false;
        if (saveImages) {
          await saveImageAsPNG(imageData, pageNum, title);
        }
        await wait(500);
        updateStatus("✅ Manually retried page " + pageNum + " - SUCCESS!");

        const autoSave = document.getElementById("auto-save")?.checked || false;
        if (autoSave) {
          generateExternalHTML(title);
        }
      } else {
        updateStatus("❌ Manual retry for page " + pageNum + " - FAILED again");
      }
    } catch (e) {
      updateStatus(
        "❌ Manual retry error for page " + pageNum + ": " + e.message
      );
    }

    manualRetryActive = false;
  }

  async function manualRetryAllPages() {
    if (manualRetryActive) {
      updateStatus("⚠️ Please wait, a retry is already in progress");
      return;
    }

    if (failedPagesList.length === 0) {
      updateStatus("✅ No failed pages to retry");
      return;
    }

    manualRetryActive = true;
    updateStatus(
      "🔧 Manually retrying all " + failedPagesList.length + " failed pages..."
    );

    const pageDelay = parseInt(document.getElementById("page-delay").value);
    const title = getCustomTitle();
    const saveImages = document.getElementById("save-images")?.checked || false;
    const autoSave = document.getElementById("auto-save")?.checked || false;

    const pagesToRetry = [...failedPagesList];
    let successCount = 0;

    for (const pageNum of pagesToRetry) {
      updateStatus(
        "🔧 Retrying page " +
          pageNum +
          " (" +
          (successCount + 1) +
          "/" +
          pagesToRetry.length +
          ")..."
      );

      const imageData = await captureSinglePageManual(
        pageNum,
        pageDelay + 3000,
        1,
        3,
        true
      );

      if (imageData) {
        const sortedPages = Array.from(pageData.keys()).sort((a, b) => a - b);
        let insertIndex = sortedPages.findIndex((p) => p > pageNum);
        if (insertIndex === -1) insertIndex = pageData.size;

        pageData.set(pageNum, true);
        addThumbnail(imageData, pageNum);

        await saveImageAsPNG(imageData, pageNum, title);

        successCount++;
        updateStatus("✅ Retried page " + pageNum + " - SUCCESS!");
      } else {
        updateStatus("❌ Retried page " + pageNum + " - FAILED again");
      }

      await wait(1000);
    }

    failedPagesList = failedPagesList.filter((p) => {
      const stillFailed = !pageData.has(p);
      return stillFailed;
    });
    updateFailedSection();

    if (autoSave && pageData.size > 0) {
      generateExternalHTML(title);
    }

    updateStatus(
      "✅ Manual retry complete! " +
        successCount +
        "/" +
        pagesToRetry.length +
        " pages recovered"
    );

    if (typeof GM_notification !== "undefined") {
      GM_notification({
        title: "Magazine Scraper",
        text:
          "Retried " +
          pagesToRetry.length +
          " pages, " +
          successCount +
          " succeeded",
        timeout: 5000,
      });
    }

    manualRetryActive = false;
  }

  async function captureSinglePageManual(
    pageNum,
    baseDelay,
    retryAttempt = 1,
    maxRetries = 3,
    forceCapture = true
  ) {
    try {
      updateStatus(
        "📄 Manually processing page " +
          pageNum +
          " (Attempt " +
          retryAttempt +
          "/" +
          maxRetries +
          ")..."
      );

      const delay = baseDelay + (retryAttempt - 1) * 2000;
      const imageData = await scrollToPageAndCaptureManual(
        pageNum,
        delay,
        forceCapture
      );

      if (imageData && imageData.length > 10000) {
        return imageData;
      } else if (imageData && imageData.length >= 5000) {
        return imageData;
      }

      if (retryAttempt < maxRetries) {
        await wait(3000);
        return await captureSinglePageManual(
          pageNum,
          baseDelay,
          retryAttempt + 1,
          maxRetries,
          forceCapture
        );
      }

      return null;
    } catch (e) {
      if (retryAttempt < maxRetries) {
        await wait(3000);
        return await captureSinglePageManual(
          pageNum,
          baseDelay,
          retryAttempt + 1,
          maxRetries,
          forceCapture
        );
      }
      return null;
    }
  }

  async function scrollToPageAndCaptureManual(
    pageNum,
    delay,
    forceCapture = true
  ) {
    const pageElement = document.querySelector(
      '.page[data-page-number="' + pageNum + '"]'
    );

    if (!pageElement) {
      updateStatus("⚠️ Page " + pageNum + ": Element not found");
      return null;
    }

    pageElement.scrollIntoView({ behavior: "smooth", block: "start" });
    await wait(1500);

    let waitCycles = 0;
    const maxCycles = Math.ceil(delay / 500);

    while (waitCycles < maxCycles) {
      let loadingDetected = false;
      const loadingSelectors = [
        ".loading-icon",
        ".loading-spinner",
        '[class*="loading"]',
        ".spinner",
        ".loader",
        ".waiting",
      ];

      for (const selector of loadingSelectors) {
        const loadingElements = pageElement.querySelectorAll(selector);
        for (const el of loadingElements) {
          const style = window.getComputedStyle(el);
          if (style.display !== "none" && style.visibility !== "hidden") {
            loadingDetected = true;
            break;
          }
        }
        if (loadingDetected) break;
      }

      if (!loadingDetected) break;
      await wait(500);
      waitCycles++;
    }

    const canvas = pageElement.querySelector("canvas");
    if (!canvas) {
      updateStatus("⚠️ Page " + pageNum + ": No canvas found");
      return null;
    }

    await wait(1000);

    if (canvas.width === 0 || canvas.height === 0) {
      updateStatus("⚠️ Page " + pageNum + ": Canvas has zero dimensions");
      await wait(2000);
    }

    const imageData = await captureCanvasDirect(canvas, pageNum);

    if (!imageData) {
      return null;
    }

    if (!forceCapture) {
      const isBlank = await isImageBlackOrBlank(imageData);
      if (isBlank) {
        updateStatus(
          "⚠️ Page " +
            pageNum +
            ": Detected black/blank screen - marking as failed"
        );
        return null;
      }
    }

    return imageData;
  }

  function getCustomTitle() {
    const titleInput = document.getElementById("custom-title");
    if (titleInput && titleInput.value) {
      let title = titleInput.value;
      title = title.replace(/[<>:"/\\|?*]/g, "");
      title = title.replace(/\s+/g, "_");
      if (title.length > 100) {
        title = title.substring(0, 100);
      }
      return title;
    }
    return "magazine";
  }

  function addThumbnail(imageData, pageNum) {
    const thumbDiv = document.getElementById("thumbnails");
    if (!thumbDiv) return;

    const existingThumb = thumbDiv.querySelector(
      '[data-page="' + pageNum + '"]'
    );
    if (existingThumb) return;

    const container = document.createElement("div");
    container.setAttribute("data-page", pageNum);
    container.style.cssText = `
          display: inline-block;
          width: 40px;
          margin: 3px;
          text-align: center;
          font-size: 10px;
          border: 2px solid #4CAF50;
          padding: 3px;
          cursor: pointer;
          border-radius: 4px;
          background: #f9f9f9;
      `;

    container.title = "Page " + pageNum;
    container.onclick = () => {
      const pageElement = document.querySelector(
        '.page[data-page-number="' + pageNum + '"]'
      );
      if (pageElement) {
        pageElement.scrollIntoView({ behavior: "smooth", block: "start" });
      }
    };

    const img = document.createElement("img");

    fetch(imageData)
      .then((res) => res.blob())
      .then((blob) => {
        const blobUrl = URL.createObjectURL(blob);
        img.src = blobUrl;
        img.onload = () => {
          URL.revokeObjectURL(blobUrl);
        };
      })
      .catch(() => {
        img.src = imageData;
      });

    img.style.width = "35px";
    img.style.height = "auto";
    img.style.display = "block";
    img.style.margin = "0 auto";

    const label = document.createElement("div");
    label.textContent = "Pg " + pageNum;
    label.style.marginTop = "4px";
    label.style.fontWeight = "bold";
    label.style.color = "#4CAF50";

    container.appendChild(img);
    container.appendChild(label);
    thumbDiv.appendChild(container);
    thumbDiv.scrollTop = thumbDiv.scrollHeight;
  }

  function isImageBlackOrBlank(dataURL) {
    return new Promise((resolve) => {
      const img = new Image();
      img.onload = () => {
        const canvas = document.createElement("canvas");
        canvas.width = Math.min(img.width, 200);
        canvas.height = Math.min(img.height, 200);
        const ctx = canvas.getContext("2d");
        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);

        const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
        let pureBlackPixels = 0;
        let totalPixels = 0;
        let hasAnyContent = false;

        for (let i = 0; i < imageData.data.length; i += 4) {
          const r = imageData.data[i];
          const g = imageData.data[i + 1];
          const b = imageData.data[i + 2];
          const a = imageData.data[i + 3];

          totalPixels++;

          if (r === 0 && g === 0 && b === 0 && a > 200) {
            pureBlackPixels++;
          }

          if ((r > 5 || g > 5 || b > 5) && a > 200) {
            hasAnyContent = true;
          }
        }

        const pureBlackRatio = pureBlackPixels / totalPixels;
        const isBlank = pureBlackRatio > 0.99 && !hasAnyContent;

        if (isBlank) {
          console.log(
            "[Scraper] Blank detection: " +
              Math.round(pureBlackRatio * 100) +
              "% pure black pixels, no content found"
          );
        } else if (pureBlackRatio > 0.5) {
          console.log(
            "[Scraper] Dark image detected but has content: " +
              Math.round(pureBlackRatio * 100) +
              "% black pixels - ACCEPTING"
          );
        }

        resolve(isBlank);
      };
      img.onerror = () => {
        console.log("[Scraper] Error loading image for blank detection");
        resolve(false);
      };
      img.src = dataURL;
    });
  }

  async function saveAllImages(title) {
    updateStatus("💾 Saving " + pageData.size + " individual images...");
    let saved = 0;

    const sortedPages = Array.from(pageData.keys()).sort((a, b) => a - b);

    for (const pageNum of sortedPages) {
      const imageData = pageData.get(pageNum);
      if (imageData) {
        await saveImageAsPNG(imageData, pageNum, title);
        saved++;
        pageData.delete(pageNum);
        updateStatus(`💾 Saved ${saved}/${sortedPages.length} images`);
        await wait(300);
      }
    }

    updateStatus("✅ Saved " + saved + " individual PNG images");

    if (typeof GM_notification !== "undefined") {
      GM_notification({
        title: "Magazine Scraper",
        text: "Saved " + saved + " images as " + title + "_page_*.png",
        timeout: 5000,
      });
    }
  }

  function generateExternalHTML(title) {
    if (pageData.size === 0) {
      updateStatus("⚠️ No pages captured, skipping HTML generation");
      return;
    }
    // Sanitize title - remove apostrophes and problematic characters
    let safeTitle = title.replace(/'/g, "\\'").replace(/"/g, '\\"');

    updateStatus("📄 Generating HTML with external image references...");

    const html =
      "<!DOCTYPE html>\n" +
      "<html>\n" +
      "\n" +
      "<head>\n" +
      '    <meta charset="UTF-8">\n' +
      '    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">\n' +
      "    <title>" +
      safeTitle +
      "</title>\n" +
      '    <script type="text/javascript" src="https://code.jquery.com/jquery-1.7.1.min.js"></script>\n' +
      '    <script type="text/javascript" src="https://cdn.gitgpt.chat/rtx/magazine_turn.js"></script>\n' +
      "    <style>\n" +
      "        * {\n" +
      "            margin: 0;\n" +
      "            padding: 0;\n" +
      "            box-sizing: border-box;\n" +
      "        }\n" +
      "\n" +
      "        body {\n" +
      "            background: #2c3e50;\n" +
      "            display: flex;\n" +
      "            justify-content: center;\n" +
      "            align-items: center;\n" +
      "            min-height: 100vh;\n" +
      "            font-family: 'Segoe UI', Arial, sans-serif;\n" +
      "            padding: 0px;\n" +
      "            overflow: hidden;\n" +
      "            position: fixed;\n" +
      "            top: 0;\n" +
      "            left: 0;\n" +
      "            right: 0;\n" +
      "            bottom: 0;\n" +
      "            -webkit-overflow-scrolling: touch;\n" +
      "            overscroll-behavior: none;\n" +
      "        }\n" +
      "\n" +
      "        #magazine {\n" +
      "            width: 100vw;\n" +
      "            height: 100vh;\n" +
      "            background: #fff;\n" +
      "            overscroll-behavior: none;\n" +
      "        }\n" +
      "\n" +
      "        #magazine .turn-page {\n" +
      "            background-size: 100.5% 100.5% !important;\n" +
      "            background-position: center;\n" +
      "            background-repeat: no-repeat;\n" +
      "            background-color: #cbcbcb63;\n" +
      "        }\n" +
      "\n" +
      "        html {\n" +
      "            overflow: hidden;\n" +
      "            position: fixed;\n" +
      "            width: 100%;\n" +
      "            height: 100%;\n" +
      "            overscroll-behavior: none;\n" +
      "            touch-action: pan-y pinch-zoom;\n" +
      "        }\n" +
      "\n" +
      "        .turn-page.loading {\n" +
      "            position: relative;\n" +
      "        }\n" +
      "\n" +
      "        .turn-page.loading::after {\n" +
      '            content: "📰";\n' +
      "            position: absolute;\n" +
      "            top: 50%;\n" +
      "            left: 50%;\n" +
      "            transform: translate(-50%, -50%);\n" +
      "            font-size: 40px;\n" +
      "            animation: spin 1s linear infinite;\n" +
      "        }\n" +
      "\n" +
      "        @keyframes spin {\n" +
      "            from {\n" +
      "                transform: translate(-50%, -50%) rotate(0deg);\n" +
      "            }\n" +
      "            to {\n" +
      "                transform: translate(-50%, -50%) rotate(360deg);\n" +
      "            }\n" +
      "        }\n" +
      "\n" +
      "        @media (hover: none) and (pointer: coarse) {\n" +
      "            html, body {\n" +
      "                margin: 0 !important;\n" +
      "                padding: 0 !important;\n" +
      "                top: 0 !important;\n" +
      "                left: 0 !important;\n" +
      "                position: fixed !important;\n" +
      "            }\n" +
      "            body {\n" +
      "                display: block !important;\n" +
      "                align-items: flex-start !important;\n" +
      "                justify-content: flex-start !important;\n" +
      "            }\n" +
      "            #magazine {\n" +
      "                top: 0 !important;\n" +
      "                left: 0 !important;\n" +
      "                position: absolute !important;\n" +
      "                margin: 0 !important;\n" +
      "            }\n" +
      "            #pageScrollOverlay {\n" +
      "                top: 0 !important;\n" +
      "                bottom: 0 !important;\n" +
      "                transform: translateX(-50%) !important;\n" +
      "            }\n" +
      "        }\n" +
      "    </style>\n" +
      "</head>\n" +
      "\n" +
      "<body>\n" +
      '    <div id="magazine"></div>\n' +
      "    <script>\n" +
      "        const totalPages = " +
      pageData.size +
      ";\n" +
      "        const title = '" +
      safeTitle +
      "';\n" +
      "        \n" +
      "        let currentPageNumber = 1;\n" +
      "        let turnInstance = null;\n" +
      "        let isRebuilding = false;\n" +
      "        let loadedPages = new Set();\n" +
      "        let loadingPages = new Set();\n" +
      "        let preloadQueue = [];\n" +
      "        \n" +
      "        function getSavedPage() {\n" +
      "            const storageKey = 'flipbook_last_page_' + title;\n" +
      "            const saved = localStorage.getItem(storageKey);\n" +
      "            if (saved && !isNaN(saved) && saved >= 1 && saved <= totalPages) {\n" +
      "                return parseInt(saved);\n" +
      "            }\n" +
      "            return 1;\n" +
      "        }\n" +
      "\n" +
      "        function savePage(pageNum) {\n" +
      "            const storageKey = 'flipbook_last_page_' + title;\n" +
      "            localStorage.setItem(storageKey, pageNum);\n" +
      "        }\n" +
      "        \n" +
      "        function createMagazine() {\n" +
      "            const magazine = $('#magazine');\n" +
      "            magazine.empty();\n" +
      "            for (let i = 1; i <= totalPages; i++) {\n" +
      "                const pageDiv = $('<div>')\n" +
      "                    .addClass('turn-page loading')\n" +
      "                    .attr('data-page', i)\n" +
      "                    .attr('data-loaded', 'false');\n" +
      "                magazine.append(pageDiv);\n" +
      "            }\n" +
      "        }\n" +
      "        \n" +
      "        function loadPageImage(pageNum, priority = false) {\n" +
      "            return new Promise((resolve) => {\n" +
      "                if (loadedPages.has(pageNum) || loadingPages.has(pageNum)) {\n" +
      "                    resolve();\n" +
      "                    return;\n" +
      "                }\n" +
      "                const pageDiv = $('.turn-page[data-page=\"' + pageNum + '\"]');\n" +
      "                if (!pageDiv.length) {\n" +
      "                    resolve();\n" +
      "                    return;\n" +
      "                }\n" +
      "                if (pageDiv.attr('data-loaded') === 'true') {\n" +
      "                    loadedPages.add(pageNum);\n" +
      "                    resolve();\n" +
      "                    return;\n" +
      "                }\n" +
      "                loadingPages.add(pageNum);\n" +
      "                const img = new Image();\n" +
      "                const imgPath = title + '_page_' + pageNum + '.png';\n" +
      "                img.onload = function () {\n" +
      "                    pageDiv.css('background-image', 'url(' + imgPath + ')');\n" +
      "                    pageDiv.removeClass('loading');\n" +
      "                    pageDiv.attr('data-loaded', 'true');\n" +
      "                    loadedPages.add(pageNum);\n" +
      "                    loadingPages.delete(pageNum);\n" +
      "                    if (priority) console.log('[Priority] Page ' + pageNum + ' loaded');\n" +
      "                    resolve();\n" +
      "                };\n" +
      "                img.onerror = function () {\n" +
      '                    pageDiv.css(\'background-image\', \'url(\\\'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" width="100%25" height="100%25"%3E%3Crect width="100%25" height="100%25" fill="%23333"/%3E%3Ctext x="50%25" y="50%25" text-anchor="middle" fill="%23666" font-size="20"%3EPage \' + pageNum + \'%3C/text%3E%3C/svg%3E\\\')\');\n' +
      "                    pageDiv.removeClass('loading');\n" +
      "                    pageDiv.attr('data-loaded', 'error');\n" +
      "                    loadingPages.delete(pageNum);\n" +
      "                    console.warn('Failed to load page ' + pageNum + ': ' + imgPath);\n" +
      "                    resolve();\n" +
      "                };\n" +
      "                img.src = imgPath;\n" +
      "            });\n" +
      "        }\n" +
      "        \n" +
      "        function preloadNearbyPages(currentPage, displayMode) {\n" +
      "            let pagesToPreload = [];\n" +
      "            if (displayMode === 'single') {\n" +
      "                pagesToPreload = [currentPage + 1, currentPage + 2, currentPage + 3, currentPage + 4, currentPage + 5, currentPage - 1, currentPage - 2];\n" +
      "            } else {\n" +
      "                pagesToPreload = [currentPage + 1, currentPage + 2, currentPage + 3, currentPage + 4, currentPage - 1, currentPage - 2];\n" +
      "            }\n" +
      "            const pagesToLoad = pagesToPreload.filter(pageNum => {\n" +
      "                return pageNum >= 1 && pageNum <= totalPages && !loadedPages.has(pageNum) && !loadingPages.has(pageNum);\n" +
      "            });\n" +
      "            if (pagesToLoad.length > 0) {\n" +
      "                if (displayMode === 'single' && currentPage + 1 <= totalPages && !loadedPages.has(currentPage + 1)) {\n" +
      "                    loadPageImage(currentPage + 1, true);\n" +
      "                }\n" +
      "                pagesToLoad.forEach((pageNum, index) => {\n" +
      "                    if (pageNum !== currentPage + 1) {\n" +
      "                        setTimeout(() => {\n" +
      "                            if (!loadedPages.has(pageNum) && !loadingPages.has(pageNum)) loadPageImage(pageNum);\n" +
      "                        }, index * 150);\n" +
      "                    }\n" +
      "                });\n" +
      "            }\n" +
      "        }\n" +
      "        \n" +
      "        function initFlipBook() {\n" +
      "            if (isRebuilding) return;\n" +
      "            isRebuilding = true;\n" +
      "            const isLandscape = window.matchMedia('(orientation: landscape)').matches;\n" +
      "            const displayMode = isLandscape ? 'double' : 'single';\n" +
      "            let pageToRestore = currentPageNumber;\n" +
      "            if (pageToRestore < 1) pageToRestore = 1;\n" +
      "            if (pageToRestore > totalPages) pageToRestore = totalPages;\n" +
      "            if (turnInstance) {\n" +
      "                try { $('#magazine').turn('destroy'); } catch (e) { console.log('Destroy error:', e); }\n" +
      "            }\n" +
      "            setTimeout(() => {\n" +
      "                $('#magazine').turn({\n" +
      "                    display: displayMode,\n" +
      "                    acceleration: true,\n" +
      "                    gradients: !$.isTouch,\n" +
      "                    elevation: 50,\n" +
      "                    duration: 400,\n" +
      "                    page: pageToRestore,\n" +
      "                    when: {\n" +
      "                        turning: function (e, page) {\n" +
      "                            if (page >= 1 && page <= totalPages && !loadedPages.has(page)) loadPageImage(page, true);\n" +
      "                        },\n" +
      "                        turned: function (e, page) {\n" +
      "                            currentPageNumber = page;\n" +
      "                            savePage(page);\n" +
      "                            const currentDisplayMode = $(this).turn('display');\n" +
      "                            const visiblePages = $(this).turn('view');\n" +
      "                            visiblePages.forEach(pageNum => { if (pageNum > 0 && pageNum <= totalPages) loadPageImage(pageNum); });\n" +
      "                            preloadNearbyPages(page, currentDisplayMode);\n" +
      "                        },\n" +
      "                        first: function () {\n" +
      "                            const firstPages = $(this).turn('view');\n" +
      "                            firstPages.forEach(pageNum => { if (pageNum > 0 && pageNum <= totalPages) loadPageImage(pageNum); });\n" +
      "                            const currentDisplayMode = $(this).turn('display');\n" +
      "                            preloadNearbyPages(pageToRestore, currentDisplayMode);\n" +
      "                        },\n" +
      "                        missing: function (e, pages) {\n" +
      "                            for (let i = 0; i < pages.length; i++) {\n" +
      "                                if (pages[i] >= 1 && pages[i] <= totalPages) loadPageImage(pages[i], true);\n" +
      "                            }\n" +
      "                        }\n" +
      "                    }\n" +
      "                });\n" +
      "                turnInstance = $('#magazine');\n" +
      "                isRebuilding = false;\n" +
      "                console.log('Flip book initialized: ' + displayMode + ' mode, page ' + pageToRestore);\n" +
      "            }, 50);\n" +
      "        }\n" +
      "        \n" +
      "        createMagazine();\n" +
      "        \n" +
      "        async function initialPreload() {\n" +
      "            for (let i = 1; i <= 6; i++) {\n" +
      "                if (i <= totalPages) await loadPageImage(i, true);\n" +
      "            }\n" +
      "            console.log('Initial preload complete');\n" +
      "        }\n" +
      "        \n" +
      "        currentPageNumber = getSavedPage();\n" +
      "        initialPreload();\n" +
      "        $(window).ready(function () { initFlipBook(); });\n" +
      "        \n" +
      "        $(window).on('orientationchange', function () {\n" +
      "            if (turnInstance) {\n" +
      "                try {\n" +
      "                    const currentView = turnInstance.turn('view');\n" +
      "                    if (currentView && currentView.length) currentPageNumber = currentView[0] || currentPageNumber;\n" +
      "                } catch (e) { }\n" +
      "            }\n" +
      "            setTimeout(() => {\n" +
      "                createMagazine();\n" +
      "                loadedPages.clear();\n" +
      "                loadingPages.clear();\n" +
      "                preloadQueue = [];\n" +
      "                initFlipBook();\n" +
      "                initialPreload();\n" +
      "            }, 100);\n" +
      "        });\n" +
      "        \n" +
      "        let resizeTimer;\n" +
      "        $(window).on('resize', function () {\n" +
      "            clearTimeout(resizeTimer);\n" +
      "            resizeTimer = setTimeout(() => {\n" +
      "                if (turnInstance) {\n" +
      "                    try {\n" +
      "                        const currentView = turnInstance.turn('view');\n" +
      "                        if (currentView && currentView.length) currentPageNumber = currentView[0] || currentPageNumber;\n" +
      "                    } catch (e) { }\n" +
      "                    const isLandscape = window.matchMedia('(orientation: landscape)').matches;\n" +
      "                    const displayMode = isLandscape ? 'double' : 'single';\n" +
      "                    if (turnInstance.turn('display') !== displayMode) {\n" +
      "                        setTimeout(() => {\n" +
      "                            createMagazine();\n" +
      "                            loadedPages.clear();\n" +
      "                            loadingPages.clear();\n" +
      "                            preloadQueue = [];\n" +
      "                            initFlipBook();\n" +
      "                            initialPreload();\n" +
      "                        }, 100);\n" +
      "                    } else {\n" +
      "                        try { turnInstance.turn('resize'); } catch (e) { }\n" +
      "                    }\n" +
      "                }\n" +
      "            }, 200);\n" +
      "        });\n" +
      "        \n" +
      "        $(window).bind('keydown', function (e) {\n" +
      "            if (e.keyCode == 37) { $('#magazine').turn('previous'); e.preventDefault(); }\n" +
      "            else if (e.keyCode == 39) { $('#magazine').turn('next'); e.preventDefault(); }\n" +
      "        });\n" +
      "        \n" +
      "        document.body.addEventListener('touchmove', function (e) {\n" +
      "            if (e.target === document.body || e.target === document.documentElement) e.preventDefault();\n" +
      "        }, { passive: false });\n" +
      "        \n" +
      "        document.body.addEventListener('touchend', function () {\n" +
      "            setTimeout(() => {\n" +
      "                if (turnInstance) {\n" +
      "                    try {\n" +
      "                        const currentView = turnInstance.turn('view');\n" +
      "                        if (currentView && currentView.length) {\n" +
      "                            currentPageNumber = currentView[0] || currentPageNumber;\n" +
      "                            savePage(currentPageNumber);\n" +
      "                        }\n" +
      "                    } catch (e) { }\n" +
      "                }\n" +
      "            }, 100);\n" +
      "        });\n" +
      "        \n" +
      "        console.log('Flip book initialized with ' + totalPages + ' pages (aggressive preloading enabled)');\n" +
      "        console.log('Next page is preloaded before you flip for smooth transitions');\n" +
      "    </script>\n" +
      "    <script>\n" +
      "        (function () {\n" +
      "            let pageScrollDragging = false;\n" +
      "            let pageTrackStartY = 0;\n" +
      "            let pageTrackStartScroll = 0;\n" +
      "            let currentTotalPages = " +
      pageData.size +
      ";\n" +
      "            let hideTimeout = null;\n" +
      "            let activeTimeout = null;\n" +
      "\n" +
      "            function getSavedPage() {\n" +
      "                const storageKey = 'flipbook_last_page_' + title;\n" +
      "                const saved = localStorage.getItem(storageKey);\n" +
      "                if (saved && !isNaN(saved) && saved >= 1 && saved <= currentTotalPages) {\n" +
      "                    return parseInt(saved);\n" +
      "                }\n" +
      "                return 1;\n" +
      "            }\n" +
      "\n" +
      "            function savePage(pageNum) {\n" +
      "                const storageKey = 'flipbook_last_page_' + title;\n" +
      "                localStorage.setItem(storageKey, pageNum);\n" +
      "            }\n" +
      "\n" +
      "            function createScrollOverlay() {\n" +
      "                if (document.getElementById('pageScrollOverlay')) return;\n" +
      "                const overlayHTML = `\n" +
      '                <div id="pageScrollOverlay" style="\n' +
      "                    position: fixed;\n" +
      "                    left: 50%;\n" +
      "                    transform: translateX(-50%);\n" +
      "                    top: 0;\n" +
      "                    bottom: 0;\n" +
      "                    z-index: 9999;\n" +
      "                    display: flex;\n" +
      "                    flex-direction: column;\n" +
      "                    align-items: center;\n" +
      "                    justify-content: center;\n" +
      "                    pointer-events: none;\n" +
      "                    opacity: 0;\n" +
      "                    transition: opacity 0.3s ease;\n" +
      '                ">\n' +
      '                    <div class="vertical-ribbon-base" style="\n' +
      "                        position: absolute;\n" +
      "                        overflow: hidden;\n" +
      "                        left: 50%;\n" +
      "                        transform: translateX(-50%);\n" +
      "                        top: 0;\n" +
      "                        bottom: 0;\n" +
      "                        font-size: 14px;\n" +
      "                        font-weight: bold;\n" +
      "                        color: #fff;\n" +
      "                        --r: 0.8em;\n" +
      "                        border-inline: 0.5em solid #0000;\n" +
      "                        padding: 0.5em 0.2em calc(var(--r) + 0.2em);\n" +
      "                        clip-path: polygon(0 0, 100% 0, 100% 100%, calc(100% - 0.5em) 100%, 50% calc(100% - var(--r)), 0.5em 100%, 0 100%);\n" +
      "                        background: url('https://cdn.gitgpt.chat/rtx/images/ribbon.png') repeat-y center top / 100% auto;\n" +
      "                        width: 48px;\n" +
      "                        height: 85vh;\n" +
      "                        max-height: 85%;\n" +
      "                        display: flex;\n" +
      "                        align-items: center;\n" +
      "                        justify-content: center;\n" +
      "                        white-space: nowrap;\n" +
      "                        box-shadow: 2px 2px 8px rgba(0,0,0,0.3);\n" +
      "                        z-index: 9998;\n" +
      '                    ">\n' +
      '                        <span style="writing-mode: vertical-rl; text-orientation: mixed;"></span>\n' +
      "                    </div>\n" +
      "                    \n" +
      '                    <div id="pageDisplayCenter" style="\n' +
      "                        position: absolute;\n" +
      "                        left: 28px;\n" +
      "                        top: calc(50% - 3px);\n" +
      "                        transform: translateY(-50%);\n" +
      "                        font-family: 'Georgia', 'Times New Roman', serif;\n" +
      "                        font-size: 12px;\n" +
      "                        font-weight: normal;\n" +
      "                        font-style: italic;\n" +
      "                        color: #fff8e7;\n" +
      "                        background: url('https://cdn.gitgpt.chat/rtx/images/ribbon2.png') no-repeat center / 100% 100%;\n" +
      "                        padding: 8px;\n" +
      "                        border-radius: 0 4px 4px 0;\n" +
      "                        backdrop-filter: blur(4px);\n" +
      "                        pointer-events: none;\n" +
      "                        white-space: nowrap;\n" +
      "                        z-index: 10;\n" +
      "                        box-shadow: 2px 2px 8px rgba(0,0,0,0.3);\n" +
      "                        opacity: 0;\n" +
      "                        transition: opacity 0.2s ease;\n" +
      "                        letter-spacing: 0.5px;\n" +
      '                    ">\n' +
      '                        <span style="font-family: monospace; font-style: normal; font-weight: bold;"></span>${getSavedPage()} / ${currentTotalPages}\n' +
      "                    </div>\n" +
      "                    \n" +
      '                    <div id="pageSliderContainer" style="\n' +
      "                        position: relative;\n" +
      "                        width: 32px;\n" +
      "                        height: 85vh;\n" +
      "                        max-height: 85%;\n" +
      "                        background: transparent;\n" +
      "                        touch-action: none;\n" +
      "                        pointer-events: auto;\n" +
      "                        cursor: grab;\n" +
      "                        z-index: 9999;\n" +
      '                    ">\n' +
      '                        <div style="\n' +
      "                            position: absolute;\n" +
      "                            top: 0;\n" +
      "                            left: 0;\n" +
      "                            width: 100%;\n" +
      "                            height: 88vh;\n" +
      "                            max-height: 88%;\n" +
      "                            overflow: hidden;\n" +
      "                            pointer-events: none;\n" +
      '                        ">\n' +
      '                            <div id="pageTrack" style="\n' +
      "                                position: absolute;\n" +
      "                                top: 0;\n" +
      "                                left: 0;\n" +
      "                                width: 100%;\n" +
      "                                transition: none;\n" +
      '                            "></div>\n' +
      "                        </div>\n" +
      "                        \n" +
      '                        <div style="\n' +
      "                            position: absolute;\n" +
      "                            left: 50%;\n" +
      "                            top: 50%;\n" +
      "                            transform: translate(-50%, -50%);\n" +
      "                            font-size: 20px;\n" +
      "                            font-weight: bold;\n" +
      "                            color: #fff;\n" +
      "                            --r: 0.5em;\n" +
      "                            border-inline: 0.3em solid #0000;\n" +
      "                            padding: 0.3em 0.15em calc(var(--r) + 0.15em);\n" +
      "                            clip-path: polygon(0 0, 100% 0, 100% 100%, calc(100% - 0.3em) calc(100% - var(--r)), 50% 100%, 0.3em calc(100% - var(--r)), 0 100%);\n" +
      "                            width: 36px;\n" +
      "                            height: 40px;\n" +
      "                            white-space: nowrap;\n" +
      "                            z-index: 15;\n" +
      "                            pointer-events: none;\n" +
      "                            display: flex;\n" +
      "                            align-items: center;\n" +
      "                            justify-content: center;\n" +
      '                        ">\n' +
      '                            <span style="writing-mode: vertical-rl; text-orientation: mixed;">📖</span>\n' +
      "                        </div>\n" +
      "                    </div>\n" +
      "                </div>\n" +
      "            `;\n" +
      "                document.body.insertAdjacentHTML('beforeend', overlayHTML);\n" +
      "                // Set initial position based on display mode\n" +
      "                updateOverlayPosition();\n" +
      "            }\n" +
      "\n" +
      "            // Add this new function to update overlay position based on display mode\n" +
      "            function updateOverlayPosition() {\n" +
      "                const overlay = document.getElementById('pageScrollOverlay');\n" +
      "                if (!overlay) return;\n" +
      "\n" +
      "                const isLandscape = window.matchMedia('(orientation: landscape)').matches;\n" +
      "                const displayMode = isLandscape ? 'double' : 'single';\n" +
      "\n" +
      "                // Detect iPad\n" +
      "                const isIPad = /iPad|Macintosh/.test(navigator.userAgent) && 'ontouchend' in document;\n" +
      "\n" +
      "                if (displayMode === 'single') {\n" +
      "                    // Single page mode - position on left side with iPad adjustment\n" +
      "                    if (isIPad) {\n" +
      "                        overlay.style.left = '15px';  // Fix for iPad - was -15px, now positive offset\n" +
      "                    } else {\n" +
      "                        overlay.style.left = '0px';\n" +
      "                    }\n" +
      "                    overlay.style.transform = 'translateX(0)';\n" +
      "                } else {\n" +
      "                    // Double page mode - position in center\n" +
      "                    overlay.style.left = '50%';\n" +
      "                    overlay.style.transform = 'translateX(-50%)';\n" +
      "                }\n" +
      "            }\n" +
      "\n" +
      "            function showOverlay(duration) { duration = duration || 3000; const o=document.getElementById('pageScrollOverlay'); if(o){o.style.opacity='1';if(hideTimeout)clearTimeout(hideTimeout);hideTimeout=setTimeout(function(){if(o&&!pageScrollDragging)o.style.opacity='0';},duration);} }\n" +
      "            function showDisplay(duration) { duration = duration || 3000; const d=document.getElementById('pageDisplayCenter'); if(d){d.style.opacity='1';if(activeTimeout)clearTimeout(activeTimeout);activeTimeout=setTimeout(function(){if(d&&!pageScrollDragging)d.style.opacity='0';},duration);} }\n" +
      "            function updatePageDisplay(pageNum) { const d=document.getElementById('pageDisplayCenter'); if(d){d.innerHTML='<span style=\"font-family:monospace;font-style:normal;font-weight:bold;\"></span>' + pageNum + '/' + currentTotalPages; savePage(pageNum); showDisplay();} }\n" +
      "\n" +
      "            function createPageNotches() {\n" +
      "                const track = document.getElementById('pageTrack');\n" +
      "                const container = document.getElementById('pageSliderContainer');\n" +
      "                if (!track || !container) return;\n" +
      "                track.innerHTML = '';\n" +
      "                const notchCount = Math.min(currentTotalPages, 51);\n" +
      "                const containerHeight = container.offsetHeight;\n" +
      "                const notchSpacing = containerHeight / (notchCount - 1);\n" +
      "                const centerX = container.offsetWidth / 2;\n" +
      "                const centerY = containerHeight / 2;\n" +
      "                const centerIndex = Math.floor(notchCount / 2);\n" +
      "                for (let i = 0; i < notchCount; i++) {\n" +
      "                    const notch = document.createElement('div');\n" +
      "                    notch.style.position = 'absolute';\n" +
      "                    notch.style.borderRadius = '1px';\n" +
      "                    notch.style.pointerEvents = 'none';\n" +
      "                    const yPos = i * notchSpacing;\n" +
      "                    const offsetFromCenter = i - centerIndex;\n" +
      "                    if (offsetFromCenter === 0) {\n" +
      "                        notch.style.width = '22px';\n" +
      "                        notch.style.height = '3px';\n" +
      "                        notch.style.left = (centerX - 11) + 'px';\n" +
      "                        notch.style.backgroundColor = 'rgba(255,215,0,0.9)';\n" +
      "                        notch.style.boxShadow = '0 0 4px rgba(255,215,0,0.5)';\n" +
      "                    } else if (Math.abs(offsetFromCenter) % 5 === 0) {\n" +
      "                        notch.style.width = '18px';\n" +
      "                        notch.style.height = '2px';\n" +
      "                        notch.style.left = (centerX - 9) + 'px';\n" +
      "                        notch.style.backgroundColor = 'rgba(255,215,150,0.8)';\n" +
      "                    } else {\n" +
      "                        notch.style.width = '10px';\n" +
      "                        notch.style.height = '1.5px';\n" +
      "                        notch.style.left = (centerX - 5) + 'px';\n" +
      "                        notch.style.backgroundColor = 'rgba(255,235,200,0.6)';\n" +
      "                    }\n" +
      "                    notch.style.top = yPos + 'px';\n" +
      "                    track.appendChild(notch);\n" +
      "                }\n" +
      "                track.style.height = containerHeight + 'px';\n" +
      "            }\n" +
      "\n" +
      "            function setupPageScrolling() {\n" +
      "                const container = document.getElementById('pageSliderContainer');\n" +
      "                const track = document.getElementById('pageTrack');\n" +
      "                const overlay = document.getElementById('pageScrollOverlay');\n" +
      "                if (!container || !track) return;\n" +
      "                function getPageFromScroll(scrollY) { const containerHeight=container.offsetHeight,centerY=containerHeight/2,progress=(-scrollY+centerY)/containerHeight,clamped=Math.max(0,Math.min(1,progress)); return Math.floor(clamped*(currentTotalPages-1))+1; }\n" +
      "                function updatePageFromScroll(scrollY) { if(!pageScrollDragging)return; const pageNum=getPageFromScroll(scrollY); updatePageDisplay(pageNum); const $magazine=$('#magazine'); if($magazine&&$magazine.turn)$magazine.turn('page',pageNum); }\n" +
      "                function setTrackPosition(pageNum) { if(!track||!container)return; const progress=(pageNum-1)/(currentTotalPages-1),containerHeight=container.offsetHeight,centerY=containerHeight/2,scrollY=-(progress*containerHeight)+centerY; track.style.transform='translateY('+scrollY+'px)'; }\n" +
      "                function startDrag(){ pageScrollDragging=true; showOverlay(2000); container.style.cursor='grabbing'; if(hideTimeout)clearTimeout(hideTimeout); if(activeTimeout)clearTimeout(activeTimeout); }\n" +
      "                function endDrag(){ pageScrollDragging=false; container.style.cursor='grab'; const scroll=parseFloat((track.style.transform||'').match(/translateY\\(([^)]+)/)?.[1]||0),pageNum=getPageFromScroll(scroll); setTrackPosition(pageNum); updatePageDisplay(pageNum); if(hideTimeout)clearTimeout(hideTimeout); hideTimeout=setTimeout(function(){ const o=document.getElementById('pageScrollOverlay'); if(o&&!pageScrollDragging)o.style.opacity='0'; },2000); if(activeTimeout)clearTimeout(activeTimeout); activeTimeout=setTimeout(function(){ const d=document.getElementById('pageDisplayCenter'); if(d&&!pageScrollDragging)d.style.opacity='0'; },2000); }\n" +
      "                container.addEventListener('mousedown',function(e){ e.preventDefault(); startDrag(); pageTrackStartY=e.clientY; const transform=track.style.transform; pageTrackStartScroll=transform&&transform.includes('translateY')?parseFloat(transform.match(/translateY\\(([^)]+)/)[1]):0; updatePageDisplay(getPageFromScroll(pageTrackStartScroll)); });\n" +
      "                document.addEventListener('mousemove',function(e){ if(!pageScrollDragging)return; e.preventDefault(); const delta=e.clientY-pageTrackStartY,newScroll=pageTrackStartScroll+delta; track.style.transform='translateY('+newScroll+'px)'; updatePageFromScroll(newScroll); });\n" +
      "                document.addEventListener('mouseup',function(){ if(pageScrollDragging)endDrag(); });\n" +
      "                container.addEventListener('touchstart',function(e){ e.preventDefault(); startDrag(); pageTrackStartY=e.touches[0].clientY; const transform=track.style.transform; pageTrackStartScroll=transform&&transform.includes('translateY')?parseFloat(transform.match(/translateY\\(([^)]+)/)[1]):0; updatePageDisplay(getPageFromScroll(pageTrackStartScroll)); },{passive:false});\n" +
      "                container.addEventListener('touchmove',function(e){ if(!pageScrollDragging)return; e.preventDefault(); const delta=e.touches[0].clientY-pageTrackStartY,newScroll=pageTrackStartScroll+delta; track.style.transform='translateY('+newScroll+'px)'; updatePageFromScroll(newScroll); },{passive:false});\n" +
      "                container.addEventListener('touchend',function(e){ if(pageScrollDragging)endDrag(); e.preventDefault(); });\n" +
      "                const $magazine=$('#magazine'); if($magazine&&$magazine.turn){ $magazine.bind('turned',function(e,page){ if(!pageScrollDragging){ setTrackPosition(page); updatePageDisplay(page); } }); }\n" +
      "                const savedPage=getSavedPage();\n" +
      "                setTimeout(function(){ createPageNotches(); setTrackPosition(savedPage); updatePageDisplay(savedPage); if(overlay)overlay.style.opacity='1'; showOverlay(3000); showDisplay(3000); },100);\n" +
      "                setTimeout(function(){ const $magazine=$('#magazine'); if($magazine&&$magazine.turn)$magazine.turn('page',savedPage); },300);\n" +
      "            }\n" +
      "\n" +
      "            function init(){\n" +
      "                createScrollOverlay();\n" +
      "                let attempts=0;\n" +
      "                const interval=setInterval(function(){ attempts++; const $magazine=$('#magazine'); if(($magazine&&$magazine.turn&&typeof $magazine.turn('page')!=='undefined')||attempts>40){ clearInterval(interval); setTimeout(setupPageScrolling,200); } },100);\n" +
      "            }\n" +
      "            if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init); else init();\n" +
      "        })();\n" +
      "    </script>\n" +
      "    <script>\n" +
      "        (function fixiOSHeight() {\n" +
      "            if(/iPad|iPhone|iPod/.test(navigator.userAgent)||(navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1)){\n" +
      "                function adjustHeight(){ const vh=window.visualViewport?window.visualViewport.height:window.innerHeight; const magazine=document.getElementById('magazine'); if(magazine){ magazine.style.height=vh+'px'; magazine.style.top='0'; magazine.style.position='absolute'; } document.body.style.margin='0'; document.body.style.padding='0'; document.body.style.top='0'; document.body.style.position='fixed'; document.documentElement.style.margin='0'; document.documentElement.style.padding='0'; document.documentElement.style.top='0'; const slider=document.getElementById('pageSliderContainer'),ribbon=document.querySelector('.vertical-ribbon-base'),overlay=document.getElementById('pageScrollOverlay'); if(slider){ slider.style.height=(vh*0.85)+'px'; slider.style.maxHeight=(vh*0.85)+'px'; slider.style.top='auto'; slider.style.bottom='auto'; } if(ribbon){ ribbon.style.height=(vh*0.85)+'px'; ribbon.style.maxHeight=(vh*0.85)+'px'; } if(overlay){ overlay.style.top='0'; overlay.style.bottom='0'; } setTimeout(function(){ if(typeof createPageNotches==='function')createPageNotches(); if(typeof setTrackPosition==='function'&&window.currentPageNumber)setTrackPosition(window.currentPageNumber); },50); }\n" +
      "                adjustHeight(); window.visualViewport?.addEventListener('resize',adjustHeight); window.addEventListener('resize',adjustHeight); window.addEventListener('orientationchange',function(){ setTimeout(adjustHeight,50); }); setTimeout(adjustHeight,100);\n" +
      "            }\n" +
      "        })();\n" +
      "    </script>\n" +
      "    <script>\n" +
      "        (function(){\n" +
      "            let wheelTimeout=null,lastScrollTime=0,isScrolling=false; const scrollThrottle=80;\n" +
      "            function getPageFromScroll(scrollY){ const container=document.getElementById('pageSliderContainer'); if(!container)return 1; const containerHeight=container.offsetHeight,centerY=containerHeight/2,progress=(-scrollY+centerY)/containerHeight,clamped=Math.max(0,Math.min(1,progress)); return Math.floor(clamped*(" +
      pageData.size +
      "-1))+1; }\n" +
      "            function setTrackPosition(pageNum){ const track=document.getElementById('pageTrack'),container=document.getElementById('pageSliderContainer'); if(!track||!container)return; const progress=(pageNum-1)/(" +
      pageData.size +
      "-1),containerHeight=container.offsetHeight,centerY=containerHeight/2,scrollY=-(progress*containerHeight)+centerY; track.style.transform='translateY('+scrollY+'px)'; }\n" +
      "            function updatePageDisplayWithoutSave(pageNum){ const display=document.getElementById('pageDisplayCenter'); if(display){ display.innerHTML='<span style=\"font-family:monospace;font-style:normal;font-weight:bold;\"></span>' + pageNum + '/' + " +
      pageData.size +
      "; } }\n" +
      "            function savePageAndUpdateDisplay(pageNum){ const display=document.getElementById('pageDisplayCenter'); if(display){ display.innerHTML='<span style=\"font-family:monospace;font-style:normal;font-weight:bold;\"></span>' + pageNum + '/' + " +
      pageData.size +
      "; localStorage.setItem('flipbook_last_page_'+title,pageNum); } }\n" +
      "            function handleWheel(e){ if(window.pageScrollDragging)return; const container=document.getElementById('pageSliderContainer'),track=document.getElementById('pageTrack'); if(!container||!track)return; const now=Date.now(); if(now-lastScrollTime<scrollThrottle)return; lastScrollTime=now; e.preventDefault(); const overlay=document.getElementById('pageScrollOverlay'),display=document.getElementById('pageDisplayCenter'); if(overlay)overlay.style.opacity='1'; if(display)display.style.opacity='1'; if(window.wheelHideTimeout)clearTimeout(window.wheelHideTimeout); if(window.wheelDisplayTimeout)clearTimeout(window.wheelDisplayTimeout); window.wheelHideTimeout=setTimeout(function(){ if(overlay&&!window.pageScrollDragging&&!isScrolling)overlay.style.opacity='0'; },1500); window.wheelDisplayTimeout=setTimeout(function(){ if(display&&!window.pageScrollDragging&&!isScrolling)display.style.opacity='0'; },1500); const currentScroll=parseFloat((track.style.transform||'').match(/translateY\\(([^)]+)/)?.[1]||0),sensitivity=1.5,delta=e.deltaY*sensitivity; let newScroll=currentScroll+delta; const containerHeight=container.offsetHeight,centerY=containerHeight/2,minScroll=-centerY,maxScroll=containerHeight-centerY; newScroll=Math.max(minScroll,Math.min(maxScroll,newScroll)); track.style.transform='translateY('+newScroll+'px)'; const pageNum=getPageFromScroll(newScroll); updatePageDisplayWithoutSave(pageNum); const $magazine=$('#magazine'); if($magazine&&$magazine.turn)$magazine.turn('page',pageNum); if(wheelTimeout)clearTimeout(wheelTimeout); wheelTimeout=setTimeout(function(){ isScrolling=true; const finalScroll=parseFloat((track.style.transform||'').match(/translateY\\(([^)]+)/)?.[1]||0),finalPage=getPageFromScroll(finalScroll); setTrackPosition(finalPage); savePageAndUpdateDisplay(finalPage); const $magazine=$('#magazine'); if($magazine&&$magazine.turn)$magazine.turn('page',finalPage); setTimeout(function(){ isScrolling=false; },200); },100); }\n" +
      "            function initWheelScrolling(){ window.currentTotalPages=" +
      pageData.size +
      "; window.pageScrollDragging=false; window.addEventListener('wheel',handleWheel,{passive:false}); }\n" +
      "            if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',initWheelScrolling); else initWheelScrolling();\n" +
      "        })();\n" +
      "    </script>\n" +
      "</body>\n" +
      "\n" +
      "</html>";

    const blob = new Blob([html], { type: "text/html" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = title + "_flipbook.html";
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);

    updateStatus(
      "✅ Generated HTML: " +
        title +
        "_flipbook.html (references external PNG files)"
    );

    if (typeof GM_notification !== "undefined") {
      GM_notification({
        title: "Magazine Scraper",
        text:
          "HTML generated! Place it in the same folder as your " +
          title +
          "_page_*.png files",
        timeout: 8000,
      });
    }
  }

  async function captureCanvasDirect(canvas, pageNum) {
    try {
      const quality = document.getElementById("image-quality")?.value || "1.0"; // Changed default to 1.0
      const webOptimized =
        document.getElementById("web-optimized")?.checked || false;

      let sourceCanvas = canvas;

      // Optional: Scale UP by 2x for higher quality
      if (webOptimized && canvas.width > 0) {
        const scale = 2; // Double the size
        const offscreen = document.createElement("canvas");
        offscreen.width = canvas.width * scale;
        offscreen.height = canvas.height * scale;

        const ctx = offscreen.getContext("2d");
        ctx.imageSmoothingEnabled = true;
        ctx.imageSmoothingQuality = "high";
        ctx.drawImage(canvas, 0, 0, offscreen.width, offscreen.height);

        sourceCanvas = offscreen;
        console.log(
          `Page ${pageNum}: Scaled UP 2x from ${canvas.width}x${canvas.height} to ${offscreen.width}x${offscreen.height}`
        );
      }

      // Save as JPEG with MAXIMUM compression quality (1.0 = 100%)
      const dataURL = sourceCanvas.toDataURL("image/jpeg", 1.0); // Force 1.0 quality here

      if (dataURL && dataURL !== "data:," && dataURL.length > 5000) {
        const sizeKB = Math.round(dataURL.length / 1024);
        const sizeMB = (dataURL.length / (1024 * 1024)).toFixed(2);
        console.log(
          `Page ${pageNum}: ${sizeKB}KB (${sizeMB}MB) - Captured at 1.0 quality`
        );
        return dataURL;
      }
      return null;
    } catch (e) {
      updateStatus("❌ Page " + pageNum + ": Capture error - " + e.message);
      return null;
    }
  }

  function saveImageAsPNG(imageData, pageNum, title) {
    return new Promise(async (resolve) => {
      // Use .png extension for JPEG images (mime JPEG, filename .png - this is good as it is!)
      const quality = document.getElementById("image-quality")?.value || "1.0"; // Changed default to 1.0
      // Remove apostrophes from title for filename
      let safeTitle = title.replace(/'/g, "");
      const filename = `${safeTitle}_page_${pageNum}.png`;

      console.log(`Page ${pageNum}: Saving with quality ${quality}`);

      // Convert dataURL to blob - DON'T re-encode, use the imageData directly
      let blob;

      // Check if imageData is already a JPEG dataURL
      if (imageData.startsWith("data:image/jpeg")) {
        // Just convert the existing JPEG dataURL to blob without re-encoding
        const response = await fetch(imageData);
        blob = await response.blob();
        console.log(
          `Page ${pageNum}: Using captured PNG directly - ${Math.round(
            blob.size / 1024
          )}KB`
        );
      } else {
        // Only re-encode if it's not JPEG (shouldn't happen now)
        const img = new Image();
        img.src = imageData;
        await new Promise((resolve) => {
          img.onload = resolve;
        });

        const canvas = document.createElement("canvas");
        canvas.width = img.width;
        canvas.height = img.height;
        const ctx = canvas.getContext("2d");
        ctx.drawImage(img, 0, 0);

        blob = await new Promise((resolve) => {
          //this is important. mime is jpeg but filename is 'filename.png' (im using png for a good reason)
          canvas.toBlob(resolve, "image/jpeg", parseFloat(quality));
        });
        console.log(
          `Page ${pageNum}: Re-encoded PNG - ${Math.round(blob.size / 1024)}KB`
        );
      }

      if (typeof GM_download !== "undefined") {
        const blobUrl = URL.createObjectURL(blob);
        GM_download({
          url: blobUrl,
          name: filename,
          saveAs: false,
          onload: () => {
            URL.revokeObjectURL(blobUrl);
            updateStatus(
              `💾 Saved: ${filename} (${Math.round(blob.size / 1024)}KB)`
            );
            resolve(true);
          },
          onerror: (err) => {
            URL.revokeObjectURL(blobUrl);
            fallbackDownload(blob, filename, resolve);
          },
        });
      } else {
        fallbackDownload(blob, filename, resolve);
      }

      function fallbackDownload(blob, filename, resolve) {
        try {
          const url = URL.createObjectURL(blob);
          const link = document.createElement("a");
          link.href = url;
          link.download = filename;
          document.body.appendChild(link);
          link.click();
          setTimeout(() => {
            document.body.removeChild(link);
            URL.revokeObjectURL(url);
          }, 100);
          updateStatus(`💾 Saved: ${filename}`);
          resolve(true);
        } catch (e) {
          console.error("Fallback download failed:", e);
          resolve(false);
        }
      }
    });
  }

  async function scrollToPageAndCapture(pageNum, delay, forceCapture = false) {
    const pageElement = document.querySelector(
      '.page[data-page-number="' + pageNum + '"]'
    );

    if (!pageElement) {
      updateStatus("⚠️ Page " + pageNum + ": Element not found");
      return null;
    }

    pageElement.scrollIntoView({ behavior: "smooth", block: "start" });
    await wait(1500);

    let waitCycles = 0;
    const maxCycles = Math.ceil(delay / 500);

    while (waitCycles < maxCycles) {
      let loadingDetected = false;

      const loadingSelectors = [
        ".loading-icon",
        ".loading-spinner",
        '[class*="loading"]',
        ".spinner",
        ".loader",
        ".waiting",
      ];

      for (const selector of loadingSelectors) {
        const loadingElements = pageElement.querySelectorAll(selector);
        for (const el of loadingElements) {
          const style = window.getComputedStyle(el);
          if (style.display !== "none" && style.visibility !== "hidden") {
            loadingDetected = true;
            break;
          }
        }
        if (loadingDetected) break;
      }

      if (!loadingDetected) break;
      await wait(500);
      waitCycles++;
    }

    const canvas = pageElement.querySelector("canvas");
    if (!canvas) {
      updateStatus("⚠️ Page " + pageNum + ": No canvas found");
      return null;
    }

    await wait(1000);

    if (canvas.width === 0 || canvas.height === 0) {
      updateStatus("⚠️ Page " + pageNum + ": Canvas has zero dimensions");
      await wait(2000);
    }

    const imageData = await captureCanvasDirect(canvas, pageNum);

    if (!imageData) {
      return null;
    }

    if (!forceCapture) {
      const isBlank = await isImageBlackOrBlank(imageData);
      if (isBlank) {
        updateStatus(
          "⚠️ Page " +
            pageNum +
            ": Detected black/blank screen - marking as failed"
        );
        return null;
      }
    }

    return imageData;
  }

  async function captureSinglePage(
    pageNum,
    baseDelay,
    retryAttempt = 1,
    maxRetries = 3
  ) {
    const forceCapture = false;

    try {
      updateStatus(
        "📄 Processing page " +
          pageNum +
          " (Attempt " +
          retryAttempt +
          "/" +
          maxRetries +
          ")..."
      );

      const delay = baseDelay + (retryAttempt - 1) * 2000;
      const imageData = await scrollToPageAndCapture(
        pageNum,
        delay,
        forceCapture
      );

      if (imageData && imageData.length > 10000) {
        updateStatus(
          "✅ Page " +
            pageNum +
            ": Captured successfully (" +
            Math.round(imageData.length / 1024) +
            "KB)"
        );
        return imageData;
      } else if (imageData && imageData.length >= 5000) {
        updateStatus(
          "⚠️ Page " +
            pageNum +
            ": Captured with small size (" +
            Math.round(imageData.length / 1024) +
            "KB), but accepting"
        );
        return imageData;
      }

      if (retryAttempt < maxRetries) {
        updateStatus(
          "⚠️ Page " +
            pageNum +
            ": Capture failed, retrying (" +
            retryAttempt +
            "/" +
            maxRetries +
            ")..."
        );
        await wait(3000);
        return await captureSinglePage(
          pageNum,
          baseDelay,
          retryAttempt + 1,
          maxRetries
        );
      }

      updateStatus(
        "❌ Page " + pageNum + ": Failed after " + maxRetries + " attempts"
      );
      return null;
    } catch (e) {
      updateStatus("❌ Page " + pageNum + ": Error - " + e.message);

      if (retryAttempt < maxRetries) {
        updateStatus("⚠️ Page " + pageNum + ": Retrying after error...");
        await wait(3000);
        return await captureSinglePage(
          pageNum,
          baseDelay,
          retryAttempt + 1,
          maxRetries
        );
      }
      return null;
    }
  }

  async function processPagesSequentially(
    startPage,
    endPage,
    baseDelay,
    maxRetries
  ) {
    let captured = 0;
    let failed = [];
    const saveImmediately =
      document.getElementById("save-images")?.checked || false;
    const title = getCustomTitle();

    for (let page = startPage; page <= endPage && isScraping; page++) {
      if (!isScraping) break;

      currentPageBeingProcessed = page;

      let pageDelay = baseDelay;
      if (page > 50) pageDelay += 2000;
      if (page > 80) pageDelay += 2000;
      if (page > 100) pageDelay += 2000;

      const progress =
        ((page - startPage + 1) / (endPage - startPage + 1)) * 100;
      updateProgress(progress);

      const imageData = await captureSinglePage(page, pageDelay, 1, maxRetries);

      if (imageData) {
        captured++;

        if (saveImmediately) {
          await saveImageAsPNG(imageData, page, title);
          pageData.set(page, true);
          addThumbnail(imageData, page);
        } else {
          pageData.set(page, imageData);
          addThumbnail(imageData, page);
        }

        updateStatus(
          "✅ Captured page " +
            page +
            " (" +
            captured +
            "/" +
            (endPage - startPage + 1) +
            ")"
        );
      } else {
        failed.push(page);
        updateStatus(
          "❌ Failed to capture page " + page + " (black screen or blank)"
        );
      }

      if (page < endPage && isScraping) {
        await wait(800);
      }
    }

    return { captured, failed };
  }

  async function retryFailedPages(failedPages, baseDelay, maxRetries) {
    if (failedPages.length === 0) {
      updateStatus("✅ No failed pages to retry!");
      return [];
    }

    updateStatus(
      "🔄 Auto-retrying " +
        failedPages.length +
        " failed pages with " +
        maxRetries +
        " attempts each..."
    );
    let stillFailed = [];

    for (const page of failedPages) {
      if (!isScraping) break;

      updateStatus("📄 Auto-retrying page " + page + "...");
      const imageData = await captureSinglePage(
        page,
        baseDelay + 4000,
        1,
        maxRetries
      );

      if (imageData) {
        const sortedPages = Array.from(pageData.keys()).sort((a, b) => a - b);
        let insertIndex = sortedPages.findIndex((p) => p > page);
        if (insertIndex === -1) insertIndex = pageData.size;

        pageData.set(page, imageData);
        addThumbnail(imageData, page);
        updateStatus("✅ Auto-retried page " + page + " - SUCCESS!");
      } else {
        stillFailed.push(page);
        updateStatus(
          "❌ Auto-retried page " + page + " - STILL FAILED (black screen)"
        );
      }

      await wait(1000);
    }

    return stillFailed;
  }

  async function startScraping() {
    if (isScraping) {
      updateStatus("Already scraping!");
      return;
    }

    const startPage = parseInt(document.getElementById("start-page").value);
    let endPage = parseInt(document.getElementById("end-page").value);
    const pageDelay = parseInt(document.getElementById("page-delay").value);
    const maxRetries = parseInt(document.getElementById("retry-count").value);
    const autoSave = document.getElementById("auto-save")?.checked || false;
    const saveImages = document.getElementById("save-images")?.checked || false;
    const title = getCustomTitle();

    if (startPage > endPage) {
      alert("Start page must be less than or equal to end page");
      return;
    }

    const detectedPages = getTotalPagesFromViewer();
    if (detectedPages > 0 && detectedPages !== endPage) {
      updateStatus(
        "📊 Updating end page from " + endPage + " to " + detectedPages
      );
      endPage = detectedPages;
      const endInput = document.getElementById("end-page");
      if (endInput) endInput.value = detectedPages;
    }

    const allPages = document.querySelectorAll(".page");
    if (allPages.length === 0 && detectedPages === 0) {
      alert("No pages found! Make sure the PDF viewer is loaded.");
      return;
    }

    pageData.clear();
    failedPagesList = [];
    autoSaveCompleted = false;
    isScraping = true;
    scrapeCompleted = false;

    const startBtn = document.getElementById("start-scrape");
    const stopBtn = document.getElementById("stop-scrape");
    const progressDiv = document.getElementById("scraper-progress");
    const thumbDiv = document.getElementById("thumbnails");
    const failedSection = document.getElementById("failed-section");

    if (failedSection) failedSection.style.display = "none";
    if (startBtn) startBtn.style.display = "none";
    if (stopBtn) stopBtn.style.display = "inline-block";
    if (progressDiv) progressDiv.style.display = "block";
    if (thumbDiv) thumbDiv.innerHTML = "";

    updateStatus("🚀 Starting capture: pages " + startPage + " to " + endPage);
    updateStatus(
      "⏱️ Base delay: " + pageDelay + "ms, Max retries: " + maxRetries
    );
    updateStatus("📝 Using title: " + title);
    updateStatus(
      "🔍 Black screen detection: ENABLED (99% pure black threshold)"
    );

    let { captured, failed } = await processPagesSequentially(
      startPage,
      endPage,
      pageDelay,
      maxRetries
    );

    let stillFailed = [];
    if (failed.length > 0 && isScraping) {
      updateStatus(
        "🔄 Auto-retry phase for " + failed.length + " failed pages..."
      );
      stillFailed = await retryFailedPages(failed, pageDelay, maxRetries);
    }

    if (isScraping) {
      const totalPagesCount = endPage - startPage + 1;
      const successCount = pageData.size;

      updateStatus(
        "✅ Complete! Captured " +
          successCount +
          "/" +
          totalPagesCount +
          " pages"
      );

      if (stillFailed.length > 0) {
        updateStatus(
          "⚠️ Still failed after auto-retry: " + stillFailed.join(", ")
        );
        failedPagesList = stillFailed;
        updateFailedSection();
      } else if (failed.length > 0 && stillFailed.length === 0) {
        updateStatus("✅ All pages captured successfully after auto-retry!");
      }

      if (!saveImages) {
        pageData.clear();
      }

      if (autoSave && pageData.size > 0) {
        generateExternalHTML(title);
        autoSaveCompleted = true;
      }

      if (failedPagesList.length > 0) {
        updateStatus(
          "💡 Manual retry available for " +
            failedPagesList.length +
            " failed pages above"
        );
        if (typeof GM_notification !== "undefined") {
          GM_notification({
            title: "Magazine Scraper",
            text:
              failedPagesList.length +
              " pages failed. Use manual retry buttons above.",
            timeout: 8000,
          });
        }
      }

      scrapeCompleted = true;

      if (autoScrapeEnabled) {
        updateStatus(
          "🤖 Auto-scrape completed! Toggle off auto-scrape if done."
        );
      }
    }

    if (startBtn) startBtn.style.display = "inline-block";
    if (stopBtn) stopBtn.style.display = "none";
    isScraping = false;
    currentPageBeingProcessed = 0;
  }

  function stopScraping() {
    isScraping = false;
    updateStatus("⏹️ Stopping scrape...");
  }

  function wait(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  function updateStatus(text) {
    const statusDiv = document.getElementById("scraper-status");
    if (statusDiv) statusDiv.textContent = text;
    console.log("[Scraper]", text);
  }

  function updateProgress(percent) {
    const progressBar = document.getElementById("progress-bar");
    if (progressBar) progressBar.style.width = percent + "%";
  }

  function initialize() {
    let checkCount = 0;
    const checkInterval = setInterval(() => {
      // Check for error before proceeding
      if (checkForLoadErrorAndReload()) {
        clearInterval(checkInterval);
        return;
      }
      const pages = document.querySelectorAll(".page");
      const canvas = document.querySelector("canvas");
      const detectedPages = getTotalPagesFromViewer();

      if ((pages.length > 0 || detectedPages > 0) && canvas) {
        clearInterval(checkInterval);
        createUI();
        const endInput = document.getElementById("end-page");
        const specificPageInput = document.getElementById("specific-page");
        if (endInput && detectedPages > 0) {
          endInput.value = detectedPages;
          endInput.max = detectedPages;
          if (specificPageInput) specificPageInput.max = detectedPages;
        } else if (endInput && pages.length > 0) {
          endInput.value = pages.length;
          endInput.max = pages.length;
          if (specificPageInput) specificPageInput.max = pages.length;
        }
        updateStatus(
          "✅ Ready! Found " + (detectedPages || pages.length) + " pages"
        );
        updateStatus(
          "💡 Use 'Download Specific Page' to capture individual pages"
        );
      } else if (checkCount > 20) {
        clearInterval(checkInterval);
        createUI();
        const pages = document.querySelectorAll(".page");
        const detectedPages = getTotalPagesFromViewer();
        const total = detectedPages || pages.length;
        const specificPageInput = document.getElementById("specific-page");
        if (total > 0) {
          document.getElementById("end-page").value = total;
          if (specificPageInput) specificPageInput.max = total;
        }
        updateStatus("Manual mode - " + total + " pages detected");
      }
      checkCount++;
    }, 1000);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initialize);
  } else {
    initialize();
  }
})();

// ✅ Memory management - Stores only true in pageData, not massive base64 strings
// ✅ Multiple download fallbacks - GM_download → fetch blob → link click → new window
// ✅ Black screen detection - 99% pure black threshold with content detection
// ✅ Aggressive preloading - Preloads next 5 pages in single mode
// ✅ Orientation handling - Preserves page position when rotating iPad
// ✅ Manual retry system - Individual and batch retry for failed pages
// ✅ Specific page download - Capture any single page on demand
// ✅ HTML generation - Dynamic page creation, no hardcoded divs
// ✅ Thumbnail previews - Visual feedback of captured pages
