// relay-server/server.js
//
// Tiny WebSocket relay for Keys Learning's "ONLINE" 1v1 mode. Pairs two
// clients by a short room code and forwards messages between them -
// it never looks at match content (word lists, progress, timings), it
// just relays whatever payload the two Godot clients send each other.
//
// Protocol (matches scripts/InternetMultiplayerManager.gd exactly):
//
//   Client -> Server
//     { type: "host" }
//     { type: "join", code }
//     { type: "rejoin", code, role }        role: "host" | "guest"
//     { type: "relay", payload }            payload passed through as-is
//
//   Server -> Client
//     { type: "hosting", code }             host only, room created
//     { type: "matched" }                   sent to BOTH sides once paired
//     { type: "join_failed", reason }       reason: "not_found" | "room_full" | "bad_code"
//     { type: "rejoin_failed", reason }     reason: "not_found" | "expired" | "slot_taken"
//     { type: "opponent_left" }
//     { type: "relay", payload }            forwarded from the other peer
//     { type: "error", reason }             malformed/unknown message
//
// Deploy: this is a plain Node process reading PORT from the environment
// (Render, Railway, Fly.io, etc. all set this automatically). Requires
// only the "ws" package - see package.json.
//
//   npm install
//   npm start
//
// Point InternetMultiplayerManager.gd's SERVER_URL at wss://<your-host>
// once deployed. Use ws:// only for local testing against 127.0.0.1.

const http = require('http');
const { WebSocketServer } = require('ws');

const PORT = process.env.PORT || 8080;

// How long a room stays reservable after one side drops, before it's
// torn down for good. Matches the 45s window InternetMultiplayerManager.gd's
// comments already promise to callers (rejoin_match()).
const RECONNECT_GRACE_MS = 45000;

// How often to ping every open socket, and how long to wait for a pong
// before treating a connection as dead. Needed because a phone locking
// its screen or losing signal often doesn't send a clean TCP close -
// without this, a stale peer would just look silently unresponsive
// forever instead of freeing up its room slot.
const HEARTBEAT_INTERVAL_MS = 30000;

// Room codes are short and easy to read aloud/text - deliberately
// excludes visually-ambiguous characters (0/O, 1/I/L).
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const CODE_LENGTH = 5;

/** @type {Map<string, Room>} */
const rooms = new Map();

/**
 * @typedef {Object} Room
 * @property {WebSocket|null} host
 * @property {WebSocket|null} guest
 * @property {number|null} hostDisconnectedAt
 * @property {number|null} guestDisconnectedAt
 * @property {NodeJS.Timeout|null} cleanupTimer
 */

function generateRoomCode() {
	let code;
	do {
		code = '';
		for (let i = 0; i < CODE_LENGTH; i++) {
			code += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
		}
	} while (rooms.has(code));
	return code;
}

function send(ws, msg) {
	if (ws && ws.readyState === ws.OPEN) {
		ws.send(JSON.stringify(msg));
	}
}

function otherRole(role) {
	return role === 'host' ? 'guest' : 'host';
}

/** True once both seats are filled with live (not-disconnected) sockets. */
function isRoomFull(room) {
	return (
		room.host && room.hostDisconnectedAt === null &&
		room.guest && room.guestDisconnectedAt === null
	);
}

function clearCleanupTimer(room) {
	if (room.cleanupTimer) {
		clearTimeout(room.cleanupTimer);
		room.cleanupTimer = null;
	}
}

/** Schedules a room for deletion after the reconnect grace window, unless something cancels it first (a fresh rejoin). */
function scheduleCleanup(code, room) {
	clearCleanupTimer(room);
	room.cleanupTimer = setTimeout(() => {
		// Only actually delete if nobody reconnected into either seat.
		const stillAbandoned =
			(!room.host || room.hostDisconnectedAt !== null) &&
			(!room.guest || room.guestDisconnectedAt !== null);
		if (stillAbandoned) {
			rooms.delete(code);
		}
	}, RECONNECT_GRACE_MS);
}

function handleHost(ws) {
	const code = generateRoomCode();
	/** @type {Room} */
	const room = {
		host: ws,
		guest: null,
		hostDisconnectedAt: null,
		guestDisconnectedAt: null,
		cleanupTimer: null,
	};
	rooms.set(code, room);

	ws.roomCode = code;
	ws.role = 'host';
	send(ws, { type: 'hosting', code });
}

