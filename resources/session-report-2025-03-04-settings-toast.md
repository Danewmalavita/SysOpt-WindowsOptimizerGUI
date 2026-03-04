# SysOpt — Session Report: Win11 Settings + Toast Notifications

**Date:** 2025-03-04  
**Version:** 3.2.0-STABLE  
**Focus:** Options Window Redesign + Toast Notification System

---

## 🎯 Objectives

1. Redesign the Options window to Win11 Settings style (sidebar navigation + pages)
2. Create dedicated Toast notification DLL (`SysOpt.Toast.dll`)
3. Integrate toast notifications at key completion points
4. Dynamic theming for the Options window
5. Fix prior bugs (Try/Catch, DEBUG→DBG, double emojis, ContextMenu transparency)

---

## ✅ Bug Fixes (Prior Session Issues)

| # | Issue | Root Cause | Fix |
|---|---|---|---|
| 1 | `Try` without `Catch` at line 906 | DWM `Add_SourceInitialized` block inserted inside `Initialize-Logger`'s try/catch | Moved DWM hook to correct location (line 1264, before `$window.Add_Loaded`) |
| 2 | `Write-Log "DEBUG"` validation error | `"DEBUG"` not in ValidateSet `"DBG;INFO;WARN;ERR;CRIT;UI"` | Changed `"DEBUG"` → `"DBG"` in 2 snapshot debug lines |
| 3 | Double 🔍 in Disk Explorer context menu | Code prepended emoji AND .lang value already included it | Removed emoji from `CtxScanFolder` in 3 .lang files |
| 4 | Double ⏳ in snapshot loading | Code prepended emoji AND .lang value already included it | Removed emoji from 6 snapshot .lang keys × 3 languages |
| 5 | ContextMenu transparent in Tasks/popups | `Application.Current` was **null** — no `Application` object existed | Added `[System.Windows.Application]::new()` with `OnExplicitShutdown` |
| 6 | ContextMenu fallback | Defense in depth for popup brushes | Handler applies Background/BorderBrush/Foreground programmatically |

---

## 🆕 New Feature: Options Window — Win11 Settings Style

### Architecture

The Options window was completely redesigned from a flat layout to a **Windows 11 Settings** dual-panel interface:

```
┌──────────────────────────────────────────────────────────┐
│ ⚙  Configuración                                         │
├──────────────┬───────────────────────────────────────────┤
│              │                                            │
│ 🎨 Interfaz  │  TEMA VISUAL                              │
│              │  ┌─────────────────────────────────┐      │
│ ⚡ Comporta- │  │ Tema visual      [ComboBox ▼]   │      │
│    miento    │  └─────────────────────────────────┘      │
│              │                                            │
│              │  IDIOMA                                    │
│              │  ┌─────────────────────────────────┐      │
│              │  │ Idioma           [ComboBox ▼]   │      │
│              │  └─────────────────────────────────┘      │
│              │                                            │
│              │  ℹ Algunos cambios requieren reiniciar     │
│              │                                            │
│ SysOpt v3.2 │                   [Aplicar]  [Cerrar]      │
└──────────────┴───────────────────────────────────────────┘
```

**Behavior Page:**
```
│ ⚡ Comporta- │  NOTIFICACIONES                            │
│    miento    │  ┌─────────────────────────┬──────┐       │
│              │  │ Notificaciones toast    │ [ON] │       │
│              │  │ Mostrar alertas...      │      │       │
│              │  └─────────────────────────┴──────┘       │
│              │  ┌─────────────────────────┬──────┐       │
│              │  │ Probar notificación     │ Test │       │
│              │  └─────────────────────────┴──────┘       │
│              │  DEPURACIÓN                                │
│              │  ┌─────────────────────────┬──────┐       │
│              │  │ Logs de depuración      │ [OFF]│       │
│              │  └─────────────────────────┴──────┘       │
```

### Key Implementation Details

- **Window size:** 680×480 (was 460×400)
- **Left sidebar:** `BgCard` background, `ComboSelected` highlight for active nav
- **Cards:** Rounded corners (8px), `BgCard` background, 16px padding
- **Toggle switches:** Win11-style pill toggles (shared `Win11Toggle` Style)
- **Dynamic theming:** After theme change, `$applyOptTheme` scriptblock updates all named controls programmatically
- **Navigation:** `MouseLeftButtonDown` handlers toggle page `Visibility` and nav styling

### Files Modified

| File | Change |
|---|---|
| `assets/xaml/OptionsWindow.xaml` | Complete rewrite — Win11 two-panel layout |
| `SysOpt.ps1` → `Show-OptionsWindow` | Complete rewrite — nav switching, dynamic theming, toast controls |
| `SysOpt.ps1` → `Save-Settings` | Added `ToastEnabled` to settings JSON |
| `SysOpt.ps1` → `Load-Settings` | Added `ToastEnabled` restore on startup |

---

## 🆕 New Feature: Toast Notification System

### Architecture

Toast notifications use a **dedicated DLL** (`SysOpt.Toast.dll`) that creates themed WPF popup windows with slide-in/fade-out animations.

```
[PowerShell: Show-Toast]  →  [SysOpt.Toast.ToastManager]  →  [WPF Window]
                                      ↑                            │
                              SetTheme(dict)               ┌──────┤
                              from Sync-ToastTheme         │ Icon │ Title
                                                           │      │ Message    [✕]
                                                           └──────┴───────────────┘
```

