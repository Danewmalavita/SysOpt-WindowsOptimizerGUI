// SysOpt.Diagnostics.cs — Motor de diagnóstico del sistema
// Compatible con C# 5 / .NET Framework 4.x
using System;
using System.Collections.Generic;

namespace SysOpt.Diagnostics
{
    /// <summary>Minimal localization helper — PS1 calls SetDict() after loading language.</summary>
    public static class Loc
    {
        private static System.Collections.Generic.Dictionary<string, string> _d =
            new System.Collections.Generic.Dictionary<string, string>(System.StringComparer.OrdinalIgnoreCase);

        public static void SetDict(System.Collections.Generic.Dictionary<string, string> d)
        {
            _d = d ?? new System.Collections.Generic.Dictionary<string, string>(System.StringComparer.OrdinalIgnoreCase);
        }

        public static string T(string key, string fallback)
        {
            return (_d != null && _d.ContainsKey(key)) ? _d[key] : fallback;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DTOs
    // ═══════════════════════════════════════════════════════════════════════

    /// <summary>Datos de entrada recogidos por el Optimizer (dry-run).</summary>
    public class DiagInput
    {
        public double TempFilesMB    { get; set; }
        public double UserTempMB     { get; set; }
        public double RecycleBinMB   { get; set; }
        public double WUCacheMB      { get; set; }
        public double BrowserCacheMB { get; set; }
        public double DnsEntries     { get; set; }
        public double OrphanedKeys   { get; set; }
        public double EventLogsMB    { get; set; }
        public double RamUsedPct     { get; set; }
        public double DiskCUsedPct   { get; set; }
    }

    /// <summary>Elemento individual del informe (fila o cabecera de sección).</summary>
    public class DiagItem
    {
        /// <summary>true = cabecera de sección; false = fila de datos.</summary>
        public bool   IsSection   { get; set; }
        public string SectionTitle{ get; set; }
        public string SectionIcon { get; set; }

        /// <summary>OK | WARN | CRIT | INFO</summary>
        public string Status      { get; set; }
        public string Label       { get; set; }
        public string Detail      { get; set; }
        public string Action      { get; set; }
        public int    Deduction   { get; set; }
        public string ExportLine  { get; set; }
    }

    /// <summary>Resultado completo del análisis diagnóstico.</summary>
    public class DiagResult
    {
        public List<DiagItem> Items     { get; set; }
        public int    Score             { get; set; }
        public int    CritCount         { get; set; }
        public int    WarnCount         { get; set; }
        public string ScoreLabel        { get; set; }
        public string ScoreColor        { get; set; }
        public List<string> ExportLines { get; set; }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Motor
    // ═══════════════════════════════════════════════════════════════════════

    public static class DiagnosticsEngine
    {
        /// <summary>
        /// Analiza los datos del sistema y devuelve el informe completo
        /// con secciones, filas, puntuación y texto exportable.
        /// </summary>
        public static DiagResult Analyze(DiagInput report)
        {
            if (report == null) report = new DiagInput();

            List<DiagItem> items = new List<DiagItem>();
            List<string> export  = new List<string>();
            int deductions = 0;
            int critCount  = 0;
            int warnCount  = 0;

            string dateStr = DateTime.Now.ToString("dd/MM/yyyy HH:mm:ss");
            export.Add(Loc.T("DiagReportTitle", "INFORME DE DIAGNÓSTICO DEL SISTEMA — SysOpt v1.0"));
            export.Add(string.Format(Loc.T("DiagExportDate", "Fecha: {0}"), dateStr));
            export.Add("");

            // ── ALMACENAMIENTO ──────────────────────────────────────────
            AddSection(items, export, Loc.T("DiagSectStorage", "ALMACENAMIENTO"), "\U0001F5C4\uFE0F");

            double tempTotal = report.TempFilesMB + report.UserTempMB;
            if (tempTotal > 1000)
            {
                AddRow(items, ref deductions, ref critCount, ref warnCount, export,
                    "CRIT", Loc.T("DiagTempCrit", "Archivos temporales acumulados"),
                    string.Format(Loc.T("DiagTempCritDetail", "{0} MB en carpetas Temp"), Math.Round(tempTotal, 0)),
                    Loc.T("DiagTempCritAction", "Limpiar Temp Windows + Usuario"), 15);
            }
            else if (tempTotal > 200)
            {
                AddRow(items, ref deductions, ref critCount, ref warnCount, export,
                    "WARN", Loc.T("DiagTempWarn", "Archivos temporales moderados"),
                    string.Format(Loc.T("DiagTempWarnDetail", "{0} MB — recomendable limpiar"), Math.Round(tempTotal, 0)),
                    Loc.T("DiagTempWarnAction", "Limpiar carpetas Temp"), 7);
            }
            else
            {
                AddRow(items, ref deductions, ref critCount, ref warnCount, export,
                    "OK", Loc.T("DiagTempOk", "Carpetas temporales limpias"),
                    string.Format(Loc.T("DiagOptimalLevel", "{0} MB — nivel óptimo"), Math.Round(tempTotal, 1)),
                    "", 0);
            }

            double recycleSize = report.RecycleBinMB;
            if (recycleSize > 500)
            {
                AddRow(items, ref deductions, ref critCount, ref warnCount, export,
                    "WARN", Loc.T("DiagRecycleBinFull", "Papelera de reciclaje llena"),
                    string.Format(Loc.T("DiagRecycleBinDetail", "{0} MB ocupados"), Math.Round(recycleSize, 0)),
                    Loc.T("DiagRecycleBinAction", "Vaciar papelera"), 5);
            }
            else if (recycleSize > 0)
            {
                AddRow(items, ref deductions, ref critCount, ref warnCount, export,
                    "INFO", Loc.T("DiagRecycleBinInfo", "Papelera con contenido"),
                    string.Format("{0} MB", Math.Round(recycleSize, 1)),
                    "", 0);
            }
            else
            {
                AddRow(items, ref deductions, ref critCount, ref warnCount, export,
                    "OK", Loc.T("DiagRecycleBinEmpty", "Papelera vacía"),
                    Loc.T("DiagRecycleBinEmptyDetail", "Sin archivos pendientes de eliminar"), "", 0);
            }

            double wuSize = report.WUCacheMB;
            if (wuSize > 2000)
            {
                AddRow(items, ref deductions, ref critCount, ref warnCount, export,
                    "WARN", Loc.T("DiagWUCacheLarge", "Caché de Windows Update grande"),
                    string.Format(Loc.T("DiagWUCacheDetail", "{0} MB en SoftwareDistribution"), Math.Round(wuSize, 0)),
                    Loc.T("DiagWUCacheAction", "Limpiar WU Cache"), 8);
            }
            else if (wuSize > 0)
            {
                AddRow(items, ref deductions, ref critCount, ref warnCount, export,
                    "INFO", Loc.T("DiagWUCachePresent", "Caché Windows Update presente"),
                    string.Format("{0} MB", Math.Round(wuSize, 1)),
                    "", 0);
            }
            else
            {
                AddRow(items, ref deductions, ref critCount, ref warnCount, export,
                    "OK", Loc.T("DiagWUCacheClean", "Caché de Windows Update limpia"),
                    Loc.T("DiagNoUpdateResidues", "Sin residuos de actualización"), "", 0);
            }

            // ── MEMORIA Y RENDIMIENTO ───────────────────────────────────
            AddSection(items, export, Loc.T("DiagSectMemory", "MEMORIA Y RENDIMIENTO"), "\U0001F4BE");

            double ramPct = report.RamUsedPct;
            if (ramPct > 85)
            {
                AddRow(items, ref deductions, ref critCount, ref warnCount, export,
                    "CRIT", Loc.T("DiagRamCritical", "Memoria RAM crítica"),
                    string.Format(Loc.T("DiagRamCritDetail", "{0}% en uso — riesgo de lentitud severa"), ramPct),
                    Loc.T("DiagRamCritAction", "Liberar RAM urgente"), 20);
            }
            else if (ramPct > 70)
            {
                AddRow(items, ref deductions, ref critCount, ref warnCount, export,
                    "WARN", Loc.T("DiagRamWarn", "Uso de RAM elevado"),
                    string.Format(Loc.T("DiagRamPctInUse", "{0}% en uso"), ramPct),
                    Loc.T("DiagRamWarnAction", "Liberar RAM recomendado"), 10);
            }
            else
            {
                AddRow(items, ref deductions, ref critCount, ref warnCount, export,
                    "OK", Loc.T("DiagRamOk", "Memoria RAM en niveles normales"),
                    string.Format(Loc.T("DiagRamPctInUse", "{0}% en uso"), ramPct),
                    "", 0);
            }

            double diskPct = report.DiskCUsedPct;
            if (diskPct > 90)
            {
                AddRow(items, ref deductions, ref critCount, ref warnCount, export,
                    "CRIT", Loc.T("DiagDiskCrit", "Disco C: casi lleno"),
                    string.Format(Loc.T("DiagDiskCritDetail", "{0}% ocupado — rendimiento muy degradado"), diskPct),
                    Loc.T("DiagDiskCritAction", "Liberar espacio urgente"), 20);
            }
            else if (diskPct > 75)
            {
                AddRow(items, ref deductions, ref critCount, ref warnCount, export,
                    "WARN", Loc.T("DiagDiskWarn", "Disco C: con poco espacio libre"),
                    string.Format(Loc.T("DiagDiskPctUsed", "{0}% ocupado"), diskPct),
                    Loc.T("DiagDiskWarnAction", "Limpiar archivos"), 10);
            }
            else
            {
                AddRow(items, ref deductions, ref critCount, ref warnCount, export,
                    "OK", Loc.T("DiagDiskOk", "Espacio en disco C: saludable"),
                    string.Format(Loc.T("DiagDiskPctUsed", "{0}% ocupado"), diskPct),
                    "", 0);
            }

            // ── RED Y NAVEGADORES ───────────────────────────────────────
            AddSection(items, export, Loc.T("DiagSectNetwork", "RED Y NAVEGADORES"), "\U0001F310");

            double dnsCount = report.DnsEntries;
            if (dnsCount > 500)
            {
                AddRow(items, ref deductions, ref critCount, ref warnCount, export,
                    "WARN", Loc.T("DiagDnsCacheLarge", "Caché DNS muy grande"),
                    string.Format(Loc.T("DiagDnsSlowResolution", "{0} entradas — puede ralentizar resolución"), dnsCount),
                    Loc.T("DiagCleanDns", "Limpiar caché DNS"), 5);
            }
            else
            {
                AddRow(items, ref deductions, ref critCount, ref warnCount, export,
                    "OK", Loc.T("DiagDnsCacheNormal", "Caché DNS normal"),
                    string.Format(Loc.T("DiagDnsEntries", "{0} entradas"), dnsCount),
                    "", 0);
            }

            double browserMB = report.BrowserCacheMB;
            if (browserMB > 1000)
            {
                AddRow(items, ref deductions, ref critCount, ref warnCount, export,
                    "WARN", Loc.T("DiagBrowserCacheLarge", "Caché de navegadores muy grande"),
                    string.Format(Loc.T("DiagBrowserWarnDetail", "{0} MB — recomendable limpiar"), Math.Round(browserMB, 0)),
                    Loc.T("DiagCleanBrowsers", "Limpiar caché navegadores"), 5);
            }
            else if (browserMB > 200)
            {
                AddRow(items, ref deductions, ref critCount, ref warnCount, export,
                    "INFO", Loc.T("DiagBrowserCachePresent", "Caché de navegadores presente"),
                    string.Format("{0} MB", Math.Round(browserMB, 1)),
                    "", 0);
            }
            else
            {
                AddRow(items, ref deductions, ref critCount, ref warnCount, export,
                    "OK", Loc.T("DiagBrowserCacheClean", "Caché de navegadores limpia"),
                    string.Format("{0} MB", Math.Round(browserMB, 1)),
                    "", 0);
            }

            // ── REGISTRO DE WINDOWS ─────────────────────────────────────
            AddSection(items, export, Loc.T("DiagSectRegistry", "REGISTRO DE WINDOWS"), "\U0001F4CB");

            double orphaned = report.OrphanedKeys;
            if (orphaned > 20)
            {
                AddRow(items, ref deductions, ref critCount, ref warnCount, export,
                    "WARN", Loc.T("DiagOrphanKeys", "Claves huérfanas en el registro"),
                    string.Format(Loc.T("DiagOrphanDetail", "{0} claves de programas desinstalados"), orphaned),
                    Loc.T("DiagOrphanAction", "Limpiar registro"), 5);
            }
            else if (orphaned > 0)
            {
                AddRow(items, ref deductions, ref critCount, ref warnCount, export,
                    "INFO", Loc.T("DiagSomeOrphanKeys", "Algunas claves huérfanas"),
                    string.Format(Loc.T("DiagMinimalImpact", "{0} claves — impacto mínimo"), orphaned),
                    "", 0);
            }
            else
            {
                AddRow(items, ref deductions, ref critCount, ref warnCount, export,
                    "OK", Loc.T("DiagRegistryClean", "Registro sin claves huérfanas"),
                    Loc.T("DiagRegistryCleanDetail", "No se detectaron entradas obsoletas"), "", 0);
            }

            // ── REGISTROS DE EVENTOS ────────────────────────────────────
            AddSection(items, export, Loc.T("DiagSectEventLogs", "REGISTROS DE EVENTOS"), "\U0001F4F0");

            double eventMB = report.EventLogsMB;
            if (eventMB > 100)
            {
                AddRow(items, ref deductions, ref critCount, ref warnCount, export,
                    "WARN", Loc.T("DiagEventLogWarn", "Logs de eventos grandes"),
                    string.Format(Loc.T("DiagEventLogDetail", "{0} MB en System+Application+Setup"), Math.Round(eventMB, 1)),
                    Loc.T("DiagEventLogAction", "Limpiar Event Logs"), 3);
            }
            else
            {
                AddRow(items, ref deductions, ref critCount, ref warnCount, export,
                    "OK", Loc.T("DiagEventLogsOk", "Logs de eventos dentro de límites"),
                    string.Format("{0} MB", Math.Round(eventMB, 1)),
                    "", 0);
            }

            // ── PUNTUACIÓN ──────────────────────────────────────────────
            int finalScore = Math.Max(0, 100 - deductions);
            string scoreColor;
            string scoreLabel;
            if (finalScore >= 80)
            {
                scoreColor = "#4AE896";
                scoreLabel = Loc.T("DiagScoreGood", "Sistema en buen estado");
            }
            else if (finalScore >= 55)
            {
                scoreColor = "#FFB547";
                scoreLabel = Loc.T("DiagScoreRecommended", "Mantenimiento recomendado");
            }
            else
            {
                scoreColor = "#FF6B84";
                scoreLabel = Loc.T("DiagUrgent", "Atención urgente");
            }

            export.Add("");
            export.Add(Loc.T("DiagExportSummary", "=== RESUMEN ==="));
            export.Add(string.Format(Loc.T("DiagScore", "Puntuación: {0} / 100"), finalScore));
            export.Add(string.Format(Loc.T("DiagCritWarn", "Críticos: {0}  |  Avisos: {1}"), critCount, warnCount));
            export.Add(string.Format(Loc.T("DiagExportState", "Estado: {0}"), scoreLabel));

            return new DiagResult
            {
                Items      = items,
                Score      = finalScore,
                CritCount  = critCount,
                WarnCount  = warnCount,
                ScoreLabel = scoreLabel,
                ScoreColor = scoreColor,
                ExportLines = export
            };
        }

        // ── Helpers privados ────────────────────────────────────────────

        private static void AddSection(List<DiagItem> items, List<string> export,
            string title, string icon)
        {
            items.Add(new DiagItem
            {
                IsSection    = true,
                SectionTitle = title,
                SectionIcon  = icon
            });
            if (export.Count > 3) export.Add(""); // separador entre secciones
            export.Add(string.Format("=== {0} ===", title));
        }

        private static void AddRow(List<DiagItem> items,
            ref int deductions, ref int critCount, ref int warnCount,
            List<string> export,
            string status, string label, string detail, string action,
            int deduction)
        {
            items.Add(new DiagItem
            {
                IsSection  = false,
                Status     = status,
                Label      = label,
                Detail     = detail,
                Action     = action,
                Deduction  = deduction
            });

            deductions += deduction;
            if (status == "CRIT") critCount++;
            else if (status == "WARN") warnCount++;

            // Línea de exportación
            string prefix;
            if (status == "CRIT") prefix = Loc.T("DiagCritPrefix", "[CRÍTICO]");
            else if (status == "WARN") prefix = Loc.T("DiagPrefixWarn", "[AVISO]");
            else if (status == "INFO") prefix = Loc.T("DiagPrefixInfo", "[INFO]");
            else prefix = Loc.T("DiagPrefixOk", "[OK]");

            string exportLine = string.Format("{0} {1}: {2}", prefix, label, detail);
            if (!string.IsNullOrEmpty(action))
            {
                exportLine = string.Format("{0} — {1}", exportLine, action);
            }
            export.Add(exportLine);
        }
    }
}
