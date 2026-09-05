# FeisClár Android App (Release Guide & Installation)

## Overview
**FeisClár** is the dedicated offline-first mobile companion for Irish dancers, teachers, and parents. It enables seamless tracking of feis competitions, dance results, grade progression, countdowns, and syllabus discovery.

---

## Key Features

- **Feis Discovery & Interactive Map**: Browse upcoming feiseanna across Ireland, the UK, Europe, North America, and Australia. Filter by event type (*Major*, *Provincial*, *Open*, *Confined*).
- **Personal Dancer Vault**: Track multiple dancers, record competition placements (Solo, Trophy, Championship, NCH), judge marks, and personal bests.
- **Visual Results Share Card**: Generate beautiful shareable celebration graphics with separate sections for Solos and Championship/Trophy dances.
- **Calendar & Reminders**: Add any feis directly into your native device calendar with start/end times, venue addresses, syllabus links, entry portal links, and notes.
- **Dynamic Tile Indicators**:
  - Crisp white feis tile icons with dynamic colored rings matching the event type (Gold for Major, Blue for Provincial, Red for Confined, Green for Open).
  - Clear **CANCELLED** banner overlay for cancelled events.
- **Offline First**: All dancer records, bookmarks, and feis data are stored locally in SQLite and encrypted private device storage.

---

## How to Install the APK on Android

1. **Download the APK**:
   - Download `feisclar.apk` from [feisclar.com](https://feisclar.com) or transfer the file to your device.
2. **Allow Unknown Apps**:
   - When opening the APK for the first time, Android may prompt: *"For your security, your phone is not allowed to install unknown apps from this source"*.
   - Tap **Settings** in the prompt and toggle **"Allow from this source"** (or enable *Install unknown apps* for your browser/file manager).
3. **Install & Launch**:
   - Tap **Install**. Once finished, tap **Open** to launch FeisClár.

---

## Quick Start in the App

1. **Select Organisation**:
   - On first launch, use the **Organisation** dropdown on the welcome card to choose your dancing organization (e.g. *CLRG*, *An Comhdháil*, *CRN*, *WIDA*, etc.).
2. **Add a Dancer**:
   - Tap the dancer profile avatar in the top-right corner to add your dancer's name, birth year, and home region.
3. **Bookmark Feiseanna**:
   - Head to the **Search** tab to explore upcoming competitions. Bookmark events to receive reminders or tap **Add to Calendar** to sync event details to your native device calendar.
4. **Log & Share Results**:
   - After a competition, record your results in the **Vault** tab and tap **Share** to export a formatted results card for family and social media.

---

## Technical Specifications

- **Platform**: Android 8.0+ (API 26+)
- **Framework**: React Native 0.79 / Expo SDK 53
- **Local Storage**: SQLite (expo-sqlite) + Secure AsyncStorage
- **Calendar & Notifications**: Native device integration (expo-calendar, expo-notifications)
- **Backend Sync**: Render Cloud API (`https://feisclar-backend.onrender.com`)
