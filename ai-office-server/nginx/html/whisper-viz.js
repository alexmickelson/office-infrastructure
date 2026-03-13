const HISTORY_S = 6;
const SAMPLE_RATE = 30;
const MAX_BARS = HISTORY_S * SAMPLE_RATE;

const canvas = document.getElementById("volumeCanvas");
const ctx2d = canvas.getContext("2d");

const volHistory = [];
let analyserNode = null;
let vizRaf = null;

export function startViz(stream) {
  const audioCtx = new AudioContext();
  const source = audioCtx.createMediaStreamSource(stream);
  analyserNode = audioCtx.createAnalyser();
  analyserNode.fftSize = 1024;
  source.connect(analyserNode);
  const buf = new Uint8Array(analyserNode.frequencyBinCount);
  function tick() {
    vizRaf = requestAnimationFrame(tick);
    analyserNode.getByteFrequencyData(buf);
    const rms =
      Math.sqrt(buf.reduce((s, v) => s + v * v, 0) / buf.length) / 255;
    volHistory.push(rms);
    if (volHistory.length > MAX_BARS) volHistory.shift();
    drawViz();
  }
  tick();
}

export function stopViz() {
  if (vizRaf) {
    cancelAnimationFrame(vizRaf);
    vizRaf = null;
  }
  drawViz();
}

export function resetVizHistory() {
  volHistory.length = 0;
}

function drawViz() {
  const W = canvas.offsetWidth * devicePixelRatio;
  const H = canvas.offsetHeight * devicePixelRatio;
  if (canvas.width !== W || canvas.height !== H) {
    canvas.width = W;
    canvas.height = H;
  }
  ctx2d.clearRect(0, 0, W, H);
  const barW = W / MAX_BARS;
  for (let i = 0; i < volHistory.length; i++) {
    const v = volHistory[i];
    ctx2d.fillStyle = `hsl(${120 - v * 120},80%,45%)`;
    ctx2d.fillRect(i * barW, H - v * H, Math.max(1, barW - 1), v * H);
  }
}
drawViz();
