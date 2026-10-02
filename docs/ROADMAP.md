# Roadmap (decided with the product owner, 2026-10-02)

Overall look: **minimal & clean** (Notion/Obsidian-like: neutral palette,
typography-first, dense but airy, subtle subject color accents only).

## Wave 1 — AI sources, gating, attachments
- **AI gating**: AI entry points are always visible but *locked* (greyed, lock
  icon) until a provider key + model are configured; tapping opens a "Set up
  AI" sheet linking to Settings. Readiness exposed as one provider.
- **Capabilities**: per provider/model, which input kinds are supported
  (text, pdf, image, audio, video, youtube). Attachment options only appear
  when the selected model supports that kind.
- **Attachments** (saved per subject, "Files" library, Supabase Storage,
  shared along with the subject, copied on copy_subject): PDF, images,
  text files (.txt/.md/.docx — text extracted in-app, works with all models),
  audio/video (Gemini only). Reusable across generations.
- **Note picker**: choose existing notes as source material — search and
  multi-select across *all* my notes and notes shared with me.
- **AI generate screen** sources: free text, selected notes, attachments
  (library or upload new), YouTube URL.

## Wave 2 — Study
- **Flashcard decks**: new syncable, shareable, copyable item in subjects and
  notes (front/back cards). Per-user spaced repetition schedule (FSRS or
  SM-2), "Due today" queue across subjects. AI deck generation.
- **Review mistakes**: auto-collect wrongly answered questions into a
  per-user Mistakes practice set.
- **Exam mode**: time limit, feedback only at the end, question pools
  (random N from a quiz).
- **Progress dashboard** (home): streak, quizzes taken, accuracy per subject,
  weakest topics, due cards, recent activity.

## Wave 3 — AI extras & organization
- **Chat** with a note/subject/attachment, answers cite sources; chats saved
  and synced, private to the user (never shared).
- **AI note tools**: summarize, simplify, expand, translate, study guide.
- **AI in quizzes**: "Explain this" on review; optional AI grading for short
  answers (self-grade stays default).
- **Search everywhere** (subjects, notes, quizzes, decks, attachments).
- **Tags, pin, sort, filter, archive.**
- **Richer notes**: LaTeX math, code highlighting, tables, checklists,
  better toolbar.
- **Export/import**: notes → Markdown/PDF, quizzes → JSON/CSV, CSV import.