### Toast DLL (`SysOpt.Toast.cs`)

| Class | Description |
|---|---|
| `ToastType` | Enum: `Success`, `Info`, `Warning`, `Error` |
| `ToastManager` | Static class — `Show()`, `SetTheme()`, `Enabled`, `Debug` |

**Features:**
- Borderless WPF window with rounded corners (12px) and drop shadow
- Accent-colored left border based on toast type
- Slide-up animation (280ms, QuarticEase) + fade-in (250ms)
- Fade-out on dismiss (250ms)
- Auto-close after configurable duration (default 4000ms)
- Click-to-dismiss close button
- Toast stacking (multiple toasts reposition automatically)
- `ShowActivated = false` — doesn't steal focus
- Theme-aware via `SetTheme()` dictionary sync
- Debug flag for `System.Diagnostics.Debug` output

**Compile references:**
- `PresentationFramework.dll`
- `PresentationCore.dll`
- `WindowsBase.dll`

### PowerShell Integration

| Function | Purpose |
|---|---|
| `Sync-ToastTheme` | Sends `$script:CurrentThemeColors` dictionary to `ToastManager.SetTheme()` |
| `Show-Toast` | Wrapper — calls `ToastManager.Show()` with Write-Log debug |

**Toast trigger points:**

| Event | Toast Type | Lang Keys |
|---|---|---|
| Optimization completed | ✅ Success | `ToastOptDoneTitle` / `ToastOptDoneMsg` |
| Analysis (dry-run) completed | ℹ Info | `ToastAnalysisDoneTitle` / `ToastAnalysisDoneMsg` |
| Diagnostic report generated | ℹ Info | `ToastAnalysisDoneTitle` / `ToastAnalysisDoneMsg` |
| Snapshot saved | ✅ Success | `ToastSnapSavedTitle` / `ToastSnapSavedMsg` |
| CSV/HTML export completed | ✅ Success | `ToastExportDoneTitle` / `ToastExportDoneMsg` |
| Test button pressed | ℹ Info | `ToastTestTitle` / `ToastTestMsg` |

### Settings Persistence

- `ToastEnabled` added to `settings.json` via `Save-Settings` / `Load-Settings`
- Toast debug flag syncs with `[LogEngine]::DebugEnabled`
- Theme syncs at startup (`Add_Loaded`) and on every theme change (`Apply-ThemeWithProgress`)

---

## 📝 compile-dlls.ps1 Fixes

| Fix | Description |
|---|---|
| `_AssemblyInfo` exclusion | Added `_AssemblyInfo` to the `.cs` auto-discovery filter to prevent it being compiled as its own DLL |
| Toast DLL added | `SysOpt.Toast.cs` → `SysOpt.Toast.dll` with WPF references |

---

## 🌐 Internationalization Update

### New Lang Keys: +24 per language

**Categories:**
- Options Window navigation: 4 keys (`OptSettingsTitle`, `OptNavInterface`, `OptNavBehavior`, section headers)
- Settings controls: 8 keys (toggle labels, descriptions, hints, test button)
- Toast messages: 10 keys (titles + messages for each trigger point)
- Splash: 1 key (`SplashLoadingToast`)

### Key Counts

| Language | Before | After | Delta |
|---|---|---|---|
| es-es.lang | 706 | 730 | +24 |
| en-us.lang | 706 | 730 | +24 |
| pt-br.lang | 706 | 730 | +24 |

---

## 📊 Project Status Summary

| Metric | Value |
|---|---|
| **Version** | 3.2.0-STABLE |
| **SysOpt.ps1** | ~6,700 lines |
| **DLLs** | 9 (added Toast) |
| **Translation keys** | 730 × 3 languages |
| **XAML files** | 9 |
| **Themes** | 33 |

### DLL Inventory (9 total)

| # | DLL | Purpose |
|---|---|---|
| 1 | SysOpt.MemoryHelper | P/Invoke memory operations |
| 2 | SysOpt.DiskEngine | Disk scanning + volume info |
| 3 | SysOpt.Core | CTK + DAL + i18n (Loc, LangEngine, SettingsHelper) |
| 4 | SysOpt.ThemeEngine | Theme parsing + application |
| 5 | SysOpt.WseTrim | Working set trim |
| 6 | SysOpt.Optimizer | 15 optimization tasks |
| 7 | SysOpt.StartupManager | Windows startup management |
| 8 | SysOpt.Diagnostics | System diagnostics engine |
| 9 | **SysOpt.Toast** | **Toast notification engine (NEW)** |

---

## ⚠️ Action Required

The new `SysOpt.Toast.dll` requires compilation on Windows:

```powershell
cd .\libs\csproj\
powershell -ExecutionPolicy Bypass -File compile-dlls.ps1
```

This will compile all 9 DLLs including the new Toast DLL. The `_AssemblyInfo_tmp` exclusion fix prevents the duplicate DLL issue.

---

## 🔜 Next Steps (from Roadmap)

1. **PS1 Reduction (v3.3.0)** — Compact large functions (-860 lines → ~5,300)
2. **Auto-update** — Version check + download from GitHub
3. **PDF Reports** — Export diagnostics as native PDF
4. **Scheduler** — Programmed tasks (overnight optimization)
5. **Plugin System** — Dynamic extensions from `plugins/`
