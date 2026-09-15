# Studexa UI Design Walkthrough

Verified on 2026-09-12 against the current working tree. The design now presents Studexa as a fuller academic portal through layered classroom canvases, prominent role dashboards, richer class cards, stronger information hierarchy, and clearer state treatments. It does not change authentication, navigation destinations, Firestore queries, quiz generation, scoring, submission rules, or any other application workflow.

## Design direction

Studexa keeps its established academic navy and soft lavender/blue identity. The interface uses navy for primary actions and key information, warm white for content surfaces, and subtle lavender/blue backgrounds to separate the application canvas from cards.

| Purpose | Token | Value |
| --- | --- | --- |
| Primary actions and emphasis | `AppTheme.primaryNavy` | `#1A237E` |
| Deep brand accent | `AppTheme.darkNavy` | `#000666` |
| Selected/soft primary surface | `AppTheme.primaryContainer` | `#E8EAF6` |
| Background gradient start | `AppTheme.gradientStart` | `#F3F0FF` |
| Background gradient end | `AppTheme.gradientEnd` | `#EFF6FF` |
| Cards and forms | `AppTheme.surfaceWhite` | `#FBF9F8` |
| Primary text | `AppTheme.textPrimary` | `#1B1C1C` |
| Secondary text | `AppTheme.textSecondary` | `#454652` |
| Borders | `AppTheme.outlineVariant` | `#C6C5D4` |

Green, orange, red, and blue semantic tokens are reserved for success, warning, error, and informational feedback. They clarify state and do not replace the primary brand palette.

## Shared visual system

[`app_theme.dart`](../lib/theme/app_theme.dart) is the source of truth for:

- A readable typography hierarchy from 30dp page headings to 12dp supporting labels, using the platform font.
- A 4–32dp spacing scale.
- Consistent 8dp controls, 12dp inputs/buttons, 14dp cards, and 20dp dialogs.
- Subtle navy-tinted shadows and low-contrast borders instead of heavy elevation.
- Unified input, button, card, dialog, bottom-sheet, divider, snackbar, checkbox, radio, progress, and tooltip styling.
- Transparent Material surface tint so warm-white surfaces retain their intended color.
- Content width limits of 600dp for compact forms and 840dp for dashboards/details on wide screens.

[`studexa_background.dart`](../lib/widgets/studexa_background.dart) adds the shared academic canvas used across authentication, teacher, student, class, quiz, results, and upload experiences. Its low-opacity grid and circular forms use the existing navy/lavender palette and sit behind all controls without intercepting input.

## Academic portal depth

- Teacher and student account summaries are now prominent navy feature panels instead of plain utility cards. Their identity, role, and account actions form one clear dashboard anchor.
- Teacher quick actions use distinct primary and secondary feature cards with large icon tiles, directional cues, stronger depth, and more generous spacing.
- Class cards now read as individual course spaces. Teacher cards include a dedicated course icon, separated enrollment metadata, and a focused upload action. Student cards use a navy course banner, instructor metadata, join-code badge, and a separate destination row.
- The shared surface system uses 18dp cards, 24dp feature panels, layered navy-tinted shadows, subtle outlines, pill chips, and consistent tab typography.
- Class details, quiz review, monitoring, results, upload, join-class, and active-attempt pages use the same academic canvas so navigation feels like one product rather than unrelated forms.

[`main.dart`](../lib/main.dart) applies this system to the normal application and the Firebase connection-error screen.

## Screen coverage

### Entry and authentication

- `SplashScreen` keeps the logo prominent against the brand gradient and uses restrained status feedback.
- `RoleSelectionScreen` presents Teacher and Student as clear, balanced destination cards.
- `LoginScreen` and `RegisterScreen` use centered form widths on desktop, consistent fields and buttons, and wrapping footer actions for narrow screens or larger text.
- `GoogleSignInButton` protects its label from horizontal overflow while retaining its recognizable Google mark.

### Teacher experience

- `TeacherHomeScreen` has a clearer portal header, account/profile surface, compact summary, primary/secondary actions, and consistent class cards. The permanent instructional workflow card was removed to reduce dashboard clutter.
- `TeacherClassDetailsScreen` uses a strong class header, compact join-code treatment, an enclosed three-tab control, consistent material/quiz/student cards, and a visible Retry state for quiz-load failures.
- `UploadGenerateQuizScreen` constrains the configuration form on desktop, groups question controls into clear surfaces, and keeps action labels usable at phone widths.
- `QuizDetailScreen` establishes hierarchy between quiz metadata, actions, question cards, answer information, and print controls.
- `QuizMonitoringScreen` aligns assignment controls and analytics cards, with overflow-safe deadline and action rows.
- `TeacherResultsScreen` uses compact metric cards, a consistent search field, and horizontally scrollable filters on narrow displays.

### Student experience

- `StudentHomeScreen` aligns its portal header, profile actions, class cards, and empty state with the teacher dashboard while keeping student-specific calls to action.
- `StudentClassDetailsScreen` uses the same class-header and tab language, preserving published-Practice visibility, attempts, materials, and people views.
- `JoinClassScreen` is presented as a focused single-purpose form with a compact readable width.
- `AnswerQuizScreen` strengthens question hierarchy, progress visibility, answer selection, skip/next controls, submission states, and results while preserving the existing round-robin and scoring behavior.
- `MaterialViewerScreen` applies the same app bar, surfaces, controls, and width constraints to extracted text, PDF preview, conversion status, and original-file actions.

## Responsive behavior

The design was exercised at 375×812 for a typical phone and 1440×900 for desktop/web. Wide layouts center the useful content instead of stretching cards and forms across the whole screen. Narrow layouts use `Expanded`, `Flexible`, `FittedBox`, wrapping action groups, scrollable filters, and scrollable question indicators where fixed rows would overflow.

No separate desktop workflow was introduced. The same actions and navigation render responsively on each supported target.

## Verification

| Verification | Result |
| --- | --- |
| Full Flutter regression suite | 184/184 passed |
| Auth visual suite | Included in 14/14 dedicated visual checks |
| Teacher core visual suite | Included in 14/14 dedicated visual checks |
| Teacher management visual suite | Included in 14/14 dedicated visual checks |
| Student and material visual suite | Included in 14/14 dedicated visual checks |
| Mobile viewport | 375×812, no captured exceptions/overflow |
| Desktop viewport | 1440×900, no captured exceptions/overflow |
| Static analysis | No issues found |

The dedicated visual tests are:

- [`auth_visual_enhancement_test.dart`](../test/auth_visual_enhancement_test.dart)
- [`teacher_visual_enhancement_test.dart`](../test/teacher_visual_enhancement_test.dart)
- [`teacher_management_visual_test.dart`](../test/teacher_management_visual_test.dart)
- [`student_visual_enhancement_test.dart`](../test/student_visual_enhancement_test.dart)

Local screenshots were generated for every batch at both viewport sizes and visually reviewed. They are verification artifacts rather than application assets and are not bundled into the app.

## Preserved behavior

This design pass retains the existing Teacher and Student roles, session routing, class creation and join-code enrollment, material selection/extraction/upload, Actual and Practice generation, publishing, attempts, scoring, results/history, monitoring, PDF export, and material preview behavior. No package was added, and the Studexa logo was not edited or regenerated.
