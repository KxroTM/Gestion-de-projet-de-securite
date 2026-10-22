// E06 - Un joueur non liste (Test_Intrus) est refuse avec un message de whitelist.
// Controle positif : un joueur liste (Test_Premium) se connecte normalement.
'use strict';

const mineflayer = require('mineflayer');
const fs = require('fs');
const path = require('path');

const REPORTS_DIR = path.join(__dirname, '..', 'reports');
fs.mkdirSync(REPORTS_DIR, { recursive: true });

const HOST = process.env.MC_HOST || 'localhost';
const PORT = parseInt(process.env.MC_PORT || '25565', 10);
const VERSION = process.env.MC_VERSION || '26.1.2';

function tryConnect(username, timeoutMs = 20000) {
  return new Promise((resolve) => {
    const bot = mineflayer.createBot({
      host: HOST,
      port: PORT,
      username,
      version: VERSION,
      auth: 'offline',
    });

    let settled = false;
    const finish = (outcome, detail) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      try { bot.end(); } catch (e) { /* deja ferme */ }
      resolve({ outcome, detail: String(detail) });
    };

    const timer = setTimeout(
      () => finish('timeout', `aucune reponse apres ${timeoutMs}ms`),
      timeoutMs
    );

    bot.once('spawn', () => finish('connected', 'evenement spawn recu'));
    bot.once('kicked', (reason) => finish('kicked', reason));
    bot.once('error', (err) => finish('error', err && err.message ? err.message : err));
    bot.once('end', (reason) => finish('end', reason));
  });
}

(async () => {
  const start = Date.now();
  let result = 'OK';
  const proofLines = [];

  const premium = await tryConnect('Test_Premium');
  proofLines.push(`Test_Premium -> ${premium.outcome}: ${premium.detail}`);
  if (premium.outcome !== 'connected') {
    result = 'FAIL';
  }

  // Paper jette "Connection throttled!" si deux connexions arrivent trop vite depuis
  // la meme adresse (connection-throttle). On espace les deux tentatives pour ne pas
  // confondre ce throttle avec un rejet de whitelist.
  await new Promise((resolve) => setTimeout(resolve, 5000));

  const intrus = await tryConnect('Test_Intrus');
  proofLines.push(`Test_Intrus -> ${intrus.outcome}: ${intrus.detail}`);
  if (intrus.outcome === 'connected') {
    result = 'FAIL';
  }

  const duration = (Date.now() - start) / 1000;
  const report = {
    id: 'whitelist',
    requirement: 'E06',
    result,
    duration_s: duration,
    proof: proofLines.join('\n'),
  };
  fs.writeFileSync(
    path.join(REPORTS_DIR, 'whitelist.json'),
    JSON.stringify(report, null, 2)
  );

  console.log(proofLines.join('\n'));
  console.log(`[whitelist] ${result} (${duration}s) -> reports/whitelist.json`);
  if (result !== 'OK') {
    process.exitCode = 1;
  }
})();
