defmodule Gno.CommitLoggerTest do
  use Gno.StoreCase, async: false

  doctest Gno.CommitLogger

  alias Gno.Commit.{Processor, ProcessorError}
  alias Gno.CommitLogger
  import ExUnit.CaptureLog

  describe "new/1" do
    test "creates a new logger middleware with default options" do
      assert {:ok, %CommitLogger{log_level: "info"}} = CommitLogger.new()
    end

    test "creates a new logger middleware with custom options" do
      assert {:ok, %CommitLogger{log_level: "debug", log_changes: true}} =
               CommitLogger.new(log_level: "debug", log_changes: true)
    end
  end

  describe "handle_state/3" do
    setup do
      %{processor: Processor.new!(Manifest.service!())}
    end

    test "logs initializing state", %{processor: processor} do
      middleware = CommitLogger.new!(log_states: ["initializing"])

      log =
        capture_log(fn ->
          assert {:ok, _} = CommitLogger.handle_state(:initializing, middleware, processor)
        end)

      assert log =~ "Commit operation started"
    end

    test "logs completed state", %{processor: processor} do
      middleware = CommitLogger.new!(log_states: ["completed"])

      log =
        capture_log(fn ->
          assert {:ok, _} = CommitLogger.handle_state(:completed, middleware, processor)
        end)

      assert log =~ "Commit operation completed successfully"
    end

    test "logs completed state with changeset details", %{processor: processor} do
      middleware =
        CommitLogger.new!(log_states: ["completed"], log_changes: true, log_level: "debug")

      changeset = Gno.EffectiveChangeset.new!(add: EX.S1 |> EX.p1(EX.O1))
      processor = %{processor | effective_changeset: changeset}

      log =
        capture_log(fn ->
          assert {:ok, _} = CommitLogger.handle_state(:prepared, middleware, processor)
        end)

      assert log =~ "[debug]"
      assert log =~ "Changes:"
      assert log =~ "http://example.com/S1"
    end

    test "logs changeset and metadata", %{processor: processor} do
      middleware =
        CommitLogger.new!(log_states: ["prepared"], log_metadata: true, log_level: "debug")

      metadata = RDF.Graph.new({EX.S, EX.p(), EX.O})
      processor = %{processor | metadata: metadata}

      log =
        capture_log(fn ->
          assert {:ok, _} = CommitLogger.handle_state(:prepared, middleware, processor)
        end)

      assert log =~ "[debug]"
      assert log =~ "Metadata:"
      assert log =~ "http://example.com/S"
      assert log =~ "Commit operation prepared"
    end

    test "does not log states not in log_states", %{processor: processor} do
      middleware = CommitLogger.new!(log_states: ["initializing"])

      log =
        capture_log(fn ->
          assert {:ok, _} = CommitLogger.handle_state(:preparing, middleware, processor)
        end)

      assert log == ""
    end

    test "processes log entries from processor", %{processor: processor} do
      middleware = CommitLogger.new!()
      processor = CommitLogger.log(processor, "Test log entry", level: "warning")

      log =
        capture_log(fn ->
          assert {:ok, updated_processor} =
                   CommitLogger.handle_state(:preparing, middleware, processor)

          assert updated_processor.assigns[:log] == []
        end)

      assert log =~ "Test log entry"
    end
  end

  describe "rollback/2" do
    setup do
      %{processor: Processor.new!(Manifest.service!())}
    end

    test "logs rollback operation", %{processor: processor} do
      middleware = CommitLogger.new!()

      log =
        capture_log(fn ->
          assert {:ok, _} = CommitLogger.rollback(middleware, processor)
        end)

      assert log =~ "Rolling back commit operation"
      assert log =~ "[warning]"
    end

    test "processes log entries during rollback", %{processor: processor} do
      middleware = CommitLogger.new!()
      processor = CommitLogger.log(processor, "Test rollback log entry", level: "error")

      log =
        capture_log(fn ->
          assert {:ok, updated_processor} = CommitLogger.rollback(middleware, processor)
          assert updated_processor.assigns[:log] == []
        end)

      assert log =~ "Rolling back commit operation"
      assert log =~ "Test rollback log entry"
    end
  end

  describe "log/3" do
    setup do
      %{processor: Processor.new!(Manifest.service!())}
    end

    test "adds log entry to processor assigns", %{processor: processor} do
      updated_processor = CommitLogger.log(processor, "Test message")

      assert [%{message: "Test message", level: nil, metadata: []} | _] =
               updated_processor.assigns[:log]
    end

    test "adds log entry with custom level", %{processor: processor} do
      metadata = [user: "test"]

      updated_processor =
        CommitLogger.log(processor, "Test message", level: "error", metadata: metadata)

      assert [%{message: "Test message", level: "error", metadata: ^metadata} | _] =
               updated_processor.assigns[:log]
    end

    test "preserves existing log entries", %{processor: processor} do
      processor =
        processor
        |> CommitLogger.log("First message")
        |> CommitLogger.log("Second message")

      assert [%{message: "Second message"}, %{message: "First message"}] = processor.assigns[:log]
    end
  end

  describe "integration with Processor" do
    test "logs commit operation states" do
      processor = commit_processor(middlewares: [CommitLogger.new!(log_states: ["all"])])

      log =
        capture_log(fn ->
          assert {:ok, _} = Processor.execute(processor, add: graph())
        end)

      assert log =~ "Commit operation started"
      assert log =~ "Commit operation prepared"
      assert log =~ "Commit operation completed successfully"
    end

    test "logs error during commit operation" do
      processor =
        commit_processor(
          middlewares: [
            TestStateFlowMiddleware.new!("test", fail_on_state: :preparing),
            CommitLogger.new!(log_states: ["initializing"])
          ]
        )

      log =
        capture_log(fn ->
          assert {:error, %ProcessorError{}} = Processor.execute(processor, add: graph())
        end)

      assert log =~ "Commit operation started"
      assert log =~ "Rolling back commit operation"
    end

    test "logs prepared changeset and metadata when enabled" do
      processor =
        commit_processor(
          middlewares: [
            CommitLogger.new!(
              log_changes: true,
              log_metadata: true,
              log_level: "debug"
            )
          ]
        )

      description = EX.S1 |> EX.p1(EX.O1)

      log =
        capture_log(fn ->
          assert {:ok, _} = Processor.execute(processor, add: description)
        end)

      assert log =~ "Commit operation completed successfully"
      assert log =~ "Changes:"
      assert log =~ "<http://example.com/S1>"
      assert log =~ "Metadata:"
      assert log =~ "prov#endedAtTime"
    end

    test "logs custom messages during commit" do
      processor =
        commit_processor(
          middlewares: [
            TestStateFlowMiddleware.new!("test", custom_log_message: "Custom log message"),
            CommitLogger.new!()
          ]
        )

      log =
        capture_log(fn ->
          assert {:ok, _} = Processor.execute(processor, add: graph())
        end)

      assert log =~ "[info] Custom log message"
      assert log =~ "Commit operation completed successfully"
    end
  end
end
