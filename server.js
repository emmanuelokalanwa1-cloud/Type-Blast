// Type Blast — online relay server
//
// Deploy this whole file to your existing Render service (replace your
// current server.js with it). It does TWO things over one WebSocket
// endpoint:
//
//   1) 1v1 ONLINE VERSUS relay — unchanged protocol, matches what
//      InternetMultiplayerManager.gd already speaks (host/join/rejoin,
//      4-char room codes, "relay" envelope for match_start/progress/
//      finished).
//
//   2) ONLINE TOURNAMENT — new. A host creates a tournament lobby with a
//      short code, other players join with that code, the host starts
//      it, and the server builds a single-elimination bracket, pairs
//      players round by round, generates the word list for every match
//      itself (so both racers always get an identical list with zero
//      client-side coordination), decides winners, and pushes live
//      bracket updates to everyone in the tournament (including players
//      who are waiting or already eliminated, so they can spectate).
//
// No database — everything lives in memory. That's fine for this use
// case (tournaments are short-lived), but it does mean a Render restart
// / free-tier spin-down wipes any tournament in progress, same as it
// already wipes any 1v1 room in progress today.
//
// --- Deploy notes ---
// package.json needs: { "dependencies": { "ws": "^8.18.0" } }
// Start command: node server.js
// Render sets process.env.PORT for you automatically.

const http = require("http");
const { WebSocketServer, WebSocket } = require("ws");

const PORT = process.env.PORT || 10000;

// Room/tournament codes avoid visually-ambiguous characters (0/O, 1/I/L).
const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const CODE_LENGTH = 4;

// How long a room/tournament seat stays reserved after a disconnect so
// rejoin_match() / tournament_rejoin can reclaim it (dropped wifi, app
// backgrounded, Render free-tier cold start, etc).
const RECONNECT_GRACE_MS = 45_000;

// If a player goes silent mid-tournament-match (drops and never comes
// back, or the app just dies) for this long, their opponent is awarded
// the match by forfeit so the bracket isn't stuck forever.
const MATCH_FORFEIT_MS = 90_000;

const WORDS_PER_MATCH = 15;

// Small built-in word pool so the server can generate identical word
// lists for both racers in a tournament match without needing anything
// from the Godot project's WordBank. Deliberately simple, common,
// typing-practice-friendly words.
const WORD_POOL = [
  "apple", "bridge", "candle", "dolphin", "eagle", "forest", "garden", "harbor",
  "island", "jungle", "kitten", "lantern", "meadow", "nectar", "ocean", "pencil",
  "quartz", "rabbit", "sunset", "temple", "umbrella", "valley", "window", "yellow",
  "zebra", "anchor", "breeze", "canyon", "desert", "engine", "falcon", "glacier",
  "hunter", "ivory", "jacket", "kettle", "ladder", "mirror", "nickel", "orange",
  "planet", "quiver", "river", "saddle", "tunnel", "unicorn", "velvet", "walnut",
  "arrow", "basket", "castle", "dagger", "empire", "feather", "goblin", "helmet",
  "insect", "jewel", "knight", "legend", "marble", "needle", "oyster", "puzzle",
  "quest", "ribbon", "sailor", "thunder", "utility", "voyage", "wizard", "yogurt",
  "acorn", "blanket", "cactus", "diamond", "echo", "fossil", "gravel", "horizon",
  "iceberg", "journey", "kernel", "lagoon", "mystery", "nomad", "olive", "pirate",
  "quarry", "rocket", "shadow", "trumpet", "utopia", "vapor", "whistle", "xenon",
  "yacht", "zenith", "amber", "bandit", "cinder", "dragon", "ember", "frost",
  "glimmer", "harvest", "impulse", "jester", "kingdom", "labyrinth", "mirage", "nova",
  "oracle", "phantom", "quicksand", "ruby", "storm", "twilight", "ultra", "vortex",
];

function randomWord() {
  return WORD_POOL[Math.floor(Math.random() * WORD_POOL.length)];
}

function generateWordList(count) {
  const list = [];
  for (let i = 0; i < count; i++) list.push(randomWord());
  return list;
}

function randomCode(existingCodes) {
  let code;
  do {
    code = "";
    for (let i = 0; i < CODE_LENGTH; i++) {
      code += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
    }
  } while (existingCodes.has(code));
  return code;
}

