# Relevé de la machine

`scripts/releve-vps.sh` photographie le VPS tel qu'il tourne vraiment, pour
écrire la documentation d'après la machine et non d'après le dépôt. Il se lance
en SSH sur le VPS : aucun clone du dépôt n'est nécessaire là-bas.

## Lancer

Depuis son poste, dans le dossier où se trouve le script :

```sh
scp scripts/releve-vps.sh <vps>:/tmp/
ssh -t <vps> 'sudo bash /tmp/releve-vps.sh'
scp '<vps>:/tmp/releve-vps-*.tar.gz' .
ssh <vps> 'rm /tmp/releve-vps.sh /tmp/releve-vps-*.tar.gz'
```

Le relevé dure moins d'une minute. `RELEVE_LOGS=0` (à placer après `sudo`)
retire les dernières lignes de journaux, qui contiennent des adresses IP de
visiteurs.

## Ce qu'il fait, et ce qu'il ne fait pas

Il **lit** seulement : aucune installation, aucun redémarrage, aucun
`apt update`, aucune écriture hors de son dossier de sortie sous `/tmp`.
L'archive produite est en `0600` et appartient au compte qui a lancé `sudo`.

| Fichier de l'archive | Contenu |
|---|---|
| `00-RESUME.md` | la vue d'ensemble : système, ports ouverts, pare-feu, conteneurs, projets Compose, unités propres |
| `01-systeme.txt` | matériel, disques, montages, occupation, processus |
| `02-paquets*` | paquets installés à la main, dépôts APT, mises à jour en attente |
| `03-comptes.txt` | comptes, groupes sensibles (`sudo`, `docker`), empreintes des clés SSH autorisées |
| `04-reseau.txt` | interfaces, routes, ports en écoute, UFW, nftables, iptables |
| `05-ssh.txt` | configuration effective de `sshd` (`sshd -T`) |
| `06-durcissement.txt` | fail2ban, AppArmor, sysctl de sécurité, mises à jour automatiques, auditd, SUID |
| `07-*.txt` | services, minuteurs, unités propres à la machine et scripts qu'elles lancent, cron |
| `08-docker*` | moteur, conteneurs et leurs réglages de sécurité, images, réseaux, volumes, `docker inspect` complet |
| `09-frontaux.txt` | vus de l'intérieur : Caddyfile et extraits, `caddy adapt`, certificats détenus, `nginx -T`, versions PostgreSQL et n8n |
| `10-journaux-conteneurs.txt`, `12-journaux.txt` | dernières lignes, avertissements du démarrage |
| `11-arborescences.txt` | `/srv`, `/opt`, `/etc/caddy`, `/var/www` : droits, tailles, dépôts git |
| `fichiers/` | copie des fichiers de configuration, à leur chemin d'origine |

## Secrets

Masqués avant l'archivage, remplacés par `***MASQUÉ***` :

- les clés privées au format PEM ;
- toute valeur dont le nom évoque un secret (`PASSWORD`, `SECRET`, `TOKEN`,
  `*_KEY`, `AUTH`, `SALT`, `DSN`…), sous les formes `NOM=valeur`,
  `nom: valeur` et `"nom": "valeur"` — ce qui couvre l'environnement des
  conteneurs dans `docker inspect` ;
- **toutes** les valeurs des fichiers `.env`, des `EnvironmentFile` systemd et
  des fichiers d'environnement Compose : les noms de variables restent ;
- les identifiants dans les URL (`postgres://user:***@…`), les en-têtes
  `Authorization`, les jetons GitHub, GitLab, AWS, Slack et les JWT ;
- les empreintes de mots de passe (`$6$…`, bcrypt, argon2).

Jamais copiés : `shadow`, clés d'hôte SSH, `authorized_keys`, `.docker/config.json`,
`.netrc`, `.pgpass`, fichiers `*.key`, dossiers `secrets/` et `.ssh/`. La liste
de ce qui a été écarté est dans `fichiers-ecartes.txt`.

Le masquage repose sur des motifs : un secret rangé sous un nom anodin passe.
Le script signale en fin de course les motifs de clé ou de jeton qui
resteraient. **Relire l'archive avant de la partager** : même masquée, elle
donne les noms de comptes, les adresses IP et l'organisation du serveur.
