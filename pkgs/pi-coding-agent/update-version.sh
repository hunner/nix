#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version>" >&2
  exit 1
fi

new_version=$1
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/../.." && pwd)
package_nix="$script_dir/package.nix"

echo "Updating package.nix to version $new_version and resetting npmDepsHash..."
sed -i -E "s|^  version = \".*\";$|  version = \"$new_version\";|" "$package_nix"
sed -i -E 's|^  npmDepsHash = .*;$|  npmDepsHash = lib.fakeHash;|' "$package_nix"

echo "Refreshing package.json and package-lock.json..."
(
  cd "$script_dir"
  npm install --package-lock-only --save-exact "@mariozechner/pi-coding-agent@${new_version}"
)

echo "Running nix build to discover the new npmDepsHash..."
(
  cd "$repo_root"
  nix build .#nixosConfigurations.liminal.pkgs.pi-coding-agent
)