function randomId() {
  return Math.random().toString(36).slice(2, 10);
}

function send(ws, obj) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(obj));
  }
}

// ============================================================
// 1) 1v1 ONLINE VERSUS RELAY
// ============================================================

// code -> { host, guest, hostSeat, guestSeat, hostDisconnectTimer, guestDisconnectTimer }
// host/guest are WebSocket instances or null while disconnected-but-in-grace.
const rooms = new Map();

function destroyRoom(code) {
  const room = rooms.get(code);
  if (!room) return;
  if (room.hostDisconnectTimer) clearTimeout(room.hostDisconnectTimer);
  if (room.guestDisconnectTimer) clearTimeout(room.guestDisconnectTimer);
  rooms.delete(code);
}

function handleHost(ws, meta) {
  const code = randomCode(rooms);
  rooms.set(code, {
    host: ws,
    guest: null,
    hostDisconnectTimer: null,
    guestDisconnectTimer: null,
  });
  meta.mode = "versus";
  meta.role = "host";
  meta.roomCode = code;
  send(ws, { type: "hosting", code });
}

function handleJoin(ws, meta, code) {
  const room = rooms.get(code);
  if (!room) {
    send(ws, { type: "join_failed", reason: "not_found" });
    return;
  }
  if (room.guest) {
    send(ws, { type: "join_failed", reason: "room_full" });
    return;
  }
  room.guest = ws;
  meta.mode = "versus";
  meta.role = "guest";
  meta.roomCode = code;
  send(ws, { type: "matched" });
  if (room.host) send(room.host, { type: "matched" });
}

function handleRejoin(ws, meta, code, role) {
  const room = rooms.get(code);
  if (!room) {
    send(ws, { type: "rejoin_failed", reason: "not_found" });
    return;
  }
  if (role === "host") {
    if (room.hostDisconnectTimer) {
      clearTimeout(room.hostDisconnectTimer);
      room.hostDisconnectTimer = null;
    }
    room.host = ws;
  } else {
    if (room.guestDisconnectTimer) {
      clearTimeout(room.guestDisconnectTimer);
      room.guestDisconnectTimer = null;
    }
    room.guest = ws;
  }
  meta.mode = "versus";
  meta.role = role;
  meta.roomCode = code;
  send(ws, { type: "matched" });
  const other = role === "host" ? room.guest : room.host;
  if (other) send(other, { type: "matched" });
}

function handleVersusRelay(ws, meta, payload) {
  const room = rooms.get(meta.roomCode);
  if (!room) return;
  const other = meta.role === "host" ? room.guest : room.host;
  if (other) send(other, { type: "relay", payload });
}

function handleVersusDisconnect(ws, meta) {
  const room = rooms.get(meta.roomCode);
  if (!room) return;
  const isHost = meta.role === "host";
  if (isHost) room.host = null; else room.guest = null;

  const other = isHost ? room.guest : room.host;
  if (other) send(other, { type: "opponent_left" });

  const timer = setTimeout(() => {
    // Still gone after the grace window -> free the code for reuse.
    destroyRoom(meta.roomCode);
  }, RECONNECT_GRACE_MS);
  if (isHost) room.hostDisconnectTimer = timer; else room.guestDisconnectTimer = timer;
}

// ============================================================
// 2) ONLINE TOURNAMENT
// ============================================================

// code -> tournament object (see shape below)
const tournaments = new Map();

// playerId -> { code, ws, forfeitTimer }  (quick lookup on message/close)
const tournamentPlayersByWs = new WeakMap();

function newTournament(code, hostId, hostName, hostWs, size) {
  return {
    code,
    size,
    hostId,
    started: false,
    finished: false,
    championId: null,
    // id -> { id, name, ws, connected, disconnectTimer }
    players: new Map([[hostId, { id: hostId, name: hostName, ws: hostWs, connected: true, disconnectTimer: null }]]),
    // rounds[roundIndex] = array of matches
    // match = { id, aId, bId, aName, bName, winnerId, bye, started,
    //           aResult: {words, elapsed} | null, bResult: {...} | null,
    //           forfeitTimer }
    rounds: [],
  };
}

