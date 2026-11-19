# Testing & Quality Assurance

SYNQRA enforces automated testing across all layers to ensure streaming stability, robust regex citation parsing, correct AWS Cognito state transitions, and responsive brutalist layouts.

---

## Running Verification Suites

```bash
# 1. Static code analysis (0 warnings / 0 errors)
flutter analyze

# 2. Automated test suite (All tests passing)
flutter test
```

---

## Test Coverage Breakdown

| Test File | Focus Area | Verified Scenarios |
|---|---|---|
| `test/cognito_auth_test.dart` | AWS Cognito SRP Authentication | Sign-in with valid SRP credentials, confirmation challenges, session refresh, sanitized researcher names, and native logout without browser redirects. |
| `test/rag_stream_repository_test.dart` | Server-Sent Events Protocol | Chunk decoding, status event mapping, cancellation handling, 404 stream fallback, and HTTP errors. |
| `test/rag_session_provider_test.dart` | Stream State Machine | Transitions (`idle` → `streaming` → `completed`), incremental token concatenation, and step duration counters. |
| `test/corpus_selection_test.dart` | Multi-Document Selection | Single-card tapping, multi-card slide range selection, `selectAll`, `clearSelection`, and query scoping payloads. |
| `test/corpus_repository_test.dart` | Multipart Uploads & Cache | Multipart file serialization, SharedPreferences manifest persistence, and upload progress polling. |
| `test/citation_parser_test.dart` | Citation Regex Parsing | Identification of `[1]`, `[2]`, `[1, 2]` patterns, text span chunking, and click-to-preview attribution binding. |
| `test/formatted_answer_test.dart` | Markdown & KaTeX Rendering | Markdown formatting, KaTeX equation parsing, and interactive badge taps. |
| `test/splash_screen_test.dart` | Kinetic Typewriter Animation | Character-by-character timer, blinking cursor state, `[ SKIP >> ]` bypass trigger, and navigation gate. |
| `test/widget_test.dart` | End-to-End Widget Shell | 4-canvas navigation container, Archival Clearance Ledger, and User Profile Dossier. |

---

## Quality Metrics

- **Static Analyzer**: `0` issues found via `flutter analyze`.
- **Automated Tests**: `57` passing tests across unit, repository, provider, and widget suites.
- **Code Formatting**: Fully formatted according to Dart style guide (`dart format .`).
