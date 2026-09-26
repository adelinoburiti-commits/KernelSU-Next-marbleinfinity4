#!/usr/bin/env bash
set -euo pipefail

KERNEL_DIR="${KERNEL_DIR:-kernel-source}"
ENABLE_SUSFS="${ENABLE_SUSFS:-false}"

if [[ "${ENABLE_SUSFS}" != "true" ]]; then
  echo "SUSFS disabled"
  exit 0
fi

source config/marble.env
source release/resolved-refs.env

if [[ -z "${susfs_commit}" ]]; then
  echo "::error::SUSFS resolution missing commit"
  exit 1
fi

work_root="$(pwd)"
susfs_dir="${work_root}/susfs4ksu"
git clone "${SUSFS_REPO}" "${susfs_dir}"
git -C "${susfs_dir}" checkout "${susfs_commit}"

# Debug: show kernel_patches structure
echo "=== SUSFS kernel_patches structure ==="
find "${susfs_dir}/kernel_patches" -type f -name "*.h" 2>/dev/null | head -20
echo "=== SUSFS include/linux ==="
ls -la "${susfs_dir}/kernel_patches/include/linux/" 2>/dev/null || echo "include/linux not found"

patch_root="${susfs_dir}/kernel_patches"
if [[ ! -d "${patch_root}" ]]; then
  echo "::error::Missing SUSFS patch directory: ${patch_root}"
  exit 1
fi

# Debug: show patch_root contents
echo "=== patch_root contents ==="
ls -la "${patch_root}/"
echo "=== patch_root/include ==="
ls -la "${patch_root}/include/" 2>/dev/null || echo "include not found"
echo "=== patch_root/include/linux ==="
ls -la "${patch_root}/include/linux/" 2>/dev/null || echo "include/linux not found"

pushd "${KERNEL_DIR}" >/dev/null
patch_suffix="${SUSFS_KERNEL_BRANCH#gki-}"
main_patch="${patch_root}/50_add_susfs_in_gki-${patch_suffix}.patch"
if [[ -f "${main_patch}" ]]; then
  patch -p1 < "${main_patch}"
else
  echo "::error::Missing main SUSFS kernel patch for ${SUSFS_KERNEL_BRANCH}"
  exit 1
fi

rsync -a "${susfs_dir}/kernel_patches/fs/" fs/
rsync -a "${susfs_dir}/kernel_patches/include/" include/

# Debug: verify susfs headers were copied
echo "=== Verifying SUSFS headers copied ==="
ls -la include/linux/susfs*.h 2>/dev/null || echo "susfs headers NOT found in include/linux/"
find include -name "susfs*" -type f 2>/dev/null || echo "No susfs files found in include/"

# Also verify the susfs.c was copied to fs/
echo "=== Verifying susfs.c copied ==="
ls -la fs/susfs.c 2>/dev/null || echo "susfs.c NOT found in fs/"

manager_kconfig=""
# Check symlink target first for KernelSU (drivers/kernelsu -> KernelSU/kernel)
if [[ -L "drivers/kernelsu" ]]; then
  target="$(readlink drivers/kernelsu)"
  if [[ -f "${target}/Kconfig" ]]; then
    manager_kconfig="${target}/Kconfig"
  fi
fi
# Check common/drivers for GKI kernels
if [[ -z "${manager_kconfig}" && -L "common/drivers/kernelsu" ]]; then
  target="$(readlink common/drivers/kernelsu)"
  if [[ -f "${target}/Kconfig" ]]; then
    manager_kconfig="${target}/Kconfig"
  fi
fi
# Fallback to direct paths
if [[ -z "${manager_kconfig}" ]]; then
  for candidate in KernelSU/kernel/Kconfig KernelSU-Next/kernel/Kconfig SukiSU-Ultra/kernel/Kconfig SukiSU/kernel/Kconfig ReSukiSU/kernel/Kconfig drivers/kernelsu/Kconfig common/drivers/kernelsu/Kconfig; do
    if [[ -f "${candidate}" ]]; then
      manager_kconfig="${candidate}"
      break
    fi
  done
fi

if [[ -z "${manager_kconfig}" ]]; then
  echo "::error::Could not find manager source directory for SUSFS integration"
  exit 1
fi

if ! grep -q '^config KSU_SUSFS$' "${manager_kconfig}"; then
  echo "::error::Official manager ref ${manager_repo}@${manager_ref} does not include manager-side SUSFS support"
  exit 1
fi

echo "Using manager-side SUSFS support from ${manager_repo}@${manager_ref}"

popd >/dev/null
echo "SUSFS applied from ${susfs_commit}"
