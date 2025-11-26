//
//  main.js
//  KalvianRootsServer
//

const familyInput = document.getElementById('familyId');
const lookupBtn = document.getElementById('lookupBtn');
const statusEl = document.getElementById('status');
const resultEl = document.getElementById('result');
const citationEl = document.getElementById('citation');
const statusDot = document.getElementById('statusDot');
const cacheListEl = document.getElementById('cacheList');
const refreshCacheBtn = document.getElementById('refreshCache');
const clearCacheBtn = document.getElementById('clearCache');
const modelNameEl = document.getElementById('modelName');

const API_HEADERS = { Authorization: 'Bearer dev', 'Content-Type': 'application/json' };
const namePattern = /(\p{L}+(?:\s+\p{L}+)*)((?:\s*<[^>]+>)?)/gu;

let statusPoller = null;
let currentFamilyId = null;
let namesReady = false;

function updateModelName(model) {
  modelNameEl.textContent = `Model: ${model}`;
}

function setStatusIndicator({ status, ready }) {
  statusDot.classList.remove('processing', 'ready');
  if (status === 'processing') {
    statusDot.classList.add('processing');
    statusEl.textContent = 'Processing family network…';
  } else if (ready) {
    statusDot.classList.add('ready');
    statusEl.textContent = 'Family network ready. Names are clickable.';
  } else {
    statusEl.textContent = 'Enter a Family ID and click "Display Family".';
  }
}

function setNamesEnabled(enabled) {
  namesReady = enabled;
  const names = resultEl.querySelectorAll('.clickable-name');
  names.forEach((node) => {
    node.classList.toggle('disabled', !enabled);
  });
}

function extractBirth(line) {
  const starMatch = line.match(/★\s*([^\s]+)/);
  if (starMatch && starMatch[1]) return starMatch[1];
  const dateMatch = line.match(/\b\d{1,2}\.\d{1,2}\.\d{2,4}\b/);
  if (dateMatch) return dateMatch[0];
  const yearMatch = line.match(/\b\d{4}\b/);
  if (yearMatch) return yearMatch[0];
  return '';
}

function buildFamilyDom(text) {
  const fragment = document.createDocumentFragment();
  const pre = document.createElement('pre');
  pre.className = 'family-text';

  const lines = text.split(/\n/);
  lines.forEach((line, index) => {
    let lastIndex = 0;
    const birthForLine = extractBirth(line);
    for (const match of line.matchAll(namePattern)) {
      if (typeof match.index !== 'number') continue;
      const start = match.index;
      const end = start + match[0].length;
      const rawBefore = line.slice(lastIndex, start);
      if (rawBefore) pre.append(document.createTextNode(rawBefore));

      const span = document.createElement('span');
      span.className = 'clickable-name disabled';
      span.dataset.name = match[1].trim();
      span.dataset.birth = birthForLine;
      span.textContent = match[0];
      pre.append(span);

      lastIndex = end;
    }

    const tail = line.slice(lastIndex);
    if (tail) pre.append(document.createTextNode(tail));
    if (index < lines.length - 1) {
      pre.append(document.createTextNode('\n'));
    }
  });

  fragment.append(pre);
  return fragment;
}

async function fetchModel() {
  try {
    const resp = await fetch('/api/ai/model', { headers: API_HEADERS });
    const payload = await resp.json();
    if (resp.ok && payload.model) {
      updateModelName(payload.model);
    }
  } catch (err) {
    console.error('Model fetch failed', err);
  }
}

async function refreshCacheList() {
  try {
    const resp = await fetch('/api/cache/list', { headers: API_HEADERS });
    const payload = await resp.json();
    if (!resp.ok) throw new Error(payload.error?.message || 'Failed to load cache list');

    const groups = Object.keys(payload);
    if (groups.length === 0) {
      cacheListEl.textContent = 'No cached families yet.';
      return;
    }

    cacheListEl.innerHTML = '';
    groups.sort().forEach((group) => {
      const details = document.createElement('details');
      details.open = true;
      const summary = document.createElement('summary');
      summary.textContent = group.toUpperCase();
      details.append(summary);

      payload[group].forEach((id) => {
        const row = document.createElement('div');
        row.className = 'cache-item';
        const label = document.createElement('span');
        label.textContent = id;
        row.append(label);

        const actions = document.createElement('div');
        actions.className = 'cache-actions';

        const displayBtn = document.createElement('button');
        displayBtn.textContent = 'Display';
        displayBtn.addEventListener('click', () => {
          familyInput.value = id;
          fetchFamily();
        });

        const removeBtn = document.createElement('button');
        removeBtn.textContent = 'Remove from cache';
        removeBtn.style.background = '#b91c1c';
        removeBtn.addEventListener('click', async () => {
          await removeFamily(id);
        });

        actions.append(displayBtn, removeBtn);
        row.append(actions);
        details.append(row);
      });

      cacheListEl.append(details);
    });
  } catch (err) {
    cacheListEl.textContent = err.message;
  }
}

