-- Joué une seule fois, au premier démarrage, sur une base vide.
--
-- postgis    : recherche par distance. Un annuaire d'artisans se consulte
--              « autour de chez moi » ; ST_DWithin sur un index GiST est la
--              seule façon d'avoir des résultats justes et indexables.
-- pg_trgm    : rapprochement approximatif, pour la recherche tolérante aux
--              fautes de frappe.
-- unaccent   : « plombier chauffagiste » saisi sans accents doit trouver.
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;

-- Recherche plein texte en français insensible aux accents. Déclarée ici pour
-- que l'application puisse s'y référer dès la première migration.
CREATE TEXT SEARCH CONFIGURATION fr_sans_accent ( COPY = french );
ALTER TEXT SEARCH CONFIGURATION fr_sans_accent
  ALTER MAPPING FOR hword, hword_part, word
  WITH unaccent, french_stem;
