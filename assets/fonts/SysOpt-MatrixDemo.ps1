# SysOpt - Matrix Rain Demo
# Carga el tema desde assets\themes\matrix.theme

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# -------------------------------------------------------
# 1. Cargar tema desde archivo
# -------------------------------------------------------
function Load-Theme {
    param([string]$ThemePath)

    $theme = @{}

    if (-not (Test-Path $ThemePath)) {
        Write-Warning "Tema no encontrado: $ThemePath - usando colores por defecto."
        return @{
            BgDeep             = "#000300"
            BgCard             = "#000800"
            BgInput            = "#000F00"
            BorderSubtle       = "#003300"
            BorderActive       = "#00FF41"
            AccentBlue         = "#00FF41"
            AccentCyan         = "#00D232"
            AccentAmber        = "#39FF14"
            AccentRed          = "#FF0000"
            AccentGreen        = "#00FF41"
            AccentPurple       = "#008F11"
            TextPrimary        = "#00FF41"
            TextSecondary      = "#008F11"
            TextMuted          = "#003B00"
            BtnPrimaryBg       = "#002200"
            BtnPrimaryFg       = "#00FF41"
            BtnPrimaryBorder   = "#00FF41"
            BtnSecondaryBg     = "#000F00"
            BtnSecondaryFg     = "#008F11"
            BtnSecondaryBorder = "#003300"
            BtnDangerBg        = "#1A0000"
            BtnDangerFg        = "#FF0000"
            StatusSuccess      = "#00FF41"
            StatusWarning      = "#39FF14"
            StatusError        = "#FF0000"
            StatusInfo         = "#00D232"
            ConsoleBg          = "#000000"
            ConsoleFg          = "#00FF41"
            Name               = "The Matrix"
        }
    }

    $lines     = Get-Content $ThemePath -Encoding UTF8
    $themeName = "Unknown"

    foreach ($line in $lines) {
        $line = $line.Trim()
        if ($line -match '^Name\s*=\s*(.+)$') {
            $themeName = $Matches[1].Trim()
        }
        if ($line -match '^([A-Za-z]+)\s*=\s*(#[0-9A-Fa-f]{6,8})$') {
            $theme[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }

    $theme["Name"] = $themeName
    return $theme
}

# Resolver ruta del tema relativa al script
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$themePath = Join-Path $scriptDir "assets\themes\matrix.theme"
$T = Load-Theme -ThemePath $themePath

# -------------------------------------------------------
# 2. XAML
# -------------------------------------------------------
[xml]$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="SysOpt"
    Width="960" Height="620"
    MinWidth="640" MinHeight="420"
    WindowStartupLocation="CenterScreen"
    Background="$($T['BgDeep'])"
    BorderThickness="0"
    WindowStyle="None"
    AllowsTransparency="False">

    <Window.Resources>

        <Style x:Key="BtnPrimary" TargetType="Button">
            <Setter Property="Background"      Value="$($T['BtnPrimaryBg'])"/>
            <Setter Property="Foreground"      Value="$($T['BtnPrimaryFg'])"/>
            <Setter Property="BorderBrush"     Value="$($T['BtnPrimaryBorder'])"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontFamily"      Value="Consolas"/>
            <Setter Property="FontSize"        Value="12"/>
            <Setter Property="Padding"         Value="18,8"/>
            <Setter Property="Cursor"          Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="3">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="$($T['BtnPrimaryBorder'])"/>
                                <Setter Property="Foreground" Value="$($T['BgDeep'])"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="BtnSecondary" TargetType="Button">
            <Setter Property="Background"      Value="$($T['BtnSecondaryBg'])"/>
            <Setter Property="Foreground"      Value="$($T['BtnSecondaryFg'])"/>
            <Setter Property="BorderBrush"     Value="$($T['BtnSecondaryBorder'])"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontFamily"      Value="Consolas"/>
            <Setter Property="FontSize"        Value="12"/>
            <Setter Property="Padding"         Value="18,8"/>
            <Setter Property="Cursor"          Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="3">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="$($T['BtnSecondaryBorder'])"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="BtnDanger" TargetType="Button">
            <Setter Property="Background"      Value="$($T['BtnDangerBg'])"/>
            <Setter Property="Foreground"      Value="$($T['BtnDangerFg'])"/>
            <Setter Property="BorderBrush"     Value="$($T['BtnDangerFg'])"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontFamily"      Value="Consolas"/>
            <Setter Property="FontSize"        Value="12"/>
            <Setter Property="Padding"         Value="18,8"/>
            <Setter Property="Cursor"          Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="3">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="$($T['BtnDangerFg'])"/>
                                <Setter Property="Foreground" Value="$($T['BgDeep'])"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

    </Window.Resources>

    <Grid>

        <Rectangle Fill="$($T['BgDeep'])"/>

        <Canvas x:Name="MatrixCanvas" ClipToBounds="True" Opacity="0.55"/>

        <Rectangle IsHitTestVisible="False">
            <Rectangle.Fill>
                <RadialGradientBrush GradientOrigin="0.5,0.5" Center="0.5,0.5" RadiusX="0.75" RadiusY="0.75">
                    <GradientStop Color="#00000000" Offset="0.3"/>
                    <GradientStop Color="#DD000300" Offset="1.0"/>
                </RadialGradientBrush>
            </Rectangle.Fill>
        </Rectangle>

        <DockPanel>

            <Border x:Name="TitleBar"
                    DockPanel.Dock="Top"
                    Background="$($T['BgCard'])"
                    BorderBrush="$($T['BorderSubtle'])"
                    BorderThickness="0,0,0,1">
                <Grid Height="36">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <StackPanel Grid.Column="0" Orientation="Horizontal"
                                VerticalAlignment="Center" Margin="12,0">
                        <TextBlock Text="[SysOpt]"
                                   FontFamily="Consolas" FontSize="13" FontWeight="Bold"
                                   Foreground="$($T['TextPrimary'])" VerticalAlignment="Center"/>
                        <TextBlock Text=" // Matrix Theme"
                                   FontFamily="Consolas" FontSize="11"
                                   Foreground="$($T['TextMuted'])"
                                   VerticalAlignment="Center" Margin="6,0,0,0"/>
                    </StackPanel>

                    <StackPanel Grid.Column="2" Orientation="Horizontal"
                                VerticalAlignment="Center" Margin="0,0,6,0">
                        <Button x:Name="BtnMinimize" Content="_"
                                Style="{StaticResource BtnSecondary}"
                                Width="32" Height="26" Margin="2,0"/>
                        <Button x:Name="BtnClose" Content="X"
                                Style="{StaticResource BtnDanger}"
                                Width="32" Height="26" Margin="2,0"/>
                    </StackPanel>
                </Grid>
            </Border>

            <Grid Margin="24">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="16"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <StackPanel Grid.Row="0">
                    <TextBlock Text="SysOpt"
                               FontFamily="Consolas" FontSize="36" FontWeight="Bold"
                               Foreground="$($T['TextPrimary'])">
                        <TextBlock.Effect>
                            <DropShadowEffect Color="$($T['AccentBlue'])" BlurRadius="18"
                                              ShadowDepth="0" Opacity="0.8"/>
                        </TextBlock.Effect>
                    </TextBlock>
                    <TextBlock Text="System Optimizer  //  Matrix Theme"
                               FontFamily="Consolas" FontSize="11"
                               Foreground="$($T['TextSecondary'])" Margin="2,2,0,0"/>
                </StackPanel>

                <Rectangle Grid.Row="1" Height="1" Margin="0,6"
                            Fill="$($T['BorderSubtle'])"/>

                <UniformGrid Grid.Row="2" Columns="4">

                    <Border Margin="0,0,6,0" CornerRadius="4" Padding="14,12"
                            Background="$($T['BgCard'])"
                            BorderBrush="$($T['BorderSubtle'])" BorderThickness="1">
                        <StackPanel>
                            <TextBlock Text="[OK] SISTEMA"
                                       FontFamily="Consolas" FontSize="10"
                                       Foreground="$($T['StatusSuccess'])"/>
                            <TextBlock Text="OPERACIONAL"
                                       FontFamily="Consolas" FontSize="14" FontWeight="Bold"
                                       Foreground="$($T['TextPrimary'])" Margin="0,4,0,0"/>
                            <TextBlock Text="Todos los modulos activos"
                                       FontFamily="Consolas" FontSize="10"
                                       Foreground="$($T['TextMuted'])" Margin="0,4,0,0"/>
                        </StackPanel>
                    </Border>

                    <Border Margin="3,0" CornerRadius="4" Padding="14,12"
                            Background="$($T['BgCard'])"
                            BorderBrush="$($T['BorderSubtle'])" BorderThickness="1">
                        <StackPanel>
                            <TextBlock Text="[CPU]"
                                       FontFamily="Consolas" FontSize="10"
                                       Foreground="$($T['AccentCyan'])"/>
                            <TextBlock Text="12%"
                                       FontFamily="Consolas" FontSize="14" FontWeight="Bold"
                                       Foreground="$($T['TextPrimary'])" Margin="0,4,0,0"/>
                            <ProgressBar Value="12" Maximum="100" Height="4" Margin="0,6,0,0"
                                         Background="$($T['BgInput'])" BorderThickness="0"
                                         Foreground="$($T['AccentCyan'])"/>
                        </StackPanel>
                    </Border>

                    <Border Margin="3,0" CornerRadius="4" Padding="14,12"
                            Background="$($T['BgCard'])"
                            BorderBrush="$($T['BorderSubtle'])" BorderThickness="1">
                        <StackPanel>
                            <TextBlock Text="[RAM]"
                                       FontFamily="Consolas" FontSize="10"
                                       Foreground="$($T['AccentAmber'])"/>
                            <TextBlock Text="58%"
                                       FontFamily="Consolas" FontSize="14" FontWeight="Bold"
                                       Foreground="$($T['TextPrimary'])" Margin="0,4,0,0"/>
                            <ProgressBar Value="58" Maximum="100" Height="4" Margin="0,6,0,0"
                                         Background="$($T['BgInput'])" BorderThickness="0"
                                         Foreground="$($T['AccentAmber'])"/>
                        </StackPanel>
                    </Border>

                    <Border Margin="6,0,0,0" CornerRadius="4" Padding="14,12"
                            Background="$($T['BgCard'])"
                            BorderBrush="$($T['BorderActive'])" BorderThickness="1">
                        <StackPanel>
                            <TextBlock Text="[UPTIME]"
                                       FontFamily="Consolas" FontSize="10"
                                       Foreground="$($T['AccentBlue'])"/>
                            <TextBlock Text="99.97%"
                                       FontFamily="Consolas" FontSize="14" FontWeight="Bold"
                                       Foreground="$($T['TextPrimary'])" Margin="0,4,0,0"/>
                            <TextBlock Text="12d 4h 33m"
                                       FontFamily="Consolas" FontSize="10"
                                       Foreground="$($T['TextMuted'])" Margin="0,4,0,0"/>
                        </StackPanel>
                    </Border>

                </UniformGrid>

                <Border Grid.Row="3" Margin="0,16,0,16" CornerRadius="4"
                        Background="$($T['ConsoleBg'])"
                        BorderBrush="$($T['BorderSubtle'])" BorderThickness="1">
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <TextBlock x:Name="ConsoleLog"
                                   FontFamily="Consolas" FontSize="12"
                                   Foreground="$($T['ConsoleFg'])"
                                   Padding="12,10"
                                   TextWrapping="Wrap"
                                   LineHeight="20"/>
                    </ScrollViewer>
                </Border>

                <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Right">
                    <Button x:Name="BtnAnalyze" Content="[ ANALIZAR ]"
                            Style="{StaticResource BtnPrimary}" Margin="0,0,8,0"/>
                    <Button x:Name="BtnClear" Content="[ LIMPIAR ]"
                            Style="{StaticResource BtnSecondary}" Margin="0,0,8,0"/>
                    <Button x:Name="BtnExit" Content="[ SALIR ]"
                            Style="{StaticResource BtnDanger}"/>
                </StackPanel>

            </Grid>
        </DockPanel>
    </Grid>
</Window>
"@

# -------------------------------------------------------
# 3. Cargar ventana
# -------------------------------------------------------
$reader   = [System.Xml.XmlNodeReader]::new($xaml)
$window   = [Windows.Markup.XamlReader]::Load($reader)
$canvas   = $window.FindName("MatrixCanvas")
$console  = $window.FindName("ConsoleLog")
$titleBar = $window.FindName("TitleBar")

$titleBar.Add_MouseLeftButtonDown({ $window.DragMove() })

# -------------------------------------------------------
# 4. Cargar fuente Matrix Code NFI desde assets\fonts\
#    Solo se usa en el digital rain - la UI sigue con Consolas
# -------------------------------------------------------
$fontPath = Join-Path $scriptDir "assets\fonts\matrix_code_nfi.ttf"
$rainFontFamily = $null

if (Test-Path $fontPath) {
    try {
        # WPF carga fuentes privadas con URI: "file:///carpeta/#Nombre Interno"
        $fontFolder = [System.IO.Path]::GetDirectoryName($fontPath)
        $folderUri  = $fontFolder.Replace("\", "/")
        $fontUri    = [Uri]::new("file:///$folderUri/")
        $rainFontFamily = [Windows.Media.FontFamily]::new($fontUri, "Matrix Code NFI")
        Write-Host "[OK] Fuente Matrix Code NFI cargada correctamente."
    } catch {
        Write-Warning "[WARN] No se pudo cargar la fuente TTF: $_"
        $rainFontFamily = $null
    }
}

if ($null -eq $rainFontFamily) {
    Write-Warning "[WARN] Fuente no encontrada en assets\fonts\matrix_code_nfi.ttf - usando Consolas."
    $rainFontFamily = [Windows.Media.FontFamily]::new("Consolas")
}

# -------------------------------------------------------
# 5. Motor Matrix
# -------------------------------------------------------
$matrixChars = "abcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()[]{}|/\<>=+-:;?~"

$matrixCfg = @{
    ColWidth    = 18
    FontSize    = 15
    TickMs      = 55
    DropLength  = 22
    SpawnChance = 0.035
    ColorHead   = "#EAFFEA"
    ColorBright = $T['AccentBlue']
    ColorMid    = $T['AccentCyan']
    ColorDim    = $T['AccentPurple']
    ColorFade   = $T['TextMuted']
}

$rng       = [System.Random]::new()
$charArray = $matrixChars.ToCharArray()
$columns   = [System.Collections.Generic.List[hashtable]]::new()

# Cache de brushes para no recrear en cada frame
$brushCache = @{}
function Get-Brush($hex) {
    if (-not $brushCache.ContainsKey($hex)) {
        $b = [Windows.Media.BrushConverter]::new().ConvertFromString($hex)
        $b.Freeze()
        $brushCache[$hex] = $b
    }
    return $brushCache[$hex]
}

# Fuente custom para el rain (Matrix Code NFI) o Consolas como fallback
$fontFamily = $rainFontFamily

function Initialize-Columns {
    $columns.Clear()
    $w       = [Math]::Max($canvas.ActualWidth, 960)
    $numCols = [Math]::Ceiling($w / $matrixCfg.ColWidth)
    for ($i = 0; $i -lt $numCols; $i++) {
        $columns.Add(@{
            X      = $i * $matrixCfg.ColWidth
            Y      = $rng.Next(-($matrixCfg.DropLength * 20), -5)
            Active = ($rng.NextDouble() -lt 0.25)
            Speed  = $rng.Next(2, 5)
        })
    }
}

function Update-Matrix {
    $canvas.Children.Clear()
    $h = $canvas.ActualHeight
    $w = $canvas.ActualWidth
    if ($h -lt 10 -or $w -lt 10) { return }

    $lineH = $matrixCfg.FontSize + 3
    $drop  = $matrixCfg.DropLength

    foreach ($col in $columns) {
        if (-not $col.Active) {
            if ($rng.NextDouble() -lt $matrixCfg.SpawnChance) {
                $col.Active = $true
                $col.Y      = -($drop * $lineH)
                $col.Speed  = $rng.Next(2, 6)
            }
            continue
        }

        $col.Y += $col.Speed

        for ($d = 0; $d -lt $drop; $d++) {
            $cy = $col.Y - ($d * $lineH)
            if ($cy -lt -$lineH -or $cy -gt $h) { continue }

            $ch = $charArray[$rng.Next($charArray.Length)]

            if     ($d -eq 0)  { $hex = $matrixCfg.ColorHead;   $op = 1.0 }
            elseif ($d -lt 2)  { $hex = $matrixCfg.ColorBright; $op = 1.0 }
            elseif ($d -lt 7)  { $hex = $matrixCfg.ColorMid;    $op = 1.0 - ($d / $drop * 0.2) }
            elseif ($d -lt 14) { $hex = $matrixCfg.ColorDim;    $op = 0.85 - ($d / $drop * 0.4) }
            else               { $hex = $matrixCfg.ColorFade;   $op = [Math]::Max(0.05, 0.35 - ($d / $drop * 0.35)) }

            $tb            = [Windows.Controls.TextBlock]::new()
            $tb.Text       = $ch
            $tb.FontFamily = $fontFamily
            $tb.FontSize   = $matrixCfg.FontSize
            $tb.Foreground = Get-Brush $hex
            $tb.Opacity    = $op
            [Windows.Controls.Canvas]::SetLeft($tb, $col.X)
            [Windows.Controls.Canvas]::SetTop($tb,  $cy)
            $canvas.Children.Add($tb) | Out-Null
        }

        if (($col.Y - ($drop * $lineH)) -gt $h) {
            $col.Active = $false
        }
    }
}

# -------------------------------------------------------
# 5. Log de consola
# -------------------------------------------------------
$logLines    = [System.Collections.Generic.List[string]]::new()
$logMessages = @(
    "[INIT]   Cargando tema: $($T['Name'])..."
    "[OK]     Tema aplicado correctamente."
    "[SCAN]   Analizando servicios del sistema..."
    "[INFO]   CPU: 12%  |  RAM: 58%  |  DISK: 34%"
    "[OK]     Sistema operacional. Sin errores criticos."
    "[MATRIX] Iniciando protocolo de optimizacion..."
    "[WARN]   3 procesos con alto consumo detectados."
    "[INFO]   Liberando memoria cache..."
    "[OK]     512 MB liberados."
    "[MATRIX] La realidad es una ilusion. Optimizando..."
)
$script:logIndex = 0

function Add-LogLine {
    if ($script:logIndex -lt $logMessages.Count) {
        $logLines.Add($logMessages[$script:logIndex])
        $script:logIndex++
    } else {
        $ts = Get-Date -Format "HH:mm:ss"
        $logLines.Add("[$ts]  Monitoreo continuo activo...")
    }
    while ($logLines.Count -gt 12) { $logLines.RemoveAt(0) }
    $console.Text = ($logLines -join "`n")
}

# -------------------------------------------------------
# 6. Timers
# -------------------------------------------------------
$timerMatrix          = [System.Windows.Threading.DispatcherTimer]::new()
$timerMatrix.Interval = [TimeSpan]::FromMilliseconds($matrixCfg.TickMs)
$timerMatrix.Add_Tick({ Update-Matrix })

$timerLog             = [System.Windows.Threading.DispatcherTimer]::new()
$timerLog.Interval    = [TimeSpan]::FromMilliseconds(900)
$timerLog.Add_Tick({ Add-LogLine })

# -------------------------------------------------------
# 7. Eventos botones
# -------------------------------------------------------
$window.FindName("BtnMinimize").Add_Click({ $window.WindowState = "Minimized" })

$window.FindName("BtnClose").Add_Click({
    $timerMatrix.Stop()
    $timerLog.Stop()
    $window.Close()
})

$window.FindName("BtnExit").Add_Click({
    $timerMatrix.Stop()
    $timerLog.Stop()
    $window.Close()
})

$window.FindName("BtnClear").Add_Click({
    $logLines.Clear()
    $script:logIndex = 0
    $console.Text = ""
    $logLines.Add("[OK]   Log limpiado.")
    $console.Text = $logLines -join "`n"
})

$window.FindName("BtnAnalyze").Add_Click({
    $logLines.Add("[SCAN] Iniciando analisis manual...")
    $logLines.Add("[INFO] Escaneando registro del sistema...")
    $console.Text = $logLines -join "`n"
})

# -------------------------------------------------------
# 8. Arranque
# -------------------------------------------------------
$window.Add_Loaded({
    Initialize-Columns
    $timerMatrix.Start()
    $timerLog.Start()
})

$window.Add_SizeChanged({ Initialize-Columns })

$window.Add_Closed({
    $timerMatrix.Stop()
    $timerLog.Stop()
})

$window.ShowDialog() | Out-Null