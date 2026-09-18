-- Backfill Member.country from the région SBC did send.
--
-- SBC's contact search returns no country field at all, so every member
-- mirrored so far has country NULL and a criteria asking for "Pays: Cameroun"
-- matched only the handful that got a country from elsewhere. Ingest now
-- derives it (see common/utils/region-country.ts); this reaches the rows
-- already in the mirror, which no amount of future ingest will re-send.
--
-- Only régions belonging to exactly one country are used. Shared names
-- ("Centre" is Cameroon and Burkina Faso, "Littoral" is Cameroon and Benin)
-- are deliberately left NULL: matching widens a country criteria over those at
-- query time, which is reversible, whereas a wrong country written here is not.
--
-- Only rows with no country are touched. The comparison folds case and
-- surrounding space, but not accents: unaccent() is an extension that is not
-- installed everywhere, and a migration that fails to apply is far worse than
-- one that leaves a few accented spellings for the query-time widening to
-- catch.
UPDATE members m
SET country = r.country
FROM (VALUES
  ('Maritime', 'TG'),
  ('Abidjan', 'CI'),
  ('Ouest', 'CM'),
  ('Atlantique', 'BJ'),
  ('Plateaux', 'TG'),
  ('Brazzaville', 'CG'),
  ('Ouémé', 'BJ'),
  ('Kara', 'TG'),
  ('Pointe-Noire', 'CG'),
  ('Borgou', 'BJ'),
  ('N''Djamena', 'TD'),
  ('Centrale', 'TG'),
  ('Dakar', 'SN'),
  ('Hauts-Bassins', 'BF'),
  ('Estuaire', 'GA'),
  ('Niamey', 'NE'),
  ('Zou', 'BJ'),
  ('Sud', 'CM'),
  ('Mono', 'BJ'),
  ('Bas-Sassandra', 'CI'),
  ('Centre-Ouest', 'BF'),
  ('Adamaoua', 'CM'),
  ('Bamako', 'ML'),
  ('Plateau', 'BJ'),
  ('Couffo', 'BJ'),
  ('Yamoussoukro', 'CI'),
  ('Extrême-Nord', 'CM'),
  ('Comoé', 'CI'),
  ('Lagunes', 'CI'),
  ('Collines', 'BJ'),
  ('Centre-Est', 'BF'),
  ('Boucle du Mouhoun', 'BF'),
  ('Kadiogo', 'BF'),
  ('Atacora', 'BJ'),
  ('Alibori', 'BJ'),
  ('Sassandra-Marahoué', 'CI'),
  ('Donga', 'BJ'),
  ('Vallée du Bandama', 'CI'),
  ('Gôh-Djiboua', 'CI'),
  ('Ogooué-Maritime', 'GA'),
  ('Chari-Baguirmi', 'TD'),
  ('Montagnes', 'CI'),
  ('Kinshasa', 'CD'),
  ('Zinder', 'NE'),
  ('Centre-Nord', 'BF'),
  ('Zanzan', 'CI'),
  ('Bangui', 'CF'),
  ('Haut-Katanga', 'CD'),
  ('Haut-Ogooué', 'GA'),
  ('Congo', 'CD'),
  ('Ouaddaï', 'TD'),
  ('Thiès', 'SN'),
  ('Mayo-Kebbi Est', 'TD'),
  ('Logone Occidental', 'TD')
) AS r(region, country)
WHERE m.country IS NULL
  AND m.city IS NOT NULL
  AND lower(btrim(m.city)) = lower(r.region);
