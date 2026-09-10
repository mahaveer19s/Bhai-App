// BHAI Central Command — Operations Radar JavaScript
let map = null;
let markers = {}; // id -> Leaflet marker
let activeEmergencies = [];
let activeLiveLocations = [];
let currentFilter = 'EMERGENCIES'; // 'EMERGENCIES' or 'LIVE_STREAMS'
let currentSelectedIncident = null;
let ws = null;
let wsReconnectTimer = null;

// DOM Elements
const loginModal = document.getElementById('login-modal');
const adminApp = document.getElementById('admin-app');
const loginForm = document.getElementById('login-form');
const loginError = document.getElementById('login-error');
const wsStatusText = document.getElementById('ws-status-text');
const wsStatusDot = document.querySelector('.status-dot');
const detailModal = document.getElementById('detail-modal');

// --- Authentication ---
function getAdminToken() {
    return sessionStorage.getItem('bhai_admin_token');
}

function setAdminToken(token) {
    sessionStorage.setItem('bhai_admin_token', token);
}

function clearAdminToken() {
    sessionStorage.removeItem('bhai_admin_token');
}

async function handleLogin(e) {
    e.preventDefault();
    loginError.style.display = 'none';
    const username = document.getElementById('admin-username').value.trim();
    const password = document.getElementById('admin-password').value;

    try {
        const res = await fetch('/api/admin/login', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username, password })
        });
        const data = await res.json();
        if (!res.ok) {
            loginError.textContent = data.detail || 'Invalid administrator credentials.';
            loginError.style.display = 'block';
            return;
        }

        setAdminToken(data.access_token);
        loginModal.style.display = 'none';
        adminApp.style.display = 'flex';
        initDashboard();
    } catch (err) {
        loginError.textContent = 'Server connection error. Please try again.';
        loginError.style.display = 'block';
    }
}

document.getElementById('btn-logout').addEventListener('click', () => {
    clearAdminToken();
    if (ws) ws.close();
    window.location.reload();
});

// --- Toast Notifications ---
function showToast(message) {
    const container = document.getElementById('toast-container');
    const toast = document.createElement('div');
    toast.className = 'toast';
    toast.textContent = message;
    container.appendChild(toast);
    setTimeout(() => {
        toast.remove();
    }, 4000);
}

// --- Navigation & Location Sharing ---
function openGoogleMapsNavigation(lat, lon) {
    const url = `https://www.google.com/maps/dir/?api=1&destination=${lat},${lon}`;
    window.open(url, '_blank');
    showToast(`Opening turn-by-turn navigation for ${lat.toFixed(5)}, ${lon.toFixed(5)}`);
}

function shareLocationDetails(title, lat, lon, accuracy) {
    const navUrl = `https://www.google.com/maps/dir/?api=1&destination=${lat},${lon}`;
    const shareText = `🚨 ${title}\nCoordinates: ${lat.toFixed(6)}, ${lon.toFixed(6)} (±${Math.round(accuracy || 10)}m)\nDirections: ${navUrl}`;

    if (navigator.share) {
        navigator.share({
            title: title,
            text: shareText,
            url: navUrl
        }).catch(() => {});
    } else if (navigator.clipboard) {
        navigator.clipboard.writeText(shareText).then(() => {
            showToast('✅ Location link and coordinates copied to clipboard!');
        });
    } else {
        showToast(`Coordinates: ${lat}, ${lon}`);
    }
}

// --- Map Initialization ---
function initMap() {
    if (map) return;
    map = L.map('radar-map').setView([28.6273, 77.3725], 13);
    L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
        attribution: '&copy; <a href="https://carto.com/">CARTO</a> &copy; OpenStreetMap',
        maxZoom: 19
    }).addTo(map);
}

function createIcon(color) {
    return L.divIcon({
        className: 'custom-map-icon',
        html: `<div style="width: 22px; height: 22px; border-radius: 50%; background: ${color}; border: 3px solid #ffffff; box-shadow: 0 0 12px ${color};"></div>`,
        iconSize: [22, 22],
        iconAnchor: [11, 11]
    });
}

