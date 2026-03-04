// ═══════════════════════════════════════════════════════════════════════════
//  SysOpt.StartupManager.cs
//  DLL para gestión de entradas de autoarranque de Windows
//  Compatible con C# 5 / csc.exe (.NET Framework 4.x)
// ═══════════════════════════════════════════════════════════════════════════
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.Serialization;
using System.Text;
using Microsoft.Win32;

namespace SysOpt.StartupManager
{
    // ───────────────────────────── DTOs ─────────────────────────────

    /// <summary>
    /// Representa una entrada de autoarranque (registro o carpeta Startup).
    /// </summary>
    [Serializable]
    public class StartupEntry
    {
        public bool   Enabled      { get; set; }
        public string Name         { get; set; }
        public string Command      { get; set; }
        public string Source       { get; set; }
        public string RegPath      { get; set; }
        public string OriginalName { get; set; }
        public string Type         { get; set; }   // "Registry" | "StartupFolder"
        public string FilePath     { get; set; }   // Ruta del .lnk para tipo StartupFolder

        public StartupEntry()
        {
            Enabled  = true;
            Name     = "";
            Command  = "";
            Source   = "";
            RegPath  = "";
            OriginalName = "";
            Type     = "Registry";
            FilePath = "";
        }
    }

    /// <summary>
    /// Resultado de la operación de aplicar cambios masivos.
    /// </summary>
    [Serializable]
    public class ApplyResult
    {
        public int Disabled { get; set; }
        public int Errors   { get; set; }
        public List<string> ErrorDetails { get; set; }

        public ApplyResult()
        {
            ErrorDetails = new List<string>();
        }
    }

    // ─────────────────────── Motor principal ───────────────────────

