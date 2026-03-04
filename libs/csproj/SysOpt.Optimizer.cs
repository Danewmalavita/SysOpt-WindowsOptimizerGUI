// =============================================================================
// SysOpt.Optimizer.cs  —  Motor de orquestación de optimización del sistema
// Fase 2D.1 del plan de externalización
//
// Absorbe la lógica inline del $OptimizationScript (runspace worker):
//   - WUCacheManager:  Limpieza de Windows Update cache (antes ~55 líneas PS1)
//   - ProcessManager:  Liberación de RAM y cierre de procesos (antes ~110 líneas PS1)
//   - OptimizerEngine: Orquestador de las 15 tareas con progreso y cancelación
//
// Referencias requeridas:
//   /r:SysOpt.Core.dll        → CleanupEngine, CleanupResult, SystemDataCollector, RamSnapshot
//   /r:SysOpt.DiskEngine.dll  → DiskOptimizer, VolumeInfo, DiskResult
//   /r:SysOpt.MemoryHelper.dll→ MemoryHelper (P/Invoke Win32)
//   /r:System.ServiceProcess.dll → ServiceController (wuauserv)
//   /r:System.Management.dll     → ManagementObjectSearcher (parent PID)
//
// Compilador: csc.exe (.NET Framework 4.x, C# 5)
// =============================================================================

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Management;
using System.ServiceProcess;
using System.Threading;

namespace SysOpt.Optimizer
{
    // =========================================================================
    // DTOs
    // =========================================================================

    /// <summary>
    /// Opciones de optimización — mapeo 1:1 con los checkboxes del XAML.
    /// Se puebla desde el hashtable $options del PS1.
    /// </summary>
    public class OptimizeOptions
    {
        public bool DryRun         { get; set; }
        public bool OptimizeDisks  { get; set; }
        public bool RecycleBin     { get; set; }
        public bool TempFiles      { get; set; }
        public bool UserTemp       { get; set; }
        public bool WUCache        { get; set; }
        public bool Chkdsk         { get; set; }
        public bool ClearMemory    { get; set; }
        public bool CloseProcesses { get; set; }
        public bool DNSCache       { get; set; }
        public bool BrowserCache   { get; set; }
        public bool BackupRegistry { get; set; }
        public bool CleanRegistry  { get; set; }
        public bool SFC            { get; set; }
        public bool DISM           { get; set; }
        public bool EventLogs      { get; set; }
        public bool AutoRestart    { get; set; }
    }

    /// <summary>
    /// Evento de progreso enviado al PS1 vía Action&lt;OptimizeProgress&gt;.
    /// El wrapper PS1 traduce cada evento a Dispatcher.Invoke().
    /// </summary>
    public class OptimizeProgress
    {
        public string TaskName { get; set; }   // Nombre de la tarea actual (para TaskText)
        public int    Percent  { get; set; }   // 0-100 global, -1 = sin cambio
        public string Message  { get; set; }   // Línea de consola (para ConsoleOutput.AppendText)
        public string Status   { get; set; }   // Texto de estado (para StatusText)
        public bool   IsError  { get; set; }

        public OptimizeProgress() { Percent = -1; }
    }

    /// <summary>Resultado de una tarea individual.</summary>
    public class TaskResult
    {
        public string       TaskName   { get; set; }
        public bool         Success    { get; set; }
        public double       FreedMB    { get; set; }
        public int          ItemsCount { get; set; }
        public List<string> Messages   { get; set; }
        public string       Error      { get; set; }

        public TaskResult()
        {
            Messages = new List<string>();
            Success  = true;
        }
    }

    /// <summary>Datos diagnósticos recopilados durante DryRun para el informe.</summary>
    [Serializable]
    public class DiagnosticData
    {
        public double TempFilesMB    { get; set; }
        public double UserTempMB     { get; set; }
        public double RecycleBinMB   { get; set; }
        public double WUCacheMB      { get; set; }
        public double BrowserCacheMB { get; set; }
        public int    DnsEntries     { get; set; }
        public int    OrphanedKeys   { get; set; }
        public double EventLogsMB    { get; set; }
        public int    RamUsedPct     { get; set; }
        public int    DiskCUsedPct   { get; set; }
    }

    /// <summary>Resultado global de la sesión de optimización.</summary>
    public class OptimizeResult
    {
        public bool             Cancelled      { get; set; }
        public bool             IsDryRun       { get; set; }
        public List<TaskResult> Tasks          { get; set; }
        public double           TotalFreedMB   { get; set; }
        public int              TotalTasks     { get; set; }
        public int              CompletedTasks { get; set; }
        public TimeSpan         Duration       { get; set; }
        public DiagnosticData   DiagData       { get; set; }
        public string           Summary        { get; set; }

        public OptimizeResult()
        {
            Tasks    = new List<TaskResult>();
            DiagData = new DiagnosticData();
        }
    }

    // =========================================================================
    // WUCacheManager — Limpieza de Windows Update Cache
    // =========================================================================

