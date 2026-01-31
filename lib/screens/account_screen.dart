import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/supabase_config.dart';
import '../utils/snackbar_helper.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    if (SupabaseConfig.url == 'YOUR_SUPABASE_URL') {
      return Scaffold(
        appBar: AppBar(title: const Text('Account')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32.0),
            child: Text(
              'Supabase not configured.\nPlease set URL and API Key in lib/services/supabase_config.dart',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: StreamBuilder(
        stream: AuthService.authStateChanges,
        builder: (context, snapshot) {
          if (AuthService.isLoggedIn) {
            return _buildProfileView();
          }
          return _buildAuthForm();
        },
      ),
    );
  }

  Widget _buildProfileView() {
    final user = AuthService.currentUser!;
    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: [
        const Center(
          child: CircleAvatar(
            radius: 50,
            child: Icon(Icons.person, size: 50),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Text(
            user.email ?? 'No email',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text(
            'Logged in via Supabase',
            style: TextStyle(color: Colors.grey),
          ),
        ),
        const SizedBox(height: 48),
        _buildActionButton(
          icon: Icons.sync,
          label: 'Manual Sync',
          onPressed: () async {
            setState(() => _isLoading = true);
            await CloudSyncService.syncLikes();
            setState(() => _isLoading = false);
            if (mounted) showSnackBar(context, 'Sync Complete');
          },
        ),
        const SizedBox(height: 16),
        _buildActionButton(
          icon: Icons.logout,
          label: 'Logout',
          color: Colors.red,
          onPressed: () async {
            await AuthService.signOut();
            setState(() {});
          },
        ),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.only(top: 16.0),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Widget _buildAuthForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isLogin ? 'Login' : 'Create Account',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),
          if (!_isLogin) ...[
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _isLoading ? null : _handleAuth,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Theme.of(context).primaryColor,
            ),
            child: _isLoading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(_isLogin ? 'LOGIN' : 'SIGN UP', style: const TextStyle(color: Colors.white)),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => setState(() => _isLogin = !_isLogin),
            child: Text(_isLogin ? "Don't have an account? Sign Up" : "Already have an account? Login"),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: Icon(icon),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          foregroundColor: color,
          side: color != null ? BorderSide(color: color) : null,
        ),
        onPressed: onPressed,
      ),
    );
  }

  Future<void> _handleAuth() async {
    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        await AuthService.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        await AuthService.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          username: _usernameController.text.trim(),
        );
      }
      // Success will trigger StreamBuilder update
    } catch (e) {
      if (mounted) showSnackBar(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
