# SysOpt - Pip-Boy 3000 Scanlines Demo
# Carga el tema desde assets\themes\pipboy.theme
# Efecto: scanlines CRT + phosphor glow + static noise + texto typewriter

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# -------------------------------------------------------
# 1. Cargar tema desde archivo
# -------------------------------------------------------
function Load-Theme {
    param([string]$ThemePath)

    $fallback = @{
        BgDeep             = "#050D05"
        BgCard             = "#0A1A0A"
        BgInput            = "#0D220D"
        BorderSubtle       = "#1A3A1A"
        BorderActive       = "#6BFF6B"
        BorderHover        = "#2A5A2A"
        AccentBlue         = "#6BFF6B"
        AccentCyan         = "#A8FF80"
        AccentAmber        = "#C8FF40"
        AccentRed          = "#FF6B40"
        AccentGreen        = "#6BFF6B"
        AccentPurple       = "#80FF80"
        TextPrimary        = "#B8FFB8"
        TextSecondary      = "#78C878"
        TextMuted          = "#4A884A"
        ProgressStart      = "#3AD83A"
        ProgressEnd        = "#A8FF80"
        BtnPrimaryBg       = "#0D4A0D"
        BtnPrimaryFg       = "#B8FFB8"
        BtnPrimaryBorder   = "#6BFF6B"
        BtnSecondaryBg     = "#0A1A0A"
        BtnSecondaryFg     = "#78C878"
        BtnSecondaryBorder = "#1A3A1A"
        BtnDangerBg        = "#2A1005"
        BtnDangerFg        = "#FF6B40"
        BtnAmberBg         = "#1E2800"
        BtnAmberFg         = "#C8FF40"
        StatusSuccess      = "#6BFF6B"
        StatusWarning      = "#C8FF40"
        StatusError        = "#FF6B40"
        StatusInfo         = "#A8FF80"
        ConsoleBg          = "#020802"
        ConsoleFg          = "#6BFF6B"
        Name               = "Pip-Boy 3000"
    }

    if (-not (Test-Path $ThemePath)) {
        Write-Warning "Tema no encontrado: $ThemePath - usando fallback."
        return $fallback
    }

    $theme = @{}
    $lines = Get-Content $ThemePath -Encoding UTF8
    $themeName = "Pip-Boy 3000"

    foreach ($line in $lines) {
        $line = $line.Trim()
        if ($line -match '^Name\s*=\s*(.+)$')                       { $themeName = $Matches[1].Trim() }
        if ($line -match '^([A-Za-z]+)\s*=\s*(#[0-9A-Fa-f]{6,8})$') { $theme[$Matches[1].Trim()] = $Matches[2].Trim() }
    }

    $theme["Name"] = $themeName

    # Rellenar claves faltantes con fallback
    foreach ($k in $fallback.Keys) {
        if (-not $theme.ContainsKey($k)) { $theme[$k] = $fallback[$k] }
    }

    return $theme
}

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$themePath = Join-Path $scriptDir "assets\themes\pipboy.theme"
$T = Load-Theme -ThemePath $themePath

