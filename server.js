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

			default:
				send(socket, { type: 'error', message: 'Unknown message type: ' + msg.type });
		}
	});

	socket.on('close', () => {
		if (socket.roomCode) {
			closeRoom(socket.roomCode, 'opponent_disconnected');
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