function handleJoin(ws, msg) {
	const code = String(msg.code || '').toUpperCase().trim();
	if (code.length === 0) {
		send(ws, { type: 'join_failed', reason: 'bad_code' });
		return;
	}

	const room = rooms.get(code);
	if (!room) {
		send(ws, { type: 'join_failed', reason: 'not_found' });
		return;
	}
	if (room.guest && room.guestDisconnectedAt === null) {
		send(ws, { type: 'join_failed', reason: 'room_full' });
		return;
	}

	room.guest = ws;
	room.guestDisconnectedAt = null;
	ws.roomCode = code;
	ws.role = 'guest';

	if (isRoomFull(room)) {
		clearCleanupTimer(room);
		send(room.host, { type: 'matched' });
		send(room.guest, { type: 'matched' });
	}
}

function handleRejoin(ws, msg) {
	const code = String(msg.code || '').toUpperCase().trim();
	const role = msg.role === 'guest' ? 'guest' : 'host';

	const room = rooms.get(code);
	if (!room) {
		send(ws, { type: 'rejoin_failed', reason: 'not_found' });
		return;
	}

	const seatIsFree = role === 'host'
		? (room.host === null || room.hostDisconnectedAt !== null)
		: (room.guest === null || room.guestDisconnectedAt !== null);

	if (!seatIsFree) {
		send(ws, { type: 'rejoin_failed', reason: 'slot_taken' });
		return;
	}

	if (role === 'host') {
		room.host = ws;
		room.hostDisconnectedAt = null;
	} else {
		room.guest = ws;
		room.guestDisconnectedAt = null;
	}
	ws.roomCode = code;
	ws.role = role;

	if (isRoomFull(room)) {
		clearCleanupTimer(room);
		send(room.host, { type: 'matched' });
		send(room.guest, { type: 'matched' });
	}
	// If the other side hasn't reconnected yet, just silently hold this
	// seat - "matched" fires once both are back, same as a fresh pairing.
}

function handleRelay(ws, msg) {
	const room = rooms.get(ws.roomCode);
	if (!room || !ws.role) return;

	const targetRole = otherRole(ws.role);
	const target = room[targetRole];
	send(target, { type: 'relay', payload: msg.payload });
}

function handleDisconnect(ws) {
	const room = rooms.get(ws.roomCode);
	if (!room || !ws.role) return;

	if (ws.role === 'host' && room.host === ws) {
		room.hostDisconnectedAt = Date.now();
	} else if (ws.role === 'guest' && room.guest === ws) {
		room.guestDisconnectedAt = Date.now();
	} else {
		return; // stale socket, already replaced by a rejoin
	}

	const other = room[otherRole(ws.role)];
	send(other, { type: 'opponent_left' });

	scheduleCleanup(ws.roomCode, room);
}

// --- HTTP + WebSocket server setup -------------------------------------

const httpServer = http.createServer((req, res) => {
	// Plain health check so Render/uptime pings don't need a WS handshake,
	// and so you can sanity-check a deploy by just visiting the URL.
	res.writeHead(200, { 'Content-Type': 'text/plain' });
	res.end('keys-learning relay server: ok\n');
});

const wss = new WebSocketServer({ server: httpServer });

wss.on('connection', (ws) => {
	ws.isAlive = true;
	ws.roomCode = null;
	ws.role = null;

	ws.on('pong', () => {
		ws.isAlive = true;
	});

	ws.on('message', (data) => {
		let msg;
		try {
			msg = JSON.parse(data.toString());
		} catch (e) {
			send(ws, { type: 'error', reason: 'bad_json' });
			return;
		}
		if (typeof msg !== 'object' || msg === null || typeof msg.type !== 'string') {
			send(ws, { type: 'error', reason: 'bad_message' });
			return;
		}

		switch (msg.type) {
			case 'host':
				handleHost(ws);
				break;
			case 'join':
				handleJoin(ws, msg);
				break;
			case 'rejoin':
				handleRejoin(ws, msg);
				break;
			case 'relay':
				handleRelay(ws, msg);
				break;
			default:
				send(ws, { type: 'error', reason: 'unknown_type' });
		}
	});

	ws.on('close', () => {
		handleDisconnect(ws);
	});

	ws.on('error', () => {
		// 'close' still fires after 'error' for ws sockets, so cleanup
		// happens there - nothing additional needed here.
	});
});

// Drops dead connections (phone locked, wifi dropped without a clean
// close, etc.) so their room slot frees up via the normal 'close' path
// instead of sitting as a ghost until the OS eventually notices.
const heartbeat = setInterval(() => {
	wss.clients.forEach((ws) => {
		if (ws.isAlive === false) {
			ws.terminate();
			return;
		}
		ws.isAlive = false;
		ws.ping();
	});
}, HEARTBEAT_INTERVAL_MS);

wss.on('close', () => {
	clearInterval(heartbeat);
});

httpServer.listen(PORT, () => {
	console.log(`Keys Learning relay server listening on port ${PORT}`);
});
