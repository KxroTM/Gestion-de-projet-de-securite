# minecraft-noel

Stack Docker pour un serveur Minecraft Paper (10-20 joueurs), avec sauvegardes
chiffrées restic et une suite de tests de sécurité automatiques exécutés à chaque
push via GitHub Actions. Projet scolaire — hors périmètre pour l'instant : bot
Discord, plugin d'authentification, déploiement sur le VPS.

## Lancement local

Prérequis : Docker Desktop (ou Docker Engine + plugin compose), `nmap`, Node.js 24.

```bash
cp .env.example .env
# Editer .env : RCON_PASSWORD et RESTIC_PASSWORD (valeurs de test suffisent en local).

docker compose -f docker-compose.yml -f docker-compose.ci.yml up -d
# docker-compose.ci.yml redirige le depot restic vers un volume local (pas de
# Backblaze B2 necessaire pour tester) et reduit la RAM allouee au serveur.

docker compose ps   # attendre que "mc" soit "healthy"

cd tests && npm ci && cd ..
bash tests/test_ports.sh
node tests/test_whitelist.js
bash tests/test_restart.sh
bash tests/test_backup_restore.sh
bash tests/test_encryption.sh

docker compose -f docker-compose.yml -f docker-compose.ci.yml down -v
```

Chaque test écrit son résultat dans `reports/<id>.json` (exigence, résultat, durée,
preuve). `python3 tests/lib/write_summary.py` regénère le tableau récapitulatif à
partir de ces fichiers.

