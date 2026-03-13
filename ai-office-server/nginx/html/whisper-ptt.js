import { getSupportedMimeType, sendToWhisper } from "./whisper-service.js";
import {
  getConfirmedText,
  clearTranscript,
  buildPrompt,
  appendText,
} from "./whisper-logic.js";
import { startViz, stopViz, resetVizHistory } from "./whisper-viz.js";

// ── DOM refs ──────────────────────────────────────────────────────────
const pttBtn = document.getElementById("pttBtn");
const clearBtn = document.getElementById("clearBtn");
const transcriptEl = document.getElementById("transcript");
const statusText = document.getElementById("statusText");
const dot = document.getElementById("dot");
const errorBox = document.getElementById("errorBox");
const wordCountEl = document.getElementById("wordCount");
const lastLatencyEl = document.getElementById("lastLatency");
const canvas = document.getElementById("volumeCanvas");

// ── Recorder state ────────────────────────────────────────────────────
let mediaStream = null;
let recorder = null;
let chunks = [];
let isRecording = false;

// ── Status ────────────────────────────────────────────────────────────
function setStatus(msg, state) {
  statusText.textContent = msg;
  dot.className = "dot " + (state || "idle");
}

function showError(msg) {
  errorBox.textContent = msg;
  errorBox.style.display = "block";
  setTimeout(() => {
    errorBox.style.display = "none";
  }, 6000);
}

// ── Transcript ────────────────────────────────────────────────────────
function renderTranscript(pendingText) {
  const confirmed = getConfirmedText();
  transcriptEl.innerHTML = "";
  if (!confirmed && !pendingText) {
    transcriptEl.innerHTML =
      '<span class="pending">Transcript will appear here...</span>';
    return;
  }
  if (confirmed) transcriptEl.appendChild(document.createTextNode(confirmed));
  if (pendingText) {
    const span = document.createElement("span");
    span.className = "pending";
    span.textContent = (confirmed ? " " : "") + pendingText;
    transcriptEl.appendChild(span);
  }
}

function updateMeta() {
  const words = getConfirmedText().trim().split(/\s+/).filter(Boolean).length;
  wordCountEl.textContent = `${words} words`;
}

// ── PTT core ──────────────────────────────────────────────────────────
async function pressStart() {
  if (isRecording || pttBtn.classList.contains("flushing")) return;

  if (!mediaStream) {
    try {
      mediaStream = await navigator.mediaDevices.getUserMedia({
        audio: true,
        video: false,
      });
    } catch (err) {
      showError("Microphone access denied: " + err.message);
      return;
    }
  }

  startViz(mediaStream);
  chunks = [];
  const mimeType = getSupportedMimeType();
  recorder = new MediaRecorder(
    mediaStream,
    mimeType ? { mimeType } : undefined,
  );
  recorder.ondataavailable = (e) => {
    if (e.data && e.data.size > 0) chunks.push(e.data);
  };
  recorder.onstop = async () => {
    const blob = new Blob(chunks, { type: recorder.mimeType || "audio/webm" });
    canvas.classList.remove("visible");
    resetVizHistory();
    stopViz();
    pttBtn.classList.add("flushing");
    pttBtn.querySelector("span").textContent = "Transcribing…";

    const server = document
      .getElementById("serverUrl")
      .value.replace(/\/$/, "");
    const language = document.getElementById("language").value;
    setStatus("Transcribing…", "sending");
    try {
      const { text, latency } = await sendToWhisper(
        server,
        language,
        blob,
        buildPrompt(),
      );
      lastLatencyEl.textContent = `last: ${latency}ms`;
      if (text) appendText(text);
      renderTranscript("");
      updateMeta();
    } catch (err) {
      showError("Error: " + err.message);
    }

    pttBtn.classList.remove("flushing");
    pttBtn.querySelector("span").innerHTML = "Hold to<br>Record";
    setStatus("Ready — hold button or Space to record", "idle");
  };
  recorder.start(100);
  isRecording = true;
  canvas.classList.add("visible");
  pttBtn.classList.add("active");
  pttBtn.querySelector("span").innerHTML = "Recording…<br>Release to send";
  setStatus("Recording…", "recording");
}

function pressEnd() {
  if (!isRecording) return;
  isRecording = false;
  pttBtn.classList.remove("active");
  if (recorder && recorder.state === "recording") recorder.stop();
}

// ── Event listeners ───────────────────────────────────────────────────
pttBtn.addEventListener("mousedown", (e) => {
  e.preventDefault();
  pressStart();
});
window.addEventListener("mouseup", () => pressEnd());

pttBtn.addEventListener(
  "touchstart",
  (e) => {
    e.preventDefault();
    pressStart();
  },
  { passive: false },
);
window.addEventListener("touchend", () => pressEnd());
window.addEventListener("touchcancel", () => pressEnd());

window.addEventListener("keydown", (e) => {
  if (e.code === "Space" && !e.repeat) {
    e.preventDefault();
    pressStart();
  }
});
window.addEventListener("keyup", (e) => {
  if (e.code === "Space") pressEnd();
});

clearBtn.addEventListener("click", () => {
  clearTranscript();
  renderTranscript("");
  updateMeta();
  lastLatencyEl.textContent = "";
});
