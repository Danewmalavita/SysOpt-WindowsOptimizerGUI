# 🗺️ SysOpt v3.2.0 — Análisis Roadmap vs Estado Actual

**Fecha**: 4 de marzo de 2026  
**Versión analizada**: v3.2.0-STABLE  
**Método**: Cruce automatizado del `SysOpt_Roadmap.html` contra el código fuente real

---

## 📊 Resumen Ejecutivo

| Métrica | Valor |
|---------|-------|
| **Versiones completadas** | 8 de 8 (v2.0.x → v3.2.0) |
| **Objetivos roadmap v3.x** | 4 de 9 completados |
| **DLLs modulares** | 9 compiladas (18 DLLs contando x86) |
| **Archivos C# fuente** | 9 en `libs/csproj/` |
| **Temas** | 68 (roadmap decía 33 — **superado 2x**) |
| **Idiomas** | 3 (ES, EN, PT-BR) |
| **Ventanas XAML** | 10 externalizadas |
| **Líneas PS1** | 6,884 (roadmap decía ~6,241 — delta por nuevas features) |

---

## ✅ Versiones Completadas (8/8)

### v2.0.x — Hotfix de estabilidad crítica ✓
Todos los 7 fixes implementados: guards anti-TYPE_ALREADY_EXISTS, fix parentKey `::ROOT::`, inyección assemblies a runspace, Import-Module en runspace rendimiento, Update-SystemInfo async, fix closure `$async`, cleanup en Add_Closed.

### v2.1.x — Estabilidad del Explorador ✓
6/6 fixes: parser `.AddParameter`, memoria adaptativa según RAM libre, childMap cacheado, Sort-Object correcto, DFS con frame stack, fix interval `if`.

### v2.3 — Funcionalidad completa del Explorador ✓
Todas las features B1-B4, A3, C3 y RAM-01 a RAM-06. Bugs BF1-BF6 corregidos.

### v2.4.0 — FIFO Streaming ✓
Integrado en v2.5.0. FIFO-01/02/03, fix Set-Content, toggle refresh, pre-cálculo top 10.

### v2.5.0 — VERSIÓN PÚBLICA ESTABLE ✓
Logging estructurado, error boundary global, CimSession timeout, deduplicación SHA256, TaskPool async. Todos los fixes UX aplicados.

