// Super Admin Dashboard Application Logic
const API_URL = `${window.location.protocol}//${window.location.host}/api`;
const WS_URL = `${window.location.protocol === 'https:' ? 'wss:' : 'ws:'}//${window.location.host}`;

let token = localStorage.getItem('admin_token');
let adminUser = null;
let socket = null;
let map = null;

// Application State
const state = {
  stats: {},
  users: [],
  orders: [],
  couriers: new Map(), // userId -> courier object & marker
  orderMarkers: new Map(), // orderId -> order marker object
  verificationCouriers: [] // list of couriers from /admin/couriers
};

// UI Elements
const els = {
  loginOverlay: document.getElementById('login-overlay'),
  loginForm: document.getElementById('login-form'),
  loginEmail: document.getElementById('login-email'),
  loginPassword: document.getElementById('login-password'),
  loginError: document.getElementById('login-error'),
  
  appLayout: document.getElementById('app-layout'),
  adminName: document.getElementById('admin-name'),
  adminRole: document.getElementById('admin-role'),
  btnLogout: document.getElementById('btn-logout'),
  wsStatus: document.getElementById('ws-status'),
  
  // Tabs
  navItems: document.querySelectorAll('.nav-item'),
  tabPanes: document.querySelectorAll('.tab-pane'),
  badgeVerifications: document.getElementById('badge-verifications'),
  onlineCouriersList: document.getElementById('online-couriers-list'),
  logsConsole: document.getElementById('logs-console'),
  
  // Stats
  statTotalUsers: document.getElementById('stat-total-users'),
  statVerifiedCouriers: document.getElementById('stat-verified-couriers'),
  statPendingVerifies: document.getElementById('stat-pending-verifies'),
  statActiveOrders: document.getElementById('stat-active-orders'),
  statRevenue: document.getElementById('stat-revenue'),
  
  // Tables
  tableUsers: document.querySelector('#table-users tbody'),
  tableVerifications: document.querySelector('#table-verifications tbody'),
  tableOrders: document.querySelector('#table-orders tbody'),
  
  // Modal
  documentModal: document.getElementById('document-modal'),
  closeModalBtn: document.getElementById('close-modal-btn'),
  nidaDocContainer: document.getElementById('nida-doc-container'),
  selfieDocContainer: document.getElementById('selfie-doc-container')
};

