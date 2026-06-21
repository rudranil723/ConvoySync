# ConvoySync Real-Time Convoy Navigation App

ConvoySync is a real-time navigation mobile app tailored for cars and bikers traveling in groups (convoys). It tracks group members, monitors gaps between them, and uses a multi-agent AI system running Gemini 1.5 Flash to automatically detect anomalies (e.g., a member drifting more than 1.5 km away or making a wrong turn) and recommend safe pull-over locations via Text-To-Speech (TTS).

---

## User Review Required

> [!IMPORTANT]
> **Database Host & Auth Setup**: We will use Supabase for PostgreSQL, Geospatial extensions (PostGIS), and Authentication. Ensure that the Supabase project has the **PostGIS** extension enabled (`CREATE EXTENSION postgis;`).
>
> **Google Places API Key**: The Conductor Agent will require access to the Google Places API. The API key must be provided in the backend configuration (`.env` file) to allow search queries for pull-over spots.
> 
> **Gemini API Key**: The Conductor Agent will use the `gemini-1.5-flash` model via the Google GenAI SDK. We will need a `GEMINI_API_KEY` configured in the backend environment.

---

## Open Questions

> [!WARNING]
> **Geofencing / Deviation Sensitivity**: For "wrong turn" detection, what is the maximum deviation threshold from the convoy's route before we flag a member as off-route? Should we compare their current bearing/heading and proximity to the planned route, or do simple point-to-point pathing analysis?
>
> **Leader/Follower Hierarchy**: What happens if the lead vehicle itself takes a wrong turn or goes off-route? Does the Telemetry Agent treat the lead vehicle as the ground truth route, or is there a pre-planned route they are all expected to follow?

---

## Proposed Changes

### Supabase Database Schema

We will configure PostgreSQL tables with PostGIS columns inside Supabase to handle spatial telemetry data efficiently.

```sql
-- Enable PostGIS extension for geospatial calculations
CREATE EXTENSION IF NOT EXISTS postgis;

-- 1. Profiles Table (Linked to Supabase Auth)
CREATE TABLE public.profiles (
    id UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    display_name VARCHAR(100),
    avatar_url TEXT,
    vehicle_type VARCHAR(20) DEFAULT 'car', -- 'car', 'motorcycle', etc.
    created_at TIMESTAMPTZ DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- 2. Convoys Table
CREATE TABLE public.convoys (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    creator_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    invite_code VARCHAR(10) UNIQUE NOT NULL, -- Short unique code to join
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- 3. Convoy Members Table
CREATE TABLE public.convoy_members (
    convoy_id UUID REFERENCES public.convoys(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    role VARCHAR(20) DEFAULT 'member' NOT NULL, -- 'leader', 'member'
    joined_at TIMESTAMPTZ DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
    PRIMARY KEY (convoy_id, user_id)
);

-- 4. Active Session Telemetry Table (Real-time storage for GIS queries)
CREATE TABLE public.telemetry_logs (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    convoy_id UUID REFERENCES public.convoys(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    location GEOGRAPHY(Point, 4326) NOT NULL, -- PostGIS point
    speed DOUBLE PRECISION,                    -- in meters per second
    bearing DOUBLE PRECISION,                  -- heading/direction in degrees (0-360)
    created_at TIMESTAMPTZ DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- Index telemetry logs for fast spatial-temporal querying
CREATE INDEX telemetry_logs_convoy_user_idx ON public.telemetry_logs (convoy_id, user_id, created_at DESC);
CREATE INDEX telemetry_logs_geo_idx ON public.telemetry_logs USING GIST (location);

-- 5. Convoy Anomalies Table
CREATE TABLE public.convoy_anomalies (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    convoy_id UUID REFERENCES public.convoys(id) ON DELETE CASCADE NOT NULL,
    anomaly_type VARCHAR(50) NOT NULL,        -- 'distance_exceeded', 'wrong_turn'
    description TEXT NOT NULL,
    metadata JSONB,                            -- e.g. current distance, last coords
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- 6. Pull-over Suggestions Table
CREATE TABLE public.pullover_suggestions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    convoy_id UUID REFERENCES public.convoys(id) ON DELETE CASCADE NOT NULL,
    anomaly_id UUID REFERENCES public.convoy_anomalies(id) ON DELETE CASCADE NOT NULL,
    name VARCHAR(255) NOT NULL,
    location GEOGRAPHY(Point, 4326) NOT NULL,
    address TEXT,
    google_place_id VARCHAR(255),
    tts_message TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);
```

