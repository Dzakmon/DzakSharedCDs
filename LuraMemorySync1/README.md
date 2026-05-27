# Ura Memory Sync

---

---

# 🇬🇧 English

WoW addon for the **L'ura** boss (Midnight) — tracks the symbol memory game with real-time raid synchronization.

---

## Installation

1. Copy the `UraMemorySync/` folder into:
   ```
   World of Warcraft/_retail_/Interface/AddOns/
   ```
2. Launch WoW and enable the addon under **AddOns** on the character selection screen.

---

## Slash commands

| Command      | Action                                  |
|--------------|-----------------------------------------|
| `/ums`       | Open / close the main window            |
| `/ums clear` | Clear the pattern and notify the raid   |
| `/ums rw`    | Send a manual Raid Warning              |
| `/ura`       | Open / close the main window (alias)    |

---

## How to use

1. The L'ura boss displays **5 symbols in a specific order**.
2. Click the corresponding symbols in the bottom row — they appear in an **arc**.
3. After **4 clicks**, the 5th missing symbol is **added automatically**.
4. Use the buttons to share the pattern with the raid:

| Button              | Effect                                                  |
|---------------------|---------------------------------------------------------|
| **Send**            | Sends the pattern to all addon users                    |
| **/SAY**            | Displays the pattern in local chat                      |
| **RW**              | Visual Raid Warning arc on screen                       |
| **SAY + Raid Alert** | Both simultaneously                                   |
| **Clear**           | Resets the pattern and notifies the raid                |

---

## Symbols

| Icon     | Name (EN)  | Name (FR) |
|----------|------------|-----------|
| ♦ purple | Diamond    | Losange   |
| ▼ green  | Triangle   | Triangle  |
| ● orange | Circle     | Rond      |
| ✕ red    | Cross      | Croix     |
| T yellow | T          | T         |

---

## Features

- **Auto language detection**: the addon automatically displays in English or French based on your WoW client language. You can still switch manually at any time.
- **Multilingual**: `[FR] / [EN]` button at the top left to switch language on the fly. Your preference is saved between sessions.
- **Visual arc**: symbols displayed in an arc in the window and in the Raid Warning, numbered 1 to 5.
- **Auto-complete**: selecting 4 out of 5 symbols automatically completes the pattern.
- **Duplicate protection**: the same symbol cannot be clicked twice.
- **Resizable**: drag the handle at the bottom right to adjust the window size.
- **Fade animations**: the SAY popup and Raid Warning overlay fade in and out smoothly.
- **Persistent positions**: window positions are saved between sessions.
- All raid members must have the addon installed to receive patterns and visual alerts.

---

---

# 🇫🇷 Français

Addon WoW pour le boss **L'ura** (Midnight) — suivi du jeu de mémoire de symboles avec synchronisation raid en temps réel.

---

## Installation

1. Copier le dossier `UraMemorySync/` dans :
   ```
   World of Warcraft/_retail_/Interface/AddOns/
   ```
2. Lancer WoW et activer l'addon dans **Addons** sur l'écran de sélection de personnage.

---

## Commandes slash

| Commande      | Action                               |
|---------------|--------------------------------------|
| `/ums`        | Ouvre / ferme la fenêtre principale  |
| `/ums clear`  | Efface le schéma et prévient le raid |
| `/ums rw`     | Envoie une Alerte Raid manuelle      |
| `/ura`        | Ouvre / ferme la fenêtre (alias)     |

---

## Utilisation

1. Le boss L'ura affiche **5 symboles dans un ordre précis**.
2. Cliquer les symboles correspondants dans la rangée du bas — ils apparaissent en **arc de cercle**.
3. Après **4 clics**, le 5ème symbole manquant est **ajouté automatiquement**.
4. Utiliser les boutons pour partager le schéma avec le raid :

| Bouton                 | Effet                                                 |
|------------------------|-------------------------------------------------------|
| **Envoyer**            | Envoie le schéma aux autres utilisateurs de l'addon  |
| **/DIRE** / **/SAY**   | Affiche le schéma dans le chat local                 |
| **AR** / **RW**        | Alerte Raid visuelle en arc de cercle à l'écran      |
| **DIRE + Alerte Raid** | Les deux simultanément                               |
| **Effacer**            | Remet à zéro et prévient le raid                     |

---

## Symboles

| Icône    | Nom (FR)  | Nom (EN)  |
|----------|-----------|-----------|
| ♦ violet | Losange   | Diamond   |
| ▼ vert   | Triangle  | Triangle  |
| ● orange | Rond      | Circle    |
| ✕ rouge  | Croix     | Cross     |
| T jaune  | T         | T         |

---

## Fonctionnalités

- **Détection automatique de la langue** : l'addon s'affiche automatiquement en français ou en anglais selon la langue de votre client WoW. Vous pouvez toujours basculer manuellement.
- **Multilingue** : bouton `[FR] / [EN]` en haut à gauche pour basculer la langue à la volée. Votre préférence est sauvegardée entre les sessions.
- **Arc visuel** : les symboles s'affichent en arc de cercle dans la fenêtre et dans l'Alerte Raid, numérotés de 1 à 5.
- **Auto-complétion** : sélectionner 4 symboles sur 5 complète automatiquement le schéma.
- **Protection doublons** : impossible de cliquer deux fois le même symbole.
- **Redimensionnable** : glisser l'angle en bas à droite pour ajuster la taille de la fenêtre.
- **Animations** : le popup SAY et l'overlay Alerte Raid apparaissent et disparaissent en fondu.
- **Positions persistantes** : les positions des fenêtres sont sauvegardées entre les sessions.
- Tous les joueurs du raid doivent avoir l'addon installé pour recevoir les schémas et les alertes visuelles.
