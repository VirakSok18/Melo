<p align="center">
  <img src="Logo.svg" alt="Melo Logo" width="100" />
</p>

# Melo — Intelligent Music Streaming & Social Audio Platform

Personalized music streaming engineered for mood, taste, and real-time social listening. 

Melo offers a dual-mode architecture: a **Standalone Serverless Mobile App** (Flutter + Supabase) that runs out-of-the-box with zero backend hosting, and an optional **Spring Boot Enterprise Microservice Backend** (`SpringBackend/`) for high-throughput streaming proxies, Bakong KHQR payment processing, and external API normalization.

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

## Key Features

- **AI Playlist Generator**: Natural language prompt deconstruction across mood, activity, and environment. Powered by Groq (Llama 3.3) and Google Gemini with live catalog search and Khmer speech-to-text normalization.
- **Adaptive Music Identity**: Learns listening preferences from telemetry (completions, skips, replays) to build dynamic taste profiles and daily mixes.
- **High-Fidelity Audio**: Multi-source adaptive audio streaming pipeline with intelligent background prefetching, fallback caching, and instant playback.
- **Listen Together**: Synchronized multi-user playback over Supabase Realtime channels.
- **Offline Playback**: Encrypted local caching of audio tracks and synchronized LRCLIB lyrics.
- **Bakong KHQR Integration**: Native Cambodian national QR payment standard support via Spring Boot backend for merchant transactions.

---

## Architecture & Modes

Melo is designed to operate flexibly in two modes:

### 1. Standalone / Frontend-First Mode (Current Mobile Release)
- **Direct Supabase Integration:** Authentication, User Profiles, Liked Songs, Custom Playlists, and Realtime Listen-Together sync run directly against Supabase with PostgreSQL Row Level Security (RLS).
- **Direct Catalog & AI:** Client directly reaches verified audio sources and Groq AI without requiring any self-hosted proxy server.
- **Cost:** 100% Free hosting overhead for mobile distribution.

### 2. Microservice Mode (Spring Boot Backend)
- **Proxy & Audio Caching:** `SpringBackend` handles server-side streaming decoding (Deezer/Spotify/YouTube), rate limiting, and edge caching.
- **Payment Verification:** Processes Bakong KHQR webhooks and verifies cryptographic payment signatures.
- **Centralized Email & OTP:** Relays transactional email OTP verification.

---

## Project Structure

```text
Melo/
├── melo/                         # Flutter Mobile Application (iOS & Android)
│   ├── android/                  # Native Android configuration & build scripts
│   ├── ios/                      # Native iOS configuration
│   ├── lib/
│   │   ├── config/               # App configuration, theme, and API routing
│   │   ├── services/             # Audio engines, Supabase client, and AI
│   │   ├── view/                 # UI screens (Home, Player, Search, Profile)
│   │   └── widgets/              # Shared audio widgets and animated visualizers
│   └── supabase/                 # Idempotent PostgreSQL schemas & RLS policies
├── SpringBackend/                # Spring Boot (Java 21) Microservice
│   ├── src/main/java/com/melo/
│   │   ├── config/               # Spring Beans (Supabase, Bakong, Spotify, Groq)
│   │   ├── controller/           # REST endpoints for search, stream & payments
│   │   ├── service/              # Audio streaming proxy and AI generator logic
│   │   └── security/             # Rate-limiting filter and security rules
│   ├── src/main/resources/       # application.properties and seed catalogs
│   ├── Dockerfile                # Production container deployment definition
│   └── pom.xml                   # Maven dependencies (Spring Boot 3, Lombok, etc.)
├── screenshots/                  # Mobile UI showcase captures
└── README.md                     # Monorepo documentation
```

---

## Getting Started

### Prerequisites

- **Flutter SDK**: 3.27 or higher
- **Java JDK**: 21 or higher (for Spring Boot backend)
- **Maven**: 3.8+ (or use included `./mvnw`)
- **Supabase Account**: Free PostgreSQL database

---

### Part 1: Mobile App Setup (Flutter)

1. **Navigate to the mobile app directory:**
   ```bash
   cd melo
   ```

2. **Configure Environment:**
   Copy the example environment template:
   ```bash
   cp .env.example .env
   ```
   Provide your Supabase URL, Anon Key, and Groq/Gemini API keys.

3. **Install Dependencies:**
   ```bash
   flutter pub get
   ```

4. **Run the Application:**
   ```bash
   flutter run
   ```

5. **Build Release APK:**
   ```bash
   flutter build apk --split-per-abi --release
   ```

---

### Part 2: Backend Setup (Spring Boot)

If you wish to run the Java microservice locally or deploy it to a cloud provider (e.g., Railway, Render, AWS):

1. **Navigate to the backend directory:**
   ```bash
   cd SpringBackend
   ```

2. **Configure Environment Secrets:**
   Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```
   Fill in your service tokens (Bakong token, Spotify Client ID/Secret, Groq API Key).

3. **Run with Maven:**
   ```bash
   # On Windows (PowerShell):
   .\mvnw.cmd spring-boot:run

   # On Linux/macOS:
   ./mvnw spring-boot:run
   ```
   The backend will start at `http://localhost:8080`.

4. **Run with Docker:**
   ```bash
   docker build -t melo-backend .
   docker run -p 8080:8080 melo-backend
   ```

---

## Security & Secrets Management

- **Zero Committed Secrets:** All production API keys, database credentials, and payment tokens are loaded exclusively through environment variables (`.env`) or cloud environment configs.
- **Git Protection:** `.gitignore` strictly blocks `.env`, `*.log`, build targets (`target/`, `build/`), and internal credential files from ever reaching version control.
- **Row Level Security:** Supabase PostgreSQL database tables are protected with granular user-scoped RLS policies.

---

## Author

**Sok Virak** — [@VirakSok18](https://github.com/VirakSok18)
