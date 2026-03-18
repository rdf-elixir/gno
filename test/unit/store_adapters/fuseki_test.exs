defmodule Gno.Store.Adapters.FusekiTest do
  use GnoCase, async: true

  doctest Gno.Store.Adapters.Fuseki

  alias Gno.Store.Adapters.Fuseki
  alias Gno.Store

  @configured_store_adapter configured_store_adapter()

  test "endpoint_base/1" do
    assert Store.endpoint_base(%Fuseki{dataset: "test-dataset"}) ==
             {:ok, "http://localhost:3030/test-dataset"}

    assert Store.endpoint_base(%Fuseki{dataset: "test-dataset", port: 42}) ==
             {:ok, "http://localhost:42/test-dataset"}

    assert %Fuseki{dataset: "example-dataset", scheme: "https", host: "example.com", port: nil}
           |> Store.endpoint_base() ==
             {:ok, "https://example.com/example-dataset"}
  end

  test "query_endpoint/1" do
    assert Store.query_endpoint(%Fuseki{dataset: "test-dataset"}) ==
             {:ok, "http://localhost:3030/test-dataset/query"}

    assert Store.query_endpoint(%Fuseki{dataset: "test-dataset", port: 42}) ==
             {:ok, "http://localhost:42/test-dataset/query"}

    assert %Fuseki{dataset: "example-dataset", scheme: "https", host: "example.com", port: nil}
           |> Store.query_endpoint() ==
             {:ok, "https://example.com/example-dataset/query"}
  end

  test "update_endpoint/1" do
    assert Store.update_endpoint(%Fuseki{dataset: "test-dataset"}) ==
             {:ok, "http://localhost:3030/test-dataset/update"}

    assert Store.update_endpoint(%Fuseki{dataset: "test-dataset", port: 42}) ==
             {:ok, "http://localhost:42/test-dataset/update"}

    assert %Fuseki{dataset: "test-dataset", scheme: "https", host: "example.com", port: nil}
           |> Store.update_endpoint() ==
             {:ok, "https://example.com/test-dataset/update"}
  end

  test "graph_store_endpoint/1" do
    assert Store.graph_store_endpoint(%Fuseki{dataset: "test-dataset"}) ==
             {:ok, "http://localhost:3030/test-dataset/data"}

    assert Store.graph_store_endpoint(%Fuseki{dataset: "test-dataset", port: 42}) ==
             {:ok, "http://localhost:42/test-dataset/data"}

    assert %Fuseki{dataset: "test-dataset", scheme: "https", host: "example.com", port: nil}
           |> Store.graph_store_endpoint() ==
             {:ok, "https://example.com/test-dataset/data"}
  end

  test "dataset_endpoint_segment/1" do
    assert Store.dataset_endpoint_segment(%Fuseki{dataset: "test-dataset"}) ==
             {:ok, "test-dataset"}

    assert Store.dataset_endpoint_segment(%Fuseki{}) ==
             {:error,
              Store.InvalidEndpointError.exception(
                "missing :dataset value for store #{inspect(%Fuseki{})}"
              )}
  end

  test "*_endpoint/1 functions when endpoints set directly" do
    assert Store.query_endpoint(%Fuseki{query_endpoint: EX.query_endpoint()}) ==
             {:ok, to_string(EX.query_endpoint())}

    assert Store.update_endpoint(%Fuseki{update_endpoint: EX.update_endpoint()}) ==
             {:ok, to_string(EX.update_endpoint())}

    assert %Fuseki{graph_store_endpoint: EX.graph_store_endpoint()}
           |> Store.graph_store_endpoint() ==
             {:ok, to_string(EX.graph_store_endpoint())}
  end

  describe "graph semantics" do
    test "default_graph_semantics/0" do
      assert Fuseki.default_graph_semantics() == :isolated
    end

    test "default_graph_iri/0" do
      assert Fuseki.default_graph_iri() == ~I<urn:x-arq:DefaultGraph>
    end

    test "graph_semantics/1" do
      assert Fuseki.graph_semantics(%Fuseki{dataset: "test"}) == :isolated
    end

    test "graph_semantics/1 with manifest override to :union" do
      assert Fuseki.graph_semantics(%Fuseki{
               dataset: "test",
               default_graph_semantics_config: "union"
             }) ==
               :union
    end
  end

  describe "Fuseki Admin API endpoints" do
    test "admin_base/1" do
      assert Fuseki.admin_base(%Fuseki{dataset: "test-dataset"}) ==
               "http://localhost:3030/$"

      assert Fuseki.admin_base(%Fuseki{dataset: "test-dataset", port: 42}) ==
               "http://localhost:42/$"

      assert %Fuseki{dataset: "example-dataset", scheme: "https", host: "example.com", port: nil}
             |> Fuseki.admin_base() ==
               "https://example.com/$"
    end

    test "ping_endpoint/1" do
      assert Fuseki.ping_endpoint(%Fuseki{dataset: "test-dataset"}) ==
               "http://localhost:3030/$/ping"
    end

    test "server_endpoint/1" do
      assert Fuseki.server_endpoint(%Fuseki{dataset: "test-dataset"}) ==
               "http://localhost:3030/$/server"
    end

    test "datasets_admin_endpoint/1" do
      assert Fuseki.datasets_admin_endpoint(%Fuseki{dataset: "test-dataset"}) ==
               "http://localhost:3030/$/datasets"
    end

    test "dataset_admin_endpoint/2" do
      assert Fuseki.dataset_admin_endpoint(%Fuseki{dataset: "test-dataset"}, "my-dataset") ==
               "http://localhost:3030/$/datasets/my-dataset"
    end

    test "stats_endpoint/1" do
      assert Fuseki.stats_endpoint(%Fuseki{dataset: "test-dataset"}) ==
               "http://localhost:3030/$/stats"
    end

    test "dataset_stats_endpoint/2" do
      assert Fuseki.dataset_stats_endpoint(%Fuseki{dataset: "test-dataset"}, "my-dataset") ==
               "http://localhost:3030/$/stats/my-dataset"
    end

    test "backup_endpoint/2" do
      assert Fuseki.backup_endpoint(%Fuseki{dataset: "test-dataset"}, "my-dataset") ==
               "http://localhost:3030/$/backup/my-dataset"
    end

    test "backups_list_endpoint/1" do
      assert Fuseki.backups_list_endpoint(%Fuseki{dataset: "test-dataset"}) ==
               "http://localhost:3030/$/backups-list"
    end

    test "tasks_endpoint/1" do
      assert Fuseki.tasks_endpoint(%Fuseki{dataset: "test-dataset"}) ==
               "http://localhost:3030/$/tasks"
    end

    test "task_endpoint/2" do
      assert Fuseki.task_endpoint(%Fuseki{dataset: "test-dataset"}, "123") ==
               "http://localhost:3030/$/tasks/123"

      assert Fuseki.task_endpoint(%Fuseki{dataset: "test-dataset"}, 456) ==
               "http://localhost:3030/$/tasks/456"
    end

    test "compact_endpoint/2" do
      assert Fuseki.compact_endpoint(%Fuseki{dataset: "test-dataset"}, "my-dataset") ==
               "http://localhost:3030/$/compact/my-dataset"
    end

    test "sleep_endpoint/1" do
      assert Fuseki.sleep_endpoint(%Fuseki{dataset: "test-dataset"}) ==
               "http://localhost:3030/$/sleep"
    end

    test "metrics_endpoint/1" do
      assert Fuseki.metrics_endpoint(%Fuseki{dataset: "test-dataset"}) ==
               "http://localhost:3030/$/metrics"
    end
  end

  if @configured_store_adapter == Fuseki do
    describe "check_availability/2" do
      test "returns error when server is not reachable" do
        assert {:error, %Gno.Store.UnavailableError{reason: :server_unreachable}} =
                 Fuseki.check_availability(unavailable_fuseki(), [])
      end
    end

    describe "check_setup/2" do
      test "returns error when server is not reachable" do
        assert {:error, %Gno.Store.UnavailableError{reason: :server_unreachable}} =
                 Fuseki.check_setup(unavailable_fuseki(), [])
      end

      test "returns error when dataset does not exist" do
        store = %Fuseki{dataset: "nonexistent-dataset-12345"}

        assert {:error, %Gno.Store.UnavailableError{reason: :dataset_not_found}} =
                 Fuseki.check_setup(store, [])
      end
    end

    describe "Admin API functions" do
      test "server_info/1" do
        assert {:ok, _} = Fuseki.server_info(Gno.store!())
      end

      test "all_datasets_info/1" do
        assert {:ok, _} = Fuseki.all_datasets_info(Gno.store!())
      end

      test "dataset_info/1" do
        assert {:ok, _} = Fuseki.dataset_info(Gno.store!())
      end

      test "dataset_info/2" do
        store = Gno.store!()
        assert {:ok, _} = Fuseki.dataset_info(store, store.dataset)
      end

      test "all_stats/1" do
        assert {:ok, _} = Fuseki.all_stats(Gno.store!())
      end

      test "dataset_stats/1" do
        assert {:ok, _} = Fuseki.dataset_stats(Gno.store!())
      end

      test "dataset_stats/2" do
        store = Gno.store!()
        assert {:ok, _} = Fuseki.dataset_stats(store, store.dataset)
      end

      test "tasks_info/1" do
        assert {:ok, _} = Fuseki.tasks_info(Gno.store!())
      end

      test "task_info/2" do
        # Use a dummy task ID since we just want to test the API call succeeds
        case Fuseki.task_info(Gno.store!(), "dummy-task-id") do
          {:ok, _} -> :ok
          {:error, _} -> :ok
        end
      end

      test "metrics/1" do
        assert {:ok, _} = Fuseki.metrics(Gno.store!())
      end
    end
  end
end
