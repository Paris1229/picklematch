# PickleMatch

PickleMatch is a Flutter app for managing pickleball sessions, queueing players, creating fair matchups, tracking leaderboards, and recording results.

## Overview

This repository contains the mobile app for PickleMatch. It includes:

- player management
- queue-based matchmaking
- skill-based pairing logic
- live court tracking
- leaderboard rankings
- match history
- local SQLite persistence

## Project structure

- `pm/` — Flutter application source code
- `logo.jpg` — app logo asset

## Requirements

- Flutter SDK
- Dart SDK
- Android Studio or VS Code with Flutter extensions

## Run locally

```bash
cd pm
flutter pub get
flutter run
```

## App features

- Add and edit players
- Track win/loss records and skill levels
- Match players by queue order or skill balance
- Generate scheduled court matches
- Record scores and update ratings
- Save match history locally

## Notes

The app stores data locally with SQLite so it can run without a backend service.