---

### Backend Service (FastAPI)

The backend exposes REST endpoints for auth & convoy coordination, alongside a WebSocket hub for broadcasting real-time telemetry and receiving AI safety alerts.

#### [NEW] [config.py](file:///h:/ConvoySync/backend/app/config.py)
Configuration settings loader utilizing `pydantic-settings` to parse environments.

#### [NEW] [database.py](file:///h:/ConvoySync/backend/app/database.py)
Database client interface initialization for Supabase integration.

#### [NEW] [main.py](file:///h:/ConvoySync/backend/app/main.py)
API entrypoint. Mounts HTTP routers and registers WebSocket connections per active convoy.

#### [NEW] [telemetry_router.py](file:///h:/ConvoySync/backend/app/routers/telemetry.py)
Endpoints for submitting positions and establishing WebSocket streams for real-time telemetry relay.

#### [NEW] [geo_service.py](file:///h:/ConvoySync/backend/app/services/geo.py)
Contains geometric algorithms: calculating distance between geo-coordinates using the Haversine formula, and heading/bearing calculations to determine wrong-turn drift.

#### [NEW] [telemetry_agent.py](file:///h:/ConvoySync/backend/app/agents/telemetry_agent.py)
Monitors telemetry streams. Inspects convoy distances against the 1.5 km threshold and evaluates trajectory matching to flag anomalies.

#### [NEW] [conductor_agent.py](file:///h:/ConvoySync/backend/app/agents/conductor_agent.py)
Invoked by telemetry warnings. Queries Google Places API to search for amenities (rest stops, gas stations) 2 miles ahead of the lead user and synthesizes voice commands using Gemini 1.5 Flash.

---

### Frontend Mobile Application (Flutter)

A cross-platform app utilizing Google Maps SDK to show live paths and alert users with voice-synthesized warnings.

#### [NEW] [theme.dart](file:///h:/ConvoySync/frontend/lib/theme.dart)
The high-fidelity dark theme definitions including:
* Primary Background: `#121212` (Deep Charcoal)
* Action Button Accent: `#FF5722` (Saturated Vivid Orange)
* Secondary Text: `#808080` (Muted Grey)
* Primary Text: `#FFFFFF` (White)

#### [NEW] [websocket_service.dart](file:///h:/ConvoySync/frontend/lib/services/websocket_service.dart)
Establishes connection to the backend telemetry stream to broadcast local GPS values and listen for incoming voice warning payloads.

#### [NEW] [tts_service.dart](file:///h:/ConvoySync/frontend/lib/services/tts_service.dart)
Interfacess with the device's native TTS engine (`flutter_tts`) to play audible safety announcements received from the Conductor Agent.

#### [NEW] [map_screen.dart](file:///h:/ConvoySync/frontend/lib/screens/map_screen.dart)
The primary real-time screen with an embedded Google Map showing live positions of all convoy members, a marker highlighting suggested pull-over spots, and HUD indicators styled in the visual theme.

---

## Verification Plan

### Automated Tests
* Run unit tests on geofencing and distance computations:
  `pytest backend/tests/test_geo.py`
* Run integration tests for the agents pipeline (mocking Google Places and Gemini API):
  `pytest backend/tests/test_agents.py`

### Manual Verification
* Establish a mock WebSocket simulation script (`backend/scratch/simulate_convoy.py`) that feeds telemetry coordinates simulating vehicles drifting apart. Confirm the telemetry agent triggers the conductor agent, generates a prompt, and relays the generated pull-over suggestion over the WebSocket.
* Verify on the Flutter emulator or a physical device that received JSON messages trigger the device speaker to vocalize the TTS warning.
