// Keys Learning — online versus relay server
// ---------------------------------------------------------------
// What this does, in plain terms:
//   Two phones on different networks usually can't connect directly to
//   each other (that's why LanVersusMode only works on the same WiFi).
//   This server sits in the middle: both players connect to IT, and it
//   just forwards messages between the two of them. It has zero game
//   logic — no word lists, no scoring, no rules. It only does two jobs:
//     1. Pair up a "host" and a "guest" using a short room code.
//     2. Relay whatever bytes one side sends to the other side.
//
// *** EXPERIMENTAL / UNVERIFIED ***
// This has not been run against a live deploy or tested with two real
// devices in this environment (no network access here). The protocol
// and room-code logic are correct to the best of my knowledge of the
// 'ws' library and WebSocket semantics, but give it a real two-device
// test pass after deploying before trusting it in front of players.
//
// ---------------------------------------------------------------
// HOW TO RUN THIS LOCALLY (to sanity-check it before deploying):
//   1. Install Node.js (v18+) from nodejs.org if you don't have it.
//   2. In this folder, run:  npm install
//   3. Run:  npm start
//   4. It listens on ws://localhost:8080 by default.
//
// HOW TO DEPLOY IT (so real phones on real internet can reach it):
//   Easiest option — Railway.app or Fly.io. Both let you push this
//   folder and get a public wss:// URL back, without managing a server
//   yourself. Steps are roughly:
//     - Create an account, install their CLI (`railway` or `flyctl`).
//     - Run their "init"/"launch" command in this folder.
//     - Deploy. They give you a URL like wss://your-app.up.railway.app
//       or wss://your-app.fly.dev — that's what goes into the Godot
//       client's SERVER_URL.
//   Both platforms auto-provide TLS, which is why the client connects
//   with "wss://" (secure) instead of "ws://".
// ---------------------------------------------------------------

const WebSocket = require('ws');

const PORT = process.env.PORT || 8080;
const wss = new WebSocket.Server({ port: PORT });

// How long a room can sit open with no guest before it's discarded.
const ROOM_TIMEOUT_MS = 10 * 60 * 1000; // 10 minutes

// How long a room stays reserved after ONE side disconnects mid-match,
// giving them a window to reconnect with the same room code instead of
// the other player being stuck waiting on a room that's gone forever.
const RECONNECT_GRACE_MS = 45 * 1000; // 45 seconds

// How often we ping every connected client. Most reverse proxies /
// load balancers (including the ones Railway/Fly put in front of your
// app) will silently close a WebSocket that's been idle too long
// (commonly ~60s). A period 25s heartbeat keeps connections alive
// through a real match, which can easily run longer than that.
const HEARTBEAT_INTERVAL_MS = 25 * 1000;

// room code -> { hostSocket, guestSocket, createdAt, timeout }
const rooms = new Map();

// Characters chosen to avoid visual confusion when read aloud/typed:
// no 0/O, no 1/I/l.
const CODE_CHARS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

function generateRoomCode() {
	let code;
	do {
		code = '';
		for (let i = 0; i < 4; i++) {
			code += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
		}
	} while (rooms.has(code));
	return code;
}

function send(socket, obj) {
	if (socket && socket.readyState === WebSocket.OPEN) {
		socket.send(JSON.stringify(obj));
	}
}

function closeRoom(code, reason) {
	const room = rooms.get(code);
	if (!room) return;
	clearTimeout(room.timeout);
	clearTimeout(room.hostGraceTimeout);
	clearTimeout(room.guestGraceTimeout);
	if (room.hostSocket) {
		room.hostSocket.roomCode = null;
		send(room.hostSocket, { type: 'opponent_left', reason });
	}
	if (room.guestSocket) {
		room.guestSocket.roomCode = null;
		send(room.guestSocket, { type: 'opponent_left', reason });
	}
	rooms.delete(code);
}

// Called when ONE side of a room disconnects. Rather than destroying the
// whole room immediately (which would strand the other player with a
// dead room code), this clears just that side's socket slot and starts
// a grace-period timer. If the disconnected player reconnects with a
// "rejoin" message using the same code within that window, they get
// reattached to the same room. If the window expires first, the room
// is fully closed via closeRoom().
function handleSideDisconnect(code, role) {
	const room = rooms.get(code);
	if (!room) return;

	const otherRole = role === 'host' ? 'guest' : 'host';
	const otherSocket = room[otherRole + 'Socket'];

	room[role + 'Socket'] = null;

	// If the room never actually got matched (e.g. host alone, no guest
	// ever joined), there's no "other side" to notify and no reconnect
	// scenario worth preserving - just tear it down.
	if (!otherSocket) {
		closeRoom(code, 'opponent_disconnected');
		return;
	}

	send(otherSocket, { type: 'opponent_left', reason: 'opponent_disconnected_temporarily' });

	const graceTimeoutKey = role + 'GraceTimeout';
	room[graceTimeoutKey] = setTimeout(() => {
		// Grace period expired with nobody reconnecting into this slot -
		// now actually close the room for good.
		closeRoom(code, 'reconnect_window_expired');
	}, RECONNECT_GRACE_MS);
}

