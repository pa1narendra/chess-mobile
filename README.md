# Chess Mobile - Full Stack Application

A comprehensive full-stack chess application featuring a Flutter-based mobile frontend and a Bun-powered backend. This project enables real-time multiplayer games, bot matches against Stockfish, and secure user authentication.

## 🚀 Features

*   **Real-time Multiplayer**: Play chess against other users in real-time.
*   **Play vs Bot**: Challenge the Stockfish engine with adjustable difficulty levels.
*   **User Authentication**: Secure sign-up and login using JWT.
*   **Cross-Platform**: Built with Flutter for seamless performance on Android and iOS.
*   **Modern UI**: Clean and intuitive interface designed with `lucide_icons`.

## 🛠️ Tech Stack

### Mobile App (Client)
*   **Framework**: [Flutter](https://flutter.dev/) (Dart)
*   **State Management**: Provider
*   **Networking**: HTTP & WebSockets
*   **Chess Logic**: `chess` package
*   **UI Components**: Material Design, Lucide Icons

### Backend (Server)
*   **Runtime**: [Bun](https://bun.sh/)
*   **Framework**: [ElysiaJS](https://elysiajs.com/)
*   **Database**: MongoDB (via Mongoose)
*   **Engine**: Stockfish.js & Chess.js

## 📋 Prerequisites

Before you begin, ensure you have the following installed:

1.  **Flutter SDK**: [Install Flutter](https://docs.flutter.dev/get-started/install).
2.  **Android Studio**: [Install Android Studio](https://developer.android.com/studio).
    *   Required for the Android SDK and tools.
    *   Set up an **Android Emulator** via the AVD Manager in Android Studio if you don't have a physical device.
3.  **Bun**: [Install Bun](https://bun.sh/docs/installation).
4.  **MongoDB**: Ensure you have a running MongoDB instance (local or Atlas).

## 🏃‍♂️ Getting Started

### 1. Backend Setup

Navigate to the backend directory:

```bash
cd chess-backend
```

Install dependencies:

```bash
bun install
```

Start the development server:

```bash
bun run dev
```

The server will typically run on `http://localhost:3000`.

### 2. Mobile App Setup

Navigate to the mobile app directory:

```bash
cd real_chess_mobile
```

Install Flutter dependencies:

```bash
flutter pub get
```

#### Running on Android Emulator
1.  Open **Android Studio**.
2.  Launch the **Virtual Device Manager** and start your emulator.
3.  Once the emulator is running, execute:

```bash
flutter run
```

*Note: If connecting to a local backend from the Android emulator, use `10.0.2.2` instead of `localhost` in your API configuration (e.g., inside `lib/const.dart` or your environment config).*

## 📂 Project Structure

*   `chess-backend/`: Contains the server-side logic, API endpoints, and database models.
*   `real_chess_mobile/`: Contains the Flutter application code, assets, and UI logic.
