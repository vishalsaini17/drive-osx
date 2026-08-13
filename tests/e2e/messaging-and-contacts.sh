#!/usr/bin/env bash
# Cross-organization messaging + contacts + presence, end to end.
# Two users registered independently => two separate personal organizations.
API=http://localhost:3001/api/v1
S=$RANDOM$RANDOM
UA=msg_a_$S
UB=msg_b_$S
UC=msg_c_$S
PASS='Sup3rSecret!pw'

pass=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "  PASS  $1 ($3)"; pass=$((pass+1));
        else echo "  FAIL  $1 (expected $2, got $3)"; fail=$((fail+1)); fi }
code() { curl -s -o /tmp/mb.$$ -w '%{http_code}' "$@"; }
body() { cat /tmp/mb.$$; }
jq_() { body | python3 -c "import sys,json;d=json.load(sys.stdin);$1" 2>/dev/null; }

reg() { # reg <username> -> echoes token
  code -X POST $API/register -H 'Content-Type: application/json' \
    -d "{\"username\":\"$1\",\"password\":\"$PASS\",\"firstName\":\"Msg\",\"lastName\":\"${1: -4}\",\"recoveryEmail\":\"$1@example.test\"}" >/dev/null
  local org; org=$(jq_ 'print(d["user"]["organizationId"])')
  code -X POST $API/login -H 'Content-Type: application/json' \
    -d "{\"username\":\"$1\",\"password\":\"$PASS\"}" >/dev/null
  echo "$(jq_ 'print(d["token"])')|$org"
}

echo "== setup: three independent registrations =="
IFS='|' read -r TOKA ORGA <<< "$(reg $UA)"
IFS='|' read -r TOKB ORGB <<< "$(reg $UB)"
IFS='|' read -r TOKC ORGC <<< "$(reg $UC)"
echo "  orgA=$ORGA"
echo "  orgB=$ORGB"
if [ "$ORGA" != "$ORGB" ]; then echo "  PASS  users are in different organizations"; pass=$((pass+1));
else echo "  FAIL  users share an organization - test is not exercising the bug"; fail=$((fail+1)); fi

echo "== TASK-001: exact-username lookup crosses organizations =="
c=$(code "$API/messaging/users/search?q=$UB" -H "Authorization: Bearer $TOKA"); chk "search responds" 200 "$c"
N=$(jq_ 'print(len(d["users"]))')
chk "exact username found across orgs" 1 "$N"
PEER=$(jq_ 'print(d["users"][0]["id"] if d["users"] else "")')

c=$(code "$API/messaging/users/search?q=$(echo $UB | tr a-z A-Z)" -H "Authorization: Bearer $TOKA")
chk "exact lookup is case-insensitive" 1 "$(jq_ 'print(len(d["users"]))')"

c=$(code "$API/messaging/users/search?q=$UB@driveosx.com" -H "Authorization: Bearer $TOKA")
chk "exact email also resolves" 1 "$(jq_ 'print(len(d["users"]))')"

echo "== TASK-001: substring search does NOT enumerate other tenants =="
c=$(code "$API/messaging/users/search?q=msg_" -H "Authorization: Bearer $TOKA")
N=$(jq_ 'print(len(d["users"]))')
chk "substring across foreign orgs returns nothing" 0 "$N"
c=$(code "$API/messaging/users/search?q=$UA" -H "Authorization: Bearer $TOKA")
chk "self excluded from own results" 0 "$(jq_ 'print(len(d["users"]))')"

echo "== chat request flow across organizations =="
c=$(code -X POST $API/messaging/requests -H "Authorization: Bearer $TOKA" -H 'Content-Type: application/json' \
  -d "{\"recipientId\":\"$PEER\",\"message\":\"Cross-org hello\"}")
chk "A sends request to B" 201 "$c"
c=$(code -X POST $API/messaging/requests -H "Authorization: Bearer $TOKA" -H 'Content-Type: application/json' \
  -d "{\"recipientId\":\"$PEER\",\"message\":\"dupe\"}")
chk "duplicate blocked" 409 "$c"

