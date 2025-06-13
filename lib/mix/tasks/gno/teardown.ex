defmodule Mix.Tasks.Gno.Teardown do
  use Mix.Task

  @shortdoc "Remove the Gno repository from the configured store"

  @requirements ["app.start"]

  def run(_args) do
    case Gno.service() do
      {:ok, service} ->
        case Gno.Service.Setup.teardown(service) do
          :ok -> Mix.Shell.IO.info("Gno repository torn down")
          {:error, errors} -> Mix.raise("teardown failed: #{inspect(errors)}")
        end

      {:error, error} ->
        Mix.raise("failed to load manifest: #{inspect(error)}")
    end
  end
end
