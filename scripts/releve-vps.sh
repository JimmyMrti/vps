#!/usr/bin/env bash
# releve-vps.sh — relevé complet de l'architecture et de la configuration du VPS.
#
# Lecture seule : le script n'installe rien, ne redémarre rien, ne modifie
# aucune configuration. Il écrit uniquement dans son dossier de sortie sous
# /tmp, puis en fait une archive.
#
# Les secrets sont masqués avant l'archivage : clés privées, mots de passe,
# jetons, valeurs des fichiers .env et des EnvironmentFile, identifiants dans
# les URL. Certains fichiers ne sont jamais copiés (shadow, clés d'hôte SSH,
# config Docker du registre, clés des certificats). Relire l'archive avant de
# la partager malgré tout : elle contient des noms de comptes, des adresses IP
# et l'arborescence du serveur.
#
# Usage, depuis son poste :
#   scp releve-vps.sh <vps>:/tmp/
#   ssh -t <vps> 'sudo bash /tmp/releve-vps.sh'
#   scp '<vps>:/tmp/releve-vps-*.tar.gz' .
#
# Variables facultatives :
#   RELEVE_SORTIE   dossier parent de la sortie (défaut : /tmp)
#   RELEVE_LOGS=0   ne pas relever les dernières lignes de journaux

set -uo pipefail
umask 077
export LC_ALL=C.UTF-8 SYSTEMD_PAGER= PAGER=cat

if [[ ${EUID} -ne 0 ]]; then
  echo "Ce script doit tourner en root : sudo bash $0" >&2
  exit 1
fi

HOTE=$(hostname -s 2>/dev/null || echo vps)
HORODATAGE=$(date +%Y%m%d-%H%M%S)
NOM="releve-vps-${HOTE}-${HORODATAGE}"
OUT="${RELEVE_SORTIE:-/tmp}/${NOM}"
F="$OUT/fichiers"          # copies des fichiers de configuration
MASQUE='***MASQUÉ***'
LISTE_ENV="$OUT/.a-masquer-entierement"
mkdir -p "$F" || exit 1
: >"$LISTE_ENV"

a() { command -v "$1" >/dev/null 2>&1; }
etape() { printf '\033[1m==> %s\033[0m\n' "$*" >&2; }

# run <fichier> <titre> <commande...> : ajoute la sortie d'une commande à un fichier.
run() {
  local fichier="$OUT/$1" titre="$2"; shift 2
  {
    printf '\n### %s\n$ %s\n' "$titre" "$*"
    timeout 120 "$@" </dev/null 2>&1
    local rc=$?
    [[ $rc -ne 0 ]] && printf '[code retour %s]\n' "$rc"
  } >>"$fichier"
}

