// Digitalgrub Chat -- Web Push service worker.
//
// Registered at scope /push/ so it never competes with Flutter's own worker
// at the root. It exists for exactly two events: a push arriving while no tab
// is open, and a click on the notification that raised.
//
// The payload is event_id_only: a room id, an event id and unread counts, and
// never the message itself. That is deliberate -- it keeps message text off
// the browser vendor's push service, the same rule the phones follow -- so the
// notification can only ever say "new message". When a tab is open, it is
// already syncing and shows the real thing; this worker stays out of its way.

self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('push', (event) => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch (_) { data = {}; }
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    if (typeof data.unread === 'number' && 'setAppBadge' in navigator) {
      navigator.setAppBadge(data.unread).catch(() => {});
    }
    // Any open tab -- visible or not -- is syncing and notifies with the
    // real text. A second, blanker notification from here would only be
    // noise.
    if (windows.length > 0) return;
    if (!data.event_id) return;
    await self.registration.showNotification('Digitalgrub Chat', {
      body: 'New message',
      icon: 'icons/Icon-192.png',
      badge: 'icons/Icon-192.png',
      tag: data.room_id || 'digitalgrub-chat',
      renotify: true,
      data: { room_id: data.room_id || null },
    });
  })());
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const room = event.notification.data && event.notification.data.room_id;
  const url = room ? '/#/chats/room/' + encodeURIComponent(room) : '/';
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const client of windows) {
      if ('focus' in client) {
        await client.focus();
        if (room && 'navigate' in client) { try { await client.navigate(url); } catch (_) {} }
        return;
      }
    }
    await self.clients.openWindow(url);
  })());
});
