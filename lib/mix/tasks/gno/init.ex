defmodule Mix.Tasks.Gno.Init do
  use Mix.Task

  alias Gno.Manifest.GeneratorError

  @shortdoc "Initializes a Gno manifest"

  @switches [
    adapter: :string,
    template: :string,
    force: :boolean
  ]

  def run(args) do
    {opts, assigns} = OptionParser.parse!(args, strict: @switches)
    opts = Keyword.put(opts, :assigns, assigns)
    project_dir = File.cwd!()

    case Gno.manifest_type().generate(project_dir, opts) do
      :ok -> Mix.shell().info("Initialized Gno manifest successfully")
      {:error, %GeneratorError{message: message}} -> Mix.raise(message)
      {:error, error} -> Mix.raise("Failed to initialize manifest: #{inspect(error)}")
    end
  end
end