wss.on('connection', (socket) => {
	socket.isAlive = true;
	socket.roomCode = null;
	socket.role = null; // 'host' or 'guest'

	socket.on('pong', () => { socket.isAlive = true; });

	socket.on('message', (raw) => {
		let msg;
		try {
			msg = JSON.parse(raw.toString());
		} catch (e) {
			send(socket, { type: 'error', message: 'Malformed message' });
			return;
		}

		switch (msg.type) {

			case 'host': {
				// Player wants to open a new room and get a code to share.
				const code = generateRoomCode();
				socket.roomCode = code;
				socket.role = 'host';

				const timeout = setTimeout(() => {
					closeRoom(code, 'timed_out_waiting_for_guest');
				}, ROOM_TIMEOUT_MS);

				rooms.set(code, {
					hostSocket: socket,
					guestSocket: null,
					createdAt: Date.now(),
					timeout,
				});

				send(socket, { type: 'hosting', code });
				break;
			}

			case 'join': {
				// Player wants to join an existing room by code.
				const code = (msg.code || '').toUpperCase().trim();
				const room = rooms.get(code);

				if (!room) {
					send(socket, { type: 'join_failed', reason: 'not_found' });
					return;
				}
				if (room.guestSocket) {
					send(socket, { type: 'join_failed', reason: 'room_full' });
					return;
				}

				clearTimeout(room.timeout);
				room.guestSocket = socket;
				socket.roomCode = code;
				socket.role = 'guest';

				send(room.hostSocket, { type: 'matched', role: 'host' });
				send(socket, { type: 'matched', role: 'guest' });
				break;
			}

			case 'relay': {
				// Forward the payload verbatim to whichever socket is the
				// other half of this room. This server never looks inside
				// payload — that's game-specific content owned by the
				// Godot client (match_start / progress / finished, etc).
				const room = rooms.get(socket.roomCode);
				if (!room) return;
				const other = socket.role === 'host' ? room.guestSocket : room.hostSocket;
				send(other, { type: 'relay', payload: msg.payload });
				break;
			}

			case 'rejoin': {
				// Reconnecting into a room this socket's previous connection
				// was already part of, using the same code and the same
				// role it had before disconnecting.
				const code = (msg.code || '').toUpperCase().trim();
				const role = msg.role === 'host' ? 'host' : (msg.role === 'guest' ? 'guest' : null);
				const room = rooms.get(code);

				if (!room || !role) {
					send(socket, { type: 'rejoin_failed', reason: 'not_found' });
					return;
				}
				if (room[role + 'Socket']) {
					// That slot is already occupied by a live connection -
					// either someone else is already reconnected there, or
					// this is a stale duplicate rejoin attempt.
					send(socket, { type: 'rejoin_failed', reason: 'slot_occupied' });
					return;
				}

				clearTimeout(room[role + 'GraceTimeout']);
				room[role + 'Socket'] = socket;
				socket.roomCode = code;
				socket.role = role;

				const otherRole = role === 'host' ? 'guest' : 'host';
				const otherSocket = room[otherRole + 'Socket'];

				send(socket, { type: 'matched', role });
				if (otherSocket) {
					send(otherSocket, { type: 'matched', role: otherRole });
				}
				break;
			}

			default:
				send(socket, { type: 'error', message: 'Unknown message type: ' + msg.type });
		}
	});

	socket.on('close', () => {
		if (socket.roomCode && socket.role) {
			handleSideDisconnect(socket.roomCode, socket.role);
		}
	});
});

// Heartbeat: ping every open connection periodically, and drop anything
// that didn't answer the previous ping (a stale/dead connection that
// didn't cleanly fire a close event).
const heartbeat = setInterval(() => {
	wss.clients.forEach((socket) => {
		if (socket.isAlive === false) {
			return socket.terminate();
		}
		socket.isAlive = false;
		socket.ping();
	});
}, HEARTBEAT_INTERVAL_MS);

wss.on('close', () => clearInterval(heartbeat));

console.log(`Relay server listening on port ${PORT}`);
