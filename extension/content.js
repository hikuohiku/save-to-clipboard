// Content script for detecting PDF pages and providing additional functionality

// Check if the current page is a PDF
function isPdfPage() {
  // Check if content type is PDF
  const contentType = document.contentType || document.mimeType;
  if (contentType && contentType.includes("application/pdf")) {
    return true;
  }

  // Check URL
  const url = window.location.href;
  if (
    url.toLowerCase().endsWith(".pdf") ||
    url.includes(".pdf?") ||
    url.includes(".pdf#")
  ) {
    return true;
  }

  // Check if the page is embedded PDF viewer
  const pdfEmbed = document.querySelector('embed[type="application/pdf"]');
  const pdfObject = document.querySelector('object[type="application/pdf"]');
  if (pdfEmbed || pdfObject) {
    return true;
  }

  return false;
}

// Listen for messages from background
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === "checkIfPdf") {
    sendResponse({ isPdf: isPdfPage() });
  }
});
