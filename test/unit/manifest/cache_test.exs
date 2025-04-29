defmodule Gno.Manifest.CacheTest do
  use GnoCase

  doctest Gno.Manifest.Cache

  alias Gno.Manifest
  alias Gno.Manifest.{Cache, LoadingError}

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    :ok
  end

  describe "manifest/2" do
    test "loads and caches a manifest", %{tmp_dir: tmp_dir} do
      assert {:ok, default_manifest} = Cache.manifest(Manifest)
      assert {:ok, ^default_manifest} = Cache.manifest(Manifest)

      %{manifest_file: manifest_file, load_path: load_path} = setup_manifest(tmp_dir)

      assert {:ok, manifest} = Cache.manifest(Manifest, load_path: load_path)
      assert manifest != default_manifest

      modify(manifest_file)

      assert {:ok, ^manifest} = Cache.manifest(Manifest, load_path: load_path)
      assert {:ok, new_manifest} = Cache.manifest(Manifest, load_path: load_path, reload: true)
      assert manifest != new_manifest
      assert manifest != new_manifest
    end

    test "handles errors from loader" do
      assert {:error, %LoadingError{reason: :missing}} =
               Cache.manifest(Manifest, load_path: "non_existent_path")
    end
  end

  describe "clear/0" do
    test "removes all entries from the cache", %{tmp_dir: tmp_dir} do
      %{manifest_file: manifest_file, load_path: load_path} = setup_manifest(tmp_dir)

      assert {:ok, manifest} = Cache.manifest(Manifest, load_path: load_path)

      modify(manifest_file)

      assert :ok = Cache.clear()

      assert {:ok, new_manifest} = Cache.manifest(Manifest, load_path: load_path)
      assert manifest != new_manifest
    end
  end

  describe "invalidate/2" do
    test "invalidates specific manifest type with specific load path", %{tmp_dir: tmp_dir} do
      %{manifest_file: manifest_file1, load_path: load_path1} = setup_manifest(tmp_dir, "dir1")
      %{manifest_file: manifest_file2, load_path: load_path2} = setup_manifest(tmp_dir, "dir2")

      assert {:ok, manifest1} = Cache.manifest(Manifest, load_path: load_path1)
      assert {:ok, manifest2} = Cache.manifest(Manifest, load_path: load_path2)

      modify(manifest_file1)
      modify(manifest_file2)

      assert :ok = Cache.invalidate(Manifest, load_path: load_path1)

      assert {:ok, new_manifest1} = Cache.manifest(Manifest, load_path: load_path1)
      assert {:ok, ^manifest2} = Cache.manifest(Manifest, load_path: load_path2)

      assert manifest1 != new_manifest1
    end
  end

  defp setup_manifest(tmp_dir, subdir \\ nil) do
    dir = if subdir, do: Path.join(tmp_dir, subdir), else: tmp_dir
    File.mkdir_p!(dir)

    manifest_file = Path.join(dir, "manifest.ttl")
    File.cp!(TestData.manifest("single_file.ttl"), manifest_file)

    %{manifest_file: manifest_file, load_path: dir}
  end

  defp modify(manifest_file) do
    File.write!(
      manifest_file,
      "<http://example.com/Repository> <http://purl.org/dc/elements/1.1/title> \"new title\" .",
      [:append]
    )
  end
end
