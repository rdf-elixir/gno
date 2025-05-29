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

  describe "handle/4" do
    test "default graph" do
      assert EX.S
             |> EX.p(EX.O)
             |> RDF.graph()
             |> Operation.insert_data!()
             |> Service.handle_sparql(Manifest.service!(), nil) ==
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
               |> Service.handle_sparql(Manifest.service!(), nil)
    end

    test "named graph" do
      assert EX.S
             |> EX.p(EX.O)
             |> RDF.graph()
             |> Operation.insert_data!()
             |> Service.handle_sparql(Manifest.service!(), :dataset) ==
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
               |> Service.handle_sparql(Manifest.service!(), :dataset)

      graph =
        EX.S2
        |> EX.p(EX.O2)
        |> RDF.graph()

      assert graph
             |> Operation.insert_data!()
             |> Service.handle_sparql(Manifest.service!(), :repo) ==
               :ok

      assert {:ok, result} =
               "CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o . }"
               |> Operation.construct!()
               |> Service.handle_sparql(Manifest.service!(), :repo)

      # some triple stores (like Fuseki) add all known prefixes
      assert Graph.clear_prefixes(result) == graph
    end
  end
end
