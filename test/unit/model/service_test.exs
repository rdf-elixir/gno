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
    test "default graph (via: nil)" do
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

    test "default graph (via: :default)" do
      assert EX.S
             |> EX.p(EX.O)
             |> RDF.graph()
             |> Operation.insert_data!()
             |> Service.handle_sparql(Manifest.service!(), graph: :default) ==
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
               |> Service.handle_sparql(Manifest.service!(), graph: :default)

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
             |> Service.handle_sparql(Manifest.service!(), graph: EX.Graph2) ==
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
               |> Service.handle_sparql(Manifest.service!(), graph: EX.Graph2)

      graph =
        EX.S2
        |> EX.p(EX.O2)
        |> RDF.graph()

      assert graph
             |> Operation.insert_data!()
             |> Service.handle_sparql(Manifest.service!(), graph: :repo_manifest) ==
               :ok

      assert {:ok, result} =
               "CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o . }"
               |> Operation.construct!()
               |> Service.handle_sparql(Manifest.service!(), graph: :repo_manifest)

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

    test "returns :ok after setup (multi-graph)", %{service: service} do
      assert {:ok, _} = Gno.Service.Setup.setup(service)
      assert :ok = Service.check_setup(service)
    end

    test "returns :ok after setup (single-graph)", %{store: store} do
      single_graph_service = single_graph_service(service(), store: store)
      assert {:ok, _} = Gno.Service.Setup.setup(single_graph_service)
      assert :ok = Service.check_setup(single_graph_service)
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

    test "returns :ok after setup (multi-graph)", %{service: service} do
      assert {:ok, _} = Gno.Service.Setup.setup(service)
      assert :ok = Service.validate_setup(service)
    end

    test "returns :ok after setup (single-graph)", %{store: store} do
      single_graph_service = single_graph_service(service(), store: store)
      assert {:ok, _} = Gno.Service.Setup.setup(single_graph_service)
      assert :ok = Service.validate_setup(single_graph_service)
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

  describe "graph_name/3" do
    test "resolves selectors" do
      assert Gno.Service.graph_name(Gno.service!(), :primary) == RDF.iri(EX.Graph)
      assert Gno.Service.graph_name(Gno.service!(), :default) == :default
      assert Gno.Service.graph_name(Gno.service!(), :all) == :all

      assert Gno.Service.graph_name(Gno.service!(), :repo_manifest) ==
               RDF.iri(EX.RepositoryManifestGraph)
    end

    test "resolves graph IRI directly" do
      graph_iri = RDF.iri(EX.Graph3)
      assert Gno.Service.graph_name(Gno.service!(), graph_iri) == graph_iri
    end

    test "resolves graph by string IRI" do
      graph_iri_string = "http://example.com/Graph3"
      assert Gno.Service.graph_name(Gno.service!(), graph_iri_string) == RDF.iri(graph_iri_string)
    end
  end

  test "default_graph/1" do
    assert %DCATR.DataGraph{} = default_graph = Gno.Service.default_graph(Gno.service!())
    assert default_graph.__id__ == RDF.iri(EX.Graph2)
  end

  test "primary_graph/1" do
    assert %DCATR.DataGraph{} = primary_graph = Gno.Service.primary_graph(Gno.service!())
    assert primary_graph.__id__ == RDF.iri(EX.Graph)
  end
end