function lobbySnapshot(t) {
  return {
    type: "tournament_lobby_update",
    code: t.code,
    host_id: t.hostId,
    size: t.size,
    started: t.started,
    players: Array.from(t.players.values()).map(p => ({ id: p.id, name: p.name, connected: p.connected })),
  };
}

function broadcastLobby(t) {
  const msg = lobbySnapshot(t);
  for (const p of t.players.values()) send(p.ws, msg);
}

function bracketSnapshot(t) {
  return {
    type: "tournament_bracket_update",
    code: t.code,
    rounds: t.rounds.map(round => round.map(m => ({
      id: m.id,
      a_id: m.aId || "",
      b_id: m.bId || "",
      a_name: m.aName,
      b_name: m.bName,
      winner_id: m.winnerId || "",
      winner_name: m.winnerId ? (m.winnerId === m.aId ? m.aName : m.bName) : "",
      bye: !!m.bye,
    }))),
  };
}

function broadcastBracket(t) {
  const msg = bracketSnapshot(t);
  for (const p of t.players.values()) send(p.ws, msg);
}

function nextPow2(n) {
  let p = 1;
  while (p < n) p *= 2;
  return p;
}

function buildBracket(t) {
  const playerIds = Array.from(t.players.keys());
  // Fisher-Yates shuffle for random seeding.
  for (let i = playerIds.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [playerIds[i], playerIds[j]] = [playerIds[j], playerIds[i]];
  }
  const slots = nextPow2(playerIds.length);
  while (playerIds.length < slots) playerIds.push(null); // null = bye

  const firstRound = [];
  for (let i = 0; i < slots; i += 2) {
    const aId = playerIds[i];
    const bId = playerIds[i + 1];
    const isBye = aId === null || bId === null;
    const realId = aId === null ? bId : aId;
    firstRound.push({
      id: `${t.code}-r0-m${firstRound.length}`,
      aId, bId,
      aName: aId ? t.players.get(aId).name : "",
      bName: bId ? t.players.get(bId).name : "",
      winnerId: isBye ? realId : null,
      bye: isBye,
      started: false,
      aResult: null, bResult: null,
      forfeitTimer: null,
    });
  }
  t.rounds = [firstRound];
}

function startMatch(t, match) {
  if (match.bye || !match.aId || !match.bId) return;
  match.started = true;
  const wordList = generateWordList(WORDS_PER_MATCH);
  const startUnix = Date.now() / 1000 + 5.0;
  match.wordList = wordList;
  match.startUnix = startUnix;

  const aPlayer = t.players.get(match.aId);
  const bPlayer = t.players.get(match.bId);
  send(aPlayer.ws, {
    type: "tournament_match_ready",
    match_id: match.id,
    opponent_name: match.bName,
    word_list: wordList,
    start_unix_time: startUnix,
  });
  send(bPlayer.ws, {
    type: "tournament_match_ready",
    match_id: match.id,
    opponent_name: match.aName,
    word_list: wordList,
    start_unix_time: startUnix,
  });

  match.forfeitTimer = setTimeout(() => resolveForfeit(t, match), MATCH_FORFEIT_MS);
}

// Kicks off every match in the current round whose both seats are real
// players (byes already have a winnerId and don't need a race).
function advanceReadyMatches(t) {
  const round = t.rounds[t.rounds.length - 1];
  for (const m of round) {
    if (!m.winnerId && !m.started && m.aId && m.bId) {
      startMatch(t, m);
    }
  }
}

