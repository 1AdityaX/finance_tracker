---
name: Between
description: Shared costs, one question at a time. Deep teal on warm off-white, Material 3, money in tabular figures.
colors:
  primary: "#176B60"
  on-primary: "#FFFFFF"
  surface: "#FAFAF6"
  on-surface: "#181C1B"
  on-surface-variant: "#3F4946"
  surface-container-low: "#F1F4F2"
  surface-container-high: "#E6E9E7"
  surface-container-highest: "#E0E3E1"
  outline-variant: "#BEC9C5"
  secondary-container: "#CBE9E2"
  on-secondary-container: "#4E6A64"
  owe-amber: "#8A5A00"
  error: "#BA1A1A"
  primary-dark: "#89D4C7"
  surface-dark: "#101413"
  surface-container-low-dark: "#181C1B"
  surface-container-high-dark: "#272B2A"
  on-surface-variant-dark: "#BEC9C5"
  owe-amber-dark: "#F2B866"
typography:
  display:
    fontFamily: "Roboto (Android), SF Pro (iOS)"
    fontSize: "36px"
    fontWeight: 400
    lineHeight: "44px"
    fontFeature: "tnum"
  headline:
    fontFamily: "Roboto (Android), SF Pro (iOS)"
    fontSize: "24px"
    fontWeight: 400
    lineHeight: "32px"
  headline-welcome:
    fontFamily: "Roboto (Android), SF Pro (iOS)"
    fontSize: "28px"
    fontWeight: 400
    lineHeight: "36px"
  title:
    fontFamily: "Roboto (Android), SF Pro (iOS)"
    fontSize: "22px"
    fontWeight: 400
    lineHeight: "28px"
  title-medium:
    fontFamily: "Roboto (Android), SF Pro (iOS)"
    fontSize: "16px"
    fontWeight: 500
    lineHeight: "24px"
    letterSpacing: "0.15px"
  body:
    fontFamily: "Roboto (Android), SF Pro (iOS)"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: "24px"
    letterSpacing: "0.5px"
  body-medium:
    fontFamily: "Roboto (Android), SF Pro (iOS)"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: "20px"
    letterSpacing: "0.25px"
  label:
    fontFamily: "Roboto (Android), SF Pro (iOS)"
    fontSize: "12px"
    fontWeight: 500
    lineHeight: "16px"
    letterSpacing: "0.5px"
    fontFeature: "tnum"
  wordmark:
    fontFamily: "Roboto (Android), SF Pro (iOS)"
    fontSize: "24px"
    fontWeight: 600
    letterSpacing: "-1px"
rounded:
  segment: "2px"
  chip: "8px"
  badge: "12px"
  control: "16px"
  panel: "20px"
  full: "9999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  gutter: "20px"
  xl: "24px"
  section: "28px"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    typography: "{typography.title-medium}"
    rounded: "{rounded.control}"
    height: "56px"
  input-filled:
    backgroundColor: "{colors.surface-container-high}"
    textColor: "{colors.on-surface}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
  input-amount:
    textColor: "{colors.on-surface}"
    typography: "{typography.display}"
  chip-answer:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.on-surface}"
    rounded: "{rounded.chip}"
  review-panel:
    backgroundColor: "{colors.surface-container-low}"
    rounded: "{rounded.panel}"
    padding: "20px"
  command-dock:
    backgroundColor: "{colors.surface-container-low}"
    padding: "8px 16px 12px"
  row-badge:
    backgroundColor: "{colors.surface-container-high}"
    textColor: "{colors.primary}"
    rounded: "{rounded.badge}"
    size: "40px"
  avatar:
    backgroundColor: "{colors.secondary-container}"
    textColor: "{colors.on-secondary-container}"
    rounded: "{rounded.full}"
    size: "40px"
---

# Design System: Between

## Overview

**Creative North Star: "The Plain Ledger"**

Between is a stock Material 3 app tuned until it reads like a short, calm conversation about money. One deep teal carries everything that is interactive or owed to you. Everything else is the scheme's quiet neutrals on a warm off-white. Surfaces stay flat: one rounded panel (the review card) and one tonal dock (the command bar) are the only places where the surface changes. Pages are a single column with a 20px gutter and text that wraps, never truncates.

