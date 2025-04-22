defmodule Gno.Manifest.LoadPathTest do
  use GnoCase, async: true

  doctest Gno.Manifest.LoadPath

  alias Gno.Manifest.LoadPath

  @moduletag :tmp_dir

  describe "load_path/1" do
    test "returns default path" do
      assert LoadPath.load_path() == ["config/gno"]
    end

    test "returns configured path" do
      assert LoadPath.load_path(load_path: ["custom/path"]) == ["custom/path"]
    end

    test "wraps single path in list" do
      assert LoadPath.load_path(load_path: "custom/path") == ["custom/path"]
    end

    test "uses application config" do
      with_application_env(:gno, :load_path, ["app/config/path"], fn ->
        assert LoadPath.load_path() == ["app/config/path"]
      end)
    end
  end

  describe "files/1" do
    setup %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "prod"))
      File.mkdir_p!(Path.join(tmp_dir, "dev"))
      File.mkdir_p!(Path.join(tmp_dir, "test"))

      files =
        %{
          manifest_file: Path.join(tmp_dir, "manifest.ttl"),
          prod_file: Path.join(tmp_dir, "prod/specific.ttl"),
          prod_suffix_file: Path.join(tmp_dir, "manifest.prod.rdf"),
          dev_file: Path.join(tmp_dir, "dev/specific.ttl"),
          dev_suffix_file: Path.join(tmp_dir, "manifest.dev.ttl"),
          test_file: Path.join(tmp_dir, "test/specific.ttl"),
          test_suffix_file: Path.join(tmp_dir, "manifest.test.ttl"),
          ignored_file: Path.join(tmp_dir, "_ignored.ttl")
        }

      Enum.each(files, fn {_, path} -> File.touch!(path) end)

      on_exit(fn ->
        File.rm_rf!(tmp_dir)
      end)

      files
    end

    test "finds all relevant files for prod environment", %{tmp_dir: tmp_dir} = ctx do
      files = LoadPath.files(env: :prod, load_path: [tmp_dir])

      assert ctx.manifest_file in files
      assert ctx.prod_file in files
      assert ctx.prod_suffix_file in files
      refute ctx.dev_file in files
      refute ctx.dev_suffix_file in files
      refute ctx.test_file in files
      refute ctx.test_suffix_file in files
      refute ctx.ignored_file in files
    end

    test "finds all relevant files for dev environment", %{tmp_dir: tmp_dir} = ctx do
      files = LoadPath.files(env: :dev, load_path: [tmp_dir])

      assert ctx.manifest_file in files
      assert ctx.dev_file in files
      assert ctx.dev_suffix_file in files
      refute ctx.prod_file in files
      refute ctx.prod_suffix_file in files
      refute ctx.test_file in files
      refute ctx.test_suffix_file in files
      refute ctx.ignored_file in files
    end

    test "finds all relevant files for test environment", %{tmp_dir: tmp_dir} = ctx do
      files = LoadPath.files(env: :test, load_path: [tmp_dir])

      assert ctx.manifest_file in files
      assert ctx.test_file in files
      assert ctx.test_suffix_file in files
      refute ctx.prod_file in files
      refute ctx.prod_suffix_file in files
      refute ctx.dev_file in files
      refute ctx.dev_suffix_file in files
      refute ctx.ignored_file in files
    end

    test "supports all RDF serialization formats", %{tmp_dir: tmp_dir} do
      files =
        for ext <- RDF.Serialization.formats() |> Enum.map(& &1.extension()) do
          path = Path.join(tmp_dir, "test.#{ext}")
          File.write!(path, "")
          path
        end

      found_files = LoadPath.files(load_path: [tmp_dir])

      for file <- files do
        assert file in found_files
      end
    end

    test "handles missing directories" do
      assert LoadPath.files(load_path: ["non/existent/path"]) == []
    end

    test "handles file paths", ctx do
      assert LoadPath.files(load_path: [ctx.manifest_file]) == [ctx.manifest_file]
    end
  end
end
