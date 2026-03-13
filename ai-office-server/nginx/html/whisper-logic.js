const PROMPT_WORDS = 20;

let confirmedText = "";

export function getConfirmedText() {
  return confirmedText;
}

export function clearTranscript() {
  confirmedText = "";
}

export function buildPrompt() {
  return confirmedText
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .slice(-PROMPT_WORDS)
    .join(" ");
}

/**
 * Deduplicate leading words between confirmed text and newly transcribed text,
 * then append the result. Returns the deduplicated new text (empty if nothing
 * useful was added).
 * @param {string} newText
 * @returns {string} the text that was actually appended
 */
export function appendText(newText) {
  newText = deduplicateLeading(newText.trim());
  if (!newText) return "";
  confirmedText = confirmedText ? confirmedText + " " + newText : newText;
  return newText;
}

function deduplicateLeading(newText) {
  if (!confirmedText || !newText) return newText;
  const prevWords = confirmedText.trim().split(/\s+/).filter(Boolean);
  const newWords = newText.split(/\s+/).filter(Boolean);
  for (
    let overlap = Math.min(8, prevWords.length, newWords.length);
    overlap >= 2;
    overlap--
  ) {
    if (
      prevWords.slice(-overlap).join(" ").toLowerCase() ===
      newWords.slice(0, overlap).join(" ").toLowerCase()
    ) {
      return newWords.slice(overlap).join(" ");
    }
  }
  return newText;
}
