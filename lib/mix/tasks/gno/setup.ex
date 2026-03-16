defmodule Mix.Tasks.Gno.Setup do
  @moduledoc """
  Installs the Gno repository on the configured store.

      $ mix gno.setup

  ## Options

  - `--no-store-repository-metadata` - skip storing repository metadata
  - `--on-existing-dataset` - strategy for existing datasets
  - `--db-type` - database type for store setup
  """

  use Mix.Task

  @shortdoc "Install the Gno repository on the configured store"

  @requirements ["app.start"]

  @switches [
    no_store_repository_metadata: :boolean,
    on_existing_dataset: :string,
    db_type: :string
  ]

  def run(args) do
    {opts, _args} = OptionParser.parse!(args, switches: @switches)
    setup_opts = build_setup_opts(opts)

    case Gno.setup(setup_opts) do
      {:ok, _service} -> Mix.Shell.IO.info("Set up Gno repository")
      {:error, %{__exception__: true} = e} -> Mix.raise("setup failed: #{Exception.message(e)}")
      {:error, error} -> Mix.raise("setup failed: #{inspect(error)}")
    end
  end

  defp build_setup_opts(parsed_opts) do
    store_options =
      []
      |> then(fn store_opts ->
        if on_existing_dataset = parsed_opts[:on_existing_dataset] do
          Keyword.put(store_opts, :on_existing_dataset, on_existing_dataset)
        else
          store_opts
        end
      end)
      |> then(fn store_opts ->
        if db_type = parsed_opts[:db_type] do
          Keyword.put(store_opts, :db_type, db_type)
        else
          store_opts
        end
      end)

    if parsed_opts[:no_store_repository_metadata] do
      [store_repository_metadata: false]
    else
      []
    end
    |> Keyword.put(:store_options, store_options)
  end
end
