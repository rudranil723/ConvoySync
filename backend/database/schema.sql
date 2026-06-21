-- Enable PostGIS extension for geo calculations if needed (optional but good to have)
CREATE EXTENSION IF NOT EXISTS postgis;

-- Clean up existing tables if they exist (for database reset safety)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP TABLE IF EXISTS public.telemetry_logs CASCADE;
DROP TABLE IF EXISTS public.convoy_members CASCADE;
DROP TABLE IF EXISTS public.convoys CASCADE;
DROP TABLE IF EXISTS public.profiles CASCADE;

-- 1. PROFILES TABLE
-- Extends the auth.users table managed by Supabase Auth
CREATE TABLE public.profiles (
    id UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
    display_name TEXT NOT NULL,
    avatar_initial VARCHAR(1) NOT NULL DEFAULT 'U',
    created_at TIMESTAMPTZ DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- 2. CONVOYS TABLE
-- Tracks active convoy sessions and configuration
CREATE TABLE public.convoys (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,
    join_code VARCHAR(6) UNIQUE NOT NULL, -- Upper-case, alphanumeric unique code (e.g. J6LU80)
    creator_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    leader_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    alert_threshold_km DOUBLE PRECISION DEFAULT 1.5 NOT NULL,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
    
    CONSTRAINT join_code_length_check CHECK (length(join_code) = 6)
);

-- Create a unique case-insensitive index on join_code
CREATE UNIQUE INDEX convoys_join_code_upper_idx ON public.convoys (UPPER(join_code));

-- 3. CONVOY MEMBERS TABLE
-- Intersection table for the many-to-many relationship of users in convoys
CREATE TABLE public.convoy_members (
    convoy_id UUID REFERENCES public.convoys(id) ON DELETE CASCADE,
    profile_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
    
    PRIMARY KEY (convoy_id, profile_id)
);

-- 4. TELEMETRY LOGS TABLE
-- Stores GPS history coordinates from active vehicles
CREATE TABLE public.telemetry_logs (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    convoy_id UUID REFERENCES public.convoys(id) ON DELETE CASCADE NOT NULL,
    profile_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    speed DOUBLE PRECISION NOT NULL,       -- meters per second or km/h (standardize in code)
    bearing DOUBLE PRECISION NOT NULL,     -- 0-360 degrees
    timestamp TIMESTAMPTZ DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- Add index to speed up telemetry trajectory path retrieval
CREATE INDEX telemetry_logs_convoy_profile_time_idx ON public.telemetry_logs (convoy_id, profile_id, timestamp DESC);

-- ==========================================
-- AUTOMATIC PROFILE SETUP ON USER SIGNUP
-- ==========================================

-- Trigger function to automatically create a public profile when a user signs up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name, avatar_initial)
  VALUES (
    new.id,
    COALESCE(new.raw_user_meta_data->>'display_name', new.raw_user_meta_data->>'username', 'User'),
    UPPER(SUBSTRING(COALESCE(new.raw_user_meta_data->>'display_name', new.raw_user_meta_data->>'username', 'U'), 1, 1))
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Bind trigger to auth.users insertion
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ==========================================
-- ROW LEVEL SECURITY (RLS) & POLICIES
-- ==========================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.convoys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.convoy_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.telemetry_logs ENABLE ROW LEVEL SECURITY;

-- 1. Profiles Policies
CREATE POLICY "Profiles are viewable by authenticated users" ON public.profiles
    FOR SELECT TO authenticated USING (true);

CREATE POLICY "Users can update their own profile" ON public.profiles
    FOR UPDATE TO authenticated USING (auth.uid() = id);

-- 2. Convoys Policies
CREATE POLICY "Convoys are viewable by authenticated users" ON public.convoys
    FOR SELECT TO authenticated USING (true);

CREATE POLICY "Authenticated users can create convoys" ON public.convoys
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = creator_id);

CREATE POLICY "Creators/leaders can update convoys" ON public.convoys
    FOR UPDATE TO authenticated USING (auth.uid() = creator_id OR auth.uid() = leader_id);

-- 3. Convoy Members Policies
CREATE POLICY "Convoy members are viewable by authenticated users" ON public.convoy_members
    FOR SELECT TO authenticated USING (true);

CREATE POLICY "Authenticated users can join convoys" ON public.convoy_members
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = profile_id);

CREATE POLICY "Members can leave convoys" ON public.convoy_members
    FOR DELETE TO authenticated USING (auth.uid() = profile_id);

-- 4. Telemetry Logs Policies
CREATE POLICY "Telemetry logs are viewable by convoy members" ON public.telemetry_logs
    FOR SELECT TO authenticated USING (
        EXISTS (
            SELECT 1 FROM public.convoy_members
            WHERE convoy_members.convoy_id = telemetry_logs.convoy_id
            AND convoy_members.profile_id = auth.uid()
        )
    );

CREATE POLICY "Members can insert their own telemetry logs" ON public.telemetry_logs
    FOR INSERT TO authenticated WITH CHECK (
        auth.uid() = profile_id
        AND EXISTS (
            SELECT 1 FROM public.convoy_members
            WHERE convoy_members.convoy_id = telemetry_logs.convoy_id
            AND convoy_members.profile_id = auth.uid()
        )
    );
