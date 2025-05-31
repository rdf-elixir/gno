defmodule Gno.Commit.ProcessorTest do
  use Gno.StoreCase, async: false

  doctest Gno.Commit.Processor

  alias Gno.Commit.{Processor, ProcessorError, ProcessorRollbackError}
  alias Gno.{Commit, EffectiveChangeset}

  import ExUnit.CaptureLog

  describe "new/1" do
    test "creates a new processor with the given service" do
      service = Manifest.service!()
      assert {:ok, %Processor{service: ^service}} = Processor.new(service)
    end
  end

  describe "execute/3 (with default CommitOperation)" do
    test "processes a simple add changeset" do
      description = EX.S1 |> EX.p1(EX.O1) |> EX.p2(EX.O2)
      expected_changeset = Gno.EffectiveChangeset.new!(add: description)

      assert {:ok, %Gno.Commit{changeset: ^expected_changeset}, %Processor{state: :completed}} =
               Processor.execute(commit_processor(), add: description)

      assert Gno.QueryUtils.graph_query() |> Gno.execute!() |> Graph.clear_prefixes() ==
               graph(description)
    end

    test "processes an update changeset" do
      Gno.insert_data!(EX.S1 |> EX.p1(EX.O1) |> EX.p2(EX.O2))

      update_description = EX.S1 |> EX.p1(EX.O1) |> EX.p2("updated value")

      expected_changeset =
        Gno.EffectiveChangeset.new!(
          update: EX.S1 |> EX.p2("updated value"),
          overwrite: EX.S1 |> EX.p2(EX.O2)
        )

      assert {:ok, %Gno.Commit{changeset: result_changeset}, %Processor{}} =
               Processor.execute(commit_processor(), update: update_description)

      assert without_prefixes(result_changeset) == expected_changeset

      expected_result = graph(EX.S1 |> EX.p1(EX.O1) |> EX.p2("updated value"))

      assert Gno.QueryUtils.graph_query() |> Gno.execute!() |> Graph.clear_prefixes() ==
               expected_result
    end

    test "processes a remove changeset" do
      Gno.insert_data!(EX.S1 |> EX.p1(EX.O1) |> EX.p2(EX.O2))

      remove_description = EX.S1 |> EX.p2(EX.O2)
      expected_changeset = Gno.EffectiveChangeset.new!(remove: remove_description)

      assert {:ok, %Gno.Commit{changeset: result_changeset}, %Processor{}} =
               Processor.execute(commit_processor(), remove: remove_description)

      assert without_prefixes(result_changeset) == expected_changeset

      expected_result = graph(EX.S1 |> EX.p1(EX.O1))

      assert Gno.QueryUtils.graph_query() |> Gno.execute!() |> Graph.clear_prefixes() ==
               expected_result
    end
  end

  test "execute/3 with custom CommitOperation" do
    service = %{Manifest.service!() | commit_operation: TestCommitOperation.build!(RDF.bnode())}
    processor = Processor.new!(service)
    description = EX.S1 |> EX.p1(EX.O1)

    assert {:ok, %Commit{} = commit, %Processor{} = processor} =
             Processor.execute(processor, add: description)

    assert commit.changeset == EffectiveChangeset.new!(add: description)
    assert commit.time == TestCommitOperation.test_time()

    assert processor.state == :completed
    assert processor.assigns[:custom_init]

    assert Graph.include?(
             processor.metadata,
             {TestCommitOperation.commit_id(processor), EX.customMetadata(), "test"}
           )
  end

  describe "execute/3 handling of NoEffectiveChanges" do
    test ":error handling" do
      Gno.insert_data!(graph())

      assert {:error, %Gno.NoEffectiveChanges{}} =
               Processor.execute(commit_processor(), add: graph())
    end

    test ":skip handling" do
      Gno.insert_data!(graph())

      assert {:ok, %Gno.NoEffectiveChanges{}, %Processor{state: :completed}} =
               Processor.execute(commit_processor(on_no_effective_changes: "skip"), add: graph())
    end

    test ":proceed handling" do
      Gno.insert_data!(graph())

      assert {:ok, %Commit{changeset: %Gno.EffectiveChangeset{} = changeset},
              %Processor{state: :completed}} =
               Processor.execute(commit_processor(on_no_effective_changes: "proceed"),
                 add: graph()
               )

      assert EffectiveChangeset.empty?(changeset)
    end

    test "overwriting with opts" do
      Gno.insert_data!(graph())

      assert {:ok, %Commit{changeset: %Gno.EffectiveChangeset{}}, %Processor{state: :completed}} =
               Processor.execute(
                 commit_processor(),
                 [add: graph()],
                 on_no_effective_changes: "proceed"
               )
    end
  end

  describe "state flow with TestStateFlowMiddleware" do
    test "records state transitions for add operation" do
      processor = test_commit_processor(middlewares: [TestStateFlowMiddleware.new!("test")])
      description = EX.S1 |> EX.p1(EX.O1)

      assert {:ok, _commit, processor} = Processor.execute(processor, add: description)

      assert_rdf_isomorphic TestStateFlowMiddleware.state_flow_list(processor).graph,
                            RDF.List.from([
                              "completed-test-mw_state:executing_post_commit",
                              "executing_post_commit-test-mw_state:transaction_ended",
                              "transaction_ended-test-mw_state:ending_transaction",
                              "ending_transaction-test-mw_state:changes_applied",
                              "changes_applied-test-mw_state:applying_changes",
                              "applying_changes-test-mw_state:transaction_started",
                              "transaction_started-test-mw_state:starting_transaction",
                              "starting_transaction-test-mw_state:prepared",
                              "prepared-test-mw_state:preparing",
                              "preparing-test-mw_state:initialized",
                              "initialized-test-mw_state:initializing",
                              "initializing-test-mw_state:"
                            ]).graph

      assert processor.state == :completed

      assert Gno.QueryUtils.graph_query() |> Gno.execute!() |> Graph.clear_prefixes() ==
               graph(description)
    end

    test "handles multiple middlewares in order" do
      processor =
        test_commit_processor(
          middlewares: [
            TestStateFlowMiddleware.new!("first"),
            Gno.CommitLogger.new!(),
            TestStateFlowMiddleware.new!("second")
          ]
        )

      description = EX.S1 |> EX.p1(EX.O1)

      {processor, log} =
        with_log(fn ->
          assert {:ok, _commit, processor} = Processor.execute(processor, add: description)
          processor
        end)

      assert log =~ "Commit operation completed successfully"

      assert_rdf_isomorphic TestStateFlowMiddleware.state_flow_list(processor).graph,
                            RDF.List.from([
                              "completed-second-mw_state:executing_post_commit",
                              "completed-first-mw_state:executing_post_commit",
                              "executing_post_commit-second-mw_state:transaction_ended",
                              "executing_post_commit-first-mw_state:transaction_ended",
                              "transaction_ended-second-mw_state:ending_transaction",
                              "transaction_ended-first-mw_state:ending_transaction",
                              "ending_transaction-second-mw_state:changes_applied",
                              "ending_transaction-first-mw_state:changes_applied",
                              "changes_applied-second-mw_state:applying_changes",
                              "changes_applied-first-mw_state:applying_changes",
                              "applying_changes-second-mw_state:transaction_started",
                              "applying_changes-first-mw_state:transaction_started",
                              "transaction_started-second-mw_state:starting_transaction",
                              "transaction_started-first-mw_state:starting_transaction",
                              "starting_transaction-second-mw_state:prepared",
                              "starting_transaction-first-mw_state:prepared",
                              "prepared-second-mw_state:preparing",
                              "prepared-first-mw_state:preparing",
                              "preparing-second-mw_state:initialized",
                              "preparing-first-mw_state:initialized",
                              "initialized-second-mw_state:initializing",
                              "initialized-first-mw_state:initializing",
                              "initializing-second-mw_state:",
                              "initializing-first-mw_state:"
                            ]).graph

      assert processor.state == :completed

      assert Gno.QueryUtils.graph_query() |> Gno.execute!() |> Graph.clear_prefixes() ==
               graph(description)
    end

    test "handles rollback on error" do
      processor =
        test_commit_processor(
          middlewares: [TestStateFlowMiddleware.new!("test", fail_on_state: :preparing)]
        )

      description = EX.S1 |> EX.p1(EX.O1)

      assert {:error, %ProcessorError{processor: result}} =
               Processor.execute(processor, add: description)

      assert_rdf_isomorphic TestStateFlowMiddleware.state_flow_list(result).graph,
                            RDF.List.from([
                              "rollback-initialized-test-mw_state:initialized",
                              "initialized-test-mw_state:initializing",
                              "initializing-test-mw_state:"
                            ]).graph

      assert result.state == {:rolled_back, :initialized}
      assert result.errors == ["Failed on state preparing"]
      assert Gno.execute!(Gno.QueryUtils.graph_query()) == empty_graph()
    end

    test "handles exception in middleware" do
      processor =
        test_commit_processor(
          middlewares: [
            TestStateFlowMiddleware.new!("test",
              fail_on_state: :preparing,
              fail_type: :exception
            )
          ]
        )

      description = EX.S1 |> EX.p1(EX.O1)

      assert {:error, %ProcessorError{processor: result}} =
               Processor.execute(processor, add: description)

      assert_rdf_isomorphic TestStateFlowMiddleware.state_flow_list(result).graph,
                            RDF.List.from([
                              "rollback-initialized-test-mw_state:initialized",
                              "initialized-test-mw_state:initializing",
                              "initializing-test-mw_state:"
                            ]).graph

      assert result.state == {:rolled_back, :initialized}
      assert result.errors == [%RuntimeError{message: "Failed on state preparing"}]
      assert Gno.execute!(Gno.QueryUtils.graph_query()) == empty_graph()
    end

    test "handles error in post-commit phase (no rollback)" do
      processor =
        test_commit_processor(
          middlewares: [
            TestStateFlowMiddleware.new!("test", fail_on_state: :executing_post_commit)
          ]
        )

      description = EX.S1 |> EX.p1(EX.O1)

      assert {:error, %ProcessorError{processor: result}} =
               Processor.execute(processor, add: description)

      assert_rdf_isomorphic TestStateFlowMiddleware.state_flow_list(result).graph,
                            RDF.List.from([
                              "transaction_ended-test-mw_state:ending_transaction",
                              "ending_transaction-test-mw_state:changes_applied",
                              "changes_applied-test-mw_state:applying_changes",
                              "applying_changes-test-mw_state:transaction_started",
                              "transaction_started-test-mw_state:starting_transaction",
                              "starting_transaction-test-mw_state:prepared",
                              "prepared-test-mw_state:preparing",
                              "preparing-test-mw_state:initialized",
                              "initialized-test-mw_state:initializing",
                              "initializing-test-mw_state:"
                            ]).graph

      assert result.state == :transaction_ended
      assert result.errors == ["Failed on state executing_post_commit"]

      assert Gno.QueryUtils.graph_query() |> Gno.execute!() |> Graph.clear_prefixes() ==
               graph(description)
    end

    test "handles error during transaction phase" do
      processor =
        test_commit_processor(
          middlewares: [
            TestStateFlowMiddleware.new!("test", fail_on_state: :ending_transaction)
          ]
        )

      description = EX.S1 |> EX.p1(EX.O1)

      assert {:error, %ProcessorError{processor: result}} =
               Processor.execute(processor, add: description)

      assert_rdf_isomorphic TestStateFlowMiddleware.state_flow_list(result).graph,
                            RDF.List.from([
                              "rollback-changes_applied-test-mw_state:changes_applied",
                              "changes_applied-test-mw_state:applying_changes",
                              "applying_changes-test-mw_state:transaction_started",
                              "transaction_started-test-mw_state:starting_transaction",
                              "starting_transaction-test-mw_state:prepared",
                              "prepared-test-mw_state:preparing",
                              "preparing-test-mw_state:initialized",
                              "initialized-test-mw_state:initializing",
                              "initializing-test-mw_state:"
                            ]).graph

      assert result.state == {:rolled_back, :changes_applied}
      assert result.errors == ["Failed on state ending_transaction"]
      assert Gno.execute!(Gno.QueryUtils.graph_query()) == empty_graph()
    end

    test "handles rollback with middlewares in different states" do
      processor =
        test_commit_processor(
          middlewares: [
            TestStateFlowMiddleware.new!("first"),
            TestStateFlowMiddleware.new!("second", fail_on_state: :prepared),
            TestStateFlowMiddleware.new!("third")
          ]
        )

      description = EX.S1 |> EX.p1(EX.O1)

      assert {:error, %ProcessorError{processor: result}} =
               Processor.execute(processor, add: description)

      assert_rdf_isomorphic TestStateFlowMiddleware.state_flow_list(result).graph,
                            RDF.List.from([
                              "rollback-preparing-third-mw_state:preparing",
                              "rollback-preparing-second-mw_state:preparing",
                              "rollback-preparing-first-mw_state:prepared",
                              "prepared-first-mw_state:preparing",
                              "preparing-third-mw_state:initialized",
                              "preparing-second-mw_state:initialized",
                              "preparing-first-mw_state:initialized",
                              "initialized-third-mw_state:initializing",
                              "initialized-second-mw_state:initializing",
                              "initialized-first-mw_state:initializing",
                              "initializing-third-mw_state:",
                              "initializing-second-mw_state:",
                              "initializing-first-mw_state:"
                            ]).graph
    end

    test "handles error during rollback" do
      processor =
        test_commit_processor(
          middlewares: [
            TestStateFlowMiddleware.new!("test", fail_on_state: {:rollback, :changes_applied})
          ]
        )

      description = EX.S1 |> EX.p1(EX.O1)

      assert {:error,
              %ProcessorRollbackError{
                processor: result,
                error: "Failed on state rollback of applying_changes"
              }} =
               Processor.execute(processor, add: description)

      assert result.state == {:rollback, :applying_changes}
      assert result.errors == ["Failed on state changes_applied"]
    end

    test "handles rollback in all middlewares even if one fails" do
      processor =
        test_commit_processor(
          middlewares: [
            TestStateFlowMiddleware.new!("first",
              fail_on_state: {:rollback, :preparing},
              fail_type: :exception
            ),
            TestStateFlowMiddleware.new!("second", fail_on_state: {:rollback, :preparing}),
            TestStateFlowMiddleware.new!("third")
          ]
        )

      description = EX.S1 |> EX.p1(EX.O1)

      assert {:error,
              %ProcessorRollbackError{
                processor: result,
                error: [
                  "Failed on state rollback of initialized",
                  %RuntimeError{message: "Failed on state rollback of initialized"}
                ]
              }} =
               Processor.execute(processor, add: description)

      assert_rdf_isomorphic TestStateFlowMiddleware.state_flow_list(result).graph,
                            RDF.List.from([
                              "rollback-initialized-third-mw_state:initialized",
                              "initialized-third-mw_state:initializing",
                              "initialized-second-mw_state:initializing",
                              "initialized-first-mw_state:initializing",
                              "initializing-third-mw_state:",
                              "initializing-second-mw_state:",
                              "initializing-first-mw_state:"
                            ]).graph

      assert result.state == {:rollback, :initialized}
      assert result.errors == [%RuntimeError{message: "Failed on state preparing"}]
    end
  end

  describe "update_commit_id/2" do
    test "updates the commit id and renames the commit id in the metadata" do
      processor = %{commit_processor() | commit_id: RDF.iri(EX.initialCommitId())}

      {:ok, processor} =
        Processor.update_metadata(processor, fn metadata ->
          Graph.add(metadata, [
            {Processor.commit_id(processor), EX.test(), "test"},
            {EX.S, EX.test(), Processor.commit_id(processor)}
          ])
        end)

      new_commit_id = RDF.iri(EX.finalCommitId())

      assert %Processor{commit_id: ^new_commit_id} =
               processor =
               Processor.update_commit_id(processor, new_commit_id)

      assert Graph.include?(processor.metadata, [
               {new_commit_id, EX.test(), "test"},
               {EX.S, EX.test(), new_commit_id}
             ])
    end
  end

  describe "update_metadata/2" do
    test "with a graph" do
      metadata = Graph.new({EX.S, EX.p(), EX.O})

      assert {:ok, %Processor{metadata: ^metadata}} =
               Processor.update_metadata(commit_processor(), metadata)
    end

    test "with a function" do
      update_fn = fn graph -> Graph.add(graph, {EX.S, EX.p(), EX.O}) end
      expected = Graph.new({EX.S, EX.p(), EX.O})

      assert {:ok, %Processor{metadata: ^expected}} =
               Processor.update_metadata(commit_processor(), update_fn)
    end

    test "with a function returning {:ok, graph}" do
      update_fn = fn graph -> {:ok, Graph.add(graph, {EX.S, EX.p(), EX.O})} end
      expected = Graph.new({EX.S, EX.p(), EX.O})

      assert {:ok, %Processor{metadata: ^expected}} =
               Processor.update_metadata(commit_processor(), update_fn)
    end

    test "with a function returning error" do
      update_fn = fn _graph -> {:error, "test error"} end

      assert {:error, "test error"} = Processor.update_metadata(commit_processor(), update_fn)
    end
  end

  describe "assign/3" do
    test "adds a value to the assigns map" do
      updated = Processor.assign(commit_processor(), :test_key, "test_value")
      assert updated.assigns.test_key == "test_value"
    end
  end
end
