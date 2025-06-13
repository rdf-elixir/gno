defmodule Gno.Service.SetupTest do
  use Gno.StoreCase, async: true

  doctest Gno.Service.Setup

  alias Gno.Service
  alias Gno.Service.{Setup, SetupError}
  alias Gno.Store.Adapters.Fuseki

  import Gno.TestFactories

  @moduletag skip: !fuseki_available?(fuseki_store())

  setup context do
    # Use a unique isolated dataset for each test
    test_name = context.test |> Atom.to_string() |> String.replace(~r/[^a-zA-Z0-9]/, "-")
    dataset_name = "setup-test-#{test_name}"
    test_store = fuseki_store(dataset_name)
    test_service = alt_service(service(), store: test_store)

    on_exit(fn ->
      Gno.Store.Adapters.Fuseki.teardown(test_store, [])
    end)

    {:ok, service: test_service, store: test_store}
  end

  describe "Setup.setup/2" do
    test "successfully sets up a new repository", %{service: service} do
      assert {:ok, service} = Setup.setup(service)

      assert repository_exists?(service)
    end

    test "fails if repository already exists", %{service: service} do
      assert {:ok, _} = Setup.setup(service)

      assert {:error, %SetupError{reason: :already_setup}} =
               Setup.setup(service)
    end

    test "skips repository metadata storage when configured", %{service: service} do
      assert {:ok, service} = Setup.setup(service, store_repository_metadata: false)

      refute repository_exists?(service)
    end

    test "runs extension with setup and validation", %{service: service} do
      defmodule CompleteTestExtension do
        use Gno.Service.Setup.Extension

        def setup(service, opts) do
          extension_data = Keyword.get(opts, :extension_data, "default_value")

          extension_graph =
            RDF.graph([
              {service.repository.__id__, ~I<http://example.com/extensionData>, extension_data}
            ])

          case Gno.insert_data(extension_graph, service: service, graph: :repo) do
            :ok -> {:ok, service}
            {:error, reason} -> {:error, reason}
          end
        end
      end

      assert {:ok, _} =
               Setup.setup(service,
                 extension: CompleteTestExtension,
                 extension_opts: [extension_data: "test_value"]
               )

      assert Gno.ask!(
               """
               ASK {
                 <#{service.repository.__id__}> <http://example.com/extensionData> "test_value" .
               }
               """,
               service: service,
               graph: :repo
             )

      assert :ok = Setup.validate(service, extension: CompleteTestExtension)
    end

    test "extension validation can fail on missing data", %{service: service} do
      defmodule ValidationTestExtension do
        use Gno.Service.Setup.Extension

        def validate(_service, _opts \\ []), do: {:error, :test_fail}
      end

      assert {:error, %Gno.Service.SetupError{reason: {:integrity_validation, :test_fail}}} =
               Setup.setup(service, extension: ValidationTestExtension)
    end
  end

  describe "Setup.teardown/2" do
    test "successfully tears down an existing repository", %{service: service} do
      assert {:ok, _} = Setup.setup(service)
      assert repository_exists?(service)

      assert :ok = Setup.teardown(service)
      assert {:error, {:query_failed, _}} = Service.check_setup(service)
    end

    test "fails when repository does not exist", %{service: service} do
      assert {:error, :not_setup} = Setup.teardown(service)
    end

    test "skips repository metadata removal when configured", %{service: service} do
      assert {:ok, _} = Setup.setup(service, store_repository_metadata: false)
      refute repository_exists?(service)
      assert :ok = Setup.teardown(service, store_repository_metadata: false)
      assert {:error, {:query_failed, _}} = Service.check_setup(service)
    end

    @tag :tmp_dir
    test "runs extension teardown with side effects", %{service: service, tmp_dir: tmp_dir} do
      test_file = Path.join(tmp_dir, "teardown_test")

      on_exit(fn ->
        if File.exists?(test_file), do: File.rm(test_file)
      end)

      defmodule FileTeardownExtension do
        use Gno.Service.Setup.Extension

        def setup(service, opts) do
          test_file = Keyword.get(opts, :test_file)
          File.write!(test_file, "extension_was_setup")
          {:ok, service}
        end

        def teardown(_service, opts) do
          test_file = Keyword.get(opts, :test_file)
          File.rm(test_file)
          :ok
        end
      end

      opts = [extension: FileTeardownExtension, extension_opts: [test_file: test_file]]
      assert {:ok, _} = Setup.setup(service, opts)
      assert File.exists?(test_file)

      assert :ok = Setup.teardown(service, opts)
      refute File.exists?(test_file)
    end

    test "handles extension teardown failures gracefully", %{service: service} do
      defmodule FailingTeardownExtension do
        use Gno.Service.Setup.Extension

        def setup(service, _opts), do: {:ok, service}
        def teardown(_service, _opts), do: {:error, :teardown_failed}
      end

      assert {:ok, _} = Setup.setup(service, extension: FailingTeardownExtension)
      assert repository_exists?(service)

      assert {:error, [{:extension_teardown, :teardown_failed}]} =
               Setup.teardown(service, extension: FailingTeardownExtension)

      assert {:error, {:query_failed, _}} = Service.check_setup(service)
    end
  end

  describe "Setup.check/2" do
    test "returns store unavailable error when dataset doesn't exist", %{service: service} do
      # Don't setup dataset - this should fail with store unavailable error
      assert {:error, %Gno.Store.UnavailableError{reason: :dataset_not_found}} =
               Setup.check(service)
    end

    test "returns :repository_not_found when dataset exists but repository not setup", %{
      service: service
    } do
      # Prepare dataset so query can execute, but don't setup repository
      :ok = Fuseki.setup(service.store, [])
      assert {:error, :repository_not_found} = Setup.check(service)
    end

    test "returns :ok after setup", %{service: service} do
      assert {:ok, _} = Setup.setup(service)
      assert :ok = Setup.check(service)
    end

    test "returns error from extension check_setup", %{service: service} do
      defmodule FailingCheckExtension do
        use Gno.Service.Setup.Extension

        @impl true
        def check_setup(_service, _opts), do: {:error, :extension_check_failed}
      end

      :ok = Fuseki.setup(service.store, [])

      assert {:error, :extension_check_failed} =
               Setup.check(service, extension: FailingCheckExtension)
    end
  end

  describe "Setup.validate/2" do
    test "returns error before setup", %{service: service} do
      # Prepare dataset so query can execute, but don't setup repository
      :ok = Fuseki.setup(service.store, [])
      assert {:error, :invalid_repository_structure} = Setup.validate(service)
    end

    test "returns :ok after setup", %{service: service} do
      assert {:ok, _} = Setup.setup(service)
      assert :ok = Setup.validate(service)
    end

    test "calls extension validate callback", %{service: service} do
      defmodule TestExtension do
        use Gno.Service.Setup.Extension
      end

      assert {:ok, _} = Setup.setup(service, extension: TestExtension)
      assert :ok = Setup.validate(service, extension: TestExtension)
    end

    test "returns error from extension validate", %{service: service} do
      defmodule FailingTestExtension do
        use Gno.Service.Setup.Extension

        @impl true
        def validate(_service, _opts \\ []), do: {:error, :extension_validation_failed}
      end

      # First prepare the store so the test gets to the extension validation step
      :ok = Fuseki.setup(service.store)

      # Setup should fail during validation phase
      assert {:error,
              %Gno.Service.SetupError{
                reason: {:integrity_validation, :extension_validation_failed}
              }} =
               Setup.setup(service, extension: FailingTestExtension)

      # Setup a working repository first to test extension validation in isolation
      working_store = fuseki_store("working-validation-test")
      working_service = alt_service(service(), store: working_store)

      # Cleanup working service
      on_exit(fn ->
        Fuseki.teardown(working_store)
      end)

      assert {:ok, _} = Setup.setup(working_service)

      # Now test extension validation on working repository
      assert {:error, :extension_validation_failed} =
               Setup.validate(working_service, extension: FailingTestExtension)
    end
  end

  describe "Fuseki.setup/2" do
    test "creates dataset successfully", %{store: store} do
      refute dataset_exists?(store)

      assert :ok = Fuseki.setup(store)
      assert dataset_exists?(store)
    end

    test "works with custom db_type option", %{store: store} do
      assert :ok = Fuseki.setup(store, db_type: "tdb")
      assert dataset_exists?(store)
    end

    test "handles already existing dataset depending on on_existing_dataset option", %{
      store: store
    } do
      assert :ok = Fuseki.setup(store)
      assert dataset_exists?(store)

      assert {:error, _error} = Fuseki.setup(store, on_existing_dataset: :error)

      assert_raise RuntimeError, fn ->
        Fuseki.setup(store, on_existing_dataset: :raise)
      end

      assert :ok = Fuseki.setup(store)

      assert dataset_exists?(store)
    end
  end

  describe "Fuseki.teardown/2" do
    test "deletes dataset successfully", %{store: store} do
      assert :ok = Fuseki.setup(store)
      assert dataset_exists?(store)

      assert :ok = Fuseki.teardown(store, [])
      refute dataset_exists?(store)
    end

    test "handles non-existing dataset gracefully", %{store: store} do
      refute dataset_exists?(store)
      assert :ok = Fuseki.teardown(store, [])
      refute dataset_exists?(store)
    end
  end

  defp repository_exists?(service) do
    case Service.check_setup(service) do
      :ok -> true
      {:error, :repository_not_found} -> false
      {:error, reason} -> raise "Failed to check repository existence: #{inspect(reason)}"
    end
  end

  defp dataset_exists?(store) do
    case Fuseki.dataset_info(store) do
      {:ok, nil} -> false
      {:ok, _} -> true
      {:error, reason} -> raise "Failed to check dataset existence: #{inspect(reason)}"
    end
  end
end