function placeWinnerIntoNextRound(t, roundIndex, matchIndex, winnerId, winnerName) {
  const round = t.rounds[roundIndex];
  const nextRoundIndex = roundIndex + 1;

  if (round.length === 1) {
    // That was the final — tournament over.
    t.finished = true;
    t.championId = winnerId;
    const msg = { type: "tournament_complete", code: t.code, champion_id: winnerId, champion_name: winnerName };
    for (const p of t.players.values()) send(p.ws, msg);
    return;
  }

  if (!t.rounds[nextRoundIndex]) {
    // Build the next round's match slots (empty until both feeder
    // matches resolve).
    const nextRound = [];
    for (let i = 0; i < round.length / 2; i++) {
      nextRound.push({
        id: `${t.code}-r${nextRoundIndex}-m${i}`,
        aId: null, bId: null, aName: "", bName: "",
        winnerId: null, bye: false, started: false,
        aResult: null, bResult: null, forfeitTimer: null,
      });
    }
    t.rounds.push(nextRound);
  }

  const nextMatch = t.rounds[nextRoundIndex][Math.floor(matchIndex / 2)];
  if (matchIndex % 2 === 0) {
    nextMatch.aId = winnerId;
    nextMatch.aName = winnerName;
  } else {
    nextMatch.bId = winnerId;
    nextMatch.bName = winnerName;
  }

  // If both feeder matches for this next-round slot are done and it
  // turned out to be a bye (one feeder had no opponent at all — only
  // possible with an odd bracket at the very first round), resolve it
  // immediately instead of waiting for a race that can't happen.
  if (nextMatch.aId && !nextMatch.bId && bothFeedersSettled(t, nextRoundIndex, Math.floor(matchIndex / 2))) {
    nextMatch.winnerId = nextMatch.aId;
    nextMatch.bye = true;
    placeWinnerIntoNextRound(t, nextRoundIndex, Math.floor(matchIndex / 2), nextMatch.aId, nextMatch.aName);
  } else if (nextMatch.bId && !nextMatch.aId && bothFeedersSettled(t, nextRoundIndex, Math.floor(matchIndex / 2))) {
    nextMatch.winnerId = nextMatch.bId;
    nextMatch.bye = true;
    placeWinnerIntoNextRound(t, nextRoundIndex, Math.floor(matchIndex / 2), nextMatch.bId, nextMatch.bName);
  }
}

function bothFeedersSettled(t, roundIndex, matchIndex) {
  const feederRound = t.rounds[roundIndex - 1];
  const feederA = feederRound[matchIndex * 2];
  const feederB = feederRound[matchIndex * 2 + 1];
  return !!feederA.winnerId && !!feederB.winnerId;
}

function findMatchByPlayer(t, playerId) {
  const round = t.rounds[t.rounds.length - 1];
  if (!round) return null;
  const idx = round.findIndex(m => (m.aId === playerId || m.bId === playerId) && !m.winnerId);
  if (idx === -1) return null;
  return { round, match: round[idx], roundIndex: t.rounds.length - 1, matchIndex: idx };
}

function decideWinner(match) {
  const a = match.aResult, b = match.bResult;
  const total = match.wordList.length;
  const aDone = a && a.words >= total;
  const bDone = b && b.words >= total;

  if (aDone && bDone) {
    return a.elapsed <= b.elapsed ? match.aId : match.bId;
  }
  if (aDone) return match.aId;
  if (bDone) return match.bId;
  // Neither finished the full list (both stopped/forfeited some other
  // way) — whoever got further wins; tie goes to whoever reported first.
  if (a && b) return a.words >= b.words ? match.aId : match.bId;
  if (a) return match.aId;
  if (b) return match.bId;
  return match.aId; // shouldn't happen
}

function resolveMatch(t, found, winnerId) {
  const { match, roundIndex, matchIndex } = found;
  if (match.winnerId) return; // already resolved (e.g. forfeit race)
  if (match.forfeitTimer) { clearTimeout(match.forfeitTimer); match.forfeitTimer = null; }
  match.winnerId = winnerId;
  const winnerName = winnerId === match.aId ? match.aName : match.bName;
  broadcastBracket(t);
  placeWinnerIntoNextRound(t, roundIndex, matchIndex, winnerId, winnerName);
  broadcastBracket(t);
  if (!t.finished) advanceReadyMatches(t);
}

function resolveForfeit(t, match) {
  if (match.winnerId) return;
  // Whoever has any result (or is still connected) wins by forfeit;
  // if neither reported anything, whoever's socket is still open wins.
  const found = { match, roundIndex: t.rounds.length - 1, matchIndex: t.rounds[t.rounds.length - 1].indexOf(match) };
  let winnerId;
  if (match.aResult && !match.bResult) winnerId = match.aId;
  else if (match.bResult && !match.aResult) winnerId = match.bId;
  else {
    const aConnected = t.players.get(match.aId)?.connected;
    const bConnected = t.players.get(match.bId)?.connected;
    winnerId = aConnected && !bConnected ? match.aId : match.bId;
  }
  resolveMatch(t, found, winnerId);
}

