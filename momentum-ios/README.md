# Momentum for iPhone

Native SwiftUI prototype for iOS 17+. Momentum helps university students **start**
the tasks they keep putting off: it turns a task into a tiny first step, runs a
focus session, handles the moment you get distracted, and shows — over the week —
which important work you keep avoiding. Tasks and sessions are stored locally as
JSON; there is no account or backend.

## Main tasks the prototype supports

1. **Start an avoided task** — pick the task, see or generate a two‑minute first
   step, and begin a focus session.
2. **Stay with the task when distracted** — a running timer with a non‑punishing
   "I got distracted" action that keeps you in the session instead of quitting.
3. **See what you keep avoiding** — the Today screen and the weekly Progress view
   surface tasks that are never started or untouched the longest, plus local
   insights generated from your own data.

## Current prototype

- **Today** (home): day streak, minutes focused today, a prominent *Start a focus
  session* action, a *What you keep putting off* list, and today's sessions.
- **Focus session** (modal, several views → closes to Today): choose task → set a
  tiny first step (with a *Suggest a first step* assist) → run a 25/15/5‑minute
  timer with pause and *I got distracted* → review and save.
- **Tasks**: all tasks grouped To‑do / Done, sorted by how much they are being
  avoided; hierarchical push to a **task detail** with its session history.
- **Progress**: weekly focused minutes per day (Mon–Sun), sessions, full blocks,
  distractions, the postponed‑tasks list, and explainable *Momentum Insights*.
- Local persistence (JSON in the app's Documents directory) and an undo snackbar.
- The prototype is seeded with the user‑test scenario data ("Alice"); *Reset
  sample day* restores it.

## Run

Open `Momentum.xcodeproj` in Xcode (15 or newer) and run the `Momentum` scheme on
an iPhone simulator (e.g. iPhone 15) or a device.

## Model checks

Run:

```sh
./test-model.sh
```

The checks cover the avoidance ranking, days‑untouched, streaks, first‑step
suggestions, weekly aggregation, validation, and JSON persistence. They use the
Swift interpreter and need no simulator.