    /// <summary>
    /// Gestiona la limpieza de la carpeta SoftwareDistribution\Download.
    /// Reemplaza ~55 líneas inline del $OptimizationScript (tarea 5).
    /// </summary>
    public static class WUCacheManager
    {
        public static TaskResult Clean(bool dryRun)
        {
            var result = new TaskResult { TaskName = "WUCache" };
            string wuPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                "SoftwareDistribution", "Download");

            try
            {
                // Calcular tamaño actual
                double beforeMB = 0;
                if (Directory.Exists(wuPath))
                {
                    beforeMB = GetDirectorySizeMB(wuPath);
                }
                result.Messages.Add("  Tamaño actual: " + beforeMB + " MB");
                result.FreedMB = beforeMB;   // en dry-run = lo que se liberaría

                if (dryRun)
                {
                    result.Messages.Add("  [DRY RUN] Se liberarían ~" + beforeMB + " MB");
                    return result;
                }

                // Detener servicio Windows Update
                result.Messages.Add("  Deteniendo servicio Windows Update (wuauserv)...");
                StopService("wuauserv", 30);

                Thread.Sleep(2000);

                // Eliminar contenido
                if (Directory.Exists(wuPath))
                {
                    foreach (string entry in Directory.GetFileSystemEntries(wuPath))
                    {
                        try
                        {
                            if (File.Exists(entry))
                                File.Delete(entry);
                            else if (Directory.Exists(entry))
                                Directory.Delete(entry, true);
                        }
                        catch { }
                    }
                }

                // Calcular espacio liberado
                double afterMB = Directory.Exists(wuPath) ? GetDirectorySizeMB(wuPath) : 0;
                result.FreedMB = Math.Round(beforeMB - afterMB, 2);

                // Reiniciar servicio
                StartService("wuauserv");
                result.Messages.Add("  \u2713 Servicio Windows Update reiniciado");
                result.Messages.Add("  \u2713 WU Cache limpiada \u2014 " + result.FreedMB + " MB liberados");
            }
            catch (Exception ex)
            {
                result.Error   = ex.Message;
                result.Success = false;
                result.Messages.Add("  ! Error: " + ex.Message);
                // Asegurar que el servicio quede activo aunque falle
                try { StartService("wuauserv"); } catch { }
            }

            return result;
        }

        // ── Helpers ─────────────────────────────────────────────────────────

        private static double GetDirectorySizeMB(string path)
        {
            long total = 0;
            try
            {
                var di = new DirectoryInfo(path);
                foreach (FileInfo fi in di.EnumerateFiles("*", SearchOption.AllDirectories))
                {
                    try { total += fi.Length; } catch { }
                }
            }
            catch { }
            return Math.Round(total / 1048576.0, 2);
        }

        private static void StopService(string name, int timeoutSec)
        {
            try
            {
                using (var sc = new ServiceController(name))
                {
                    if (sc.Status == ServiceControllerStatus.Running ||
                        sc.Status == ServiceControllerStatus.StartPending)
                    {
                        sc.Stop();
                        sc.WaitForStatus(ServiceControllerStatus.Stopped,
                                         TimeSpan.FromSeconds(timeoutSec));
                    }
                }
            }
            catch { }
        }

