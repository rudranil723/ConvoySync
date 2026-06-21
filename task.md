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
- [ ] Implement Telemetry Agent (`app/agents/telemetry_agent.py`)
  - [ ] Fetch current convoy locations from the real-time cache or latest database logs
  - [ ] Identify if max vehicle-to-vehicle gap > 1.5 km
  - [ ] Identify if a member takes a wrong turn (deviates significantly from route)
  - [ ] Flag anomalies and insert into `convoy_anomalies` table
- [ ] Implement Conductor Agent (`app/agents/conductor_agent.py`)
  - [ ] Trigger on telemetry anomaly flags
  - [ ] Query Google Places API to find safe pull-over locations (e.g. gas station, rest stop) 2 miles ahead of the lead vehicle
  - [ ] Build prompt and use Gemini 1.5 Flash to write a concise warning instruction suitable for Text-to-Speech (TTS)
  - [ ] Push safety instruction to the WebSocket manager for broadcasting to the convoy
- [ ] Integrate Agents Workflow (using LangGraph or custom stateful workers)

## Milestone 4: Flutter Mobile App & UI Integration
- [ ] Initialize Flutter Mobile App
  - [ ] Add dependencies (`google_maps_flutter`, `web_socket_channel`, `flutter_tts`, `geolocator`, `supabase_flutter`)
  - [ ] Set up theme styling (#121212 primary background, #FF5722 orange accent, #808080 muted grey, #FFFFFF text) in `lib/theme.dart`
- [ ] Implement Authentication & Lobby Screen
  - [ ] Sign in / sign up screen using Supabase Auth
  - [ ] Create / Join convoy lobby using code sharing
- [ ] Build Google Maps Telemetry Screen (`lib/screens/map_screen.dart`)
  - [ ] Render live Google Map with markers representing all active convoy members
  - [ ] Periodically broadcast local device telemetry via WebSockets
  - [ ] Handle incoming WebSocket alert payloads and feed them to the native Text-To-Speech engine using `flutter_tts`
