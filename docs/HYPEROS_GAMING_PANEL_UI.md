# Hyper OS Gaming Control Panel UI

## A. App Structure

Path: `apps/hyperos-gaming-panel/`

- `src/App.jsx` — shell layout, header, transitions, page state.
- `src/components/Sidebar.jsx` — navigation rail.
- `src/components/Dashboard.jsx` — live metric cards with charts.
- `src/components/Controls.jsx` — game mode toggle + performance controls.
- `src/lib/mockMetrics.js` — lightweight local telemetry mock.
- `tailwind.config.js` — Hyper OS dark/neon tokens.

## B. UI Design

- Left sidebar with minimal navigation.
- Main content card with dashboard on top and controls below.
- Rounded 2xl cards, soft glow, high contrast text.
- Dark surface (`#0b0f14`) with cyan/purple neon accents.

## C. React Code

Core implemented features:
- Animated dashboard metric cards (CPU/GPU/RAM/FPS).
- Central game mode toggle with glow state.
- Performance controls via governor/scheduler dropdowns.
- Driver status and Vulkan health badge in header.

## D. Styling (Tailwind)

Custom Hyper palette in `tailwind.config.js`:
- `hyper.bg`, `hyper.panel`, `hyper.text`
- accent colors: `hyper.cyan`, `hyper.purple`
- custom shadows: `shadow-neon`, `shadow-purple`

## E. Animations (Framer Motion)

- Fade/slide transitions for content changes.
- Hover lift on cards and nav entries.
- Toggle glow state changes on game mode button.

## F. Future Improvements

1. Replace mock telemetry with backend IPC to `hyperos-gamed`.
2. Add profile editor with schema validation.
3. Add plugin tabs (streaming, overlays, capture).
4. Add theme presets and per-user layout density.