        private static void StartService(string name)
        {
            try
            {
                using (var sc = new ServiceController(name))
                {
                    if (sc.Status != ServiceControllerStatus.Running)
                    {
                        sc.Start();
                    }
                }
            }
            catch { }
        }
    }

    // =========================================================================
    // ProcessManager — Liberación de RAM y cierre de procesos no críticos
    // =========================================================================

    /// <summary>
    /// Reemplaza ~110 líneas inline del $OptimizationScript (tareas 7 y 8).
    /// </summary>
    public static class ProcessManager
    {
        /// <summary>Lista de procesos críticos que NUNCA deben cerrarse.</summary>
        private static readonly HashSet<string> CriticalProcesses = new HashSet<string>(
            StringComparer.OrdinalIgnoreCase)
        {
            "System", "svchost", "csrss", "wininit", "services", "lsass", "winlogon",
            "dwm", "explorer", "taskhostw", "RuntimeBroker", "sihost", "fontdrvhost",
            "smss", "conhost", "dllhost", "spoolsv", "SearchIndexer", "MsMpEng",
            "powershell", "pwsh", "audiodg", "wudfhost", "dasHost", "TextInputHost",
            "SecurityHealthService", "SgrmBroker", "SecurityHealthSystray",
            "ShellExperienceHost", "StartMenuExperienceHost", "SearchUI", "Cortana",
            "ApplicationFrameHost", "SystemSettings", "WmiPrvSE", "Memory Compression"
        };

        /// <summary>
        /// Vacía el Working Set de todos los procesos accesibles.
        /// Usa MemoryHelper (P/Invoke: OpenProcess + EmptyWorkingSet).
        /// </summary>
        public static TaskResult ClearMemory(bool dryRun)
        {
            var result = new TaskResult { TaskName = "ClearMemory" };

            try
            {
                RamSnapshot ramBefore = SystemDataCollector.GetRamSnapshot();
                double totalGB   = Math.Round(ramBefore.TotalBytes / 1073741824.0, 2);
                double freeGBBef = Math.Round(ramBefore.FreeBytes  / 1073741824.0, 2);

                result.Messages.Add("  Total RAM:       " + totalGB  + " GB");
                result.Messages.Add("  Libre antes:     " + freeGBBef + " GB");

                if (dryRun)
                {
                    result.Messages.Add("  [DRY RUN] Se vaciaría el Working Set de todos los procesos accesibles");
                    return result;
                }

                int count = 0;
                foreach (Process proc in Process.GetProcesses())
                {
                    try
                    {
                        IntPtr hProc = MemoryHelper.OpenProcess(0x1F0FFF, false, proc.Id);
                        if (hProc != IntPtr.Zero)
                        {
                            MemoryHelper.EmptyWorkingSet(hProc);
                            MemoryHelper.CloseHandle(hProc);
                            count++;
                        }
                    }
                    catch { }
                }

                result.Messages.Add("  Working Set vaciado en " + count + " procesos");
                result.ItemsCount = count;

                Thread.Sleep(2000);

                RamSnapshot ramAfter = SystemDataCollector.GetRamSnapshot();
                double freeGBAft = Math.Round(ramAfter.FreeBytes / 1073741824.0, 2);
                double gained    = Math.Round(freeGBAft - freeGBBef, 2);

                result.Messages.Add("  Libre después:   " + freeGBAft + " GB");
                result.Messages.Add("  \u2713 RAM recuperada: " + gained + " GB");
            }
            catch (Exception ex)
            {
                result.Error   = ex.Message;
                result.Success = false;
                result.Messages.Add("  Error: " + ex.Message);
            }

            return result;
        }

        /// <summary>
        /// Cierra procesos no críticos de la sesión actual del usuario.
        /// </summary>
        public static TaskResult CloseNonCritical(bool dryRun)
        {
            var result = new TaskResult { TaskName = "CloseProcesses" };

            try
            {
                int currentPid = Process.GetCurrentProcess().Id;
                int sessionId  = Process.GetCurrentProcess().SessionId;
                int parentPid  = GetParentPid(currentPid);

                var targets = new List<Process>();
                foreach (Process proc in Process.GetProcesses())
                {
                    try
                    {
                        if (proc.SessionId == sessionId &&
                            !CriticalProcesses.Contains(proc.ProcessName) &&
                            proc.Id != currentPid &&
                            proc.Id != parentPid &&
                            proc.ProcessName != "Idle")
                        {
                            targets.Add(proc);
                        }
                    }
                    catch { }
                }

                result.Messages.Add("  Procesos candidatos: " + targets.Count);

                int closed = 0;
                foreach (Process p in targets)
                {
                    if (dryRun)
                    {
                        result.Messages.Add("  [DRY RUN] Cerraría: " + p.ProcessName +
                                            " (PID: " + p.Id + ")");
                    }
                    else
                    {
                        try
                        {
                            p.Kill();
                            closed++;
                            result.Messages.Add("  \u2713 Cerrado: " + p.ProcessName +
                                                " (PID: " + p.Id + ")");
                        }
                        catch { }
                    }
                }

                result.Messages.Add("");
                result.Messages.Add("  \u2713 Procesos cerrados: " + closed + " de " + targets.Count);
                result.ItemsCount = closed;
            }
            catch (Exception ex)
            {
                result.Error   = ex.Message;
                result.Success = false;
                result.Messages.Add("  Error: " + ex.Message);
            }

            return result;
        }

        /// <summary>Obtiene el PID del proceso padre vía WMI.</summary>
        private static int GetParentPid(int pid)
        {
            try
            {
                using (var searcher = new ManagementObjectSearcher(
                    "SELECT ParentProcessId FROM Win32_Process WHERE ProcessId=" + pid))
                {
                    foreach (ManagementObject obj in searcher.Get())
                    {
                        return Convert.ToInt32(obj["ParentProcessId"]);
                    }
                }
            }
            catch { }
            return -1;
        }
    }

    // =========================================================================
    // OptimizerEngine — Orquestador principal
    // =========================================================================

    /// <summary>
    /// Secuencia las 15 tareas de optimización con progreso y cancelación.
    /// Reemplaza el if/else chain del $OptimizationScript (~620 líneas PS1)
    /// por una sola llamada: OptimizerEngine.Run(opts, ct, callback).
    /// </summary>
    public static class OptimizerEngine
    {
        /// <summary>
        /// Claves de tareas en orden de ejecución (mapeo 1:1 con $taskKeys del PS1).
        /// </summary>
        private static readonly string[] TaskKeys = new string[]
        {
            "OptimizeDisks", "RecycleBin", "TempFiles", "UserTemp", "WUCache",
            "Chkdsk", "ClearMemory", "CloseProcesses", "DNSCache", "BrowserCache",
            "BackupRegistry", "CleanRegistry", "SFC", "DISM", "EventLogs"
        };

        /// <summary>Etiquetas legibles para cada tarea.</summary>
        private static readonly Dictionary<string, string> TaskLabels;

        /// <summary>Números de sección para los banners.</summary>
        private static readonly Dictionary<string, string> TaskBanners;

        static OptimizerEngine()
        {
            TaskLabels = new Dictionary<string, string>
            {
                { "OptimizeDisks",  "Optimización de discos" },
                { "RecycleBin",     "Vaciando papelera" },
                { "TempFiles",      "Archivos temporales Windows" },
                { "UserTemp",       "Archivos temporales Usuario" },
                { "WUCache",        "Windows Update Cache" },
                { "Chkdsk",         "Check Disk (CHKDSK)" },
                { "ClearMemory",    "Liberando memoria RAM" },
                { "CloseProcesses", "Cerrando procesos" },
                { "DNSCache",       "Limpiando caché DNS" },
                { "BrowserCache",   "Limpiando navegadores" },
                { "BackupRegistry", "Backup del registro" },
                { "CleanRegistry",  "Limpiando registro" },
                { "SFC",            "SFC /SCANNOW" },
                { "DISM",           "DISM" },
                { "EventLogs",      "Event Viewer Logs" }
            };

            TaskBanners = new Dictionary<string, string>
            {
                { "OptimizeDisks",  "1. OPTIMIZACIÓN DE DISCOS DUROS" },
                { "RecycleBin",     "2. VACIANDO PAPELERA DE RECICLAJE" },
                { "TempFiles",      "3. ARCHIVOS TEMPORALES DE WINDOWS" },
                { "UserTemp",       "4. ARCHIVOS TEMPORALES DE USUARIO" },
                { "WUCache",        "5. WINDOWS UPDATE CACHE (SoftwareDistribution)" },
                { "Chkdsk",         "6. PROGRAMANDO CHECK DISK (CHKDSK)" },
                { "ClearMemory",    "7. LIBERANDO MEMORIA RAM" },
                { "CloseProcesses", "8. CERRANDO PROCESOS NO CRÍTICOS" },
                { "DNSCache",       "9. LIMPIANDO CACHÉ DNS" },
                { "BrowserCache",   "10. LIMPIANDO CACHÉ DE NAVEGADORES" },
                { "BackupRegistry", "11. BACKUP DEL REGISTRO" },
                { "CleanRegistry",  "12. LIMPIANDO CLAVES HUÉRFANAS DEL REGISTRO" },
                { "SFC",            "13. SFC /SCANNOW" },
                { "DISM",           "14. DISM \u2014 Reparación de imagen del sistema" },
                { "EventLogs",      "15. LIMPIANDO EVENT VIEWER LOGS" }
            };
        }

        // =====================================================================
        // Run — Punto de entrada principal
        // =====================================================================

        /// <summary>
        /// Ejecuta todas las tareas seleccionadas en secuencia.
        /// </summary>
        /// <param name="options">Tareas a ejecutar y modo dry-run.</param>
        /// <param name="ct">Token de cancelación (del CancelButton PS1).</param>
        /// <param name="onProgress">Callback para actualizar la UI desde PS1.</param>
        /// <returns>Resultado agregado con métricas y datos diagnósticos.</returns>
        public static OptimizeResult Run(
            OptimizeOptions options,
            CancellationToken ct,
            Action<OptimizeProgress> onProgress)
        {
            var result = new OptimizeResult { IsDryRun = options.DryRun };
            bool dryRun = options.DryRun;
            string dryRunLabel = dryRun ? " [MODO ANÁLISIS \u2014 sin cambios]" : "";

            // Determinar tareas seleccionadas
            var selected = GetSelectedTasks(options);
            result.TotalTasks = selected.Count;

            if (selected.Count == 0)
            {
                Msg(onProgress, "", 0, "No hay tareas seleccionadas.");
                Status(onProgress, "Sin tareas seleccionadas");
                return result;
            }

            int totalTasks     = selected.Count;
            int completedTasks = 0;
            DateTime startTime = DateTime.Now;

            // ── Header ──────────────────────────────────────────────────────
            int boxWidth = 62;
            string titleLine = dryRun
                ? "INICIANDO OPTIMIZACIÓN  \u2014  MODO ANÁLISIS (DRY RUN)"
                : "INICIANDO OPTIMIZACIÓN DEL SISTEMA WINDOWS";
            EmitBox(onProgress, boxWidth, titleLine, 0);
            Msg(onProgress, "", 0,
                "Fecha:    " + DateTime.Now.ToString("dd/MM/yyyy HH:mm:ss"));
            Msg(onProgress, "", 0,
                "Modo:     " + (dryRun
                    ? "\U0001f50d ANÁLISIS (Dry Run) \u2014 solo reportar"
                    : "\u2699 EJECUCIÓN real"));
            Msg(onProgress, "", 0, "Tareas:   " + totalTasks);
            Msg(onProgress, "", 0,
                "Tareas a ejecutar: " + string.Join(", ", selected));
            Msg(onProgress, "", 0, "");

            // ── Ejecución secuencial ────────────────────────────────────────
            foreach (string taskKey in selected)
            {
                if (ct.IsCancellationRequested)
                {
                    Msg(onProgress, "", Pct(completedTasks, totalTasks), "");
                    Msg(onProgress, "", Pct(completedTasks, totalTasks),
                        "\u26a0 OPTIMIZACIÓN CANCELADA POR EL USUARIO");
                    Status(onProgress, "\u26a0 Cancelado por el usuario");
                    result.Cancelled = true;
                    break;
                }

                int basePct = Pct(completedTasks, totalTasks);
                string label = TaskLabels.ContainsKey(taskKey)
                    ? TaskLabels[taskKey] : taskKey;
                string banner = TaskBanners.ContainsKey(taskKey)
                    ? TaskBanners[taskKey] : taskKey;

                Progress(onProgress, label, basePct);
                Status(onProgress, (dryRun ? "[DRY RUN] " : "") + label + "...");
                EmitSection(onProgress, banner + dryRunLabel, basePct);

                // Despachar tarea
                TaskResult tr = ExecuteTask(taskKey, dryRun, ct, onProgress, basePct);

                // Emitir mensajes al console
                foreach (string m in tr.Messages)
                {
                    Msg(onProgress, label, basePct, m);
                }

                // Acumular en resultado global
                result.Tasks.Add(tr);
                result.TotalFreedMB += tr.FreedMB;

                // Actualizar DiagData según tarea
                UpdateDiagData(result.DiagData, taskKey, tr);

                completedTasks++;
                result.CompletedTasks = completedTasks;
                Progress(onProgress, "", Pct(completedTasks, totalTasks));
            }

            // ── Capturar estado final de RAM y disco ────────────────────────
            if (!ct.IsCancellationRequested)
            {
                try
                {
                    RamSnapshot ramFinal = SystemDataCollector.GetRamSnapshot();
                    result.DiagData.RamUsedPct = (int)Math.Round(ramFinal.UsedPercent);
                }
                catch { }

                try
                {
                    // Obtener % uso de disco C: vía WMI
                    using (var searcher = new ManagementObjectSearcher(
                        "SELECT Size, FreeSpace FROM Win32_LogicalDisk WHERE DeviceID='C:'"))
                    {
                        foreach (ManagementObject obj in searcher.Get())
                        {
                            long size = Convert.ToInt64(obj["Size"]);
                            long free = Convert.ToInt64(obj["FreeSpace"]);
                            if (size > 0)
                            {
                                result.DiagData.DiskCUsedPct =
                                    (int)Math.Round(((double)(size - free) / size) * 100);
                            }
                        }
                    }
                }
                catch { }
            }

            // ── Footer ──────────────────────────────────────────────────────
            result.Duration = DateTime.Now - startTime;
            string durStr = string.Format("{0:D2}d {1:D2}h {2:D2}m {3:D2}s",
                result.Duration.Days, result.Duration.Hours,
                result.Duration.Minutes, result.Duration.Seconds);

            string footerTitle = result.Cancelled
                ? "OPTIMIZACIÓN CANCELADA"
                : (dryRun
                    ? "ANÁLISIS COMPLETADO EXITOSAMENTE"
                    : "OPTIMIZACIÓN COMPLETADA EXITOSAMENTE");

            Msg(onProgress, "", 100, "");
            EmitBox(onProgress, boxWidth, footerTitle, 100);
            Msg(onProgress, "", 100, "Tareas: " + completedTasks + " / " + totalTasks);
            Msg(onProgress, "", 100, "Tiempo: " + durStr);
            Msg(onProgress, "", 100, "");

            result.Summary = footerTitle + " | " + completedTasks + "/" + totalTasks +
                             " tareas | " + durStr;

            if (!result.Cancelled)
            {
                Status(onProgress, "\u2713 " + (dryRun ? "Análisis" : "Optimización") +
                       " completada");
                Progress(onProgress, "\u00a1Todas las tareas completadas!", 100);
            }

            return result;
        }

        // =====================================================================
        // Despacho de tareas individuales
        // =====================================================================

        private static TaskResult ExecuteTask(
            string taskKey, bool dryRun, CancellationToken ct,
            Action<OptimizeProgress> onProgress, int basePct)
        {
            switch (taskKey)
            {
                case "OptimizeDisks":  return DoOptimizeDisks(dryRun, ct, onProgress, basePct);
                case "RecycleBin":     return DoRecycleBin(dryRun);
                case "TempFiles":      return DoTempFiles(dryRun);
                case "UserTemp":       return DoUserTemp(dryRun);
                case "WUCache":        return WUCacheManager.Clean(dryRun);
                case "Chkdsk":         return DoChkdsk(dryRun);
                case "ClearMemory":    return ProcessManager.ClearMemory(dryRun);
                case "CloseProcesses": return ProcessManager.CloseNonCritical(dryRun);
                case "DNSCache":       return DoDnsCache(dryRun);
                case "BrowserCache":   return DoBrowserCache(dryRun);
                case "BackupRegistry": return DoBackupRegistry(dryRun);
                case "CleanRegistry":  return DoCleanRegistry(dryRun);
                case "SFC":            return DoSfc(dryRun);
                case "DISM":           return DoDism(dryRun);
                case "EventLogs":      return DoEventLogs(dryRun);
                default:
                    var unknown = new TaskResult { TaskName = taskKey, Success = false };
                    unknown.Messages.Add("  ! Tarea desconocida: " + taskKey);
                    return unknown;
            }
        }

        // ── 1. Optimización de discos (usa DiskOptimizer de SysOpt.DiskEngine) ──

        private static TaskResult DoOptimizeDisks(
            bool dryRun, CancellationToken ct,
            Action<OptimizeProgress> onProgress, int basePct)
        {
            var tr = new TaskResult { TaskName = "OptimizeDisks" };
            try
            {
                VolumeInfo[] volumes = DiskOptimizer.GetFixedVolumes();
                tr.Messages.Add("Unidades encontradas: " + volumes.Length);

                for (int i = 0; i < volumes.Length; i++)
                {
                    if (ct.IsCancellationRequested) break;
                    VolumeInfo vol = volumes[i];

                    tr.Messages.Add("");
                    tr.Messages.Add("  [" + (i + 1) + "/" + volumes.Length + "] Unidad " +
                                    vol.DriveLetter + ": \u2014 " + vol.SizeGB +
                                    " GB total, " + vol.FreeGB + " GB libre");
                    tr.Messages.Add("  Tipo: " + vol.MediaType);

                    DiskResult r = DiskOptimizer.OptimizeVolume(
                        vol.DriveLetter, vol.IsSSD, dryRun);
                    tr.Messages.AddRange(r.Messages);
                }

                tr.Messages.Add("");
                tr.Messages.Add("\u2713 Optimización de discos " +
                                (dryRun ? "analizada" : "completada"));
            }
            catch (Exception ex)
            {
                tr.Error   = ex.Message;
                tr.Success = false;
                tr.Messages.Add("  ! Error: " + ex.Message);
            }
            return tr;
        }

        // ── 2. Papelera (usa CleanupEngine de SysOpt.Core) ─────────────────

        private static TaskResult DoRecycleBin(bool dryRun)
        {
            var tr = new TaskResult { TaskName = "RecycleBin" };
            try
            {
                CleanupResult r = CleanupEngine.EmptyRecycleBin(dryRun);
                tr.Messages.AddRange(r.Messages);
                tr.FreedMB = r.FreedMB;
            }
            catch (Exception ex)
            {
                tr.Error = ex.Message; tr.Success = false;
                tr.Messages.Add("  ! Error: " + ex.Message);
            }
            return tr;
        }

        // ── 3. Temp Windows (usa CleanupEngine.CleanPaths) ──────────────────

        private static TaskResult DoTempFiles(bool dryRun)
        {
            var tr = new TaskResult { TaskName = "TempFiles" };
            try
            {
                string winDir = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
                string[] paths = new string[]
                {
                    Path.Combine(winDir, "Temp"),
                    Path.Combine(winDir, "Prefetch")
                };
                CleanupResult r = CleanupEngine.CleanPaths(paths, dryRun);
                tr.Messages.AddRange(r.Messages);
                tr.FreedMB = r.FreedMB;
                tr.Messages.Add("");
                tr.Messages.Add("  \u2713 Total: " + Math.Round(r.FreedMB, 2) + " MB " +
                                (dryRun ? "por liberar" : "liberados"));
            }
            catch (Exception ex)
            {
                tr.Error = ex.Message; tr.Success = false;
                tr.Messages.Add("  ! Error: " + ex.Message);
            }
            return tr;
        }

        // ── 4. Temp Usuario (usa CleanupEngine.CleanPaths) ──────────────────

        private static TaskResult DoUserTemp(bool dryRun)
        {
            var tr = new TaskResult { TaskName = "UserTemp" };
            try
            {
                string[] paths = new string[]
                {
                    Environment.GetEnvironmentVariable("TEMP") ?? "",
                    Path.Combine(
                        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                        "Temp")
                };
                // Filtrar rutas vacías y duplicadas
                var uniquePaths = new List<string>();
                foreach (string p in paths)
                {
                    if (!string.IsNullOrEmpty(p) && !uniquePaths.Contains(p))
                        uniquePaths.Add(p);
                }
                CleanupResult r = CleanupEngine.CleanPaths(uniquePaths.ToArray(), dryRun);
                tr.Messages.AddRange(r.Messages);
                tr.FreedMB = r.FreedMB;
                tr.Messages.Add("");
                tr.Messages.Add("  \u2713 Total: " + Math.Round(r.FreedMB, 2) + " MB " +
                                (dryRun ? "por liberar" : "liberados"));
            }
            catch (Exception ex)
            {
                tr.Error = ex.Message; tr.Success = false;
                tr.Messages.Add("  ! Error: " + ex.Message);
            }
            return tr;
        }

        // ── 6. Chkdsk (usa DiskOptimizer.ScheduleChkdsk) ───────────────────

        private static TaskResult DoChkdsk(bool dryRun)
        {
            var tr = new TaskResult { TaskName = "Chkdsk" };
            try
            {
                DiskResult r = DiskOptimizer.ScheduleChkdsk("C", dryRun);
                tr.Messages.AddRange(r.Messages);
            }
            catch (Exception ex)
            {
                tr.Error = ex.Message; tr.Success = false;
                tr.Messages.Add("  ! Error: " + ex.Message);
            }
            return tr;
        }

        // ── 9. DNS Cache ────────────────────────────────────────────────────

        private static TaskResult DoDnsCache(bool dryRun)
        {
            var tr = new TaskResult { TaskName = "DNSCache" };
            try
            {
                if (dryRun)
                {
                    // Contar entradas DNS vía ipconfig /displaydns
                    int count = CountDnsCacheEntries();
                    tr.Messages.Add("  [DRY RUN] Caché DNS actual: " + count + " entradas");
                    tr.ItemsCount = count;
                }
                else
                {
                    CleanupResult r = CleanupEngine.FlushDns(false);
                    tr.Messages.AddRange(r.Messages);
                }
            }
            catch (Exception ex)
            {
                tr.Error = ex.Message; tr.Success = false;
                tr.Messages.Add("  Error: " + ex.Message);
            }
            return tr;
        }

        /// <summary>Cuenta entradas de caché DNS vía ipconfig /displaydns.</summary>
        private static int CountDnsCacheEntries()
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = "cmd.exe",
                    Arguments = "/c ipconfig /displaydns",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    StandardOutputEncoding = System.Text.Encoding.UTF8
                };
                using (Process proc = Process.Start(psi))
                {
                    string output = proc.StandardOutput.ReadToEnd();
                    proc.WaitForExit(10000);
                    // Cada entrada tiene "Record Name"
                    int count = 0;
                    foreach (string line in output.Split('\n'))
                    {
                        if (line.IndexOf("Record Name", StringComparison.OrdinalIgnoreCase) >= 0)
                            count++;
                    }
                    return count;
                }
            }
            catch { return 0; }
        }

        // ── 10. Browser Cache (usa CleanupEngine) ───────────────────────────

        private static TaskResult DoBrowserCache(bool dryRun)
        {
            var tr = new TaskResult { TaskName = "BrowserCache" };
            try
            {
                CleanupResult r = CleanupEngine.CleanBrowserCaches(dryRun);
                tr.Messages.AddRange(r.Messages);
                tr.FreedMB = r.FreedMB;
            }
            catch (Exception ex)
            {
                tr.Error = ex.Message; tr.Success = false;
                tr.Messages.Add("  ! Error: " + ex.Message);
            }
            return tr;
        }

        // ── 11. Backup del Registro (usa CleanupEngine) ─────────────────────

        private static TaskResult DoBackupRegistry(bool dryRun)
        {
            var tr = new TaskResult { TaskName = "BackupRegistry" };
            try
            {
                string backupPath = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.Desktop),
                    "RegistryBackup_" + DateTime.Now.ToString("yyyyMMdd_HHmmss"));
                CleanupResult r = CleanupEngine.BackupRegistry(backupPath, dryRun);
                tr.Messages.AddRange(r.Messages);
            }
            catch (Exception ex)
            {
                tr.Error = ex.Message; tr.Success = false;
                tr.Messages.Add("  ! Error: " + ex.Message);
            }
            return tr;
        }

        // ── 12. Limpiar Registro (usa CleanupEngine) ────────────────────────

        private static TaskResult DoCleanRegistry(bool dryRun)
        {
            var tr = new TaskResult { TaskName = "CleanRegistry" };
            try
            {
                CleanupResult r = CleanupEngine.CleanRegistryOrphans(dryRun);
                tr.Messages.AddRange(r.Messages);
                tr.ItemsCount = r.FilesProcessed;
            }
            catch (Exception ex)
            {
                tr.Error = ex.Message; tr.Success = false;
                tr.Messages.Add("  ! Error: " + ex.Message);
            }
            return tr;
        }

        // ── 13. SFC (usa CleanupEngine) ─────────────────────────────────────

        private static TaskResult DoSfc(bool dryRun)
        {
            var tr = new TaskResult { TaskName = "SFC" };
            try
            {
                CleanupResult r = CleanupEngine.RunSfc(dryRun);
                tr.Messages.AddRange(r.Messages);
            }
            catch (Exception ex)
            {
                tr.Error = ex.Message; tr.Success = false;
                tr.Messages.Add("  ! Error: " + ex.Message);
            }
            return tr;
        }

        // ── 14. DISM (usa CleanupEngine) ────────────────────────────────────

        private static TaskResult DoDism(bool dryRun)
        {
            var tr = new TaskResult { TaskName = "DISM" };
            try
            {
                CleanupResult r = CleanupEngine.RunDism(dryRun);
                tr.Messages.AddRange(r.Messages);
            }
            catch (Exception ex)
            {
                tr.Error = ex.Message; tr.Success = false;
                tr.Messages.Add("  ! Error: " + ex.Message);
            }
            return tr;
        }

        // ── 15. Event Logs (usa CleanupEngine) ─────────────────────────────

        private static TaskResult DoEventLogs(bool dryRun)
        {
            var tr = new TaskResult { TaskName = "EventLogs" };
            try
            {
                string[] logNames = new string[] { "System", "Application", "Setup" };
                CleanupResult r = CleanupEngine.CleanEventLogs(logNames, dryRun);
                tr.Messages.AddRange(r.Messages);
                tr.FreedMB = r.FreedMB;
            }
            catch (Exception ex)
            {
                tr.Error = ex.Message; tr.Success = false;
                tr.Messages.Add("  ! Error: " + ex.Message);
            }
            return tr;
        }

        // =====================================================================
        // Helpers internos
        // =====================================================================

        /// <summary>Determina qué tareas están seleccionadas via reflection.</summary>
        private static List<string> GetSelectedTasks(OptimizeOptions opts)
        {
            var list = new List<string>();
            foreach (string key in TaskKeys)
            {
                var prop = typeof(OptimizeOptions).GetProperty(key);
                if (prop != null)
                {
                    object val = prop.GetValue(opts, null);
                    if (val is bool && (bool)val)
                        list.Add(key);
                }
            }
            return list;
        }

        /// <summary>Calcula porcentaje global.</summary>
        private static int Pct(int completed, int total)
        {
            if (total <= 0) return 0;
            return (int)Math.Round(((double)completed / total) * 100);
        }

        /// <summary>Actualiza DiagnosticData con los resultados de la tarea.</summary>
        private static void UpdateDiagData(DiagnosticData d, string taskKey, TaskResult tr)
        {
            switch (taskKey)
            {
                case "TempFiles":      d.TempFilesMB    = tr.FreedMB;    break;
                case "UserTemp":       d.UserTempMB     = tr.FreedMB;    break;
                case "RecycleBin":     d.RecycleBinMB   = tr.FreedMB;    break;
                case "WUCache":        d.WUCacheMB      = tr.FreedMB;    break;
                case "BrowserCache":   d.BrowserCacheMB = tr.FreedMB;    break;
                case "DNSCache":       d.DnsEntries     = tr.ItemsCount; break;
                case "CleanRegistry":  d.OrphanedKeys   = tr.ItemsCount; break;
                case "EventLogs":      d.EventLogsMB    = tr.FreedMB;    break;
            }
        }

        // ── Emisión de progreso ─────────────────────────────────────────────

        /// <summary>Envía un mensaje de consola al callback.</summary>
        private static void Msg(Action<OptimizeProgress> cb, string task, int pct, string msg)
        {
            if (cb == null) return;
            cb(new OptimizeProgress
            {
                TaskName = task,
                Percent  = pct,
                Message  = "[" + DateTime.Now.ToString("HH:mm:ss") + "] " + msg
            });
        }

        /// <summary>Actualiza solo el progreso (barra + task text).</summary>
        private static void Progress(Action<OptimizeProgress> cb, string task, int pct)
        {
            if (cb == null) return;
            cb(new OptimizeProgress { TaskName = task, Percent = pct });
        }

        /// <summary>Actualiza solo el texto de estado.</summary>
        private static void Status(Action<OptimizeProgress> cb, string status)
        {
            if (cb == null) return;
            cb(new OptimizeProgress { Status = status });
        }

        /// <summary>Emite un banner de sección (═══...═══ TÍTULO ═══...═══).</summary>
        private static void EmitSection(Action<OptimizeProgress> cb, string title, int pct)
        {
            Msg(cb, "", pct, "");
            Msg(cb, "", pct, "\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550" +
                "\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550" +
                "\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550" +
                "\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550" +
                "\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550");
            Msg(cb, "", pct, title);
            Msg(cb, "", pct, "\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550" +
                "\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550" +
                "\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550" +
                "\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550" +
                "\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550");
        }

        /// <summary>Emite un recuadro ╔═══╗ / ║ TÍTULO ║ / ╚═══╝.</summary>
        private static void EmitBox(Action<OptimizeProgress> cb, int width, string title, int pct)
        {
            int pad  = Math.Max(0, width - title.Length);
            int left = pad / 2;
            int right = pad - left;

            Msg(cb, "", pct,
                "\u2554" + new string('\u2550', width) + "\u2557");
            Msg(cb, "", pct,
                "\u2551" + new string(' ', left) + title + new string(' ', right) + "\u2551");
            Msg(cb, "", pct,
                "\u255a" + new string('\u2550', width) + "\u255d");
        }
    }
}
