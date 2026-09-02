---
name: Studexa Core
colors:
  surface: '#fbf9f8'
  surface-dim: '#dcd9d9'
  surface-bright: '#fbf9f8'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f5f3f3'
  surface-container: '#f0eded'
  surface-container-high: '#eae8e7'
  surface-container-highest: '#e4e2e1'
  on-surface: '#1b1c1c'
  on-surface-variant: '#454652'
  inverse-surface: '#303030'
  inverse-on-surface: '#f2f0f0'
  outline: '#767683'
  outline-variant: '#c6c5d4'
  surface-tint: '#4c56af'
  primary: '#000666'
  on-primary: '#ffffff'
  primary-container: '#1a237e'
  on-primary-container: '#8690ee'
  inverse-primary: '#bdc2ff'
  secondary: '#5b5e68'
  on-secondary: '#ffffff'
  secondary-container: '#e0e2ee'
  on-secondary-container: '#61646e'
  tertiary: '#001943'
  on-tertiary: '#ffffff'
  tertiary-container: '#002c6d'
  on-tertiary-container: '#6294ff'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#e0e0ff'
  primary-fixed-dim: '#bdc2ff'
  on-primary-fixed: '#000767'
  on-primary-fixed-variant: '#343d96'
  secondary-fixed: '#e0e2ee'
  secondary-fixed-dim: '#c4c6d2'
  on-secondary-fixed: '#181b24'
  on-secondary-fixed-variant: '#434750'
  tertiary-fixed: '#d9e2ff'
  tertiary-fixed-dim: '#b0c6ff'
  on-tertiary-fixed: '#001945'
  on-tertiary-fixed-variant: '#00429b'
  background: '#fbf9f8'
  on-background: '#1b1c1c'
  surface-variant: '#e4e2e1'
typography:
  display-lg:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
    letterSpacing: -0.01em
  headline-md:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  title-lg:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '500'
    lineHeight: 24px
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  label-lg:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.05em
  label-md:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '500'
    lineHeight: 14px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 4px
  xs: 8px
  sm: 12px
  md: 16px
  lg: 24px
  xl: 32px
  margin-mobile: 20px
  gutter-mobile: 12px
---

## Brand & Style
The design system is engineered for high-focus educational environments, balancing the rigor of academic study with the approachability of a modern mobile experience. The aesthetic follows a **Modern Corporate** direction—relying on systematic layouts, generous whitespace, and a sophisticated color palette to reduce cognitive load. 

The personality is professional yet encouraging, moving away from "gamified" education toward a "productivity tool" mindset. Visuals prioritize clarity and high-fidelity execution, using subtle tonal layering and precise typography to guide the student's journey from flashcards to deep-focus sessions.

## Colors
The palette uses a hierarchical structure to signal importance and interaction:
- **Primary (Deep Indigo):** Reserved for core branding elements, navigation bars, and primary CTAs. It represents stability and focus.
- **Secondary (Lavender-Gray):** Applied to large surfaces, background containers, and inactive states. It softens the interface and prevents visual fatigue.
- **Tertiary (Electric Blue):** Used exclusively for interactive accents, progress indicators, and active selection states to provide a tactile "pop."
- **Semantic Colors:** Use standard emerald for success, amber for warnings, and crimson for errors, all calibrated to match the saturation of the Electric Blue accent.

## Typography
This design system utilizes **Inter** for its exceptional legibility and systematic weight distribution. 
- **Hierarchy:** Headlines use tighter letter spacing and heavier weights to create a strong visual anchor. 
- **Readability:** Body text maintains a 1.5x line-height ratio to ensure long-form educational content is comfortable to read on mobile screens. 
- **Labels:** All-caps styling is reserved for secondary labels and metadata to differentiate them from actionable body text.

## Layout & Spacing
The layout adheres to a **4px baseline grid** for vertical rhythm and a fluid 4-column system for mobile.
- **Margins:** Standard mobile views use a 20px outer margin to provide breathing room.
- **Safe Areas:** Ensure content avoids the hardware "notch" and bottom home indicator through dynamic padding.
- **Section Spacing:** Use 32px (xl) to separate distinct content blocks (e.g., "Recent Courses" vs "Daily Goals") and 16px (md) for internal component spacing.

## Elevation & Depth
Depth is conveyed through a **Tonal Layering** approach combined with soft ambient shadows. 
- **Level 0 (Background):** Solid `#F8F9FA`.
- **Level 1 (Cards):** White background with a 1px border of Lavender-Gray or a very soft shadow (Y: 2, Blur: 8, Opacity: 4% Indigo).
- **Level 2 (Active/Floating):** Higher elevation shadow (Y: 4, Blur: 12, Opacity: 8% Indigo) used for active cards or persistent bottom sheets.
- **Transitions:** Elements should feel physically connected; use subtle scaling (98%) on press states to enhance the tactile feel.

## Shapes
The design system employs a **Rounded** shape language to soften the professional aesthetic. 
- **Standard (8px):** Buttons, input fields, and small cards.
- **Large (16px):** Main content containers and prominent dashboard cards.
- **Pill:** Reserved exclusively for status indicators (e.g., "In Progress") and chips.

## Components
- **Buttons:** Primary buttons use the Deep Indigo background with white text. Secondary buttons use a Lavender-Gray ghost style with Indigo text. The Electric Blue is reserved for "High Action" buttons like "Start Quiz."
- **Input Fields:** Outlined style with a 1px Lavender-Gray stroke. On focus, the stroke shifts to Electric Blue with a subtle 2px outer glow.
- **Cards:** Use a white surface. For educational content, cards should include a 4px vertical accent bar on the left side using the subject's associated color.
- **Progress Bars:** Use a thick 8px track with rounded end-caps. The track is Lavender-Gray and the fill is Electric Blue.
- **Icons:** 24px bounding box, 1.5pt stroke weight, slightly rounded joins. Icons should always be accompanied by a label in nav bars to ensure accessibility.
- **Chips:** Small, 32px height containers for tags or filters. Active chips toggle from a white background to a light tint of Electric Blue with Indigo text.