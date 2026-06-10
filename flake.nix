
# nix run .#yaml-validation
# nix run .#kubernetes-validation
# nix run .#kube-security-validation
# nix run .#helm-validation
# nix run .#docker-security-scan
{
  description = "Renovate validation tooling";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];

      forAllSystems = f:
        nixpkgs.lib.genAttrs systems
          (system: f (import nixpkgs { inherit system; }));
    in
    {
      packages = forAllSystems (pkgs:
        let
          commonInputs = with pkgs; [
            bash
            coreutils
            findutils
            gnugrep
            gawk
            jq
            yq-go
            yamllint
            kubeconform
            kube-linter
            kubernetes-helm
            trivy
          ];
        in
        {
          yaml-validation =
            pkgs.writeShellApplication {
              name = "yaml-validation";
              runtimeInputs = commonInputs;

              text = ''
                yamllint -f parsable ai-office-server/ || true
                echo "YAML linting complete"
              '';
            };

          kubernetes-validation =
            pkgs.writeShellApplication {
              name = "kubernetes-validation";
              runtimeInputs = commonInputs;

              text = ''
                find ai-office-server/kubernetes \
                  \( -name "*.yml" -o -name "*.yaml" \) \
                  | while read -r file; do

                  echo "Checking: $file"

                  kubeconform \
                    -summary \
                    -output text \
                    -skip CustomResourceDefinition,Application,Gateway,HTTPRoute \
                    "$file" || true
                done
              '';
            };

          kube-security-validation =
            pkgs.writeShellApplication {
              name = "kube-security-validation";
              runtimeInputs = commonInputs;

              text = ''
                kube-linter lint \
                  ai-office-server/kubernetes \
                  --config .github/kube-linter-config.yaml \
                  || true
              '';
            };

          helm-validation =
            pkgs.writeShellApplication {
              name = "helm-validation";
              runtimeInputs = commonInputs;

              text = ''
                for file in ai-office-server/kubernetes/argocd/yml/*.yml; do
                  REPO_URL=$(yq eval '.spec.source.repoURL // ""' "$file")
                  CHART=$(yq eval '.spec.source.chart // ""' "$file")
                  VERSION=$(yq eval '.spec.source.targetRevision // ""' "$file")

                  [ -z "$CHART" ] && continue
                  [ "$CHART" = "null" ] && continue

                  REPO_NAME=$(echo "$REPO_URL" | md5sum | cut -d' ' -f1)

                  helm repo add "$REPO_NAME" "$REPO_URL" 2>/dev/null || true
                  helm repo update "$REPO_NAME" 2>/dev/null || true

                  helm search repo "$REPO_NAME/$CHART" \
                    --version "$VERSION" \
                    | grep -q "$VERSION"
                done
              '';
            };

          docker-security-scan =
            pkgs.writeShellApplication {
              name = "docker-security-scan";
              runtimeInputs = commonInputs;

              text = ''
                IMAGES=$(mktemp)

                if [ -f ai-office-server/docker-compose.yml ]; then
                  yq eval '.services.*.image' \
                    ai-office-server/docker-compose.yml \
                    | grep -v null >> "$IMAGES" || true
                fi

                find ai-office-server/kubernetes \
                  \( -name "*.yml" -o -name "*.yaml" \) \
                  | while read -r file; do
                      yq eval '.. | select(has("image")) | .image' "$file" \
                        2>/dev/null \
                        | grep -v null >> "$IMAGES" || true
                    done

                sort -u "$IMAGES" > "$IMAGES.sorted"

                while read -r image; do
                  [ -z "$image" ] && continue

                  echo "Scanning $image"

                  trivy image \
                    --severity HIGH,CRITICAL \
                    --exit-code 0 \
                    --no-progress \
                    "$image"
                done < "$IMAGES.sorted"
              '';
            };

          default =
            pkgs.symlinkJoin {
              name = "renovate-validation-tools";

              paths = [
                self.packages.${pkgs.system}.yaml-validation
                self.packages.${pkgs.system}.kubernetes-validation
                self.packages.${pkgs.system}.kube-security-validation
                self.packages.${pkgs.system}.helm-validation
                self.packages.${pkgs.system}.docker-security-scan
              ];
            };
        });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            self.packages.${pkgs.system}.default
          ];
        };
      });
    };
}