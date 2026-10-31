#!/usr/bin/env bash
# End-to-end workflow probe against the running stack.
# Exercises: register -> login -> profile -> org -> files -> share -> messaging.
API=http://localhost:3001/api/v1
S=$RANDOM$RANDOM
UA=aud_a_$S
UB=aud_b_$S
PASS='Sup3rSecret!pw'

pass=0; fail=0
chk() { # chk <label> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "  PASS  $1 ($3)"; pass=$((pass+1));
  else echo "  FAIL  $1 (expected $2, got $3)"; fail=$((fail+1)); fi
}
code() { curl -s -o /tmp/body.$$ -w '%{http_code}' "$@"; }
body() { cat /tmp/body.$$; }

echo "== 1. Registration =="
c=$(code -X POST $API/register -H 'Content-Type: application/json' \
  -d "{\"username\":\"$UA\",\"password\":\"$PASS\",\"firstName\":\"Aud\",\"lastName\":\"Alpha\",\"recoveryEmail\":\"$UA@example.test\"}")
chk "register user A" 201 "$c"
ORGA=$(body | python3 -c 'import sys,json; print(json.load(sys.stdin)["user"]["organizationId"])' 2>/dev/null)
code -X POST $API/login -H 'Content-Type: application/json' -d "{\"username\":\"$UA\",\"password\":\"$PASS\"}" >/dev/null
TOKA=$(body | python3 -c 'import sys,json; print(json.load(sys.stdin)["token"])' 2>/dev/null)
echo "  tokenA=${TOKA:0:18}... orgA=$ORGA"

c=$(code -X POST $API/register -H 'Content-Type: application/json' \
  -d "{\"username\":\"$UB\",\"password\":\"$PASS\",\"firstName\":\"Aud\",\"lastName\":\"Beta\",\"recoveryEmail\":\"$UB@example.test\"}")
chk "register user B" 201 "$c"
code -X POST $API/login -H 'Content-Type: application/json' -d "{\"username\":\"$UB\",\"password\":\"$PASS\"}" >/dev/null
TOKB=$(body | python3 -c 'import sys,json; print(json.load(sys.stdin)["token"])' 2>/dev/null)

c=$(code -X POST $API/register -H 'Content-Type: application/json' \
  -d "{\"username\":\"$UA\",\"password\":\"$PASS\",\"firstName\":\"Dup\",\"lastName\":\"Dup\",\"recoveryEmail\":\"d@example.test\"}")
chk "duplicate username rejected" 409 "$c"

c=$(code -X POST $API/register -H 'Content-Type: application/json' -d '{"username":"x"}')
chk "invalid registration rejected" 400 "$c"

echo "== 2. Login =="
c=$(code -X POST $API/login -H 'Content-Type: application/json' -d "{\"username\":\"$UA\",\"password\":\"$PASS\"}")
chk "login user A" 200 "$c"
c=$(code -X POST $API/login -H 'Content-Type: application/json' -d "{\"username\":\"$UA\",\"password\":\"wrongwrong\"}")
chk "bad password rejected" 401 "$c"

echo "== 3. Profile / auth =="
c=$(code $API/profile -H "Authorization: Bearer $TOKA"); chk "profile with token" 200 "$c"
c=$(code $API/profile); chk "profile without token" 401 "$c"
c=$(code $API/profile -H "Authorization: Bearer garbage.token.here"); chk "profile bad token" 401 "$c"

echo "== 4. Organizations =="
c=$(code $API/organizations -H "Authorization: Bearer $TOKA"); chk "list orgs" 200 "$c"
c=$(code $API/organizations/$ORGA/storage -H "Authorization: Bearer $TOKA"); chk "storage summary" 200 "$c"

echo "== 5. Files =="
c=$(code -X POST $API/files -H "Authorization: Bearer $TOKA" -H 'Content-Type: application/json' \
  -d '{"name":"audit-folder","type":"folder"}')
chk "create folder" 201 "$c"
FOLDER=$(body | python3 -c 'import sys,json;d=json.load(sys.stdin);print((d.get("data") or d.get("file") or {}).get("id",""))' 2>/dev/null)
c=$(code -X POST $API/files -H "Authorization: Bearer $TOKA" -H 'Content-Type: application/json' \
  -d "{\"name\":\"audit.txt\",\"type\":\"file\",\"mimeType\":\"text/plain\",\"content\":\"hello audit\",\"parentId\":\"$FOLDER\"}")
chk "create file in folder" 201 "$c"
FILE=$(body | python3 -c 'import sys,json;d=json.load(sys.stdin);print((d.get("data") or d.get("file") or {}).get("id",""))' 2>/dev/null)
echo "  folder=$FOLDER file=$FILE"

c=$(code "$API/files/children?parentId=$FOLDER" -H "Authorization: Bearer $TOKA"); chk "list children" 200 "$c"
c=$(code $API/files/$FILE -H "Authorization: Bearer $TOKA"); chk "get file" 200 "$c"
c=$(code $API/files/$FILE/breadcrumbs -H "Authorization: Bearer $TOKA"); chk "breadcrumbs" 200 "$c"
c=$(code $API/files/$FILE/content -H "Authorization: Bearer $TOKA"); chk "download content" 200 "$c"

