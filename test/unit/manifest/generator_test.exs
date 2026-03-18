defmodule Gno.Manifest.GeneratorTest do
  use GnoCase

  doctest Gno.Manifest.Generator

  alias Gno.Manifest
  alias DCATR.Manifest.GeneratorError

  @moduletag :tmp_dir

  setup context do
    project_dir = context.tmp_dir
    manifest_dir = "config/gno"
    on_exit(fn -> File.rm_rf!(project_dir) end)
    {:ok, project_dir: project_dir, manifest_dir: manifest_dir}
  end

  @all_adapters [Store, Fuseki, Oxigraph, Qlever]

  describe "Gno.Manifest.generate/3" do
    test "initializes service config without adapter", %{
      project_dir: project_dir,
      manifest_dir: manifest_dir
    } do
      assert :ok = Manifest.generate(project_dir)

      assert_files_generated(Path.join(project_dir, manifest_dir))

      assert_selected_adapter(
        Path.join([project_dir, manifest_dir, "service.ttl"]),
        Store,
        @all_adapters -- [Store]
      )
    end

    test "initializes service config with adapter", %{
      project_dir: project_dir,
      manifest_dir: manifest_dir
    } do
      assert :ok = Manifest.generate(project_dir, adapter: Fuseki)

      assert_files_generated(Path.join(project_dir, manifest_dir))

      assert_selected_adapter(
        Path.join([project_dir, manifest_dir, "service.ttl"]),
        Fuseki,
        @all_adapters -- [Fuseki]
      )

      File.rm_rf!(Path.join(project_dir, manifest_dir))

      assert :ok = Manifest.generate(project_dir, adapter: Oxigraph)

      assert_files_generated(Path.join(project_dir, manifest_dir))

      assert_selected_adapter(
        Path.join([project_dir, manifest_dir, "service.ttl"]),
        Oxigraph,
        @all_adapters -- [Oxigraph]
      )

      File.rm_rf!(Path.join(project_dir, manifest_dir))

      assert :ok = Manifest.generate(project_dir, adapter: Qlever)

      assert_files_generated(Path.join(project_dir, manifest_dir))

      assert_selected_adapter(
        Path.join([project_dir, manifest_dir, "service.ttl"]),
        Qlever,
        @all_adapters -- [Qlever]
      )
    end

    test "with unknown adapter", %{project_dir: project_dir} do
      assert {:error, %GeneratorError{message: "Invalid store adapter: :unknown" <> _}} =
               Manifest.generate(project_dir, adapter: :unknown)
    end
  end

  defp assert_files_generated(manifest_dir) do
    assert File.exists?(Path.join(manifest_dir, "service.ttl"))
    assert File.exists?(Path.join(manifest_dir, "repository.ttl"))
    assert File.exists?(Path.join(manifest_dir, "dataset.ttl"))
    assert File.exists?(Path.join(manifest_dir, "store.ttl"))
    assert File.exists?(Path.join(manifest_dir, "fuseki.ttl"))
    assert File.exists?(Path.join(manifest_dir, "oxigraph.ttl"))
    assert File.exists?(Path.join(manifest_dir, "qlever.ttl"))
  end

  defp assert_selected_adapter(file, selected_adapter, disabled_adapters) do
    lines =
      file
      |> File.read!()
      |> String.split("\n")

    configured_adapters =
      lines
      |> Enum.map(fn line ->
        case Regex.run(~r/gno:serviceStore <([a-zA-Z]+)>/, line) do
          [_, adapter] ->
            {
              case adapter do
                "Store" ->
                  Store

                adapter_class ->
                  assert adapter = Store.Adapter.type(adapter_class)
                  adapter
              end,
              not (line |> String.trim_leading() |> String.starts_with?("#"))
            }

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    assert configured_adapters[selected_adapter]

    Enum.each(disabled_adapters, fn disabled_adapter ->
      assert Map.has_key?(configured_adapters, disabled_adapter)
      assert configured_adapters[disabled_adapter] == false
    end)
  end
end
