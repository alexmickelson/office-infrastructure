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
            kubeconform
            kube-linter
            kubernetes-helm
            trivy
          ];
        in
        {
          kubernetes-validation =
            pkgs.writeShellApplication {
              name = "kubernetes-validation";
              runtimeInputs = commonInputs;

              text = ''
                KUBE_FILES=$(find ai-office-server/kubernetes \
                  -name "*.yml" -o -name "*.yaml" | grep -v docker-compose)

                for file in $KUBE_FILES; do

                  echo "Checking: $file"

                  kubeconform \
                    -summary \
                    -output text \
                    -skip CustomResourceDefinition,Application,Gateway,HTTPRoute,PeerAuthentication,ReferenceGrant,AuthorizationPolicy,ServiceMonitor,Kustomization,ClusterSecretStore,SecretStore,ExternalSecret,ProxyClass,SealedSecret \
                    "$file"
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
                  --config .github/kube-linter-config.yaml
              '';
            };

         helm-validation =
            pkgs.writeShellApplication {
              name = "helm-validation";
              runtimeInputs = commonInputs;

              text = ''
                VALUES_FILE=$(mktemp)
                trap 'rm -f "$VALUES_FILE"' EXIT

                for file in ai-office-server/kubernetes/argocd/yml/*.yml; do
                  REPO_URL=$(yq eval '.spec.source.repoURL // ""' "$file" | grep -v '^---$' | sed '/^$/d' | tail -1)
                  CHART=$(yq eval '.spec.source.chart // ""' "$file" | grep -v '^---$' | sed '/^$/d' | tail -1)
                  VERSION=$(yq eval '.spec.source.targetRevision // ""' "$file" | grep -v '^---$' | sed '/^$/d' | tail -1)

                  [ -z "$CHART" ] && continue
                  [ "$CHART" = "null" ] && continue

                  if [ "$VERSION" = "*" ]; then
                    echo "ERROR: $file uses wildcard version '*' — pin to a specific version"
                    exit 1
                  fi

                  echo ""
                  echo ""
                  echo ""
                  echo "$CHART - $VERSION - $REPO_URL"

                  REPO_NAME=$(echo "$REPO_URL" | md5sum | cut -d' ' -f1)

                  helm repo add "$REPO_NAME" "$REPO_URL" 2>/dev/null || true
                  helm repo update "$REPO_NAME" 2>/dev/null || true

                  if helm search repo "$REPO_NAME/$CHART" \
                    --version "$VERSION" \
                    | grep -q "$VERSION"; then

                    echo "Version exists"

                    VALUES=$(yq eval '.spec.source.helm.values // ""' "$file")

                    if [ -n "$VALUES" ] && [ "$VALUES" != "null" ]; then
                      echo "$VALUES" > "$VALUES_FILE"

                      helm template test "$REPO_NAME/$CHART" \
                        --version "$VERSION" \
                        --values "$VALUES_FILE" \
                        --dry-run > /dev/null
                    else
                      helm template test "$REPO_NAME/$CHART" \
                        --version "$VERSION" \
                        --dry-run > /dev/null
                    fi

                    echo "Template renders successfully"
                  else
                    echo "Version $VERSION not found in repository"
                    exit 1
                  fi
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

                KUBE_FILES=$(find ai-office-server/kubernetes \
                  -name "*.yml" -o -name "*.yaml" | grep -v docker-compose)

                for file in $KUBE_FILES; do
                      yq eval '.. | select(has("image")) | .image' "$file" \
                        2>/dev/null \
                        | grep -v null >> "$IMAGES" || true
                    done

                sort -u "$IMAGES" > "$IMAGES.sorted"

                if [ ! -s "$IMAGES.sorted" ]; then
                  echo "No images found"
                  exit 0
                fi

                while read -r image; do
                  [ -z "$image" ] && continue

                  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
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
