defmodule Gno.ManifestTest do
  use GnoCase

  doctest Gno.Manifest

  alias Gno.Manifest
  alias Gno.{Service, Store, Repository, Dataset}
  alias Gno.Store.Adapters.{Oxigraph, Fuseki, GraphDB}

  import RDF.Sigils

  @configured_store_adapter configured_store_adapter()

  describe "env/1" do
    test "returns configured environment" do
      assert Manifest.env(env: :prod) == :prod
      assert Manifest.env(env: :dev) == :dev
      assert Manifest.env(env: :test) == :test
    end

    test "accepts string environments" do
      assert Manifest.env(env: "PROD") == :prod
      assert Manifest.env(env: "prod") == :prod
    end

    test "reads from GNO_ENV" do
      System.put_env("GNO_ENV", "prod")
      assert Manifest.env() == :prod
      System.delete_env("GNO_ENV")
    end

    test "falls back to MIX_ENV" do
      System.put_env("MIX_ENV", "dev")
      assert Manifest.env() == :dev
      System.delete_env("MIX_ENV")
    end

    test "raises on invalid environment" do
      assert_raise RuntimeError, ~r/Invalid environment/, fn ->
        Manifest.env(env: :invalid)
      end
    end
  end

  describe "with test manifest" do
    setup do
      [load_path: TestData.manifest("flat_dir")]
    end

    test "service/0", %{load_path: load_path} do
      assert {:ok,
              %Service{
                repository: %Repository{
                  dataset: %Dataset{}
                },
                store: %Fuseki{}
              }} = Manifest.service(load_path: load_path)
    end

    test "repository/0", %{load_path: load_path} do
      assert {:ok, %Repository{dataset: %Dataset{}}} =
               Manifest.repository(load_path: load_path)
    end

    test "dataset/0", %{load_path: load_path} do
      assert {:ok,
              %Dataset{
                __additional_statements__: %{
                  ~I<http://purl.org/dc/terms/title> => %{~L"test dataset" => nil}
                }
              }} = Manifest.dataset(load_path: load_path)
    end

    test "store/0", %{load_path: load_path} do
      assert {:ok, %Fuseki{}} = Manifest.store(load_path: load_path)
    end
  end

  describe "with default manifest" do
    test "service/0" do
      assert {:ok,
              %Service{
                repository: %Repository{
                  dataset: %Dataset{}
                },
                store: %@configured_store_adapter{}
              }} = Manifest.service()
    end

    test "repository/0" do
      assert {:ok, %Repository{dataset: %Dataset{}}} = Manifest.repository()
    end

    test "dataset/0" do
      assert {:ok,
              %Dataset{
                __additional_statements__: %{
                  ~I<http://purl.org/dc/terms/title> => %{~L"test dataset" => nil}
                }
              }} = Manifest.dataset()
    end

    case @configured_store_adapter do
      Store ->
        test "store/0 with generic store" do
          assert {:ok, %Store{}} = Manifest.store()
        end

      Fuseki ->
        test "store/0 with Fuseki adapter" do
          assert {:ok,
                  %Fuseki{
                    port: 3030,
                    dataset: "gno-test-dataset"
                  }} = Manifest.store()
        end

      Oxigraph ->
        test "store/0 with Oxigraph adapter" do
          assert {:ok, %Oxigraph{port: 7879}} = Manifest.store()
        end

      GraphDB ->
        test "store/0 with GraphDB adapter" do
          assert {:ok, %GraphDB{port: 7200}} = Manifest.store()
        end
    end
  end
end
