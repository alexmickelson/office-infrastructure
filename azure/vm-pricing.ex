#!/usr/bin/env nix-shell
#!nix-shell -i elixir -p elixir

original_gl = Process.group_leader()
{:ok, devnull} = File.open("/dev/null", [:write])
Process.group_leader(self(), devnull)
Mix.install([{:req, "~> 0.5"}])
Process.group_leader(self(), original_gl)
File.close(devnull)

defmodule VmPricing do
  @base_url "https://prices.azure.com/api/retail/prices"

  @us_regions ~w[
    eastus eastus2 westus westus2 westus3
    centralus northcentralus southcentralus westcentralus
  ]

  # Specs from https://learn.microsoft.com/en-us/azure/virtual-machines/av2-series
  # and https://learn.microsoft.com/en-us/azure/virtual-machines/a-series
  # (VM specs are not available from the Retail Prices API; the Azure Resource SKUs
  #  API at /subscriptions/{id}/providers/Microsoft.Compute/skus requires ARM auth)
  @sku_specs %{
    "Standard_A0" => %{vcpu: 1, ram: 0.75, storage: 20},
    "Standard_A1" => %{vcpu: 1, ram: 1.75, storage: 70},
    "Standard_A2" => %{vcpu: 2, ram: 3.5, storage: 135},
    "Standard_A3" => %{vcpu: 4, ram: 7.0, storage: 285},
    "Standard_A4" => %{vcpu: 8, ram: 14.0, storage: 605},
    "Standard_A5" => %{vcpu: 2, ram: 14.0, storage: 135},
    "Standard_A6" => %{vcpu: 4, ram: 28.0, storage: 285},
    "Standard_A7" => %{vcpu: 8, ram: 56.0, storage: 605},
    "Standard_A8" => %{vcpu: 8, ram: 56.0, storage: 382},
    "Standard_A9" => %{vcpu: 16, ram: 112.0, storage: 382},
    "Standard_A10" => %{vcpu: 8, ram: 56.0, storage: 382},
    "Standard_A11" => %{vcpu: 16, ram: 112.0, storage: 382},
    "Standard_A1_v2" => %{vcpu: 1, ram: 2.0, storage: 10},
    "Standard_A2_v2" => %{vcpu: 2, ram: 4.0, storage: 20},
    "Standard_A4_v2" => %{vcpu: 4, ram: 8.0, storage: 40},
    "Standard_A8_v2" => %{vcpu: 8, ram: 16.0, storage: 80},
    "Standard_A2m_v2" => %{vcpu: 2, ram: 16.0, storage: 20},
    "Standard_A4m_v2" => %{vcpu: 4, ram: 32.0, storage: 40},
    "Standard_A8m_v2" => %{vcpu: 8, ram: 64.0, storage: 80}
  }

  @opts %{
    # e.g. "Standard_A" or nil for any
    sku_prefix: "Standard_A",
    region: nil,
    # "linux" | "windows"
    os: "linux",
    # "payg" | "spot" | "reserved"
    price_type: "payg",
    count: 20,
    # minimum vCPU count (nil = no minimum)
    min_vcpu: 4,
    # true = show cheapest SKU per region
    compare: false,
    # false = US regions only
    all_regions: false
  }

  def main do
    opts = @opts

    IO.puts("Querying Azure VM pricing...")
    IO.puts("  SKU prefix : #{opts.sku_prefix || "any"}")
    IO.puts("  Region     : #{opts.region || "all regions"}")
    IO.puts("  OS         : #{opts.os}")
    IO.puts("  Price type : #{opts.price_type}")

    regions_label =
      cond do
        Map.get(opts, :all_regions) -> "all"
        Map.get(opts, :region) -> Map.get(opts, :region)
        true -> "US only (#{Enum.join(@us_regions, " ")})"
      end

    IO.puts("  Regions    : #{regions_label}")
    IO.puts("  Results    : #{opts.count}")
    IO.puts("  Min vCPUs  : #{opts.min_vcpu || "any"}")

    data = fetch_prices(opts)

    valid =
      data
      |> Enum.filter(&(&1["unitPrice"] > 0))
      |> Enum.filter(fn item ->
        product = item["productName"] || ""

        case opts.os do
          "linux" -> !String.contains?(product, "Windows")
          "windows" -> String.contains?(product, "Windows")
          _ -> true
        end
      end)
      |> Enum.filter(fn item ->
        sku = item["armSkuName"] || ""
        min = Map.get(opts, :min_vcpu)

        case Map.get(@sku_specs, sku) do
          nil -> true
          spec -> is_nil(min) or spec.vcpu >= min
        end
      end)

    if Enum.empty?(valid) do
      IO.puts("No results found. Try broadening your filters.")
      System.halt(1)
    end

    IO.puts("  Found      : #{length(valid)} entries\n")

    if opts.compare do
      compare_regions(valid, opts.count)
    else
      print_table(valid, opts.count)
    end
  end


  defp build_filter(opts) do
    parts = ["serviceName eq 'Virtual Machines'"]

    parts =
      if opts.sku_prefix,
        do: parts ++ ["startswith(armSkuName,'#{opts.sku_prefix}')"],
        else: parts

    parts =
      if opts.region,
        do: parts ++ ["armRegionName eq '#{opts.region}'"],
        else: parts

    parts =
      case opts.price_type do
        "spot" -> parts ++ ["priceType eq 'Consumption'", "contains(skuName,'Spot')"]
        "reserved" -> parts ++ ["priceType eq 'Reservation'"]
        _ -> parts ++ ["priceType eq 'Consumption'"]
      end

    parts =
      if !opts.all_regions && !opts.region do
        region_clause =
          @us_regions
          |> Enum.map(&"armRegionName eq '#{&1}'")
          |> Enum.join(" or ")

        parts ++ ["(#{region_clause})"]
      else
        parts
      end

    Enum.join(parts, " and ")
  end

  defp fetch_prices(opts) do
    filter = build_filter(opts)
    encoded = URI.encode(filter, &URI.char_unreserved?/1)
    fetch_all("#{@base_url}?$filter=#{encoded}", [], opts.count)
  end

  defp fetch_all(nil, acc, _limit), do: acc
  defp fetch_all("", acc, _limit), do: acc

  defp fetch_all(url, acc, limit) do
    response = Req.get!(url)
    items = response.body["Items"] || []
    next = response.body["NextPageLink"]
    acc = acc ++ items

    if length(acc) >= limit * 3 or is_nil(next) or next == "" do
      acc
    else
      fetch_all(next, acc, limit)
    end
  end

  defp fmt(price, decimals \\ 4),
    do: :erlang.float_to_binary(price * 1.0, [{:decimals, decimals}])

  defp sku_spec(sku, key, default \\ "?") do
    case Map.get(@sku_specs, sku) do
      nil -> default
      spec -> Map.get(spec, key, default) |> to_string()
    end
  end

  defp os_label(product_name) do
    if String.contains?(product_name, "Windows"), do: "Windows", else: "Linux"
  end

  defp print_table(data, count) do
    rows =
      data
      |> Enum.sort_by(& &1["unitPrice"])
      |> Enum.take(count)
      |> Enum.map(fn item ->
        hr = item["unitPrice"]
        sku = item["armSkuName"] || ""

        [
          sku,
          item["armRegionName"] || "",
          os_label(item["productName"] || ""),
          sku_spec(sku, :vcpu),
          sku_spec(sku, :ram),
          sku_spec(sku, :storage),
          "$#{fmt(hr)}",
          "$#{fmt(hr * 730, 2)}"
        ]
      end)

    headers = ["SKU", "Region", "OS", "vCPU", "RAM(GiB)", "Disk(GiB)", "$/hr", "$/month"]
    print_aligned([headers | rows])
  end

  defp compare_regions(data, count) do
    rows =
      data
      |> Enum.group_by(& &1["armRegionName"])
      |> Enum.map(fn {_region, items} -> Enum.min_by(items, & &1["unitPrice"]) end)
      |> Enum.sort_by(& &1["unitPrice"])
      |> Enum.take(count)
      |> Enum.map(fn item ->
        hr = item["unitPrice"]
        sku = item["armSkuName"] || ""

        [
          sku,
          item["armRegionName"] || "",
          sku_spec(sku, :vcpu),
          sku_spec(sku, :ram),
          sku_spec(sku, :storage),
          "$#{fmt(hr)}",
          "$#{fmt(hr * 730, 2)}"
        ]
      end)

    headers = ["SKU", "Region", "vCPU", "RAM(GiB)", "Disk(GiB)", "$/hr", "$/month"]
    print_aligned([headers | rows])
  end

  defp print_aligned(rows) do
    col_count = rows |> List.first() |> length()

    widths =
      for col <- 0..(col_count - 1) do
        rows |> Enum.map(&(Enum.at(&1, col) |> to_string() |> String.length())) |> Enum.max()
      end

    for row <- rows do
      row
      |> Enum.zip(widths)
      |> Enum.map(fn {cell, width} -> String.pad_trailing(to_string(cell), width) end)
      |> Enum.join("  ")
      |> IO.puts()
    end

    IO.puts("")
  end
end

VmPricing.main()
