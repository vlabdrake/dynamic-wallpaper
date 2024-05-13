# dynamic wallpaper

## features

- swww-based dynamic wallpaper switcher
- switches wallpapers from configured list during the day
- creates symlink to current wallpaper (useful with screenlock utilities, e.g. hyprlock)
- switch gtk theme at morning and evening
- switch app themes:
  - zed editor
  - helix editor
  - kitty terminal

## usage

```bash
$ ./dynamic_wallpaper config.json
```

## config format

```json
{
  "wallpaper": {
    "symlink": "path/to/symlink",
    "wallpapers": [
      "path/to/wallpaper-1.jpg",
      "path/to/wallpaper-2.jpg",
      "path/to/wallpaper-3.jpg",
      "path/to/wallpaper-4.jpg"
    ]
  },
  "gtk": {
    "light_theme": "gtk-theme-light",
    "dark_theme": "gtk-theme-dark"
  },
  "kitty": {
    "light_theme": "solarized_light.conf",
    "dark_theme": "nord.conf"
  },
  "helix": {
    "light_theme": "emacs",
    "dark_theme": "darcula"
  }
}
```
