# ConvoySync Task List

## Milestone 1: Environment & Backend Setup
- [x] Initialize FastAPI project structure
  - [x] Set up python environment and dependencies (`fastapi`, `uvicorn`, `websockets`, `supabase`, `pydantic-settings`, `google-genai`)
  - [x] Configure `.env.example` and load settings via `app/config.py`
- [/] Supabase Integration & Schema Deployment
  - [ ] Deploy tables and triggers in Supabase instance (pending user SQL execution)
  - [x] Configure database client and verification helper in `app/database.py`

## Milestone 2: Telemetry Calculations & WebSockets
- [x] Implement Geometrical Service (`app/services/geo.py`)
  - [x] Calculate distances between points using Haversine formula
  - [x] Calculate heading / bearing matches to detect wrong turns
- [x] Build WebSocket Telemetry Hub (`app/routers/telemetry.py`)
  - [x] Implement WebSocket connection manager to keep track of active convoys and their connected members
  - [x] Listen for incoming telemetry payloads `(latitude, longitude, speed, bearing)`
  - [x] Broadcast telemetry updates to all other participants in the same convoy

## Milestone 3: Stateful Multi-Agent AI System
- [x] Implement Telemetry Agent (`app/agents/telemetry_agent.py`)
  - [x] Fetch current convoy locations and config from database logs
  - [x] Identify if max vehicle-to-vehicle gap > 1.5 km
  - [x] Identify if a member takes a wrong turn (deviates significantly from route)
  - [x] Flag anomalies and insert into `convoy_anomalies` table (database logging logic stubbed inside background worker)
- [x] Implement Conductor Agent (`app/agents/conductor_agent.py`)
  - [x] Trigger on telemetry anomaly flags
  - [x] Query Google Places API stub to find safe pull-over locations 2 miles ahead of the lead vehicle
  - [x] Build prompt and use Gemini 1.5 Flash to write a concise warning instruction suitable for Text-to-Speech (TTS)
  - [x] Push safety instruction to the WebSocket manager for broadcasting to the convoy
- [x] Integrate Agents Workflow (using unawaited background tasks in telemetry router)

## Milestone 4: Flutter Mobile App & UI Integration
- [/] Initialize Flutter Mobile App
  - [x] Add dependencies (`google_maps_flutter`, `web_socket_channel`, `flutter_tts`, `geolocator`, `supabase_flutter`, `flutter_riverpod`) in `pubspec.yaml`
  - [x] Set up theme styling (#121212 primary background, #FF5722 orange accent, #808080 muted grey, #FFFFFF text) in `lib/theme.dart`
- [/] Implement Authentication & Lobby Screen
  - [x] Sign in / sign up screen layouts in `lib/screens/auth_screen.dart`
  - [x] Create / Join convoy lobby layouts and bottom drawer sheet in `lib/screens/lobby_screen.dart`
- [x] Build Google Maps Telemetry Screen (`lib/screens/map_screen.dart`)
  - [x] Render live Google Map with dark mode style JSON and real-time rider markers
  - [x] Camera follows device GPS position continuously via location_service
  - [x] Periodically broadcast local device telemetry via WebSockets
  - [x] Animated HUD overlay with speed, distance-to-leader, and cross-track error metrics
  - [x] Pulsing vivid orange warning banner on wrong_turn or distance_exceeded flags
  - [x] "Simulate Anomaly" dev button injects mock payload and triggers TTS vocalization
  - [x] Handle incoming WebSocket alert payloads and feed them to the native TTS engine using `flutter_tts`
- [x] Implement Services Layer (`lib/services/`)
  - [x] `supabase_service.dart` — signIn, signUp, real-time convoy/member streams
  - [x] `websocket_service.dart` — connect, streamTelemetry, ai_alert callback hook
  - [x] `location_service.dart` — GPS permission handling, position stream
  - [x] `tts_service.dart` — native TTS with audio focus and duck-others config
- [x] Implement Riverpod Providers (`lib/providers/`)
  - [x] `lobby_provider.dart` — active convoy ID, code, and user role state
  - [x] `telemetry_provider.dart` — rider telemetry map, alert history buffer
