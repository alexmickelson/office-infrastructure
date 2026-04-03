#!/usr/bin/env nix-shell
#!nix-shell -i elixir -p elixir azure-cli

original_gl = Process.group_leader()
{:ok, devnull} = File.open("/dev/null", [:write])
Process.group_leader(self(), devnull)
Mix.install([{:req, "~> 0.5"}, {:jason, "~> 1.4"}])
Process.group_leader(self(), original_gl)
File.close(devnull)

defmodule VmPricing do
  @base_url "https://prices.azure.com/api/retail/prices"
  @arm_base "https://management.azure.com"

  # @us_regions ~w[
  #   eastus eastus2 westus westus2 westus3
  # ]

  @us_regions ~w[
    westus3
  ]

  @opts %{
    # --- arm_compare mode ---
    # true  = show cheapest x86_prefix SKUs vs ARM64 SKUs side by side
    # false = show single table (uses sku_prefix below)
    arm_compare: true,
    # x86 family to pull for left-hand side
    x86_prefix: "Standard_A",
    # search space for right-hand side (filtered to Arm64 by arch)
    arm_search_prefix: "Standard_D",

    # --- single-table mode (arm_compare: false) ---
    # e.g. "Standard_A" or "Standard_D" or nil for any
    sku_prefix: "Standard_A",

    region: nil,
    # "linux" | "windows"
    os: "linux",
    # "payg" | "spot" | "reserved"
    price_type: "payg",
    count: 10,
    # minimum vCPU count (nil = no minimum)
    min_vcpu: 2,
    # show cheapest SKU per region
    compare: false,
    # false = US regions only
    all_regions: false,
    # fetch real specs from ARM Resource SKUs API (requires az login)
    arm_specs: true,
    # show $/vCPU and $/GiB columns
    show_ratios: true
  }

  def main do
    opts = @opts

    IO.puts("Querying Azure VM pricing...")
    IO.puts("  SKU prefix : #{opts.sku_prefix || "any"}")
    IO.puts("  Region     : #{opts.region || "all regions"}")
    IO.puts("  OS         : #{opts.os}")
    IO.puts("  Price type : #{opts.price_type}")
    IO.puts("  ARM specs  : #{opts.arm_specs}")

    regions_label =
      cond do
        Map.get(opts, :all_regions) -> "all"
        Map.get(opts, :region) -> Map.get(opts, :region)
        true -> "US only (#{Enum.join(@us_regions, " ")})"
      end

    IO.puts("  Regions    : #{regions_label}")
    IO.puts("  Results    : #{opts.count}")
    IO.puts("  Min vCPUs  : #{opts.min_vcpu || "any"}")

    sku_specs =
      if opts.arm_specs do
        spec_region = opts.region || hd(@us_regions)
        IO.puts("\nFetching ARM SKU specs for #{spec_region}...")

        case fetch_arm_specs(spec_region) do
          {:ok, specs} ->
            IO.puts("  Loaded #{map_size(specs)} SKU specs from ARM API\n")
            specs

          {:error, reason} ->
            IO.puts("  Warning: ARM specs unavailable (#{reason}), falling back to hardcoded specs\n")
            hardcoded_specs()
        end
      else
        hardcoded_specs()
      end

    if opts.arm_compare do
      run_arm_compare(sku_specs, opts)
    else
      data = fetch_prices(opts)
      valid = filter_valid(data, sku_specs, opts)

      if Enum.empty?(valid) do
        IO.puts("No results found. Try broadening your filters.")
        System.halt(1)
      end

      IO.puts("  Found      : #{length(valid)} entries\n")

      if opts.compare do
        compare_regions(valid, sku_specs, opts)
      else
        render_table(valid, sku_specs, opts)
      end
    end
  end

  defp filter_valid(data, sku_specs, opts) do
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

      case Map.get(sku_specs, sku) do
        nil -> is_nil(min)
        spec -> is_nil(min) or spec.vcpu >= min
      end
    end)
  end

  defp run_arm_compare(sku_specs, opts) do
    IO.puts("=== Cheapest x86 (#{opts.x86_prefix}*) vs ARM64 (#{opts.arm_search_prefix}* Arm64) ===")
    IO.puts("    Region: #{opts.region || Enum.join(@us_regions, ", ")}  |  Min vCPUs: #{opts.min_vcpu || "any"}  |  Top #{opts.count} each\n")

    x86_valid =
      %{opts | sku_prefix: opts.x86_prefix}
      |> fetch_prices()
      |> filter_valid(sku_specs, opts)

    arm_valid =
      %{opts | sku_prefix: opts.arm_search_prefix}
      |> fetch_prices()
      |> Enum.filter(fn item ->
        case Map.get(sku_specs, item["armSkuName"] || "") do
          %{arch: "Arm64"} -> true
          _ -> false
        end
      end)
      |> filter_valid(sku_specs, opts)

    IO.puts("--- x86: #{opts.x86_prefix}* (#{length(x86_valid)} matching entries) ---")
    render_table(x86_valid, sku_specs, opts)

    IO.puts("--- ARM64 (#{length(arm_valid)} matching entries) ---")
    render_table(arm_valid, sku_specs, opts)
  end

  # --- ARM SKU Specs ---

  defp fetch_arm_specs(region) do
    with {:ok, token} <- get_arm_token(),
         {:ok, sub_id} <- get_subscription_id() do
      url =
        "#{@arm_base}/subscriptions/#{sub_id}/providers/Microsoft.Compute/skus" <>
          "?api-version=2021-07-01&$filter=location+eq+'#{region}'"

      headers = [{"Authorization", "Bearer #{token}"}, {"Content-Type", "application/json"}]

      case Req.get(url, headers: headers) do
        {:ok, %{status: 200, body: body}} ->
          specs =
            (body["value"] || [])
            |> Enum.filter(&(&1["resourceType"] == "virtualMachines"))
            |> Enum.reduce(%{}, fn sku, acc ->
              name = sku["name"]
              caps = parse_capabilities(sku["capabilities"] || [])
              vcpu = parse_int(caps["vCPUs"])
              ram = parse_float(caps["MemoryGB"])
              # MaxResourceVolumeMB = local/temp SSD (e.g. 40960 MB → 40 GiB for A4_v2)
              # OSDiskSizeInMB is just the max OS-disk cap (~1 TB), not useful here
              temp_mb = parse_int(caps["MaxResourceVolumeMB"])
              disk_gb = if temp_mb && temp_mb > 0, do: div(temp_mb, 1024), else: 0
              arch = caps["CpuArchitectureType"] || "x86_64"

              if vcpu && ram do
                Map.put(acc, name, %{vcpu: vcpu, ram: ram, storage: disk_gb, arch: arch})
              else
                acc
              end
            end)

          {:ok, specs}

        {:ok, %{status: status}} ->
          {:error, "HTTP #{status}"}

        {:error, reason} ->
          {:error, inspect(reason)}
      end
    end
  end

  defp parse_capabilities(caps) do
    Enum.reduce(caps, %{}, fn %{"name" => k, "value" => v}, acc -> Map.put(acc, k, v) end)
  end

  defp get_arm_token do
    case System.cmd(
           "az",
           ["account", "get-access-token", "--resource", "https://management.azure.com",
            "--query", "accessToken", "-o", "tsv"],
           stderr_to_stdout: false
         ) do
      {token, 0} -> {:ok, String.trim(token)}
      {err, _} -> {:error, "az token: #{String.trim(err)}"}
    end
  end

  defp get_subscription_id do
    case System.cmd("az", ["account", "show", "--query", "id", "-o", "tsv"],
           stderr_to_stdout: false) do
      {id, 0} -> {:ok, String.trim(id)}
      {err, _} -> {:error, "az sub: #{String.trim(err)}"}
    end
  end

  defp parse_int(nil), do: nil

  defp parse_int(s) do
    case Integer.parse(to_string(s)) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_float(nil), do: nil

  defp parse_float(s) do
    case Float.parse(to_string(s)) do
      {f, _} -> f
      :error -> nil
    end
  end

  # Fallback hardcoded specs (A-series only)
  defp hardcoded_specs do
    %{
      "Standard_A0" => %{vcpu: 1, ram: 0.75, storage: 20},
      "Standard_A1" => %{vcpu: 1, ram: 1.75, storage: 70},
      "Standard_A2" => %{vcpu: 2, ram: 3.5, storage: 135},
      "Standard_A3" => %{vcpu: 4, ram: 7.0, storage: 285},
      "Standard_A4" => %{vcpu: 8, ram: 14.0, storage: 605},
      "Standard_A1_v2" => %{vcpu: 1, ram: 2.0, storage: 10},
      "Standard_A2_v2" => %{vcpu: 2, ram: 4.0, storage: 20},
      "Standard_A4_v2" => %{vcpu: 4, ram: 8.0, storage: 40},
      "Standard_A8_v2" => %{vcpu: 8, ram: 16.0, storage: 80}
    }
  end

  # --- Pricing API ---

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

  # --- Formatting ---

  defp fmt(price, decimals \\ 4),
    do: :erlang.float_to_binary(price * 1.0, [{:decimals, decimals}])

  defp sku_val(sku_specs, sku, key, default \\ "?") do
    case Map.get(sku_specs, sku) do
      nil -> default
      spec -> Map.get(spec, key, default) |> to_string()
    end
  end

  defp os_label(product_name) do
    if String.contains?(product_name, "Windows"), do: "Windows", else: "Linux"
  end

  defp ratio(price, sku_specs, sku, key) do
    case Map.get(sku_specs, sku) do
      nil ->
        "?"

      spec ->
        val = Map.get(spec, key)
        if val && val > 0, do: "$#{fmt(price / val, 4)}", else: "?"
    end
  end

  defp build_row(item, sku_specs, include_os, show_ratios) do
    hr = item["unitPrice"]
    sku = item["armSkuName"] || ""

    base = [sku, item["armRegionName"] || ""]
    base = if include_os, do: base ++ [os_label(item["productName"] || "")], else: base

    base =
      base ++
        [
          sku_val(sku_specs, sku, :vcpu),
          sku_val(sku_specs, sku, :ram),
          sku_val(sku_specs, sku, :storage),
          "$#{fmt(hr)}",
          "$#{fmt(hr * 730, 2)}"
        ]

    if show_ratios,
      do: base ++ [ratio(hr, sku_specs, sku, :vcpu), ratio(hr, sku_specs, sku, :ram)],
      else: base
  end

  defp build_headers(include_os, show_ratios) do
    base = ["SKU", "Region"]
    base = if include_os, do: base ++ ["OS"], else: base
    base = base ++ ["vCPU", "RAM(GiB)", "Disk(GiB)", "$/hr", "$/month"]
    if show_ratios, do: base ++ ["$/vCPU/hr", "$/GiB/hr"], else: base
  end

  defp render_table(data, sku_specs, opts) do
    rows =
      data
      |> Enum.sort_by(& &1["unitPrice"])
      |> Enum.take(opts.count)
      |> Enum.map(&build_row(&1, sku_specs, true, opts.show_ratios))

    print_aligned([build_headers(true, opts.show_ratios) | rows])
  end

  defp print_table(data, sku_specs, opts), do: render_table(data, sku_specs, opts)

  defp compare_regions(data, sku_specs, opts) do
    rows =
      data
      |> Enum.group_by(& &1["armRegionName"])
      |> Enum.map(fn {_region, items} -> Enum.min_by(items, & &1["unitPrice"]) end)
      |> Enum.sort_by(& &1["unitPrice"])
      |> Enum.take(opts.count)
      |> Enum.map(&build_row(&1, sku_specs, false, opts.show_ratios))

    print_aligned([build_headers(false, opts.show_ratios) | rows])
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
