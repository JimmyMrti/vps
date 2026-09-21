# Conformité ANSSI

Ce que le socle applique, guide par guide, et ce qu'il n'applique pas.

---

## Sur les références

Les mesures ci-dessous sont rattachées aux **guides** de l'ANSSI et à leurs
thèmes, pas à des numéros de recommandation.

C'est délibéré. Les numéros `R<n>` changent d'une version à l'autre du guide,
et une citation fausse dans un document de sécurité est pire qu'une absence de
citation : elle se recopie, et personne ne la revérifie. Les guides sont donc
cités par leur titre et leur référence, avec leur URL. Le rapprochement
recommandation par recommandation, s'il est souhaité pour un audit, se fait
sur le PDF à jour.

| Guide | Référence | Où |
|---|---|---|
| Recommandations de configuration d'un système GNU/Linux | ANSSI-BP-028 v2.0 | <https://cyber.gouv.fr/publications/recommandations-de-securite-relatives-un-systeme-gnulinux> |
| Recommandations pour un usage sécurisé d'(Open)SSH | note technique | <https://cyber.gouv.fr/publications/recommandations-pour-un-usage-securise-dopenssh> |
| Recommandations de sécurité relatives à TLS | ANSSI-BP-035 | <https://cyber.gouv.fr/publications/recommandations-de-securite-relatives-tls> |
| Recommandations de sécurité pour la journalisation | note technique | <https://cyber.gouv.fr/publications/recommandations-de-securite-pour-la-mise-en-oeuvre-dun-systeme-de-journalisation> |
| Recommandations relatives au déploiement de conteneurs Docker | note technique | <https://cyber.gouv.fr/publications/recommandations-de-securite-relatives-au-deploiement-de-conteneurs-docker> |

---

## Système — ANSSI-BP-028

| Thème du guide | Ce qui est fait | Où |
|---|---|---|
| Minimisation des services installés | Retrait de `telnet`, `rsh`, `nis`, `avahi`, `cups`, `rpcbind`, `nfs-common`, `snapd` | `roles/socle` |
| Modules noyau inutiles | Systèmes de fichiers exotiques, DCCP, SCTP, RDS, TIPC, FireWire, Bluetooth, stockage USB interdits par `install … /bin/false` | `roles/socle` |
| Options de montage | `/tmp` et `/dev/shm` en `nosuid,nodev,noexec` | `roles/socle` |
| Paramètres noyau | `kptr_restrict`, `dmesg_restrict`, `ptrace_scope`, `suid_dumpable`, liens protégés, BPF non privilégié désactivé, `sysrq` coupé | `roles/socle` |
| Paramètres réseau | Pas de routage, pas de source routing, pas de redirections ICMP, `rp_filter`, SYN cookies, `log_martians` | `roles/socle` |
| Contrôle d'accès obligatoire | AppArmor activé et vérifié | `roles/socle` |
| `umask` par défaut | `027` | `roles/socle` |
| Comptes de service | Coquille `nologin`, root verrouillé, aucune console root | `roles/comptes` |
| Élévation de privilèges | Groupe `sudo`, journalisation des entrées-sorties, `use_pty` | `roles/comptes` |
| Mises à jour | `unattended-upgrades` sur les seules origines de sécurité, `needrestart` automatique | `roles/mises_a_jour` |
| Cloisonnement des services réseau | Conteneurs sans capacités, sans élévation, sur réseaux séparés | `roles/docker`, `roles/proxy` |

## SSH — note technique (Open)SSH

| Thème | Ce qui est fait |
|---|---|
| Authentification | Par clé exclusivement, mot de passe et clavier interactif désactivés |
| Compte root | Connexion directe interdite |
| Comptes autorisés | `AllowUsers` limité au seul compte d'administration |
| Échange de clés | `curve25519-sha256` en tête, groupes Diffie-Hellman de moins de 3072 bits retirés de `/etc/ssh/moduli` |
| Chiffrement | ChaCha20-Poly1305 et AES-GCM d'abord ; rien sans authentification intégrée |
| Intégrité | Uniquement des MAC en mode *encrypt-then-MAC*, rien en SHA-1 |
| Clés d'hôte | Ed25519 et RSA seulement ; DSA et ECDSA supprimées |
| Rebond | `X11Forwarding`, `AllowAgentForwarding`, `AllowTcpForwarding`, `PermitTunnel` tous désactivés |
| Tentatives | `MaxAuthTries 3`, `LoginGraceTime 20`, plus `fail2ban` et une limite de débit nftables |
| Journalisation | `LogLevel VERBOSE`, qui trace l'empreinte de la clé utilisée |

## TLS — ANSSI-BP-035

| Thème | Ce qui est fait |
|---|---|
| Versions | TLS 1.2 en plancher, 1.3 privilégié ; tout le reste refusé |
| Suites | ECDHE uniquement (confidentialité persistante), AEAD uniquement ; ni RSA statique, ni CBC, ni SHA-1 |
| Courbes | `x25519`, `secp384r1`, `secp256r1` |
| HSTS | Posé au point de terminaison TLS, un an, sous-domaines compris |
| Certificats | Let's Encrypt, renouvellement automatique, `CAA` limitant l'émission à cette seule autorité |

Caddy ne permet pas de choisir les suites TLS 1.3 : elles sont fixées par la
norme et toutes acceptables.

## Journalisation — note technique

