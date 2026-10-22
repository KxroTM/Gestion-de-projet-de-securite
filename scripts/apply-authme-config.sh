#!/usr/bin/env bash
# Applique config/authme-config.yml (dialogues graphiques pre-join/post-join desactives,
# cf. README) sur le plugin AuthMe DEJA demarre, puis recharge sa configuration.
#
# Pourquoi pas un volume monte directement sur /data/plugins/AuthMe/config.yml dans
# docker-compose.yml : au premier demarrage (volume vide), Docker cree les dossiers
# intermediaires manquants du point de montage en tant que root, AVANT que le
# conteneur (uid 1000) ne tourne. Resultat : /data/plugins/ devient illisible/
# inscriptible pour le process du serveur, qui ne peut plus meme ecrire le jar
# telecharge (AccessDeniedException). En copiant le fichier APRES coup, une fois
# qu'AuthMe a deja cree son dossier avec les bonnes permissions au demarrage normal,
# on evite completement ce probleme.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

docker compose cp config/authme-config.yml mc:/data/plugins/AuthMe/config.yml
docker compose exec -T mc rcon-cli "authme reload"
