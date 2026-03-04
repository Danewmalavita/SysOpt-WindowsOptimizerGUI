# SysOpt v3.2.0 — Análisis del Roadmap vs Implementación

> Actualizado: 2026-03-04 · Basado en `SysOpt_Roadmap.html` y código fuente real  
> Post CTK + DAL completados · **6,153 líneas · 71 funciones · 8 DLLs**

---

## 1. Estado de Implementación por Módulo

### ✅ Completados (20 ítems)

| ID | Módulo | Detalle |
|----|--------|---------|
| DLL-1 | SysOpt.Core.dll | LangEngine + CoreUtils + SettingsHelper + **SystemDataCollector (DAL)** — 63 KB |
| DLL-2 | SysOpt.ThemeEngine.dll | ParseTheme, ApplyTheme, ListThemes — 11 KB |
| DLL-3 | SysOpt.DiskEngine.dll | DiskItem_v211, DiskItemToggle_v230, PScanner211 + **ScanCtl211 CTK bridge** — 17 KB |
| DLL-4 | SysOpt.MemoryHelper.dll | EmptyWorkingSet (P/Invoke) — 3.5 KB |
| DLL-5 | SysOpt.WseTrim.dll | WorkingSetTrimmer batch — 4 KB |
| DLL-6 | SysOpt.Optimizer.dll | 15 tareas via OptimizerEngine.Run() — 32 KB |
| DLL-7 | SysOpt.StartupManager.dll | GetEntries/SetEnabled vía registro — 10 KB |
| DLL-8 | SysOpt.Diagnostics.dll | 9 métricas via DiagnosticsEngine.RunAll() — 14 KB |
| **CTK** | **ScanTokenManager COMPLETO** | **Bridge CTK→ScanCtl211.Stop · 0 escrituras directas · Cancel()/Dispose() limpio** |
| **DAL** | **SystemDataCollector COMPLETO** | **13 WMI queries migradas · CimSession eliminada · 8 Get*Snapshot() activos** |
| THM | 33 temas | Paleta completa con BtnPrimaryBg/TextMuted para toggle |
| I18N | 3 idiomas | es-es, en-us, pt-br via LangEngine.T() |
| UI-1 | Toggle Win11 | 50×26px, anti-aliased, colores adaptativos |
| UI-2 | Opciones Window | DockPanel, selectores tema/idioma, vista previa |
| DBG | Auditoría DLLs | 8/8 DLLs en debug log + splash (10%→59%) |
| OPT | Compactación | $taskMap (15 if→1 hash), $diagHash (reflexión) |
| FIX-1 | Scope global | 71 funciones → `global:` para handlers WPF |
| FIX-2 | Splash monotónico | Progreso 10→...→100 sin retrocesos |
| FIX-3 | Barra optimización | Percent=-1 default, sin reset a 0% |
| FIX-4 | StartupManager | GetAll() → GetEntries() — nombre correcto |

---

### 🟡 Parcialmente Implementados (1 ítem)

| ID | Módulo | En C# (DLL) | En PS1 (uso) | Estado |
|----|--------|-------------|--------------|--------|
| AGENT | AgentBus | ✅ `AgentBus` + `IAgentTransport` + `AgentThresholds` | ⚠️ **0 refs en PS1** — hooks existen pero sin consumo | **Standalone safe, 0% integrado** |

---

### ⬜ Pendientes (no implementados)

| ID | Módulo | Descripción | Complejidad |
|----|--------|-------------|-------------|
| TOAST | Notificaciones | Toast nativo Windows 10/11 al completar optimización | Media |
| SCHED | Scheduler | Tareas programadas (optimización nocturna) | Alta |
| PLUGIN | Sistema plugins | Extensiones cargadas dinámicamente desde `plugins/` | Alta |
| UPD | Auto-update | Verificación de versión + descarga desde GitHub | Media |
| RPT-PDF | Informe PDF | Exportar diagnóstico como PDF nativo | Media |

---

## 2. Trabajo Completado en Esta Sesión

### 2a. CTK — Migración Completa ✅

**Problema:** ScanCtl211 y ScanTokenManager coexistían con patrones duales (`Stop=$true` + `Cancel()`).  
**Solución:** Bridge en C# — `ScanCtl211.Stop` getter ahora lee `_stop || _token.IsCancellationRequested`.

| Cambio | Detalle |
|--------|---------|
| C# bridge | `ScanCtl211.SetToken(CancellationToken)` + `Stop` getter lee token |
| PS1 init | `RequestNew()` + `SetToken()` en línea de carga |
| 5× `Stop=$true` | **Eliminadas** — reemplazadas por `Cancel()` |
| 4× patrones duales | **Simplificados** — un solo mecanismo |
| Add_Closed | `Dispose()` solo — bridge propaga automáticamente |
| **Resultado** | **0 escrituras directas a ScanCtl211.Stop · -15 líneas** |

### 2b. DAL — Migración Completa ✅

**Problema:** 13 queries WMI/CIM directas en PS1 vía `Invoke-CimQuery` + infraestructura `CimSession` pesada.  
**Solución:** Todo migrado a `[SystemDataCollector]::Get*Snapshot()` en SysOpt.Core.dll.

