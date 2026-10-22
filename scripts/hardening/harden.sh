#!/usr/bin/env bash
# Durcissement idempotent du futur VPS Debian 12 hebergeant la stack minecraft-noel.
# A executer manuellement sur le VPS (root), JAMAIS en CI : UFW/Fail2ban/sshd n'ont pas
# de sens dans un conteneur GitHub Actions et ce script modifie l'hote reel.
#
# Rappel important : Docker manipule directement les regles iptables/nftables et
# CONTOURNE UFW pour les ports qu'il publie. C'est pourquoi la regle du projet est de
# ne jamais publier d'autre port que 25565 (RCON reste uniquement sur le reseau Docker
# interne) : UFW seul ne suffirait pas a le proteger si on le publiait par erreur.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Ce script doit etre execute en root (sudo)." >&2
  exit 1
fi

SSH_PORT="${SSH_PORT:-22}"
GAME_PORT="${GAME_PORT:-25565}"
SSHD_CONFIG="/etc/ssh/sshd_config"

echo "== UFW : autoriser uniquement SSH ($SSH_PORT) et le port du jeu ($GAME_PORT) =="
apt-get update -qq
apt-get install -y -qq ufw

ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}/tcp" comment "SSH"
ufw allow "${GAME_PORT}/tcp" comment "Minecraft"
ufw --force enable
ufw status verbose

echo "== sshd : cle uniquement, root interdit =="
set_sshd_option() {
  local key="$1" value="$2"
  if grep -qE "^[#[:space:]]*${key}[[:space:]]" "$SSHD_CONFIG"; then
    sed -i "s|^[#[:space:]]*${key}[[:space:]].*|${key} ${value}|" "$SSHD_CONFIG"
  else
    echo "${key} ${value}" >> "$SSHD_CONFIG"
  fi
}
cp -n "$SSHD_CONFIG" "${SSHD_CONFIG}.bak-$(date +%Y%m%d)" || true
set_sshd_option "PermitRootLogin" "no"
set_sshd_option "PasswordAuthentication" "no"
set_sshd_option "PubkeyAuthentication" "yes"
set_sshd_option "Port" "$SSH_PORT"
sshd -t
systemctl reload sshd

echo "== Fail2ban : 5 echecs en 10 min -> ban 1h sur sshd =="
apt-get install -y -qq fail2ban
install -d -m 0755 /etc/fail2ban/jail.d
cat > /etc/fail2ban/jail.d/minecraft-noel.conf <<EOF
[sshd]
enabled = true
port = ${SSH_PORT}
maxretry = 5
findtime = 10m
bantime = 1h
EOF
systemctl enable --now fail2ban
systemctl restart fail2ban

echo "== unattended-upgrades : mises a jour de securite automatiques =="
apt-get install -y -qq unattended-upgrades apt-listchanges
dpkg-reconfigure -f noninteractive unattended-upgrades
systemctl enable --now unattended-upgrades

echo "== Termine. Verifie 'ufw status', 'systemctl status fail2ban', 'sshd -T' avant de fermer la session SSH en cours. =="