# -------------------------------------------------------
# 2. XAML - Ventana Pip-Boy con scanlines via DrawingBrush
# -------------------------------------------------------
[xml]$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="SysOpt - Pip-Boy 3000"
    Width="980" Height="660"
    MinWidth="700" MinHeight="480"
    WindowStartupLocation="CenterScreen"
    Background="$($T['BgDeep'])"
    WindowStyle="None"
    AllowsTransparency="False"
    BorderThickness="0">

    <Window.Resources>

        <!-- Scanlines via DrawingBrush: lineas horizontales semitransparentes -->
        <DrawingBrush x:Key="ScanlinesBrush"
                      TileMode="Tile"
                      ViewportUnits="Absolute"
                      Viewport="0,0,1,4">
            <DrawingBrush.Drawing>
                <DrawingGroup>
                    <!-- Linea oscura cada 4px = efecto CRT clasico -->
                    <GeometryDrawing Brush="#22000000">
                        <GeometryDrawing.Geometry>
                            <RectangleGeometry Rect="0,0,1,2"/>
                        </GeometryDrawing.Geometry>
                    </GeometryDrawing>
                    <!-- Linea levemente mas brillante: reflejo fosforo -->
                    <GeometryDrawing Brush="#0A6BFF6B">
                        <GeometryDrawing.Geometry>
                            <RectangleGeometry Rect="0,2,1,1"/>
                        </GeometryDrawing.Geometry>
                    </GeometryDrawing>
                </DrawingGroup>
            </DrawingBrush.Drawing>
        </DrawingBrush>

        <!-- Glow verde fosforescente para textos importantes -->
        <Style x:Key="GlowText" TargetType="TextBlock">
            <Setter Property="FontFamily"  Value="Courier New"/>
            <Setter Property="Foreground"  Value="$($T['TextPrimary'])"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Foreground" Value="$($T['AccentBlue'])"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Boton primario estilo Pip-Boy -->
        <Style x:Key="BtnPrimary" TargetType="Button">
            <Setter Property="Background"      Value="$($T['BtnPrimaryBg'])"/>
            <Setter Property="Foreground"      Value="$($T['BtnPrimaryFg'])"/>
            <Setter Property="BorderBrush"     Value="$($T['BtnPrimaryBorder'])"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontFamily"      Value="Courier New"/>
            <Setter Property="FontSize"        Value="12"/>
            <Setter Property="Padding"         Value="16,7"/>
            <Setter Property="Cursor"          Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="2">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="$($T['BtnPrimaryBorder'])"/>
                                <Setter Property="Foreground" Value="$($T['BgDeep'])"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="$($T['AccentCyan'])"/>
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
            <Setter Property="FontFamily"      Value="Courier New"/>
            <Setter Property="FontSize"        Value="12"/>
            <Setter Property="Padding"         Value="16,7"/>
            <Setter Property="Cursor"          Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="2">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="$($T['BtnSecondaryBorder'])"/>
                                <Setter Property="Foreground" Value="$($T['TextPrimary'])"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="BtnAmber" TargetType="Button">
            <Setter Property="Background"      Value="$($T['BtnAmberBg'])"/>
            <Setter Property="Foreground"      Value="$($T['BtnAmberFg'])"/>
            <Setter Property="BorderBrush"     Value="$($T['BtnAmberFg'])"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontFamily"      Value="Courier New"/>
            <Setter Property="FontSize"        Value="12"/>
            <Setter Property="Padding"         Value="16,7"/>
            <Setter Property="Cursor"          Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="2">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="$($T['BtnAmberFg'])"/>
                                <Setter Property="Foreground" Value="$($T['BgDeep'])"/>
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
            <Setter Property="FontFamily"      Value="Courier New"/>
            <Setter Property="FontSize"        Value="12"/>
            <Setter Property="Padding"         Value="16,7"/>
            <Setter Property="Cursor"          Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="2">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="$($T['BtnDangerFg'])"/>
                                <Setter Property="Foreground" Value="$($T['BgDeep'])"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Separador estilo terminal -->
        <Style x:Key="Separator" TargetType="TextBlock">
            <Setter Property="FontFamily"  Value="Courier New"/>
            <Setter Property="FontSize"    Value="11"/>
            <Setter Property="Foreground"  Value="$($T['BorderSubtle'])"/>
            <Setter Property="Margin"      Value="0,4,0,4"/>
        </Style>

        <!-- Card Pip-Boy -->
        <Style x:Key="PipCard" TargetType="Border">
            <Setter Property="Background"     Value="$($T['BgCard'])"/>
            <Setter Property="BorderBrush"    Value="$($T['BorderSubtle'])"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius"   Value="2"/>
            <Setter Property="Padding"        Value="14,10"/>
        </Style>

    </Window.Resources>

    <Grid>

        <!-- CAPA 0: Fondo base solido -->
        <Rectangle Fill="$($T['BgDeep'])"/>

        <!-- CAPA 1: Scanlines CRT sobre todo -->
        <Rectangle Fill="{StaticResource ScanlinesBrush}"
                   IsHitTestVisible="False" Opacity="1"/>

        <!-- CAPA 2: Vineta CRT - bordes curvados oscuros -->
        <Rectangle IsHitTestVisible="False">
            <Rectangle.Fill>
                <RadialGradientBrush GradientOrigin="0.5,0.5" Center="0.5,0.5"
                                     RadiusX="0.85" RadiusY="0.85">
                    <GradientStop Color="#00000000" Offset="0.55"/>
                    <GradientStop Color="#AA000000" Offset="0.85"/>
                    <GradientStop Color="#EE000000" Offset="1.0"/>
                </RadialGradientBrush>
            </Rectangle.Fill>
        </Rectangle>

        <!-- CAPA 3: Flicker canvas (ruido estatico suave) -->
        <Canvas x:Name="NoiseCanvas" IsHitTestVisible="False" Opacity="0.04"/>

        <!-- CAPA 4: UI principal -->
        <DockPanel>

            <!-- Barra de titulo draggable estilo terminal -->
            <Border x:Name="TitleBar"
                    DockPanel.Dock="Top"
                    Background="$($T['BgCard'])"
                    BorderBrush="$($T['BorderActive'])"
                    BorderThickness="0,0,0,2">
                <Grid Height="38">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <!-- Logo -->
                    <StackPanel Grid.Column="0" Orientation="Horizontal"
                                VerticalAlignment="Center" Margin="14,0">
                        <TextBlock Text="[" Foreground="$($T['TextMuted'])"
                                   FontFamily="Courier New" FontSize="14" FontWeight="Bold"
                                   VerticalAlignment="Center"/>
                        <TextBlock Text="PIP-BOY 3000" Foreground="$($T['AccentBlue'])"
                                   FontFamily="Courier New" FontSize="14" FontWeight="Bold"
                                   VerticalAlignment="Center">
                            <TextBlock.Effect>
                                <DropShadowEffect Color="$($T['AccentBlue'])" BlurRadius="8"
                                                  ShadowDepth="0" Opacity="0.9"/>
                            </TextBlock.Effect>
                        </TextBlock>
                        <TextBlock Text="]" Foreground="$($T['TextMuted'])"
                                   FontFamily="Courier New" FontSize="14" FontWeight="Bold"
                                   VerticalAlignment="Center"/>
                        <TextBlock Text="  ROBCO INDUSTRIES(TM) UNIFIED OPERATING SYSTEM"
                                   Foreground="$($T['TextMuted'])"
                                   FontFamily="Courier New" FontSize="10"
                                   VerticalAlignment="Center" Margin="10,0,0,0"/>
                    </StackPanel>

                    <!-- Hora + botones -->
                    <StackPanel Grid.Column="2" Orientation="Horizontal"
                                VerticalAlignment="Center" Margin="0,0,8,0">
                        <TextBlock x:Name="ClockDisplay"
                                   FontFamily="Courier New" FontSize="12"
                                   Foreground="$($T['TextSecondary'])"
                                   VerticalAlignment="Center" Margin="0,0,12,0"/>
                        <Button x:Name="BtnMinimize" Content="_"
                                Style="{StaticResource BtnSecondary}"
                                Width="30" Height="26" Margin="2,0"/>
                        <Button x:Name="BtnClose" Content="X"
                                Style="{StaticResource BtnDanger}"
                                Width="30" Height="26" Margin="2,0"/>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- Tabs estilo Pip-Boy: STAT / INV / DATA / MAP / RADIO -->
            <Border DockPanel.Dock="Top"
                    Background="$($T['BgCardDark'])"
                    BorderBrush="$($T['BorderSubtle'])"
                    BorderThickness="0,0,0,1">
                <StackPanel Orientation="Horizontal" Height="32">
                    <Border x:Name="TabStat" Padding="20,0" Background="$($T['BgCard'])"
                            BorderBrush="$($T['BorderActive'])" BorderThickness="0,0,0,2"
                            Cursor="Hand">
                        <TextBlock Text="STAT" FontFamily="Courier New" FontSize="12" FontWeight="Bold"
                                   Foreground="$($T['AccentBlue'])" VerticalAlignment="Center">
                            <TextBlock.Effect>
                                <DropShadowEffect Color="$($T['AccentBlue'])" BlurRadius="6" ShadowDepth="0" Opacity="0.7"/>
                            </TextBlock.Effect>
                        </TextBlock>
                    </Border>
                    <Border Padding="20,0" Background="$($T['BgCardDark'])"
                            BorderBrush="$($T['BorderSubtle'])" BorderThickness="0,0,0,1"
                            Cursor="Hand">
                        <TextBlock Text="INV" FontFamily="Courier New" FontSize="12"
                                   Foreground="$($T['TextMuted'])" VerticalAlignment="Center"/>
                    </Border>
                    <Border Padding="20,0" Background="$($T['BgCardDark'])"
                            BorderBrush="$($T['BorderSubtle'])" BorderThickness="0,0,0,1"
                            Cursor="Hand">
                        <TextBlock Text="DATA" FontFamily="Courier New" FontSize="12"
                                   Foreground="$($T['TextMuted'])" VerticalAlignment="Center"/>
                    </Border>
                    <Border Padding="20,0" Background="$($T['BgCardDark'])"
                            BorderBrush="$($T['BorderSubtle'])" BorderThickness="0,0,0,1"
                            Cursor="Hand">
                        <TextBlock Text="MAP" FontFamily="Courier New" FontSize="12"
                                   Foreground="$($T['TextMuted'])" VerticalAlignment="Center"/>
                    </Border>
                    <Border Padding="20,0" Background="$($T['BgCardDark'])"
                            BorderBrush="$($T['BorderSubtle'])" BorderThickness="0,0,0,1"
                            Cursor="Hand">
                        <TextBlock Text="RADIO" FontFamily="Courier New" FontSize="12"
                                   Foreground="$($T['TextMuted'])" VerticalAlignment="Center"/>
                    </Border>
                </StackPanel>
            </Border>

            <!-- Cuerpo -->
            <Grid Margin="20,16,20,16">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="220"/>
                    <ColumnDefinition Width="16"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <!-- Panel izquierdo: S.P.E.C.I.A.L stats -->
                <StackPanel Grid.Column="0">

                    <TextBlock Text="S.P.E.C.I.A.L." FontFamily="Courier New"
                               FontSize="13" FontWeight="Bold"
                               Foreground="$($T['AccentBlue'])">
                        <TextBlock.Effect>
                            <DropShadowEffect Color="$($T['AccentBlue'])" BlurRadius="10" ShadowDepth="0" Opacity="0.8"/>
                        </TextBlock.Effect>
                    </TextBlock>

                    <TextBlock Text="----------------" Style="{StaticResource Separator}"/>

                    <!-- Stat row helper: repetimos el patron -->
                    <Grid Margin="0,3,0,3">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="90"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="24"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="STR" FontFamily="Courier New" FontSize="11"
                                   Foreground="$($T['TextSecondary'])" VerticalAlignment="Center"/>
                        <ProgressBar Grid.Column="1" Value="8" Maximum="10" Height="6"
                                     Background="$($T['BgInput'])" BorderThickness="0"
                                     Foreground="$($T['AccentBlue'])" VerticalAlignment="Center"/>
                        <TextBlock Grid.Column="2" Text="8" FontFamily="Courier New" FontSize="11"
                                   Foreground="$($T['TextPrimary'])" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                    </Grid>

                    <Grid Margin="0,3,0,3">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="90"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="24"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="PER" FontFamily="Courier New" FontSize="11"
                                   Foreground="$($T['TextSecondary'])" VerticalAlignment="Center"/>
                        <ProgressBar Grid.Column="1" Value="6" Maximum="10" Height="6"
                                     Background="$($T['BgInput'])" BorderThickness="0"
                                     Foreground="$($T['AccentBlue'])" VerticalAlignment="Center"/>
                        <TextBlock Grid.Column="2" Text="6" FontFamily="Courier New" FontSize="11"
                                   Foreground="$($T['TextPrimary'])" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                    </Grid>

                    <Grid Margin="0,3,0,3">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="90"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="24"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="END" FontFamily="Courier New" FontSize="11"
                                   Foreground="$($T['TextSecondary'])" VerticalAlignment="Center"/>
                        <ProgressBar Grid.Column="1" Value="7" Maximum="10" Height="6"
                                     Background="$($T['BgInput'])" BorderThickness="0"
                                     Foreground="$($T['AccentBlue'])" VerticalAlignment="Center"/>
                        <TextBlock Grid.Column="2" Text="7" FontFamily="Courier New" FontSize="11"
                                   Foreground="$($T['TextPrimary'])" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                    </Grid>

                    <Grid Margin="0,3,0,3">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="90"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="24"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="CHA" FontFamily="Courier New" FontSize="11"
                                   Foreground="$($T['TextSecondary'])" VerticalAlignment="Center"/>
                        <ProgressBar Grid.Column="1" Value="5" Maximum="10" Height="6"
                                     Background="$($T['BgInput'])" BorderThickness="0"
                                     Foreground="$($T['AccentBlue'])" VerticalAlignment="Center"/>
                        <TextBlock Grid.Column="2" Text="5" FontFamily="Courier New" FontSize="11"
                                   Foreground="$($T['TextPrimary'])" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                    </Grid>

                    <Grid Margin="0,3,0,3">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="90"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="24"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="INT" FontFamily="Courier New" FontSize="11"
                                   Foreground="$($T['TextSecondary'])" VerticalAlignment="Center"/>
                        <ProgressBar Grid.Column="1" Value="9" Maximum="10" Height="6"
                                     Background="$($T['BgInput'])" BorderThickness="0"
                                     Foreground="$($T['AccentCyan'])" VerticalAlignment="Center"/>
                        <TextBlock Grid.Column="2" Text="9" FontFamily="Courier New" FontSize="11"
                                   Foreground="$($T['AccentCyan'])" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                    </Grid>

                    <Grid Margin="0,3,0,3">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="90"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="24"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="AGI" FontFamily="Courier New" FontSize="11"
                                   Foreground="$($T['TextSecondary'])" VerticalAlignment="Center"/>
                        <ProgressBar Grid.Column="1" Value="7" Maximum="10" Height="6"
                                     Background="$($T['BgInput'])" BorderThickness="0"
                                     Foreground="$($T['AccentBlue'])" VerticalAlignment="Center"/>
                        <TextBlock Grid.Column="2" Text="7" FontFamily="Courier New" FontSize="11"
                                   Foreground="$($T['TextPrimary'])" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                    </Grid>

                    <Grid Margin="0,3,0,3">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="90"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="24"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="LCK" FontFamily="Courier New" FontSize="11"
                                   Foreground="$($T['TextSecondary'])" VerticalAlignment="Center"/>
                        <ProgressBar Grid.Column="1" Value="4" Maximum="10" Height="6"
                                     Background="$($T['BgInput'])" BorderThickness="0"
                                     Foreground="$($T['AccentAmber'])" VerticalAlignment="Center"/>
                        <TextBlock Grid.Column="2" Text="4" FontFamily="Courier New" FontSize="11"
                                   Foreground="$($T['AccentAmber'])" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                    </Grid>

                    <TextBlock Text="----------------" Style="{StaticResource Separator}" Margin="0,10,0,4"/>

                    <!-- HP + RAD -->
                    <TextBlock Text="STATUS" FontFamily="Courier New" FontSize="11"
                               FontWeight="Bold" Foreground="$($T['TextSecondary'])" Margin="0,0,0,6"/>

                    <Grid Margin="0,2,0,2">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="90"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="36"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="HP" FontFamily="Courier New" FontSize="11"
                                   Foreground="$($T['StatusSuccess'])" VerticalAlignment="Center"/>
                        <ProgressBar Grid.Column="1" Value="87" Maximum="100" Height="8"
                                     Background="$($T['BgInput'])" BorderThickness="0"
                                     Foreground="$($T['StatusSuccess'])" VerticalAlignment="Center"/>
                        <TextBlock Grid.Column="2" Text="87/100" FontFamily="Courier New" FontSize="9"
                                   Foreground="$($T['TextMuted'])" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                    </Grid>

                    <Grid Margin="0,4,0,2">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="90"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="36"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="RAD" FontFamily="Courier New" FontSize="11"
                                   Foreground="$($T['AccentAmber'])" VerticalAlignment="Center"/>
                        <ProgressBar Grid.Column="1" Value="12" Maximum="100" Height="8"
                                     Background="$($T['BgInput'])" BorderThickness="0"
                                     Foreground="$($T['AccentAmber'])" VerticalAlignment="Center"/>
                        <TextBlock Grid.Column="2" Text="12 RAD" FontFamily="Courier New" FontSize="9"
                                   Foreground="$($T['TextMuted'])" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                    </Grid>

                    <Grid Margin="0,4,0,2">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="90"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="36"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="AP" FontFamily="Courier New" FontSize="11"
                                   Foreground="$($T['AccentCyan'])" VerticalAlignment="Center"/>
                        <ProgressBar Grid.Column="1" Value="65" Maximum="100" Height="8"
                                     Background="$($T['BgInput'])" BorderThickness="0"
                                     Foreground="$($T['AccentCyan'])" VerticalAlignment="Center"/>
                        <TextBlock Grid.Column="2" Text="65 AP" FontFamily="Courier New" FontSize="9"
                                   Foreground="$($T['TextMuted'])" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                    </Grid>

                </StackPanel>

                <!-- Divisor vertical -->
                <Rectangle Grid.Column="1" Width="1" HorizontalAlignment="Center"
                            Fill="$($T['BorderSubtle'])"/>

                <!-- Panel derecho: log terminal -->
                <Grid Grid.Column="2">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <!-- Header terminal -->
                    <StackPanel Grid.Row="0" Margin="0,0,0,10">
                        <TextBlock FontFamily="Courier New" FontSize="11"
                                   Foreground="$($T['TextMuted'])">
                            ROBCO INDUSTRIES(TM) TERMLINK PROTOCOL
                        </TextBlock>
                        <TextBlock FontFamily="Courier New" FontSize="11"
                                   Foreground="$($T['TextMuted'])">
                            COPYRIGHT 2075-2077 ROBCO INDUSTRIES
                        </TextBlock>
                        <TextBlock FontFamily="Courier New" FontSize="11"
                                   Foreground="$($T['AccentBlue'])" Margin="0,4,0,0">
                            &gt;&gt; SYSOPT v4.2.1 - SYSTEM OPTIMIZER ONLINE
                            <TextBlock.Effect>
                                <DropShadowEffect Color="$($T['AccentBlue'])" BlurRadius="6" ShadowDepth="0" Opacity="0.6"/>
                            </TextBlock.Effect>
                        </TextBlock>
                        <TextBlock Text="-------------------------------------------"
                                   Style="{StaticResource Separator}"/>
                    </StackPanel>

                    <!-- Consola con typewriter -->
                    <Border Grid.Row="1"
                            Background="$($T['ConsoleBg'])"
                            BorderBrush="$($T['BorderSubtle'])"
                            BorderThickness="1" CornerRadius="2">
                        <ScrollViewer x:Name="LogScroller"
                                      VerticalScrollBarVisibility="Auto"
                                      HorizontalScrollBarVisibility="Disabled">
                            <TextBlock x:Name="ConsoleLog"
                                       FontFamily="Courier New" FontSize="12"
                                       Foreground="$($T['ConsoleFg'])"
                                       Padding="12,10" TextWrapping="Wrap"
                                       LineHeight="20">
                                <TextBlock.Effect>
                                    <DropShadowEffect Color="$($T['AccentBlue'])" BlurRadius="4" ShadowDepth="0" Opacity="0.5"/>
                                </TextBlock.Effect>
                            </TextBlock>
                        </ScrollViewer>
                    </Border>

                    <!-- Input + botones -->
                    <Grid Grid.Row="2" Margin="0,12,0,0">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="10"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <!-- Prompt input simulado -->
                        <Border Grid.Row="0"
                                Background="$($T['BgInput'])"
                                BorderBrush="$($T['BorderSubtle'])"
                                BorderThickness="1" CornerRadius="2" Padding="10,6">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&gt; " FontFamily="Courier New" FontSize="12"
                                           Foreground="$($T['AccentBlue'])"/>
                                <TextBlock x:Name="CursorBlink" Text="_"
                                           FontFamily="Courier New" FontSize="12"
                                           Foreground="$($T['AccentBlue'])"/>
                            </StackPanel>
                        </Border>

                        <!-- Botones accion -->
                        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right">
                            <Button x:Name="BtnAnalyze" Content="[ ANALYZE ]"
                                    Style="{StaticResource BtnPrimary}" Margin="0,0,8,0"/>
                            <Button x:Name="BtnClear" Content="[ CLEAR ]"
                                    Style="{StaticResource BtnSecondary}" Margin="0,0,8,0"/>
                            <Button x:Name="BtnVats" Content="[ V.A.T.S. ]"
                                    Style="{StaticResource BtnAmber}" Margin="0,0,8,0"/>
                            <Button x:Name="BtnExit" Content="[ EXIT ]"
                                    Style="{StaticResource BtnDanger}"/>
                        </StackPanel>
                    </Grid>
                </Grid>
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
$console  = $window.FindName("ConsoleLog")
$titleBar = $window.FindName("TitleBar")
$clock    = $window.FindName("ClockDisplay")
$cursor   = $window.FindName("CursorBlink")
$scroller = $window.FindName("LogScroller")
$noiseCanvas = $window.FindName("NoiseCanvas")

