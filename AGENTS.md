# AGENTS.md

## Project Overview

This repository contains a lightweight MATLAB-based serial waveform monitor for DSP/MCU debugging.

The project is intended to remain general-purpose and should not be coupled to a specific Boost converter, LLC converter, inverter, DSP model, or other single hardware project unless explicitly requested.

The main application entry point is expected to be:

```matlab
DSPSerialMonitor
```

The application should remain easy to run directly from MATLAB without requiring App Designer, external packages, or additional launch scripts.

---

## General Working Rules

- Read the relevant source files completely before making changes.
- Understand the current data flow and GUI structure before modifying code.
- Make the smallest change that correctly satisfies the task.
- Do not perform unrelated refactors.
- Preserve existing working behavior unless the task explicitly requests a change.
- Prefer incremental, reviewable changes over large rewrites.
- Keep the current coding style unless there is a clear technical reason to change it.
- Do not create unnecessary files.
- If a task has its own Plan `.md` file, read that Plan before modifying code and treat it as the task-specific specification.
- When instructions conflict, follow the user's latest explicit request first.

---

## Scope

The project is a general serial waveform monitor.

Do not hard-code application logic around names such as:

```text
Boost
Vin
Vout
IL
Iout
Duty
```

These may be valid user-configured channel names, but the application itself should treat incoming values as generic channels.

Prefer generic concepts such as:

```text
Channel
Plot
Serial Data
Waveform
Display Settings
```

---

## MATLAB Requirements

- Use MATLAB `.m` source files.
- Keep compatibility with MATLAB R2019b or newer unless the user explicitly changes this requirement.
- Prefer built-in MATLAB functionality.
- Do not introduce additional toolbox dependencies without approval.
- Do not introduce third-party MATLAB packages without approval.
- Continue using `uifigure`, `uigridlayout`, `uiaxes`, and related built-in UI components where appropriate.
- Do not migrate the application to App Designer `.mlapp` unless explicitly requested.
- Do not create a Windows `.exe` or installer unless explicitly requested.
- Keep the main application runnable directly from the MATLAB Command Window.

Example:

```matlab
DSPSerialMonitor
```

---

## MATLAB Code Style

- Preserve existing variable names when practical.
- Do not rename large groups of variables only for stylistic reasons.
- Prefer clear and readable code over clever abstractions.
- Avoid unnecessary class-based rewrites.
- Use local or nested helper functions when that matches the existing application structure.
- Extract logic only when doing so clearly improves maintainability, testability, or correctness.
- New helper functions should have a focused responsibility.
- Avoid duplicated logic when a small helper function can safely remove repetition.
- Add comments where state transitions, channel-to-plot mapping, buffering, or UI rebuild logic would otherwise be difficult to understand.

---

## Language and UI Text

- MATLAB code comments may use Chinese.
- User-facing GUI controls may use Chinese.
- Plot labels should avoid unnecessary Chinese text when it may cause font/rendering issues.
- Keep standard plot labels such as:

```text
Time (s)
Value
Amplitude
```

in English when appropriate.
- User-configured channel names and units must be preserved as entered.

---

## Serial Communication

The currently working serial communication path is considered stable.

Unless a task explicitly requests protocol changes:

- Do not modify the DSP/MCU firmware.
- Do not change the serial frame format.
- Do not change the number of values expected per frame.
- Do not change the delimiter.
- Do not change the line terminator.
- Do not change normal/invalid frame classification semantics.
- Do not introduce binary framing, CRC, checksums, sequence numbers, or device timestamps.

The current protocol is fixed-width in channel count and CSV-like in representation.

Conceptually:

```text
value1,value2,value3,value4
```

One line corresponds to one frame.

Malformed data must never crash the GUI or terminate acquisition.

---

## Serial Error Handling

Serial communication is hardware- and driver-dependent. Preserve robust error handling.

- Keep connection failures recoverable.
- Keep malformed frames recoverable.
- Do not allow one invalid frame to stop acquisition.
- Preserve useful diagnostic information when serial connection fails.
- Disable serial callbacks cleanly before releasing the serial object.
- Closing the GUI must not leave callbacks active.
- Avoid silently swallowing errors when the user would benefit from a meaningful message.

---

## Data Model

Keep acquisition data separate from display configuration.

Incoming serial channels should remain conceptually independent from plots.

