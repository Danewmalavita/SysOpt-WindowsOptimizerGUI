# 📋 SysOpt v3.2.0 — Informe de Sesión de Desarrollo

**Fecha:** 4 de marzo de 2026
**Versión:** 3.2.0-DEV
**Líneas PS1:** 6,924 → 6,243 (−681 líneas, −9.8%)
**DLLs modulares:** 5 → 8

---

## 🎯 Objetivo de la Sesión

Completar la **Fase 2D del plan de externalización**: mover lógica de optimización, gestión de inicio y diagnóstico desde PowerShell a DLLs compiladas en C#, además de corregir bugs críticos de runtime.

---

## ✅ Trabajo Realizado

### 1. Nuevas DLLs Compiladas (Fase 2D)

| DLL | Funcionalidad | Líneas C# | Impacto |
|-----|---------------|-----------|---------|
| `SysOpt.Optimizer.dll` | 15 tareas de optimización (limpieza, TRIM, defrag, etc.) | ~600 | Reemplaza 15 bloques if en PS1 por `$taskMap` hashtable |
| `SysOpt.StartupManager.dll` | Gestión de programas de inicio (HKCU/HKLM) | ~390 | Lectura/escritura de registry startup entries |
| `SysOpt.Diagnostics.dll` | 9 métricas de diagnóstico del sistema | ~280 | Motor de scoring con reflexión vía `$diagHash` |

**Total: 8 DLLs** — Core, ThemeEngine, DiskEngine, MemoryHelper, WseTrim, Optimizer, StartupManager, Diagnostics.

### 2. Integración en SysOpt.ps1

- **Carga secuencial en splash** con indicadores de progreso: 10% → 17% → 24% → 31% → 38% → 45% → 52% → 59%
- **Auditoría en debug logs** — las 8 DLLs aparecen tanto en la secuencia de carga como en la sección de auditoría
- **Auto-detección** — escanea `libs/` buscando cualquier `SysOpt.*.dll` no cargada y la reporta
- **GuardType** por cada DLL para verificar carga exitosa

### 3. Metadata Unificado

- Eliminada clave duplicada `v3.2.0` en `$script:AppNotes`
- 17 ítems consolidados: CTK, DAL, AGENT, DLL (×5), THEME, UI, DBG, OPT (×2)
- Eliminada clave obsoleta `v2.4.0` (FIFO)

---

## 🐛 Bugs Corregidos

### Bug 1: `StartupEntry.Location` no existe
- **Error:** `The property 'Location' cannot be found on this object`
- **Causa:** El PS1 usaba `$se.Location` y `$e.Location`, pero la clase C# `StartupEntry` define la propiedad como `RegPath`
- **Fix:** `$se.Location` → `$se.RegPath` (escritura), `$e.Location` → `$e.RegPath` (lectura)

### Bug 2: Parpadeo de barra de progreso — Splash
- **Error:** La barra de splash retrocedía de 70% a 40% después de cargar DLLs
- **Causa:** Las etapas post-DLL tenían valores menores (40→65→85→100) que las etapas de DLL (10→59→70)
- **Fix:** Renumerado a secuencia monotónica: 70→74→82→90→100. Añadida protección anti-retroceso en `Set-SplashProgress`

### Bug 3: Parpadeo de barra de progreso — Optimización
- **Error:** La barra de optimización se reseteaba a 0% al iniciar cada nueva tarea
- **Causa:** El helper `Status()` en C# creaba `OptimizeProgress` sin establecer `Percent`, dejándolo en `0` (default de `int`). El callback PS1 (`if ($p.Percent -ge 0)`) dejaba pasar el 0
- **Fix:** Constructor `OptimizeProgress() { Percent = -1; }` — ahora `Status()` no altera la barra. Solo `Msg()` y `Progress()` que establecen `Percent` explícitamente actualizan la barra

### Bug 4: `Write-Log` no reconocido en handlers WPF
- **Error:** `El término 'Write-Log' no se reconoce como nombre de un cmdlet` en `ERR-DISPATCHER`
- **Causa:** Los event handlers WPF (`Add_Click`, `Add_SelectionChanged`, etc.) se ejecutan vía `ScriptBlock.InvokeAsDelegateHelper`, que NO resuelve funciones de script scope — solo ve scope global
- **Fix:** Convertidas **73 funciones** de `function Name {` a `function global:Name {`. Única excepción: `script:Load-SysOptDll` (interna del boot, nunca llamada desde handler WPF)

### Bug 5: `Load-Language` no reconocido al cambiar idioma/tema
- **Error:** `El término 'Load-Language' no se reconoce` al interactuar con la ventana de Opciones
- **Causa:** Mismo problema de scope que Bug 4
- **Fix:** Incluida en la conversión masiva a `global:` (Bug 4)

---

## 📊 Métricas de la Sesión

| Métrica | Valor |
|---------|-------|
| Líneas PS1 eliminadas | −681 (6,924 → 6,243) |
| Reducción porcentual | −9.8% |
| DLLs nuevas creadas | 3 (Optimizer, StartupManager, Diagnostics) |
| DLLs totales | 8 |
| Bugs corregidos | 5 |
| Funciones convertidas a global | 73 |
| Temas soportados | 33 |
| Idiomas soportados | 3 (ES, EN, PT-BR) |

---

## 📁 Archivos Modificados

| Archivo | Cambio |
|---------|--------|
| `SysOpt.ps1` | Metadata unificado, `global:` en 73 funciones, progreso monotónico, `Location`→`RegPath` |
| `libs/csproj/SysOpt.Optimizer.cs` | `OptimizeProgress.Percent` default = −1 (constructor) |
| `libs/csproj/SysOpt.StartupManager.cs` | Nueva DLL — gestión de startup entries |
| `libs/csproj/SysOpt.Diagnostics.cs` | Nueva DLL — motor de diagnóstico con 9 métricas |
| `libs/csproj/compile-dlls.ps1` | Referencias inter-DLL actualizadas para las 8 DLLs |

---

## 🔮 Próximos Pasos (Roadmap)

- **Fase 2E:** Continuar externalización — objetivo: reducir PS1 a ~2,500 líneas
- **Precompilar DLLs** para incluirlas directamente en el ZIP de distribución
- **Candidatos para externalización:** lógica de UI dinámica, handlers de disco, gestión de snapshots

---

*Informe generado automáticamente — SysOpt Development Session*
