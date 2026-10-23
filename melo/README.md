<p align="center">
  <img src="Logo.svg" alt="Melo Logo" width="100" />
</p>

# Melo

Personalized music streaming engineered for mood, taste, and real-time social listening.

Built with Flutter for iOS and Android.

---

## UI Showcase

| Onboarding & Setup | Home Feed | AI Vibe Generator |
|:---:|:---:|:---:|
| <img src="screenshots/01_onboarding_landing.png" width="260" alt="Landing Screen" /> | <img src="screenshots/02_home_feed.jpg" width="260" alt="Home Screen" /> | <img src="screenshots/03_ai_vibe_generator.jpg" width="260" alt="AI Generator Screen" /> |
| Onboarding & Authentication | Personalized Mixes & Discovery | Natural Language Playlist Generation |

| Now Playing & Lyrics | Playlist View | Library |
|:---:|:---:|:---:|
| <img src="screenshots/04_now_playing_player.jpg" width="260" alt="Music Player Screen" /> | <img src="screenshots/05_playlist_detail.png" width="260" alt="Playlist Screen" /> | <img src="screenshots/06_music_library.jpg" width="260" alt="Library Screen" /> |
| Waveform Player & Synced Lyrics | Curated & Daily Playlists | Liked Songs & Followed Artists |

<p align="center">
  <b>Offline Mode & Local Storage</b><br/><br/>
  <img src="screenshots/07_offline_downloads.jpg" width="260" alt="Offline Mode Screen" /><br/>
  <i>Playback with zero data connection</i>
</p>

---

## Features

- **AI Playlist Generator**: Natural language prompt deconstruction across mood, activity, and environment. Powered by Groq (Llama 3.3) and Google Gemini with live catalog search and Khmer speech-to-text normalization.
- **Adaptive Music Identity**: Learns listening preferences from telemetry (completions, skips, replays) to build dynamic taste profiles and daily mixes.
- **High-Fidelity Audio**: Multi-source adaptive audio streaming pipeline with intelligent background prefetching, fallback caching, and instant playback.
- **Listen Together**: Synchronized multi-user playback over Supabase Realtime channels.
- **Offline Playback**: Encrypted local caching of audio tracks and synchronized LRCLIB lyrics.

---

## Tech Stack

- **Frontend**: Flutter (Dart)
- **Audio Engine**: just_audio, just_audio_background, custom stream decoders
- **Backend & Auth**: Supabase (PostgreSQL, Row Level Security, Realtime channels)
- **AI Models**: Groq (Llama 3.3 70B), Google Gemini 2.5 Flash
- **Catalog & Audio**: Adaptive multi-source audio pipeline, LRCLIB (synced lyrics)

---

## Project Structure

```
Melo/
├── melo/                     # Flutter mobile application
│   ├── android/              # Native Android configuration
│   ├── ios/                  # Native iOS configuration
│   ├── lib/
│   │   ├── config/           # App configuration and API endpoints
│   │   ├── services/         # Core business logic and streaming engines
│   │   ├── view/             # UI screens and navigation
│   │   └── widgets/          # Shared components
│   └── supabase/             # Database schemas and RLS policies
├── screenshots/              # Mobile UI screenshots
└── README.md
```

---

## Getting Started

### Prerequisites

- Flutter SDK (3.27 or higher)
- Dart SDK (3.6 or higher)
- Android Studio / Xcode

### 1. Clone the repository

```bash
git clone https://github.com/VirakSok18/Melo.git
cd Melo/melo
```

### 2. Configure Environment

Copy the templates:

```bash
cp .env.example .env
cp android/app/google-services.json.example android/app/google-services.json
```

Add your project credentials to `.env`:

```properties
GROQ_API_KEY=your_groq_api_key_here
GEMINI_API_KEY=your_gemini_api_key_here
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your_supabase_anon_key_here
GOOGLE_WEB_CLIENT_ID=your_google_web_client_id_here
BACKEND_URL=https://your-backend-url.com
SHARE_BASE_URL=https://melo.app
```

### 3. Install Dependencies

```bash
flutter pub get
```

### 4. Run the Application

```bash
flutter run --dart-define-from-file=.env
```

---

## Security

- No sensitive API keys or private tokens are stored in version control.
- Configuration is loaded via `--dart-define-from-file=.env` and persisted into device-encrypted secure storage (`flutter_secure_storage`).
- Database tables are guarded by Supabase Row Level Security (RLS) policies.

---

## Author

Sok Virak