| Cambio | Detalle |
|--------|---------|
| Core.cs | Añadidos `OsBuild` y `BootTime` a `SystemSnapshot` |
| Init logging | 5 queries → 1 `GetFullSnapshot()` |
| CPU+RAM tab | 4 queries → `GetCpuSnapshot()` + `GetRamSnapshot()` |
| Network tab | 3 queries → `GetNetworkSnapshot()` |
| Memory cleanup | 1 query → `GetRamSnapshot().FreeBytes` |
| **Eliminados** | `Get-SharedCimSession`, `Invoke-CimQuery`, `$script:CimSession` |
| **Resultado** | **0 Get-CimInstance directos · 0 Win32_* en código activo · -75 líneas** |

### Métricas acumuladas

| Métrica | v3.1.0 | v3.2.0 pre-CTK | v3.2.0 post-DAL | Δ total |
|---------|--------|-----------------|------------------|---------|
| Líneas PS1 | 6,924 | 6,243 | **6,153** | **-771 (-11.1%)** |
| Funciones global | 73 | 73 | **71** | -2 (CIM eliminadas) |
| WMI queries en PS1 | ~18 | ~18 | **0** | **-18** |
| CancellationToken | parcial | parcial | **completo** | ✅ |
| DAL coverage | 0% | 10% | **100%** | ✅ |

---

## 3. Próximos Pasos — v3.2.x → v3.3.0

### ~~Fase 1: CTK Completo (v3.2.1)~~ ✅ COMPLETADO

### ~~Fase 2: DAL Completo (v3.2.2)~~ ✅ COMPLETADO

### Fase 3: Toast Notifications (v3.2.3) — Esfuerzo: Medio 🔔

| # | Acción | Detalle |
|---|--------|---------|
| 1 | Crear `SysOpt.Toast.dll` con wrapper de `Windows.UI.Notifications` | C#, ~150 líneas |
| 2 | Método `ShowToast(title, body, icon)` — compatible Win10/11 | AppUserModelID |
| 3 | Llamar desde PS1 al completar optimización, diagnóstico, escaneo | 3 puntos de integración |
| 4 | Respetar setting "Notificaciones = on/off" en Options | +1 checkbox en XAML |

### Fase 4: Reducción Agresiva PS1 (v3.3.0) — Esfuerzo: Alto 🏗️

**Funciones más grandes — candidatas a externalización:**

| Función | Líneas | Acción propuesta | Reducción estimada |
|---------|--------|------------------|-------------------|
| `Start-DiskScan` | 440 | Migrar lógica de traversal a SysOpt.DiskEngine.dll | -200 |
| `Show-FolderScanner` | 341 | Migrar builders de UI a XAML + code-behind mínimo | -150 |
| `Update-PerformanceTab` | 267 | Compactar bindings (DAL ya migrado) | -80 |
| `Start-Optimization` | 215 | Ya usa Optimizer.dll — compactar callbacks | -50 |
| `Load-SnapshotList` | 207 | Migrar parseo a SysOpt.Core.dll | -120 |
| `Apply-ThemeWithProgress` | 207 | Migrar apply-loop a ThemeEngine.dll | -80 |
| `Get-SnapshotEntriesAsync` | 163 | Migrar a SysOpt.Core.dll | -100 |
| `Show-ExportProgressDialog` | 158 | Compactar + migrar export a DLL | -80 |
| **Total estimado** | | | **~-860 líneas** |

**Objetivo v3.3.0:** PS1 de 6,153 → ~5,300 líneas (reducción acumulada: -1,624 desde v3.1.0 = **-23.5%**)

---

## 4. Resumen Ejecutivo

```
v3.1.0  ████████████████████████████████████  6,924 líneas (baseline)
v3.2.0  █████████████████████████████████     6,243 líneas (-681, -9.8%)  ← DLLs + UI + fixes
v3.2.0  ████████████████████████████████      6,153 líneas (-90, CTK+DAL) ← HOY
v3.3.0  ███████████████████████████           5,300 líneas (-853, reducción agresiva) ← objetivo
Meta    ██████████████████                   ~4,000 líneas (-2,924, -42%) ← meta final
```

### Prioridad recomendada

```
 ✅ HECHO   → CTK Completo — bridge CTK→ScanCtl211, 0 escrituras directas
 ✅ HECHO   → DAL Completo — 13 WMI queries migradas, CimSession eliminada
 PRÓXIMO   → Toast (feature visible para el usuario, nueva DLL)
 DESPUÉS   → Agent hooks (necesita Transport impl real)
 v3.3.0    → Reducción agresiva (-860 líneas: DiskScan + FolderScanner + SnapshotList)
```

---

## 5. Dependencias entre Fases

```
CTK ✅ ──────┐
             ├──→ v3.2.x estable ──→ Reducción agresiva (v3.3.0)
DAL ✅ ──────┘                              │
                                            ├──→ Plugin system (v3.4.0)
Toast ──→ standalone (próximo)              │
                                            └──→ Auto-update (v3.5.0)
Agent hooks ──→ necesita Transport impl + DAL ✅
```

---

*Documento actualizado el 2026-03-04 — SysOpt v3.2.0-DEV · 8 DLLs · 6,153 líneas · CTK ✅ · DAL ✅*
