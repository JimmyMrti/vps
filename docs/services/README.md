# Services applicatifs

Ce dossier décrit **ce qui tourne sur le VPS**, par opposition au socle
(provisionnement, durcissement de l'hôte, frontal Caddy) décrit ailleurs dans
ce dépôt.

| Service | Rôle | Domaine | État |
|---|---|---|---|
| `site` | preventioncambriolage.fr, pages statiques | `preventioncambriolage.fr` | en production |
| `n8n` | automatisation, webhooks entrants | domaine distinct recommandé, repli `auto.preventioncambriolage.fr` | à installer |
| `annuaire` | annuaire artisans enrichi | domaine propre, à choisir | à écrire |

| Document | Contenu |
|---|---|
| [`n8n.md`](n8n.md) | exposition, authentification, ce qu'on interdit à n8n |
| [`annuaire.md`](annuaire.md) | contrat d'exécution de l'application, base de données, recherche |
| [`dimensionnement.md`](dimensionnement.md) | mémoire, CPU, disque, limites par conteneur |
| [`sauvegardes.md`](sauvegardes.md) | quoi, où, à quelle fréquence, et comment on vérifie |
| [`donnees-personnelles.md`](donnees-personnelles.md) | base légale, durées de conservation, règles de diffusion |

---

## Le principe de cloisonnement

Trois services sur une seule machine, c'est trois occasions de se compromettre
l'un l'autre. La règle tenue ici est simple : **deux conteneurs ne se parlent
que si on l'a écrit quelque part.**

```
                  Internet
                     │
              ┌──────┴──────┐        seul conteneur qui publie 80/443
              │    Caddy    │
              └──────┬──────┘
          réseau ────┼──────────────────────────┐  (edge)
                     │                          │
        ┌────────────┼────────────┐             │
        │            │            │             │
   ┌────┴────┐  ┌────┴────┐  ┌────┴─────┐       │
   │  site   │  │   n8n   │  │ annuaire │       │
   └─────────┘  └────┬────┘  └────┬─────┘       │
                     │            │
          réseau ────┤            ├──── réseau  │  (n8n_interne / annuaire_interne)
                     │            │                interne: true
              ┌──────┴───┐  ┌─────┴──────┐
              │ postgres │  │  postgres  │
              │   n8n    │  │  annuaire  │
              └──────────┘  └────────────┘
```

Ce que le schéma impose :

- **Aucun service applicatif ne publie de port.** Sur ce VPS, un `ports:` dans
  un compose ouvre le pare-feu sans passer par UFW — Docker écrit directement
  dans iptables. Le frontal est le seul à avoir le droit de le faire.
- **Chaque base de données vit sur un réseau `internal: true`**, donc sans
  route vers Internet. Une base compromise ne peut pas exfiltrer d'elle-même.
- **Une base par service, pas une base mutualisée.** n8n stocke des
  identifiants d'API chiffrés ; l'annuaire stocke des données de personnes.
  Deux instances PostgreSQL coûtent environ 150 Mo de plus que deux bases dans
  une seule instance — c'est le prix d'un cloisonnement qui tient même si
  quelqu'un obtient le rôle superutilisateur d'un côté.
- **n8n est le seul service qui a une bonne raison d'appeler l'extérieur.**
  C'est aussi celui qui exécute du code fourni par l'utilisateur. Il est donc
  traité comme le maillon le plus exposé, voir [`n8n.md`](n8n.md).

---

## Contrat avec le socle

Ces fichiers supposent que le socle fournit :

| Élément | Attendu |
|---|---|
| Réseau Docker | un réseau externe `edge`, créé une fois : `docker network create edge` |
| Arborescence | `/opt/vps/services/<nom>/` — `docker-compose.yml` en 0644 root:root, `.env` en 0600 root:root |
| Secrets | des fichiers sous `/opt/vps/secrets/<nom>/`, 0600 root:root, jamais dans le compose |
| Frontal | un Caddyfile contenant `import /etc/caddy/sites/*.caddy`, le dossier `sites/` monté en lecture seule depuis `edge/sites/` de ce dépôt |
| Déploiement | le modèle « pull » déjà en place : aucun SSH entrant, un timer systemd tire l'image depuis `ghcr.io` avec un jeton `read:packages` |

Si le socle retient d'autres conventions, seuls les chemins changent : la
répartition des réseaux et des droits, elle, est le cœur du sujet.

---

## Migration à prévoir sur le site existant

Aujourd'hui `docker-compose.prod.yml` de preventioncambriolage embarque son
propre Caddy et publie 80, 443 et 443/udp. Avec un frontal mutualisé, **les
deux se disputeraient les ports**. La bascule :

1. Créer le réseau `edge` et démarrer le Caddy du socle avec, dans ses sites,
   `preventioncambriolage.caddy` (fourni ici).
2. Retirer le service `caddy` de la pile du site et raccorder `web` au réseau
   `edge` — le site continue d'écouter en HTTP simple sur 8080, sans port
   publié, exactement comme aujourd'hui côté conteneur.
3. Reprendre le volume `caddy_data` existant, ou laisser Caddy redemander les
   certificats. Let's Encrypt limite à **5 certificats identiques par semaine**
   : on ne recommence pas cette étape à volonté.

L'ordre compte : tant que l'ancien Caddy tient les ports, le nouveau ne
démarre pas.

---

## Mise en service, dans l'ordre

L'ordre n'est pas indicatif : chaque étape suppose la précédente.

```bash
# 1. Le socle, d'abord : hôte durci, Docker, réseau `edge`, frontal Caddy.
docker network create edge

# 2. Les enregistrements DNS, AVANT le premier démarrage de Caddy sur un
#    nouveau domaine. Caddy demande le certificat immédiatement, et un DNS qui
#    ne résout pas encore fait échouer la demande.

# 3. Les secrets, jamais dans le dépôt.
install -d -m 0700 -o root -g root /opt/vps/secrets/n8n
openssl rand -hex 32 > /opt/vps/secrets/n8n/mdp_postgres
printf 'N8N_ENCRYPTION_KEY=%s\n' "$(openssl rand -hex 32)" \
  > /opt/vps/secrets/n8n/chiffrement.env
chmod 600 /opt/vps/secrets/n8n/*

# 4. La clé de chiffrement n8n est recopiée dans un gestionnaire de mots de
#    passe, hors du serveur. Sans elle, les sauvegardes de n8n ne valent rien.

# 5. La configuration.
cp services/n8n/.env.example /opt/vps/services/n8n/.env
chmod 600 /opt/vps/services/n8n/.env
#    Puis on renseigne N8N_IMAGE avec une version explicite et N8N_DOMAIN.

# 6. Le démarrage.
docker compose -f /opt/vps/services/n8n/docker-compose.yml up -d

# 7. La première connexion crée le compte propriétaire. Activer la double
#    authentification immédiatement : entre le démarrage et cette étape,
#    n'importe qui atteignant l'interface peut créer ce compte.

# 8. Les sauvegardes, avant de saisir quoi que ce soit qu'on regretterait de
#    perdre.
systemctl enable --now sauvegarde.timer verification-sauvegarde.timer \
                       restauration-test.timer surveillance-disque.timer
```

L'étape 7 est celle qu'on oublie. Un n8n fraîchement démarré et joignable
attend que quelqu'un crée le compte propriétaire — **le premier qui arrive
l'obtient.** C'est la raison pour laquelle l'interface est fermée par défaut
dans `edge/sites/n8n.caddy` : même pendant ces quelques minutes, il n'y a pas
de fenêtre.

Pour l'annuaire, l'ordre est le même, avec la migration de schéma intercalée :

```bash
docker compose --profile migration run --rm migration
docker compose up -d
```