$titleBar.Add_MouseLeftButtonDown({ $window.DragMove() })

# -------------------------------------------------------
# 4. Efecto noise / static (rectangulos random semitransparentes)
# -------------------------------------------------------
$rng = [System.Random]::new()

function Update-Noise {
    $noiseCanvas.Children.Clear()
    $w = $noiseCanvas.ActualWidth
    $h = $noiseCanvas.ActualHeight
    if ($w -lt 10 -or $h -lt 10) { return }

    # Genera 80 pixeles de ruido dispersos
    for ($i = 0; $i -lt 80; $i++) {
        $rect = [Windows.Shapes.Rectangle]::new()
        $rect.Width  = $rng.Next(1, 4)
        $rect.Height = $rng.Next(1, 3)
        $rect.Fill   = if ($rng.NextDouble() -gt 0.5) {
            [Windows.Media.Brushes]::LimeGreen
        } else {
            [Windows.Media.Brushes]::White
        }
        $rect.Opacity = $rng.NextDouble() * 0.6
        [Windows.Controls.Canvas]::SetLeft($rect, $rng.NextDouble() * $w)
        [Windows.Controls.Canvas]::SetTop($rect,  $rng.NextDouble() * $h)
        $noiseCanvas.Children.Add($rect) | Out-Null
    }
}

