# dynamic wallpaper

## features

  * swww-based dynamic wallpaper switcher
  * switches wallpapers from configured list during the day
  * creates symlink to current wallpaper (useful with screenlock utilities, e.g. hyprlock)
  * uses systemd timer

## usage

```bash
$ ./dynamic_wallpaper config.json
```

## config format

```json
{
  "symlink": "path/to/symlink",
  "wallpapers": [
    "path/to/wallpaper-1.jpg",
    "path/to/wallpaper-2.jpg",
    "path/to/wallpaper-3.jpg",
    "path/to/wallpaper-4.jpg"
  ]
}
```