The voice comes from the copy and the colour of money, not from decoration. Balances are sentences ("3 friends owe you ₹1,750."), with only the figure coloured. Money always sets in tabular figures. Answers already given shrink into outlined chips that read left to right as a sentence.

**Key Characteristics:**
- One brand hue (seed #176B60, fidelity scheme); light surface overridden to warm #FAFAF6.
- Three balance states: teal (owed to you), amber (you owe), muted (even). Red is reserved for errors.
- One family, the platform face (Roboto on Android, SF on iOS) at Material 3 sizes.
- Flat. Depth comes from tone (surface containers), never shadow.
- Generous 16px rounding on controls, 20px on the one panel.

## Colors

One saturated teal on warm off-white, with Material's teal-tinted neutrals doing the rest. Dark mode is the same seed's dark scheme, a teal-tinted near-black.

### Primary
- **Between Teal** (primary): filled buttons, the focused input border, the wordmark, the slash in the command field, row badge icons, the current step segment, and any amount someone owes you. In dark mode it lifts to Pale Teal (primary-dark).

### Neutral
- **Warm Paper** (surface): the light page background, kept from the first version of the app. Dark: surface-dark.
- **Ink** (on-surface): body and headline text.
- **Muted Slate** (on-surface-variant): secondary text, the "n of N" label, ₹ and % unit markers, even (zero) balances.
- **Tonal Low** (surface-container-low): the review panel and the command dock.
- **Tonal High** (surface-container-high): filled input background, row badges. **Tonal Highest** (surface-container-highest): unfilled step segments.
- **Hairline** (outline-variant): dividers (1px) and chip outlines.
- **Mint Container** (secondary-container / on-secondary-container): avatar circles with a single initial.

### Semantic
- **Owe Amber** (owe-amber, owe-amber-dark): any amount you owe. Applied only through `BalanceColors.forSign`.
- **Error Red** (error): validation messages above the Continue button. Nothing else.

### Named Rules
**The Owing Is Not An Error Rule.** Debt is amber, never red. Money colour comes only from `forSign(sign)`: teal when positive, amber when negative, muted slate when zero.

**The Coloured Figure Rule.** In a balance sentence, colour only the amount. The words stay ink.

## Typography

**Display Font:** the platform face (Roboto on Android, SF Pro on iOS), via Material 3's default typography
**Body Font:** the same family

**Character:** One neutral family, so the money and the plain-English questions carry the voice. Hierarchy comes from size, with a 600 weight only on the wordmark and the command slash.

### Hierarchy
- **Display** (400, 36px/44px, tabular): the amount field while entering a value, the quantity stepper value, and the total on the review panel.
- **Headline** (400, 24px/32px): each flow question, "Look right?", and the balance sentence on home, friend and bill screens. The welcome line uses headline-welcome (28px/36px).
- **Title** (400, 22px/28px): the record name on the review panel, the command slash.
- **Title Medium** (500, 16px/24px): section headers, filled-button labels, per-person amounts.
- **Body** (16px and 14px): list titles, review line labels, explanations, balance phrases under friends.
- **Label** (500, 12px/16px, tabular): the "3 of 7" step counter, capped at 1.3x text scale.
- **Wordmark** (600, 24px, -1px tracking, primary): lower-case "between" in the home app bar.

### Named Rules
**The Tabular Money Rule.** Every rupee figure uses `fontFeatures: tabular`, whether in a sentence, a row, a field or a review line.

## Layout

A single column for phones. Everything sits on a 20px horizontal gutter: list tiles, section headers, questions, inputs, the answer strip, the review panel and the Continue button. The command dock uses 16px. Vertical rhythm uses steps of 4, 8, 12, 16 and 24px, and section headers get 28px above them. Rows wrap instead of truncating at large text sizes (chips wrap, trailing amounts scale down to at most 35% of the width). The flow screen pins Continue above the keyboard. When the keyboard is open, the answer strip collapses to one horizontally scrolling line, and its wrapped height is capped at a quarter of the viewport. Touch targets are at least 48dp, and filled buttons are 56dp tall. Tablet layouts are not designed.

## Elevation & Depth

Flat. No shadows are added anywhere. Depth is tonal: the page sits on surface, the review panel and command dock lift one step to surface-container-low, and inputs and badges sit on surface-container-high. The command dock also has a 1px outline-variant divider along its top edge, so the list visibly scrolls underneath it. Snackbars float, using Material's default.

### Named Rules
**The One Panel Rule.** The review card is the only rounded container in the flows. Lists, friends and bills are plain rows, never cards.

## Shapes

Soft and consistent. Controls (filled buttons, filled inputs) round at 16px. The review panel rounds at 20px. Row badges are 40px squares rounded at 12px. Chips keep Material's 8px with a hairline outline. Avatars are full circles. Step segments are 4px bars rounded at 2px with 4px gaps.

## Components

### Buttons
- **Primary:** a full-width FilledButton, 56dp tall, rounded at 16px, with a Title Medium label. One per flow page, pinned at the bottom (Continue, then the save verb).
- **Tonal:** FilledButton.tonalIcon for paired secondary actions on friend and bill screens. IconButton.filledTonal for the quantity stepper's minus and plus buttons (28px icon).
- **Text:** only in the discard-answers dialog.

### Chips
- **Answer chips:** outlined ActionChips holding each given answer as a phrase ("in General", "₹1,200", "paid by you"). Tapping one returns to that question. 8px spacing; they wrap as a sentence.
- **Command chips:** the same ActionChip style in the home dock, labelled with a slash command (/expense, /sent, /receive, /bill).
- **Mode chips:** ChoiceChips in the split editor (Equally, By quantity, By percentage, By amount).

### Cards / Containers
- **Review panel:** surface-container-low, rounded at 20px, 20px padding, no border or shadow. Shows the title, a display-size total, a hairline divider, per-person lines, another divider, then who-owes-whom lines in balance colours with "After this:" captions.
- **Command dock:** a full-width bottom bar on surface-container-low with a top divider. It holds wrapping command chips over a filled command field with a primary "/" prefix.

### Inputs / Fields
- **Filled (default):** surface-container-high fill, 16px radius, no stroke at rest.
- **Focus:** a 2px primary border.
- **Amount:** unfilled, display-size tabular text with a muted "₹ " prefix, on an underline.
- **Error:** the message renders as body-medium in error red above Continue, announced as a live region.

### Navigation
- **Flow app bar:** a back arrow (close on the first page) and a left-aligned title, with close on the right once past the first page. The step bar sits below: one segment per question, current in primary, confirmed in primary at 40% opacity, upcoming in surface-container-highest. "n of N" or "Review" follows the segments.
- **Home:** the wordmark in the app bar, and the command dock in the bottom slot. Ctrl/Cmd+K focuses the command field.

### Rows (signature)
- **Friend row:** an avatar initial, the name, and the balance phrase in its balance colour.
- **Activity row:** a 40px row badge (receipt, or a north-east or south-west arrow), the title, a subtitle of facts joined with " · ", and a TrailingAmount (Title Small, tabular, signed and coloured on a friend's screen).

## Do's and Don'ts

### Do:
- **Do** colour money only through `forSign`: primary when owed to you, owe-amber when you owe, on-surface-variant when even.
- **Do** set every rupee figure in tabular figures.
- **Do** keep a 20px gutter and one full-width 56dp FilledButton (16px radius) as the page's single primary action.
- **Do** express depth with surface-container tones, not shadows.
- **Do** let chips and rows wrap or scale down at large text sizes rather than truncate the question, input or Continue.

### Don't:
- **Don't** use error red for debts. It is only for validation messages.
- **Don't** wrap lists, friends or bills in cards. The review panel is the only rounded container in the flows.
- **Don't** add a second accent hue. Teal and the balance amber are the whole chromatic range.
- **Don't** add strokes to filled inputs at rest. The border appears only on focus.