echo "== TASK-002a: recipient in another org can SEE the request =="
c=$(code $API/messaging/requests -H "Authorization: Bearer $TOKB"); chk "B lists requests" 200 "$c"
NIN=$(jq_ 'print(len([x for x in d["requests"] if x["direction"]=="incoming"]))')
chk "B sees the incoming request" 1 "$NIN"
REQ=$(jq_ 'r=[x for x in d["requests"] if x["direction"]=="incoming"];print(r[0]["id"] if r else "")')

echo "== messaging is gated before acceptance =="
c=$(code $API/messaging/conversations -H "Authorization: Bearer $TOKB")
chk "B has no conversation yet" 0 "$(jq_ 'print(len(d["conversations"]))')"

echo "== acceptance =="
c=$(code -X POST $API/messaging/requests/$REQ/respond -H "Authorization: Bearer $TOKB" -H 'Content-Type: application/json' -d '{"action":"accept"}')
chk "B accepts" 200 "$c"
CONV=$(jq_ 'print(d.get("conversationId") or "")')

echo "== TASK-002b: BOTH sides see the conversation =="
c=$(code $API/messaging/conversations -H "Authorization: Bearer $TOKA")
chk "A sees 1 conversation" 1 "$(jq_ 'print(len(d["conversations"]))')"
c=$(code $API/messaging/conversations -H "Authorization: Bearer $TOKB")
chk "B sees 1 conversation (was 0 before fix)" 1 "$(jq_ 'print(len(d["conversations"]))')"

echo "== messages both ways =="
c=$(code -X POST $API/messaging/conversations/$CONV/messages -H "Authorization: Bearer $TOKA" -H 'Content-Type: application/json' -d '{"body":"from A"}')
chk "A sends" 201 "$c"
c=$(code -X POST $API/messaging/conversations/$CONV/messages -H "Authorization: Bearer $TOKB" -H 'Content-Type: application/json' -d '{"body":"from B"}')
chk "B replies" 201 "$c"
c=$(code $API/messaging/conversations/$CONV/messages -H "Authorization: Bearer $TOKB")
chk "B reads both messages" 2 "$(jq_ 'print(len(d["messages"]))')"

echo "== outsider cannot reach the conversation =="
c=$(code $API/messaging/conversations/$CONV/messages -H "Authorization: Bearer $TOKC")
chk "C blocked from reading" 403 "$c"
c=$(code -X POST $API/messaging/conversations/$CONV/messages -H "Authorization: Bearer $TOKC" -H 'Content-Type: application/json' -d '{"body":"intrusion"}')
chk "C blocked from posting" 403 "$c"
c=$(code $API/messaging/conversations -H "Authorization: Bearer $TOKC")
chk "C sees no conversations" 0 "$(jq_ 'print(len(d["conversations"]))')"

echo "== TASK-005: contacts auto-created by acceptance, readable via API =="
c=$(code $API/contacts -H "Authorization: Bearer $TOKA"); chk "A lists contacts" 200 "$c"
chk "A has B as a contact" 1 "$(jq_ 'print(len(d["contacts"]))')"
chk "contact source recorded" chat_request "$(jq_ 'print(d["contacts"][0]["source"])')"
c=$(code $API/contacts -H "Authorization: Bearer $TOKB")
chk "B has A as a contact (both sides)" 1 "$(jq_ 'print(len(d["contacts"]))')"
c=$(code $API/contacts -H "Authorization: Bearer $TOKC")
chk "C has no contacts (no fabricated seed data)" 0 "$(jq_ 'print(len(d["contacts"]))')"

echo "== contacts CRUD =="
c=$(code -X POST $API/contacts -H "Authorization: Bearer $TOKC" -H 'Content-Type: application/json' \
  -d '{"displayName":"External Person","email":"ext@elsewhere.example","company":"Elsewhere Ltd"}')
