# SysOpt v3.2.0 — Estructura del Proyecto

> Última actualización: 04/03/2026 · 80 archivos · 15 directorios

---

## 📁 Árbol completo

```
SysOpt-WindowsOptimizerGUI-3.2.0-DEV/
│
├── SysOpt.ps1                          # Script principal — 6,243 líneas (v3.2.0)
├── README.MD                           # Documentación bilingüe ES/EN para GitHub
├── SysOpt_Roadmap.html                 # Hoja de ruta visual HTML
├── sysopt-externalization-plan.md      # Plan de externalización a DLLs
├── SysOpt-ProjectStructure.md          # ← Este archivo
│
├── assets/                             # Recursos de la aplicación
│   ├── img/                            # Imágenes e iconos
│   │   ├── SysOpt.ico                  #   Icono de la aplicación (.ico)
│   │   └── sysopt.png                  #   Logo en PNG (splash, about)
│   │
│   ├── lang/                           # Archivos de idioma (.lang)
│   │   ├── en-us.lang                  #   English (US)
│   │   ├── es-es.lang                  #   Español (España)
│   │   └── pt-br.lang                  #   Português (Brasil)
│   │
│   ├── templates/                      # Plantillas HTML
│   │   └── diskreport.html             #   Plantilla de informe de disco
│   │
│   ├── themes/                         # Temas visuales — 33 archivos .theme
│   │   ├── apple.theme                 #   Apple · Minimalista blanco
│   │   ├── aws.theme                   #   Amazon Web Services · Naranja
│   │   ├── azure.theme                 #   Microsoft Azure · Azul cielo
│   │   ├── bloomberg.theme             #   Bloomberg Terminal · Fondo negro
│   │   ├── cyberpunk.theme             #   Cyberpunk 2077 · Neón amarillo
│   │   ├── default.theme               #   Default Dark (tema por defecto)
│   │   ├── default-light.theme         #   Default Light
│   │   ├── diablo.theme                #   Diablo · Rojo infernal
│   │   ├── dracula.theme               #   Dracula · Púrpura oscuro
│   │   ├── figma.theme                 #   Figma · Negro moderno
│   │   ├── github-dark.theme           #   GitHub Dark Mode
│   │   ├── iceblue.theme               #   Ice Blue · Azul helado
│   │   ├── icecream.theme              #   Ice Cream · Pastel cálido
│   │   ├── kiss.theme                  #   KISS · Negro y rojo rock
│   │   ├── manga-japan.theme           #   Manga Japan · Rojo y blanco
│   │   ├── matrix.theme                #   Matrix · Verde terminal
│   │   ├── monokai.theme               #   Monokai · IDE clásico
│   │   ├── notion.theme                #   Notion · Blanco limpio
│   │   ├── office.theme                #   Microsoft Office · Azul corporativo
│   │   ├── pipboy.theme                #   Pip-Boy · Verde Fallout
│   │   ├── ps5.theme                   #   PlayStation 5 · Blanco y azul
│   │   ├── simpsons.theme              #   Simpsons · Amarillo Springfield
│   │   ├── slack.theme                 #   Slack · Púrpura moderno
│   │   ├── solarized-dark.theme        #   Solarized Dark · Azul oscuro
│   │   ├── starwars.theme              #   Star Wars · Negro imperial
│   │   ├── symphony of the night.theme #   Castlevania · Púrpura gótico
│   │   ├── ubuntu.theme                #   Ubuntu · Naranja y gris
│   │   ├── votorantim.theme            #   Votorantim · Verde corporativo
│   │   ├── votorantim2.theme           #   Votorantim v2 · Variante
│   │   ├── wallstreet.theme            #   Wall Street · Verde financiero
│   │   ├── windows.theme               #   Windows Dark · Azul sistema
│   │   ├── windows-light.theme         #   Windows Light
│   │   └── xbox.theme                  #   Xbox · Verde brillante
│   │
│   └── xaml/                           # Ventanas XAML — 9 archivos
│       ├── MainWindow.xaml             #   Ventana principal (tabs, toolbar)
│       ├── SplashWindow.xaml           #   Splash de arranque con progreso
│       ├── OptionsWindow.xaml          #   Opciones: tema, idioma, toggle debug
│       ├── AboutWindow.xaml            #   Acerca de: versión, créditos
│       ├── FolderScannerWindow.xaml    #   Explorador de disco con árbol
│       ├── DedupWindow.xaml            #   Deduplicación de archivos SHA256
│       ├── DiagnosticWindow.xaml       #   Diagnóstico del sistema (9 métricas)
│       ├── StartupManagerWindow.xaml   #   Gestor de inicio de Windows
│       └── TasksWindow.xaml            #   Panel de tareas async (TaskPool)
│
├── libs/                               # Ensamblados compilados (.dll)
│   ├── SysOpt.Core.dll                 #   Core: LangEngine, XamlLoader, CTK, DAL, AgentBus
│   ├── SysOpt.ThemeEngine.dll          #   Motor de temas: parser de .theme
│   ├── SysOpt.DiskEngine.dll           #   Motor de disco: DiskItem, scanner
│   ├── SysOpt.MemoryHelper.dll         #   Operaciones de memoria: WMI queries
│   ├── SysOpt.WseTrim.dll              #   Working Set Trim: liberación RAM
│   ├── SysOpt.Optimizer.dll            #   ⚠ Compilar con compile-dlls.ps1
│   ├── SysOpt.StartupManager.dll       #   ⚠ Compilar con compile-dlls.ps1
│   ├── SysOpt.Diagnostics.dll          #   ⚠ Compilar con compile-dlls.ps1
│   │
│   ├── csproj/                         # Fuentes C# y proyectos de compilación
│   │   ├── compile-dlls.ps1            #   Script de compilación — compila las 8 DLLs
│   │   ├── SysOpt.Core.cs              #   LangEngine + CTK + DAL + AgentBus (~950 líneas)
│   │   ├── SysOpt.ThemeEngine.cs       #   ThemeEngine parser
│   │   ├── DiskEngine.cs               #   DiskItem_v211, DiskItemToggle_v230, PScanner211
│   │   ├── MemoryHelper.cs             #   MemoryHelper WMI operations
│   │   ├── WseTrim.cs                  #   WorkingSetTrimmer
│   │   ├── SysOpt.Optimizer.cs         #   OptimizerEngine — 15 tareas (~600 líneas)
│   │   ├── SysOpt.StartupManager.cs    #   StartupEngine — registro de inicio (~390 líneas)
│   │   ├── SysOpt.Diagnostics.cs       #   DiagnosticsEngine — 9 métricas (~280 líneas)
│   │   ├── SysOpt.DiskEngine.csproj    #   Proyecto: DiskEngine
│   │   ├── SysOpt.MemoryHelper.csproj  #   Proyecto: MemoryHelper
│   │   ├── SysOpt.WseTrim.csproj       #   Proyecto: WseTrim
│   │   ├── SysOpt.StartupManager.csproj#   Proyecto: StartupManager
│   │   └── SysOpt.Diagnostics.csproj   #   Proyecto: Diagnostics
│   │
│   └── x86/                            # DLLs para arquitectura x86
│       ├── SysOpt.Core.dll
│       ├── SysOpt.DiskEngine.dll
│       ├── SysOpt.MemoryHelper.dll
│       ├── SysOpt.ThemeEngine.dll
│       └── SysOpt.WseTrim.dll
│
├── docs/                               # Documentación técnica
│   └── step6-optimizer-dll-implementation.md
│
├── logs/                               # Logs de ejecución (vacío — se genera en runtime)
├── output/                             # Exportaciones (vacío — se genera en runtime)
├── resources/                          # Recursos adicionales (reservado)
└── snapshots/                          # Snapshots del sistema (reservado)
```