// ── Auth Logic ──────────────────────────────────────────────────────────────
els.loginForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  els.loginError.classList.add('hide');
  
  const email = els.loginEmail.value;
  const password = els.loginPassword.value;
  
  try {
    const res = await fetch(`${API_URL}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password })
    });
    
    const data = await res.json();
    if (!res.ok) throw new Error(data.message || 'Login failed');
    
    const user = data.user;
    if (user.role.toUpperCase() !== 'ADMIN') {
      throw new Error('Access denied: Admin role required.');
    }
    
    token = data.accessToken;
    localStorage.setItem('admin_token', token);
    localStorage.setItem('admin_user', JSON.stringify(user));
    
    initDashboard();
  } catch (error) {
    els.loginError.textContent = error.message;
    els.loginError.classList.remove('hide');
  }
});

els.btnLogout.addEventListener('click', () => {
  localStorage.removeItem('admin_token');
  localStorage.removeItem('admin_user');
  token = null;
  adminUser = null;
  if (socket) socket.close();
  location.reload();
});

// Check existing login
if (token) {
  try {
    adminUser = JSON.parse(localStorage.getItem('admin_user'));
    initDashboard();
  } catch (e) {
    localStorage.clear();
    els.loginOverlay.classList.remove('hide');
  }
} else {
  els.loginOverlay.classList.remove('hide');
}

// ── Init Dashboard ──────────────────────────────────────────────────────────
async function initDashboard() {
  adminUser = JSON.parse(localStorage.getItem('admin_user'));
  els.adminName.textContent = adminUser.name;
  els.adminRole.textContent = adminUser.role === 'super_admin' ? 'Super Admin' : 'Administrator';
  
  els.loginOverlay.classList.add('hide');
  els.appLayout.classList.remove('hide');
  
  // Set up Map
  initMap();
  
  // Initial Fetches
  await fetchStats();
  await fetchUsers();
  await fetchOrders();
  await fetchCouriers();
  
  // Connect real-time socket
  connectWS();
  
  // Add Nav Tab Handlers
  els.navItems.forEach(item => {
    item.addEventListener('click', (e) => {
      e.preventDefault();
      const tabId = item.getAttribute('data-tab');
      
      els.navItems.forEach(nav => nav.classList.remove('active'));
      els.tabPanes.forEach(pane => pane.classList.remove('active'));
      
      item.classList.add('active');
      document.getElementById(`tab-${tabId}`).classList.add('active');
      
      // Invalidate Map layout on display
      if (tabId === 'dashboard' && map) {
        setTimeout(() => map.invalidateSize(), 100);
      }
    });
  });
}

// ── Leaflet Live Map ────────────────────────────────────────────────────────
function initMap() {
  // Center map on Dar es Salaam
  map = L.map('live-map').setView([-6.7924, 39.2083], 13);
  
  // Load beautiful dark-mode tiles
  L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>',
    subdomains: 'abcd',
    maxZoom: 20
  }).addTo(map);
}

// Helper: Custom pulsing courier marker
function createCourierIcon() {
  return L.divIcon({
    className: 'courier-marker-icon',
    html: `<div class="marker-pin-wrapper"><div class="pulse-circle"></div><div class="center-dot"></div></div>`,
    iconSize: [40, 40],
    iconAnchor: [20, 20]
  });
}

// Helper: Custom order marker
function createOrderIcon(status) {
  const isPending = status === 'PENDING';
  return L.divIcon({
    className: 'order-marker-icon',
    html: `<div class="order-marker-pin-wrapper"><div class="order-dot ${isPending ? 'pending' : 'active'}"></div></div>`,
    iconSize: [30, 30],
    iconAnchor: [15, 15]
  });
}

// ── WebSocket Connectivity ──────────────────────────────────────────────────
function connectWS() {
  const statusDot = els.wsStatus.querySelector('.status-dot');
  const statusText = els.wsStatus.querySelector('.status-text');
  
  socket = new WebSocket(`${WS_URL}?token=${token}`);
  
  socket.onopen = () => {
    statusDot.className = 'status-dot online';
    statusText.textContent = 'Online';
    logEvent('system', 'Connected to real-time notification network.');
  };
  
  socket.onclose = () => {
    statusDot.className = 'status-dot offline';
    statusText.textContent = 'Offline';
    logEvent('error', 'Disconnected from real-time network. Reconnecting in 5s...');
    setTimeout(connectWS, 5000);
  };
  
  socket.onerror = (err) => {
    console.error('WebSocket connection error:', err);
  };
  
  socket.onmessage = (event) => {
    try {
      const data = JSON.parse(event.data);
      handleWSEvent(data);
    } catch (e) {
      console.error('Error parsing WS frame:', e);
    }
  };
}

function handleWSEvent(data) {
  switch (data.type) {
    case 'active_couriers':
      data.couriers.forEach(courier => {
        updateCourierPin(courier);
      });
      updateOnlineCouriersWidget();
      break;
      
    case 'courier_location_update':
      updateCourierPin(data.courier);
      updateOnlineCouriersWidget();
      logEvent('location', `Courier [${data.courier.name}] location sync: ${data.courier.currentLatitude.toFixed(4)}, ${data.courier.currentLongitude.toFixed(4)}`);
      break;
      
    case 'courier_offline':
      removeCourierPin(data.userId);
      updateOnlineCouriersWidget();
      logEvent('system', `Courier [ID: ${data.userId}] went offline.`);
      break;
      
    case 'order_event':
      logEvent('order', `Order [ID: ${data.order.id.slice(0,8)}] status updated: ${data.eventType}`);
      fetchStats();
      fetchOrders();
      updateOrderPin(data.order);
      break;
      
    case 'order_broadcast':
      logEvent('order', `New order broadcasted: [${data.order.itemType}] TZS ${data.order.estimatedPrice}`);
      fetchStats();
      fetchOrders();
      updateOrderPin(data.order);
      break;
      
    default:
      console.log('Unhandled WS payload:', data);
  }
}

// Map plotting
function updateCourierPin(courier) {
  if (!courier.currentLatitude || !courier.currentLongitude) return;
  
  const latLng = [courier.currentLatitude, courier.currentLongitude];
  
  if (state.couriers.has(courier.id)) {
    const active = state.couriers.get(courier.id);
    active.marker.setLatLng(latLng);
    active.courier = courier;
  } else {
    const marker = L.marker(latLng, { icon: createCourierIcon() }).addTo(map);
    marker.bindPopup(`
      <div style="font-family: Outfit; color: #0b132b">
        <h4 style="margin: 0 0 5px 0">${courier.name}</h4>
        <p style="margin: 0; font-size: 11px; color: #666">Verified Courier: ${courier.isFullyVerified ? 'Yes' : 'No'}</p>
        <p style="margin: 0; font-size: 11px; color: #666">Status: ${courier.courierStatus}</p>
      </div>
    `);
    state.couriers.set(courier.id, { courier, marker });
  }
}

function removeCourierPin(userId) {
  if (state.couriers.has(userId)) {
    const active = state.couriers.get(userId);
    map.removeLayer(active.marker);
    state.couriers.delete(userId);
  }
}

function updateOrderPin(order) {
  if (!order.pickupLatitude || !order.pickupLongitude) return;
  
  const latLng = [order.pickupLatitude, order.pickupLongitude];
  
  if (order.status !== 'PENDING' && order.status !== 'ACCEPTED' && order.status !== 'PICKED_UP') {
    // Remove completed/cancelled orders from active map tracking
    if (state.orderMarkers.has(order.id)) {
      map.removeLayer(state.orderMarkers.get(order.id));
      state.orderMarkers.delete(order.id);
    }
    return;
  }
  
  if (state.orderMarkers.has(order.id)) {
    const marker = state.orderMarkers.get(order.id);
    marker.setLatLng(latLng);
  } else {
    const marker = L.marker(latLng, { icon: createOrderIcon(order.status) }).addTo(map);
    marker.bindPopup(`
      <div style="font-family: Outfit; color: #0b132b">
        <h4 style="margin: 0 0 5px 0">${order.itemType}</h4>
        <p style="margin: 0; font-size: 11px; color: #666">Pickup: ${order.pickupAddress}</p>
        <p style="margin: 0; font-size: 11px; color: #666">Fee: TZS ${parseFloat(order.estimatedPrice).toFixed(0)}</p>
        <p style="margin: 5px 0 0 0; font-size: 11px; font-weight: bold; color: ${order.status === 'PENDING' ? '#f5a623' : '#3b82f6'}">Status: ${order.status}</p>
      </div>
    `);
    state.orderMarkers.set(order.id, marker);
  }
}

// ── API Fetch Calls ─────────────────────────────────────────────────────────
async function fetchStats() {
  try {
    const res = await fetch(`${API_URL}/admin/stats`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    const data = await res.json();
    state.stats = data;
    
    // Render Stats
    els.statTotalUsers.textContent = data.totalUsers;
    els.statVerifiedCouriers.textContent = data.totalCouriers;
    els.statPendingVerifies.textContent = data.pendingVerifications;
    els.statActiveOrders.textContent = data.activeOrders;
    els.statRevenue.textContent = `TZS ${data.totalRevenue.toLocaleString()}`;
    
    // Manage badge
    if (data.pendingVerifications > 0) {
      els.badgeVerifications.textContent = data.pendingVerifications;
      els.badgeVerifications.classList.remove('hide');
    } else {
      els.badgeVerifications.classList.add('hide');
    }
  } catch (error) {
    console.error('Error fetching stats:', error);
  }
}

async function fetchUsers() {
  try {
    const res = await fetch(`${API_URL}/admin/users`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    const data = await res.json();
    state.users = data.users;
    
    renderUsers();
  } catch (error) {
    console.error('Error fetching users:', error);
  }
}

async function fetchCouriers() {
  try {
    const res = await fetch(`${API_URL}/admin/couriers`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    const data = await res.json();
    state.verificationCouriers = data.couriers || [];
    renderVerifications();
  } catch (error) {
    console.error('Error fetching couriers:', error);
  }
}

async function fetchOrders() {
  try {
    const res = await fetch(`${API_URL}/admin/orders`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    const data = await res.json();
    state.orders = data.orders;
    
    renderOrders();
    
    // Plot active orders on map
    state.orders.forEach(order => {
      updateOrderPin(order);
    });
  } catch (error) {
    console.error('Error fetching orders:', error);
  }
}

// ── Render Engines ──────────────────────────────────────────────────────────
function renderUsers() {
  els.tableUsers.innerHTML = '';
  const isSuper = adminUser.role === 'super_admin';
  
  state.users.forEach(user => {
    const tr = document.createElement('tr');
    
    const joined = new Date(user.createdAt).toLocaleDateString();
    
    tr.innerHTML = `
      <td><strong>${user.name}</strong></td>
      <td>${user.email}</td>
      <td>${user.phone}</td>
      <td>${joined}</td>
      <td>
        <select class="role-select" data-id="${user.id}" ${isSuper ? '' : 'disabled'}>
          <option value="user" ${user.role === 'user' ? 'selected' : ''}>User</option>
          <option value="admin" ${user.role === 'admin' ? 'selected' : ''}>Admin</option>
          <option value="super_admin" ${user.role === 'super_admin' ? 'selected' : ''}>Super Admin</option>
        </select>
      </td>
      <td>
        <label class="switch">
          <input type="checkbox" class="status-toggle" data-id="${user.id}" ${user.isActive ? 'checked' : ''} ${isSuper ? '' : 'disabled'}>
          <span class="slider"></span>
        </label>
      </td>
      <td>
        <button class="btn btn-danger btn-sm" onclick="deactivateUser('${user.id}')" ${isSuper && user.id !== adminUser.id ? '' : 'disabled'}>
          <i class="fa-solid fa-user-slash"></i>
        </button>
      </td>
    `;
    
    els.tableUsers.appendChild(tr);
  });
  
  // Attach role-change listeners
  document.querySelectorAll('.role-select').forEach(select => {
    select.addEventListener('change', async (e) => {
      const id = select.getAttribute('data-id');
      const role = select.value;
      
      try {
        const res = await fetch(`${API_URL}/admin/users/${id}/role`, {
          method: 'PUT',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`
          },
          body: JSON.stringify({ role })
        });
        
        if (!res.ok) {
          const data = await res.json();
          throw new Error(data.message || 'Failed to update role');
        }
        
        logEvent('system', `Role updated to [${role}] for user ID: ${id}`);
        fetchStats();
      } catch (error) {
        alert(error.message);
        fetchUsers(); // reset UI state
      }
    });
  });
  
  // Attach status toggle listeners
  document.querySelectorAll('.status-toggle').forEach(toggle => {
    toggle.addEventListener('change', async (e) => {
      const id = toggle.getAttribute('data-id');
      const isActive = toggle.checked;
      
      try {
        const res = await fetch(`${API_URL}/admin/users/${id}/active`, {
          method: 'PUT',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`
          },
          body: JSON.stringify({ isActive })
        });
        
        if (!res.ok) {
          const data = await res.json();
          throw new Error(data.message || 'Failed to toggle status');
        }
        
        logEvent('system', `Deactivation toggle updated to [${isActive}] for user ID: ${id}`);
        fetchStats();
      } catch (error) {
        alert(error.message);
        toggle.checked = !isActive; // rollback
      }
    });
  });
}

function renderVerifications() {
  els.tableVerifications.innerHTML = '';
  
  const pending = state.verificationCouriers.filter(c => !c.isVerified);
  
  if (pending.length === 0) {
    els.tableVerifications.innerHTML = '<tr><td colspan="7" class="empty-list">No pending courier verification applications.</td></tr>';
    return;
  }
  
  pending.forEach(user => {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td><strong>${user.name}</strong></td>
      <td>${user.email}</td>
      <td>${user.phone}</td>
      <td><code>${user.nidaNumber || 'N/A'}</code></td>
      <td>
        <span class="vehicle-badge">
          <i class="fa-solid fa-${user.vehicleType === 'car' ? 'car' : 'motorcycle'}"></i>
          ${user.vehicleType ? user.vehicleType.toUpperCase() : 'N/A'}
        </span>
        <div style="font-size:0.75rem;color:var(--color-text-muted);margin-top:2px;">Reg: ${user.vehicleRegistrationNumber || 'N/A'}</div>
      </td>
      <td>
        <button class="btn btn-success" onclick="openDocViewer('${user.idDocumentUrl}', '${user.selfieUrl}')">
          <i class="fa-solid fa-folder-open"></i> View Materials
        </button>
      </td>
      <td>
        <div style="display:flex;gap:10px;">
          <button class="btn btn-primary" onclick="verifyCourier('${user.id}', 'verified')">
            <i class="fa-solid fa-check"></i> Approve
          </button>
          <button class="btn btn-danger" onclick="verifyCourier('${user.id}', 'unverified')">
            <i class="fa-solid fa-xmark"></i> Reject
          </button>
        </div>
      </td>
    `;
    els.tableVerifications.appendChild(tr);
  });
}

function renderOrders() {
  els.tableOrders.innerHTML = '';
  
  if (state.orders.length === 0) {
    els.tableOrders.innerHTML = '<tr><td colspan="10" class="empty-list">No order transactions found.</td></tr>';
    return;
  }
  
  state.orders.forEach(order => {
    const tr = document.createElement('tr');
    const weight = order.packageWeightKg ? `${order.packageWeightKg} kg` : '—';
    const clientName = order.customerName || 'N/A';
    const courierName = order.courierName || '<span style="color:var(--color-text-muted);font-style:italic;">Unassigned</span>';
    
    tr.innerHTML = `
      <td><code>${order.id.slice(0, 8)}</code></td>
      <td><strong>${clientName}</strong></td>
      <td><strong>${courierName}</strong></td>
      <td><div style="max-width:150px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;" title="${order.pickupAddress}">${order.pickupAddress}</div></td>
      <td><div style="max-width:150px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;" title="${order.dropoffAddress}">${order.dropoffAddress}</div></td>
      <td>${order.itemType}</td>
      <td>${weight}</td>
      <td>TZS ${parseFloat(order.estimatedPrice).toFixed(0)}</td>
      <td><span class="status-badge status-${order.status}">${order.status}</span></td>
      <td>
        ${(order.status !== 'DELIVERED' && order.status !== 'CANCELLED') ? `
          <button class="btn btn-danger btn-sm" onclick="cancelOrder('${order.id}')">
            <i class="fa-solid fa-ban"></i> Cancel
          </button>
        ` : '—'}
      </td>
    `;
    els.tableOrders.appendChild(tr);
  });
}

// ── Sidebar Widgets ────────────────────────────────────────────────────────
function updateOnlineCouriersWidget() {
  els.onlineCouriersList.innerHTML = '';
  
  if (state.couriers.size === 0) {
    els.onlineCouriersList.innerHTML = '<p class="empty-list">No couriers online</p>';
    return;
  }
  
  for (const { courier } of state.couriers.values()) {
    const card = document.createElement('div');
    card.className = 'courier-sidebar-card';
    card.innerHTML = `
      <div class="courier-status-pulse"></div>
      <div class="courier-card-details">
        <h4>${courier.name}</h4>
        <p>${courier.isFullyVerified ? 'Verified Courier' : 'Pending Verification'}</p>
      </div>
    `;
    
    // Zoom/Pan to courier on click
    card.addEventListener('click', () => {
      if (courier.currentLatitude && courier.currentLongitude) {
        map.setView([courier.currentLatitude, courier.currentLongitude], 16);
      }
    });
    
    els.onlineCouriersList.appendChild(card);
  }
}

// ── Actions Handlers ────────────────────────────────────────────────────────
window.deactivateUser = async (id) => {
  if (!confirm('Are you sure you want to deactivate this account?')) return;
  try {
    const res = await fetch(`${API_URL}/admin/users/${id}/active`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: JSON.stringify({ isActive: false })
    });
    if (!res.ok) throw new Error('Failed to deactivate user');
    logEvent('error', `User ID: ${id} has been deactivated.`);
    fetchUsers();
    fetchStats();
  } catch (error) {
    alert(error.message);
  }
};

window.verifyCourier = async (id, status) => {
  const confirmMsg = status === 'verified' ? 'Verify and approve this courier application?' : 'Reject this courier application?';
  if (!confirm(confirmMsg)) return;
  
  try {
    const res = await fetch(`${API_URL}/admin/couriers/${id}/verify`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: JSON.stringify({ status })
    });
    
    if (!res.ok) throw new Error('Failed to verify courier');
    logEvent('system', `Courier ID: ${id} verification set to: ${status}`);
    await fetchCouriers();
    await fetchUsers();
    await fetchStats();
  } catch (error) {
    alert(error.message);
  }
};

window.cancelOrder = async (id) => {
  if (!confirm('Cancel this active order? This cannot be undone.')) return;
  
  try {
    const res = await fetch(`${API_URL}/admin/orders/${id}/cancel`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      }
    });
    
    if (!res.ok) throw new Error('Failed to cancel order');
    logEvent('error', `Active Order ID: ${id} was CANCELLED by Admin.`);
    fetchOrders();
    fetchStats();
  } catch (error) {
    alert(error.message);
  }
};

