/// Names of Supabase RPCs (implemented in `supabase/migrations`).
///
/// Parameter names are part of the contract; see docs/CONTRACTS.md.
abstract final class SupabaseRpc {
  /// `find_user_by_email(p_email text) returns table(id uuid, display_name text,
  ///   email text)`
  /// Exact, case-insensitive match; returns 0 or 1 row.
  static const String findUserByEmail = 'find_user_by_email';

  /// `copy_subject(p_subject_id uuid) returns uuid` (new subject id).
  static const String copySubject = 'copy_subject';

  /// `copy_note(p_note_id uuid, p_target_subject_id uuid) returns uuid`.
  static const String copyNote = 'copy_note';

  /// `copy_quiz(p_quiz_id uuid, p_target_subject_id uuid,
  ///   p_target_note_id uuid default null) returns uuid`.
  static const String copyQuiz = 'copy_quiz';
}
