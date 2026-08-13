#!/usr/bin/env bash
# Realtime message delivery, end to end.
#
# Proves the path the UI depends on:
#   A sends ──► API stores ──► outbox ──► worker ──► notification
#        ──► Redis ──► /ws gateway ──► B's socket (no refresh, no polling)
#
# The socket is opened through the UI's own origin (:3000), so this also covers
# the dev-server proxy — realtime silently failed there before, because Vite
# was not configured to upgrade /ws even though production nginx was.
API=http://localhost:3001/api/v1
WS_ORIGIN=${WS_ORIGIN:-localhost:3000}
S=$RANDOM$RANDOM
UA=rt_a_$S
UB=rt_b_$S
PASS='Sup3rSecret!pw'

pass=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "  PASS  $1 ($3)"; pass=$((pass+1));
        else echo "  FAIL  $1 (expected $2, got $3)"; fail=$((fail+1)); fi }
code() { curl -s -o /tmp/rt.$$ -w '%{http_code}' "$@"; }
jq_() { python3 -c "import sys,json;d=json.load(sys.stdin);$1" < /tmp/rt.$$ 2>/dev/null; }

reg() {
  code -X POST $API/register -H 'Content-Type: application/json' \
    -d "{\"username\":\"$1\",\"password\":\"$PASS\",\"firstName\":\"Rt\",\"lastName\":\"${1: -4}\",\"recoveryEmail\":\"$1@example.test\"}" >/dev/null
  code -X POST $API/login -H 'Content-Type: application/json' \
    -d "{\"username\":\"$1\",\"password\":\"$PASS\"}" >/dev/null
  jq_ 'print(d["token"])'
}

echo "== setup =="
TOKA=$(reg $UA); TOKB=$(reg $UB)
[ -n "$TOKA" ] && [ -n "$TOKB" ] && { echo "  PASS  both users signed in"; pass=$((pass+1)); } \
  || { echo "  FAIL  sign-in"; fail=$((fail+1)); exit 1; }

code "$API/messaging/users/search?q=$UB" -H "Authorization: Bearer $TOKA" >/dev/null
PEER=$(jq_ 'print(d["users"][0]["id"] if d["users"] else "")')
code -X POST $API/messaging/requests -H "Authorization: Bearer $TOKA" -H 'Content-Type: application/json' \
  -d "{\"recipientId\":\"$PEER\",\"message\":\"realtime check\"}" >/dev/null
code $API/messaging/requests -H "Authorization: Bearer $TOKB" >/dev/null
REQ=$(jq_ 'r=[x for x in d["requests"] if x["direction"]=="incoming"];print(r[0]["id"] if r else "")')
code -X POST $API/messaging/requests/$REQ/respond -H "Authorization: Bearer $TOKB" \
  -H 'Content-Type: application/json' -d '{"action":"accept"}' >/dev/null
CONV=$(jq_ 'print(d.get("conversationId") or "")')
[ -n "$CONV" ] && { echo "  PASS  conversation established"; pass=$((pass+1)); } \
  || { echo "  FAIL  no conversation"; fail=$((fail+1)); exit 1; }

