# Dakika0 - Peer-to-Peer Delivery App

Dakika0 is a corporate-level, professional Flutter application designed for P2P delivery services. It features a modern design system using Mint Green and Navy Blue, supporting both Light and Dark modes.

## ✨ Key Features

- **Multi-Authentication**: Support for Email and Phone number login.
- **Localization**: Full support for English and Swahili (Kiswahili).
- **Theme Management**: Seamless transition between Light and Dark modes.
- **Modular Architecture**: Feature-based folder structure for scalability and maintainability.
- **Responsive Design**: Built to look stunning on all screen sizes.
- **State Management**: Powered by Riverpod for robust and predictable state handling.
- **User Management**: Dedicated profile settings for managing user preferences and security.

## 🛠️ Tech Stack

- **Framework**: Flutter
- **State Management**: flutter_riverpod
- **Localization**: Native flutter_localizations with JSON files
- **Animations**: flutter_animate
- **Typography**: Google Fonts (Outfit)
- **Icons**: Material Icons & Cupertino Icons

## 📁 Folder Structure

```
lib/
├── core/               # Core utilities, theme, and shared widgets
│   ├── constants/
│   ├── localization/   # Translation logic and providers
│   ├── theme/          # Color schemes and theme data
│   ├── utils/
│   └── widgets/        # Shared UI components
├── features/           # Feature-based modules
│   ├── auth/           # Login, Register, OTP screens
│   ├── dashboard/      # Main hub and stats
│   ├── delivery/       # Request and track deliveries
│   └── profile/        # User management and settings
└── main.dart           # App entry point and provider setup
```

## 🚀 Getting Started

1.  **Install Dependencies**:
    ```bash
    flutter pub get
    ```

2.  **Run the App**:
    ```bash
    flutter run
    ```

## 🎨 Brand Identity

- **Mint Green**: `#ACF0D1` - Used for primary accents and dark mode highlights.
- **Navy Blue**: `#00203F` - Used for corporate branding and light mode primary colors.

## 🌍 Localization

Translations are located in `assets/lang/`:
- `en.json`: English
- `sw.json`: Swahili (Kiswahili)

## 📝 License

This project is for demonstration purposes as part of the Dakika0 delivery ecosystem.