# Fichiers jamais copiés, quel que soit leur emplacement.
interdit() {
  case "$1" in
    */shadow|*/shadow-|*/gshadow|*/gshadow-|*/security/opasswd) return 0 ;;
    */ssh_host_*_key|*/id_rsa|*/id_ecdsa|*/id_ed25519|*/id_dsa) return 0 ;;
    *.key|*.p12|*.pfx|*.jks|*.keystore|*.kdbx|*.gpg|*.asc) return 0 ;;
    */.docker/config.json|*/.git-credentials|*/.netrc|*/.pgpass) return 0 ;;
    */authorized_keys|*/authorized_keys2|*/known_hosts) return 0 ;;
    */secrets/*|*/secret/*|*/.ssh/*) return 0 ;;
  esac
  return 1
}

# copier <chemin> [env] : copie un fichier texte dans l'archive, en gardant son chemin.
# Avec « env », toutes les valeurs du fichier seront masquées.
copier() {
  local src="$1" mode="${2:-}"
  [[ -f "$src" && ! -L "$src" ]] || { [[ -L "$src" ]] && echo "$src -> $(readlink "$src")" >>"$OUT/liens-symboliques.txt"; return 0; }
  if interdit "$src"; then
    echo "$src (écarté : fichier sensible)" >>"$OUT/fichiers-ecartes.txt"; return 0
  fi
  local taille; taille=$(stat -c %s "$src" 2>/dev/null || echo 0)
  if (( taille > 524288 )); then
    echo "$src (écarté : ${taille} octets)" >>"$OUT/fichiers-ecartes.txt"; return 0
  fi
  if (( taille > 0 )) && ! grep -Iq . "$src" 2>/dev/null; then
    echo "$src (écarté : binaire)" >>"$OUT/fichiers-ecartes.txt"; return 0
  fi
  mkdir -p "$F$(dirname "$src")" && cp -p "$src" "$F$src" 2>/dev/null
  case "$src" in *.env|*/.env|*/.env.*|*/env) mode=env ;; esac
  [[ "$mode" == env ]] && echo "$F$src" >>"$LISTE_ENV"
  return 0
}
# copier_arbo <dossier> [profondeur] : copie les fichiers de configuration d'une arborescence.
copier_arbo() {
  local d="$1" prof="${2:-4}"
  [[ -d "$d" ]] || return 0
  find "$d" -maxdepth "$prof" \
    \( -name .git -o -name node_modules -o -name data -o -name caddy_data -o -name certificates \
       -o -name pgdata -o -name postgres -o -name postgresql -o -name .docker -o -name volumes \
       -o -name dist -o -name .cache -o -name backups -o -name sauvegardes \) -prune -o \
    -type f \( -iname '*.yml' -o -iname '*.yaml' -o -iname '*.caddy' -o -iname 'Caddyfile*' \
       -o -iname '*.conf' -o -iname '*.env' -o -iname '.env*' -o -iname '*.service' -o -iname '*.timer' \
       -o -iname '*.sh' -o -iname 'Dockerfile*' -o -iname '*.json' -o -iname '*.toml' -o -iname '*.ini' \
       -o -iname '*.md' -o -iname '*.cfg' -o -iname '*.txt' -o -iname 'Makefile' -o -iname '*.sources' -o -iname '*.list' \) -print0 2>/dev/null |
    while IFS= read -r -d '' f; do copier "$f"; done
}

etape "Relevé dans $OUT"

# --- 1. Système -------------------------------------------------------------
etape "Système"
S=01-systeme.txt
run $S "Identité" hostnamectl
run $S "Distribution" cat /etc/os-release
run $S "Noyau" uname -a
run $S "Allumé depuis" uptime
run $S "Horloge" timedatectl
run $S "Processeur" lscpu
run $S "Mémoire" free -h
run $S "Swap" swapon --show
run $S "Disques" lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
run $S "Occupation des disques" df -hT -x tmpfs -x devtmpfs -x overlay
run $S "Montages" findmnt -D -t nooverlay,notmpfs,noproc,nosysfs,nocgroup2
run $S "Plus gros dossiers" bash -c 'du -xhd1 / 2>/dev/null | sort -rh | head -20'
run $S "Dossiers de premier niveau de /srv, /opt, /home, /var/lib" bash -c 'du -xhd1 /srv /opt /home /var/lib 2>/dev/null | sort -rh | head -40'
run $S "Charge des processus (top 25 mémoire)" bash -c 'ps -eo user,pid,ppid,%cpu,%mem,rss,etime,comm --sort=-rss | head -26'
for f in /etc/hostname /etc/hosts /etc/fstab /etc/timezone /etc/default/locale /etc/machine-info; do copier "$f"; done

