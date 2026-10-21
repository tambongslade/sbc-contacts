# Fiche App Store Connect — SBC Network (iOS 1.0)

Tout ce qu'il faut saisir dans App Store Connect, dans l'ordre des menus.
Les textes longs sont dans `fr/` et `en/` (un fichier par champ, prêt à
copier-coller, limites de caractères déjà vérifiées).

**Champs à compléter par toi** = marqués ⚠️.

---

## 0. Avant de commencer — à corriger

1. ✅ **Captures iPad** : le build tourne aussi sur iPad, donc App Store Connect
   exige des captures iPad 13". Elles sont dans `../ipad-13/` (2064 × 2752),
   prises sur le simulateur iPad Pro 13" en mode démo.
2. **Langue principale.** Le menu affiche *English (Canada)*, alors que les
   captures et l'app sont en français. Dans *Informations sur l'app → Langue
   principale*, choisir **Français** (ou Français (Canada)), puis ajouter
   l'anglais comme 2ᵉ langue avec les textes de `en/`.

---

## 1. Distribution → Informations sur l'app (App Information)

| Champ | Valeur |
|---|---|
| Nom | `fr/nom.txt` → **SBC Network** (le nom actuel « SBCContacts » peut être remplacé ; il doit être unique sur l'App Store) |
| Sous-titre (FR) | `fr/sous-titre.txt` → L'annuaire SBC dans ta poche |
| Sous-titre (EN) | `en/sous-titre.txt` → Your SBC directory, synced |
| Bundle ID | com.sbc.sbcContacts (déjà fixé) |
| SKU | déjà fixé à la création de l'app, non modifiable |
| Catégorie principale | **Business** (Économie et entreprise) |
| Catégorie secondaire | **Social Networking** (Réseaux sociaux) |
| Droits sur le contenu | « Oui, l'app contient du contenu de tiers » → **et j'ai les droits** (les fiches membres viennent de SBC) |
| Classification par âge | voir §4 |

## 2. Distribution → Tarifs et disponibilité

| Champ | Valeur |
|---|---|
| Prix | **Gratuit** (0 €) |
| Disponibilité | Tous les pays (ou au minimum : Cameroun, Côte d'Ivoire, Sénégal, Togo, France, Canada…) |
| Distribution aux entreprises / B2B | Non (app publique) |

## 3. Distribution → Version iOS 1.0 (la page de ta capture)

| Champ | Valeur |
|---|---|
| Captures iPhone 6,3" (Dynamic Island, écran moyen) | `../iphone-6.3/01…05` (1206 × 2622) |
| Captures iPhone 6,9" (si demandé) | `../iphone-6.9/01…05` |
| Captures iPad 13" | `../ipad-13/01…05` (2064 × 2752) |
| Texte promotionnel | `fr/texte-promotionnel.txt` / `en/texte-promotionnel.txt` |
| Description | `fr/description.txt` / `en/description.txt` |
| Mots-clés | `fr/mots-cles.txt` / `en/mots-cles.txt` |
| URL d'assistance (Support URL) | https://contacts.sniperbusinesscenterlive.com/support/ |
| URL marketing | https://contacts.sniperbusinesscenterlive.com/ |
| Version | 1.0 |
| Copyright | **2026 Sniper Business Center** |
| Build | Choisir le **build 18** (1.0.0) une fois qu'il apparaît comme traité |
| Publication | « Publier manuellement cette version » (conseillé pour la 1ʳᵉ sortie) |

### Informations pour la vérification (App Review Information)

| Champ | Valeur |
|---|---|
| Connexion requise | **Oui** |
| Nom d'utilisateur | ⚠️ le numéro WhatsApp du compte de revue, avec l'indicatif (ex. +237 690 00 00 01) — voir `backend/scripts/set-review-login.ts` |
| Mot de passe | ⚠️ le mot de passe donné à ce script (pas celui du compte SBC) |
| Prénom / Nom | ⚠️ |
| Téléphone | ⚠️ (avec indicatif, ex. +237 …) |
| E-mail | tambongkersten7@gmail.com |
| Notes | coller `notes-app-review.txt` |

Le compte de test doit avoir un abonnement SBC actif : sinon le relecteur
ne voit pas l'annuaire et l'app est refusée (Guideline 2.1).

## 4. Classification par âge (questionnaire)

| Question | Réponse |
|---|---|
| Violence (cartoon, réaliste, prolongée) | Aucune |
| Contenu sexuel / nudité | Aucun |
| Grossièretés / humour grossier | Aucun |
| Alcool, tabac, drogues | Aucun |
| Thèmes matures / suggestifs / horreur | Aucun |
| Jeux d'argent simulés / réels, concours | Non |
| Contenu médical | Non |
| Accès Web non restreint | Non |
| **Contenu généré par les utilisateurs** | **Oui** (les avis laissés sur les membres) |
| Messagerie / chat dans l'app | Non (WhatsApp est une app externe) |
| Publicité | Non |
| Contrôles parentaux / vérification d'âge | Non |

L'app est destinée aux adultes (la politique dit 18+). Si App Store Connect
propose de *relever* la classification, choisir **18+**.

## 5. Confidentialité de l'app (App Privacy)

| Champ | Valeur |
|---|---|
| URL de la politique de confidentialité | https://contacts.sniperbusinesscenterlive.com/privacy/ |
| Collectez-vous des données ? | **Oui** |
| Suivi (tracking) | **Non** pour toutes les données |

Données à déclarer : toutes **liées à l'identité** de l'utilisateur, **non utilisées
pour le suivi**, finalité **Fonctionnalité de l'app** uniquement.

| Catégorie Apple | Type | Pourquoi |
|---|---|---|
| Coordonnées | Nom | Profil reçu de SBC à la connexion |
| Coordonnées | Adresse e-mail | idem |
| Coordonnées | Numéro de téléphone | idem |
| Contenu utilisateur | Autre contenu utilisateur | Avis et scores de confiance laissés sur les membres |
| Identifiants | Identifiant utilisateur | Identifiant de membre SBC |
| Autres données | Autres types de données | Favoris, critères de synchronisation, historique de synchro |

**Ne pas cocher :**
- *Contacts* : l'app lit le carnet d'adresses **sur l'appareil uniquement**. Elle
  n'envoie au serveur que l'identifiant SBC des membres enregistrés et
  l'identifiant local de la fiche créée, jamais les contacts du téléphone.
- *Localisation* : la ville et le pays viennent du profil SBC, pas du GPS.
- *Diagnostics* / *Données d'utilisation* : aucun SDK d'analyse ni de crash.
- Notifications push : non utilisées par la version iOS 1.0 (les alertes sont
  affichées dans l'app).

## 6. Autres liens (si demandés)

| Page | URL |
|---|---|
| Conditions d'utilisation (à mettre dans la description ou en CLUF personnalisé, optionnel) | https://contacts.sniperbusinesscenterlive.com/terms/ |
| Suppression de compte et de données | https://contacts.sniperbusinesscenterlive.com/delete-account/ |
| Page d'accueil | https://contacts.sniperbusinesscenterlive.com/ |

Les cinq pages répondent bien (HTTP 200, vérifié le 09/10/2026).

## 7. Export (chiffrement)

Déjà réglé dans le build : `ITSAppUsesNonExemptEncryption = NO` (HTTPS
standard uniquement). Rien à fournir.

---

## Risques de refus à connaître

Ce sont des points que les relecteurs Apple signalent souvent. Ils ne bloquent
pas la saisie de la fiche, mais ils peuvent entraîner un refus :

1. **Avis entre membres sans « Signaler » ni « Bloquer »** (Guideline 1.2). Une
   app avec du contenu généré par les utilisateurs doit permettre de signaler un
   avis abusif et de bloquer son auteur. Aucun de ces boutons n'existe
   aujourd'hui.
2. **Pas de suppression de compte dans l'app** (Guideline 5.1.1(v)). La
   suppression se fait seulement par e-mail. Comme le compte est créé chez SBC
   et pas dans l'app, ça peut passer, mais l'idéal est un bouton
   « Supprimer mon compte » dans Profil (même s'il ouvre simplement la page
   `/delete-account/`). Ajouter aussi un lien vers la politique de
   confidentialité dans Profil.
3. **Marque SBC** (Guideline 5.2). Si le compte développeur n'est pas au nom du
   Sniper Business Center, Apple peut demander la preuve que tu as le droit
   d'utiliser la marque. Prépare une lettre d'autorisation de SBC.