---

## 📊 Estadísticas

| Métrica | Valor |
|---------|-------|
| **Script principal** | `SysOpt.ps1` — 6,243 líneas |
| **DLLs compiladas** | 8 ensamblados C# en `libs/` |
| **Fuentes C#** | 8 archivos `.cs` en `libs/csproj/` |
| **Temas visuales** | 33 archivos `.theme` |
| **Ventanas XAML** | 9 archivos `.xaml` |
| **Idiomas** | 3 (ES, EN, PT-BR) |
| **Archivos totales** | 80 |
| **Directorios** | 15 |

---

## 🏗️ Arquitectura de DLLs (8)

| # | DLL | Namespace / Clase principal | Líneas C# | Estado |
|---|-----|-----------------------------|-----------|--------|
| 1 | `SysOpt.Core.dll` | `LangEngine`, `XamlLoader`, `ScanTokenManager`, `SystemDataCollector`, `AgentBus` | ~950 | ✅ Precompilada |
| 2 | `SysOpt.ThemeEngine.dll` | `ThemeEngine` | ~200 | ✅ Precompilada |
| 3 | `SysOpt.DiskEngine.dll` | `DiskItem_v211`, `PScanner211`, `ScanCtl211` | ~350 | ✅ Precompilada |
| 4 | `SysOpt.MemoryHelper.dll` | `MemoryHelper` | ~150 | ✅ Precompilada |
| 5 | `SysOpt.WseTrim.dll` | `WorkingSetTrimmer` | ~120 | ✅ Precompilada |
| 6 | `SysOpt.Optimizer.dll` | `OptimizerEngine` (15 tareas) | ~600 | ⚠ Compilar |
| 7 | `SysOpt.StartupManager.dll` | `StartupEngine` | ~390 | ⚠ Compilar |
| 8 | `SysOpt.Diagnostics.dll` | `DiagnosticsEngine` (9 métricas) | ~280 | ⚠ Compilar |

