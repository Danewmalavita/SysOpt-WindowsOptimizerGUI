// ─────────────────────────────────────────────────────────────────────────────
// SysOpt.ThemeEngine — Parsing y metadatos de archivos .theme
// Compilar:  csc /target:library /out:SysOpt.ThemeEngine.dll SysOpt.ThemeEngine.cs
// ─────────────────────────────────────────────────────────────────────────────
using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Collections.Generic;
using System.IO;

/// <summary>
/// Motor de temas para SysOpt.  Lee ficheros .theme (formato INI con
/// secciones [meta] y [colors]) y devuelve diccionarios clave→valor.
/// </summary>
public static class ThemeEngine
{
    // ── Parsear sección [colors] ───────────────────────────────────────────
    /// <summary>Devuelve un Dictionary&lt;string,string&gt; con claves de color
    /// (p. ej. BgDeep → #0D0F1A).</summary>
    public static Dictionary<string, string> ParseThemeFile(string path)
    {
        if (string.IsNullOrEmpty(path))
            throw new ArgumentNullException("path");
        if (!File.Exists(path))
            throw new FileNotFoundException("Theme file not found: " + path);

        var colors = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        string section = "";

        foreach (var rawLine in File.ReadAllLines(path))
        {
            var line = rawLine.Trim();
            if (line.Length == 0 || line[0] == '#') continue;

            if (line[0] == '[' && line[line.Length - 1] == ']')
            {
                section = line.Substring(1, line.Length - 2).ToLowerInvariant();
                continue;
            }
            if (section != "colors") continue;

            int eq = line.IndexOf('=');
            if (eq <= 0) continue;

            string key = line.Substring(0, eq).Trim();
            string val = line.Substring(eq + 1).Trim();

            // Quitar comentarios inline  (#...)
            int hash = val.IndexOf('#', 1);   // ignora el '#' del color
            // Solo cortar si el '#' NO está precedido de nada alfanumérico
            // (es decir, es un comentario, no parte del hex color).
            // Heurística: si el primer carácter es '#' y hash > 0, verificar.
            if (val.Length > 0 && val[0] == '#' && hash > 0)
            {
                // El valor es un color hex; el segundo '#' sería comentario
                // solo si hay espacio antes
                int sp = val.IndexOf(' ', 1);
                if (sp > 0 && sp < hash)
                    val = val.Substring(0, sp).Trim();
            }

            colors[key] = val;
        }
        return colors;
    }

    // ── Parsear sección [meta] ─────────────────────────────────────────────
    /// <summary>Devuelve metadatos del tema (Name, Author, Version).</summary>
    public static Dictionary<string, string> GetThemeMeta(string path)
    {
        if (string.IsNullOrEmpty(path))
            throw new ArgumentNullException("path");
        if (!File.Exists(path))
            throw new FileNotFoundException("Theme file not found: " + path);

        var meta = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        string section = "";

        foreach (var rawLine in File.ReadAllLines(path))
        {
            var line = rawLine.Trim();
            if (line.Length == 0 || line[0] == '#') continue;

            if (line[0] == '[' && line[line.Length - 1] == ']')
            {
                section = line.Substring(1, line.Length - 2).ToLowerInvariant();
                continue;
            }
            if (section != "meta") continue;

            int eq = line.IndexOf('=');
            if (eq <= 0) continue;

            meta[line.Substring(0, eq).Trim()] = line.Substring(eq + 1).Trim();
        }
        return meta;
    }

    // ── Listar temas disponibles ───────────────────────────────────────────
    /// <summary>Devuelve nombres de archivo sin extensión de todos los .theme
    /// en la carpeta indicada.</summary>
    public static string[] ListThemes(string themesFolder)
    {
        if (!Directory.Exists(themesFolder)) return new string[0];
        var files = Directory.GetFiles(themesFolder, "*.theme");
        var names = new string[files.Length];
        for (int i = 0; i < files.Length; i++)
            names[i] = Path.GetFileNameWithoutExtension(files[i]);
        Array.Sort(names, StringComparer.OrdinalIgnoreCase);
        return names;
    }
}