# -------------------------------------------------------
# 5. Typewriter log
# -------------------------------------------------------
$script:fullLog     = [System.Collections.Generic.List[string]]::new()
$script:typeBuffer  = [System.Collections.Generic.Queue[char]]::new()
$script:currentLine = ""
$script:displayedLines = [System.Collections.Generic.List[string]]::new()

$bootMessages = @(
    "INITIALIZING ROBCO TERMLINK..."
    "SEARCHING FOR NETWORK..."
    ">"
    "CONNECTED TO VAULT-TEC NETWORK NODE 7."
    ">"
    "SYSOPT v4.2.1 LOADED."
    "COPYRIGHT 2075 VAULT-TEC CORPORATION."
    ">"
    "SCANNING SYSTEM INTEGRITY..."
    "  [OK]  CPU LOAD:       12%"
    "  [OK]  MEMORY:         58% USED  (3.7 / 6.4 GB)"
    "  [OK]  STORAGE:        34% USED  (127 / 370 GB)"
    "  [!!]  RAD LEVEL:      12 RADS  - MINIMAL EXPOSURE"
    ">"
    "RUNNING DIAGNOSTICS..."
    "  MODULE OPTIMIZER........ ONLINE"
    "  MODULE CLEANER.......... ONLINE"
    "  MODULE NETWORK.......... ONLINE"
    "  MODULE VAULT LINK....... ONLINE"
    ">"
    "ALL SYSTEMS NOMINAL."
    "READY FOR USER INPUT."
    ">"
    "WAR. WAR NEVER CHANGES."
)