# --- 2. Paquets et mises à jour ---------------------------------------------
etape "Paquets"
S=02-paquets.txt
run $S "Paquets installés à la main" apt-mark showmanual
run $S "Paquets retenus" apt-mark showhold
run $S "Nombre de paquets" bash -c 'dpkg-query -W | wc -l'
run $S "Paquets en attente de mise à jour (cache local, sans apt update)" apt list --upgradable
run $S "Redémarrage requis" bash -c 'ls -l /var/run/reboot-required* 2>/dev/null && cat /var/run/reboot-required.pkgs 2>/dev/null || echo non'
a snap && run $S "Snaps" snap list
dpkg-query -W -f='${Package}\t${Version}\t${Status}\n' 2>/dev/null | awk -F'\t' '$3 ~ /installed/ {print $1"\t"$2}' >"$OUT/02-paquets-liste.tsv"
copier /etc/apt/sources.list
copier_arbo /etc/apt/sources.list.d 1
copier_arbo /etc/apt/preferences.d 1
for f in /etc/apt/apt.conf.d/*; do copier "$f"; done
ls -l /etc/apt/keyrings /usr/share/keyrings 2>/dev/null >"$OUT/02-apt-trousseaux.txt"

# --- 3. Comptes -------------------------------------------------------------
etape "Comptes"
S=03-comptes.txt
run $S "Comptes avec un shell de connexion" bash -c "awk -F: '\$7 !~ /(nologin|false|sync|halt|shutdown)\$/' /etc/passwd"
run $S "Comptes humains (UID >= 1000)" bash -c "awk -F: '\$3>=1000 && \$3<65534' /etc/passwd"
run $S "Membres des groupes sensibles" bash -c 'for g in sudo adm docker wheel lxd systemd-journal; do getent group $g; done'
run $S "État des mots de passe (sans empreinte)" bash -c 'passwd -Sa 2>/dev/null || for u in $(cut -d: -f1 /etc/passwd); do passwd -S "$u"; done'
run $S "Dernières connexions" bash -c 'lastlog 2>/dev/null | grep -v "Never logged" || true; last -n 30 2>/dev/null || true'
run $S "Clés SSH autorisées (empreintes uniquement)" bash -c '
  for d in /root $(awk -F: "\$3>=1000 && \$3<65534 {print \$6}" /etc/passwd); do
    for k in "$d"/.ssh/authorized_keys "$d"/.ssh/authorized_keys2; do
      [ -f "$k" ] || continue
      echo "--- $k ($(stat -c "%U:%G %a" "$k"))"
      ssh-keygen -lf "$k" 2>&1
      grep -Eo "^(from|command|restrict|no-[a-z-]+)[^ ]*" "$k" | sort -u | sed "s/^/  option : /"
    done
  done'
run $S "Droits des dossiers personnels" bash -c 'ls -ld /root /home/*'
run $S "Variables exportées par les fichiers de shell des comptes" bash -c 'grep -HnE "^[[:space:]]*export[[:space:]]" /root/.bashrc /root/.profile /home/*/.bashrc /home/*/.profile /home/*/.bash_profile /etc/environment /etc/profile.d/*.sh 2>/dev/null'
copier /etc/sudoers
copier_arbo /etc/sudoers.d 1
copier /etc/login.defs
copier_arbo /etc/security 2
copier_arbo /etc/pam.d 1

# --- 4. Réseau et pare-feu ----------------------------------------------------
etape "Réseau et pare-feu"
S=04-reseau.txt
run $S "Interfaces" ip -br address
run $S "Interfaces (détail)" ip address
run $S "Routes" ip route
run $S "Routes IPv6" ip -6 route
run $S "Ports en écoute" ss -tulpen
run $S "Résolution DNS" bash -c 'resolvectl status 2>/dev/null || cat /etc/resolv.conf'
run $S "UFW" ufw status verbose
run $S "UFW (numéroté)" ufw status numbered
run $S "Règles nftables" nft list ruleset
run $S "Règles iptables" iptables-save
run $S "Règles ip6tables" ip6tables-save
copier_arbo /etc/netplan 1
copier_arbo /etc/ufw 2
copier_arbo /etc/cloud 3
copier /etc/nftables.conf
copier /etc/default/ufw

# --- 5. SSH -------------------------------------------------------------------
etape "SSH"
S=05-ssh.txt
run $S "Configuration effective de sshd" sshd -T
run $S "Clés d'hôte (empreintes)" bash -c 'for k in /etc/ssh/ssh_host_*_key.pub; do ssh-keygen -lf "$k"; done'
copier /etc/ssh/sshd_config
copier_arbo /etc/ssh/sshd_config.d 1
copier /etc/ssh/ssh_config
copier_arbo /etc/ssh/ssh_config.d 1

# --- 6. Durcissement ----------------------------------------------------------
etape "Durcissement"
S=06-durcissement.txt
if a fail2ban-client; then
  run $S "fail2ban" fail2ban-client status
  for j in $(fail2ban-client status 2>/dev/null | sed -n 's/.*Jail list:[[:space:]]*//p' | tr ',' ' '); do
    run $S "fail2ban : prison $j" fail2ban-client status "$j"
    run $S "fail2ban : réglages de $j" bash -c "for k in maxretry findtime bantime logpath; do printf '%s = ' \$k; fail2ban-client get $j \$k 2>&1 | tr '\n' ' '; echo; done"
  done
