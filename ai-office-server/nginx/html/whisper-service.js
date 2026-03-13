export function getSupportedMimeType() {
  return (
    [
      "audio/webm;codecs=opus",
      "audio/webm",
      "audio/ogg;codecs=opus",
      "audio/ogg",
    ].find((t) => MediaRecorder.isTypeSupported(t)) || ""
  );
}

/**
 * @param {string} serverUrl
 * @param {string} language
 * @param {Blob} blob
 * @param {string} prompt
 * @returns {Promise<{text: string, latency: number}>}
 */
export async function sendToWhisper(serverUrl, language, blob, prompt) {
  const t0 = Date.now();
  const formData = new FormData();
  formData.append("file", blob, "audio.webm");
  formData.append("response_format", "json");
  formData.append("language", language === "auto" ? "" : language);
  if (prompt) formData.append("prompt", prompt);

  const res = await fetch(`${serverUrl}/inference`, {
    method: "POST",
    body: formData,
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${await res.text()}`);
  const data = await res.json();
  return { text: (data.text || "").trim(), latency: Date.now() - t0 };
}