function updateMapMarkers() {
    if (!map) return;

    const redIcon = createIcon('#ef4444');
    const cyanIcon = createIcon('#00bcd4');
    const activeIds = new Set();
    const bounds = [];

    // Render Emergencies
    activeEmergencies.forEach(em => {
        const id = 'em-' + em.id;
        activeIds.add(id);
        const lat = em.last_latitude || em.initial_latitude;
        const lon = em.last_longitude || em.initial_longitude;
        if (lat == null || lon == null) return;
        bounds.push([lat, lon]);

        const popupHtml = `
            <div style="font-family: sans-serif; min-width: 200px;">
                <div style="font-weight: 800; color: #ef4444; font-size: 14px; margin-bottom: 4px;">🚨 EMERGENCY ALERT</div>
                <div style="font-size: 12px; color: #64748b; margin-bottom: 8px;">ID: ${em.id.slice(0, 12)}...</div>
                <div style="font-size: 13px; font-weight: bold; margin-bottom: 6px;">Lat: ${lat.toFixed(5)}, Lon: ${lon.toFixed(5)}</div>
                <div style="display: flex; gap: 6px; margin-top: 10px;">
                    <button onclick="openGoogleMapsNavigation(${lat}, ${lon})" style="background: #0284c7; color: #fff; border: none; padding: 6px 10px; border-radius: 6px; cursor: pointer; font-size: 11px; font-weight: bold;">🗺️ Navigate</button>
                    <button onclick="shareLocationDetails('BHAI Emergency', ${lat}, ${lon}, ${em.last_accuracy || 10})" style="background: #334155; color: #fff; border: none; padding: 6px 10px; border-radius: 6px; cursor: pointer; font-size: 11px;">📲 Share</button>
                </div>
            </div>
        `;

        if (markers[id]) {
            markers[id].setLatLng([lat, lon]).setPopupContent(popupHtml);
        } else {
            markers[id] = L.marker([lat, lon], { icon: redIcon }).addTo(map).bindPopup(popupHtml);
        }
    });

    // Render Live Location Streams
    activeLiveLocations.forEach(loc => {
        const id = 'loc-' + loc.id;
        activeIds.add(id);
        const lat = loc.last_latitude || loc.initial_latitude;
        const lon = loc.last_longitude || loc.initial_longitude;
        if (lat == null || lon == null) return;
        bounds.push([lat, lon]);

        const popupHtml = `
            <div style="font-family: sans-serif; min-width: 200px;">
                <div style="font-weight: 800; color: #00bcd4; font-size: 14px; margin-bottom: 4px;">📍 LIVE LOCATION (5s)</div>
                <div style="font-size: 12px; color: #64748b; margin-bottom: 8px;">Session: ${loc.id.slice(0, 12)}...</div>
                <div style="font-size: 13px; font-weight: bold; margin-bottom: 6px;">Lat: ${lat.toFixed(5)}, Lon: ${lon.toFixed(5)}</div>
                <div style="display: flex; gap: 6px; margin-top: 10px;">
                    <button onclick="openGoogleMapsNavigation(${lat}, ${lon})" style="background: #0284c7; color: #fff; border: none; padding: 6px 10px; border-radius: 6px; cursor: pointer; font-size: 11px; font-weight: bold;">🗺️ Navigate</button>
                    <button onclick="shareLocationDetails('BHAI Live Stream', ${lat}, ${lon}, ${loc.last_accuracy || 10})" style="background: #334155; color: #fff; border: none; padding: 6px 10px; border-radius: 6px; cursor: pointer; font-size: 11px;">📲 Share</button>
                </div>
            </div>
        `;

        if (markers[id]) {
            markers[id].setLatLng([lat, lon]).setPopupContent(popupHtml);
        } else {
            markers[id] = L.marker([lat, lon], { icon: cyanIcon }).addTo(map).bindPopup(popupHtml);
        }
    });

    // Clean up markers that are no longer active
    for (const id in markers) {
        if (!activeIds.has(id)) {
            map.removeLayer(markers[id]);
            delete markers[id];
        }
    }

    if (bounds.length > 0 && !map._userPanned) {
        try {
            map.fitBounds(bounds, { maxZoom: 15, padding: [40, 40] });
        } catch (_) {}
    }
}

// --- Data Fetching ---
async function fetchAdminData() {
    const token = getAdminToken();
    if (!token) return;

    try {
        const headers = { 'Authorization': `Bearer ${token}` };

        const [dashRes, emRes, locRes] = await Promise.all([
            fetch('/api/admin/dashboard', { headers }),
            fetch('/api/admin/emergencies', { headers }),
            fetch('/api/admin/live-locations', { headers })
        ]);

        if (dashRes.status === 401 || dashRes.status === 403) {
            clearAdminToken();
            window.location.reload();
            return;
        }

        if (dashRes.ok) {
            const dash = await dashRes.json();
            document.getElementById('metric-active-emergencies').textContent = dash.active_emergencies || 0;
            document.getElementById('metric-live-locations').textContent = dash.active_live_locations || 0;
            document.getElementById('metric-resolved').textContent = dash.resolved_emergencies || 0;
            document.getElementById('metric-responders').textContent = dash.helper_acknowledgements || 0;
        }

        if (emRes.ok) {
            activeEmergencies = await emRes.json();
            document.getElementById('count-emergencies').textContent = activeEmergencies.length;
        }

        if (locRes.ok) {
            activeLiveLocations = await locRes.json();
            document.getElementById('count-live-streams').textContent = activeLiveLocations.length;
        }

        renderFeed();
        updateMapMarkers();
    } catch (err) {
        console.error('Fetch error in admin sync:', err);
    }
}

