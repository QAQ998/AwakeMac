# AwakeMac UI specification

## Design intent

AwakeMac is a quiet utility that should feel bundled with macOS. Its core action must be understandable in under five seconds: see the current wake state, choose a duration, and toggle it. The interface uses standard controls, system spacing, system typography, semantic colors, and SF Symbols. It avoids custom cards, decorative imagery, invented metrics, and excessive glass effects.

## Context answers

- Narrative role: operational control surface, not a dashboard or promotional page.
- Viewing distance: approximately 50–90 cm on a Mac display.
- Visual temperature: calm and trustworthy; green indicates safely active, orange indicates an approaching deadline or safety warning, red only indicates failure.
- Capacity: the 340 pt menu popover holds one primary action, two subordinate choices, conditional safety status, and two footer commands without scrolling.

## Surfaces

- Menu popover: 340 pt wide, natural height up to 430 pt. Header, large wake toggle, duration picker, clamshell toggle, conditional notice, footer.
- Settings: 520×420 pt default, resizable. Native tabbed Settings scene with General, Safety, and About tabs.
- Small widget: state, remaining time, one toggle action.
- Medium widget: state and clamshell summary on the left; 30 min, 1 hour, unlimited, and stop actions on the right.
- First-use safety sheet: native warning icon, concise risk copy, Cancel and Continue/Open System Settings actions.

## State rules

- Off: moon symbol, secondary text, wake toggle off. Clamshell control is disabled.
- Active: sun symbol and system green status. Duration is editable while running.
- Under five minutes: orange remaining-time text; no flashing.
- No-lid device or capability-query failure: clamshell row remains visible, disabled, and explains why. No helper installation is attempted.
- Advanced mode: laptop symbol and explicit “experimental” copy. It is never enabled silently from a widget or after restart.
- Language and appearance changes reflow text; English can wrap to two lines, never scale down below the standard text style.

## Accessibility

- Native controls provide keyboard and VoiceOver behavior.
- All icon-only buttons have labels and hints.
- Semantic colors are accompanied by text and symbols.
- Layout is checked in light, dark, increased contrast, reduce transparency, and reduce motion modes.