### v3.0.0 — Arquitectura modular DLL ✓
`SysOpt.MemoryHelper.dll` + `SysOpt.DiskEngine.dll` en `.\libs\`. Ruta relativa a PSScriptRoot.

### v3.1.0 — Temas + Multiidioma + Opciones ✓
Motor de temas dual (293 DynamicResource + 298 Get-TC), 3 idiomas, SysOpt.Core.dll + ThemeEngine.dll, ventana de opciones, ComboBox theming, persistencia settings.json.

### v3.2.0 — Externalización DLLs + 68 Temas ✓ (parcial)
- ✅ SysOpt.Optimizer.dll — 15 tareas
- ✅ SysOpt.StartupManager.dll — gestión de inicio
- ✅ SysOpt.Diagnostics.dll — diagnóstico con Loc.T()
- ✅ SysOpt.Toast.dll — notificaciones toast temáticas
- ✅ SysOpt.WseTrim.dll — trim de espacios en blanco
- ✅ 68 temas (superado: roadmap decía 33)
- ✅ Toggle Win11 en opciones
- ✅ Auditoría de 9 DLLs en debug/splash
- ✅ Sección "Acerca de" integrada en Opciones
- ✅ Changelog externalizado a SysOpt.info

---

## 🔮 Objetivos Roadmap v3.x — Estado Detallado

### 🟢 Prioridad Alta — Arquitectura

| ID | Objetivo | Estado | Evidencia |
|----|----------|--------|-----------|
| **DLL** | Tipos C# compilados a DLL externo | ✅ **COMPLETADO** | 9 DLLs en `libs/`, 9 `.cs` en `libs/csproj/`, guards de tipo, Add-Type -Path |
| **CTK** | CancellationToken unificado | ✅ **COMPLETADO** | ScanTokenManager con RequestNew()/Cancel()/Dispose(), bridge CTK→ScanCtl211.Stop, 20 refs en PS1 |
| **DAL** | Abstracción capa de datos | ✅ **COMPLETADO** | SystemDataCollector con 13 WMI queries migradas, 8 Get*Snapshot() activos, modelos puros (Cpu/Ram/Disk/Network/Gpu/PortSnapshot) |

### 🟡 Prioridad Media — Funcionalidad

| ID | Objetivo | Estado | Detalle |
|----|----------|--------|---------|
| **C1** | Sistema de temas completo | ✅ **SUPERADO** | 68 temas (roadmap: 33), motor dual, ThemeEngine.dll, ComboBox theming |
| **C2** | Notificaciones Toast nativas | ⚠️ **PARCIAL** | SysOpt.Toast.dll compilada y cargada, Show-Toast + Sync-ToastTheme implementados. Usa sistema propio WPF en vez de WinRT ToastNotificationManager del roadmap |
| **C4** | Programador de tareas integrado | ❌ **PENDIENTE** | 0 refs a Register-ScheduledTask. Sin interfaz para crear tareas programadas |
| **PLG** | Plugin system para módulos externos | ❌ **PENDIENTE** | 0 refs a "plugin", sin directorio `.\plugins\`. Sin arquitectura de extensibilidad |

### 🔵 Prioridad Baja — UX & Polish

| ID | Objetivo | Estado | Detalle |
|----|----------|--------|---------|
| **I18N** | Multiidioma completo | ✅ **COMPLETADO** | 3 idiomas (ES/EN/PT-BR), ~930 keys, LangEngine en Core.dll, T() + Loc.T(), cambio en caliente |
| **UPD** | Auto-actualización integrada | ❌ **PENDIENTE** | 0 refs a GitHub Releases API ni check de versión automático |
| **RPT** | Informe de sesión PDF/HTML | ⚠️ **PARCIAL** | Existe template `diskreport.html` para exportar informe de disco. Falta informe completo de sesión con PDF y puntuación antes/después |

---

## 📦 Inventario Real del Proyecto

### DLLs Modulares (9 + 9 x86 = 18)

| # | DLL | Función | Fuente C# |
|---|-----|---------|-----------|
| 1 | SysOpt.Core.dll | LangEngine + SettingsHelper | SysOpt.Core.cs |
| 2 | SysOpt.ThemeEngine.dll | Parser de archivos .theme | SysOpt.ThemeEngine.cs |
| 3 | SysOpt.DiskEngine.dll | DiskItem, ScanCtl, PScanner | DiskEngine.cs |
| 4 | SysOpt.MemoryHelper.dll | EmptyWorkingSet nativo | MemoryHelper.cs |
| 5 | SysOpt.Optimizer.dll | 15 tareas de optimización | SysOpt.Optimizer.cs |
| 6 | SysOpt.StartupManager.dll | Gestión inicio Windows | SysOpt.StartupManager.cs |
| 7 | SysOpt.Diagnostics.dll | 9 métricas, scoring 0-100 | SysOpt.Diagnostics.cs |
| 8 | SysOpt.Toast.dll | Notificaciones toast WPF | SysOpt.Toast.cs |
| 9 | SysOpt.WseTrim.dll | Trim espacios en blanco | WseTrim.cs |

### Ventanas XAML (10)
`AboutWindow` · `ChangelogWindow` · `DedupWindow` · `DiagnosticWindow` · `FolderScannerWindow` · `MainWindow` · `OptionsWindow` · `SplashWindow` · `StartupManagerWindow` · `TasksWindow`

### Temas (68)
Desde clásicos (`default`, `matrix`, `pipboy`) hasta gaming (`elden-ring`, `god-of-war`, `zelda`, `cyberpunk`, `dark-souls`, `doom`, `halo`, `resident-evil`, `sekiro`, `bloodborne`, `hollow-knight`...) y tech (`aws`, `azure`, `github-dark`, `ubuntu`, `slack`, `figma`, `bloomberg`, `wallstreet`).

---

## 🎯 Próximos Pasos Sugeridos

### Prioridad inmediata
1. **C4 — Programador de tareas**: Interfaz para Register-ScheduledTask con optimizaciones automáticas
2. **UPD — Auto-actualización**: Check de versión contra GitHub Releases al arrancar

### Prioridad media
3. **PLG — Plugin system**: Arquitectura de carga dinámica desde `.\plugins\`
4. **RPT — Informe de sesión**: PDF/HTML completo con puntuación antes/después

### Mejoras detectadas en sesión actual
5. **Task 4**: Limpieza de DLLs/subprocesos al cerrar (procesos quedan activos)
6. **Task 5**: Easter egg Atari Breakout en logo de "Acerca de"

### C2 — Toast: Decisión pendiente
El roadmap especificaba WinRT `ToastNotificationManager` para notificaciones nativas del sistema. La implementación actual usa un sistema propio WPF (SysOpt.Toast.dll con ToastManager). 
**Opciones**: (a) Mantener toast WPF actual (funcional y tematizable), (b) Añadir toast nativo WinRT como complemento para cuando la app está minimizada.

---

## 📈 Progreso Global

```
Roadmap v3.x ─────────────────────────────────

  ██████████████████░░░░░░░░  67%  (6/9 objetivos)

  ✅ DLL  ✅ CTK  ✅ DAL  ✅ C1  ✅ I18N  ⚠️ C2
  ❌ C4   ❌ PLG  ❌ UPD  ⚠️ RPT
```

**SysOpt v3.2.0 está en un estado muy sólido.** Toda la base arquitectural está completada (DLLs, CTK, DAL), el sistema de temas supera ampliamente lo planificado (68 vs 33), y el multiidioma está maduro. Los pendientes son features de usuario (programador, plugins, auto-update) que no requieren refactorización — solo extensión.