// --- Incident Feed Rendering ---
function renderFeed() {
    const feed = document.getElementById('incident-feed-list');
    feed.innerHTML = '';

    if (currentFilter === 'EMERGENCIES') {
        if (activeEmergencies.length === 0) {
            feed.innerHTML = '<div class="empty-state">No emergency incidents currently active.</div>';
            return;
        }

        activeEmergencies.forEach(em => {
            const card = document.createElement('div');
            const isActive = em.status === 'ACTIVE';
            card.className = `incident-card ${isActive ? 'active-alert' : ''}`;
            const time = new Date(em.triggered_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
            const lat = em.last_latitude || em.initial_latitude || 0;
            const lon = em.last_longitude || em.initial_longitude || 0;

            card.innerHTML = `
                <div class="card-top">
                    <span class="status-pill ${isActive ? 'red' : 'green'}">${em.status}</span>
                    <span class="card-time">${time}</span>
                </div>
                <div class="card-loc">📍 ${lat.toFixed(5)}, ${lon.toFixed(5)}</div>
                <div class="card-meta">
                    <span>Responders: ${em.helper_count || 0}</span>
                    <span>Accuracy: ±${Math.round(em.last_accuracy || 10)}m</span>
                </div>
            `;
            card.addEventListener('click', () => openIncidentModal(em, 'EMERGENCY'));
            feed.appendChild(card);
        });
    } else {
        if (activeLiveLocations.length === 0) {
            feed.innerHTML = '<div class="empty-state">No active 5-second live location streams.</div>';
            return;
        }

        activeLiveLocations.forEach(loc => {
            const card = document.createElement('div');
            card.className = 'incident-card live-stream';
            const time = new Date(loc.last_updated_at || loc.started_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
            const lat = loc.last_latitude || loc.initial_latitude || 0;
            const lon = loc.last_longitude || loc.initial_longitude || 0;

            card.innerHTML = `
                <div class="card-top">
                    <span class="status-pill cyan">STREAM ACTIVE</span>
                    <span class="card-time">${time}</span>
                </div>
                <div class="card-loc">📍 ${lat.toFixed(5)}, ${lon.toFixed(5)}</div>
                <div class="card-meta">
                    <span>User: ${loc.user_id.slice(0, 8)}...</span>
                    <span>Interval: 5s</span>
                </div>
            `;
            card.addEventListener('click', () => openIncidentModal(loc, 'LIVE_LOCATION'));
            feed.appendChild(card);
        });
    }
}

// --- Incident Modal Detail ---
function openIncidentModal(item, type) {
    currentSelectedIncident = { ...item, type };
    const lat = item.last_latitude || item.initial_latitude || 0;
    const lon = item.last_longitude || item.initial_longitude || 0;
    const acc = item.last_accuracy || item.initial_accuracy || 10;
    const when = item.last_updated_at || item.triggered_at || item.started_at;

    document.getElementById('modal-status-badge').textContent = item.status || 'ACTIVE';
    document.getElementById('modal-title').textContent = type === 'EMERGENCY' ? 'Emergency Incident' : 'Live Location Stream';
    document.getElementById('modal-id').textContent = `ID: ${item.id}`;
    document.getElementById('modal-lat').textContent = lat.toFixed(6);
    document.getElementById('modal-lon').textContent = lon.toFixed(6);
    document.getElementById('modal-accuracy').textContent = `±${Math.round(acc)} m`;
    document.getElementById('modal-updated').textContent = new Date(when).toLocaleTimeString();

    const mgmtBar = document.getElementById('modal-mgmt-bar');
    const chatSection = document.getElementById('modal-chat-section');
    mgmtBar.style.display = type === 'EMERGENCY' ? 'flex' : 'none';
    if (chatSection) {
        chatSection.style.display = type === 'EMERGENCY' ? 'block' : 'none';
        if (type === 'EMERGENCY') {
            loadAdminChat(item.id);
        }
    }

    detailModal.style.display = 'flex';
}

// --- Admin Emergency Chat ---
let currentAdminConversationId = null;

async function loadAdminChat(alertId) {
    const token = getAdminToken();
    if (!token) return;
    const msgContainer = document.getElementById('admin-chat-messages');
    msgContainer.innerHTML = '<div style="color: #94a3b8; text-align: center; margin: auto;">Loading encrypted conversation...</div>';

    try {
        const convRes = await fetch('/chat/conversations', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
            body: JSON.stringify({ alert_id: alertId, is_admin_thread: true })
        });
        if (!convRes.ok) throw new Error('Could not initialize chat');
        const conv = await convRes.json();
        currentAdminConversationId = conv.id;

        const msgRes = await fetch(`/chat/conversations/${conv.id}/messages`, {
            headers: { 'Authorization': `Bearer ${token}` }
        });
        const messages = await msgRes.json();
        renderAdminChatMessages(messages);
    } catch (e) {
        msgContainer.innerHTML = '<div style="color: #ef4444; text-align: center; margin: auto;">Chat unavailable.</div>';
    }
}

function renderAdminChatMessages(messages) {
    const msgContainer = document.getElementById('admin-chat-messages');
    msgContainer.innerHTML = '';
    if (!messages || messages.length === 0) {
        msgContainer.innerHTML = '<div style="color: #94a3b8; text-align: center; margin: auto;">No messages in this incident yet. Start communication below.</div>';
        return;
    }

    messages.forEach(m => {
        const el = document.createElement('div');
        const isOperator = m.sender_id === '3960dfc0-a49f-4058-b470-61b9a603cd50' || m.transport === 'INTERNET';
        el.style.cssText = `padding: 6px 10px; border-radius: 8px; max-width: 80%; line-height: 1.4; word-break: break-word; ${
            isOperator ? 'align-self: flex-end; background: #00bcd4; color: #070b14; font-weight: 500;' : 'align-self: flex-start; background: #334155; color: #fff;'
        }`;
        const time = new Date(m.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        el.innerHTML = `<div>${escapeHtml(m.message)}</div><div style="font-size: 9px; opacity: 0.75; text-align: right; margin-top: 2px;">${time} • ${m.transport}</div>`;
        msgContainer.appendChild(el);
    });
    msgContainer.scrollTop = msgContainer.scrollHeight;
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

async function sendAdminMessage() {
    const input = document.getElementById('admin-chat-input');
    const text = input.value.trim();
    if (!text || !currentAdminConversationId) return;

    const token = getAdminToken();
    const clientMsgId = 'adm-' + Date.now();
    input.value = '';

    try {
        const res = await fetch(`/chat/conversations/${currentAdminConversationId}/messages`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
            body: JSON.stringify({ client_message_id: clientMsgId, message: text, transport: 'INTERNET' })
        });
        if (res.ok) {
            const msg = await res.json();
            // Refresh messages
            const msgRes = await fetch(`/chat/conversations/${currentAdminConversationId}/messages`, {
                headers: { 'Authorization': `Bearer ${token}` }
            });
            const messages = await msgRes.json();
            renderAdminChatMessages(messages);
        }
    } catch (e) {
        showToast('Failed to send message.');
    }
}

document.getElementById('admin-chat-send').addEventListener('click', sendAdminMessage);
document.getElementById('admin-chat-input').addEventListener('keydown', (e) => {
    if (e.key === 'Enter') sendAdminMessage();
});


document.getElementById('modal-btn-close').addEventListener('click', () => {
    detailModal.style.display = 'none';
});

document.getElementById('modal-btn-navigate').addEventListener('click', () => {
    if (!currentSelectedIncident) return;
    const lat = currentSelectedIncident.last_latitude || currentSelectedIncident.initial_latitude;
    const lon = currentSelectedIncident.last_longitude || currentSelectedIncident.initial_longitude;
    openGoogleMapsNavigation(lat, lon);
});

document.getElementById('modal-btn-share').addEventListener('click', () => {
    if (!currentSelectedIncident) return;
    const lat = currentSelectedIncident.last_latitude || currentSelectedIncident.initial_latitude;
    const lon = currentSelectedIncident.last_longitude || currentSelectedIncident.initial_longitude;
    const acc = currentSelectedIncident.last_accuracy || 10;
    shareLocationDetails('BHAI Incident', lat, lon, acc);
});

// Acknowledge, Resolve, Cancel buttons
document.getElementById('modal-btn-ack').addEventListener('click', async () => {
    if (!currentSelectedIncident) return;
    const token = getAdminToken();
    try {
        await fetch(`/api/emergency/${currentSelectedIncident.id}/acknowledge`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
            body: JSON.stringify({ response_type: 'ACKNOWLEDGED' })
        });
        showToast('Incident acknowledged by Admin.');
        detailModal.style.display = 'none';
        fetchAdminData();
    } catch (_) {}
});

document.getElementById('modal-btn-resolve').addEventListener('click', async () => {
    if (!currentSelectedIncident) return;
    const token = getAdminToken();
    try {
        await fetch(`/api/emergency/${currentSelectedIncident.id}/resolve`, {
            method: 'POST',
            headers: { 'Authorization': `Bearer ${token}` }
        });
        showToast('Incident marked as RESOLVED.');
        detailModal.style.display = 'none';
        fetchAdminData();
    } catch (_) {}
});

document.getElementById('modal-btn-cancel').addEventListener('click', async () => {
    if (!currentSelectedIncident) return;
    const token = getAdminToken();
    try {
        await fetch(`/api/emergency/${currentSelectedIncident.id}/cancel`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
            body: JSON.stringify({ reason: 'ADMIN_CLOSED' })
        });
        showToast('Incident CANCELLED.');
        detailModal.style.display = 'none';
        fetchAdminData();
    } catch (_) {}
});

