"""Digitalgrub Chat's Sygnal pushkins.

One job: let a phone tell a call push from a message push, so a locked phone
can ring like a phone instead of saying "New message".

The obvious route — the client's ring rule sets tweaks on call events — is a
dead end, in Synapse's own words (push/httppusher.py): "event_id_only doesn't
include the tweaks, so override them", tweaks = {}. Our pushers use
event_id_only deliberately, so that message text never rides through Google
or Apple, which means the gateway is handed an event id and a room id and
nothing else. So the pushkin asks the question directly: it looks the event
up over Synapse's admin API — the two containers are neighbours on the same
compose network — and marks the push when the type is a call ring. The event
is fetched by id, so a busy room cannot bury it, and the answer is cached
briefly so a roomful of phones costs one lookup. Any failure quietly means
"not a call": a ring that arrives as "New message" is still better than a
message push that arrives late or not at all.

Deployment: mounted at /sygnal-ext (PYTHONPATH) with /secrets alongside, the
same admin-account file the invite script uses.

Config:
  com.digitalgrub.chat.android:
    type: dg_pushkins.DgGcmPushkin
    ... (unchanged gcm settings)
"""

import json
import logging
import os
import time
import urllib.error
import urllib.parse
import urllib.request

import asyncio

from twisted.internet.defer import Deferred

from sygnal.apnspushkin import ApnsPushkin
from sygnal.gcmpushkin import GcmPushkin

logger = logging.getLogger(__name__)

SYNAPSE_URL = os.environ.get("DG_SYNAPSE_URL", "http://synapse:8008")
ADMIN_ACCOUNT_FILE = os.environ.get(
    "DG_ADMIN_ACCOUNT_FILE", "/secrets/admin-account"
)
CALL_EVENT_TYPE = "org.matrix.msc4075.rtc.notification"

_admin_token = None


def _synapse(path, token=None, method="GET", body=None):
    request = urllib.request.Request(SYNAPSE_URL + path, method=method)
    if token:
        request.add_header("Authorization", "Bearer " + token)
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        request.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(request, data=data, timeout=5) as response:
        return json.loads(response.read())


def _admin_login():
    creds = {}
    with open(ADMIN_ACCOUNT_FILE) as f:
        for line in f:
            line = line.strip()
            if "=" in line:
                key, _, value = line.partition("=")
                creds[key.strip()] = value.strip().strip('"')
    localpart = creds["user"].split(":", 1)[0].lstrip("@")
    return _synapse(
        "/_matrix/client/v3/login",
        method="POST",
        body={
            "type": "m.login.password",
            "identifier": {"type": "m.id.user", "user": localpart},
            "password": creds["password"],
        },
    )["access_token"]


# One answer serves every recipient of the same ring: a ten-person room costs
# Synapse one lookup, not ten. Short-lived on purpose -- it exists to cover the
# burst of pushes for a single event, not to remember anything.
_call_cache = {}
_CALL_CACHE_TTL_SECONDS = 120
_CALL_CACHE_MAX = 512


def _cached_verdict(event_id):
    entry = _call_cache.get(event_id)
    if entry is None:
        return None
    verdict, at = entry
    if time.monotonic() - at > _CALL_CACHE_TTL_SECONDS:
        _call_cache.pop(event_id, None)
        return None
    return verdict


def _remember_verdict(event_id, verdict):
    if len(_call_cache) >= _CALL_CACHE_MAX:
        # Nothing here is worth preserving past its burst, so the cheapest
        # eviction is the right one.
        _call_cache.clear()
    _call_cache[event_id] = (verdict, time.monotonic())


def _is_call_event(room_id, event_id):
    """True when the event is a call ring, by asking Synapse for that event.

    Asks for the event by id rather than scanning the tail of the timeline.
    Everyone answering a group call writes membership state right behind the
    ring, so any window deep enough for a quiet room can still lose the ring
    in a busy one — and a busy room is exactly where the phone most needs to
    ring. Asking by id has no window to fall out of.
    Every failure path returns False on purpose — misclassifying a call as a
    message degrades to today's behaviour, while an exception here would cost
    the push entirely.
    """
    global _admin_token
    if not room_id or not event_id:
        return False
    remembered = _cached_verdict(event_id)
    if remembered is not None:
        return remembered
    try:
        for attempt in (0, 1):
            if _admin_token is None:
                _admin_token = _admin_login()
            room = urllib.parse.quote(room_id, safe="")
            event = urllib.parse.quote(event_id, safe="")
            try:
                context = _synapse(
                    f"/_synapse/admin/v1/rooms/{room}/context/{event}?limit=0",
                    token=_admin_token,
                )
            except urllib.error.HTTPError as error:
                if error.code in (401, 403) and attempt == 0:
                    _admin_token = None
                    continue
                raise
            verdict = (context.get("event") or {}).get("type") == CALL_EVENT_TYPE
            _remember_verdict(event_id, verdict)
            return verdict
    except Exception:
        logger.exception("call lookup failed for %s; treating as message", event_id)
    return False


_original_build_data = GcmPushkin._build_data


def _dg_build_data(n, device, api_version, send_badge_counts):
    data = _original_build_data(n, device, api_version, send_badge_counts)
    if data is not None and getattr(n, "dg_call", False):
        # FCM v1 requires string values in the data map.
        data["dg_call"] = "1"
        logger.info("dg_call marker added for event %s", n.event_id)
    return data


# The dispatch path invokes `GcmPushkin._build_data(...)` by class name rather
# than through `self`, so a subclass override is dead code; wrapping the
# function on the base class is the smallest change that actually runs.
GcmPushkin._build_data = staticmethod(_dg_build_data)


class DgGcmPushkin(GcmPushkin):
    """GcmPushkin plus the dg_call marker; see module docstring."""

    async def _dispatch_notification_unlimited(self, n, device, context):
        # The classifier runs off-thread, bridged with Deferred.fromFuture:
        # this coroutine is driven by Twisted's ensureDeferred on top of the
        # asyncioreactor, where a raw deferToThread Deferred parks forever
        # (Synapse read the stall as a gateway timeout) and a bare asyncio
        # future dies with "await wasn't used with future".
        await _classify(n)
        return await super()._dispatch_notification_unlimited(n, device, context)

async def _classify(n):
    """Stamps the notification with whether it is a call, once."""
    if not hasattr(n, "dg_call"):
        loop = asyncio.get_event_loop()
        n.dg_call = await Deferred.fromFuture(
            loop.run_in_executor(None, _is_call_event, n.room_id, n.event_id)
        )
    return n.dg_call


class DgApnsVoipPushkin(ApnsPushkin):
    """The iOS ring channel: forwards call events, swallows everything else.

    Apple's contract for VoIP pushes is strict — every one delivered must
    immediately report a call to CallKit, or the app is punished — and
    Synapse sends every notifying event to every pusher indiscriminately.
    So this pushkin is the filter: pointed at the `.voip` topic with
    push_type voip, it lets ring events through and answers success-without-
    dispatch for the rest, which keeps messages off the ring channel without
    marking their pushkeys as failed.

    Config (no pushers reference this until the iOS app registers its
    PushKit token as a second pusher):
      com.digitalgrub.chat.ios.voip:
        type: dg_pushkins.DgApnsVoipPushkin
        keyfile: /secrets/apns-key.p8
        key_id / team_id: as the alert app
        topic: com.digitalgrub.chat.voip
        push_type: voip
    """

    async def _dispatch_notification_unlimited(self, n, device, context):
        if not await _classify(n):
            return []
        logger.info("voip ring dispatch for event %s", n.event_id)
        return await super()._dispatch_notification_unlimited(n, device, context)

