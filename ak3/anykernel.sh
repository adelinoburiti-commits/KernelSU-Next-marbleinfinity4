
properties() { '
kernel.string=Poco F5 | Redmi Note 12 Turbo
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=marble
device.name2=marblein
supported.versions=
supported.patchlevels=
'; }

block=boot;
is_slot_device=auto;
ramdisk_compression=auto;
patch_vbmeta_flag=auto;

. tools/ak3-core.sh;

kdir="${AKHOME:-${home:-$PWD}}";
KEYCHECK="${bin:-$kdir/tools}/keycheck";

ui_print " "
ui_print "███████╗ ██████╗ ██╗███████╗"
ui_print "╚══███╔╝██╔═══██╗██║██╔════╝"
ui_print "  ███╔╝ ██║   ██║██║███████╗"
ui_print " ███╔╝  ██║   ██║██║╚════██║"
ui_print "███████╗╚██████╔╝██║███████║"
ui_print "╚══════╝ ╚═════╝ ╚═╝╚══════╝"
ui_print " "
ui_print "        Kernel by Pablo Escobar"
ui_print " "

PROPFILES="/system_root/system/build.prop /system/build.prop /product/etc/build.prop /system_ext/etc/build.prop"

detect_source() {
  SRC=unknown
  HOW=none

  for f in $PROPFILES; do
    [ -f "$f" ] || continue

    v=$(grep -m1 '^ro\.sys\.buildtype=' "$f" |
      cut -d= -f2- |
      tr -d '\r ' |
      tr '[:upper:]' '[:lower:]')

    case "$v" in
      aosp|clo)
        SRC="$v"
        HOW="ro.sys.buildtype"
        return 0
        ;;
    esac
  done

  for f in $PROPFILES; do
    [ -f "$f" ] || continue

    if grep -qiE 'aospa|neoteric' "$f"; then
      SRC=clo
      HOW="AOSPA/Neoteric ROM"
      return 0
    fi
  done

  return 1
}

unsupported() {
  ui_print " "
  ui_print "──────────────────────────────────────"
  ui_print "            Unsupported ROM"
  ui_print "──────────────────────────────────────"
  ui_print " "
  abort "Installation aborted.";
}

CONFIRM_WITH_POWER=0

use_keycheck() { [ "$CONFIRM_WITH_POWER" != "1" ] && [ -x "$KEYCHECK" ]; }

wait_key() {
  if use_keycheck; then
    while true; do
      "$KEYCHECK"; a=$?
      "$KEYCHECK"; b=$?
      [ "$a" = "$b" ] || continue
      case "$b" in
        42) return 1;;
        41) return 2;;
      esac
    done
  fi
  while true; do
    ev=$(getevent -lc 1 2>/dev/null | grep -Eo 'KEY_(VOLUMEUP|VOLUMEDOWN|POWER) +DOWN' | head -n1);
    key=${ev%% *}
    case "$key" in
      KEY_VOLUMEUP) r=1;;
      KEY_VOLUMEDOWN) r=2;;
      KEY_POWER) [ "$CONFIRM_WITH_POWER" = "1" ] || continue; r=3;;
      *) continue;;
    esac
    i=0
    while [ $i -lt 20 ]; do
      getevent -lc 1 2>/dev/null | grep -Eq "$key +UP" && break
      i=$((i+1))
    done
    return $r
  done
}