// --- Tabs Switcher ---
document.getElementById('tab-emergencies').addEventListener('click', () => {
    currentFilter = 'EMERGENCIES';
    document.getElementById('tab-emergencies').classList.add('active');
    document.getElementById('tab-live-streams').classList.remove('active');
    renderFeed();
});

document.getElementById('tab-live-streams').addEventListener('click', () => {
    currentFilter = 'LIVE_STREAMS';
    document.getElementById('tab-live-streams').classList.add('active');
    document.getElementById('tab-emergencies').classList.remove('active');
    renderFeed();
});

// --- WebSocket Realtime Mesh ---
function connectAdminWebSocket() {
    const token = getAdminToken();
    if (!token) return;

    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${protocol}//${window.location.host}/ws/admin?token=${encodeURIComponent(token)}`;

    if (ws) {
        try { ws.close(); } catch (_) {}
    }

    ws = new WebSocket(wsUrl);

    ws.onopen = () => {
        wsStatusText.textContent = 'Realtime Mesh Active';
        wsStatusDot.classList.add('connected');
    };

    ws.onmessage = (event) => {
        try {
            const msg = JSON.parse(event.data);
            const evt = msg.event;
            const data = msg.data;

            if (evt === 'emergency_created') {
                showToast(`🚨 NEW EMERGENCY ALERT RECEIVED!`);
                fetchAdminData();
            } else if (evt === 'live_location_updated' || evt === 'emergency_location_updated') {
                // Update marker directly if present
                const id = evt === 'live_location_updated' ? 'loc-' + data.session_id : 'em-' + data.id;
                if (markers[id] && data.latitude && data.longitude) {
                    markers[id].setLatLng([data.latitude, data.longitude]);
                }
                fetchAdminData();
            } else if (evt === 'emergency_resolved' || evt === 'emergency_cancelled' || evt === 'live_location_stopped') {
                fetchAdminData();
            }
        } catch (e) {
            console.error('Error handling WebSocket message:', e);
        }
    };

    ws.onclose = () => {
        wsStatusText.textContent = 'Reconnecting...';
        wsStatusDot.classList.remove('connected');
        clearTimeout(wsReconnectTimer);
        wsReconnectTimer = setTimeout(connectAdminWebSocket, 3000);
    };

    ws.onerror = () => {
        if (ws) ws.close();
    };
}

// --- Dashboard Init ---
function initDashboard() {
    initMap();
    fetchAdminData();
    connectAdminWebSocket();
    // 5-second polling fallback in case WebSockets are restricted by proxies
    setInterval(fetchAdminData, 5000);
}

document.getElementById('btn-manual-refresh').addEventListener('click', () => {
    fetchAdminData();
    showToast('Dashboard data refreshed.');
});

loginForm.addEventListener('submit', handleLogin);

window.addEventListener('DOMContentLoaded', () => {
    const token = getAdminToken();
    if (token) {
        loginModal.style.display = 'none';
        adminApp.style.display = 'flex';
        initDashboard();
    } else {
        loginModal.style.display = 'flex';
        adminApp.style.display = 'none';
    }
});
