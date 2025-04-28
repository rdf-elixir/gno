defmodule Gno.Manifest.GeneratorTest do
  use GnoCase

  doctest Gno.Manifest.Generator

  alias Gno.Manifest.{Generator, GeneratorError}
  alias Gno.Store.Adapters.{Fuseki, Oxigraph}

  @moduletag :tmp_dir

  setup context do
    project_dir = context.tmp_dir
    manifest_dir = "config/gno"
    on_exit(fn -> File.rm_rf!(project_dir) end)
    {:ok, project_dir: project_dir, manifest_dir: manifest_dir}
  end

  @all_adapters [Store, Fuseki, Oxigraph]

  describe "manifest_dir/1" do
    test "with default options" do
      assert Generator.manifest_dir() == {:ok, "config/gno"}
    end

    test "with load_path option" do
      assert Generator.manifest_dir(load_path: ["path1", "path2"]) == {:ok, "path2"}
    end

    test "with absolute paths" do
      assert {:error, %GeneratorError{message: message}} =
               Generator.manifest_dir(load_path: ["/path1", "/absolute/path"])

      assert message =~ "Cannot use absolute path as manifest directory: /absolute/path"
      assert message =~ "must be relative to the project directory"
    end
  end

  describe "generate/3" do
    test "initializes service config without adapter", %{
      project_dir: project_dir,
      manifest_dir: manifest_dir
    } do
      assert :ok = Generator.generate(Gno.Manifest, project_dir)

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
      assert :ok = Generator.generate(Gno.Manifest, project_dir, adapter: Fuseki)

      assert_files_generated(Path.join(project_dir, manifest_dir))

      assert_selected_adapter(
        Path.join([project_dir, manifest_dir, "service.ttl"]),
        Fuseki,
        @all_adapters -- [Fuseki]
      )

      File.rm_rf!(Path.join(project_dir, manifest_dir))

      assert :ok = Generator.generate(Gno.Manifest, project_dir, adapter: Oxigraph)

      assert_files_generated(Path.join(project_dir, manifest_dir))

      assert_selected_adapter(
        Path.join([project_dir, manifest_dir, "service.ttl"]),
        Oxigraph,
        @all_adapters -- [Oxigraph]
      )
    end

    test "with unknown adapter", %{project_dir: project_dir} do
      assert {:error, %GeneratorError{message: "Invalid store adapter: :unknown" <> _}} =
               Generator.generate(Gno.Manifest, project_dir, adapter: :unknown)
    end

    test "with existing directory", %{project_dir: project_dir, manifest_dir: manifest_dir} do
      File.mkdir_p!(Path.join(project_dir, manifest_dir))

      assert {:error, %GeneratorError{message: "Manifest directory already exists: " <> _}} =
               Generator.generate(Gno.Manifest, project_dir)
    end

    test "with force flag and existing directory", %{
      project_dir: project_dir,
      manifest_dir: manifest_dir
    } do
      manifest_path = Path.join(project_dir, manifest_dir)
      File.mkdir_p!(manifest_path)
      existing_file = Path.join(manifest_path, "dataset.ttl")
      File.write!(existing_file, "Original content")

      assert :ok = Generator.generate(Gno.Manifest, project_dir, force: true)

      refute File.read!(existing_file) == "Original content"
    end

    test "custom template with custom assigns in EEx templates", %{
      project_dir: project_dir,
      manifest_dir: manifest_dir
    } do
      custom_template_dir = Path.join(project_dir, "custom_template")
      File.mkdir_p!(custom_template_dir)
      File.write!(Path.join(custom_template_dir, "custom.ttl.eex"), "<%= @custom_value %>")

      assert :ok =
               Generator.generate(
                 Gno.Manifest,
                 project_dir,
                 template: custom_template_dir,
                 adapter: Fuseki,
                 assigns: [custom_value: "Test"]
               )

      content = File.read!(Path.join([project_dir, manifest_dir, "custom.ttl"]))
      assert content == "Test"
    end

    test "with non-existent template directory", %{project_dir: project_dir} do
      assert {:error, %GeneratorError{message: "Template does not exist: " <> _}} =
               Generator.generate(Gno.Manifest, project_dir, template: "non/existent/dir")
    end
  end

  defp assert_files_generated(manifest_dir) do
    assert File.exists?(Path.join(manifest_dir, "service.ttl"))
    assert File.exists?(Path.join(manifest_dir, "repository.ttl"))
    assert File.exists?(Path.join(manifest_dir, "dataset.ttl"))
    assert File.exists?(Path.join(manifest_dir, "store.ttl"))
    assert File.exists?(Path.join(manifest_dir, "fuseki.ttl"))
    assert File.exists?(Path.join(manifest_dir, "oxigraph.ttl"))
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