function Queue-Message($msg) {
    foreach ($ch in $msg.ToCharArray()) {
        $script:typeBuffer.Enqueue($ch)
    }
    $script:typeBuffer.Enqueue([char]10) # newline
}

foreach ($msg in $bootMessages) { Queue-Message $msg }

function Tick-Typewriter {
    if ($script:typeBuffer.Count -eq 0) { return }

    # Escribir 2 chars por tick para velocidad adecuada
    for ($i = 0; $i -lt 2; $i++) {
        if ($script:typeBuffer.Count -eq 0) { break }
        $ch = $script:typeBuffer.Dequeue()

        if ([int]$ch -eq 10) {
            # Nueva linea
            $script:displayedLines.Add($script:currentLine)
            $script:currentLine = ""
            # Mantener ultimas 18 lineas
            while ($script:displayedLines.Count -gt 18) {
                $script:displayedLines.RemoveAt(0)
            }
        } else {
            $script:currentLine += $ch
        }
    }

    $console.Text = ($script:displayedLines -join "`n") + "`n" + $script:currentLine
    $scroller.ScrollToBottom()
}

# -------------------------------------------------------
# 6. Cursor blink
# -------------------------------------------------------
$script:cursorVisible = $true
function Tick-Cursor {
    $script:cursorVisible = -not $script:cursorVisible
    $cursor.Opacity = if ($script:cursorVisible) { 1.0 } else { 0.0 }
}

