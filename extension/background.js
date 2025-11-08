// Background service worker for Save to Clipboard extension
// Handles Native Messaging communication with Swift host

const NATIVE_HOST_NAME = "com.hikuohiku.save_to_clipboard";

// Listen for extension icon click
chrome.action.onClicked.addListener(async (tab) => {
  try {
    // Check if the current tab is a PDF
    const response = await chrome.tabs.sendMessage(tab.id, {
      action: "checkIfPdf",
    });

    if (response && response.isPdf) {
      // Get filename from URL
      const url = tab.url;
      const filename =
        url.substring(url.lastIndexOf("/") + 1).split("?")[0] || "document.pdf";

      console.log(`Copying PDF from: ${url}`);

      // Copy PDF to clipboard
      const result = await copyPdfViaHost(url, filename);

      if (result.success) {
        console.log("PDF successfully copied to clipboard!");
        // Show a badge to indicate success
        chrome.action.setBadgeText({ text: "✓", tabId: tab.id });
        chrome.action.setBadgeBackgroundColor({
          color: "#4CAF50",
          tabId: tab.id,
        });
        setTimeout(() => {
          chrome.action.setBadgeText({ text: "", tabId: tab.id });
        }, 2000);
      }
    } else {
      console.log("Current page is not a PDF");
      // Show a badge to indicate this is not a PDF
      chrome.action.setBadgeText({ text: "!", tabId: tab.id });
      chrome.action.setBadgeBackgroundColor({
        color: "#FF9800",
        tabId: tab.id,
      });
      setTimeout(() => {
        chrome.action.setBadgeText({ text: "", tabId: tab.id });
      }, 2000);
    }
  } catch (error) {
    console.error("Error:", error);
    // Show a badge to indicate error
    chrome.action.setBadgeText({ text: "✗", tabId: tab.id });
    chrome.action.setBadgeBackgroundColor({ color: "#F44336", tabId: tab.id });
    setTimeout(() => {
      chrome.action.setBadgeText({ text: "", tabId: tab.id });
    }, 2000);
  }
});

// Copy PDF using native messaging host
async function copyPdfViaHost(url, filename) {
  return new Promise((resolve, reject) => {
    // Connect to native host
    const port = chrome.runtime.connectNative(NATIVE_HOST_NAME);

    // Listen for response
    port.onMessage.addListener((response) => {
      console.log("Response from native host:", response);
      port.disconnect();

      if (response.success) {
        resolve(response);
      } else {
        reject(new Error(response.error || "Unknown error from native host"));
      }
    });

    // Handle connection errors
    port.onDisconnect.addListener(() => {
      const error = chrome.runtime.lastError;
      if (error) {
        console.error("Native host disconnect error:", error);
        reject(
          new Error(
            `Failed to connect to native host: ${error.message}\n\n` +
              `Make sure the Swift native host is installed. See DESIGN.md for instructions.`,
          ),
        );
      }
    });

    // Send request to native host
    const message = {
      action: "copyPdf",
      url: url,
      filename: filename || "document.pdf",
    };

    console.log("Sending to native host:", message);
    port.postMessage(message);
  });
}
