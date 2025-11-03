
class SupabaseConstants {
  // Values are loaded from dart-define at build/run time when provided.
  // Defaults below preserve the current values for local/manual runs.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://uwvymdexcapqxpbjaous.supabase.co',
  );
  

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV3dnltZGV4Y2FwcXhwYmphb3VzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjE4NDE3NzMsImV4cCI6MjA3NzQxNzc3M30.Nexpj5GoNp97UqTNdJ-6xQMB_05mauBbswr69neAZkw',
  );
}