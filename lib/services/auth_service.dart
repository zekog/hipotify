import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';

class AuthService {
  static SupabaseClient get _client {
    if (!SupabaseConfig.isConfigured) {
      throw Exception("Supabase not initialized. Please check your configuration.");
    }
    return Supabase.instance.client;
  }

  static User? get currentUser => SupabaseConfig.isConfigured ? _client.auth.currentUser : null;
  static Session? get currentSession => SupabaseConfig.isConfigured ? _client.auth.currentSession : null;
  static bool get isLoggedIn => SupabaseConfig.isConfigured && _client.auth.currentSession != null;

  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? username,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: username != null ? {'username': username} : null,
    );
    
    if (response.user != null && username != null) {
      // Create profile entry
      await _client.from('profiles').upsert({
        'id': response.user!.id,
        'username': username,
      });
    }
    
    return response;
  }

  /// Ensures a profile exists for the current user.
  /// This prevents foreign key violations if the user signed up before profile logic was added.
  static Future<void> ensureProfileExists() async {
    final user = currentUser;
    if (user == null) return;

    try {
      // Use upsert to handle both "missing" and "already exists" cases cleanly
      await _client.from('profiles').upsert({
        'id': user.id,
        'username': user.email?.split('@')[0] ?? 'User',
      }, onConflict: 'id');
      print("AuthService: Profile ensured for ${user.id}");
    } catch (e) {
      print("AuthService: Error ensuring profile: $e");
      // Don't rethrow here if it's just a duplicate key or similar non-critical issue,
      // but the foreign key error later will catch it if it truly failed.
    }
  }

  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  static Future<void> signOut() async {
    if (SupabaseConfig.isConfigured) {
      await _client.auth.signOut();
    }
  }

  static Stream<AuthState> get authStateChanges {
    if (!SupabaseConfig.isConfigured) return const Stream.empty();
    return _client.auth.onAuthStateChange;
  }
}