function handleTournamentCreate(ws, meta, name, size) {
  const code = randomCode(tournaments);
  const hostId = randomId();
  const allowedSizes = [2, 4, 8, 16];
  const safeSize = allowedSizes.includes(size) ? size : 8;
  const t = newTournament(code, hostId, (name || "Host").slice(0, 20), ws, safeSize);
  tournaments.set(code, t);

  meta.mode = "tournament";
  meta.tournamentCode = code;
  meta.playerId = hostId;

  send(ws, { type: "tournament_created", code, player_id: hostId, you_are_host: true });
  broadcastLobby(t);
}

function handleTournamentJoin(ws, meta, code, name) {
  const t = tournaments.get(code);
  if (!t) {
    send(ws, { type: "tournament_join_failed", reason: "not_found" });
    return;
  }
  if (t.started) {
    send(ws, { type: "tournament_join_failed", reason: "already_started" });
    return;
  }
  if (t.players.size >= t.size) {
    send(ws, { type: "tournament_join_failed", reason: "full" });
    return;
  }
  const playerId = randomId();
  t.players.set(playerId, { id: playerId, name: (name || "Player").slice(0, 20), ws, connected: true, disconnectTimer: null });

  meta.mode = "tournament";
  meta.tournamentCode = code;
  meta.playerId = playerId;

  send(ws, { type: "tournament_joined", code, player_id: playerId, you_are_host: false });
  broadcastLobby(t);
}

function handleTournamentRejoin(ws, meta, code, playerId) {
  const t = tournaments.get(code);
  if (!t || !t.players.has(playerId)) {
    send(ws, { type: "tournament_join_failed", reason: "not_found" });
    return;
  }
  const p = t.players.get(playerId);
  if (p.disconnectTimer) { clearTimeout(p.disconnectTimer); p.disconnectTimer = null; }
  p.ws = ws;
  p.connected = true;

  meta.mode = "tournament";
  meta.tournamentCode = code;
  meta.playerId = playerId;

  send(ws, { type: "tournament_joined", code, player_id: playerId, you_are_host: t.hostId === playerId });
  broadcastLobby(t);
  if (t.started) {
    broadcastBracket(t);
    const found = findMatchByPlayer(t, playerId);
    if (found && found.match.started && !found.match.winnerId) {
      // Restart this one match fresh for both sides — simplest safe
      // behavior instead of trying to resume mid-race.
      found.match.started = false;
      found.match.aResult = null;
      found.match.bResult = null;
      if (found.match.forfeitTimer) { clearTimeout(found.match.forfeitTimer); found.match.forfeitTimer = null; }
      startMatch(t, found.match);
    }
  }
}

function handleTournamentStart(ws, meta) {
  const t = tournaments.get(meta.tournamentCode);
  if (!t) return;
  if (t.hostId !== meta.playerId) return;
  if (t.started || t.players.size < 2) return;
  t.started = true;
  buildBracket(t);
  broadcastLobby(t);
  broadcastBracket(t);
  advanceReadyMatches(t);
}

function handleTournamentProgress(t, meta, matchId, wordsDone) {
  const found = findMatchByPlayer(t, meta.playerId);
  if (!found || found.match.id !== matchId) return;
  const opponentId = found.match.aId === meta.playerId ? found.match.bId : found.match.aId;
  const opponent = t.players.get(opponentId);
  if (opponent) send(opponent.ws, { type: "tournament_relay", match_id: matchId, payload: { kind: "progress", words_done: wordsDone } });
}

function handleTournamentFinished(t, meta, matchId, wordsDone, elapsedSeconds) {
  const found = findMatchByPlayer(t, meta.playerId);
  if (!found || found.match.id !== matchId) return;
  const { match } = found;

  const opponentId = match.aId === meta.playerId ? match.bId : match.aId;
  const opponent = t.players.get(opponentId);
  if (opponent) send(opponent.ws, { type: "tournament_relay", match_id: matchId, payload: { kind: "finished", words_done: wordsDone, elapsed_seconds: elapsedSeconds } });

  if (match.aId === meta.playerId) match.aResult = { words: wordsDone, elapsed: elapsedSeconds };
  else match.bResult = { words: wordsDone, elapsed: elapsedSeconds };

  if (match.aResult && match.bResult) {
    resolveMatch(t, found, decideWinner(match));
  }
}