// ═══════════════════════════════════════════════════════════════════════════════
// ThemeApplier — WPF visual tree manipulation for theme application
// ═══════════════════════════════════════════════════════════════════════════════
public static class ThemeApplier
{
    /// <summary>
    /// Recursively get ALL visual children of a DependencyObject (iterative for performance).
    /// Replaces PS1 Get-VisualChildren (~9 lines, used in 8+ places).
    /// </summary>
    public static System.Collections.Generic.List<DependencyObject> GetVisualChildren(DependencyObject parent)
    {
        var result = new System.Collections.Generic.List<DependencyObject>();
        var stack = new System.Collections.Generic.Stack<DependencyObject>();
        stack.Push(parent);
        while (stack.Count > 0)
        {
            var current = stack.Pop();
            int count = VisualTreeHelper.GetChildrenCount(current);
            for (int i = 0; i < count; i++)
            {
                var child = VisualTreeHelper.GetChild(current, i);
                result.Add(child);
                stack.Push(child);
            }
        }
        return result;
    }

    /// <summary>
    /// Darken a hex color by a factor (0.0 = black, 1.0 = original).
    /// Replaces PS1 local:DarkAccent function.
    /// </summary>
    public static string DarkenColor(string hex, double factor)
    {
        try
        {
            if (string.IsNullOrEmpty(hex)) return hex;
            hex = hex.TrimStart('#');
            if (hex.Length < 6) return "#" + hex;
            int r = (int)(Convert.ToInt32(hex.Substring(0, 2), 16) * factor);
            int g = (int)(Convert.ToInt32(hex.Substring(2, 2), 16) * factor);
            int b = (int)(Convert.ToInt32(hex.Substring(4, 2), 16) * factor);
            r = Math.Max(0, Math.Min(255, r));
            g = Math.Max(0, Math.Min(255, g));
            b = Math.Max(0, Math.Min(255, b));
            return string.Format("#{0:X2}{1:X2}{2:X2}", r, g, b);
        }
        catch { return hex; }
    }

    /// <summary>
    /// Compute dynamic status colors from theme dictionary.
    /// Replaces the color computation part of Update-DynamicThemeValues (~30 lines).
    /// Returns a Dictionary with StatusRunningBg/Fg, StatusDoneBg/Fg, etc.
    /// </summary>
    public static Dictionary<string, string> BuildStatusColors(Dictionary<string, string> tc)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (tc == null || tc.Count == 0) return result;

        string blue   = tc.ContainsKey("AccentBlue")   ? tc["AccentBlue"]   : "#5BA3FF";
        string green  = tc.ContainsKey("AccentGreen")  ? tc["AccentGreen"]  : "#4AE896";
        string red    = tc.ContainsKey("AccentRed")    ? tc["AccentRed"]    : "#FF6B84";
        string amber  = tc.ContainsKey("AccentAmber")  ? tc["AccentAmber"]  : "#FFB547";

        result["StatusRunningBg"] = tc.ContainsKey("BgStatusInfo") ? tc["BgStatusInfo"] : DarkenColor(blue,  0.18);
        result["StatusRunningFg"] = tc.ContainsKey("FgStatusInfo") ? tc["FgStatusInfo"] : blue;
        result["StatusDoneBg"]    = tc.ContainsKey("BgStatusOk")   ? tc["BgStatusOk"]   : DarkenColor(green, 0.18);
        result["StatusDoneFg"]    = tc.ContainsKey("FgStatusOk")   ? tc["FgStatusOk"]   : green;
        result["StatusErrorBg"]   = tc.ContainsKey("BgStatusErr")  ? tc["BgStatusErr"]  : DarkenColor(red,   0.22);
        result["StatusErrorFg"]   = tc.ContainsKey("FgStatusErr")  ? tc["FgStatusErr"]  : red;
        result["StatusCancelBg"]  = tc.ContainsKey("BgStatusWarn") ? tc["BgStatusWarn"] : DarkenColor(amber, 0.22);
        result["StatusCancelFg"]  = tc.ContainsKey("FgStatusWarn") ? tc["FgStatusWarn"] : amber;

        // Icon backgrounds = same as status backgrounds
        result["IconRunningBg"] = result["StatusRunningBg"];
        result["IconDoneBg"]    = result["StatusDoneBg"];
        result["IconErrorBg"]   = result["StatusErrorBg"];
        result["IconCancelBg"]  = result["StatusCancelBg"];