    public static class StartupEngine
    {
        // Rutas de registro estándar de autoarranque
        private static readonly string[][] RegistryPaths = new string[][]
        {
            new string[] { @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run",             "HKCU Run",      "HKCU" },
            new string[] { @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run",             "HKLM Run",      "HKLM" },
            new string[] { @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run", "HKLM Run (32)", "HKLM" }
        };

        // ═══════════════════ GetEntries ═══════════════════

        /// <summary>
        /// Lee todas las entradas de autoarranque del registro de Windows
        /// y de la carpeta Startup del usuario.
        /// </summary>
        public static List<StartupEntry> GetEntries()
        {
            var entries = new List<StartupEntry>();

            // 1. Entradas de registro
            foreach (string[] regDef in RegistryPaths)
            {
                string subKey     = regDef[0];
                string sourceName = regDef[1];
                string hiveTag    = regDef[2];

                RegistryKey hive = (hiveTag == "HKCU")
                    ? Registry.CurrentUser
                    : Registry.LocalMachine;

                try
                {
                    using (RegistryKey key = hive.OpenSubKey(subKey, false))
                    {
                        if (key == null) continue;

                        string[] valueNames = key.GetValueNames();
                        foreach (string valName in valueNames)
                        {
                            if (string.IsNullOrEmpty(valName)) continue;

                            object val = key.GetValue(valName);
                            string cmd = (val != null) ? val.ToString() : "";

                            var entry = new StartupEntry();
                            entry.Enabled      = true;
                            entry.Name         = valName;
                            entry.Command      = cmd;
                            entry.Source        = sourceName;
                            entry.RegPath      = hiveTag + @":\" + subKey;
                            entry.OriginalName = valName;
                            entry.Type         = "Registry";

                            entries.Add(entry);
                        }
                    }
                }
                catch (Exception)
                {
                    // Sin acceso a esa clave — continuar con la siguiente
                }
            }

            // 2. Carpeta Startup del usuario
            try
            {
                string startupFolder = Environment.GetFolderPath(
                    Environment.SpecialFolder.Startup);

                if (Directory.Exists(startupFolder))
                {
                    string[] files = Directory.GetFiles(startupFolder);
                    foreach (string filePath in files)
                    {
                        string fileName = Path.GetFileNameWithoutExtension(filePath);
                        string ext      = Path.GetExtension(filePath).ToLowerInvariant();

                        // Solo archivos relevantes (.lnk, .bat, .cmd, .exe, .vbs)
                        if (ext != ".lnk" && ext != ".bat" && ext != ".cmd" &&
                            ext != ".exe" && ext != ".vbs") continue;

                        var entry = new StartupEntry();
                        entry.Enabled      = true;
                        entry.Name         = fileName;
                        entry.Command      = filePath;
                        entry.Source        = "Startup Folder";
                        entry.RegPath      = "";
                        entry.OriginalName = Path.GetFileName(filePath);
                        entry.Type         = "StartupFolder";
                        entry.FilePath     = filePath;

                        entries.Add(entry);
                    }
                }
            }
            catch (Exception)
            {
                // Sin acceso a carpeta Startup — no fatal
            }

            return entries;
        }

        // ═══════════════════ DisableEntry ═══════════════════

        /// <summary>
        /// Deshabilita una única entrada de autoarranque.
        /// Para registro: elimina el valor.
        /// Para carpeta Startup: renombra el archivo añadiendo .disabled.
        /// </summary>
        public static bool DisableEntry(StartupEntry entry)
        {
            if (entry == null) return false;

            try
            {
                if (entry.Type == "StartupFolder")
                {
                    return DisableStartupFolderEntry(entry);
                }
                else
                {
                    return DisableRegistryEntry(entry);
                }
            }
            catch (Exception)
            {
                return false;
            }
        }

        // ═══════════════════ EnableEntry ═══════════════════

        /// <summary>
        /// Rehabilita una entrada previamente deshabilitada.
        /// Para registro: restaura el valor con el comando original.
        /// Para carpeta Startup: renombra el archivo quitando .disabled.
        /// </summary>
        public static bool EnableEntry(StartupEntry entry)
        {
            if (entry == null) return false;

            try
            {
                if (entry.Type == "StartupFolder")
                {
                    return EnableStartupFolderEntry(entry);
                }
                else
                {
                    return EnableRegistryEntry(entry);
                }
            }
            catch (Exception)
            {
                return false;
            }
        }

        // ═══════════════════ ApplyChanges ═══════════════════

        /// <summary>
        /// Aplica los cambios masivos: deshabilita las entradas con Enabled = false.
        /// Solo actúa sobre entradas desmarcadas (Enabled == false).
        /// </summary>
        public static ApplyResult ApplyChanges(IEnumerable<StartupEntry> entries)
        {
            var result = new ApplyResult();

            foreach (StartupEntry entry in entries)
            {
                if (entry.Enabled) continue;  // Solo procesamos las desmarcadas

                bool ok = DisableEntry(entry);
                if (ok)
                {
                    result.Disabled++;
                }
                else
                {
                    result.Errors++;
                    result.ErrorDetails.Add(
                        string.Format("No se pudo deshabilitar: {0} ({1})",
                            entry.Name, entry.Source));
                }
            }

            return result;
        }

        // ═══════════════════ ExportJson ═══════════════════

        /// <summary>
        /// Exporta la lista de entradas como JSON simple (sin dependencias externas).
        /// Útil para backups antes de aplicar cambios.
        /// </summary>
        public static string ExportJson(IEnumerable<StartupEntry> entries)
        {
            var sb = new StringBuilder();
            sb.AppendLine("[");

            bool first = true;
            foreach (StartupEntry e in entries)
            {
                if (!first) sb.AppendLine(",");
                first = false;

                sb.AppendLine("  {");
                sb.AppendLine(string.Format("    \"name\": \"{0}\",",         EscapeJson(e.Name)));
                sb.AppendLine(string.Format("    \"command\": \"{0}\",",      EscapeJson(e.Command)));
                sb.AppendLine(string.Format("    \"source\": \"{0}\",",       EscapeJson(e.Source)));
                sb.AppendLine(string.Format("    \"regPath\": \"{0}\",",      EscapeJson(e.RegPath)));
                sb.AppendLine(string.Format("    \"originalName\": \"{0}\",", EscapeJson(e.OriginalName)));
                sb.AppendLine(string.Format("    \"type\": \"{0}\",",         EscapeJson(e.Type)));
                sb.AppendLine(string.Format("    \"enabled\": {0}",           e.Enabled ? "true" : "false"));
                sb.Append("  }");
            }

            sb.AppendLine();
            sb.AppendLine("]");
            return sb.ToString();
        }

        // ══════════════════ Helpers privados ══════════════════

        private static bool DisableRegistryEntry(StartupEntry entry)
        {
            string hiveName = "";
            string subKey   = "";
            ParseRegPath(entry.RegPath, out hiveName, out subKey);

            RegistryKey hive = GetHive(hiveName);
            if (hive == null) return false;

            using (RegistryKey key = hive.OpenSubKey(subKey, true))
            {
                if (key == null) return false;
                key.DeleteValue(entry.OriginalName, false);
            }
            return true;
        }

        private static bool EnableRegistryEntry(StartupEntry entry)
        {
            string hiveName = "";
            string subKey   = "";
            ParseRegPath(entry.RegPath, out hiveName, out subKey);

            RegistryKey hive = GetHive(hiveName);
            if (hive == null) return false;

            using (RegistryKey key = hive.OpenSubKey(subKey, true))
            {
                if (key == null) return false;
                key.SetValue(entry.OriginalName, entry.Command, RegistryValueKind.String);
            }
            return true;
        }

        private static bool DisableStartupFolderEntry(StartupEntry entry)
        {
            if (string.IsNullOrEmpty(entry.FilePath)) return false;
            if (!File.Exists(entry.FilePath)) return false;

            string disabledPath = entry.FilePath + ".disabled";
            File.Move(entry.FilePath, disabledPath);
            return true;
        }

        private static bool EnableStartupFolderEntry(StartupEntry entry)
        {
            string disabledPath = entry.FilePath + ".disabled";
            if (!File.Exists(disabledPath)) return false;

            File.Move(disabledPath, entry.FilePath);
            return true;
        }

        /// <summary>
        /// Parsea "HKCU:\SOFTWARE\...\Run" en hiveName="HKCU" y subKey="SOFTWARE\...\Run"
        /// </summary>
        private static void ParseRegPath(string regPath, out string hiveName, out string subKey)
        {
            hiveName = "";
            subKey   = "";
            if (string.IsNullOrEmpty(regPath)) return;

            int idx = regPath.IndexOf(@":\");
            if (idx < 0)
            {
                // Fallback: intentar con ":"
                idx = regPath.IndexOf(':');
                if (idx < 0) return;
                hiveName = regPath.Substring(0, idx).ToUpperInvariant();
                subKey   = (idx + 1 < regPath.Length) ? regPath.Substring(idx + 1) : "";
            }
            else
            {
                hiveName = regPath.Substring(0, idx).ToUpperInvariant();
                subKey   = regPath.Substring(idx + 2);  // Skip :\
            }

            // Quitar barra inicial si existe
            if (subKey.StartsWith(@"\"))
                subKey = subKey.Substring(1);
        }

        private static RegistryKey GetHive(string hiveName)
        {
            switch (hiveName)
            {
                case "HKCU": return Registry.CurrentUser;
                case "HKLM": return Registry.LocalMachine;
                default:     return null;
            }
        }

        private static string EscapeJson(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            return s
                .Replace("\\", "\\\\")
                .Replace("\"", "\\\"")
                .Replace("\n", "\\n")
                .Replace("\r", "\\r")
                .Replace("\t", "\\t");
        }
    }
}