# -------------------------------------------------------
# 7. Reloj en la barra
# -------------------------------------------------------
function Tick-Clock {
    $clock.Text = (Get-Date -Format "HH:mm:ss")
}

# -------------------------------------------------------
# 8. Flicker CRT - la ventana parpadea levemente de opacidad
# -------------------------------------------------------
$script:flickerCount = 0
function Tick-Flicker {
    $script:flickerCount++
    # Cada ~3 segundos un flicker rapido
    if ($script:flickerCount % 55 -eq 0) {
        $window.Opacity = 0.88
    } elseif ($script:flickerCount % 55 -eq 2) {
        $window.Opacity = 1.0
    }
}

# -------------------------------------------------------
# 9. Timers
# -------------------------------------------------------
# Timer principal 40ms: noise + flicker
$timerMain          = [System.Windows.Threading.DispatcherTimer]::new()
$timerMain.Interval = [TimeSpan]::FromMilliseconds(40)
$timerMain.Add_Tick({
    Update-Noise
    Tick-Flicker
})

# Timer typewriter 35ms
$timerType          = [System.Windows.Threading.DispatcherTimer]::new()
$timerType.Interval = [TimeSpan]::FromMilliseconds(35)
$timerType.Add_Tick({ Tick-Typewriter })

# Timer cursor 500ms
$timerCursor          = [System.Windows.Threading.DispatcherTimer]::new()
$timerCursor.Interval = [TimeSpan]::FromMilliseconds(500)
$timerCursor.Add_Tick({ Tick-Cursor })

