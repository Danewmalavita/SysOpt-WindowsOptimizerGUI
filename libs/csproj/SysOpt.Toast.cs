// SysOpt.Toast.cs — Toast Notification Engine (WPF custom popup)
// Muestra notificaciones estilo toast temáticas con animación slide-in/fade-out.
// Uso: [ToastManager]::Show("Título", "Mensaje", [ToastType]::Success)
//      [ToastManager]::SetTheme(themeDict)  — sincroniza colores del tema activo
//      [ToastManager]::Enabled = $true/$false — activa/desactiva globalmente
//
// Requiere: PresentationFramework, PresentationCore, WindowsBase
// Compilar: csc /target:library /r:PresentationFramework.dll /r:PresentationCore.dll /r:WindowsBase.dll SysOpt.Toast.cs

using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Threading;

namespace SysOpt.Toast
{
    /// <summary>Tipo de notificación toast.</summary>
    public enum ToastType { Success, Info, Warning, Error }

    /// <summary>Motor de notificaciones toast temáticas.</summary>
    public static class ToastManager
    {
        private static Dictionary<string, string> _theme = new Dictionary<string, string>();
        private static bool _enabled = true;
        private static bool _debug   = false;
        private static readonly List<Window> _active = new List<Window>();

        /// <summary>Habilitar/deshabilitar notificaciones toast globalmente.</summary>
        public static bool Enabled { get { return _enabled; } set { _enabled = value; } }

        /// <summary>Si true, Write-Host muestra info de debug al mostrar/cerrar toasts.</summary>
        public static bool Debug { get { return _debug; } set { _debug = value; } }

        /// <summary>Número de toasts actualmente visibles.</summary>
        public static int ActiveCount { get { return _active.Count; } }

        /// <summary>Sincronizar colores del tema activo.</summary>
        public static void SetTheme(Dictionary<string, string> theme)
        {
            _theme = theme ?? new Dictionary<string, string>();
        }

        /// <summary>Mostrar una notificación toast.</summary>
        /// <param name="title">Título del toast.</param>
        /// <param name="message">Mensaje descriptivo (puede ser vacío).</param>
        /// <param name="type">Tipo: Success, Info, Warning, Error.</param>
        /// <param name="durationMs">Duración en ms antes del auto-cierre (default 4000).</param>
        public static void Show(string title, string message = "",
                                ToastType type = ToastType.Info, int durationMs = 4000)
        {
            if (!_enabled) return;

            // Ensure UI thread
            var disp = Application.Current != null ? Application.Current.Dispatcher : null;
            if (disp != null && !disp.CheckAccess())
            {
                disp.Invoke(() => ShowCore(title, message, type, durationMs));
            }
            else
            {
                ShowCore(title, message, type, durationMs);
            }
        }

