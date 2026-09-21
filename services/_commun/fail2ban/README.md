# fail2ban pour le frontal

À installer côté socle : ces fichiers vont dans `/etc/fail2ban/`.

Ils comblent un manque assumé : **Caddy ne sait pas limiter le débit sans
greffon**, et reconstruire Caddy pour cela ajouterait une chaîne de
compilation à maintenir sur une machine qui n'en a aucune. Le bannissement
après coup n'est pas équivalent — il punit au lieu de lisser — mais il coûte
un fichier de configuration au lieu d'une image sur mesure.

```
filter.d/caddy-abus.conf   →  /etc/fail2ban/filter.d/caddy-abus.conf
action.d/docker-user.conf  →  /etc/fail2ban/action.d/docker-user.conf
jail.d/caddy.conf          →  /etc/fail2ban/jail.d/caddy.conf
```

Le journal lu est `/var/log/caddy/acces.log`, produit par l'extrait
`journal_acces` de [`edge/sites/00-extraits.caddy`](../../../edge/sites/00-extraits.caddy).
Il doit être monté depuis l'hôte dans le conteneur Caddy, sans quoi fail2ban ne
voit rien :

```yaml
volumes:
  - /var/log/caddy:/var/log/caddy
```

## Le piège : bannir sans rien bloquer

`fail2ban` insère ses règles dans la chaîne `INPUT`. **Le trafic à destination
d'un conteneur Docker ne passe pas par `INPUT`** : il traverse `FORWARD` et les
chaînes `DOCKER`. Une règle posée dans `INPUT` ne bloque donc rien, et
`fail2ban-client status` affiche pourtant des adresses bannies — la panne la
plus discrète qui soit.

C'est la même mécanique que celle qui fait qu'un conteneur publiant un port
contourne UFW.

L'action `docker-user` fournie ici insère dans la chaîne **`DOCKER-USER`**, que
Docker consulte avant ses propres règles et ne réécrit jamais. C'est le seul
endroit où un bannissement porte réellement sur le trafic des conteneurs.

## Vérifier que ça bloque vraiment

```bash
fail2ban-client status caddy-abus        # des adresses bannies ?
iptables -n -L DOCKER-USER               # et la chaîne f2b y est-elle ?
iptables -n -L f2b-caddy-abus            # avec les adresses dedans ?
```

Les trois doivent concorder. Si la première liste des adresses et que les
autres sont vides, rien n'est bloqué.
