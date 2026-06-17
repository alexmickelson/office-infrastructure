/**
 * Dashboard card configuration and click handlers.
 */

const DASHBOARD_LINKS = [
  { label: "AI Agent", url: "https://alexagent.snowse.io" },
  { label: "ArgoCD", url: "https://alexargocd.snowse.io" },
  { label: "Monitoring", url: "https://alexmonitoring.snowse.io" },
  { label: "OpenCost", url: "https://alexopencost.snowse.io" },
  { label: "Discord Admin", url: "https://discordadmin.snowse.io" },
  { label: "Hermes Dashboard", url: "https://alexhermes-dashboard.snowse.io" },
  { label: "Pantheon", url: "https://alexpantheon.snowse.io" },
  {
    label: "Simple Syllabus Check",
    url: "https://simplesyllabuscheck.snowse.io",
  },
  { label: "Vault", url: "https://alexvault.snowse.io" },
  { label: "Dashboard", url: "https://alexdashboard.snowse.io" },
];

function createCard(link) {
  const card = document.createElement("div");
  card.className = "card";
  card.setAttribute("data-url", link.url);
  card.addEventListener("click", () => window.open(link.url, "_blank"));

  const heading = document.createElement("h3");
  heading.textContent = link.label;

  const urlEl = document.createElement("div");
  urlEl.className = "url";
  urlEl.textContent = new URL(link.url).hostname;

  card.appendChild(heading);
  card.appendChild(urlEl);
  return card;
}

function renderCards(filter = "") {
  const grid = document.getElementById("card-grid");
  if (!grid) return;

  grid.innerHTML = "";

  const lowerFilter = filter.toLowerCase();

  for (const link of DASHBOARD_LINKS) {
    const hostname = new URL(link.url).hostname;
    if (
      !link.label.toLowerCase().includes(lowerFilter) &&
      !hostname.includes(lowerFilter)
    ) {
      continue;
    }
    grid.appendChild(createCard(link));
  }
}

function init() {
  const searchInput = document.getElementById("search-input");

  renderCards();

  if (searchInput) {
    searchInput.addEventListener("input", (e) => renderCards(e.target.value));
    searchInput.focus();
  }
}

document.addEventListener("DOMContentLoaded", init);
