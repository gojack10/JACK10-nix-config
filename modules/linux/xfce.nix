{ config, lib, ... }:

let
  uint = value: { type = "uint"; inherit value; };
  wallpaper = "${config.home.homeDirectory}/.local/share/JACK10-nix-config/bg.png";
  launcher = name: icon: exec: ''
    [Desktop Entry]
    Type=Application
    Name=${name}
    Icon=${icon}
    Exec=${exec}
    Terminal=false
  '';
in
{
  home.sessionVariables.GTK_THEME = "Adwaita:dark";

  xfconf.settings = {
    xsettings = {
      "Net/ThemeName" = "Adwaita-dark";
      "Net/IconThemeName" = "Papirus-Dark";
      "Gtk/FontName" = "Sans 10";
      "Gtk/MonospaceFontName" = "JetBrainsMono Nerd Font Mono 10";
    };

    xfwm4 = {
      "general/use_compositing" = false;
      "general/click_to_focus" = true;
      "general/theme" = "Default";
    };

    xfce4-desktop = {
      "desktop-icons/style" = 0;
      "backdrop/screen0/monitoreDP-1/workspace0/last-image" = wallpaper;
      "backdrop/screen0/monitoreDP-1/workspace0/image-style" = uint 5;
    };

    xfce4-panel = {
      "panels" = [ 1 ];
      "panels/dark-mode" = true;
      "panels/panel-1/position" = "p=10;x=0;y=0";
      "panels/panel-1/length" = uint 100;
      "panels/panel-1/position-locked" = true;
      "panels/panel-1/size" = uint 44;
      "panels/panel-1/icon-size" = uint 28;
      "panels/panel-1/plugin-ids" = [ 1 2 3 4 5 6 7 8 9 10 11 12 ];

      "plugins/plugin-1" = "whiskermenu";
      "plugins/plugin-1/button-title" = "Apps";
      "plugins/plugin-1/show-button-title" = true;
      "plugins/plugin-2" = "launcher";
      "plugins/plugin-2/items" = [ "chromium.desktop" ];
      "plugins/plugin-3" = "launcher";
      "plugins/plugin-3/items" = [ "files.desktop" ];
      "plugins/plugin-4" = "launcher";
      "plugins/plugin-4/items" = [ "terminal.desktop" ];
      "plugins/plugin-5" = "separator";
      "plugins/plugin-5/expand" = true;
      "plugins/plugin-5/style" = uint 0;
      "plugins/plugin-6" = "tasklist";
      "plugins/plugin-6/grouping" = uint 1;
      "plugins/plugin-6/show-handle" = false;
      "plugins/plugin-7" = "separator";
      "plugins/plugin-7/expand" = true;
      "plugins/plugin-7/style" = uint 0;
      "plugins/plugin-8" = "pulseaudio";
      "plugins/plugin-8/enable-keyboard-shortcuts" = true;
      "plugins/plugin-9" = "notification-plugin";
      "plugins/plugin-10" = "systray";
      "plugins/plugin-10/square-icons" = true;
      "plugins/plugin-11" = "clock";
      "plugins/plugin-12" = "actions";
      "plugins/plugin-12/items" = [
        "+logout-dialog"
        "+switch-user"
        "+suspend"
        "+restart"
        "+shutdown"
        "-lock-screen"
        "-hibernate"
        "-hybrid-sleep"
      ];
    };
  };

  xdg.configFile = lib.mapAttrs (_: file: file // { force = true; }) {
    "xfce4/panel/launcher-2/chromium.desktop".text = launcher "Chromium" "chromium" "/usr/bin/chromium %U";
    "xfce4/panel/launcher-3/files.desktop".text = launcher "Files" "folder" "/usr/bin/thunar %U";
    "xfce4/panel/launcher-4/terminal.desktop".text = launcher "Terminal" "utilities-terminal" "/usr/bin/xfce4-terminal";

    "xfce4/panel/whiskermenu-1.rc".text = ''
      button-title=Apps
      show-button-title=true
      show-button-icon=true
      launcher-show-name=true
      launcher-show-description=true
      view-mode=1
    '';

    "xfce4/terminal/terminalrc".text = ''
      [Configuration]
      FontName=JetBrainsMono Nerd Font Mono 10
      ColorUseTheme=FALSE
      ColorForeground=#d0d0d0
      ColorBackground=#090909
      ColorCursor=#d0d0d0
      ColorPalette=#0f0f0f;#ff5555;#5fff87;#ffff5f;#5fafff;#ff87ff;#5fd7ff;#d0d0d0;#8a8a8a;#ff5555;#5fff87;#ffff5f;#5fafff;#ff87ff;#5fd7ff;#ffffff
      MiscMenubarDefault=FALSE
      MiscToolbarDefault=FALSE
      MiscBordersDefault=FALSE
      MiscConfirmClose=TRUE
      MiscDefaultGeometry=100x30
      ScrollingBar=TERMINAL_SCROLLBAR_NONE
    '';

    "gtk-3.0/settings.ini".text = ''
      [Settings]
      gtk-theme-name=Adwaita-dark
      gtk-icon-theme-name=Papirus-Dark
      gtk-font-name=Sans 10
      gtk-application-prefer-dark-theme=1
    '';

    "gtk-4.0/settings.ini".text = ''
      [Settings]
      gtk-theme-name=Adwaita-dark
      gtk-icon-theme-name=Papirus-Dark
      gtk-font-name=Sans 10
      gtk-application-prefer-dark-theme=1
    '';

    "xfce4/helpers.rc".text = ''
      WebBrowser=chromium
      FileManager=thunar
      TerminalEmulator=xfce4-terminal
    '';
    "mimeapps.list" = { };
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = [ "chromium.desktop" ];
      "x-scheme-handler/http" = [ "chromium.desktop" ];
      "x-scheme-handler/https" = [ "chromium.desktop" ];
      "inode/directory" = [ "thunar.desktop" ];
    };
  };
}