fi
copier_arbo /etc/fail2ban 2
run $S "AppArmor" aa-status
run $S "Paramètres noyau de sécurité" bash -c 'sysctl -a 2>/dev/null | grep -E "^(net\.ipv4\.(ip_forward|conf\.(all|default)\.(rp_filter|accept_redirects|send_redirects|accept_source_route|log_martians)|tcp_syncookies|icmp_echo_ignore_broadcasts)|net\.ipv6\.conf\.(all|default)\.(accept_redirects|accept_ra|disable_ipv6)|kernel\.(kptr_restrict|dmesg_restrict|randomize_va_space|yama\.ptrace_scope|unprivileged_bpf_disabled|sysrq|perf_event_paranoid|modules_disabled)|fs\.(protected_[a-z]+|suid_dumpable)|user\.max_user_namespaces)"'
run $S "Mises à jour automatiques : dernières exécutions" bash -c 'tail -n 40 /var/log/unattended-upgrades/unattended-upgrades.log 2>/dev/null || echo "journal absent"'
run $S "auditd" bash -c 'systemctl is-active auditd 2>&1; auditctl -l 2>&1 | head -100'
run $S "Modules noyau chargés" bash -c 'lsmod | sort'
run $S "Fichiers SUID/SGID hors paquets standard (système de fichiers racine)" bash -c 'find / -xdev -type f -perm /6000 2>/dev/null | sort'
copier /etc/sysctl.conf
copier_arbo /etc/sysctl.d 1
copier_arbo /etc/modprobe.d 1
copier_arbo /etc/audit 2
copier_arbo /etc/logrotate.d 1
copier /etc/logrotate.conf
copier /etc/systemd/journald.conf
copier_arbo /etc/systemd/journald.conf.d 1