En production, `docker-compose.yml` seul est utilisé (sans l'override CI) : il faut
alors renseigner `RESTIC_REPOSITORY` (format `b2:<bucket>:<chemin>`) et
`B2_ACCOUNT_ID` / `B2_ACCOUNT_KEY` dans `.env`.

## Choix de la version Minecraft

Le serveur utilise Paper **26.1.2**. Minecraft est passé à un versionnement
calendaire (26.x) ; mineflayer déclare officiellement `26.1` comme dernière version
testée (`testedVersions` / `latestSupportedVersion` dans
[`lib/version.js`](https://github.com/PrismarineJS/mineflayer/blob/master/lib/version.js)
du dépôt officiel). Mais PaperMC n'a jamais publié de build pour la version exacte
`26.1` : confirmé par l'API officielle (`fill.papermc.io/v3/projects/paper/versions/26.1`
renvoie `version_not_found`, et la liste des builds du groupe ne contient que
`26.1.1`/`26.1.2`), et par l'erreur obtenue en pratique au premier démarrage
(`Requested version 26.1 is not available`). La version vanilla `26.1` a bien
existé côté Mojang (sortie le 24/03/2026) mais a été remplacée par un patch
(`26.1.1`) seulement 8 jours plus tard, avant que Paper n'ait eu le temps/besoin de
publier un build dédié.

`26.1.2` a été choisie plutôt que de reculer jusqu'à la version précédente
entièrement "testée" par mineflayer (`1.21.11`) car `26.1`, `26.1.1` et `26.1.2`
partagent exactement le même protocole réseau (`version: 775` dans les données de
`minecraft-data`, le paquet sur lequel mineflayer s'appuie pour le wire protocol) :
seul le `dataVersion` (format de sauvegarde du monde) change entre ces patches,
ce qui n'affecte pas la communication avec le bot. `26.1.2` reste donc la version
la plus récente dont le comportement réseau correspond à ce que mineflayer annonce
supporter, même si la chaîne `26.1.2` n'apparaît pas littéralement dans sa liste
`testedVersions`.

Minecraft 26.1 et versions ultérieures exigent Java 25 (le serveur refuse de démarrer
sous Java 21 : `Minecraft 26.1 and newer requires running the server with Java 25 or
above`), d'où le tag d'image `itzg/minecraft-server:2026.10.0-java25` (et non
`-java21`).

## Image `itzg/minecraft-server` et whitelist en mode offline

`ONLINE_MODE=FALSE` + `WHITELIST` avec de simples pseudos (`Test_Premium`,
`Test_Crack`) ne fonctionne pas tel quel : l'image essaie de résoudre les pseudos via
l'API Mojang/PlayerDB même en mode offline, ce qui échoue sur des comptes fictifs
(`Could not resolve user from Playerdb`). La solution (confirmée par le mainteneur
de l'image) est de fournir directement les UUID offline (`OfflinePlayer:<pseudo>`,
UUID v3) dans `WHITELIST`. C'est ce que fait `docker-compose.yml`. Consequence : le
champ `name` de `whitelist.json` reste vide (seul l'UUID est utilisé pour la
correspondance), ce qui est normal.

## Tests et correspondance avec les exigences

| Exigence | Test                        | Ce qui est vérifié |
| -------- | ---------------------------- | --- |
| DS09     | `tests/test_ports.sh`        | Seul le port 25565 est publié ; `nmap` confirme 25565 ouvert et 25575 fermé. |
| E06      | `tests/test_whitelist.js`    | `Test_Intrus` est refusé (message de whitelist) ; `Test_Premium` se connecte (contrôle positif). |
| E09      | `tests/test_restart.sh`      | Après un crash simulé (`pkill -9 java` dans le conteneur), `mc` redevient `healthy` en moins de 180s. |
| E08      | `tests/test_backup_restore.sh` | Sauvegarde restic déclenchée, puis restauration ; durée < 900s. |
| DS07     | `tests/test_backup_restore.sh` | Même test : empreinte SHA-256 du monde identique avant/après restauration, bloc témoin retrouvé par RCON. |
| DS03     | `tests/test_encryption.sh`   | `restic snapshots` échoue avec un mauvais mot de passe ; le nom du niveau n'apparaît en clair dans aucun fichier du dépôt restic. |
| DS05     | Job `secrets` (gitleaks, CI) | Aucun secret dans le dépôt (historique complet scanné à chaque push). |

Chaque test a été vérifié "cassable" pendant le développement (ex. publier le port
RCON fait échouer DS09, whitelister l'intrus fait échouer E06, désynchroniser le
monde entre la sauvegarde et la restauration fait échouer E08/DS07, pointer vers un
contenu non chiffré fait échouer DS03).

Le job `images` (Trivy, scan des deux images utilisées) est un contrôle de sécurité
supplémentaire de la CI, sans exigence numérotée dédiée dans le cahier des charges
d'origine.

## Pipeline CI (`.github/workflows/security.yml`)

Déclenché sur `push` et `pull_request`. Trois jobs :
- `secrets` : gitleaks sur tout l'historique.
- `images` : Trivy sur les deux images utilisées (échec sur CRITICAL corrigeable).
- `stack` : génère `.env` avec des mots de passe aléatoires (`openssl rand -hex 24`,
  aucun secret GitHub requis), démarre la stack, attend l'état healthy, lance les 5
  tests, écrit le récapitulatif dans le résumé du run, publie `reports/` en artefact,
  et arrête systématiquement la stack (`docker compose down -v`) même en cas
  d'échec. Les images Docker et les `node_modules` des tests sont mis en cache entre
  les exécutions.

## Tableau des risques

| Risque | Impact | Réponse prévue |
| --- | --- | --- |
| CVE critiques sans correctif publié dans les images Docker utilisées (`itzg/minecraft-server`, `itzg/mc-backup`) | Moyen | Risque accepté et documenté dans `.trivyignore`, revu chaque semaine (prochaine revue : 2026-10-29) ; image mise à jour dès qu'un correctif sort sous un tag figé. |
| Mineflayer ne supporte pas encore Minecraft 26.2/26.3 | Faible | Reste sur Paper 26.1.2 (dernier build compatible) ; réévaluer la version dès que `testedVersions` de mineflayer est mis à jour. |
| Moteur Docker Desktop local ne respectant pas toujours la restart policy après un arrêt externe | Faible (local uniquement) | Les tests utilisent un crash interne (`pkill`) plutôt qu'un arrêt externe ; validé comme non reproductible sur la CI (Linux natif). |

## Vulnérabilités connues et acceptées (`.trivyignore`)

Au 2026-10-22, Trivy signale des CVE CRITICAL corrigeables sans qu'aucun tag Docker
figé ne soit disponible pour les corriger (seuls des tags flottants comme `java25`
ou `latest` ont été reconstruits avec le correctif — exclus par la règle "jamais
`latest`"). Elles sont listées dans `.trivyignore` avec justification, plutôt que de
bloquer indéfiniment le pipeline sur un correctif qui ne dépend pas de ce dépôt :

**Dans `itzg/minecraft-server:2026.10.0-java25` :**
- **7 CVE noyau Linux** (`linux-libc-dev`, couche OS) : KVM imbriqué,
  RDMA/InfiniBand, cible NVMe-over-TCP — aucun de ces sous-systèmes n'est utilisé
  par cette stack, risque pratique quasi nul.
- **CVE-2026-8763 (BouncyCastle 1.84)** dans le `.jar` de Paper 26.1.2 build 74 :
  PaperMC a cessé de builder cette version (remplacée par 26.2/26.3, non supportées
  par mineflayer à ce jour — vérifié sur `testedVersions`), aucun correctif ne
  viendra. BouncyCastle n'est pas le mécanisme de chiffrement principal du
  protocole Minecraft.
- **CVE-2022-36944 (scala-library 2.13.1)** : même situation, aucun tag daté plus
  récent disponible.

**Dans `itzg/mc-backup:2026.10.1` :** aucune nouvelle image publiée depuis.
- **5 CVE rclone** (accès non autorisé, RCE, contournement d'authentification) et
  **1 CVE grpc-go** (dépendance de rclone) : l'image embarque rclone pour supporter
  des remotes `rclone:...`, mais notre configuration utilise exclusivement le
  backend B2 natif de restic (`RESTIC_REPOSITORY=b2:<bucket>:<chemin>`), jamais le
  préfixe `rclone:`. Ce code n'est jamais exécuté par cette stack.
- **CVE-2025-68121 (Go `crypto/tls`)** : sans impact en local/CI (pas de connexion
  TLS sortante, dépôt restic local) ; en production avec Backblaze B2, le contenu
  reste protégé par le chiffrement restic indépendamment du TLS.

À revoir dès qu'un nouveau tag daté de l'une de ces deux images est publié, ou que
mineflayer ajoute le support de 26.2/26.3.

## Durcissement de l'hôte (`scripts/hardening/harden.sh`)

Script idempotent pour le futur VPS Debian 12 (non exécuté en CI, à lancer
manuellement en root sur le VPS) :
- UFW : seuls SSH et le port 25565 sont autorisés en entrée ;
- `sshd` : authentification par clé uniquement, connexion root interdite ;
- Fail2ban : 5 échecs en 10 minutes → bannissement 1h sur le service SSH ;
- `unattended-upgrades` : mises à jour de sécurité automatiques.

**Important** : Docker manipule directement les règles iptables/nftables et
contourne UFW pour tout port qu'il publie. UFW protège donc uniquement SSH ; c'est
pourquoi la stack ne doit jamais publier d'autre port que 25565 (le port RCON reste
exclusivement sur le réseau Docker interne).

## Ce qui reste manuel

- Droits et configuration du bot Discord (hors périmètre de ce projet).
- Activation de la 2FA sur les comptes ayant accès au dépôt et à Backblaze B2.
- Verrouillage d'objet (object lock) sur le bucket B2 de production.
- Relecture humaine des pull requests avant fusion.
- Accord du professeur avant toute mise en production réelle.

## Protection de branche à activer sur GitHub (DS04)

Sur `main` : pull request obligatoire avant fusion, au moins 1 approbation requise,
et le pipeline CI (`security.yml`) doit être vert. Ces règles se configurent dans
GitHub (Settings → Branches → Branch protection rules) et ne sont pas automatisables
depuis ce dépôt.

## Critère de fin

Pipeline entièrement vert sur `main`, récapitulatif à 7 lignes "OK" (DS09, E06, E09,
E08, DS07, DS03, DS05), et chaque test déjà vu en échec au moins une fois pendant le
contrôle de non-triche décrit plus haut.

<!-- PR de demo pour prouver que la protection de branche main fonctionne (DS04). -->