> ⚠ Las DLLs 6-8 requieren compilación: `cd libs\csproj && .\compile-dlls.ps1`

---

## 🔄 Orden de carga (Splash)

```
[1/8]  10%  SysOpt.DiskEngine.dll      → DiskItem_v211, PScanner211
[2/8]  17%  SysOpt.MemoryHelper.dll    → MemoryHelper
[3/8]  24%  SysOpt.Core.dll            → LangEngine, ScanTokenManager, DAL
[4/8]  31%  SysOpt.ThemeEngine.dll     → ThemeEngine
[5/8]  38%  SysOpt.WseTrim.dll         → WorkingSetTrimmer
[6/8]  45%  SysOpt.Optimizer.dll       → OptimizerEngine
[7/8]  52%  SysOpt.StartupManager.dll  → StartupEngine
[8/8]  59%  SysOpt.Diagnostics.dll     → DiagnosticsEngine
       70%  Permisos de administrador
       74%  Controles UI
       82%  Ventana principal
       90%  Carga inicial de datos
      100%  ¡Listo!
```

---

## 📂 Convenciones de nombres

| Tipo | Patrón | Ejemplo |
|------|--------|---------|
| DLLs | `SysOpt.{Módulo}.dll` | `SysOpt.Optimizer.dll` |
| Fuentes C# | `SysOpt.{Módulo}.cs` | `SysOpt.Optimizer.cs` |
| Temas | `{nombre}.theme` | `cyberpunk.theme` |
| Idiomas | `{locale}.lang` | `es-es.lang` |
| Ventanas | `{Nombre}Window.xaml` | `OptionsWindow.xaml` |

---

## ⚙️ Compilación

```powershell
# Compilar todas las DLLs (requiere .NET Framework 4.x)
cd libs\csproj
.\compile-dlls.ps1

# El script auto-descubre los .cs y gestiona las inter-dependencias
# Output: DLLs copiadas a ..\libs\ (x64) y ..\libs\x86\ (x86)
```

---

*Generado automáticamente — SysOpt v3.2.0 (Dev)*
