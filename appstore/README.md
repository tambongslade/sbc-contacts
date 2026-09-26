# Captures App Store — SBC Network

Générées le 25/09/2026 depuis le simulateur iPhone 17 Pro Max, app lancée en
mode démo (`-demo`) : **aucune donnée réelle de membre n'apparaît**, tout vient
des fixtures de `DemoMode.swift`. Barre d'état figée à 09:41 (convention Apple).

## Fichiers

| Ordre | Fichier | Écran | Accroche |
|---|---|---|---|
| 1 | `01-annuaire.png`  | Recherche         | Tout l'annuaire SBC dans ta poche |
| 2 | `02-critere.png`   | Nouveau critère   | Crée ton critère en quelques secondes |
| 3 | `03-selection.png` | Revue d'un critère| Tu choisis qui rejoint ton répertoire |
| 4 | `04-synchro.png`   | Tableau Synchro   | Tes contacts restent toujours à jour |
| 5 | `05-confiance.png` | Profil d'un membre| Un score de confiance sur chaque membre |

`_apercu.png` = planche de contact des cinq visuels.

## Tailles

- `iphone-6.9/` → **1320 × 2868** (6,9" — iPhone 17 Pro Max). Taille principale
  demandée par App Store Connect.
- `iphone-6.5/` → **1242 × 2688** (6,5"), au cas où la fiche la réclame encore.

App Store Connect met à l'échelle la 6,9" pour les autres tailles d'iPhone :
téléverser `iphone-6.9/` suffit dans la plupart des cas.

## Régénérer

Les captures brutes viennent de `simctl`, les visuels sont composés en HTML puis
rendus avec Chrome headless. Le script est dans le dossier scratchpad de la
session. Les écrans profonds sont atteints avec les drapeaux debug
`-demo -tab <onglet> -route <écran>` (voir `DemoMode.swift`).