save_screen() {
  n=0
  for b in /sys/class/backlight/*/brightness /sys/class/leds/lcd-backlight/brightness /sys/class/leds/wled/brightness; do
    [ -f "$b" ] || continue
    n=$((n+1))
    cat "$b" > "/tmp/.ak_bl_$n" 2>/dev/null
    echo "$b" > "/tmp/.ak_blp_$n"
  done
}
restore_screen() {
  for p in /tmp/.ak_blp_*; do
    [ -f "$p" ] || continue
    n=${p##*_}
    b=$(cat "$p"); v=$(cat "/tmp/.ak_bl_$n" 2>/dev/null)
    if [ -n "$v" ] && [ "$v" -gt 0 ] 2>/dev/null; then echo "$v" > "$b" 2>/dev/null; fi
  done
  [ -f /sys/class/graphics/fb0/blank ] && echo 0 > /sys/class/graphics/fb0/blank 2>/dev/null
}
keep_screen_on() {
  ( i=0; while [ $i -lt 8 ]; do sleep 1; restore_screen; i=$((i+1)); done ) >/dev/null 2>&1 &
}

detect_source >/dev/null 2>&1 || true
case "$SRC" in
  aosp|clo) ;;
  *) unsupported;;
esac

if [ -s "$kdir/Image" ]; then
  name="zip-kernel"
  ui_print " "; ui_print "Flashing the kernel in this zip";
else
  if use_keycheck; then
    ui_print "Key input: keycheck"
  else
    command -v getevent >/dev/null 2>&1 || abort "No key input available (no tools/keycheck, no getevent). Aborting...";
    ui_print "Key input: getevent"
  fi

  ui_print " "
  ui_print "Select kernel to flash:"
  ui_print "  1. KernelSU"
  ui_print "  2. KernelSU-Next"
  ui_print " "

  if [ "$CONFIRM_WITH_POWER" = "1" ]; then
    ui_print "  Vol+ / Vol- = move   Power = confirm"
    save_screen
    sel=1
    while true; do
      case $sel in
        1) name=kernelsu; lbl="1. KernelSU";;
        2) name=kernelsu-next; lbl="2. KernelSU-Next";;
      esac
      ui_print "  > $lbl"
      wait_key; k=$?
      case $k in
        1) sel=$((sel - 1)); [ $sel -lt 1 ] && sel=2;;
        2) sel=$((sel % 2 + 1));;
        3)
          if [ -s "$kdir/$SRC/$name" ]; then keep_screen_on; break; fi
          ui_print "  $name is not in this zip, choose the other one";;
      esac
    done
  else
    ui_print "  Vol+ = 1. KernelSU    Vol- = 2. KernelSU-Next"
    while true; do
      wait_key; k=$?
      case $k in
        1) name=kernelsu; lbl="1. KernelSU";;
        2) name=kernelsu-next; lbl="2. KernelSU-Next";;
      esac
      [ -s "$kdir/$SRC/$name" ] && break
      ui_print "  $name is not in this zip, press the other key"
    done
  fi

  ui_print " "; ui_print "Flashing: $lbl";
  cp -f "$kdir/$SRC/$name" "$kdir/Image" || abort "Unable to stage kernel Image. Aborting...";
  for f in dtb dtbo; do
    [ -s "$kdir/$SRC/$f" ] && cp -f "$kdir/$SRC/$f" "$kdir/$f";
  done
  rm -rf "$kdir/aosp" "$kdir/clo";
fi

backup_current_boot() {
  backup_dir="/sdcard/marble-kernel-backup";
  slot_name="${SLOT:-noslot}";
  stamp="$(date +%Y%m%d-%H%M%S 2>/dev/null || date +%s)";
  backup_img="${backup_dir}/boot-marble-${slot_name}-${stamp}.img";
  backup_txt="${backup_dir}/boot-marble-${slot_name}-${stamp}.txt";

  ui_print "Backing up current boot image...";
  mkdir -p "$backup_dir" || abort "Unable to create ${backup_dir}. Aborting...";
  [ -s "$BOOTIMG" ] || abort "Dumped boot image is missing. Backup failed; aborting for safety.";
  cp -f "$BOOTIMG" "$backup_img" || abort "Unable to save boot backup. Aborting...";
  {
    echo "device=marble/marblein";
    echo "slot=${slot_name}";
    echo "source_block=${BLOCK}";
    echo "created=${stamp}";
    echo "backup=${backup_img}";
    echo "installed=${SRC}/${name}";
  } > "$backup_txt" 2>/dev/null || true;
  ui_print "Backup saved:";
  ui_print "  ${backup_img}";
}

dump_boot;
backup_current_boot;
write_boot;