chk "create external contact" 201 "$c"
CID=$(jq_ 'print(d["contact"]["id"])')
chk "external contact has no presence" None "$(jq_ 'print(d["contact"]["presence"])')"
c=$(code -X PATCH $API/contacts/$CID -H "Authorization: Bearer $TOKC" -H 'Content-Type: application/json' -d '{"isFavourite":true,"jobTitle":"Buyer"}')
chk "update contact" 200 "$c"
chk "favourite persisted" True "$(jq_ 'print(d["contact"]["isFavourite"])')"
c=$(code "$API/contacts?search=Elsewhere" -H "Authorization: Bearer $TOKC")
chk "search by company" 1 "$(jq_ 'print(len(d["contacts"]))')"
c=$(code $API/contacts/$CID -H "Authorization: Bearer $TOKA")
chk "another user cannot read that contact" 404 "$c"
c=$(code -X DELETE $API/contacts/$CID -H "Authorization: Bearer $TOKA")
chk "another user cannot delete it" 404 "$c"
c=$(code -X DELETE $API/contacts/$CID -H "Authorization: Bearer $TOKC")
chk "owner deletes it" 200 "$c"

echo "== save-to-contacts from Messenger =="
c=$(code -X POST $API/contacts -H "Authorization: Bearer $TOKC" -H 'Content-Type: application/json' -d "{\"contactUserId\":\"$PEER\"}")
chk "save a platform user" 201 "$c"
c=$(code -X POST $API/contacts -H "Authorization: Bearer $TOKC" -H 'Content-Type: application/json' -d "{\"contactUserId\":\"$PEER\"}")
chk "saving twice is idempotent" 201 "$c"
c=$(code $API/contacts -H "Authorization: Bearer $TOKC")
chk "still exactly one contact" 1 "$(jq_ 'print(len(d["contacts"]))')"

echo "== presence =="
c=$(code -X POST $API/contacts/presence/heartbeat -H "Authorization: Bearer $TOKB" -H 'Content-Type: application/json' -d '{"status":"online","statusText":"Working"}')
chk "B heartbeat" 200 "$c"
c=$(code $API/contacts -H "Authorization: Bearer $TOKA")
chk "A sees B online" online "$(jq_ 'print(d["contacts"][0]["presence"])')"
chk "A sees B status text" Working "$(jq_ 'print(d["contacts"][0]["statusText"])')"
c=$(code -X POST $API/contacts/presence/offline -H "Authorization: Bearer $TOKB")
chk "B signs off" 200 "$c"
c=$(code $API/contacts -H "Authorization: Bearer $TOKA")
chk "A sees B offline" offline "$(jq_ 'print(d["contacts"][0]["presence"])')"
c=$(code -X POST $API/contacts/presence/lookup -H "Authorization: Bearer $TOKA" -H 'Content-Type: application/json' -d "{\"userIds\":[\"$PEER\"]}")
chk "presence lookup" 200 "$c"

echo "== TASK-004: chat events produce notifications =="
sleep 2
c=$(code $API/notifications -H "Authorization: Bearer $TOKB"); chk "B lists notifications" 200 "$c"
HASREQ=$(jq_ 'print("yes" if any(n.get("type")=="chat.request_received" for n in d.get("notifications",d if isinstance(d,list) else [])) else "no")')
chk "B was notified of the chat request" yes "$HASREQ"
c=$(code $API/notifications -H "Authorization: Bearer $TOKA")
HASACC=$(jq_ 'print("yes" if any(n.get("type")=="chat.request_accepted" for n in d.get("notifications",d if isinstance(d,list) else [])) else "no")')
chk "A was notified of the acceptance" yes "$HASACC"
HASMSG=$(jq_ 'print("yes" if any(n.get("type")=="chat.message" for n in d.get("notifications",d if isinstance(d,list) else [])) else "no")')
chk "A was notified of B's message" yes "$HASMSG"

echo "== TASK-012: meetings collection endpoint =="
c=$(code $API/meetings -H "Authorization: Bearer $TOKA"); chk "GET /meetings" 200 "$c"
c=$(code "$API/meetings?limit=5&status=scheduled" -H "Authorization: Bearer $TOKA"); chk "GET /meetings filtered" 200 "$c"

echo
echo "RESULT: $pass passed, $fail failed"
rm -f /tmp/mb.$$
[ $fail -eq 0 ]