# --- 7. systemd et tâches planifiées -----------------------------------------
etape "Services et tâches planifiées"
S=07-systemd.txt
run $S "Services en cours" systemctl list-units --type=service --state=running --no-legend
run $S "Unités en échec" systemctl list-units --state=failed --no-legend
run $S "Unités activées" systemctl list-unit-files --state=enabled --no-legend
run $S "Minuteurs" systemctl list-timers --all --no-legend
run $S "Unités propres à la machine (/etc/systemd/system)" bash -c 'find /etc/systemd/system -maxdepth 2 -type f | sort'
while IFS= read -r -d '' u; do
  copier "$u"
  nomu=$(basename "$u")
  case "$nomu" in *.service|*.timer|*.path|*.socket|*.mount)
    run $S "Unité $nomu (telle que systemd la lit, surcharges comprises)" systemctl cat "$nomu"
    if [[ "$nomu" == *@.* ]]; then
      for inst in $(systemctl list-units --all --plain --no-legend "${nomu%%@*}@*.${nomu##*.}" 2>/dev/null | awk '{print $1}'); do
        run $S "État de $inst" systemctl status --no-pager -n 15 "$inst"
      done
    else
      run $S "État de $nomu" systemctl status --no-pager -n 15 "$nomu"
    fi ;;
  esac
  # Scripts lancés et fichiers d'environnement référencés par l'unité.
  grep -E '^(ExecStart|ExecStartPre|ExecStartPost|ExecStop|ExecReload)=' "$u" 2>/dev/null |
    sed -E 's/^[^=]+=[-@:+!]*//' | awk '{print $1}' |
    while read -r x; do [[ "$x" == /* && ! "$x" =~ ^/(usr/)?s?bin/ ]] && copier "$x"; done
  grep -E '^EnvironmentFile=' "$u" 2>/dev/null | sed -E 's/^EnvironmentFile=-?//' |
    while read -r e; do copier "$e" env; done
done < <(find /etc/systemd/system -maxdepth 2 -type f -print0 2>/dev/null)
S=07-cron.txt
run $S "crontab système" cat /etc/crontab
run $S "Crontabs des comptes" bash -c 'for u in $(cut -d: -f1 /etc/passwd); do c=$(crontab -l -u "$u" 2>/dev/null) && printf "\n--- %s\n%s\n" "$u" "$c"; done'
for d in /etc/cron.d /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly; do
  run $S "Contenu de $d" ls -l "$d"
done
copier_arbo /etc/cron.d 1

# --- 8. Docker -----------------------------------------------------------------
etape "Docker"
S=08-docker.txt
if a docker && docker info >/dev/null 2>&1; then
  run $S "Version" docker version
  run $S "Moteur" docker info
  run $S "Conteneurs" docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
  run $S "Conteneurs (réglages de sécurité)" docker inspect -f \
    '{{.Name}}
  image={{.Config.Image}}  redémarrage={{.HostConfig.RestartPolicy.Name}}  utilisateur={{if .Config.User}}{{.Config.User}}{{else}}(root par défaut){{end}}
  racine en lecture seule={{.HostConfig.ReadonlyRootfs}}  privilégié={{.HostConfig.Privileged}}  cap_drop={{.HostConfig.CapDrop}}  cap_add={{.HostConfig.CapAdd}}
  security_opt={{.HostConfig.SecurityOpt}}  mémoire max={{.HostConfig.Memory}}  pids max={{.HostConfig.PidsLimit}}  réseau={{.HostConfig.NetworkMode}}
  ports publiés={{json .HostConfig.PortBindings}}
  réseaux={{range $k, $v := .NetworkSettings.Networks}}{{$k}}({{$v.IPAddress}}) {{end}}
  montages={{range .Mounts}}
    {{.Type}} {{if .Name}}{{.Name}}{{else}}{{.Source}}{{end}} -> {{.Destination}} rw={{.RW}}{{end}}
  compose : projet={{index .Config.Labels "com.docker.compose.project"}} service={{index .Config.Labels "com.docker.compose.service"}}
            dossier={{index .Config.Labels "com.docker.compose.project.working_dir"}}
            fichiers={{index .Config.Labels "com.docker.compose.project.config_files"}}
  healthcheck={{if .State.Health}}{{.State.Health.Status}}{{else}}aucun{{end}}  démarré={{.State.StartedAt}}
' $(docker ps -aq)
  run $S "Images" docker image ls --digests
  run $S "Étiquettes des images (révision, source)" bash -c 'docker image ls -q | sort -u | xargs -r docker image inspect -f "{{.RepoTags}} {{.Created}} {{json .Config.Labels}}"'
  run $S "Réseaux" docker network ls
  run $S "Réseaux (détail)" bash -c 'docker network ls -q | xargs -r docker network inspect -f "{{.Name}} driver={{.Driver}} interne={{.Internal}} sous-réseau={{range .IPAM.Config}}{{.Subnet}} {{end}} conteneurs={{range .Containers}}{{.Name}} {{end}}"'
  run $S "Volumes" docker volume ls
  run $S "Volumes (détail)" bash -c 'docker volume ls -q | xargs -r docker volume inspect -f "{{.Name}} -> {{.Mountpoint}} étiquettes={{json .Labels}}"'
  run $S "Occupation disque de Docker" docker system df -v
  run $S "Projets Compose" docker compose ls -a
  docker ps -aq | while read -r id; do
    n=$(docker inspect -f '{{.Name}}' "$id" | tr -d /)
    docker inspect "$id" >"$OUT/08-docker-inspect-$n.json" 2>&1
  done
  copier_arbo /etc/docker 1
  copier /etc/default/docker
  # Fichiers Compose et dossiers de travail des projets en service.
  docker ps -aq | xargs -r docker inspect -f \
    '{{index .Config.Labels "com.docker.compose.project.working_dir"}}|{{index .Config.Labels "com.docker.compose.project.config_files"}}|{{index .Config.Labels "com.docker.compose.project.environment_file"}}' 2>/dev/null |
    sort -u | while IFS='|' read -r wd cf ef; do
      [[ -n "$wd" ]] && copier_arbo "$wd" 3
      for c in ${cf//,/ }; do copier "$c"; done
      for e in ${ef//,/ }; do copier "$e" env; done
    done

  # Configuration vue de l'intérieur des conteneurs frontaux.
  S=09-frontaux.txt
  docker ps --format '{{.Names}} {{.Image}}' | while read -r n img; do
    case "$img" in
      *caddy*)
        run $S "$n : version de Caddy" docker exec "$n" caddy version
        run $S "$n : fichiers de /etc/caddy" docker exec "$n" find /etc/caddy -type f
        for cf in $(docker exec "$n" find /etc/caddy -type f 2>/dev/null); do
          run $S "$n : $cf" docker exec "$n" cat "$cf"
        done
        run $S "$n : configuration résolue (caddy adapt)" docker exec "$n" caddy adapt --config /etc/caddy/Caddyfile --pretty
        run $S "$n : certificats détenus (noms et dates, sans les clés)" docker exec "$n" sh -c 'find /data/caddy/certificates -type f -name "*.crt" -exec ls -l {} \; 2>/dev/null'
        run $S "$n : variables d'environnement" docker exec "$n" env ;;
      *nginx*) ;;  # traité ci-dessous, quel que soit le nom de l'image
      *postgres*|*postgis*)
        run $S "$n : version de PostgreSQL" docker exec "$n" postgres --version
        run $S "$n : bases et tailles" docker exec "$n" sh -c 'psql -U "${POSTGRES_USER:-postgres}" -Atc "select datname, pg_size_pretty(pg_database_size(datname)) from pg_database" 2>&1' ;;
      *n8n*)
        run $S "$n : version de n8n" docker exec "$n" n8n --version ;;
    esac
  done

  docker ps --format '{{.Names}}' | while read -r n; do
    docker exec "$n" sh -c 'command -v nginx' >/dev/null 2>&1 &&
      run $S "$n : configuration résolue (nginx -T)" docker exec "$n" nginx -T
  done

  if [[ "${RELEVE_LOGS:-1}" != 0 ]]; then
    S=10-journaux-conteneurs.txt
    docker ps --format '{{.Names}}' | while read -r n; do
      run $S "$n : 60 dernières lignes" docker logs --tail 60 "$n"
    done
  fi
else
  echo "Docker absent ou moteur arrêté." >"$OUT/$S"
fi

# --- 9. Arborescences de déploiement ----------------------------------------
etape "Arborescences de déploiement"
S=11-arborescences.txt
for d in /srv /opt /etc/caddy /var/www; do
  [[ -d "$d" ]] || continue
  run $S "Arborescence de $d (4 niveaux)" bash -c "find '$d' -maxdepth 4 \\( -name .git -o -name node_modules \\) -prune -o -printf '%M %u:%g %8s %TY-%Tm-%Td %p\n' 2>/dev/null | sort -k5 | head -2000"
  run $S "Taille par dossier de $d" bash -c "du -xhd2 '$d' 2>/dev/null | sort -rh | head -40"
  run $S "Dépôts git sous $d" bash -c "find '$d' -maxdepth 4 -name .git -type d 2>/dev/null | while read -r g; do r=\${g%/.git}; echo \"--- \$r\"; git -C \"\$r\" -c safe.directory='*' remote -v 2>&1 | sed -E 's#://[^/@]+@#://***MASQUÉ***@#'; git -C \"\$r\" -c safe.directory='*' log -1 --format='%h %ci %s' 2>&1; git -C \"\$r\" -c safe.directory='*' status -s 2>&1 | head -20; done"
  copier_arbo "$d" 4
done
run $S "Emplacement des fichiers de config Docker du registre (contenu non relevé)" bash -c 'find / -xdev -path /proc -prune -o -path "*/.docker/config.json" -print 2>/dev/null; env | grep -E "^DOCKER_CONFIG=" || true; grep -rs DOCKER_CONFIG /etc/environment /etc/profile.d /etc/systemd/system 2>/dev/null || true'

# --- 10. Journaux système ---------------------------------------------------
if [[ "${RELEVE_LOGS:-1}" != 0 ]]; then
  etape "Journaux système"
  S=12-journaux.txt
  run $S "Erreurs et avertissements depuis le démarrage (200 dernières)" journalctl -b -p warning --no-pager -n 200
  run $S "Taille du journal" journalctl --disk-usage
fi

# --- Masquage des secrets ----------------------------------------------------
etape "Masquage des secrets"
# Forme « nom: valeur » ou « nom=valeur ».
CLES='(pass(word|wd|phrase)?|pwd|secret|token|api[_-]?key|access[_-]?key|private[_-]?key|[a-z0-9]+_key|encryption[_-]?key|credentials?|auth|bearer|salt|dsn|database_url|db_url|connection_string|client_secret|webhook_url)'
# Forme « nom valeur » en début de ligne (nginx, Caddy, fichiers de conf) : liste plus étroite,
# et les chemins de fichier ne sont pas masqués.
CLES2='(pass(word|wd|phrase)?|secret|token|api[_-]?key|access[_-]?key|private[_-]?key|encryption[_-]?key|client_secret|bearer)'
masquer() {
  sed -E -i \
    -e "/-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----/,/-----END [A-Z0-9 ]*PRIVATE KEY-----/c\\
${MASQUE} (clé privée)" \
    -e "s/(Authorization:?[[:space:]]*\"?(Bearer|Basic|Token)[[:space:]]+)[A-Za-z0-9._~+\/=-]+/\1${MASQUE}/Ig" \
    -e "s/(${CLES}[A-Za-z0-9_.-]*\"?[[:space:]]*[=:][[:space:]]*\"?)[^\"'[:space:],{}[]+/\1${MASQUE}/Ig" \
    -e "s/^([[:space:]]*${CLES2}[A-Za-z0-9_.-]*[[:space:]]+)(\"[^\"]+\"|[^/[:space:]\"{}][^[:space:]\"{}]{7,})([[:space:]]*;?[[:space:]]*)$/\1${MASQUE}\3/I" \
    -e "s#(://[^/:@[:space:]\"']+:)[^@/[:space:]\"']+@#\1${MASQUE}@#g" \
    -e "s/\b(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|glpat-[A-Za-z0-9_-]{20,}|sk-(ant-|proj-)?[A-Za-z0-9]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16})/${MASQUE}/g" \
    -e "s/\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/${MASQUE}/g" \
    -e "s/(\\\$(1|2[aby]|5|6|y|argon2id?)\\\$)[^:[:space:]\"]+/\1${MASQUE}/g" \
    "$1"
}
find "$OUT" -type f ! -name '.a-masquer-entierement' -print0 | while IFS= read -r -d '' f; do masquer "$f"; done
# Fichiers d'environnement : on garde les noms de variables, toutes les valeurs sont masquées.
while IFS= read -r f; do
  [[ -f "$f" ]] && sed -E -i "s/^([[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*).+/\1${MASQUE}/" "$f"
done <"$LISTE_ENV"
rm -f "$LISTE_ENV"

# --- Résumé ----------------------------------------------------------------------
R="$OUT/00-RESUME.md"
{
  echo "# Relevé de $(hostname -f 2>/dev/null || hostname)"
  echo
  echo "Relevé le $(date -Iseconds) par \`releve-vps.sh\`, en lecture seule. Secrets masqués (\`${MASQUE}\`)."
  echo
  echo "- Système : $(. /etc/os-release; echo "$PRETTY_NAME"), noyau $(uname -r)"
  echo "- Processeur : $(nproc) cœurs ; mémoire : $(free -h | awk '/^Mem/ {print $2" dont "$3" utilisés"}')"
  echo "- Disque racine : $(df -h / | awk 'NR==2 {print $3" utilisés sur "$2" ("$5")"}')"
  echo "- Allumé depuis : $(uptime -p)"
  echo
  echo "## Ports en écoute (hors boucle locale)"
  echo '```'
  ss -tulnpH 2>/dev/null | awk '$5 !~ /^(127\.|\[::1\]|::1)/ {print $1, $5, $7}' | sort -u
  echo '```'
  echo
  echo "## Pare-feu"
  echo '```'
  ufw status 2>&1 | head -30
  echo '```'
  if a docker && docker info >/dev/null 2>&1; then
    echo
    echo "## Conteneurs"
    echo '```'
    docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
    echo '```'
    echo
    echo "## Projets Compose"
    echo '```'
    docker ps -a --format '{{.Label "com.docker.compose.project"}}\t{{.Label "com.docker.compose.project.working_dir"}}' | sort -u
    echo '```'
  fi
  echo
  echo "## Unités systemd propres à la machine"
  echo '```'
  find /etc/systemd/system -maxdepth 1 -type f \( -name '*.service' -o -name '*.timer' \) -printf '%f\n' | sort
  echo '```'
  echo
  echo "## Contenu de l'archive"
  echo '```'
  (cd "$OUT" && find . -type f | sort)
  echo '```'
} >"$R" 2>/dev/null
masquer "$R"

# --- Contrôle et archive -------------------------------------------------------
etape "Contrôle des fuites résiduelles"
RESTE=$(grep -rIlE -- '-----BEGIN [A-Z ]*PRIVATE KEY|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_|glpat-|AKIA[0-9A-Z]{16}' "$OUT" 2>/dev/null || true)
if [[ -n "$RESTE" ]]; then
  echo "ATTENTION : motif de secret encore présent dans :" >&2
  echo "$RESTE" >&2
fi

ARCHIVE="${OUT}.tar.gz"
tar -czf "$ARCHIVE" -C "$(dirname "$OUT")" "$NOM" && rm -rf "$OUT"
if [[ -n "${SUDO_USER:-}" ]]; then chown "$SUDO_USER": "$ARCHIVE"; fi
chmod 600 "$ARCHIVE"

etape "Terminé"
echo "Archive : $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))" >&2
CIBLE="${SUDO_USER:-root}@$(hostname -f 2>/dev/null || hostname)"
echo "À récupérer depuis un terminal de ton poste (pas dans cette session SSH), point final compris :" >&2
echo "  scp $CIBLE:$ARCHIVE ." >&2
echo "Puis supprimer la copie sur le VPS : rm $ARCHIVE" >&2