echo
echo "== B connects to the realtime gateway through the UI origin =="
RESULT=$(python3 - "$WS_ORIGIN" "$TOKB" "$CONV" "$API" "$TOKA" <<'PY'
import json, sys, threading, time, urllib.request
from http.client import HTTPConnection
import base64, hashlib, os, socket, struct

ws_origin, token_b, conv, api, token_a = sys.argv[1:6]
host, _, port = ws_origin.partition(':')
port = int(port or 80)

# Minimal RFC6455 client: avoids adding a dependency just to assert delivery.
key = base64.b64encode(os.urandom(16)).decode()
sock = socket.create_connection((host, port), timeout=10)
sock.sendall((
    f"GET /ws?token={token_b} HTTP/1.1\r\n"
    f"Host: {ws_origin}\r\n"
    "Upgrade: websocket\r\nConnection: Upgrade\r\n"
    f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
).encode())

buf = b""
while b"\r\n\r\n" not in buf:
    chunk = sock.recv(4096)
    if not chunk:
        print("HANDSHAKE_FAILED|no response"); sys.exit(0)
    buf += chunk
status = buf.split(b"\r\n")[0].decode()
if "101" not in status:
    print(f"HANDSHAKE_FAILED|{status}"); sys.exit(0)
print(f"HANDSHAKE_OK|{status}")

def read_frame(s, timeout=20):
    s.settimeout(timeout)
    hdr = s.recv(2)
    if len(hdr) < 2: return None
    length = hdr[1] & 0x7F
    if length == 126:
        length = struct.unpack(">H", s.recv(2))[0]
    elif length == 127:
        length = struct.unpack(">Q", s.recv(8))[0]
    data = b""
    while len(data) < length:
        part = s.recv(length - len(data))
        if not part: break
        data += part
    return data

frames = []
def reader():
    deadline = time.time() + 20
    while time.time() < deadline:
        try:
            payload = read_frame(sock)
        except Exception:
            break
        if payload is None: break
        try:
            frames.append(json.loads(payload.decode()))
        except Exception:
            pass

t = threading.Thread(target=reader, daemon=True); t.start()
time.sleep(1.5)   # let 'connected' land and the subscription settle

# A sends, with the socket already open and nothing polling.
req = urllib.request.Request(
    f"{api}/messaging/conversations/{conv}/messages",
    data=json.dumps({"body": "Realtime hello from A"}).encode(),
    headers={"Content-Type": "application/json", "Authorization": f"Bearer {token_a}"},
    method="POST")
with urllib.request.urlopen(req, timeout=10) as r:
    print(f"SEND_STATUS|{r.status}")

t.join(timeout=18)

notes = [f for f in frames if f.get("type") == "notification"]
print(f"CONNECTED_FRAME|{'yes' if any(f.get('type')=='connected' for f in frames) else 'no'}")

# Any notification queued before the socket opened (the earlier chat request)
# is delivered too, so select the one under test rather than the first to
# arrive. Its count is asserted separately, to catch duplicates.
chat = [f for f in notes if (f.get("payload") or {}).get("type") == "chat.message"]
print(f"NOTIFICATION_COUNT|{len(notes)}")
print(f"CHAT_MESSAGE_COUNT|{len(chat)}")
if chat:
    p = chat[0].get("payload", {})
    d = p.get("data", {}) or {}
    print(f"NOTIF_TYPE|{p.get('type')}")
    print(f"NOTIF_TITLE|{p.get('title')}")
    print(f"NOTIF_BODY|{p.get('body')}")
    print(f"NOTIF_CONV|{d.get('conversationId')}")
    print(f"NOTIF_HAS_MSGID|{'yes' if d.get('messageId') else 'no'}")
    print(f"NOTIF_APPID|{d.get('appId')}")
sock.close()
PY
)
echo "$RESULT" | sed 's/^/  · /'

get() { echo "$RESULT" | grep "^$1|" | head -1 | cut -d'|' -f2-; }

echo
chk "websocket handshake through UI origin" "HANDSHAKE_OK" "$([ -n "$(get HANDSHAKE_OK)" ] && echo HANDSHAKE_OK || echo FAILED)"
chk "gateway greets the client" "yes" "$(get CONNECTED_FRAME)"
chk "A's message accepted" "201" "$(get SEND_STATUS)"
chk "B received the message push, exactly once" "1" "$(get CHAT_MESSAGE_COUNT)"
chk "push is a chat message" "chat.message" "$(get NOTIF_TYPE)"
chk "push carries the message preview" "Realtime hello from A" "$(get NOTIF_BODY)"
chk "push routes to the conversation" "$CONV" "$(get NOTIF_CONV)"
chk "push carries a message id for dedupe" "yes" "$(get NOTIF_HAS_MSGID)"
chk "push names the app to open" "messenger" "$(get NOTIF_APPID)"

echo
echo "== nothing is lost while offline: B fetches after the fact =="
code $API/messaging/conversations -H "Authorization: Bearer $TOKB" >/dev/null
chk "conversation shows unread" "1" "$(jq_ 'print(d["conversations"][0]["unreadCount"])')"
chk "preview stored server-side" "Realtime hello from A" "$(jq_ 'print(d["conversations"][0]["lastMessagePreview"])')"
code $API/messaging/conversations/$CONV/messages -H "Authorization: Bearer $TOKB" >/dev/null
chk "message retrievable on reopen" "1" "$(jq_ 'print(len(d["messages"]))')"
code -X POST $API/messaging/conversations/$CONV/read -H "Authorization: Bearer $TOKB" >/dev/null
code $API/messaging/conversations -H "Authorization: Bearer $TOKB" >/dev/null
chk "unread clears once read" "0" "$(jq_ 'print(d["conversations"][0]["unreadCount"])')"

echo
echo "== sender is not notified of their own message =="
code $API/notifications -H "Authorization: Bearer $TOKA" >/dev/null
chk "A has no chat.message notification" "0" \
  "$(jq_ 'ns=d.get("notifications", d if isinstance(d,list) else []);print(len([n for n in ns if n.get("type")=="chat.message"]))')"

echo
echo "RESULT: $pass passed, $fail failed"
rm -f /tmp/rt.$$
[ $fail -eq 0 ]