# Timer reloj 1000ms
$timerClock          = [System.Windows.Threading.DispatcherTimer]::new()
$timerClock.Interval = [TimeSpan]::FromMilliseconds(1000)
$timerClock.Add_Tick({ Tick-Clock })

# -------------------------------------------------------
# 10. Botones
# -------------------------------------------------------
$window.FindName("BtnMinimize").Add_Click({ $window.WindowState = "Minimized" })

$window.FindName("BtnClose").Add_Click({
    $timerMain.Stop(); $timerType.Stop()
    $timerCursor.Stop(); $timerClock.Stop()
    $window.Close()
})

$window.FindName("BtnExit").Add_Click({
    $timerMain.Stop(); $timerType.Stop()
    $timerCursor.Stop(); $timerClock.Stop()
    $window.Close()
})

$window.FindName("BtnClear").Add_Click({
    $script:displayedLines.Clear()
    $script:currentLine = ""
    $script:typeBuffer.Clear()
    $console.Text = ""
    Queue-Message ">"
    Queue-Message "TERMINAL CLEARED."
    Queue-Message "READY."
    Queue-Message ">"
})

$window.FindName("BtnAnalyze").Add_Click({
    Queue-Message ">"
    Queue-Message "RUNNING FULL SYSTEM SCAN..."
    Queue-Message "  SCANNING REGISTRY......... DONE"
    Queue-Message "  SCANNING STARTUP ITEMS..... DONE"
    Queue-Message "  SCANNING TEMP FILES........ DONE"
    Queue-Message "  FOUND: 247 MB RECLAIMABLE"
    Queue-Message "  FOUND: 12 STARTUP ENTRIES"
    Queue-Message "SCAN COMPLETE. AWAITING ORDERS."
    Queue-Message ">"
})

$window.FindName("BtnVats").Add_Click({
    Queue-Message ">"
    Queue-Message "V.A.T.S. TARGETING ONLINE..."
    Queue-Message "  TARGET: JUNK FILES"
    Queue-Message "  HIT CHANCE: 95%"
    Queue-Message "  EXECUTING..."
    Queue-Message "  ** CRITICAL HIT ** 247 MB ELIMINATED."
    Queue-Message ">"
})

# -------------------------------------------------------
# 11. Arranque
# -------------------------------------------------------
$window.Add_Loaded({
    Tick-Clock
    $timerMain.Start()
    $timerType.Start()
    $timerCursor.Start()
    $timerClock.Start()
})

$window.Add_SizeChanged({ Update-Noise })

$window.Add_Closed({
    $timerMain.Stop(); $timerType.Stop()
    $timerCursor.Stop(); $timerClock.Stop()
})

$window.ShowDialog() | Out-Null
