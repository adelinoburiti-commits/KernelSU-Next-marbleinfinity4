#!/usr/bin/env bash
set -euo pipefail

MANAGER="${MANAGER:-kernelsu-next}"
KERNEL_DIR="${KERNEL_DIR:-kernel-source}"

source release/resolved-refs.env

if [[ -z "${manager_repo}" || -z "${manager_commit}" || -z "${manager_setup_path}" ]]; then
  echo "::error::Manager resolution missing repo, commit, or setup path"
  exit 1
fi

pushd "${KERNEL_DIR}" >/dev/null
setup_url="https://raw.githubusercontent.com/${manager_repo}/${manager_commit}/${manager_setup_path}"
echo "Applying ${MANAGER} from ${manager_repo}@${manager_commit}"
curl -fsSL "${setup_url}" -o /tmp/manager-setup.sh

echo "Running manager setup script..."
bash /tmp/manager-setup.sh "${manager_commit}"
echo "Manager setup script completed"

# Debug: show drivers directory structure
echo "=== drivers/ directory after setup ==="
ls -la drivers/ 2>/dev/null | head -20 || true
if [[ -d "common/drivers" ]]; then
  echo "=== common/drivers/ directory after setup ==="
  ls -la common/drivers/ 2>/dev/null | head -20 || true
fi
if [[ -d "KernelSU" ]]; then
  echo "=== KernelSU/ directory ==="
  ls -la KernelSU/ 2>/dev/null || true
  if [[ -d "KernelSU/kernel" ]]; then
    ls -la KernelSU/kernel/ 2>/dev/null || true
  fi
fi

# Verify manager integration was applied
if [[ "${MANAGER}" == "kernelsu" ]]; then
  # Check both drivers/ and common/drivers/ for GKI kernels
  kernelsu_path=""
  for path in "drivers/kernelsu" "common/drivers/kernelsu"; do
    if [[ -L "${path}" || -d "${path}" ]]; then
      kernelsu_path="${path}"
      break
    fi
  done
  if [[ -z "${kernelsu_path}" ]]; then
    echo "::error::KernelSU symlink/directory not created at drivers/kernelsu or common/drivers/kernelsu"
    exit 1
  fi
  if [[ ! -f "${kernelsu_path}/Kconfig" ]]; then
    echo "::error::KernelSU Kconfig not found at ${kernelsu_path}/Kconfig"
    ls -la "${kernelsu_path}/" 2>/dev/null || true
    exit 1
  fi
  echo "KernelSU integration verified at ${kernelsu_path}"
fi
popd >/dev/null
