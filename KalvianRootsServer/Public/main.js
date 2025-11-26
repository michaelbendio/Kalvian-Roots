//
//  main.js
//  KalvianRootsServer
//
//  Created by Michael Bendio on 11/24/25.
//

const familyInput = document.getElementById('familyId');
const lookupBtn = document.getElementById('lookupBtn');
const statusEl = document.getElementById('status');
const resultEl = document.getElementById('result');
const citationEl = document.getElementById('citation');

const API_HEADERS = { Authorization: 'Bearer dev' };

function escapeHtml(str) {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function buildClickableFamily(text) {
  const escaped = escapeHtml(text);
  const namePattern = /(\p{L}+(?:\s+\p{L}+)*)((?:\s*\([A-Z0-9]{4}-[A-Z0-9]{3}\))?)/gu;

  return escaped.replace(namePattern, (match) => {
    const trimmed = match.trim();
    if (!trimmed) return match;
    const encodedName = encodeURIComponent(trimmed);
    return `<span class="clickable-name" data-name="${trimmed}" data-encoded-name="${encodedName}">${match}</span>`;
  });
}

function bindNameClicks(familyId) {
  const nameNodes = resultEl.querySelectorAll('.clickable-name');
  nameNodes.forEach((node) => {
    node.addEventListener('click', () => fetchCitation(familyId, node.dataset.name));
  });
}

async function fetchFamily() {
  const id = familyInput.value.trim();
  if (!id) {
    statusEl.textContent = 'Please enter a Family ID.';
    return;
  }

  lookupBtn.disabled = true;
  statusEl.textContent = 'Searching…';
  resultEl.textContent = '';
  citationEl.textContent = '';

  try {
    const resp = await fetch(`/api/families/${encodeURIComponent(id)}`, {
      headers: API_HEADERS,
    });
    const payload = await resp.json();

    if (!resp.ok) {
      const message = payload.error?.message || 'Request failed';
      throw new Error(message);
    }

    statusEl.textContent = `Showing family "${id}"`;
    resultEl.innerHTML = buildClickableFamily(payload.text);
    bindNameClicks(id);
  } catch (err) {
    statusEl.textContent = err.message;
    resultEl.textContent = '';
  } finally {
    lookupBtn.disabled = false;
  }
}

async function fetchCitation(familyId, personName) {
  if (!personName) return;
  citationEl.textContent = 'Fetching citation…';

  try {
    const resp = await fetch(
      `/api/citation/${encodeURIComponent(familyId)}/${encodeURIComponent(personName)}`,
      { headers: API_HEADERS }
    );
    const payload = await resp.json();

    if (!resp.ok) {
      const message = payload.error?.message || 'Request failed';
      throw new Error(message);
    }

    citationEl.textContent = `Person: ${payload.person}\nFamily: ${payload.family}\nCitation: ${payload.citation}`;
  } catch (err) {
    citationEl.textContent = err.message;
  }
}

lookupBtn.addEventListener('click', fetchFamily);
familyInput.addEventListener('keyup', (event) => {
  if (event.key === 'Enter') fetchFamily();
});