function handleTournamentLeave(ws, meta) {
  const t = tournaments.get(meta.tournamentCode);
  if (!t) return;
  removePlayerFromTournament(t, meta.playerId, /*immediate=*/true);
}

function removePlayerFromTournament(t, playerId, immediate) {
  const p = t.players.get(playerId);
  if (!p) return;

  if (!t.started) {
    // Lobby phase — just drop them from the list. If the host leaves
    // pre-start, promote the next player to host so the lobby isn't
    // orphaned.
    t.players.delete(playerId);
    if (t.hostId === playerId && t.players.size > 0) {
      t.hostId = t.players.keys().next().value;
    }
    if (t.players.size === 0) {
      tournaments.delete(t.code);
      return;
    }
    broadcastLobby(t);
    return;
  }

  p.connected = false;
  if (immediate) {
    t.players.delete(playerId);
  } else {
    p.disconnectTimer = setTimeout(() => {
      t.players.delete(playerId);
    }, RECONNECT_GRACE_MS);
  }
  broadcastLobby(t);

  // If they're mid-match, their forfeit timer (started in startMatch)
  // will award the win to their opponent if they don't rejoin in time.
}

// ============================================================
// Connection handling
// ============================================================

const server = http.createServer((req, res) => {
  // Minimal HTTP response so Render's health check (and casual browser
  // hits) get a 200 instead of a hang — the actual game traffic is all
  // WebSocket.
  res.writeHead(200, { "Content-Type": "text/plain" });
  res.end("Type Blast relay server is running.\n");
});

const wss = new WebSocketServer({ server });

wss.on("connection", (ws) => {
  const meta = { mode: null, role: null, roomCode: null, tournamentCode: null, playerId: null };

  ws.on("message", (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw.toString());
    } catch (e) {
      send(ws, { type: "error", reason: "bad_json" });
      return;
    }
    if (!msg || typeof msg !== "object" || typeof msg.type !== "string") {
      send(ws, { type: "error", reason: "bad_message" });
      return;
    }

    switch (msg.type) {
      // --- 1v1 versus ---
      case "host":
        handleHost(ws, meta);
        break;
      case "join":
        handleJoin(ws, meta, String(msg.code || "").toUpperCase());
        break;
      case "rejoin":
        handleRejoin(ws, meta, String(msg.code || "").toUpperCase(), msg.role === "host" ? "host" : "guest");
        break;
      case "relay":
        if (meta.mode === "versus") handleVersusRelay(ws, meta, msg.payload || {});
        break;

      // --- tournament ---
      case "tournament_create":
        handleTournamentCreate(ws, meta, msg.name, Number(msg.size));
        break;
      case "tournament_join":
        handleTournamentJoin(ws, meta, String(msg.code || "").toUpperCase(), msg.name);
        break;
      case "tournament_rejoin":
        handleTournamentRejoin(ws, meta, String(msg.code || "").toUpperCase(), msg.player_id);
        break;
      case "tournament_start":
        handleTournamentStart(ws, meta);
        break;
      case "tournament_leave":
        handleTournamentLeave(ws, meta);
        break;
      case "tournament_relay": {
        const t = tournaments.get(meta.tournamentCode);
        if (!t || meta.mode !== "tournament") break;
        const payload = msg.payload || {};
        if (payload.kind === "progress") {
          handleTournamentProgress(t, meta, msg.match_id, Number(payload.words_done || 0));
        } else if (payload.kind === "finished") {
          handleTournamentFinished(t, meta, msg.match_id, Number(payload.words_done || 0), Number(payload.elapsed_seconds || 0));
        }
        break;
      }

      default:
        send(ws, { type: "error", reason: "unknown_type" });
    }
  });

  ws.on("close", () => {
    if (meta.mode === "versus" && meta.roomCode) {
      handleVersusDisconnect(ws, meta);
    } else if (meta.mode === "tournament" && meta.tournamentCode && meta.playerId) {
      const t = tournaments.get(meta.tournamentCode);
      if (t) removePlayerFromTournament(t, meta.playerId, /*immediate=*/false);
    }
  });
});

server.listen(PORT, () => {
  console.log(`Type Blast relay server listening on port ${PORT}`);
});