// Document modal viewer
window.openDocViewer = (docUrl, selfieUrl) => {
  const uploadBaseUrl = `${window.location.protocol}//${window.location.host}`;
  
  els.nidaDocContainer.innerHTML = docUrl && docUrl !== 'null'
    ? `<img src="${uploadBaseUrl}${docUrl}" alt="NIDA ID">`
    : `<p>No document uploaded</p>`;
    
  els.selfieDocContainer.innerHTML = selfieUrl && selfieUrl !== 'null'
    ? `<img src="${uploadBaseUrl}${selfieUrl}" alt="Courier Selfie">`
    : `<p>No document uploaded</p>`;
    
  els.documentModal.classList.remove('hide');
};

els.closeModalBtn.addEventListener('click', () => {
  els.documentModal.classList.add('hide');
});

// Close modal when clicking outside
window.addEventListener('click', (e) => {
  if (e.target === els.documentModal) {
    els.documentModal.classList.add('hide');
  }
});

// ── Log Console Manager ─────────────────────────────────────────────────────
function logEvent(type, text) {
  const time = new Date().toLocaleTimeString();
  const entry = document.createElement('div');
  entry.className = `log-entry ${type}`;
  entry.innerHTML = `<span class="time">[${time}]</span> ${text}`;
  
  els.logsConsole.appendChild(entry);
  
  // Keep scroll at bottom
  els.logsConsole.scrollTop = els.logsConsole.scrollHeight;
}
