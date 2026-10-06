#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

work="$(mktemp -d)"
cp -r ak3/. "${work}/"
rm -rf "${work}/README.md" "${work}/Image" "${work}/dtb" "${work}/dtbo" "${work}/.git"
cp LICENSE "${work}/LICENSE"

for dir in release-assets/*/; do
  [[ -f "${dir}zip-name.env" && -f "${dir}build-info.txt" ]] || continue
  zip_name="$(grep -m1 '^zip_name=' "${dir}zip-name.env" | cut -d= -f2-)"
  src_full="$(grep -m1 '^kernel_source=' "${dir}build-info.txt" | cut -d= -f2-)"
  mgr="$(grep -m1 '^manager=' "${dir}build-info.txt" | cut -d= -f2-)"
  case "${src_full}" in
    aosp-pablo) src=aosp ;;
    clo-marble) src=clo ;;
    *) echo "::warning::skipping ${dir}: unknown kernel_source '${src_full}'"; continue ;;
  esac
  case "${mgr}" in
    kernelsu|kernelsu-next) ;;
    *) echo "::warning::skipping ${dir}: unknown manager '${mgr}'"; continue ;;
  esac
  zip="${dir}${zip_name}"
  [[ -s "${zip}" ]] || { echo "::error::missing ${zip}"; exit 1; }

  mkdir -p "${work}/${src}"
  unzip -p "${zip}" Image > "${work}/${src}/${mgr}"
  for f in dtb dtbo; do
    if unzip -Z1 "${zip}" | grep -qx "${f}" && [[ ! -e "${work}/${src}/${f}" ]]; then
      unzip -p "${zip}" "${f}" > "${work}/${src}/${f}"
    fi
  done
  echo "added ${src}/${mgr} from ${zip_name}"
done

missing=0
for src in aosp clo; do
  for mgr in kernelsu kernelsu-next; do
    [[ -s "${work}/${src}/${mgr}" ]] || { echo "::error::missing ${src}/${mgr}"; missing=1; }
  done
done
(( missing == 0 )) || exit 1

mkdir -p combined
zip_name="zois-kernel-$(date +%Y.%m.%d).zip"
rm -f "combined/${zip_name}"
(cd "${work}" && zip -r9q "${OLDPWD}/combined/${zip_name}" . -x ".git/*" "*placeholder*" "banner" "banner.txt")
(cd combined && sha256sum "${zip_name}" > "${zip_name}.sha256")
{
  echo "zip_name=${zip_name}"
  echo "zip_sha256=$(sha256sum "combined/${zip_name}" | awk '{print $1}')"
} > combined/zip-name.env
unzip -Z1 "combined/${zip_name}" | grep -E '^(aosp|clo)/' | sort
echo "Combined zip: combined/${zip_name}"