        return result;
    }

    /// <summary>
    /// Apply dark theme to a ComboBox (closed state + DropDownOpened handler).
    /// Replaces PS1 Apply-ComboBoxDarkTheme (~79 lines).
    /// </summary>
    public static void ApplyComboBoxTheme(ComboBox cb, string bgHex, string borderHex, string fgHex, string hoverHex)
    {
        if (cb == null) return;
        var bc = new BrushConverter();
        Brush darkBg, darkBorder, lightFg;
        try
        {
            darkBg     = (Brush)bc.ConvertFromString(bgHex);
            darkBorder = (Brush)bc.ConvertFromString(borderHex);
            lightFg    = (Brush)bc.ConvertFromString(fgHex);
        }
        catch { return; }

        cb.ApplyTemplate();
        cb.Foreground = lightFg;

        // Theme closed ComboBox (ToggleButton and Borders)
        foreach (var child in GetVisualChildren(cb))
        {
            var tb = child as ToggleButton;
            if (tb != null)
            {
                tb.Background  = darkBg;
                tb.BorderBrush = darkBorder;
                tb.Foreground  = lightFg;
                tb.ApplyTemplate();
                foreach (var inner in GetVisualChildren(tb))
                {
                    var bd = inner as Border;
                    if (bd != null)
                    {
                        bd.Background  = darkBg;
                        bd.BorderBrush = darkBorder;
                    }
                }
            }
            else
            {
                var bdr = child as Border;
                if (bdr != null)
                {
                    bdr.Background  = darkBg;
                    bdr.BorderBrush = darkBorder;
                }
            }
        }

        // Theme dropdown popup when it opens
        cb.DropDownOpened += (sender, e) =>
        {
            try
            {
                var combo = sender as ComboBox;
                if (combo == null) return;
                var bc2 = new BrushConverter();
                var popBg     = (Brush)bc2.ConvertFromString(bgHex);
                var popBorder = (Brush)bc2.ConvertFromString(borderHex);
                var popFg     = (Brush)bc2.ConvertFromString(fgHex);

                var popup = combo.Template.FindName("PART_Popup", combo) as System.Windows.Controls.Primitives.Popup;
                if (popup != null && popup.Child != null)
                {
                    var chrome = popup.Child;
                    var chromeBorder = chrome as Border;
                    if (chromeBorder != null)
                    {
                        chromeBorder.Background  = popBg;
                        chromeBorder.BorderBrush = popBorder;
                    }
                    foreach (var px in GetVisualChildren(chrome))
                    {
                        var pbd = px as Border; if (pbd != null) { pbd.Background = popBg; pbd.BorderBrush = popBorder; }
                        var sv = px as ScrollViewer; if (sv != null) { sv.Background = popBg; }
                    }
                }
                foreach (var item in combo.Items)
                {
                    var container = combo.ItemContainerGenerator.ContainerFromItem(item) as ComboBoxItem;
                    if (container != null)
                    {
                        container.Background  = popBg;
                        container.Foreground  = popFg;
                        container.BorderBrush = Brushes.Transparent;
                    }
                }
            }
            catch { }
        };
    }

    /// <summary>
    /// Replace gradient stop colors in a visual tree based on a color map.
    /// Replaces PASS 2 of Apply-ThemeWithProgress (~50 lines).
    /// colorMap: Dictionary of old hex "#RRGGBB" → new Color
    /// </summary>
    public static void ReplaceGradientColors(DependencyObject root, Dictionary<string, Color> colorMap)
    {
        if (colorMap == null || colorMap.Count == 0) return;
        var allElements = GetVisualChildren(root);
        allElements.Insert(0, root);

        string[] props = { "Background", "Foreground", "BorderBrush", "Fill" };

        foreach (var el in allElements)
        {
            foreach (string propName in props)
            {
                try
                {
                    var pi = el.GetType().GetProperty(propName);
                    if (pi == null) continue;
                    var brush = pi.GetValue(el) as GradientBrush;
                    if (brush == null) continue;

                    bool changed = false;
                    var newGrad = brush.Clone();
                    foreach (GradientStop gs in newGrad.GradientStops)
                    {
                        string oldHex = string.Format("#{0:X2}{1:X2}{2:X2}", gs.Color.R, gs.Color.G, gs.Color.B);
                        Color newColor;
                        if (colorMap.TryGetValue(oldHex, out newColor))
                        {
                            gs.Color = newColor;
                            changed = true;
                        }
                    }
                    if (changed) pi.SetValue(el, newGrad);
                }
                catch { }
            }
        }
    }
}
