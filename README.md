# TimerApp

A small native macOS floating focus timer (SwiftUI + AppKit, no dependencies).

## Features

- **Focus / Break / Long break** modes with a Pomodoro cycle (long break every N sessions) and optional auto-start.
- **Companion**: Mochi, Neko or Tomo cheers you on. Its mood follows the timer: ready, focused, pumped, final stretch, worried when paused, celebrating when done, relaxing on breaks, and dozing off when you've been idle a while. Click it for a bounce.
- **Alarm tones**: pick any system sound or your own audio file, plus repeat count and volume.
- **Resizable**: drag the bottom-right corner, use the Size slider in settings, or press ⌘+ / ⌘− / ⌘0.
- **Intention**: type what you're working on; it shows while the session runs.
- **Ambient sound**: white, pink or brown noise during focus sessions.
- **Menu bar timer** with quick controls; closing the window keeps the timer running there.
- **Stats**: today's focus time, sessions, daily streak and a 7-day chart (click the footer).
- **Shortcuts**: Space start/pause, R reset, S skip, Esc leave a text field, ⌘W hide, ⌘Q quit.

## Build

```bash
./build.sh
```

This compiles with `swiftc` and produces `TimerApp.app` in this folder. Double-click it to run, or copy it to `/Applications`.
