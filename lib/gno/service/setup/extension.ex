defmodule Gno.Service.Setup.Extension do
  @moduledoc """
  Behavior for `Gno.Service.Setup` extensions with custom setup logic.
  """

  alias Gno.Service

  @doc """
  Performs extension-specific initialization during setup.

  Called after the repository has been initialized but before validation.
  The extension can perform any additional setup steps needed, such as:

  - Creating application-specific graphs
  - Setting up initial data structures
  - Configuring external systems

  Returns the service (potentially modified) on success.
  """
  @callback setup(Service.t(), keyword()) :: {:ok, Service.t()} | {:error, term()}

  @doc """
  Checks if the service's repository is set up, i.e. exists.

  Called during setup to verify if the repository already exists and is accessible.
  Implementations should implement a minimal check to verify the repository exists.
  More detailed validation should be done in the `validate/2` callback.
  """
  @callback check_setup(Service.t(), keyword()) :: :ok | {:error, term()}

  @doc """
  Validates the setup state after all initialization is complete.

  Called as the final step of setup to ensure everything is properly configured.
  Should check that all required components are in place and properly initialized.
  """
  @callback validate(Service.t(), keyword()) :: :ok | {:error, term()}

  @doc """
  Performs extension-specific teardown.
  """
  @callback teardown(Service.t(), keyword()) :: :ok | {:error, term()}

  @doc """
  Provides default implementations of the setup extension callbacks.

  ## Examples

      defmodule MyApp.Setup do
        use Gno.Service.Setup.Extension

        @impl true
        def setup(service, opts) do
          # Custom setup logic here
          {:ok, service}
        end
      end
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Gno.Service.Setup.Extension

      @impl true
      def setup(service, _opts), do: {:ok, service}

      @impl true
      def check_setup(service, _opts), do: Gno.Service.check_setup(service)

      @impl true
      def validate(service, _opts), do: Gno.Service.validate_setup(service)

      @impl true
      def teardown(_service, _opts), do: :ok

      defoverridable setup: 2, check_setup: 2, validate: 2, teardown: 2
    end
  end
end