async function removeFamily(id) {
  try {
    await fetch('/api/cache/remove', {
      method: 'POST',
      headers: API_HEADERS,
      body: JSON.stringify({ id }),
    });
    await refreshCacheList();
  } catch (err) {
    console.error('Failed to remove family', err);
  }
}

async function clearAllFamilies() {
  try {
    await fetch('/api/cache/clear-all', { method: 'POST', headers: API_HEADERS });
    await refreshCacheList();
    statusEl.textContent = 'Cache cleared.';
    statusDot.classList.remove('processing', 'ready');
    resultEl.textContent = 'Family text will appear here.';
    citationEl.textContent = 'Citations will appear here.';
    currentFamilyId = null;
    namesReady = false;
  } catch (err) {
    statusEl.textContent = 'Clear cache not permitted from this host.';
  }
}

async function pollStatusUntilReady() {
  if (statusPoller) {
    clearTimeout(statusPoller);
    statusPoller = null;
  }

  const poll = async () => {
    try {
      const resp = await fetch('/api/cache/status', { headers: API_HEADERS });
      const payload = await resp.json();
      if (!resp.ok) throw new Error(payload.error?.message || 'Status check failed');

      setStatusIndicator(payload);
      if (payload.ready) {
        setNamesEnabled(true);
        await refreshCacheList();
        return;
      }
    } catch (err) {
      console.error('Status polling failed', err);
    }

    statusPoller = setTimeout(poll, 800);
  };

  poll();
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
  setNamesEnabled(false);
  namesReady = false;

  try {
    const resp = await fetch(`/api/families/${encodeURIComponent(id)}`, { headers: API_HEADERS });
    const payload = await resp.json();

    if (!resp.ok) {
      const message = payload.error?.message || 'Request failed';
      throw new Error(message);
    }

    currentFamilyId = id;
    statusEl.textContent = `Showing family "${id}"`;
    resultEl.innerHTML = '';
    const dom = buildFamilyDom(payload.text);
    resultEl.append(dom);
    bindNameClicks();
    setStatusIndicator({ status: 'processing', ready: false });
    pollStatusUntilReady();
  } catch (err) {
    statusEl.textContent = err.message;
    resultEl.textContent = '';
  } finally {
    lookupBtn.disabled = false;
  }
}

function bindNameClicks() {
  const nameNodes = resultEl.querySelectorAll('.clickable-name');
  nameNodes.forEach((node) => {
    node.addEventListener('click', () => {
      if (!namesReady) return;
      fetchCitation(node.dataset.name, node.dataset.birth || '');
    });
  });
}

async function fetchCitation(personName, birth) {
  if (!personName) return;
  citationEl.textContent = 'Fetching citation…';

  try {
    const resp = await fetch('/api/citation', {
      method: 'POST',
      headers: API_HEADERS,
      body: JSON.stringify({ name: personName, birth }),
    });
    const payload = await resp.json();

    if (!resp.ok) {
      const message = payload.error?.message || 'Request failed';
      throw new Error(message);
    }

    citationEl.textContent = `Person: ${payload.personName}\nBirth: ${payload.birth || 'unknown'}\nCitation: ${payload.citation}`;
  } catch (err) {
    citationEl.textContent = err.message;
  }
}

function setupClearCacheVisibility() {
  const host = window.location.hostname;
  if (host === '127.0.0.1' || host === 'localhost') {
    clearCacheBtn.style.display = 'inline-flex';
  }
}

lookupBtn.addEventListener('click', fetchFamily);
familyInput.addEventListener('keyup', (event) => {
  if (event.key === 'Enter') fetchFamily();
});
refreshCacheBtn.addEventListener('click', refreshCacheList);
clearCacheBtn.addEventListener('click', clearAllFamilies);

setupClearCacheVisibility();
fetchModel();
refreshCacheList();
