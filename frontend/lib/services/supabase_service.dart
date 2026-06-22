import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final SupabaseService instance = SupabaseService._internal();
  SupabaseService._internal();

  // Placeholder configurations. Users should replace these with their own live keys.
  static const String _supabaseUrl = 'https://your-project.supabase.co';
  static const String _supabaseAnonKey = 'your-anon-key-placeholder';

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await Supabase.initialize(
        url: _supabaseUrl,
        anonKey: _supabaseAnonKey,
      );
      _isInitialized = true;
    } catch (e) {
      // Gracefully catch initialization exceptions when running placeholder configuration
      print('Supabase SDK Initialization warning: $e');
    }
  }

  SupabaseClient get client => Supabase.instance.client;

  // Email authentication wrapper
  Future<AuthResponse> signInWithEmail(String email, String password) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<AuthResponse> signUpWithEmail(String email, String password) async {
    return await client.auth.signUp(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await client.auth.signOut();
  }

  // Stream active convoys
  Stream<List<Map<String, dynamic>>> streamConvoys() {
    try {
      return client.from('convoys').stream(primaryKey: ['id']).map((event) => event);
    } catch (e) {
      print('Error streaming convoys: $e');
      return const Stream.empty();
    }
  }

  // Stream members of a convoy
  Stream<List<Map<String, dynamic>>> streamConvoyMembers(String convoyId) {
    try {
      return client
          .from('convoy_members')
          .stream(primaryKey: ['convoy_id', 'user_id'])
          .eq('convoy_id', convoyId)
          .map((event) => event);
    } catch (e) {
      print('Error streaming convoy members: $e');
      return const Stream.empty();
    }
  }
}