| Thème | Ce qui est fait |
|---|---|
| Persistance | `journald` en `Storage=persistent` — sans quoi un redémarrage efface tout, y compris celui qu'un correctif déclenche à 4 h 30 |
| Intégrité | `Seal=yes` : la retouche d'une entrée devient détectable |
| Rétention | 60 jours, 512 Mo, rotation hebdomadaire |
| Débit | Limité, pour qu'un incident bavard ne chasse pas le contexte utile |
| Audit système | `auditd` sur les comptes, sudo, SSH, pare-feu, socket Docker, `/opt`, chargement de modules, changements d'heure |
| Verrouillage | Règles d'audit immuables (`-e 2`) : toute tentative de désactivation exige un redémarrage, donc se voit |
| Journal applicatif | Accès du frontal en JSON, rotation `logrotate`, lisible par `fail2ban` |

## Conteneurs — note technique Docker

| Thème | Ce qui est fait |
|---|---|
| Source des paquets | Dépôt officiel Docker, pas celui d'Ubuntu qui est en retard de correctifs |
| Privilèges | `no-new-privileges` au niveau du démon et de chaque conteneur |
| Capacités | `cap_drop: ALL` partout ; seul le frontal reçoit `NET_BIND_SERVICE` |
| Système de fichiers | Site statique en `read_only` avec `tmpfs` pour ce qui doit être écrit |
| Cloisonnement réseau | Un réseau d'exposition partagé, un réseau `internal` par pile pour les bases |
| Exposition | Un seul conteneur publie des ports |
| Ressources | Limites mémoire et processeur sur chaque service |
| Journaux | Rotation à 10 Mo × 3, sinon un conteneur bavard remplit le disque |
| Images | Étiquettes de version figées, ménage hebdomadaire des images remplacées |

---

## Écarts assumés

Les voici en clair. Un écart écrit et justifié vaut mieux qu'une conformité
affichée et fausse.

### 1. Le groupe `docker` équivaut à root

Qui peut parler à la socket Docker peut monter n'importe quel chemin de l'hôte
dans un conteneur privilégié. C'est inhérent au mode classique, pas un défaut
de configuration.

**Pourquoi c'est accepté.** Le mode *rootless* supprime ce point mais
complique les ports privilégiés, ne gère pas les mêmes options réseau, et
demanderait de réécrire l'ensemble des piles pour un serveur administré par
une personne.

**Ce qui le compense.** Le compte d'administration est protégé comme un compte
root : clé SSH à phrase de passe, mot de passe verrouillé, `AllowUsers`
restreint. La socket Docker est surveillée par `auditd`. La liste des membres
du groupe est affichée à chaque passage du playbook.

### 2. Pas de partitionnement séparé

Le guide recommande des partitions distinctes pour `/var`, `/var/log`, `/tmp`
et `/home`, avec leurs options de montage.

**Pourquoi c'est accepté.** Le partitionnement d'un VPS OVH est figé à
l'installation. L'obtenir imposerait de réinstaller la machine, donc de
couper un site en production.

**Ce qui le compense.** `/tmp` et `/dev/shm` sont montés en mémoire avec
`nosuid,nodev,noexec`, ce qui porte l'essentiel du gain. La croissance des
journaux est bornée par `journald` et `logrotate`, et l'occupation du disque
est surveillée.

### 3. Pas de mot de passe sur le chargeur de démarrage

**Pourquoi c'est accepté.** Sur un VPS, l'accès « physique » passe par la
console de l'espace client OVH : protéger GRUB déplace le problème vers le
compte OVH sans le supprimer. Et un mot de passe GRUB fait courir le risque
d'un serveur qui ne redémarre plus seul après une mise à jour du noyau — avec
les redémarrages automatiques à 4 h 30, ce serait une panne silencieuse.

**Ce qui le compense.** Le compte OVH doit être protégé par une
authentification à double facteur. C'est la vraie barrière.

### 4. Le trafic sortant n'est pas filtré

**Pourquoi c'est accepté.** Le restreindre supposerait de tenir à jour la
liste des destinations légitimes : registres d'images, ACME, dépôts apt,
stockage de sauvegarde, et tous les appels sortants de n8n — dont l'objet même
est d'appeler des services tiers arbitraires. Une telle liste dérive, puis est
désactivée en catastrophe un soir de panne.

**Ce qui le compense.** Les bases de données sont sur des réseaux `internal`,
sans route vers l'extérieur : ce qui a le plus de valeur est déjà privé de
sortie.

### 5. Pas de chargement de modules verrouillé après démarrage

`kernel.modules_disabled = 1` empêcherait Docker de charger à la volée les
modules réseau dont il a besoin.

**Ce qui le compense.** La liste des modules interdits, et la surveillance
`auditd` des appels de chargement.

### 6. Pas de contrôle d'intégrité des fichiers

Ni AIDE, ni équivalent.

**Pourquoi.** Sur une machine dont la quasi-totalité du contenu utile est en
conteneurs immuables reconstruits depuis un registre, un contrôle d'intégrité
du système de fichiers de l'hôte apporte peu et produit beaucoup de bruit.

**À réexaminer** si la machine accueille un jour des composants installés
directement sur l'hôte.

### 7. Pas de protection contre le déni de service

Un VPS seul n'y résiste pas. La réponse, si le besoin apparaît, est de passer
les domaines derrière un service de filtrage en amont. Ce n'est pas fait, et
ce n'est pas un oubli.