echo "== 5b. Cross-tenant isolation =="
c=$(code $API/files/$FILE -H "Authorization: Bearer $TOKB"); chk "user B cannot read A's file" 404 "$c"
c=$(code -X DELETE $API/files/$FILE -H "Authorization: Bearer $TOKB"); chk "user B cannot trash A's file" 404 "$c"

echo "== 6. Search =="
c=$(code "$API/search?q=audit" -H "Authorization: Bearer $TOKA"); chk "search" 200 "$c"

echo "== 7. Trash lifecycle =="
c=$(code -X DELETE $API/files/$FILE -H "Authorization: Bearer $TOKA"); chk "trash file" 200 "$c"
c=$(code $API/files/trash -H "Authorization: Bearer $TOKA"); chk "list trash" 200 "$c"
c=$(code -X PATCH $API/files/$FILE/restore -H "Authorization: Bearer $TOKA"); chk "restore file" 200 "$c"

echo "== 8. Messaging: request flow =="
c=$(code "$API/messaging/users/search?q=$UB" -H "Authorization: Bearer $TOKA")
chk "directory search" 200 "$c"
PEER=$(body | python3 -c 'import sys,json;d=json.load(sys.stdin);u=d.get("users",[]);print(u[0]["id"] if u else "")' 2>/dev/null)
echo "  found peer id=$PEER  (users returned: $(body | python3 -c 'import sys,json;print(len(json.load(sys.stdin).get("users",[])))' 2>/dev/null))"

c=$(code $API/messaging/conversations -H "Authorization: Bearer $TOKA"); chk "conversations empty-listing" 200 "$c"
echo "  conversations for fresh user: $(body)"

if [ -n "$PEER" ]; then
  c=$(code -X POST $API/messaging/requests -H "Authorization: Bearer $TOKA" -H 'Content-Type: application/json' \
    -d "{\"recipientId\":\"$PEER\",\"message\":\"Hi, audit run\"}")
  chk "send chat request" 201 "$c"
  c=$(code -X POST $API/messaging/requests -H "Authorization: Bearer $TOKA" -H 'Content-Type: application/json' \
    -d "{\"recipientId\":\"$PEER\",\"message\":\"duplicate\"}")
  chk "duplicate request blocked" 409 "$c"
  c=$(code -X POST $API/messaging/requests -H "Authorization: Bearer $TOKA" -H 'Content-Type: application/json' \
    -d "{\"recipientId\":\"$PEER\",\"message\":\"$(python3 -c 'print("x"*300)')\"}")
  chk "over-long request note rejected" 400 "$c"

  c=$(code $API/messaging/requests -H "Authorization: Bearer $TOKB"); chk "B lists requests" 200 "$c"
  REQ=$(body | python3 -c 'import sys,json;d=json.load(sys.stdin);r=[x for x in d.get("requests",[]) if x["direction"]=="incoming"];print(r[0]["id"] if r else "")' 2>/dev/null)
  echo "  incoming request id=$REQ"

  c=$(code -X POST $API/messaging/requests/$REQ/respond -H "Authorization: Bearer $TOKB" -H 'Content-Type: application/json' -d '{"action":"accept"}')
  chk "B accepts request" 200 "$c"
  CONV=$(body | python3 -c 'import sys,json;print(json.load(sys.stdin).get("conversationId") or "")' 2>/dev/null)
  echo "  conversation=$CONV"

  c=$(code -X POST $API/messaging/conversations/$CONV/messages -H "Authorization: Bearer $TOKA" -H 'Content-Type: application/json' -d '{"body":"first message"}')
  chk "A sends message" 201 "$c"
  c=$(code $API/messaging/conversations/$CONV/messages -H "Authorization: Bearer $TOKB"); chk "B reads messages" 200 "$c"
  echo "  messages: $(body | python3 -c 'import sys,json;print(len(json.load(sys.stdin).get("messages",[])))' 2>/dev/null)"
  c=$(code -X POST $API/messaging/conversations/$CONV/read -H "Authorization: Bearer $TOKB"); chk "B marks read" 200 "$c"
  c=$(code $API/messaging/conversations/$CONV/messages -H "Authorization: Bearer $TOKA"); chk "A reads own conversation" 200 "$c"
fi

echo "== 9. Notifications / audit / meetings =="
c=$(code $API/notifications -H "Authorization: Bearer $TOKA"); chk "notifications" 200 "$c"
c=$(code $API/audit-logs -H "Authorization: Bearer $TOKA"); chk "audit logs" 200 "$c"
c=$(code $API/meetings -H "Authorization: Bearer $TOKA"); chk "meetings list" 200 "$c"

echo "== 10. Mail =="
c=$(code $API/mail/inbox -H "Authorization: Bearer $TOKA"); chk "mail inbox" 200 "$c"

echo
echo "RESULT: $pass passed, $fail failed"
rm -f /tmp/body.$$
[ $fail -eq 0 ]
