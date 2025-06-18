defmodule Gno.ServiceTest do
  use Gno.StoreCase

  doctest Gno.Service

  alias Gno.Store.SPARQL.Operation

  describe "new/1" do
    test "with default commit operation" do
      assert {:ok, %Gno.Service{commit_operation: %Gno.CommitOperation{}}} =
               Service.new()
    end

    test "with commit operation as class" do
      assert {:ok, %Gno.Service{commit_operation: %TestCommitOperation{}}} =
               Service.new(commit_operation: EX.TestCommitOperation)
    end
  end

  describe "handle_sparql/4" do
    test "default graph" do
      assert EX.S
             |> EX.p(EX.O)
             |> RDF.graph()
             |> Operation.insert_data!()
             |> Service.handle_sparql(Manifest.service!(), graph: nil) ==
               :ok

      assert {:ok,
              %SPARQL.Query.Result{
                results: [
                  %{
                    "s" => ~I<http://example.com/S>,
                    "p" => ~I<http://example.com/p>,
                    "o" => ~I<http://example.com/O>
                  }
                ]
              }} =
               "SELECT * WHERE { ?s ?p ?o . }"
               |> Operation.select!()
               |> Service.handle_sparql(Manifest.service!(), graph: nil)
    end

    test "named graph" do
      assert EX.S
             |> EX.p(EX.O)
             |> RDF.graph()
             |> Operation.insert_data!()
             |> Service.handle_sparql(Manifest.service!()) ==
               :ok

      assert {:ok,
              %SPARQL.Query.Result{
                results: [
                  %{
                    "s" => ~I<http://example.com/S>,
                    "p" => ~I<http://example.com/p>,
                    "o" => ~I<http://example.com/O>
                  }
                ]
              }} =
               "SELECT * WHERE { ?s ?p ?o . }"
               |> Operation.select!()
               |> Service.handle_sparql(Manifest.service!(), graph: :dataset)

      graph =
        EX.S2
        |> EX.p(EX.O2)
        |> RDF.graph()

      assert graph
             |> Operation.insert_data!()
             |> Service.handle_sparql(Manifest.service!(), graph: :repo) ==
               :ok

      assert {:ok, result} =
               "CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o . }"
               |> Operation.construct!()
               |> Service.handle_sparql(Manifest.service!(), graph: :repo)

      # some triple stores (like Fuseki) add all known prefixes
      assert Graph.clear_prefixes(result) == graph
    end
  end

  describe "check_setup/1" do
    @describetag skip: !fuseki_available?(fuseki_store())

    setup context do
      test_name = context.test |> Atom.to_string() |> String.replace(~r/[^a-zA-Z0-9]/, "-")
      dataset_name = "check-test-#{test_name}"
      test_store = fuseki_store(dataset_name)
      test_service = alt_service(service(), store: test_store)

      on_exit(fn ->
        Gno.Store.Adapters.Fuseki.teardown(test_store, [])
      end)

      {:ok, service: test_service, store: test_store}
    end

    test "returns error before setup", %{service: service} do
      # Prepare dataset so the query can execute, but don't setup repository
      :ok = Gno.Store.Adapters.Fuseki.setup(service.store, [])
      assert {:error, :repository_not_found} = Service.check_setup(service)
    end

    test "returns :ok after setup", %{service: service} do
      assert {:ok, _} = Gno.Service.Setup.setup(service)
      assert :ok = Service.check_setup(service)
    end
  end

  describe "validate_setup/1" do
    @describetag skip: !fuseki_available?(fuseki_store())

    setup context do
      test_name = context.test |> Atom.to_string() |> String.replace(~r/[^a-zA-Z0-9]/, "-")
      dataset_name = "validate-test-#{test_name}"
      test_store = fuseki_store(dataset_name)
      test_service = alt_service(service(), store: test_store)

      on_exit(fn ->
        Gno.Store.Adapters.Fuseki.teardown(test_store, [])
      end)

      {:ok, service: test_service, store: test_store}
    end

    test "returns error before setup", %{service: service} do
      # Prepare dataset so the query can execute, but don't setup repository
      :ok = Gno.Store.Adapters.Fuseki.setup(service.store, [])
      assert {:error, :invalid_repository_structure} = Service.validate_setup(service)
    end

    test "returns :ok after setup", %{service: service} do
      assert {:ok, _} = Gno.Service.Setup.setup(service)
      assert :ok = Service.validate_setup(service)
    end
  end

  describe "fetch_repository/2" do
    @describetag skip: !fuseki_available?(fuseki_store())

    setup context do
      test_name = context.test |> Atom.to_string() |> String.replace(~r/[^a-zA-Z0-9]/, "-")
      dataset_name = "fetch-repo-test-#{test_name}"
      test_store = fuseki_store(dataset_name)
      test_service = alt_service(service(), store: test_store)

      on_exit(fn ->
        Gno.Store.Adapters.Fuseki.teardown(test_store, [])
      end)

      {:ok, service: test_service, store: test_store}
    end

    test "returns error before setup", %{service: service} do
      # Prepare dataset so the query can execute, but don't setup repository
      :ok = Gno.Store.Adapters.Fuseki.setup(service.store, [])

      assert {:error, %Grax.ValidationError{}} = Service.fetch_repository(service)
    end

    test "fetches complete repository after setup", %{service: service} do
      assert {:ok, _} = Gno.Service.Setup.setup(service)

      assert {:ok, repository} = Service.fetch_repository(service)
      assert repository == service.repository
    end
  end

  describe "fetch_repository_graph/2" do
    @describetag skip: !fuseki_available?(fuseki_store())

    setup context do
      test_name = context.test |> Atom.to_string() |> String.replace(~r/[^a-zA-Z0-9]/, "-")
      dataset_name = "fetch-repo-graph-test-#{test_name}"
      test_store = fuseki_store(dataset_name)
      test_service = alt_service(service(), store: test_store)

      on_exit(fn ->
        Gno.Store.Adapters.Fuseki.teardown(test_store, [])
      end)

      {:ok, service: test_service, store: test_store}
    end

    test "returns empty graph before setup", %{service: service} do
      :ok = Gno.Store.Adapters.Fuseki.setup(service.store)

      assert {:ok, graph} = Service.fetch_repository_graph(service)

      assert RDF.Graph.triple_count(graph) == 0
    end

    test "returns populated graph after setup", %{service: service} do
      assert {:ok, _} = Gno.Service.Setup.setup(service)

      assert {:ok, graph} = Service.fetch_repository_graph(service)

      assert RDF.Graph.triple_count(graph) > 0
      assert RDF.Graph.describes?(graph, service.repository.__id__)
      assert RDF.Graph.describes?(graph, service.repository.dataset.__id__)
    end
  end
end
