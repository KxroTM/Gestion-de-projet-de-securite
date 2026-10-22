// E07 - Un compte ne peut pas etre usurpe sans le bon mot de passe.
// Plugin AuthMe : avant de s'authentifier, un joueur ne peut pas discuter (et plus
// generalement pas jouer) ; une tentative avec un mauvais mot de passe est refusee
// (kick immediat, kickOnWrongPassword=true) ; avec le bon mot de passe, l'acces est
// accorde normalement (controle positif).
'use strict';

const mineflayer = require('mineflayer');
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const REPORTS_DIR = path.join(__dirname, '..', 'reports');
fs.mkdirSync(REPORTS_DIR, { recursive: true });

const HOST = process.env.MC_HOST || 'localhost';
const PORT = parseInt(process.env.MC_PORT || '25565', 10);
const VERSION = process.env.MC_VERSION || '26.1.2';
const PASSWORD = process.env.AUTH_TEST_PASSWORD || 'TestPass123AuthE07';
const RECONNECT_DELAY_MS = 5000; // evite le throttle anti-bot de Paper entre deux connexions

function rcon(cmd) {
  return execSync(`docker compose exec -T mc rcon-cli "${cmd}"`, { encoding: 'utf8' });
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Se connecte en Test_Premium, envoie une suite d'actions de chat espacees dans le
// temps, et collecte les evenements (messages, kick, erreur, fin) jusqu'au timeout.
function connectAndCollect(actions, timeoutMs) {
  return new Promise((resolve) => {
    const bot = mineflayer.createBot({
      host: HOST,
      port: PORT,
      username: 'Test_Premium',
      version: VERSION,
      auth: 'offline',
    });

    const events = [];
    let settled = false;
    const finish = () => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      try { bot.end(); } catch (e) { /* deja ferme */ }
      resolve(events);
    };

    const timer = setTimeout(finish, timeoutMs);

    bot.on('message', (msg) => events.push({ type: 'message', text: msg.toString() }));
    bot.on('kicked', (reason) => { events.push({ type: 'kicked', reason: String(reason) }); finish(); });
    bot.on('error', (err) => events.push({ type: 'error', text: err && err.message ? err.message : String(err) }));
    bot.on('end', (reason) => { events.push({ type: 'end', reason: String(reason) }); finish(); });
    bot.on('spawn', () => {
      events.push({ type: 'spawn' });
      let t = 0;
      for (const action of actions) {
        t += action.delayMs;
        setTimeout(() => { try { bot.chat(action.chat); } catch (e) { /* bot deja deconnecte */ } }, t);
      }
    });
  });
}

(async () => {
  const start = Date.now();
  let result = 'OK';
  const proofLines = [];

  rcon('authme unregister Test_Premium');
  rcon(`authme register Test_Premium ${PASSWORD}`);
  proofLines.push('Test_Premium (re)enregistre via RCON avec un mot de passe connu.');

  // 1. Avant authentification : le chat doit etre refuse (usurpation sans mot de
  //    passe impossible : on ne peut pas agir comme le compte sans s'authentifier).
  const preLoginEvents = await connectAndCollect(
    [{ delayMs: 1500, chat: 'hello before login' }],
    6000
  );
  const blocked = preLoginEvents.some(
    (e) => e.type === 'message' && /authenticated/i.test(e.text)
  );
  proofLines.push(
    `Avant login, message envoye -> ${blocked ? 'refuse (AuthMe a demande authentification)' : 'ECHEC: pas refuse'}`
  );
  if (!blocked) result = 'FAIL';

  await wait(RECONNECT_DELAY_MS);

  // 2. Mauvais mot de passe -> kick immediat (kickOnWrongPassword=true).
  const wrongPassEvents = await connectAndCollect(
    [{ delayMs: 1500, chat: '/login mot_de_passe_invalide' }],
    8000
  );
  const kicked = wrongPassEvents.some((e) => e.type === 'kicked');
  proofLines.push(`Mauvais mot de passe -> ${kicked ? 'kick confirme' : 'ECHEC: pas de kick'}`);
  if (!kicked) result = 'FAIL';

  await wait(RECONNECT_DELAY_MS);

  // 3. Controle positif : bon mot de passe -> login reussi, chat fonctionne ensuite.
  const correctPassEvents = await connectAndCollect(
    [
      { delayMs: 1500, chat: `/login ${PASSWORD}` },
      { delayMs: 2000, chat: 'hello after login' },
    ],
    9000
  );
  const loggedIn = correctPassEvents.some(
    (e) => e.type === 'message' && /successful login/i.test(e.text)
  );
  const chatWorked = correctPassEvents.some(
    (e) => e.type === 'message' && e.text.includes('hello after login')
  );
  proofLines.push(
    `Bon mot de passe -> login=${loggedIn ? 'OK' : 'ECHEC'}, chat_apres_login=${chatWorked ? 'OK' : 'ECHEC'}`
  );
  if (!loggedIn || !chatWorked) result = 'FAIL';

  const duration = (Date.now() - start) / 1000;
  const report = {
    id: 'auth',
    requirement: 'E07',
    result,
    duration_s: duration,
    proof: proofLines.join('\n'),
  };
  fs.writeFileSync(path.join(REPORTS_DIR, 'auth.json'), JSON.stringify(report, null, 2));

  console.log(proofLines.join('\n'));
  console.log(`[auth] ${result} (${duration}s) -> reports/auth.json`);
  if (result !== 'OK') {
    process.exitCode = 1;
  }
})();