        // ── Core rendering ────────────────────────────────────────────────
        private static void ShowCore(string title, string message, ToastType type, int durationMs)
        {
            if (_debug)
                System.Diagnostics.Debug.WriteLine(
                    string.Format("[TOAST] Show: type={0} title=\"{1}\" dur={2}ms active={3}",
                                  type, title, durationMs, _active.Count));

            var w = new Window
            {
                WindowStyle           = WindowStyle.None,
                AllowsTransparency    = true,
                Background            = Brushes.Transparent,
                Topmost               = true,
                ShowInTaskbar         = false,
                Width                 = 370,
                SizeToContent         = SizeToContent.Height,
                ResizeMode            = ResizeMode.NoResize,
                ShowActivated         = false      // no robar foco
            };

            // ── Colores del tema ──
            string accent  = AccentFor(type);
            string bgCard  = TC("BgCard",        "#161925");
            string bgDeep  = TC("BgDeep",        "#0D0F1A");
            string fgTitle = TC("TextPrimary",    "#E8EAF6");
            string fgMsg   = TC("TextSecondary",  "#9BA4C0");
            string fgMuted = TC("TextMuted",      "#6B7494");

            // ── Outer border ──
            var outer = new Border
            {
                CornerRadius    = new CornerRadius(12),
                Background      = Brush(bgCard),
                BorderBrush     = Brush(accent),
                BorderThickness = new Thickness(1),
                Margin          = new Thickness(8),
                Padding         = new Thickness(16, 14, 16, 14),
                Effect          = new DropShadowEffect
                {
                    BlurRadius  = 24,
                    ShadowDepth = 6,
                    Opacity     = 0.55,
                    Color       = Colors.Black,
                    Direction   = 270
                }
            };

            // ── Grid: icon | text | close ──
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            // Icon
            var icon = new TextBlock
            {
                Text              = IconFor(type),
                FontSize          = 22,
                VerticalAlignment = VerticalAlignment.Top,
                Margin            = new Thickness(0, 0, 14, 0)
            };
            Grid.SetColumn(icon, 0);

            // Text stack
            var sp = new StackPanel();
            sp.Children.Add(new TextBlock
            {
                Text         = title ?? "",
                FontFamily   = new FontFamily("Segoe UI"),
                FontSize     = 13,
                FontWeight   = FontWeights.SemiBold,
                Foreground   = Brush(fgTitle),
                TextWrapping = TextWrapping.Wrap
            });
            if (!string.IsNullOrWhiteSpace(message))
            {
                sp.Children.Add(new TextBlock
                {
                    Text         = message,
                    FontFamily   = new FontFamily("Segoe UI"),
                    FontSize     = 12,
                    Foreground   = Brush(fgMsg),
                    TextWrapping = TextWrapping.Wrap,
                    Margin       = new Thickness(0, 3, 0, 0)
                });
            }
            Grid.SetColumn(sp, 1);

            // Close button (borderless)
            var btn = new Button
            {
                Content                    = "\u2715",
                FontSize                   = 11,
                Width                      = 22,
                Height                     = 22,
                Background                 = Brushes.Transparent,
                BorderThickness            = new Thickness(0),
                Foreground                 = Brush(fgMuted),
                Cursor                     = Cursors.Hand,
                VerticalAlignment          = VerticalAlignment.Top,
                HorizontalContentAlignment = HorizontalAlignment.Center,
                Margin                     = new Thickness(8, 0, 0, 0),
                Focusable                  = false
            };
            var captW = w;
            btn.Click += (s, e) => DismissToast(captW);
            Grid.SetColumn(btn, 2);

            g.Children.Add(icon);
            g.Children.Add(sp);
            g.Children.Add(btn);
            outer.Child = g;
            w.Content = outer;

            // ── Posicionar ──
            w.Opacity = 0;
            w.Show();
            PositionToast(w);

            // ── Animación slide-up + fade-in ──
            double finalTop = w.Top;
            w.Top = finalTop + 50;
            w.BeginAnimation(Window.TopProperty,
                new DoubleAnimation(w.Top, finalTop, Dur(280))
                { EasingFunction = new QuarticEase { EasingMode = EasingMode.EaseOut } });
            w.BeginAnimation(Window.OpacityProperty,
                new DoubleAnimation(0, 1, Dur(250)));

            _active.Add(w);

            // ── Auto-dismiss timer ──
            var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(durationMs) };
            var captW2 = w;
            timer.Tick += (s, e) => { timer.Stop(); DismissToast(captW2); };
            timer.Start();
        }

        // ── Dismiss con fade-out ──────────────────────────────────────────
        private static void DismissToast(Window w)
        {
            if (!_active.Contains(w)) return;
            if (_debug)
                System.Diagnostics.Debug.WriteLine(
                    string.Format("[TOAST] Dismiss: remaining={0}", _active.Count - 1));

            var fade = new DoubleAnimation(1, 0, Dur(250));
            var captW = w;
            fade.Completed += (s, e) =>
            {
                _active.Remove(captW);
                try { captW.Close(); } catch { }
                RepositionAll();
            };
            w.BeginAnimation(Window.OpacityProperty, fade);
        }

        // ── Posicionamiento bottom-right, apilado ────────────────────────
        private static void PositionToast(Window w)
        {
            var wa = SystemParameters.WorkArea;
            double y = wa.Bottom - 16;
            foreach (var t in _active)
            {
                if (t != w) y -= (t.ActualHeight + 8);
            }
            w.Left = wa.Right - w.ActualWidth - 16;
            w.Top  = y - w.ActualHeight;
        }

        private static void RepositionAll()
        {
            var wa = SystemParameters.WorkArea;
            double y = wa.Bottom - 16;
            foreach (var t in _active)
            {
                double target = y - t.ActualHeight;
                t.BeginAnimation(Window.TopProperty,
                    new DoubleAnimation(t.Top, target, Dur(200)));
                y = target - 8;
            }
        }

        // ── Helpers ──────────────────────────────────────────────────────
        private static string TC(string key, string fallback)
        {
            string v;
            return (_theme != null && _theme.TryGetValue(key, out v) && !string.IsNullOrEmpty(v))
                   ? v : fallback;
        }

        private static string AccentFor(ToastType t)
        {
            switch (t)
            {
                case ToastType.Success: return TC("StatusSuccess", "#4AE896");
                case ToastType.Warning: return TC("StatusWarning", "#FFB547");
                case ToastType.Error:   return TC("StatusError",   "#FF6B84");
                default:                return TC("StatusInfo",    "#5BA3FF");
            }
        }

        private static string IconFor(ToastType t)
        {
            switch (t)
            {
                case ToastType.Success: return "\u2705";   // ✅
                case ToastType.Warning: return "\u26A0";   // ⚠
                case ToastType.Error:   return "\u274C";   // ❌
                default:                return "\u2139";   // ℹ
            }
        }

        private static SolidColorBrush Brush(string hex)
        {
            try { return new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex)); }
            catch { return Brushes.Gray; }
        }

        private static Duration Dur(int ms)
        {
            return new Duration(TimeSpan.FromMilliseconds(ms));
        }
    }
}