Preferred relationship:

```text
Serial Channels
      ↓
Data Buffer
      ↓
Display Configuration
      ↓
Plots
```

Do not make Plot count determine how many channels are received.

Do not make channel visibility determine whether incoming data is stored.

A hidden channel should normally:

- continue to be received;
- continue to be stored;
- continue to be available for CSV export;
- only be hidden from the GUI.

---

## Plot and Display Architecture

Treat `Channel` and `Plot` as separate concepts.

Preferred model:

```text
axesHandles(plotIndex)
lineHandles(channelIndex)
```

A Plot may contain multiple Channel lines.

A Channel may be assigned to one Plot.

Unless explicitly requested, do not implement the same Channel simultaneously in multiple Plots.

Channel colors should follow the Channel, not the Plot.

For example, moving CH1 between Plot 1 and Plot 3 should not unexpectedly change its color.

---

## Plot Rebuild Rules

Do not rebuild axes or line objects during every serial callback.

Plot layout rebuilding should occur only when necessary, such as:

- application startup;
- Plot count changes;
- Channel-to-Plot mapping changes;
- display configuration is applied.

During normal acquisition, prefer updating existing graphics objects using:

```matlab
XData
YData
Visible
XLim
YLim
```

Do not repeatedly delete and recreate graphics objects while streaming.

---

## Plot Performance

Preserve the existing strategy of decoupling data acquisition from graphics refresh.

Do not remove or bypass mechanisms equivalent to:

```matlab
plotPeriod
counterPeriod
maxPlotSamples
maxStoredSamples
```

unless the task explicitly replaces them with a better verified design.

General requirements:

- Do not redraw at the serial frame rate unless necessary.
- Do not plot the entire long-term data history when only a limited visible time window is needed.
- Keep graphics workload bounded during long acquisition sessions.
- Avoid multiple `drawnow` calls per refresh cycle.
- Prefer a single:

```matlab
drawnow limitrate nocallbacks
```

after updating all visible graphics.

Do not perform speculative performance rewrites without profiling evidence.

---

## Buffering

Preserve bounded memory behavior.

If the application uses a circular/ring buffer:

- do not casually replace it with endlessly growing arrays;
- preserve chronological ordering when reading stored samples;
- ensure Clear correctly resets logical state;
- ensure reconnecting does not corrupt time/index state.

Long-running acquisition should remain stable.

---

## Y-Axis Behavior

Y-axis settings belong to the display layer.

When multiple Channels share one Plot, use a simple and predictable rule.

Unless a task explicitly requests a different design:

- do not introduce `yyaxis`;
- do not add automatic per-channel dual axes;
- keep one Y-axis per Plot;
- combine configured Channel limits conservatively when multiple Channels share a Plot;
- preserve current “expand when exceeded” behavior if present;
- do not continuously shrink the Y-axis every frame.

`Reset Y Axis` should remain deterministic and should not alter unrelated channel/display settings.

---

## Configuration and Preferences

User display settings should persist when practical.

Use MATLAB preferences consistently.

When adding new preference fields:

- maintain backward compatibility with older saved settings;
- supply safe defaults when a field is missing;
- validate stored data before using it;
- corrupted or outdated preferences must not prevent application startup.

If the application was renamed from an older project name, migration code may read legacy preferences, but new settings should be stored under the current generic application identity.

---

## CSV Export

CSV export represents acquired data, not current visual layout.

Therefore:

- hidden Channels must still be exportable;
- moving a Channel between Plots must not change acquisition order;
- Plot count must not change CSV column count;
- Channel display names may be used for CSV headers when safely converted to valid unique names;
- time data should remain the first column unless explicitly changed.

Do not couple CSV export to `Visible` or Plot assignment.

---

## Existing Features

When modifying the application, protect existing working features unless the task explicitly changes them.

Typical regression-sensitive features include:

- Refresh Serial Ports
- Connect
- Disconnect
- Pause Display
- Resume Display
- Clear
- Save CSV
- Window length
- Reset Y Axis
- Channel Settings
- Good frame count
- Bad frame count
- Sample count
- GUI close handling
- saved display preferences

After changes, explicitly consider whether each affected feature still behaves correctly.

---

## Pause Behavior

`Pause Display` should pause graphics updates, not data acquisition.

While paused:

