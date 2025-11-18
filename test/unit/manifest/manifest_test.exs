defmodule Gno.ManifestTest do
  use GnoCase

  doctest Gno.Manifest

  alias Gno.Manifest
  alias Gno.{Service, Store}
  alias Gno.Store.Adapters.{Oxigraph, Fuseki, GraphDB}
  alias DCATR.{Repository, Dataset}

  @configured_store_adapter configured_store_adapter()

  describe "store loading with test manifest" do
    setup do
      [load_path: TestData.manifest("flat_dir")]
    end

    test "service/0 returns service with store field", %{load_path: load_path} do
      assert {:ok,
              %Service{
                repository: %Repository{
                  dataset: %Dataset{}
                },
                store: %Fuseki{}
              }} = Manifest.service(load_path: load_path)
    end

    test "store/0 extracts store from service", %{load_path: load_path} do
      assert {:ok, %Fuseki{}} = Manifest.store(load_path: load_path)
    end
  end

  describe "store loading with default manifest" do
    test "service/0 returns service with configured store adapter" do
      assert {:ok,
              %Service{
                repository: %Repository{
                  dataset: %Dataset{}
                },
                store: %@configured_store_adapter{}
              }} = Manifest.service()
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

  describe "commit operation configuration" do
    test "custom commit operation with middleware chain" do
      load_path = [
        TestData.manifest("single_file.trig"),
        TestData.manifest("commit_config/custom_commit_operation_with_middleware.trig")
      ]

      assert {:ok,
              %Gno.Manifest{
                service: %Service{
                  commit_operation: %TestCommitOperation{
                    middlewares: [
                      %Gno.CommitLogger{log_level: "info", log_states: ["all"]},
                      %TestStateFlowMiddleware{label: "first"},
                      %TestStateFlowMiddleware{label: "second"}
                    ]
                  }
                }
              }} = DCATR.Manifest.Loader.load(Gno.Manifest, load_path: load_path)
    end

    test "custom commit operation as class" do
      load_path = [
        TestData.manifest("single_file.trig"),
        TestData.manifest("commit_config/custom_commit_operation_as_class.trig")
      ]

      assert {:ok,
              %Gno.Manifest{
                service: %Service{
                  commit_operation: %TestCommitOperation{}
                }
              }} = DCATR.Manifest.Loader.load(Gno.Manifest, load_path: load_path)
    end

    test "commit middleware as class" do
      load_path = [
        TestData.manifest("single_file.trig"),
        TestData.manifest("commit_config/commit_operation_with_middleware_as_class.trig")
      ]

      assert {:ok,
              %Gno.Manifest{
                service: %Service{
                  commit_operation: %Gno.CommitOperation{
                    middlewares: [
                      %TestStateFlowMiddleware{label: "default"},
                      %Gno.CommitLogger{log_level: "info"}
                    ]
                  }
                }
              }} = DCATR.Manifest.Loader.load(Gno.Manifest, load_path: load_path)
    end

    test "custom commit operation with middleware as class" do
      load_path = [
        TestData.manifest("single_file.trig"),
        TestData.manifest("commit_config/custom_commit_operation_with_middleware_as_class.trig")
      ]

      assert {:ok,
              %Gno.Manifest{
                service: %Service{
                  commit_operation: %TestCommitOperation{
                    middlewares: [
                      %TestStateFlowMiddleware{label: "default"},
                      %Gno.CommitLogger{log_level: "info"}
                    ]
                  }
                }
              }} = DCATR.Manifest.Loader.load(Gno.Manifest, load_path: load_path)
    end
  end
end
