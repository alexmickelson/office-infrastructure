#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl jq util-linux

# Azure VM Pricing Finder
# Queries the Azure Retail Prices API to find best VM prices
# Usage: ./vm-pricing.sh [options]
#   -s <sku>        Filter by SKU prefix (default: all, e.g. Standard_B, Standard_D)
#   -r <region>     Filter by region (default: all, e.g. eastus, westeurope)
#   -o <os>         Filter by OS: linux|windows (default: linux)
#   -t <type>       Price type: spot|payg|reserved (default: payg)
#   -n <count>      Number of results to show (default: 20)
#   -c              Compare mode: show cheapest SKU per region
#   -a              All regions (default: US regions only)
#   -h              Show this help

set -euo pipefail

BASE_URL="https://prices.azure.com/api/retail/prices"

# US Azure regions
US_REGIONS=(
  eastus
  eastus2
  westus
  westus2
  westus3
  centralus
  northcentralus
  southcentralus
  westcentralus
)

# Defaults
SKU_PREFIX=""
REGION=""
OS_FILTER="linux"
PRICE_TYPE="payg"
COUNT=100
COMPARE_MODE=false
ALL_REGIONS=false

usage() {
  sed -n '/#/p' "$0" | sed 's/^# \?//' | head -20
  exit 0
}

while getopts "s:r:o:t:n:ach" opt; do
  case $opt in
    s) SKU_PREFIX="$OPTARG" ;;
    r) REGION="$OPTARG" ;;
    o) OS_FILTER="$OPTARG" ;;
    t) PRICE_TYPE="$OPTARG" ;;
    n) COUNT="$OPTARG" ;;
    c) COMPARE_MODE=true ;;
    a) ALL_REGIONS=true ;;
    h) usage ;;
    *) usage ;;
  esac
done

# Build OData filter
build_filter() {
  local parts=()

  parts+=("serviceName eq 'Virtual Machines'")

  if [[ -n "$SKU_PREFIX" ]]; then
    parts+=("startswith(armSkuName,'${SKU_PREFIX}')")
  fi

  if [[ -n "$REGION" ]]; then
    parts+=("armRegionName eq '${REGION}'")
  fi

  case "$OS_FILTER" in
    linux)   parts+=("contains(productName,'Linux')") ;;
    windows) parts+=("contains(productName,'Windows')") ;;
  esac

  case "$PRICE_TYPE" in
    spot)     parts+=("priceType eq 'Consumption'" "contains(skuName,'Spot')") ;;
    reserved) parts+=("priceType eq 'Reservation'") ;;
    payg)     parts+=("priceType eq 'Consumption'") ;;
  esac

  # Region whitelist: default to US regions unless -a or -r is given
  if ! $ALL_REGIONS && [[ -z "$REGION" ]]; then
    local region_clause=""
    for r in "${US_REGIONS[@]}"; do
      [[ -n "$region_clause" ]] && region_clause="$region_clause or "
      region_clause="${region_clause}armRegionName eq '$r'"
    done
    parts+=("($region_clause)")
  fi

  local filter=""
  for part in "${parts[@]}"; do
    [[ -n "$filter" ]] && filter="$filter and "
    filter="$filter$part"
  done
  echo "$filter"
}

fetch_prices() {
  local filter
  filter=$(build_filter)

  # URL-encode the filter value using jq's @uri builtin
  local encoded_filter
  encoded_filter=$(jq -rn --arg f "$filter" '$f | @uri')

  # Use a temp file to accumulate items — avoids ARG_MAX when passing large JSON
  local tmp
  tmp=$(mktemp)
  trap 'rm -f "$tmp" "${tmp}.new"' RETURN
  echo "[]" > "$tmp"

  local next_url="${BASE_URL}?\$filter=${encoded_filter}"

  while [[ -n "$next_url" ]]; do
    local response
    response=$(curl -sf "$next_url")

    if [[ -z "$response" ]]; then
      echo "Error: Failed to fetch pricing data" >&2
      return 1
    fi

    # Pipe page items through stdin; read accumulator from file via --slurpfile
    echo "$response" \
      | jq --slurpfile acc "$tmp" '.Items // [] | $acc[0] + .' \
      > "${tmp}.new"
    mv "${tmp}.new" "$tmp"

    next_url=$(echo "$response" | jq -r '.NextPageLink // empty')

    local current_count
    current_count=$(jq 'length' "$tmp")
    if (( current_count >= COUNT * 3 )); then
      break
    fi
  done

  cat "$tmp"
}

print_table() {
  local data="$1"

  (
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "SKU" "Region" "vCPU" '$/hr' '$/day' "Variant"
    echo "$data" | jq -r \
      '[.[] | select(.unitPrice > 0)]
       | sort_by(.unitPrice)
       | .[]
       | [.armSkuName,
          .armRegionName,
          (.armSkuName | capture("Standard_[A-Za-z]+(?<v>[0-9]+)") | .v // "?"),
          ("$" + (.unitPrice | tostring)),
          ("$" + ((.unitPrice * 24 * 100 | round) as $c | ($c / 100 | floor | tostring) + "." + ($c % 100 | if . < 10 then "0" + tostring else tostring end))),
          (.skuName | gsub("^[^,]+, "; ""))]
       | @tsv' \
    | head -n "$COUNT"
  ) | column -t -s $'\t'

  echo ""
}

compare_regions() {
  local data="$1"

  (
    printf '%s\t%s\t%s\t%s\t%s\n' "SKU" "Region" "vCPU" '$/hr' '$/day'
    echo "$data" | jq -r \
      '[.[] | select(.unitPrice > 0)]
       | [group_by(.armRegionName)[]
          | min_by(.unitPrice)]
       | sort_by(.unitPrice)
       | .[]
       | [.armSkuName,
          .armRegionName,
          (.armSkuName | capture("Standard_[A-Za-z]+(?<v>[0-9]+)") | .v // "?"),
          ("$" + (.unitPrice | tostring)),
          ("$" + ((.unitPrice * 24 * 100 | round) as $c | ($c / 100 | floor | tostring) + "." + ($c % 100 | if . < 10 then "0" + tostring else tostring end)))]
       | @tsv' \
    | head -n "$COUNT"
  ) | column -t -s $'\t'

  echo ""
}

# Summary of what we're querying
echo "Querying Azure VM pricing..."
echo "  SKU prefix : ${SKU_PREFIX:-any}"
echo "  Region     : ${REGION:-all regions}"
echo "  OS         : $OS_FILTER"
echo "  Price type : $PRICE_TYPE"
echo "  Regions    : $(if $ALL_REGIONS; then echo 'all'; elif [[ -n "$REGION" ]]; then echo "$REGION"; else echo "US only (${US_REGIONS[*]})"; fi)"
echo "  Results    : $COUNT"

data=$(fetch_prices)
count=$(echo "$data" | jq '[.[] | select(.unitPrice > 0)] | length')

if (( count == 0 )); then
  echo "No results found. Try broadening your filters."
  exit 1
fi

echo "  Found      : $count entries"

if $COMPARE_MODE; then
  compare_regions "$data"
else
  print_table "$data"
fi