- serial data should continue to be read;
- valid samples should continue to enter the buffer;
- counters may continue to update if the existing design does so;
- resuming should redraw using the latest buffered data.

Do not silently change Pause into “stop serial reception”.

---

## Clear Behavior

Clear should reset acquisition data and related counters without resetting unrelated user configuration.

Unless explicitly requested, Clear should not reset:

- Channel names;
- units;
- Channel visibility;
- Channel-to-Plot mapping;
- Plot count;
- saved display preferences.

---

## UI Changes

Keep the UI engineering-oriented and compact.

- Prioritize waveform readability.
- Do not add decorative elements without functional value.
- Keep related controls grouped together.
- Avoid excessive modal dialogs.
- Preserve the existing visual style unless redesign is part of the task.
- New controls should fit naturally into the current layout.
- Do not make the main window unnecessarily larger solely to accommodate one new control.

---

## Refactoring Policy

Refactor only when required by the current task or when a very small refactor prevents fragile duplicated code.

Do not:

- rewrite the whole application into classes without being asked;
- migrate to MVC/MVVM solely for architecture purity;
- split the project into many files prematurely;
- rewrite working serial code while implementing a display feature;
- change unrelated naming conventions.

If a larger refactor becomes necessary, explain why before proceeding when possible.

---

## File Creation

Do not create files unless they serve a clear purpose.

For normal feature work, prefer modifying the existing application source.

Potentially reasonable future files include:

```text
tests/
examples/
docs/
```

but only create them when requested or when the current task explicitly requires them.

Do not create temporary duplicate application versions such as:

```text
DSPSerialMonitor_new.m
DSPSerialMonitor_v2.m
DSPSerialMonitor_fixed.m
```

Modify the intended source file instead, unless the user explicitly asks for a copy.

---

## Testing and Validation

After changes:

1. Perform available static/syntax checks.
2. Run MATLAB tests when they exist and MATLAB execution is available.
3. Test non-hardware-dependent code where practical.
4. Clearly distinguish automated validation from hardware/manual validation.

Never claim hardware or GUI behavior was tested if it was not actually tested.

If MATLAB GUI interaction cannot be automated, provide a concise manual verification list.

Important regression cases usually include:

```text
Application startup
Serial port refresh
Connect / disconnect
Valid frame reception
Malformed frame handling
Pause / resume
Clear
CSV export
Plot layout changes
Channel visibility
Channel-to-Plot mapping
Preference persistence
Application close
```

---

## Hardware Safety

This MATLAB application may be used while controlling real power-electronics hardware.

Do not automatically change firmware, controller gains, PWM behavior, protection thresholds, or DSP control logic as part of a GUI-only task.

Any requested changes that could affect real power hardware should be treated separately and carefully.

---

## Git and GitHub

Do not perform Git or GitHub write operations unless the user explicitly asks.

Without explicit permission, do not:

```text
git init
git add
git commit
git push
git reset --hard
git clean
create a GitHub repository
modify remotes
create releases
```

Reading repository state or diffs may be acceptable when useful, but destructive or publishing operations require explicit user intent.

When the current task explicitly says not to use Git/GitHub, do not perform any Git/GitHub operation at all.

---

## Destructive Operations

Before:

- deleting source files;
- overwriting large amounts of working code;
- removing user configuration;
- performing irreversible operations;

ask for confirmation unless the current task explicitly and unambiguously requires that exact action.

Renaming a source file as part of an explicitly requested application rename is acceptable, but do not delete the only working implementation before the replacement is valid.

---

## Task Plans

Task-specific Plan files contain temporary implementation requirements.

When a Plan exists:

1. Read this `AGENTS.md`.
2. Read the complete task Plan.
3. Read all directly relevant source code.
4. Identify constraints and acceptance criteria.
5. Implement only the requested scope.
6. Validate the result.
7. Report what changed and what remains to be manually verified.

Do not edit the Plan unless explicitly requested.

---

## Completion Report

After completing a coding task, report concisely:

### Modified

Summarize the functional changes.

### Files

List files created, renamed, or modified.

### Validation

Separate:

```text
Actually tested
```

from:

```text
Not tested / requires manual MATLAB or hardware verification
```

### Notes

Mention only important compatibility issues, remaining risks, or required user checks.

Do not include unrelated suggestions unless they materially help the current task.
